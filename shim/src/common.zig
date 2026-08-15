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
    /// Read live for every record, never cached: a forked child inherits every global
    /// in this file, and a cached pid would be the parent's — in the one process the
    /// pid field exists to tell apart.
    pub extern "c" fn getpid() c_int;
    pub extern "c" fn getpgrp() c_int;
    pub extern "c" fn getpgid(pid: c_int) c_int;
    /// macOS only: asks a descriptor for its path.
    ///
    /// Variadic, as C declares it. A fixed third argument was the third instance of the
    /// same ABI mistake in this codebase: on arm64 the buffer pointer went into a
    /// register the callee never read, `F_GETPATH` failed, and every fd-based operation
    /// (`write`, `fsync`, `close`) was silently dropped from the trace — macOS counted
    /// three operations where Linux counted five, with nothing reporting an error.
    pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    /// Not interposed, so the extern reaches libc directly on both platforms. Used by
    /// the stdio wrappers to hand a stream's descriptor to `noteFd`.
    pub extern "c" fn fileno(stream: *FILE) c_int;
};

const SEEK_END: c_int = 2;
/// Darwin's F_GETPATH. The buffer must hold at least PATH_MAX (1024) bytes.
const F_GETPATH: c_int = 50;
const darwin_path_max: usize = 1024;
/// These three predate the Linux/BSD split and share values everywhere.
const F_DUPFD: c_int = 0;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

/// `RTLD_NEXT` is `((void *) -1)`: resolve the symbol in the search order *after* us,
/// which is how we reach the real libc function we just replaced.
pub const rtld_next: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));

pub const AT_FDCWD: c_int = if (builtin.os.tag == .macos) -2 else -100;
/// Also platform-specific, and getting it wrong is quiet: `unlinkat` with this flag is
/// a directory removal, and misreading it records `.unlink` where Linux records
/// `.rmdir` — a parity claim that fails only for targets which remove directories.
pub const AT_REMOVEDIR: c_int = if (builtin.os.tag == .macos) 0x0080 else 0x200;
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
/// The access-mode mask and O_TRUNC agree across Linux and Darwin; O_CREAT does not
/// and is branched above.
const O_ACCMODE: c_int = 0o3;
const O_TRUNC: c_int = if (is_darwin) 0x400 else 0o1000;

/// Is this open capable of changing state? (ADR 0003)
///
/// True iff the access mode is not read-only, or the call can create or truncate. The
/// oracle applies the same predicate textually (`isReadOnlyOpen`, src/oracle.zig) —
/// the two must stay in agreement, and the acceptance suite's mutation pair is the
/// standing drift detector. Notes pinned by the tests below: `O_RDONLY|O_CREAT`
/// (creates but cannot write) is write-capable; `O_APPEND` alone is not (append
/// without write access cannot write); an invalid access mode of 3 lands on the
/// write-capable side — the unparseable errs toward being counted.
pub fn openIsWriteCapable(flags: c_int) bool {
    if ((flags & O_ACCMODE) != 0) return true; // O_RDONLY == 0
    return (flags & (O_CREAT | O_TRUNC)) != 0;
}

