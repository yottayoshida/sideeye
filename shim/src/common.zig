//! The part of the shim that does not depend on how symbols get replaced.
//!
//! Everything here runs *inside somebody else's process*, which sets the rules:
//! no heap, no standard-library I/O, no locks, no assumptions about what the target
//! has already initialised. State lives in globals; buffers are fixed and static.
//!
//! v0.1 supports single-threaded targets only. A target that creates a thread is
//! reported as UNKNOWN rather than measured, so the globals below do not need
//! synchronisation — and adding a lock would be worse than useless, because it would
//! hide the very condition we must report.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");

pub const c = struct {
    pub extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
    pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
    pub extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
    pub extern "c" fn raise(sig: c_int) c_int;
    pub extern "c" fn _exit(status: c_int) noreturn;
    pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
    /// macOS only: asks a descriptor for its path.
    ///
    /// Variadic, as C declares it. A fixed third argument was the third instance of the
    /// same ABI mistake in this codebase: on arm64 the buffer pointer went into a
    /// register the callee never read, `F_GETPATH` failed, and every fd-based operation
    /// (`write`, `fsync`, `close`) was silently dropped from the trace — macOS counted
    /// three operations where Linux counted five, with nothing reporting an error.
    pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
};

const SEEK_END: c_int = 2;
/// Darwin's F_GETPATH. The buffer must hold at least PATH_MAX (1024) bytes.
const F_GETPATH: c_int = 50;
const darwin_path_max: usize = 1024;

/// `RTLD_NEXT` is `((void *) -1)`: resolve the symbol in the search order *after* us,
/// which is how we reach the real libc function we just replaced.
pub const rtld_next: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

pub const AT_FDCWD: c_int = if (builtin.os.tag == .macos) -2 else -100;
const SIGKILL: c_int = 9;

// These differ between the two platforms and getting them wrong is quiet: the trace
// file would open with the wrong semantics — truncating instead of appending, or
// leaking across an exec — and the failure would look like missing records rather than
// like a bad flag.
const is_darwin = builtin.os.tag == .macos;
const O_WRONLY: c_int = 0o1;
/// Public because `ops.zig` has to decide whether a variadic `mode` argument is even
/// present before reading it.
pub const O_CREAT: c_int = if (is_darwin) 0x200 else 0o100;
const O_APPEND: c_int = if (is_darwin) 0x8 else 0o2000;
const O_CLOEXEC: c_int = if (is_darwin) 0x1000000 else 0o2000000;

// `open` and `openat` are variadic in C, and declaring them with a fixed third
// argument is wrong in a way that only shows on some ABIs. On arm64 macOS variadic
// arguments are passed on the stack while fixed ones go in registers, so a fixed-arity
// declaration reads `mode` from a register the caller never wrote — every created file
// came out with mode 0, with no error anywhere. The identical code is correct on Linux.
// Declaring them variadic is correct on both.
//
// `creat` is genuinely two-argument in POSIX and stays as it is.
pub const OpenFn = if (is_darwin)
    *const fn ([*:0]const u8, c_int, ...) callconv(.c) c_int
else
    *const fn ([*:0]const u8, c_int, c_uint) callconv(.c) c_int;
pub const OpenatFn = if (is_darwin)
    *const fn (c_int, [*:0]const u8, c_int, ...) callconv(.c) c_int
else
    *const fn (c_int, [*:0]const u8, c_int, c_uint) callconv(.c) c_int;
