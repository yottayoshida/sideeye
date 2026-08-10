//! The replacement functions, shared by both platforms.
//!
//! Every one of these does the same three things: note the operation, look up the real
//! function, forward to it. What differs between Linux and macOS is only how the
//! replacement gets installed and how `common.real` gets filled — `linux.zig` exports
//! these symbols for `LD_PRELOAD` to resolve, `macos.zig` lists them in a
//! `__DATA,__interpose` table. Keeping the bodies in one place means a fix to path
//! handling or ordering cannot land on one platform and miss the other.
//!
//! On the fixed-arity wrappers for variadic libc functions: `open`, `openat` and the
//! `*at` family take an optional `mode` argument. Declaring them with the mode always
//! present is the usual practice for preload shims — the extra argument is ignored by
//! the callee when `O_CREAT` is absent — and it avoids `@cVaStart` machinery in the one
//! component that must stay boring. Whether that holds on this ABI is not assumed: the
//! spike's oracle comparison is what confirms every call was seen and forwarded intact.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const common = @import("common.zig");

const AT_FDCWD = common.AT_FDCWD;

fn missing() c_int {
    // dlsym could not find the real symbol. Failing loudly beats forwarding nowhere.
    return -1;
}

// --- kill-point ops: open family -------------------------------------------------

/// `open` and `openat` are the only variadic entry points here, and the right way to
/// declare them differs by platform — not as a preference, but because each ABI makes
/// the other form wrong.
///
/// On arm64 macOS variadic arguments are passed on the stack while fixed ones go in
/// registers, so a fixed-arity declaration reads `mode` from a register the caller
/// never wrote. Every created file came out with mode 0 and nothing reported an error.
/// On Linux the two forms agree, and Zig refuses `@cVaStart` for this target outright
/// ("disabled due to miscompilations") — which is its own statement about how much that
/// ABI can be relied on.
///
/// So each side uses the form that is correct for it. The bodies stay identical apart
/// from how `mode` is obtained.
const open_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        // Reading it when O_CREAT is absent would consume something never pushed.
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        common.note1(.open, AT_FDCWD, path);
        const g = common.real.open orelse return missing();
        return g(path, flags, mode);
    }
} else struct {
    pub fn f(path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        common.note1(.open, AT_FDCWD, path);
        const g = common.real.open orelse return missing();
        return g(path, flags, mode);
    }
};

pub const open = open_impl.f;


const openat_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        common.note1(.open, dirfd, path);
        const g = common.real.openat orelse return missing();
        return g(dirfd, path, flags, mode);
    }
} else struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        common.note1(.open, dirfd, path);
        const g = common.real.openat orelse return missing();
        return g(dirfd, path, flags, mode);
    }
};

pub const openat = openat_impl.f;


pub fn creat(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.open, AT_FDCWD, path);
    const f = common.real.creat orelse return missing();
    return f(path, mode);
}


// --- kill-point ops: write family ------------------------------------------------

pub fn write(fd: c_int, buf: [*]const u8, count: usize) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.write orelse return -1;
    return f(fd, buf, count);
}

pub fn pwrite(fd: c_int, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.pwrite orelse return -1;
    return f(fd, buf, count, offset);
}


pub fn writev(fd: c_int, iov: *const anyopaque, iovcnt: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    const f = common.real.writev orelse return -1;
    return f(fd, iov, iovcnt);
}

// --- kill-point ops: rename ------------------------------------------------------

pub fn rename(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, AT_FDCWD, old, AT_FDCWD, new);
    const f = common.real.rename orelse return missing();
    return f(old, new);
}

pub fn renameat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, olddirfd, old, newdirfd, new);
    const f = common.real.renameat orelse return missing();
    return f(olddirfd, old, newdirfd, new);
}

// --- kill-point ops: unlink ------------------------------------------------------

pub fn unlink(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.unlink, AT_FDCWD, path);
    const f = common.real.unlink orelse return missing();
    return f(path);
}

pub fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    // AT_REMOVEDIR (0x200) makes this an rmdir; report it as what it does.
    const op: contract.OpClass = if (flags & 0x200 != 0) .rmdir else .unlink;
    common.note1(op, dirfd, path);
    const f = common.real.unlinkat orelse return missing();
    return f(dirfd, path, flags);
}

// --- kill-point ops: sync and truncate -------------------------------------------

pub fn fsync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    const f = common.real.fsync orelse return missing();
    return f(fd);
}

pub fn fdatasync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    const f = common.real.fdatasync orelse return missing();
    return f(fd);
}

pub fn ftruncate(fd: c_int, length: i64) callconv(.c) c_int {
    common.noteFd(.truncate, fd);
    const f = common.real.ftruncate orelse return missing();
    return f(fd, length);
}


pub fn truncate(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    common.note1(.truncate, AT_FDCWD, path);
    const f = common.real.truncate orelse return missing();
    return f(path, length);
}


// --- kill-point ops: directories -------------------------------------------------

pub fn mkdir(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, AT_FDCWD, path);
    const f = common.real.mkdir orelse return missing();
    return f(path, mode);
}

pub fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, dirfd, path);
    const f = common.real.mkdirat orelse return missing();
    return f(dirfd, path, mode);
}

pub fn rmdir(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.rmdir, AT_FDCWD, path);
    const f = common.real.rmdir orelse return missing();
    return f(path);
}

// --- lifecycle -------------------------------------------------------------------

pub fn close(fd: c_int) callconv(.c) c_int {
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

pub fn fork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.fork orelse return missing();
    return f();
}

pub fn vfork() callconv(.c) c_int {
    common.noteBoundary(.fork);
    const f = common.real.vfork orelse return missing();
    return f();
}

pub fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execve orelse return missing();
    return f(path, argv, envp);
}

pub fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execv orelse return missing();
    return f(path, argv);
}

pub fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const f = common.real.execvp orelse return missing();
    return f(file, argv);
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
    const f = common.real.posix_spawn orelse return missing();
    return f(pid, path, file_actions, attrp, argv, envp);
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
    const f = common.real.posix_spawnp orelse return missing();
    return f(pid, file, file_actions, attrp, argv, envp);
}

pub fn pthread_create(
    thread: *anyopaque,
    attr: ?*const anyopaque,
    start_routine: *const anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    common.noteBoundary(.thread);
    const f = common.real.pthread_create orelse return missing();
    return f(thread, attr, start_routine, arg);
}
