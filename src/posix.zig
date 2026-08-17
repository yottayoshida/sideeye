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
/// Declared variadic, as C declares it.
///
/// This was a fixed three-argument declaration, and on arm64 macOS that silently loses
/// `mode`: variadic arguments travel on the stack, fixed ones in registers, so the
/// callee read a register the caller never wrote. Every file `restore()` wrote came out
/// with permissions nobody asked for — and since the engine then failed to read its own
/// output, the symptom looked like a shim defect for several rounds. The shim was fine.
/// Calling a variadic function correctly needs no `@cVaStart`; only receiving does.
pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn dup2(old_fd: c_int, new_fd: c_int) c_int;
/// `off_t` is 64-bit on every target this builds for (aarch64/x86-64 glibc, Darwin), so
/// the plain symbol is the 64-bit one and no lseek64 spelling is needed.
pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
/// Same values on Linux and Darwin.
pub const SEEK_SET: c_int = 0;
pub const SEEK_END: c_int = 2;

/// Same value on Linux and Darwin.
pub const EINTR: c_int = 4;
/// Same value on Linux and Darwin.
pub const ENOENT: c_int = 2;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
/// Mutates `template` in place (the trailing XXXXXX) and returns it, or null on failure.
pub extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
pub extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
pub extern "c" fn getpid() c_int;
pub extern "c" fn fork() c_int;
pub extern "c" fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
/// Exec with an explicit environment, so a child can be given a *minimal* env rather
/// than inheriting the parent's (the MCP server must not hand its credentials to a
/// config's operation). Requires an absolute path — no PATH search — which pairs with
/// the canonical self-path the MCP adapter resolves.
pub extern "c" fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;
pub extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
pub extern "c" fn setpgid(pid: c_int, pgid: c_int) c_int;
pub extern "c" fn kill(pid: c_int, sig: c_int) c_int;
/// Waits without reaping, which `waitpid` cannot do. See `runChild` for why that matters.
///
/// The `siginfo_t` out-parameter is written but never read here, so it is passed as an
/// opaque buffer rather than described: the struct differs between the platforms and
/// nothing in this file needs a field of it.
pub extern "c" fn waitid(idtype: c_int, id: c_int, infop: *anyopaque, options: c_int) c_int;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
pub extern "c" fn _exit(status: c_int) noreturn;
pub extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;
/// macOS: fills `buf` with the executable's path (may be non-canonical; realpath it).
/// Returns 0 on success; on too-small buffer returns -1 and writes the needed size.
pub extern "c" fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int;
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;

/// `access` mode: executable. Same value on Linux and the BSDs.
pub const X_OK: c_int = 1;

/// The only signal in play. Cannot be caught, which is the point: a target that could
/// decline to die would make the crash point a request rather than a fact.
///
/// Typed `u8` so the same constant serves both users — `kill` widens it to `c_int`, and
/// `Term.isSignal` compares it directly. `main.zig` was spelling it as a bare `9`.
pub const SIGKILL: u8 = 9;

/// `waitid` selectors and flags, taken from the platform headers rather than from memory.
///
/// `P_PID` and `WEXITED` agree across Linux and Darwin; **`WNOWAIT` does not** —
/// `0x01000000` in glibc's `bits/waitflags.h`, `0x00000020` in the macOS SDK's
/// `sys/wait.h`. Three defects in this project so far were a platform constant that was
/// right on one side and quietly plausible on the other, so the differing one is branched
/// and the agreeing ones say so.
pub const P_PID: c_int = 1;
pub const WEXITED: c_int = 4;
pub const WNOWAIT: c_int = if (builtin.os.tag == .linux) 0x01000000 else 0x00000020;

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_CREAT: c_int = if (builtin.os.tag == .linux) 0o100 else 0x200;
pub const O_TRUNC: c_int = if (builtin.os.tag == .linux) 0o1000 else 0x400;
pub const O_EXCL: c_int = if (builtin.os.tag == .linux) 0o200 else 0x800;
pub const O_NOFOLLOW: c_int = if (builtin.os.tag == .linux) 0o400000 else 0x100;

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

pub const Kind = enum { file, dir, symlink, other, missing };