pub const CreatFn = *const fn ([*:0]const u8, c_uint) callconv(.c) c_int;
pub const WriteFn = *const fn (c_int, [*]const u8, usize) callconv(.c) isize;
pub const PwriteFn = *const fn (c_int, [*]const u8, usize, i64) callconv(.c) isize;
pub const WritevFn = *const fn (c_int, *const anyopaque, c_int) callconv(.c) isize;
pub const RenameFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int;
pub const RenameatFn = *const fn (c_int, [*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int;
pub const UnlinkFn = *const fn ([*:0]const u8) callconv(.c) c_int;
pub const UnlinkatFn = *const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int;
pub const FdFn = *const fn (c_int) callconv(.c) c_int;
pub const FtruncateFn = *const fn (c_int, i64) callconv(.c) c_int;
pub const TruncateFn = *const fn ([*:0]const u8, i64) callconv(.c) c_int;
pub const MkdirFn = *const fn ([*:0]const u8, c_uint) callconv(.c) c_int;
pub const MkdiratFn = *const fn (c_int, [*:0]const u8, c_uint) callconv(.c) c_int;
pub const RmdirFn = *const fn ([*:0]const u8) callconv(.c) c_int;
pub const ForkFn = *const fn () callconv(.c) c_int;
pub const ExecveFn = *const fn ([*:0]const u8, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int;
pub const ExecvpFn = *const fn ([*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int;
pub const PosixSpawnFn = *const fn (?*anyopaque, [*:0]const u8, ?*const anyopaque, ?*const anyopaque, [*]const ?[*:0]const u8, [*]const ?[*:0]const u8) callconv(.c) c_int;
pub const PthreadCreateFn = *const fn (*anyopaque, ?*const anyopaque, *const anyopaque, ?*anyopaque) callconv(.c) c_int;

pub var real: struct {
    open: ?OpenFn = null,
    openat: ?OpenatFn = null,
    creat: ?CreatFn = null,
    write: ?WriteFn = null,
    pwrite: ?PwriteFn = null,
    writev: ?WritevFn = null,
    rename: ?RenameFn = null,
    renameat: ?RenameatFn = null,
    unlink: ?UnlinkFn = null,
    unlinkat: ?UnlinkatFn = null,
    fsync: ?FdFn = null,
    fdatasync: ?FdFn = null,
    close: ?FdFn = null,
    ftruncate: ?FtruncateFn = null,
    truncate: ?TruncateFn = null,
    mkdir: ?MkdirFn = null,
    mkdirat: ?MkdiratFn = null,
    rmdir: ?RmdirFn = null,
    fork: ?ForkFn = null,
    vfork: ?ForkFn = null,
    execve: ?ExecveFn = null,
    execv: ?ExecvpFn = null,
    execvp: ?ExecvpFn = null,
    posix_spawn: ?PosixSpawnFn = null,
    posix_spawnp: ?PosixSpawnFn = null,
    pthread_create: ?PthreadCreateFn = null,
} = .{};

var state_dir_buf: [contract.max_path]u8 = undefined;
var state_dir_len: usize = 0;
var trace_fd: c_int = -1;
var kill_at: u32 = 0;
var seq: u32 = 0;
var active: bool = false;

/// Guards against observing our own work. The path resolution below calls libc, and
/// while none of those calls are interposed today, a future addition to the symbol
/// list would silently start recording the shim's own behaviour as the target's.
var busy: bool = false;

/// One record is built here and written with a single `write(2)`, so a trace never
/// ends with half a record even when the process dies mid-run.
var record_buf: [contract.max_record_len]u8 = undefined;

fn lookup(comptime T: type, name: [*:0]const u8) ?T {
    const p = c.dlsym(rtld_next, name) orelse return null;
    return @ptrCast(@alignCast(p));
}

fn resolveAll() void {
    real.open = lookup(OpenFn, "open");
    real.openat = lookup(OpenatFn, "openat");
    real.creat = lookup(CreatFn, "creat");
    real.write = lookup(WriteFn, "write");
    real.pwrite = lookup(PwriteFn, "pwrite");
    real.writev = lookup(WritevFn, "writev");
    real.rename = lookup(RenameFn, "rename");
    real.renameat = lookup(RenameatFn, "renameat");
    real.unlink = lookup(UnlinkFn, "unlink");
    real.unlinkat = lookup(UnlinkatFn, "unlinkat");
    real.fsync = lookup(FdFn, "fsync");
    real.fdatasync = lookup(FdFn, "fdatasync");
    real.close = lookup(FdFn, "close");
    real.ftruncate = lookup(FtruncateFn, "ftruncate");
    real.truncate = lookup(TruncateFn, "truncate");
    real.mkdir = lookup(MkdirFn, "mkdir");
    real.mkdirat = lookup(MkdiratFn, "mkdirat");
    real.rmdir = lookup(RmdirFn, "rmdir");
    real.fork = lookup(ForkFn, "fork");
    real.vfork = lookup(ForkFn, "vfork");
    real.execve = lookup(ExecveFn, "execve");
    real.execv = lookup(ExecvpFn, "execv");
    real.execvp = lookup(ExecvpFn, "execvp");
    real.posix_spawn = lookup(PosixSpawnFn, "posix_spawn");
    real.posix_spawnp = lookup(PosixSpawnFn, "posix_spawnp");
    real.pthread_create = lookup(PthreadCreateFn, "pthread_create");
}

fn parseU32(s: []const u8) u32 {
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return 0;
        v = v *% 10 +% (ch - '0');
    }
    return v;
}

/// Runs before `main` via `.init_array`.
///
/// Initialising lazily — on the first interposed call — would be simpler, but it would
/// make "the shim never loaded" and "the target performed no operations" produce the
/// same empty trace. The `shim_ready` marker written here is what lets the engine tell
/// those apart, so it has to be written whether or not the target does anything.
pub fn init() void {
    // macOS fills `real` from extern declarations before this runs (see shim.zig);
    // dlsym is a Linux-only step.
    if (builtin.os.tag != .macos) resolveAll();

    const sd = c.getenv(contract.env.state_dir) orelse return;
    const tp = c.getenv(contract.env.trace_path) orelse return;

    const sd_slice = std.mem.span(sd);
    if (sd_slice.len == 0 or sd_slice.len > contract.max_path) return;
    const normalized = contract.normalizePath(&state_dir_buf, "/", sd_slice) catch return;
    state_dir_len = normalized.len;

    trace_fd = callOpen(tp, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644);
    if (trace_fd < 0) return;

    if (c.getenv(contract.env.kill_at)) |k| kill_at = parseU32(std.mem.span(k));

    // The shim writes the header, not the engine.
    //
    // If the engine wrote it, the version field would be one the engine had just
    // produced and was about to read back — a check of nothing. Written here, it
    // records which contract *this binary* was built against, which is what makes a
    // stale shim paired with a fresh engine detectable instead of silently misread.
    // The file is opened O_APPEND, so an offset of zero means nobody has written yet.
    if (c.lseek(trace_fd, 0, SEEK_END) == 0) {
        var head: [contract.header_len]u8 = undefined;
        const n = contract.encodeHeader(&head) catch return;
        _ = writeAll(head[0..n]);
    }

    active = true;
    writeRecord(.{ .op = .shim_ready, .seq = 0, .path = stateDir(), .aux = "" });
}

pub fn stateDir() []const u8 {
    return state_dir_buf[0..state_dir_len];
}

/// Writes through the *real* `write`, obtained via dlsym, not through the symbol this
/// library exports. The shim's own output therefore never passes its own interposition
/// and cannot appear in the trace as if the target had produced it.
fn writeAll(bytes: []const u8) bool {
    if (trace_fd < 0) return false;
    var off: usize = 0;
    while (off < bytes.len) {
        const w = callWrite(trace_fd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return false;
        off += @intCast(w);
    }
    return true;
}

fn writeRecord(rec: contract.Record) void {
    const n = contract.encodeRecord(&record_buf, rec) catch return;
    _ = writeAll(record_buf[0..n]);
}

/// Absolute path of an open descriptor, via `/proc/self/fd/N`.
///
/// Returns null when the link cannot be read — an unlinked file, an `O_TMPFILE`
/// descriptor, a socket. The caller turns that into UNKNOWN rather than guessing,
/// because a descriptor we cannot name is one we cannot decide is in scope.
const deleted_suffix = " (deleted)";

/// Absolute path of an open descriptor, via `/proc/self/fd/N`.
///
/// Returns null only when the descriptor cannot name a filesystem path at all — the
/// link failed to read, or it resolves to something like `socket:[12345]`, which is
/// proof the descriptor is *not* in the state directory rather than uncertainty about
/// it. Those must not become UNKNOWN: a target that writes to a socket would otherwise
/// be unjudgeable, and there would be nothing wrong with it.
///
/// A descriptor whose file has been unlinked reads back as `/path/to/file (deleted)`.
/// That case sets `deleted` and still returns the path, because the caller needs to
/// know whether it was inside the state directory before deciding what it means.
fn fdPath(out: []u8, fd: c_int, deleted: *bool) ?[]const u8 {
    deleted.* = false;

    if (builtin.os.tag == .macos) {
        // `fcntl(F_GETPATH)` is the Darwin equivalent of reading /proc/self/fd, and it
        // resolves symlinks the same way (/etc/hosts comes back as /private/etc/hosts).
        // It has no "(deleted)" spelling, so an unlinked file simply reports its last
        // path; that is a known gap rather than a silent one — see BUILDLOG.
        if (out.len < darwin_path_max) return null;
        if (c.fcntl(fd, F_GETPATH, out.ptr) == -1) return null;
        const p = std.mem.sliceTo(out, 0);
        if (p.len == 0 or p[0] != '/') return null;
        return p;
    }

    var link_buf: [64]u8 = undefined;
    const link = std.fmt.bufPrintZ(&link_buf, "/proc/self/fd/{d}", .{fd}) catch return null;
    const n = c.readlink(link, out.ptr, out.len);
    if (n <= 0) return null;
    var raw = out[0..@intCast(n)];
    if (raw.len == 0 or raw[0] != '/') return null;
    if (std.mem.endsWith(u8, raw, deleted_suffix)) {
        deleted.* = true;
        raw = raw[0 .. raw.len - deleted_suffix.len];
    }
    return raw;
}

fn cwdPath(out: []u8) ?[]const u8 {
    const r = c.getcwd(out.ptr, out.len) orelse return null;
    return std.mem.span(r);
}

/// Resolve a (dirfd, path) pair the way the kernel would, minus symlink following.
/// Resolve a (dirfd, path) pair, distinguishing "not our business" from "could not
/// tell".
///
/// `unresolvable` is set only for the second kind. A directory descriptor that cannot
/// name a path at all — a socket, a pipe — is proof the operation is not in the state
/// directory, and treating that as uncertainty would make ordinary programs
/// unjudgeable. A descriptor whose directory has been unlinked is the opposite: it
/// named something once, and where that was decides whether this matters.
fn resolveAt(out: []u8, dirfd: c_int, path: [*:0]const u8, unresolvable: *bool) ?[]const u8 {
    unresolvable.* = false;
    const p = std.mem.span(path);
    if (p.len == 0) return null;
    if (p[0] == '/') {
        return contract.normalizePath(out, "/", p) catch {
            unresolvable.* = true;
            return null;
        };
    }

    var base_buf: [contract.max_path]u8 = undefined;
    var base_deleted = false;
    const base = if (dirfd == AT_FDCWD) blk: {
        break :blk cwdPath(&base_buf) orelse {
            // The working directory itself could not be read; a relative path cannot be
            // placed, and it may well have been inside the state directory.
            unresolvable.* = true;
            return null;
        };
    } else blk: {
        const b = fdPath(&base_buf, dirfd, &base_deleted) orelse return null;
        if (base_deleted) {
            unresolvable.* = contract.isInsideDir(b, stateDir());
            return null;
        }
        break :blk b;
    };

    return contract.normalizePath(out, base, p) catch {
        unresolvable.* = true;
        return null;
    };
}

/// An operation that was seen but could not be placed.
///
/// Dropping it silently is the failure this whole tool exists to avoid: the engine
/// would then see a trace that is complete as far as it can tell, and PASS is the
/// honest-looking answer to that. Recorded instead, so the engine can refuse to judge.
fn noteUnresolved(path: []const u8) void {
    writeRecord(.{ .op = .unresolved, .seq = 0, .path = path, .aux = "" });
}

/// The single place where an operation becomes a counted event, and the single place
/// where the process dies.
fn observe(op: contract.OpClass, path: []const u8, aux: []const u8) void {
    var s: u32 = 0;
    if (op.isKillPoint()) {
        if (!contract.isInsideDir(path, stateDir())) return;
        seq += 1;
        s = seq;
        if (kill_at != 0 and s == kill_at) {
            // Landing evidence first, then die. Without this record the claim "we died
            // before the k-th operation" would rest on the engine having set a variable,
            // not on anything the target actually did.
            writeRecord(.{ .op = .kill_landed, .seq = s, .path = path, .aux = aux });
            _ = c.raise(SIGKILL);
            // SIGKILL cannot be caught or ignored, so this is unreachable. If it is ever
            // reached, the run is not what it claims to be — refuse to continue quietly.
            c._exit(@intFromEnum(contract.ExitCode.setup_error));
        }
    } else if (op == .close) {
        // Recorded so the oracle can match it, but never a crash point: SIGKILL closes
        // descriptors anyway, so dying just before close and just after it leave the
        // same bytes on disk.
        if (!contract.isInsideDir(path, stateDir())) return;
    }
    writeRecord(.{ .op = op, .seq = s, .path = path, .aux = aux });
}

pub fn note1(op: contract.OpClass, dirfd: c_int, path: [*:0]const u8) void {
    if (!active or busy) return;
    busy = true;
    defer busy = false;

    var buf: [contract.max_path]u8 = undefined;
    var unresolvable = false;
    const resolved = resolveAt(&buf, dirfd, path, &unresolvable) orelse {
        // Recorded only when the path genuinely could not be determined. A descriptor
        // that names no path at all says the operation is elsewhere, which is an answer.
        if (unresolvable) noteUnresolved(std.mem.span(path));
        return;
    };
    observe(op, resolved, "");
}

pub fn note2(
    op: contract.OpClass,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: [*:0]const u8,
) void {
    if (!active or busy) return;
    busy = true;
    defer busy = false;

    var buf: [contract.max_path]u8 = undefined;
    var abuf: [contract.max_path]u8 = undefined;
    var unresolvable = false;
    const resolved = resolveAt(&buf, dirfd, path, &unresolvable) orelse {
        if (unresolvable) noteUnresolved(std.mem.span(path));
        return;
    };
    const aresolved = resolveAt(&abuf, adirfd, apath, &unresolvable) orelse {
        // Half of a rename is not something to record as a rename.
        if (unresolvable) noteUnresolved(std.mem.span(apath));
        return;
    };
    observe(op, resolved, aresolved);
}

pub fn noteFd(op: contract.OpClass, fd: c_int) void {
    if (!active or busy) return;
    if (fd == trace_fd) return; // never observe the trace we are writing
    if (fd <= 2) return; // stdin/stdout/stderr are not state
    busy = true;
    defer busy = false;

    var buf: [contract.max_path]u8 = undefined;
    var deleted = false;
    // A null here means the descriptor cannot name a path at all (a socket, a pipe, a
    // failed link read). That is evidence it is outside the state directory, not
    // uncertainty about it, so there is nothing to report.
    const resolved = fdPath(&buf, fd, &deleted) orelse return;
    if (!contract.isInsideDir(resolved, stateDir())) return;
    if (deleted) {
        // The file was inside the state directory and has since been unlinked. Writing
        // through such a descriptor still changes bytes the engine cannot see in any
        // snapshot, so the operation exists but has no address.
        noteUnresolved(resolved);
        return;
    }
    observe(op, resolved, "");
}

// --- reaching the real function ---------------------------------------------------
//
// Linux has to look the original up with `dlsym` and keep it somewhere, so it goes
// through the `real` table. macOS must NOT: interposition is live from the moment the
// library loads, while the constructor that would fill such a table runs much later,
// and every call the system libraries make in between would find it empty. There the
// original is called directly.
//
// These wrappers are the only place that difference appears. `ops.zig` calls them and
// stays identical on both platforms.

const darwin = if (is_darwin) @import("darwin_libc.zig") else struct {};

pub inline fn callOpen(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.open(path, flags, mode);
    const f = real.open orelse return -1;
    return f(path, flags, mode);
}
pub inline fn callOpenat(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.openat(dirfd, path, flags, mode);
    const f = real.openat orelse return -1;
    return f(dirfd, path, flags, mode);
}
pub inline fn callCreat(path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.creat(path, mode);
    const f = real.creat orelse return -1;
    return f(path, mode);
}
pub inline fn callWrite(fd: c_int, buf: [*]const u8, n: usize) isize {
    if (is_darwin) return darwin.write(fd, buf, n);
    const f = real.write orelse return -1;
    return f(fd, buf, n);
}
pub inline fn callPwrite(fd: c_int, buf: [*]const u8, n: usize, off: i64) isize {
    if (is_darwin) return darwin.pwrite(fd, buf, n, off);
    const f = real.pwrite orelse return -1;
    return f(fd, buf, n, off);
}
pub inline fn callWritev(fd: c_int, iov: *const anyopaque, cnt: c_int) isize {
    if (is_darwin) return darwin.writev(fd, iov, cnt);
    const f = real.writev orelse return -1;
    return f(fd, iov, cnt);
}
pub inline fn callRename(old: [*:0]const u8, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.rename(old, new);
    const f = real.rename orelse return -1;
    return f(old, new);
}
pub inline fn callRenameat(od: c_int, old: [*:0]const u8, nd: c_int, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.renameat(od, old, nd, new);
    const f = real.renameat orelse return -1;
    return f(od, old, nd, new);
}
pub inline fn callUnlink(path: [*:0]const u8) c_int {
    if (is_darwin) return darwin.unlink(path);
    const f = real.unlink orelse return -1;
    return f(path);
}
pub inline fn callUnlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    if (is_darwin) return darwin.unlinkat(dirfd, path, flags);
    const f = real.unlinkat orelse return -1;
    return f(dirfd, path, flags);
}
pub inline fn callFsync(fd: c_int) c_int {
    if (is_darwin) return darwin.fsync(fd);
    const f = real.fsync orelse return -1;
    return f(fd);
}
pub inline fn callFdatasync(fd: c_int) c_int {
    // Darwin has no fdatasync; fsync is the honest equivalent.
    if (is_darwin) return darwin.fsync(fd);
    const f = real.fdatasync orelse return -1;
    return f(fd);
}
pub inline fn callClose(fd: c_int) c_int {
    if (is_darwin) return darwin.close(fd);
    const f = real.close orelse return -1;
    return f(fd);
}
pub inline fn callFtruncate(fd: c_int, len: i64) c_int {
    if (is_darwin) return darwin.ftruncate(fd, len);
    const f = real.ftruncate orelse return -1;
    return f(fd, len);
}
pub inline fn callTruncate(path: [*:0]const u8, len: i64) c_int {
    if (is_darwin) return darwin.truncate(path, len);
    const f = real.truncate orelse return -1;
    return f(path, len);
}
pub inline fn callMkdir(path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.mkdir(path, mode);
    const f = real.mkdir orelse return -1;
    return f(path, mode);
}
pub inline fn callMkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.mkdirat(dirfd, path, mode);
    const f = real.mkdirat orelse return -1;
    return f(dirfd, path, mode);
}
pub inline fn callRmdir(path: [*:0]const u8) c_int {
    if (is_darwin) return darwin.rmdir(path);
    const f = real.rmdir orelse return -1;
    return f(path);
}
pub inline fn callFork() c_int {
    if (is_darwin) return darwin.fork();
    const f = real.fork orelse return -1;
    return f();
}
pub inline fn callVfork() c_int {
    if (is_darwin) return darwin.vfork();
    const f = real.vfork orelse return -1;
    return f();
}
pub inline fn callExecve(p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execve(p, a, e);
    const f = real.execve orelse return -1;
    return f(p, a, e);
}
pub inline fn callExecv(p: [*:0]const u8, a: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execv(p, a);
    const f = real.execv orelse return -1;
    return f(p, a);
}
pub inline fn callExecvp(p: [*:0]const u8, a: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execvp(p, a);
    const f = real.execvp orelse return -1;
    return f(p, a);
}
pub inline fn callPosixSpawn(pid: ?*anyopaque, p: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.posix_spawn(pid, p, fa, at, a, e);
    const f = real.posix_spawn orelse return -1;
    return f(pid, p, fa, at, a, e);
}
pub inline fn callPosixSpawnp(pid: ?*anyopaque, p: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.posix_spawnp(pid, p, fa, at, a, e);
    const f = real.posix_spawnp orelse return -1;
    return f(pid, p, fa, at, a, e);
}
pub inline fn callPthreadCreate(t: *anyopaque, at: ?*const anyopaque, s: *const anyopaque, arg: ?*anyopaque) c_int {
    if (is_darwin) return darwin.pthread_create(t, at, s, arg);
    const f = real.pthread_create orelse return -1;
    return f(t, at, s, arg);
}

/// Temporary instrumentation for the macOS `mode` investigation. Enabled only when
/// SIDEEYE_DEBUG is set, writes hex directly to fd 2 with no formatting machinery —
/// this has to be safe to call before anything is initialised.
pub fn debugHex(tag: []const u8, v: u32) void {
    if (c.getenv("SIDEEYE_DEBUG") == null) return;
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    if (tag.len < 32) {
        @memcpy(buf[0..tag.len], tag);
        i = tag.len;
    }
    var j: usize = 8;
    while (j > 0) {
        j -= 1;
        const d: u8 = @intCast((v >> @intCast(j * 4)) & 0xf);
        buf[i] = if (d < 10) '0' + d else 'a' + d - 10;
        i += 1;
    }
    buf[i] = '\n';
    i += 1;
    _ = callWrite(2, &buf, i);
}

/// Boundary detectors carry no path: their presence alone forces UNKNOWN.
pub fn noteBoundary(op: contract.OpClass) void {
    if (!active or busy) return;
    busy = true;
    defer busy = false;
    writeRecord(.{ .op = op, .seq = 0, .path = "", .aux = "" });
}
