//! macOS symbol installation.
//!
//! dyld does not resolve by first-definition-wins the way `LD_PRELOAD` does. Instead a
//! library declares pairs of (replacement, original) in a `__DATA,__interpose` section,
//! and dyld rewrites calls that cross image boundaries.
//!
//! Two consequences, both measured rather than assumed (BUILDLOG 2026-08-10):
//!
//!   - **No `dlsym` is needed.** Calls within the same image are not interposed, so the
//!     `extern` declarations below reach the real functions directly. `bindReal` simply
//!     points `common.real` at them.
//!   - **The constructor section differs.** `.init_array` is `__DATA,__mod_init_func`
//!     here; `shim.zig` picks the right one.
//!
//! What is *not* available here is an oracle: `dtruss` is DTrace-based and System
//! Integrity Protection refuses it. The engine's structural detectors carry completeness
//! alone on this platform, and a PASS requires the caller to say `--allow-unverified`.

const std = @import("std");
const common = @import("common.zig");
const ops = @import("ops.zig");

// The real functions. Declaring them here and calling them from the same image is what
// makes them reachable without a lookup.
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn creat(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern "c" fn pwrite(fd: c_int, buf: [*]const u8, count: usize, offset: i64) isize;
extern "c" fn writev(fd: c_int, iov: *const anyopaque, iovcnt: c_int) isize;
extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
extern "c" fn renameat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8) c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int;
extern "c" fn fsync(fd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn ftruncate(fd: c_int, length: i64) c_int;
extern "c" fn truncate(path: [*:0]const u8, length: i64) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn rmdir(path: [*:0]const u8) c_int;
extern "c" fn fork() c_int;
extern "c" fn vfork() c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;
extern "c" fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
extern "c" fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
extern "c" fn posix_spawn(pid: ?*anyopaque, path: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;
extern "c" fn posix_spawnp(pid: ?*anyopaque, file: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;
extern "c" fn pthread_create(thread: *anyopaque, attr: ?*const anyopaque, start: *const anyopaque, arg: ?*anyopaque) c_int;

/// macOS has no `fdatasync`; `fsync` covers both spellings here.
pub fn bindReal() void {
    common.real.open = &open;
    common.real.openat = &openat;
    common.real.creat = &creat;
    common.real.write = &write;
    common.real.pwrite = &pwrite;
    common.real.writev = &writev;
    common.real.rename = &rename;
    common.real.renameat = &renameat;
    common.real.unlink = &unlink;
    common.real.unlinkat = &unlinkat;
    common.real.fsync = &fsync;
    common.real.fdatasync = &fsync;
    common.real.close = &close;
    common.real.ftruncate = &ftruncate;
    common.real.truncate = &truncate;
    common.real.mkdir = &mkdir;
    common.real.mkdirat = &mkdirat;
    common.real.rmdir = &rmdir;
    common.real.fork = &fork;
    common.real.vfork = &vfork;
    common.real.execve = &execve;
    common.real.execv = &execv;
    common.real.execvp = &execvp;
    common.real.posix_spawn = &posix_spawn;
    common.real.posix_spawnp = &posix_spawnp;
    common.real.pthread_create = &pthread_create;
}

const Interpose = extern struct {
    replacement: *const anyopaque,
    original: *const anyopaque,
};

fn entry(replacement: anytype, original: anytype) Interpose {
    return .{ .replacement = @ptrCast(replacement), .original = @ptrCast(original) };
}

/// `@intFromPtr` on a function address is not comptime-evaluable, so the table holds
/// pointers rather than integers.
export const sideeye_interposers linksection("__DATA,__interpose") = [_]Interpose{
    entry(&ops.open, &open),
    entry(&ops.openat, &openat),
    entry(&ops.creat, &creat),
    entry(&ops.write, &write),
    entry(&ops.pwrite, &pwrite),
    entry(&ops.writev, &writev),
    entry(&ops.rename, &rename),
    entry(&ops.renameat, &renameat),
    entry(&ops.unlink, &unlink),
    entry(&ops.unlinkat, &unlinkat),
    entry(&ops.fsync, &fsync),
    entry(&ops.close, &close),
    entry(&ops.ftruncate, &ftruncate),
    entry(&ops.truncate, &truncate),
    entry(&ops.mkdir, &mkdir),
    entry(&ops.mkdirat, &mkdirat),
    entry(&ops.rmdir, &rmdir),
    entry(&ops.fork, &fork),
    entry(&ops.vfork, &vfork),
    entry(&ops.execve, &execve),
    entry(&ops.execv, &execv),
    entry(&ops.execvp, &execvp),
    entry(&ops.posix_spawn, &posix_spawn),
    entry(&ops.posix_spawnp, &posix_spawnp),
    entry(&ops.pthread_create, &pthread_create),
};