test "the write-capability predicate, pinned case by case" {
    try std.testing.expect(!openIsWriteCapable(0)); // O_RDONLY
    try std.testing.expect(openIsWriteCapable(O_WRONLY));
    try std.testing.expect(openIsWriteCapable(0o2)); // O_RDWR
    try std.testing.expect(openIsWriteCapable(O_CREAT)); // creates, cannot write
    try std.testing.expect(openIsWriteCapable(O_TRUNC));
    try std.testing.expect(!openIsWriteCapable(O_APPEND)); // append without write access
    try std.testing.expect(!openIsWriteCapable(O_CLOEXEC));
    try std.testing.expect(openIsWriteCapable(0o3)); // invalid accmode: err toward counting
    try std.testing.expect(openIsWriteCapable(O_WRONLY | O_CREAT | O_TRUNC));
}

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
pub const LinkFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int;
pub const LinkatFn = *const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, c_int) callconv(.c) c_int;
pub const SymlinkFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int;
pub const SymlinkatFn = *const fn ([*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int;
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
pub const SetsidFn = *const fn () callconv(.c) c_int;
pub const SetpgidFn = *const fn (c_int, c_int) callconv(.c) c_int;

// --- stdio, at flush granularity (ADR 0005) ----------------------------------------

pub const FILE = opaque {};
pub const FopenFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) ?*FILE;
pub const FreopenFn = *const fn (?[*:0]const u8, [*:0]const u8, *FILE) callconv(.c) ?*FILE;
pub const FflushFn = *const fn (?*FILE) callconv(.c) c_int;
pub const FcloseFn = *const fn (*FILE) callconv(.c) c_int;
pub const FpendingFn = *const fn (*FILE) callconv(.c) usize;
pub const FseekFn = *const fn (*FILE, c_long, c_int) callconv(.c) c_int;
pub const FseekoFn = *const fn (*FILE, i64, c_int) callconv(.c) c_int;
pub const RewindFn = *const fn (*FILE) callconv(.c) void;
pub const FsetposFn = *const fn (*FILE, *const anyopaque) callconv(.c) c_int;

/// A stream's write capability, from its fopen mode string (C11 7.21.5.3): the mode
/// begins 'r', 'w' or 'a', optionally followed by 'b', '+' and platform extensions.
/// Only a plain 'r' without '+' is read-only. Unknown shapes err toward write-capable —
/// the unparseable is counted, the same stance as `openIsWriteCapable`. The oracle
/// needs no matching text predicate: for every *valid* mode it classifies the openat
/// this fopen issues, whose flags say the same thing ("r" opens O_RDONLY and is
/// excluded on both sides). An invalid mode is the one shape the two can disagree on —
/// libc fails it with EINVAL before any syscall, so the recorded `.open` has no
/// counterpart and the run ends in a divergence UNKNOWN, which is the fail-closed
/// direction, not a verdict.
pub fn modeIsWriteCapable(mode: [*:0]const u8) bool {
    const m = std.mem.span(mode);
    if (m.len == 0) return true; // unparseable: err toward counting
    if (m[0] != 'r') return true; // 'w', 'a', and anything unknown
    for (m[1..]) |ch| {
        if (ch == '+') return true;
    }
    return false;
}

test "the mode-string predicate, pinned case by case" {
    try std.testing.expect(!modeIsWriteCapable("r"));
    try std.testing.expect(!modeIsWriteCapable("rb"));
    try std.testing.expect(!modeIsWriteCapable("re")); // glibc close-on-exec extension
    try std.testing.expect(modeIsWriteCapable("r+"));
    try std.testing.expect(modeIsWriteCapable("rb+"));
    try std.testing.expect(modeIsWriteCapable("r+b"));
    try std.testing.expect(modeIsWriteCapable("w"));
    try std.testing.expect(modeIsWriteCapable("wx"));
    try std.testing.expect(modeIsWriteCapable("a"));
    try std.testing.expect(modeIsWriteCapable("w+"));
    try std.testing.expect(modeIsWriteCapable("")); // unparseable errs toward counting
    try std.testing.expect(modeIsWriteCapable("z"));
}

/// `__fpending`, resolved at runtime on both platforms and never guessed. glibc and
/// musl ship it; macOS may not, and falls back to the SDK-public `__sFILE` fields.
var fpending: ?FpendingFn = null;

/// The head of Darwin's `struct __sFILE`, as the SDK's <stdio.h> declares it. Only the
/// fields up to `_bf` are read. The layout has been ABI-stable for decades; the pin
/// test below writes into a real stream and fails loudly the day that stops being true.
const DarwinSFile = extern struct {
    p: ?[*]u8,
    r: c_int,
    w: c_int,
    flags: c_short,
    file: c_short,
    bf_base: ?[*]u8,
    bf_size: c_int,
};
/// __SWR: the stream is open for writing. A read stream's `_p` also sits past its
/// buffer base, so without this check a read position would masquerade as pending
/// output and every fclose of a read stream would invent a write.
const darwin_swr: c_short = 0x0008;

fn darwinPending(stream: *FILE) usize {
    const s: *const DarwinSFile = @ptrCast(@alignCast(stream));
    if ((s.flags & darwin_swr) == 0) return 0;
    const p = s.p orelse return 0;
    const base = s.bf_base orelse return 0;
    if (@intFromPtr(p) <= @intFromPtr(base)) return 0;
    return @intFromPtr(p) - @intFromPtr(base);
}

/// stdio recording is armed only when the pending-bytes question can be answered.
/// Without `__fpending` (Linux) the shim records nothing stdio-shaped and behaves
/// exactly as v4 did — the oracle still refuses stdio targets rather than misjudging
/// them. macOS always has the `__sFILE` fallback.
pub fn stdioActive() bool {
    if (is_darwin) return true;
    return fpending != null;
}

fn pendingBytes(stream: *FILE) usize {
    if (fpending) |f| return f(stream);
    if (is_darwin) return darwinPending(stream);
    return 0; // unreachable while stdioActive() gates every caller
}

/// The flush is where buffered bytes become one write(2) (ADR 0005): record `.write`
/// iff the stream holds pending output. Recording an empty flush would invent an
/// operation the oracle never sees — the pending check is a correctness requirement,
/// not an optimisation.
///
/// The `active`/`busy` refusal comes first, before any look at the stream's internals:
/// `noteFd` would refuse the record anyway, but an inactive or re-entered shim must
/// not so much as read `__sFILE` fields of a stream it was never armed to observe.
pub fn noteStdioFlush(stream: *FILE) void {
    if (!active or busy) return;
    if (!stdioActive()) return;
    if (pendingBytes(stream) == 0) return;
    noteFd(.write, c.fileno(stream));
}

pub fn noteStdioClose(stream: *FILE) void {
    if (!active or busy) return;
    if (!stdioActive()) return;
    noteFd(.close, c.fileno(stream));
}

/// Whether a flush is due, for the freopen wrapper's explicit pre-flush. Same guards
/// as noteStdioFlush: an inactive shim answers "no" without touching the stream.
pub fn stdioHasPending(stream: *FILE) bool {
    if (!active or busy) return false;
    if (!stdioActive()) return false;
    return pendingBytes(stream) != 0;
}

test "pending bytes are read from a real stream, not assumed" {
    // The one place the shim depends on stdio internals. On Linux this exercises the
    // dlsym'd __fpending; on macOS, whichever of __fpending / __sFILE the init chose.
    // Failing here means the pending source is wrong for this platform — which must be
    // a loud test failure, never a quiet phantom write in a trace.
    if (fpending == null and !is_darwin) fpending = lookup(FpendingFn, "__fpending");
    if (!stdioActive()) return error.SkipZigTest;

    const path = "/tmp/sideeye-fpending-test";
    const f = std.c.fopen(path, "w") orelse return error.SkipZigTest;
    const stream: *FILE = @ptrCast(f);
    try std.testing.expectEqual(@as(usize, 0), pendingBytes(stream));
    _ = std.c.fwrite("ab", 1, 2, f);
    try std.testing.expectEqual(@as(usize, 2), pendingBytes(stream));
    _ = std.c.fclose(f);

    // Control: a read stream never reports pending output, whatever its position.
    const rf = std.c.fopen(path, "r") orelse return error.SkipZigTest;
    const rstream: *FILE = @ptrCast(rf);
    var buf: [1]u8 = undefined;
    _ = std.c.fread(&buf, 1, 1, rf);
    try std.testing.expectEqual(@as(usize, 0), pendingBytes(rstream));
    _ = std.c.fclose(rf);
    _ = std.c.unlink(path);
}

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
    link: ?LinkFn = null,
    linkat: ?LinkatFn = null,
    symlink: ?SymlinkFn = null,
    symlinkat: ?SymlinkatFn = null,
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
    setsid: ?SetsidFn = null,
    setpgid: ?SetpgidFn = null,
    fopen: ?FopenFn = null,
    fopen64: ?FopenFn = null,
    freopen: ?FreopenFn = null,
    freopen64: ?FreopenFn = null,
    fflush: ?FflushFn = null,
    fflush_unlocked: ?FflushFn = null,
    fclose: ?FcloseFn = null,
    fseek: ?FseekFn = null,
    fseeko: ?FseekoFn = null,
    fseeko64: ?FseekoFn = null,
    rewind: ?RewindFn = null,
    fsetpos: ?FsetposFn = null,
    fsetpos64: ?FsetposFn = null,
} = .{};