/// Entry kind taken from the directory entry itself.
///
/// `stat` was the obvious choice, but `std.c.Stat` does not describe Linux's `struct
/// stat` in a usable form here, and hand-rolling the layout per architecture is exactly
/// the kind of ABI guesswork that goes wrong quietly. `dirent.type` carries the same
/// information for free, is defined identically on both target platforms, and needs no
/// extra syscall. Some filesystems report DT_UNKNOWN, so the caller falls back to
/// `kindOfPathNoFollow` (whose doc carries the dated correction to this paragraph's
/// `stat` claim).
pub fn kindFromDirent(e: *Dirent) Kind {
    return switch (e.type) {
        DT_DIR => .dir,
        DT_REG => .file,
        DT_LNK => .symlink,
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

/// Entry kind without opening and without following: the snapshot's DT_UNKNOWN
/// fallback. Its predecessor probed by `open(O_RDONLY)`, which is three different
/// wrong answers on the entries this classification exists to notice (#5 R1): a FIFO
/// with no writer blocks that open forever, a socket's failed open read back as
/// `.missing` — silently absent from the snapshot — and a readable device passed as
/// `.file` and got its bytes slurped. `fstatat(AT_SYMLINK_NOFOLLOW)` answers for the
/// entry itself, never for what it points at, and cannot hang.
///
/// This file once refused `stat` outright ("hand-rolling the layout per architecture
/// is exactly the kind of ABI guesswork that goes wrong quietly" — kindFromDirent's
/// doc). Corrected 2026-08-17: that was true of hand-rolling and is not true of what
/// std ships — but the two platforms get there differently, and the difference is
/// itself the old fear vindicated upstream: on Darwin `std.c.fstatat` resolves the
/// per-arch symbol (`fstatat$INODE64` on x86-64); on Linux std deliberately binds no
/// libc stat symbol at all (glibc's are versioned aliases) and speaks the `statx`
/// syscall directly, with the layout maintained in `std.os.linux`.
/// Only a path that is genuinely GONE answers `.missing` (the entry raced away
/// between readdir and here — the same benign race every walk lives with). Every
/// other failure is `Unclassifiable`, loudly: ENOSYS under an old kernel, EPERM under
/// seccomp, EACCES, EIO — collapsing those into "absent" would delete a real entry
/// from the snapshot and route it around #5's refusal, which is the exact silent
/// shape this function replaced (R1).
pub const ClassifyError = error{Unclassifiable};

pub fn kindOfPathNoFollow(path: [*:0]const u8) ClassifyError!Kind {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(lnx.AT.FDCWD, path, lnx.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true }, &stx);
        switch (lnx.errno(rc)) {
            .SUCCESS => {},
            .NOENT => return .missing,
            else => return error.Unclassifiable,
        }
        // std's own contract: "Callers must check this field since support varies by
        // kernel version and filesystem." A mode the kernel never filled in is not a
        // classification.
        if (!stx.mask.TYPE) return error.Unclassifiable;
        const m: u32 = stx.mode;
        if (lnx.S.ISLNK(m)) return .symlink;
        if (lnx.S.ISDIR(m)) return .dir;
        if (lnx.S.ISREG(m)) return .file;
        return .other;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstatat(std.c.AT.FDCWD, path, &st, std.c.AT.SYMLINK_NOFOLLOW) != 0) {
            if (std.c._errno().* == ENOENT) return .missing;
            return error.Unclassifiable;
        }
        const m = st.mode;
        if (std.c.S.ISLNK(m)) return .symlink;
        if (std.c.S.ISDIR(m)) return .dir;
        if (std.c.S.ISREG(m)) return .file;
        return .other;
    }
}

/// Test apparatus only: the classification above owes its falsification to a real
/// FIFO (#5), and std.c carries no mkfifo. The engine itself never creates one.
pub extern "c" fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;

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

/// Run a command to completion with extra environment variables set, and leave nothing of
/// it running.
///
/// The variables are applied in the child after `fork`, so the engine's own environment
/// stays clean across worlds — otherwise `SIDEEYE_KILL_AT` from world k would leak into
/// world k+1 and every subsequent run would die at the wrong place.
///
/// ## Why the process group
///
/// This used to `waitpid` the direct child and return. Everything the target spawned
/// outlived it: after the subject is killed at crash point k, a grandchild keeps running
/// while the engine snapshots the state directory, restores it for the next world, and
/// runs the checker. The verdict then describes a moment nobody chose. v0.1 only got away
/// with it because a target that creates processes is refused before any world is
/// explored — the recording run still had the hazard.
///
/// The child puts itself in a new process group before `exec`, and the whole group is
/// signalled once the direct child is gone.
///
/// **The signal has to be sent before the child is reaped**, which is why `waitid` appears
/// here at all. `kill(-N, …)` addresses the process group whose id is N, and N is the
/// child's pid. That id is safe to signal only while it is still spoken for: POSIX keeps a
/// pid out of circulation until the process lifetime ends, and a process that has exited
/// but not been waited for is still alive in that sense, still a member of its group, and
/// still holding the group id. Reap first and both become reusable — an unrelated process
/// could be allocated that pid, become a group leader, and receive a `SIGKILL` meant for
/// something that no longer exists.
///
/// The first version of this function did exactly that: `waitpid`, then `kill(-pid)`. The
/// argument written here for why it was safe ("a freshly allocated pid cannot equal a live
/// group id") is true at the moment of `fork` and false after the reap, which is the only
/// moment that mattered. `waitid(… WNOWAIT)` waits for the child to exit while leaving it
/// reapable, so the id stays pinned across the signal.
///
/// What this does **not** establish is that no descendant remains. A grandchild is
/// reparented away when its parent dies, so it is not this process's child to wait for —
/// `waitpid` returning `ECHILD` says nothing about it. The group signal is the strongest
/// thing available here; confirming the state directory has actually stopped moving is a
/// separate step, and it is an observation rather than a proof.
pub fn runChild(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, null, false, false);
}

