//! Linux symbol replacement.
//!
//! Under `LD_PRELOAD` the dynamic linker resolves a symbol to the first library that
//! defines it, so exporting `open` here means the target's calls land in this file.
//! The real function is reached through `dlsym(RTLD_NEXT, …)` (see common.zig).
//!
//! On the fixed-arity wrappers for variadic libc functions: `open`, `openat` and the
//! `*at` family take an optional `mode` argument. Declaring them with the mode always
//! present is the usual practice for preload shims — the extra argument is ignored by
//! the callee when `O_CREAT` is absent — and it avoids `@cVaStart` machinery in the one
//! component that must stay boring. Whether that holds on this ABI is not assumed: the
//! spike's oracle comparison is what confirms every call was seen and forwarded intact.

const std = @import("std");
const contract = @import("contract");
const common = @import("common.zig");

const AT_FDCWD = common.AT_FDCWD;

fn missing() c_int {
    // dlsym could not find the real symbol. Failing loudly beats forwarding nowhere.
    return -1;
}

// --- kill-point ops: open family -------------------------------------------------

export fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
    common.note1(.open, AT_FDCWD, path);
    const f = common.real.open orelse return missing();
    return f(path, flags, mode);
}

export fn open64(path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
    return open(path, flags, mode);
}

export fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
    common.note1(.open, dirfd, path);
    const f = common.real.openat orelse return missing();
    return f(dirfd, path, flags, mode);
}

export fn openat64(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
    return openat(dirfd, path, flags, mode);
}

export fn creat(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.open, AT_FDCWD, path);
    const f = common.real.creat orelse return missing();
    return f(path, mode);
}

export fn creat64(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    return creat(path, mode);
}

// --- kill-point ops: write family ------------------------------------------------

export fn write(fd: c_int, buf: [*]const u8, count: usize) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.write orelse return -1;
    return f(fd, buf, count);
}

export fn pwrite(fd: c_int, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.pwrite orelse return -1;
    return f(fd, buf, count, offset);
}

export fn pwrite64(fd: c_int, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    return pwrite(fd, buf, count, offset);
}

export fn writev(fd: c_int, iov: *const anyopaque, iovcnt: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.writev orelse return -1;
    return f(fd, iov, iovcnt);
}

// --- kill-point ops: rename ------------------------------------------------------

export fn rename(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, AT_FDCWD, old, AT_FDCWD, new);
    const f = common.real.rename orelse return missing();
    return f(old, new);
}

export fn renameat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, olddirfd, old, newdirfd, new);
    const f = common.real.renameat orelse return missing();
    return f(olddirfd, old, newdirfd, new);
}

// --- kill-point ops: unlink ------------------------------------------------------

export fn unlink(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.unlink, AT_FDCWD, path);
    const f = common.real.unlink orelse return missing();
    return f(path);
}

export fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    // AT_REMOVEDIR (0x200) makes this an rmdir; report it as what it does.
    const op: contract.OpClass = if (flags & 0x200 != 0) .rmdir else .unlink;
    common.note1(op, dirfd, path);
    const f = common.real.unlinkat orelse return missing();
    return f(dirfd, path, flags);
}

// --- kill-point ops: sync and truncate -------------------------------------------

export fn fsync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    const f = common.real.fsync orelse return missing();
    return f(fd);
}

export fn fdatasync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    const f = common.real.fdatasync orelse return missing();
    return f(fd);
}

export fn ftruncate(fd: c_int, length: i64) callconv(.c) c_int {
    common.noteFd(.truncate, fd);
    const f = common.real.ftruncate orelse return missing();
    return f(fd, length);
}

export fn ftruncate64(fd: c_int, length: i64) callconv(.c) c_int {
    return ftruncate(fd, length);
}

export fn truncate(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    common.note1(.truncate, AT_FDCWD, path);
    const f = common.real.truncate orelse return missing();
    return f(path, length);
}

export fn truncate64(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    return truncate(path, length);
}

// --- kill-point ops: directories -------------------------------------------------

export fn mkdir(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, AT_FDCWD, path);
    const f = common.real.mkdir orelse return missing();
    return f(path, mode);
}

export fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, dirfd, path);
    const f = common.real.mkdirat orelse return missing();
    return f(dirfd, path, mode);
}

export fn rmdir(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.rmdir, AT_FDCWD, path);
    const f = common.real.rmdir orelse return missing();
    return f(path);
}

// --- lifecycle -------------------------------------------------------------------

export fn close(fd: c_int) callconv(.c) c_int {
    // Recorded before the call: afterwards the descriptor no longer resolves to a path.
    common.noteFd(.close, fd);
    const f = common.real.close orelse return missing();
    return f(fd);
}

// --- boundary detectors ----------------------------------------------------------
//
// These do not make the operation fail; they record that the run left the region
// v0.1 can reason about. The engine turns a single occurrence into UNKNOWN.
//
// `clone`, `clone3` and a raw `syscall(SYS_clone, …)` bypass this file entirely.
// That gap is why the recording run is compared against an external oracle and why
// the engine carries detectors that do not depend on interposition at all.

export fn fork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.fork orelse return missing();
    return f();
}

export fn vfork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.vfork orelse return missing();
    return f();
}

export fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execve orelse return missing();
    return f(path, argv, envp);
}

export fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execv orelse return missing();
    return f(path, argv);
}

export fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execvp orelse return missing();
    return f(file, argv);
}

export fn posix_spawn(
    pid: ?*anyopaque,
    path: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.posix_spawn orelse return missing();
    return f(pid, path, file_actions, attrp, argv, envp);
}

export fn posix_spawnp(
    pid: ?*anyopaque,
    file: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.posix_spawnp orelse return missing();
    return f(pid, file, file_actions, attrp, argv, envp);
}

export fn pthread_create(
    thread: *anyopaque,
    attr: ?*const anyopaque,
    start_routine: *const anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    common.noteBoundary(.thread);
    const f = common.real.pthread_create orelse return missing();
    return f(thread, attr, start_routine, arg);
}