var state_dir_buf: [contract.max_path]u8 = undefined;
var state_dir_len: usize = 0;
/// A second spelling of the same directory; empty when there is only one.
var alt_dir_buf: [contract.max_path]u8 = undefined;
var alt_dir_len: usize = 0;
var trace_fd: c_int = -1;
var kill_at: u32 = 0;
var seq: u32 = 0;
var active: bool = false;
/// The pid this shim instance initialised in. Only that process may raise the kill.
///
/// A forked child inherits this value but answers `getpid()` differently, so it can
/// never arm — which is the point: `SIDEEYE_KILL_AT` names the k-th operation *of the
/// subject*, and a child that counted its own operations to k would kill the wrong
/// process at an address that belongs to nobody. A spawned or exec'd child re-runs
/// `init()` and does arm itself; that is tolerable because the kill only fires on a
/// state-directory operation, and a child's state-directory operation already makes the
/// engine refuse the run (`child_touched_state_dir`) — the arm can only go off in a
/// world that is thrown away.
var armed_pid: c_int = -1;

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
    real.link = lookup(LinkFn, "link");
    real.linkat = lookup(LinkatFn, "linkat");
    real.symlink = lookup(SymlinkFn, "symlink");
    real.symlinkat = lookup(SymlinkatFn, "symlinkat");
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
    real.setsid = lookup(SetsidFn, "setsid");
    real.setpgid = lookup(SetpgidFn, "setpgid");
    real.fopen = lookup(FopenFn, "fopen");
    real.fopen64 = lookup(FopenFn, "fopen64");
    real.freopen = lookup(FreopenFn, "freopen");
    real.freopen64 = lookup(FreopenFn, "freopen64");
    real.fflush = lookup(FflushFn, "fflush");
    real.fflush_unlocked = lookup(FflushFn, "fflush_unlocked");
    real.fclose = lookup(FcloseFn, "fclose");
    real.fseek = lookup(FseekFn, "fseek");
    real.fseeko = lookup(FseekoFn, "fseeko");
    real.fseeko64 = lookup(FseekoFn, "fseeko64");
    real.rewind = lookup(RewindFn, "rewind");
    real.fsetpos = lookup(FsetposFn, "fsetpos");
    real.fsetpos64 = lookup(FsetposFn, "fsetpos64");
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

    // Both platforms ask for __fpending at runtime rather than assuming it. Recording
    // paths are gated on `active`, which is only set at the end of this function, so a
    // constructor-time dlsym is safe even on macOS, where call-through must not depend
    // on tables like this one (see darwin_libc.zig).
    fpending = lookup(FpendingFn, "__fpending");

    const sd = c.getenv(contract.env.state_dir) orelse return;
    const tp = c.getenv(contract.env.trace_path) orelse return;

    const sd_slice = std.mem.span(sd);
    if (sd_slice.len == 0 or sd_slice.len > contract.max_path) return;
    const normalized = contract.normalizePath(&state_dir_buf, "/", sd_slice) catch return;
    state_dir_len = normalized.len;

    if (c.getenv(contract.env.state_dir_alt)) |alt| {
        const a = std.mem.span(alt);
        if (a.len != 0 and a.len <= contract.max_path) {
            if (contract.normalizePath(&alt_dir_buf, "/", a)) |n| {
                // Identical spellings would make `canonical` copy a path onto itself for
                // no reason; only a genuinely different one is worth carrying.
                if (!std.mem.eql(u8, n, normalized)) alt_dir_len = n.len;
            } else |_| {}
        }
    }

    trace_fd = callOpen(tp, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644);
    if (trace_fd < 0) return;

    // The channel's one weakness is its number: the shim holds trace_fd as an integer,
    // and a target that closes that number — daemonize loops sweep 3..255 as ordinary
    // hygiene — leaves later trace writes landing in whatever file inherits it.
    // Measured before this guard existed: a state file with trace records spliced
    // between its own bytes. Two moves shrink that surface. The descriptor is
    // relocated above the range hygiene sweeps reach, and a close() of the relocated
    // number is treated as the channel dying (noteTraceClose) rather than ignored.
    // The fallback floor exists because a 256-descriptor rlimit — the macOS default —
    // rejects F_DUPFD at 900; if both floors fail the low number is kept, and a sweep
    // that reaches it still ends in refusal, never in a silent half-account.
    relocate: {
        for ([_]c_int{ 900, 200 }) |floor| {
            const high = c.fcntl(trace_fd, F_DUPFD, floor);
            if (high < 0) continue;
            _ = c.fcntl(high, F_SETFD, FD_CLOEXEC);
            _ = callClose(trace_fd);
            trace_fd = high;
            break :relocate;
        }
    }

    if (c.getenv(contract.env.kill_at)) |k| kill_at = parseU32(std.mem.span(k));

    armed_pid = c.getpid();

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
    writeRecord(.shim_ready, 0, stateDir(), "");
}

