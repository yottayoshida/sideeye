//! The replacement functions, shared by both platforms.
//!
//! Every one does the same two things: note the operation, then forward to the real
//! function through `common.call*`. Those wrappers are where the platforms differ —
//! Linux goes through a `dlsym`-filled table, macOS calls the original directly — and
//! keeping that difference in one place means a fix to path handling or ordering cannot
//! land on one platform and miss the other.
//!
//! How these get installed differs too: `linux.zig` exports the symbols for
//! `LD_PRELOAD` to resolve, `macos.zig` lists them in a `__DATA,__interpose` table.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const common = @import("common.zig");

const AT_FDCWD = common.AT_FDCWD;

// --- kill-point ops: open family -------------------------------------------------

/// `open` and `openat` are the only variadic entry points, and the right declaration
/// differs by platform — not as a preference, but because each ABI makes the other
/// form wrong.
///
/// On arm64 macOS variadic arguments go on the stack while fixed ones go in registers,
/// so a fixed-arity declaration reads `mode` from a register the caller never wrote.
/// On Linux the two agree, and Zig refuses `@cVaStart` for that target outright
/// ("disabled due to miscompilations") — its own statement about that ABI.
const open_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        // Reading it when O_CREAT is absent would consume something never pushed.
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        common.note1(.open, AT_FDCWD, path);
        return common.callOpen(path, flags, mode);
    }
} else struct {
    pub fn f(path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        common.note1(.open, AT_FDCWD, path);
        return common.callOpen(path, flags, mode);
    }
};
pub const open = open_impl.f;

const openat_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        common.note1(.open, dirfd, path);
        return common.callOpenat(dirfd, path, flags, mode);
    }
} else struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        common.note1(.open, dirfd, path);
        return common.callOpenat(dirfd, path, flags, mode);
    }
};
pub const openat = openat_impl.f;

pub fn creat(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.open, AT_FDCWD, path);
    return common.callCreat(path, mode);
}

// --- kill-point ops: write family ------------------------------------------------

pub fn write(fd: c_int, buf: [*]const u8, count: usize) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callWrite(fd, buf, count);
}

pub fn pwrite(fd: c_int, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callPwrite(fd, buf, count, offset);
}

pub fn writev(fd: c_int, iov: *const anyopaque, iovcnt: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callWritev(fd, iov, iovcnt);
}

// --- kill-point ops: rename ------------------------------------------------------

pub fn rename(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, AT_FDCWD, old, AT_FDCWD, new);
    return common.callRename(old, new);
}

pub fn renameat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, olddirfd, old, newdirfd, new);
    return common.callRenameat(olddirfd, old, newdirfd, new);
}

// --- kill-point ops: unlink ------------------------------------------------------

pub fn unlink(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.unlink, AT_FDCWD, path);
    return common.callUnlink(path);
}

pub fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    // AT_REMOVEDIR makes this an rmdir; report it as what it does. The constant differs
    // between platforms, which is why it is not spelled inline here.
    const op: contract.OpClass = if (flags & common.AT_REMOVEDIR != 0) .rmdir else .unlink;
    common.note1(op, dirfd, path);
    return common.callUnlinkat(dirfd, path, flags);
}

// --- kill-point ops: sync and truncate -------------------------------------------

pub fn fsync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    return common.callFsync(fd);
}

pub fn fdatasync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    return common.callFdatasync(fd);
}

pub fn ftruncate(fd: c_int, length: i64) callconv(.c) c_int {
    common.noteFd(.truncate, fd);
    return common.callFtruncate(fd, length);
}

pub fn truncate(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    common.note1(.truncate, AT_FDCWD, path);
    return common.callTruncate(path, length);
}

// --- kill-point ops: directories -------------------------------------------------

pub fn mkdir(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, AT_FDCWD, path);
    return common.callMkdir(path, mode);
}

pub fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, dirfd, path);
    return common.callMkdirat(dirfd, path, mode);
}

pub fn rmdir(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.rmdir, AT_FDCWD, path);
    return common.callRmdir(path);
}

// --- lifecycle -------------------------------------------------------------------

pub fn close(fd: c_int) callconv(.c) c_int {
    // Recorded before the call: afterwards the descriptor no longer resolves to a path.
    common.noteFd(.close, fd);
    return common.callClose(fd);
}

// --- boundary detectors ----------------------------------------------------------
//
// These do not make the operation fail; they record that the run crossed a process
// boundary. Whether that is tolerable is the engine's decision, not this file's.
//
// Recorded *after* the call succeeds, except where noted. The old pre-call records
// meant a failed fork — no child anywhere — read exactly like a real one, and the
// difference between those is the difference between a refusal and a verdict.
//
// `clone`, `clone3` and a raw `syscall(SYS_clone, …)` bypass this file entirely.
// That gap is why the recording run is compared against an external oracle where one
// exists, and why the engine carries detectors that do not depend on interposition.

