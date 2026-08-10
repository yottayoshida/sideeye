//! Direct libc bindings for the engine.
//!
//! The engine deliberately does not use `std.Io`. That layer was reworked wholesale in
//! Zig 0.16 — `std.fs` no longer holds `File` or `Dir`, spawning a child goes through a
//! vtable, and more movement is already scheduled for 0.17. Everything sideeye needs
//! from the operating system is plain POSIX: walk a directory, read and write a file,
//! fork, exec, wait. That surface has been stable for decades.
//!
//! The shim reached the same conclusion first, for a different reason (it cannot use a
//! standard library at all inside somebody else's process). Both halves ending up on
//! the same small set of calls is a convenience, not a coincidence.
//!
//! Types come from `std.c`, which is a description of the platform ABI rather than an
//! abstraction over it, so it does not carry the same churn.

const std = @import("std");
const builtin = @import("builtin");

pub const Dirent = std.c.dirent;

pub extern "c" fn opendir(name: [*:0]const u8) ?*anyopaque;
pub extern "c" fn readdir(dirp: *anyopaque) ?*Dirent;
pub extern "c" fn closedir(dirp: *anyopaque) c_int;
pub extern "c" fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
pub extern "c" fn fork() c_int;
pub extern "c" fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
pub extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn _exit(status: c_int) noreturn;
pub extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_CREAT: c_int = if (builtin.os.tag == .linux) 0o100 else 0x200;
pub const O_TRUNC: c_int = if (builtin.os.tag == .linux) 0o1000 else 0x400;

// Values of `dirent.type`, identical on Linux and the BSDs.
pub const DT_UNKNOWN: u8 = 0;
pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;

/// True when the path itself is a symbolic link, without following it.
///
/// `readlink` on a non-link fails with EINVAL, which is the cheapest way to ask this
/// question without a `stat` struct. It matters for deletion: `opendir` follows links,
/// so treating "can be opened as a directory" as "is a directory" would let a link
/// inside the state directory redirect a recursive delete outside of it.
pub fn isSymlink(path: [*:0]const u8) bool {
    var buf: [1]u8 = undefined;
    return readlink(path, &buf, buf.len) >= 0;
}

pub const Kind = enum { file, dir, other, missing };

/// Entry kind taken from the directory entry itself.
///
/// `stat` was the obvious choice, but `std.c.Stat` does not describe Linux's `struct
/// stat` in a usable form here, and hand-rolling the layout per architecture is exactly
/// the kind of ABI guesswork that goes wrong quietly. `dirent.type` carries the same
/// information for free, is defined identically on both target platforms, and needs no
/// extra syscall. Some filesystems report DT_UNKNOWN, so the caller falls back to
/// `isDirPath`.
pub fn kindFromDirent(e: *Dirent) Kind {
    return switch (e.type) {
        DT_DIR => .dir,
        DT_REG => .file,
        DT_UNKNOWN => .missing, // "ask again a different way"
        else => .other,
    };
}

/// Fallback for filesystems that do not fill in `dirent.type`: a path that can be
/// opened as a directory is one.
pub fn isDirPath(path: [*:0]const u8) bool {
    const d = opendir(path) orelse return false;
    _ = closedir(d);
    return true;
}

pub fn kindOfPath(path: [*:0]const u8) Kind {
    if (isDirPath(path)) return .dir;
    const fd = open(path, O_RDONLY, 0);
    if (fd < 0) return .missing;
    _ = close(fd);
    return .file;
}

/// `d_name` is a fixed-size array in the struct; the name is the NUL-terminated prefix.
pub fn direntName(e: *Dirent) []const u8 {
    const p: [*:0]const u8 = @ptrCast(&e.name);
    return std.mem.span(p);
}

pub const Term = union(enum) {
    exited: u8,
    signaled: u8,
    unknown: c_int,

    pub fn isSignal(self: Term, sig: u8) bool {
        return switch (self) {
            .signaled => |s| s == sig,
            else => false,
        };
    }
};

pub fn decodeStatus(status: c_int) Term {
    const s: u32 = @bitCast(status);
    // WIFEXITED / WEXITSTATUS / WTERMSIG, spelled out rather than imported: the macros
    // are identical across Linux and the BSDs for these three cases.
    if (s & 0x7f == 0) return .{ .exited = @intCast((s >> 8) & 0xff) };
    if ((s & 0x7f) + 1 >= 2) {
        const sig: u8 = @intCast(s & 0x7f);
        if (sig != 0x7f) return .{ .signaled = sig };
    }
    return .{ .unknown = status };
}

pub const SpawnError = error{ ForkFailed, OutOfMemory };

/// Run a command to completion with extra environment variables set.
///
/// The variables are applied in the child after `fork`, so the engine's own environment
/// stays clean across worlds — otherwise `SIDEEYE_KILL_AT` from world k would leak into
/// world k+1 and every subsequent run would die at the wrong place.
pub fn runChild(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
) SpawnError!Term {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const argv_z = try arena.alloc(?[*:0]const u8, argv.len + 1);
    for (argv, 0..) |a, i| argv_z[i] = (try arena.dupeZ(u8, a)).ptr;
    argv_z[argv.len] = null;

    const env_z = try arena.alloc([2][*:0]const u8, env_pairs.len);
    for (env_pairs, 0..) |kv, i| {
        env_z[i][0] = (try arena.dupeZ(u8, kv[0])).ptr;
        env_z[i][1] = (try arena.dupeZ(u8, kv[1])).ptr;
    }

    const pid = fork();
    if (pid < 0) return error.ForkFailed;
    if (pid == 0) {
        for (env_z) |kv| _ = setenv(kv[0], kv[1], 1);
        _ = execvp(argv_z[0].?, argv_z.ptr);
        // Only reached when exec failed; 127 is the shell's convention for that.
        _exit(127);
    }

    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    return decodeStatus(status);
}

test "exit status decoding distinguishes exit from signal" {
    // exit(0) and exit(1)
    try std.testing.expectEqual(Term{ .exited = 0 }, decodeStatus(0x0000));
    try std.testing.expectEqual(Term{ .exited = 1 }, decodeStatus(0x0100));
    // killed by SIGKILL (9) — the case that matters most here, since every explored
    // world is expected to end this way
    try std.testing.expectEqual(Term{ .signaled = 9 }, decodeStatus(9));
    try std.testing.expect(decodeStatus(9).isSignal(9));
    try std.testing.expect(!decodeStatus(0x0000).isSignal(9));
}