pub fn stateDir() []const u8 {
    return state_dir_buf[0..state_dir_len];
}

fn altDir() []const u8 {
    return alt_dir_buf[0..alt_dir_len];
}

/// Is this path inside the state directory, under either spelling of it?
pub fn isInState(path: []const u8) bool {
    if (contract.isInsideDir(path, stateDir())) return true;
    return alt_dir_len != 0 and contract.isInsideDir(path, altDir());
}

/// Rewrite a path under the alternative spelling into the canonical one.
///
/// Containment has to accept both spellings, but the *trace* must hold one: the engine
/// compares paths textually to place crash points, and a run that recorded
/// `/tmp/x/key.json` for the unlink and `/private/tmp/x/key.json` for the open would
/// describe two files where the target touched one.
///
/// Returns `path` unchanged when it is already canonical or outside both.
fn canonical(out: []u8, path: []const u8) []const u8 {
    if (alt_dir_len == 0) return path;
    if (contract.isInsideDir(path, stateDir())) return path;
    if (!contract.isInsideDir(path, altDir())) return path;
    const tail = path[alt_dir_len..];
    const sd = stateDir();
    if (sd.len + tail.len > out.len) return path;
    @memcpy(out[0..sd.len], sd);
    @memcpy(out[sd.len..][0..tail.len], tail);
    return out[0 .. sd.len + tail.len];
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

/// The pid is taken here, once for every record, rather than accepted from the caller:
/// there is exactly one correct value and it is whoever is executing this line.
fn writeRecord(op: contract.OpClass, s: u32, path: []const u8, aux: []const u8) void {
    const rec: contract.Record = .{
        .op = op,
        .seq = s,
        .pid = @bitCast(c.getpid()),
        .path = path,
        .aux = aux,
    };
    const n = contract.encodeRecord(&record_buf, rec) catch return;
    _ = writeAll(record_buf[0..n]);
}

/// The target is closing the shim's own trace descriptor.
///
/// That is legal behaviour — descriptor-hygiene sweeps close numbers they never
/// opened — but it ends observation, and the cost of ignoring it is measured: the
/// number gets re-used for a target file, and the shim's later trace writes land
/// inside it. So the channel announces its death while the descriptor still works
/// (`unresolved`, which the engine refuses on) and then goes silent: with trace_fd
/// at -1, `writeAll` drops everything, and nothing is ever written through a number
/// the target now owns. Called from every wrapper that retires a descriptor —
/// close, fclose, freopen — before the real call retires it.
pub fn noteTraceClose(fd: c_int) void {
    if (!active or fd < 0 or fd != trace_fd) return;
    writeRecord(.unresolved, 0, "trace:closed-by-target", "");
    trace_fd = -1;
}

const deleted_suffix = " (deleted)";

/// Absolute path of an open descriptor — `/proc/self/fd/N` on Linux, `F_GETPATH` on
/// macOS.
///
/// Callers ask `fdKind` first (contract v8), so the descriptors that reach this
/// function are the ones fstat proved to be regular files or directories. A null
/// here is therefore always a failed measurement on something real — never proof of
/// innocence — and both callers record it as `unresolved` so the engine refuses.
///
/// A descriptor whose file has been unlinked reads back as `/path/to/file (deleted)`
/// on Linux. That case sets `deleted` and still returns the path, because the caller
/// needs to know whether it was inside the state directory before deciding what it
/// means. F_GETPATH has no such spelling; on macOS the deleted case is carried by
/// `st_nlink == 0` out of `fdKind` instead.
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
        // The same three-way split as noteFd (contract v8). A proven non-directory
        // base — a socket, a pipe, a dead number — makes the *at() call itself fail
        // without touching anything, so there is nothing to place. A real directory
        // whose path cannot be read back is a failed measurement instead; the first
        // version of this branch answered "not ours" for both (same conflation the
        // review caught in noteFd, found here by the same-class scan).
        switch (fdKind(dirfd, &base_deleted)) {
            .non_path => return null,
            .unresolvable => {
                unresolvable.* = true;
                return null;
            },
            .path_backed => {},
        }
        // A separate flag for fdPath's own answer: it resets its out-param on entry,
        // and letting it share `base_deleted` would erase fdKind's nlink==0 finding —
        // exactly the macOS deleted-directory case that flag exists to carry.
        var base_link_deleted = false;
        const b = fdPath(&base_buf, dirfd, &base_link_deleted) orelse {
            unresolvable.* = true;
            return null;
        };
        if (base_deleted or base_link_deleted) {
            unresolvable.* = isInState(b);
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
    writeRecord(.unresolved, 0, path, "");
}

/// The single place where an operation becomes a counted event, and the single place
/// where the process dies.
fn observe(op: contract.OpClass, raw_path: []const u8, raw_aux: []const u8) void {
    // Both spellings count; one is recorded.
    var pbuf: [contract.max_path]u8 = undefined;
    var abuf: [contract.max_path]u8 = undefined;
    const path = canonical(&pbuf, raw_path);
    const aux = canonical(&abuf, raw_aux);

    var s: u32 = 0;
    if (op.isKillPoint()) {
        // A two-path operation touches the state directory when *either* endpoint is
        // inside it (ADR 0006): a rename or link whose source is inside and whose
        // destination is outside is a real mutation of the state directory, and judging
        // only the first path used to drop it. The two-path property is the contract's,
        // so both observers read the same definition.
        const in_scope = contract.isInsideDir(path, stateDir()) or
            (op.isTwoPath() and aux.len > 0 and contract.isInsideDir(aux, stateDir()));
        if (!in_scope) return;
        seq += 1;
        s = seq;
        // Only the process that initialised this shim instance may die here. A forked
        // child inherits `kill_at` and its own copy of `seq`, and without this guard it
        // would count its own operations up to k and kill *itself* — the engine would
        // then read a kill_landed at the right seq from the wrong process. See
        // `armed_pid` for why a spawned child arming itself is tolerable and this is not.
        if (kill_at != 0 and s == kill_at and c.getpid() == armed_pid) {
            // Landing evidence first, then die. Without this record the claim "we died
            // before the k-th operation" would rest on the engine having set a variable,
            // not on anything the target actually did.
            writeRecord(.kill_landed, s, path, aux);
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
    writeRecord(op, s, path, aux);
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

/// What stands behind a descriptor, asked of fstat before any path query.
///
/// Three answers, and the difference is the contract (v8): a socket, pipe or device
/// is *proof* the operation is not in the state directory — nothing to record. A
/// regular file or directory is path-backed and must go on to name its path. Anything
/// else — including a failed fstat on a descriptor the wrapper was actually handed —
/// is `unresolvable`: an operation that was seen but cannot be placed, which must be
/// recorded so the engine refuses, never silently dropped. (The first version of
/// `noteFd` treated every resolution failure as "not ours"; review caught that a
/// query failure and a proven non-file are different answers wearing one null.)
///
/// `deleted` is set when `st_nlink == 0` — an open, unlinked file. This is what
/// finally closes the macOS gap: F_GETPATH has no "(deleted)" spelling, so nlink is
/// the cross-platform witness that a descriptor's bytes have no snapshot address.
const FdKind = enum { path_backed, non_path, unresolvable };

/// The type and link count behind a descriptor, reached differently per platform:
/// std.c maps Darwin's fstat symbol decoration ($INODE64 on x86_64), but deliberately
/// exports no libc fstat on Linux (`.linux => {}` in std/c.zig — the historical
/// __fxstat indirection), so there the raw statx syscall is the stable spelling. The
/// shim already speaks raw resolution syscalls per operation (the /proc/self/fd
/// readlink below); the oracle's read-only classification absorbs them.
const FdStatResult = union(enum) { ok: struct { mode: u32, nlink: u32 }, bad_fd: void, failed: void };

const EBADF: c_int = 9; // same value on Linux and Darwin

fn fdStat(fd: c_int) FdStatResult {
    if (is_darwin) {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) {
            if (std.c._errno().* == EBADF) return .bad_fd;
            return .failed;
        }
        return .{ .ok = .{ .mode = @intCast(st.mode), .nlink = @intCast(st.nlink) } };
    }
    var stx: std.os.linux.Statx = undefined;
    // 0x1000 is AT_EMPTY_PATH: statx the descriptor itself, no path walk.
    const rc = std.os.linux.statx(@intCast(fd), "", 0x1000, .{ .TYPE = true, .NLINK = true }, &stx);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {},
        .BADF => return .bad_fd,
        else => return .failed,
    }
    // The kernel reports which fields it actually filled; a TYPE it did not vouch for
    // is a measurement that did not happen, not a zero to read.
    if (!stx.mask.TYPE) return .failed;
    return .{ .ok = .{ .mode = stx.mode, .nlink = if (stx.mask.NLINK) stx.nlink else 1 } };
}

// The file-type mask and its values agree between Linux and Darwin.
const S_IFMT: u32 = 0o170000;
const S_IFSOCK: u32 = 0o140000;
const S_IFLNK: u32 = 0o120000;
const S_IFREG: u32 = 0o100000;
const S_IFBLK: u32 = 0o060000;
const S_IFDIR: u32 = 0o040000;
const S_IFCHR: u32 = 0o020000;
const S_IFIFO: u32 = 0o010000;

fn fdKind(fd: c_int, deleted: *bool) FdKind {
    switch (fdStat(fd)) {
        // EBADF: there is nothing real behind this number; the operation the wrapper
        // is about to attempt will fail without touching anything.
        .bad_fd => return .non_path,
        // The stat itself failed on a live descriptor: a measurement that could not
        // be taken, never evidence of innocence.
        .failed => return .unresolvable,
        .ok => |st| {
            const m = st.mode & S_IFMT;
            if (m == S_IFSOCK or m == S_IFIFO or m == S_IFCHR or m == S_IFBLK)
                return .non_path;
            // Type bits of zero are the kernel's anon-inode spelling — eventfd,
            // epoll, timerfd, io_uring have no file format on Linux, and nothing
            // that can live in a state directory stats that way (kqueue on macOS
            // reports a FIFO; measured). A symlink descriptor (O_PATH|O_NOFOLLOW)
            // cannot carry a write, truncate or sync. Both are proof of innocence,
            // not failed measurements — before this branch existed, one close() of
            // an eventfd sent the whole run to `unresolvable_path` (measured).
            if (m == 0 or m == S_IFLNK) return .non_path;
            if (m == S_IFREG or m == S_IFDIR) {
                if (st.nlink == 0) deleted.* = true;
                return .path_backed;
            }
            return .unresolvable;
        },
    }
}

/// An fd-addressed operation that was seen but could not be placed. The label names
/// the descriptor because there is no path to name — the point of recording it is
/// that the engine refuses instead of passing.
fn noteUnresolvedFd(fd: c_int) void {
    var b: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&b, "fd:{d}", .{fd}) catch "fd:?";
    noteUnresolved(s);
}

pub fn noteFd(op: contract.OpClass, fd: c_int) void {
    if (!active or busy) return;
    // The ONLY early return keyed on the descriptor itself. Contract v8: no descriptor
    // number is exempt from observation — not 0/1/2 (a target can dup2 a state file
    // onto any of them; measured as a false PASS before this change), and not the
    // trace fd, whose number a target can close and re-use for a state file. The
    // trace channel protects itself instead of asking for an exemption here: its
    // descriptor is relocated above the hygiene-sweep range at init, and a close()
    // of it announces the channel's death (noteTraceClose) so the engine refuses.
    // Where a descriptor points is decided by asking the kernel, below, every time.
    if (fd < 0) return;
    busy = true;
    defer busy = false;

    var deleted = false;
    switch (fdKind(fd, &deleted)) {
        // Proof, not uncertainty: sockets, pipes and devices are not state-directory
        // entries, so an operation through one is legitimately none of our business.
        .non_path => return,
        .unresolvable => {
            noteUnresolvedFd(fd);
            return;
        },
        .path_backed => {},
    }

    var buf: [contract.max_path]u8 = undefined;
    var link_deleted = false;
    const resolved = fdPath(&buf, fd, &link_deleted) orelse {
        // A regular file or directory whose path could not be read back. That is a
        // failed measurement, not evidence of innocence — recorded, so the engine
        // refuses to judge a run whose operations it cannot place.
        noteUnresolvedFd(fd);
        return;
    };
    if (!isInState(resolved)) return;
    if (deleted or link_deleted) {
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
pub inline fn callLink(old: [*:0]const u8, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.link(old, new);
    const f = real.link orelse return -1;
    return f(old, new);
}
pub inline fn callLinkat(od: c_int, old: [*:0]const u8, nd: c_int, new: [*:0]const u8, flags: c_int) c_int {
    if (is_darwin) return darwin.linkat(od, old, nd, new, flags);
    const f = real.linkat orelse return -1;
    return f(od, old, nd, new, flags);
}
pub inline fn callSymlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int {
    if (is_darwin) return darwin.symlink(target, linkpath);
    const f = real.symlink orelse return -1;
    return f(target, linkpath);
}
pub inline fn callSymlinkat(target: [*:0]const u8, newdirfd: c_int, linkpath: [*:0]const u8) c_int {
    if (is_darwin) return darwin.symlinkat(target, newdirfd, linkpath);
    const f = real.symlinkat orelse return -1;
    return f(target, newdirfd, linkpath);
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
/// The real `vfork`, returned rather than called.
///
/// Every other wrapper goes through a `call*` function here. `vfork` cannot: any frame
/// alive across its double return is corrupted by the child running on the shared stack,
/// so the *exported wrapper itself* must make the call — as a guaranteed tail call, with
/// this function inlined into it. See `ops.vfork` for the measurements.
pub inline fn realVfork() ?ForkFn {
    if (is_darwin) return darwin.vfork;
    return real.vfork;
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
pub inline fn callSetsid() c_int {
    if (is_darwin) return darwin.setsid();
    const f = real.setsid orelse return -1;
    return f();
}
pub inline fn callSetpgid(pid: c_int, pgid: c_int) c_int {
    if (is_darwin) return darwin.setpgid(pid, pgid);
    const f = real.setpgid orelse return -1;
    return f(pid, pgid);
}
pub inline fn callFopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.fopen(path, mode));
    const f = real.fopen orelse return null;
    return f(path, mode);
}
pub inline fn callFopen64(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE {
    // Never installed on macOS (no such symbol there); routed to fopen for the sake of
    // compiling one ops.zig for both platforms.
    if (is_darwin) return @ptrCast(darwin.fopen(path, mode));
    const f = real.fopen64 orelse return null;
    return f(path, mode);
}
pub inline fn callFreopen(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *FILE) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.freopen(path, mode, @ptrCast(stream)));
    const f = real.freopen orelse return null;
    return f(path, mode, stream);
}
pub inline fn callFreopen64(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *FILE) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.freopen(path, mode, @ptrCast(stream)));
    const f = real.freopen64 orelse return null;
    return f(path, mode, stream);
}
pub inline fn callFflush(stream: ?*FILE) c_int {
    if (is_darwin) return darwin.fflush(@ptrCast(stream));
    const f = real.fflush orelse return -1;
    return f(stream);
}
pub inline fn callFflushUnlocked(stream: ?*FILE) c_int {
    if (is_darwin) return darwin.fflush(@ptrCast(stream));
    const f = real.fflush_unlocked orelse return -1;
    return f(stream);
}
pub inline fn callFclose(stream: *FILE) c_int {
    if (is_darwin) return darwin.fclose(@ptrCast(stream));
    const f = real.fclose orelse return -1;
    return f(stream);
}
pub inline fn callFseek(stream: *FILE, off: c_long, whence: c_int) c_int {
    if (is_darwin) return darwin.fseek(@ptrCast(stream), off, whence);
    const f = real.fseek orelse return -1;
    return f(stream, off, whence);
}
pub inline fn callFseeko(stream: *FILE, off: i64, whence: c_int) c_int {
    if (is_darwin) return darwin.fseeko(@ptrCast(stream), off, whence);
    const f = real.fseeko orelse return -1;
    return f(stream, off, whence);
}
pub inline fn callFseeko64(stream: *FILE, off: i64, whence: c_int) c_int {
    if (is_darwin) return darwin.fseeko(@ptrCast(stream), off, whence);
    const f = real.fseeko64 orelse return -1;
    return f(stream, off, whence);
}
pub inline fn callRewind(stream: *FILE) void {
    if (is_darwin) return darwin.rewind(@ptrCast(stream));
    const f = real.rewind orelse return;
    return f(stream);
}
pub inline fn callFsetpos(stream: *FILE, pos: *const anyopaque) c_int {
    if (is_darwin) return darwin.fsetpos(@ptrCast(stream), pos);
    const f = real.fsetpos orelse return -1;
    return f(stream, pos);
}
pub inline fn callFsetpos64(stream: *FILE, pos: *const anyopaque) c_int {
    if (is_darwin) return darwin.fsetpos(@ptrCast(stream), pos);
    const f = real.fsetpos64 orelse return -1;
    return f(stream, pos);
}