pub fn fork() callconv(.c) c_int {
    const rc = common.callFork();
    // Parent only. The child's rc is 0 and its operations carry its own pid; recording
    // the boundary twice would claim two forks happened.
    if (rc > 0) common.noteBoundary(.fork);
    return rc;
}

/// The one wrapper that must not have a stack frame at the moment it calls the real
/// function — enforced by the `.always_tail` below, which is a compile error on any
/// target where the backend cannot guarantee it.
///
/// A `vfork` child runs on the parent's stack while the parent is suspended, and the call
/// returns twice. An ordinary wrapper's frame spans that double return: the child pops
/// the frame on its way back to the target, runs, and overwrites the memory it occupied —
/// including the saved frame pointer and return address the *parent's* return path will
/// restore. Measured, with the control that settles where the fault is:
///
///   vfork+exec of /bin/true, glibc 2.36 aarch64:   exit 0   without the shim
///                                                  exit 127 with an ordinary wrapper
///                                                  exit 127 with the shim loaded but
///                                                           *inactive* (recording nothing)
///
/// The inactive case is the proof: no recording happened, so the corruption is the frame
/// itself. The parent resumed through clobbered saved registers into the child's branch
/// and exited 127 with no output — silently wrong control flow, not a crash. sideeye then
/// blamed the corpse: `recording_run_failed`, for a death it caused. glibc's own `vfork`
/// is hand-written frameless assembly for exactly this reason.
///
/// The shim needs nothing *after* vfork returns, so the frame does not need to exist:
/// record the boundary first (an ordinary call, safely before the fork), then tail-jump.
/// At the jump the stack is exactly as if the target had called `vfork` directly, and
/// both returns land in the target without touching this function again.
///
/// Why the other process-creating wrappers do not need this: a `fork` child runs on a
/// *copy* of the stack, and glibc's `posix_spawn` gives its `CLONE_VM|CLONE_VFORK` child
/// a freshly mmap'd stack — measured as the reason spawn survived an ordinary wrapper
/// while vfork did not. Only `vfork` shares the parent's.
pub fn vfork() callconv(.c) c_int {
    // The one boundary still recorded before the call: there is no frame afterwards to
    // record from. The cost is that a failed vfork leaves a fork record with no child —
    // the engine reads that as a boundary and refuses, which errs toward UNKNOWN.
    common.noteBoundary(.fork);
    const real_vfork = common.realVfork() orelse return -1;
    return @call(.always_tail, real_vfork, .{});
}

// Exec keeps the pre-call record: on success there is no "after" in the same image to
// record from, and on failure the extra record errs toward refusal.
pub fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    return common.callExecve(path, argv, envp);
}

pub fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    return common.callExecv(path, argv);
}

pub fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    return common.callExecvp(file, argv);
}

// Through v2 these recorded `.fork`, which is wrong in kind: the child is a new process
// *and* a new image. The misclassification was harmless while both were refused, and
// stops being harmless the moment the engine treats them differently.
pub fn posix_spawn(
    pid: ?*anyopaque,
    path: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    const rc = common.callPosixSpawn(pid, path, file_actions, attrp, argv, envp);
    if (rc == 0) common.noteBoundary(.spawn);
    return rc;
}

pub fn posix_spawnp(
    pid: ?*anyopaque,
    file: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    const rc = common.callPosixSpawnp(pid, file, file_actions, attrp, argv, envp);
    if (rc == 0) common.noteBoundary(.spawn);
    return rc;
}

pub fn pthread_create(
    thread: *anyopaque,
    attr: ?*const anyopaque,
    start_routine: *const anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    const rc = common.callPthreadCreate(thread, attr, start_routine, arg);
    if (rc == 0) common.noteBoundary(.thread);
    return rc;
}

// --- containment escapes -----------------------------------------------------------
//
// The engine confines the target by putting it in its own process group and killing the
// group. A process that leaves the group is one the engine can no longer claim to have
// stopped — so the departure itself is recorded, and the engine refuses rather than
// pretends.

pub fn setsid() callconv(.c) c_int {
    const rc = common.callSetsid();
    // setsid fails for a process that is already a group leader, and the engine makes
    // the direct child exactly that — so a successful setsid can only have come from a
    // descendant, which is precisely the process that just escaped.
    if (rc >= 0) common.noteBoundary(.detached);
    return rc;
}

pub fn setpgid(pid: c_int, pgid: c_int) callconv(.c) c_int {
    // A call that changes nothing is not an escape. The direct child is already its
    // own group leader (the engine made it so), and a target calling setpgid(0, 0) in
    // that position — shells do — must not be refused for it. The same courtesy goes
    // to a call aimed at another process: only a group that actually changed counts.
    const subject = if (pid == 0) common.c.getpid() else pid;
    const before = common.c.getpgid(subject);
    const rc = common.callSetpgid(pid, pgid);
    if (rc == 0 and common.c.getpgid(subject) != before)
        common.noteBoundary(.detached);
    return rc;
}
