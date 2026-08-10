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
        common.debugHex("open flags=0x", @bitCast(flags));
        common.debugHex("open  read=0x", mode);
        common.note1(.open, AT_FDCWD, path);
        common.debugHex("open  fwd =0x", mode);
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
// These do not make the operation fail; they record that the run left the region
// v0.1 can reason about. The engine turns a single occurrence into UNKNOWN.
//
// `clone`, `clone3` and a raw `syscall(SYS_clone, …)` bypass this file entirely.
// That gap is why the recording run is compared against an external oracle where one
// exists, and why the engine carries detectors that do not depend on interposition.

pub fn fork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    return common.callFork();
}

pub fn vfork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    return common.callVfork();
}

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

pub fn posix_spawn(
    pid: ?*anyopaque,
    path: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    common.noteBoundary(.fork);
    return common.callPosixSpawn(pid, path, file_actions, attrp, argv, envp);
}

pub fn posix_spawnp(
    pid: ?*anyopaque,
    file: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    common.noteBoundary(.fork);
    return common.callPosixSpawnp(pid, file, file_actions, attrp, argv, envp);
}

pub fn pthread_create(
    thread: *anyopaque,
    attr: ?*const anyopaque,
    start_routine: *const anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    common.noteBoundary(.thread);
    return common.callPthreadCreate(thread, attr, start_routine, arg);
}