/// Record that a `linkat(…, AT_EMPTY_PATH)` linked a descriptor rather than a named
/// source: its old path is empty, so there is nothing to resolve or place, and the
/// engine must refuse rather than judge a link it cannot address (ADR 0006). Recorded
/// even where an oracle would also catch it, so the platform with no oracle refuses too.
pub fn noteLinkByDescriptor() void {
    if (!active or busy) return;
    busy = true;
    defer busy = false;
    noteUnresolved("");
}

/// Boundary detectors carry no path. Since v3 their presence no longer forces UNKNOWN
/// by itself — the engine decides, with the oracle's help, whether the boundary was
/// tolerable — but they must still all be recorded, because "no boundary seen" is an
/// input to that decision.
pub fn noteBoundary(op: contract.OpClass) void {
    if (!active or busy) return;
    busy = true;
    defer busy = false;
    writeRecord(op, 0, "", "");
}

// ---------------------------------------------------------------------------------

/// Set the two spellings directly. `init()` reads them from the environment, which a
/// test cannot arrange without a child process.
fn setDirsForTest(canonical_dir: []const u8, alt: []const u8) void {
    @memcpy(state_dir_buf[0..canonical_dir.len], canonical_dir);
    state_dir_len = canonical_dir.len;
    @memcpy(alt_dir_buf[0..alt.len], alt);
    alt_dir_len = alt.len;
}