/// `runChild`, with the child's stdout sent to a file. What a target says on stdout
/// is evidence — the L1 success marker is read from it (ADR 0008) — and evidence
/// belongs in the work directory, not interleaved with the engine's own report.
pub fn runChildCapture(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: []const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, stdout_path, false, false);
}

/// `runChildCapture`, with the child's stderr sent to the same file. The
/// falsification gate uses this (#134): its child's output must not reach the
/// transcript unlabeled, and a checker reports through both streams — the target's
/// own stderr passes through the checker's — so capturing stdout alone would still
/// leak the exact line class that was once harvested as world evidence.
pub fn runChildCaptureAll(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: []const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, stdout_path, false, true);
}

/// Like `runChildCapture`, but the child receives *only* `env_pairs` as its whole
/// environment (via `execve`, argv[0] an absolute path — no inheritance, no PATH
/// search). The MCP adapter uses this so a config's operation cannot read the server's
/// credentials, and so a canonical self-path is what actually runs (ADR 0010).
pub fn runChildCaptureMinimalEnv(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: []const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, stdout_path, true, false);
}

fn runChildImpl(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: ?[]const u8,
    minimal_env: bool,
    capture_stderr: bool,
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
    // For minimal-env exec: a NULL-terminated `NAME=VALUE` array to hand execve.
    const envp: ?[*]const ?[*:0]const u8 = if (minimal_env) blk: {
        const list = try arena.alloc(?[*:0]const u8, env_pairs.len + 1);
        for (env_pairs, 0..) |kv, i|
            list[i] = (try std.fmt.allocPrintSentinel(arena, "{s}={s}", .{ kv[0], kv[1] }, 0)).ptr;
        list[env_pairs.len] = null;
        break :blk list.ptr;
    } else null;
    const stdout_z: ?[*:0]const u8 = if (stdout_path) |sp| (try arena.dupeZ(u8, sp)).ptr else null;

    const pid = fork();
    if (pid < 0) return error.ForkFailed;
    if (pid == 0) {
        // Before exec, so the target never runs in the engine's group.
        _ = setpgid(0, 0);
        if (stdout_z) |sz| {
            // A capture that cannot be opened must not fall back to the engine's own
            // stdout: a world whose evidence went to the wrong stream would read as
            // "marker never appeared". 126 is distinct from exec's 127 on purpose.
            // Under minimal_env (the MCP path) the capture is opened O_NOFOLLOW|O_EXCL:
            // the work dir is attacker-visible in the general case, and a pre-planted
            // symlink must not turn the capture into an arbitrary-file truncation or a
            // read of the child's stdout by someone else.
            const flags: c_int = if (minimal_env)
                O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_EXCL
            else
                O_WRONLY | O_CREAT | O_TRUNC;
            const cfd = open(sz, flags, @as(c_uint, 0o600));
            if (cfd < 0) _exit(126);
            if (cfd != 1) {
                if (dup2(cfd, 1) < 0) _exit(126);
                _ = close(cfd);
            }
            if (capture_stderr) {
                // Both streams into the capture: a partial capture would leak the
                // other stream to the inherited fds — the exact failure this variant
                // exists to prevent. 126 for the same reason as the open above.
                if (dup2(1, 2) < 0) _exit(126);
            }
            if (minimal_env) {
                // The child (a config's operation, untrusted) must not read the MCP
                // transport on fd 0, nor write to it on fd 2. stdin → /dev/null,
                // stderr → the same capture file. Higher fds are closed so no inherited
                // descriptor (the JSON-RPC stdin among them) survives into the child.
                const nfd = open("/dev/null", O_RDONLY, @as(c_uint, 0));
                if (nfd >= 0 and nfd != 0) {
                    _ = dup2(nfd, 0);
                    _ = close(nfd);
                }
                _ = dup2(1, 2); // stderr → capture
                var fd: c_int = 3;
                while (fd < 256) : (fd += 1) _ = close(fd);
            }
        }
        if (envp) |ep| {
            // execve replaces the whole environment: no inheritance. argv[0] must be an
            // absolute path (the adapter passes the canonical self-path).
            _ = execve(argv_z[0].?, argv_z.ptr, ep);
        } else {
            for (env_z) |kv| _ = setenv(kv[0], kv[1], 1);
            _ = execvp(argv_z[0].?, argv_z.ptr);
        }
        // Only reached when exec failed; 127 is the shell's convention for that.
        _exit(127);
    }
    // Repeated in the parent to close the window where the child has not been scheduled
    // yet. Whichever call runs first wins; the second fails harmlessly (EACCES once the
    // child has exec'd, ESRCH if it has already exited).
    _ = setpgid(pid, pid);

    // Wait for the child to finish, but leave it reapable so its pid — and therefore the
    // group id about to be signalled — cannot be handed to anything else.
    var info: [256]u8 align(16) = undefined;
    if (waitid(P_PID, pid, &info, WEXITED | WNOWAIT) == 0) {
        // Everything the target left behind, in one signal, while the id is still pinned.
        _ = kill(-pid, SIGKILL);
    }
    // If `waitid` failed the id is not pinned, so nothing is signalled: sending SIGKILL to
    // a group that may have been recycled is worse than leaving a stray process. The stray
    // is what the quiescence check is for.

    // Retried rather than assumed. `status` is only written when the call succeeds, so a
    // discarded failure leaves it zero, `decodeStatus` reads a killed world as a clean
    // exit, and the world is reported as `kill_did_not_land` — the wrong reason. Bounded
    // because there is no errno binding here to tell a retryable interruption from a
    // permanent failure, and an unbounded loop on the permanent one would hang. Same class
    // as the ordering defect above: a wait call's side effect trusted without checking that
    // the call happened.
    var status: c_int = 0;
    var tries: u8 = 0;
    while (waitpid(pid, &status, 0) < 0 and tries < 8) : (tries += 1) {}

    // Reap what is still ours. Usually nothing: grandchildren belong to init the moment
    // the direct child dies. The loop exists so the engine does not accumulate zombies
    // from a target that put several processes in the group directly.
    while (waitpid(-pid, null, 0) > 0) {}

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

test "kindOfPathNoFollow classifies every kind without opening anything" {
    // The real FIFO is the load-bearing case: the retired open-probing fallback would
    // block on it forever, so a regression to probing surfaces here as a test timeout
    // rather than a wrong value. pid-unique paths: `zig build test` runs this file in
    // several concurrent binaries and a fixed shared path flakes under pairing (#28).
    var bb: [128]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-kindnf-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, @as(c_uint, 0o755));

    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/f", .{base}) catch unreachable;
    const fd = open(file_z.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = close(fd);
    try std.testing.expectEqual(Kind.file, try kindOfPathNoFollow(file_z.ptr));

    var db: [160]u8 = undefined;
    const dir_z = std.fmt.bufPrintZ(&db, "{s}/d", .{base}) catch unreachable;
    try std.testing.expect(mkdir(dir_z.ptr, @as(c_uint, 0o755)) == 0);
    try std.testing.expectEqual(Kind.dir, try kindOfPathNoFollow(dir_z.ptr));

    // Dangling on purpose: the answer must be about the link, never its target —
    // and a link TO a real file must still answer .symlink, not .file.
    var lb: [160]u8 = undefined;
    const dangling_z = std.fmt.bufPrintZ(&lb, "{s}/l", .{base}) catch unreachable;
    try std.testing.expect(symlink("no-such-target", dangling_z.ptr) == 0);
    try std.testing.expectEqual(Kind.symlink, try kindOfPathNoFollow(dangling_z.ptr));
    var l2b: [160]u8 = undefined;
    const tofile_z = std.fmt.bufPrintZ(&l2b, "{s}/l2", .{base}) catch unreachable;
    try std.testing.expect(symlink("f", tofile_z.ptr) == 0);
    try std.testing.expectEqual(Kind.symlink, try kindOfPathNoFollow(tofile_z.ptr));

    var qb: [160]u8 = undefined;
    const fifo_z = std.fmt.bufPrintZ(&qb, "{s}/pipe", .{base}) catch unreachable;
    try std.testing.expect(mkfifo(fifo_z.ptr, @as(c_uint, 0o644)) == 0);
    try std.testing.expectEqual(Kind.other, try kindOfPathNoFollow(fifo_z.ptr));

    var mb: [160]u8 = undefined;
    const gone_z = std.fmt.bufPrintZ(&mb, "{s}/gone", .{base}) catch unreachable;
    try std.testing.expectEqual(Kind.missing, try kindOfPathNoFollow(gone_z.ptr));

    _ = unlink(fifo_z.ptr);
    _ = unlink(tofile_z.ptr);
    _ = unlink(dangling_z.ptr);
    _ = unlink(file_z.ptr);
    _ = rmdir(dir_z.ptr);
    _ = rmdir(base.ptr);
}