test "both spellings of the state directory are inside it" {
    setDirsForTest("/private/tmp/x/state", "/tmp/x/state");
    defer setDirsForTest("", "");

    try std.testing.expect(isInState("/private/tmp/x/state/key.json"));
    try std.testing.expect(isInState("/tmp/x/state/key.json"));
    // Component boundaries still hold for the alternative spelling.
    try std.testing.expect(!isInState("/tmp/x/state2/key.json"));
    try std.testing.expect(!isInState("/etc/passwd"));
}

test "a path under the alternative spelling is recorded under the canonical one" {
    setDirsForTest("/private/tmp/x/state", "/tmp/x/state");
    defer setDirsForTest("", "");

    var buf: [contract.max_path]u8 = undefined;
    // The reason this matters: the engine places crash points by comparing recorded
    // paths textually. One file recorded under two spellings reads as two files.
    try std.testing.expectEqualStrings(
        "/private/tmp/x/state/key.json",
        canonical(&buf, "/tmp/x/state/key.json"),
    );
    try std.testing.expectEqualStrings(
        "/private/tmp/x/state/key.json",
        canonical(&buf, "/private/tmp/x/state/key.json"),
    );
    // Outside both: returned untouched, not rewritten into the state directory.
    try std.testing.expectEqualStrings("/etc/passwd", canonical(&buf, "/etc/passwd"));
}

test "with one spelling, canonical is the identity" {
    setDirsForTest("/tmp/x/state", "");
    defer setDirsForTest("", "");

    var buf: [contract.max_path]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/x/state/k", canonical(&buf, "/tmp/x/state/k"));
    try std.testing.expect(isInState("/tmp/x/state/k"));
    try std.testing.expect(!isInState("/private/tmp/x/state/k"));
}
