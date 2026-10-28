//! Everything here runs *inside somebody else's process*, which sets the rules:
//! no heap, no standard-library I/O, no locks, no assumptions about what the target
//! has already initialised. State lives in globals; buffers are fixed and static.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
/// Build-time only (#270). `test_seq_gap` is false in every shipped shim — build.zig
/// hardcodes false into libsideeye_shim's own options module regardless of any -D
/// flag, and true only into the separately named libsideeye_shim_testgap that
/// `-Dtest-seq-gap` additionally produces. There is no runtime knob: an environment
/// variable that could bend the numbering would be a production backdoor.
const shim_build_options = @import("shim_build_options");

const syscalls = if (builtin.os.tag == .linux) @import("syscalls.zig") else struct {
    pub var armed: bool = false;
    pub var guard_signal: bool = false;
    pub fn armGuards() void {}
    pub fn resolveGuards() void {}
    pub const Install = enum { armed, unsupported, failed };
    pub fn installHandler() void {}
    pub fn install() Install {
        return .unsupported;
    }
    pub fn traceWrite(_: c_int, _: [*]const u8, _: usize) isize {
        return -1;
    }
};

/// `syscalls.armed` is the one flag both doors read: the `SIGSYS` handler records only
/// while it is set, and every wrapper whose syscall the filter traps stays silent while
/// it is set. Exactly one of the two counts any operation, in every case — including a
/// process standing in front of a filter it inherited without installing one, where the
/// flag is false, the handler only re-issues, and the wrappers count.
///
/// Two writers are outside the trap set and their wrappers keep recording unconditionally:
/// `copy_file_range` and `pwritev2` take six arguments, which leaves the filter no free
/// register for the re-issue sentinel. `pwritev2` is handled a third way on top of that —
/// refused rather than counted, for the reason spelled out where its wrapper is
/// (`ops.zig`): neither counting it nor silencing it is correct on both kernels.
pub inline fn countedAtSyscall() bool {
    return syscalls.armed;
}

pub const c = struct {
    pub extern "c" fn dlsym(handle: ?*anyopaque, symbol: [*:0]const u8) ?*anyopaque;
    pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
    pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
    pub extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
    pub extern "c" fn raise(sig: c_int) c_int;
    /// Sent with pid 0 — the caller's own process group — when a world reaches its crash
    /// point (v15). `raise` would kill only the process that got there, and the shell
    /// that spawned it would carry on to the next command.
    pub extern "c" fn kill(pid: c_int, sig: c_int) c_int;
    pub extern "c" fn _exit(status: c_int) noreturn;
    pub extern "c" fn usleep(usec: c_uint) c_int;
    pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
    /// Positional because the read must not depend on where the descriptor happens to be:
    /// the offset is shared with a forked child, and `refreshCount` moves it itself with
    /// `lseek(SEEK_END)` to find the file's size. Moving it is harmless — every write here
    /// is `O_APPEND`, which ignores the offset — and `init` reads it once for the same
    /// reason (an offset of zero means nobody has written the header yet), so a read that
    /// consumed it would be the thing that broke.
    pub extern "c" fn pread(fd: c_int, buf: [*]u8, count: usize, offset: i64) isize;
    /// Read live for every record, never cached: a forked child inherits every global
    /// in this file, and a cached pid would be the parent's — in the one process the
    /// pid field exists to tell apart.
    pub extern "c" fn getpid() c_int;
    /// `time_t` is 64-bit on both platforms this builds for.
    pub extern "c" fn time(t: ?*i64) i64;
    /// Only the subject calls these (execSeqCarrySet guards on getpid == armed_pid),
    /// so the heap they may touch is never a vfork parent's shared one.
    pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    pub extern "c" fn getpgrp() c_int;
    pub extern "c" fn getpgid(pid: c_int) c_int;
    /// Variadic, as C declares it. A fixed third argument was the third instance of the
    /// same ABI mistake in this codebase: on arm64 the buffer pointer went into a
    /// register the callee never read, `F_GETPATH` failed, and every fd-based operation
    /// (`write`, `fsync`, `close`) was silently dropped from the trace — macOS counted
    /// three operations where Linux counted five, with nothing reporting an error.
    pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    pub extern "c" fn fileno(stream: *FILE) c_int;
};

const SEEK_END: c_int = 2;
/// Darwin's F_GETPATH. The buffer must hold at least PATH_MAX (1024) bytes.
const F_GETPATH: c_int = 50;
const darwin_path_max: usize = 1024;
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
pub const RENAME_EXCHANGE: c_uint = 2;
pub const RENAME_WHITEOUT: c_uint = 4;
/// Darwin's `renamex_np`/`renameatx_np` flags (v12). The NUMBERS collide with the
/// Linux pair above and the MEANINGS do not: Darwin's 0x4 is `RENAME_EXCL` — the
/// decline-to-clobber flag, `RENAME_NOREPLACE`'s relative, a plain rename this shim
/// records — while Linux's 0x4 is `RENAME_WHITEOUT`, which is refused. Reusing the
/// constants above by value would refuse the allowed flag. Named per-platform so the
/// wrapper reads as the header does.
pub const DARWIN_RENAME_SWAP: c_uint = 0x2;
pub const DARWIN_RENAME_EXCL: c_uint = 0x4;
pub const ATTR_CMN_NAME: u32 = 0x00000001;
const SIGKILL: c_int = 9;

// These differ between the two platforms and getting them wrong is quiet: the trace
// file would open with the wrong semantics — truncating instead of appending, or
// leaking across an exec — and the failure would look like missing records rather than
// like a bad flag.
const is_darwin = builtin.os.tag == .macos;
const O_RDONLY: c_int = 0;
const O_WRONLY: c_int = 0o1;
pub const O_CREAT: c_int = if (is_darwin) 0x200 else 0o100;
const O_APPEND: c_int = if (is_darwin) 0x8 else 0o2000;
const O_CLOEXEC: c_int = if (is_darwin) 0x1000000 else 0o2000000;
pub const O_RDWR: c_int = 0x2;
pub const O_EXCL: c_int = if (is_darwin) 0x800 else 0o200;
pub const O_ACCMODE: c_int = 0o3;
const O_TRUNC: c_int = if (is_darwin) 0x400 else 0o1000;
/// The value differs *within* Linux by architecture — 0o400000 on x86_64, 0o100000 on
/// aarch64 — so the `is_darwin` shape above cannot express it. The engine's copy carried
/// the x86_64 number for all of Linux once, which left the one guard that used it inert on
/// arm64: measured in an arm64 container, a symlink planted at a capture path was opened
/// straight through (#316). The five literals above were checked on three targets then and
/// are right; a sixth written the same way is where the next one goes wrong.
const O_NOFOLLOW: c_int = blk: {
    var f: std.posix.O = .{};
    f.NOFOLLOW = true;
    break :blk @bitCast(f);
};

const O_NONBLOCK: c_int = blk: {
    var f: std.posix.O = .{};
    f.NONBLOCK = true;
    break :blk @bitCast(f);
};

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
pub const PwritevFn = *const fn (c_int, *const anyopaque, c_int, i64) callconv(.c) isize;
pub const Pwritev2Fn = *const fn (c_int, *const anyopaque, c_int, i64, c_int) callconv(.c) isize;
/// The kernel copy primitives (#244). `copy_file_range` is the one whose destination
/// is not the first argument — src/oracle.zig's `fd_write_args` carries the same fact
/// for the other observer.
pub const CopyFileRangeFn = *const fn (c_int, ?*i64, c_int, ?*i64, usize, c_uint) callconv(.c) isize;
pub const SendfileFn = *const fn (c_int, c_int, ?*i64, usize) callconv(.c) isize;
pub const RenameFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int;
pub const RenameatFn = *const fn (c_int, [*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int;
pub const Renameat2Fn = *const fn (c_int, [*:0]const u8, c_int, [*:0]const u8, c_uint) callconv(.c) c_int;
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
/// `pthread_t` by value (v18). An unsigned long on glibc and a pointer on Darwin — both a
/// register-sized integer at the ABI, which is all these wrappers need of it: the value is
/// a key into `joinable`, compared for equality and never dereferenced. POSIX names
/// `pthread_equal` as the comparison; on both libcs the shim runs under it is the integer's.
pub const PthreadJoinFn = *const fn (usize, ?*?*anyopaque) callconv(.c) c_int;
pub const PthreadDetachFn = *const fn (usize) callconv(.c) c_int;
pub const RoutineFn = *const fn (?*anyopaque) callconv(.c) ?*anyopaque;
pub const SetsidFn = *const fn () callconv(.c) c_int;
pub const Open2Fn = *const fn ([*:0]const u8, c_int) callconv(.c) c_int;
pub const Openat2Fn = *const fn (c_int, [*:0]const u8, c_int) callconv(.c) c_int;
pub const ClosefromFn = *const fn (c_int) callconv(.c) void;
pub const CloseRangeFn = *const fn (c_uint, c_uint, c_int) callconv(.c) c_int;
pub const SetpgidFn = *const fn (c_int, c_int) callconv(.c) c_int;

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

const DarwinSFile = extern struct {
    p: ?[*]u8,
    r: c_int,
    w: c_int,
    flags: c_short,
    file: c_short,
    bf_base: ?[*]u8,
    bf_size: c_int,
};
const darwin_swr: c_short = 0x0008;

fn darwinPending(stream: *FILE) usize {
    const s: *const DarwinSFile = @ptrCast(@alignCast(stream));
    if ((s.flags & darwin_swr) == 0) return 0;
    const p = s.p orelse return 0;
    const base = s.bf_base orelse return 0;
    if (@intFromPtr(p) <= @intFromPtr(base)) return 0;
    return @intFromPtr(p) - @intFromPtr(base);
}

fn preInitStream(stream: *FILE) bool {
    if (preInitDecided()) |decided| return decided;
    return preInitFd(c.fileno(stream));
}

/// Whether a write-capable stream open reaches the recording door: once armed, when stdio is
/// observed at all; before, always (#753) — `fpending`, which `stdioActive` asks about, is
/// looked up by the constructor, and a stream a library constructor opened on a state file
/// would otherwise carry no mark.
pub fn stdioOpenRecorded(mode: [*:0]const u8) bool {
    return (stdioActive() or !active) and modeIsWriteCapable(mode);
}

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
    if (!active and !preInitStream(stream)) return;
    if (mine().busy) return;
    if (!stdioActive()) return;
    // The flush's own `write(2)` is trapped and counted by the handler in syscalls mode,
    // so recording it here as well would count one operation twice.
    //
    // Gated HERE and not in `stdioActive()`, which was the first attempt: that predicate
    // also decides whether `fopen` and `freopen` record their `.open` and whether
    // `fclose` records its `.close`, so switching it off cost all three. Measured — the
    // syscalls-mode trace came back with four correct writes and no `.open` and no
    // `.close` at all, while the mode's own writes looked right.
    //
    // `stdioHasPending` deliberately keeps answering truthfully: the freopen wrapper
    // uses it to decide whether to perform an explicit `fflush`, and answering "no"
    // there would change what the target does rather than what the shim records. That
    // flush still happens, its `write(2)` still traps, and the handler still counts it.
    if (countedAtSyscall()) return;
    if (pendingBytes(stream) == 0) return;
    noteFd(.write, c.fileno(stream));
}

pub fn noteStdioClose(stream: *FILE) void {
    if (!active and !preInitStream(stream)) return;
    if (mine().busy) return;
    if (!stdioActive()) return;
    noteFd(.close, c.fileno(stream));
}

pub fn stdioHasPending(stream: *FILE) bool {
    if (!active or mine().busy) return false;
    if (!stdioActive()) return false;
    return pendingBytes(stream) != 0;
}

test "pending bytes are read from a real stream, not assumed" {
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
    pwritev: ?PwritevFn = null,
    pwritev2: ?Pwritev2Fn = null,
    copy_file_range: ?CopyFileRangeFn = null,
    sendfile: ?SendfileFn = null,
    rename: ?RenameFn = null,
    renameat: ?RenameatFn = null,
    renameat2: ?Renameat2Fn = null,
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
    pthread_join: ?PthreadJoinFn = null,
    pthread_detach: ?PthreadDetachFn = null,
    setsid: ?SetsidFn = null,
    setpgid: ?SetpgidFn = null,
    __open_2: ?Open2Fn = null,
    __open64_2: ?Open2Fn = null,
    __openat_2: ?Openat2Fn = null,
    __openat64_2: ?Openat2Fn = null,
    closefrom: ?ClosefromFn = null,
    close_range: ?CloseRangeFn = null,
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
var alt_dir_buf: [contract.max_path]u8 = undefined;
var alt_dir_len: usize = 0;
var trace_fd: c_int = -1;
var kill_at: u32 = 0;
var kill_group: bool = false;
/// The run's cgroup as `/proc/self/cgroup` spells it (v17, #559): the path after `0::`, or
/// empty when the engine gave this spawn no cgroup. Copied out of the environment at init,
/// because the target owns its environment after that and the question is asked again at
/// every boundary and at the crash point.
var run_cgroup_buf: [contract.max_path]u8 = undefined;
var run_cgroup_len: usize = 0;
var kill_cgroup_fd: c_int = -1;
// Not read back from the environment when a sweep's casualty is reopened: the target may have
// changed it by then.
var trace_path_buf: [contract.max_path + 1]u8 = @splat(0);
var trace_path_len: usize = 0;
var trace_identity: ?FileIdentity = null;
var kill_cgroup_path_buf: [contract.max_path + 1]u8 = @splat(0);
var kill_cgroup_path_len: usize = 0;
var kill_aside_path_buf: [contract.max_path + 1]u8 = @splat(0);
var kill_aside_path_len: usize = 0;
var kill_aside_fd: c_int = -1;
/// **Slots keyed by thread id, not `threadlocal`.** A shared object's `threadlocal`
/// compiles to the general-dynamic TLS model, whose first access from a thread takes
/// `__tls_get_addr`'s slow path under the loader's lock; under `--observe syscalls` that
/// first access can happen inside the `SIGSYS` handler, and a lock taken in a signal
/// handler is what this module's rules forbid. Whether it happens depends on the target
/// and on the C library, so a run that worked would prove nothing about the next one. A
/// fixed array keyed by `gettid()` — one syscall, one compare-and-swap — is
/// async-signal-safe by construction. A thread's slot is never freed: nothing here sees a
/// thread end. Only a process that shares the table without owning it — a `vfork` child —
/// gives back the slot it claimed, before its exec; and once the table is full, a slot whose
/// claiming process has exited and been reaped is taken back. The 65th thread shares `reserve`, whose `busy` is the old process-wide guard,
/// and the run records `thread-slots-exhausted` once so the engine refuses it rather
/// than judges it.
///
/// Zero-initialised on purpose, not `undefined`: an all-zero global lands in `.bss`,
/// and sixty-five of these — some 72 KB each since the scratch buffers moved in (#555) —
/// are nearly five megabytes the file need not carry. Only the pages a thread touches
/// become memory.
const ThreadState = struct {
    tid: u64 = 0,
    claimer_pid: c_int = 0,
    /// Guards against observing our own work. The path resolution below calls libc, and
    /// while none of those calls are interposed today, a future addition to the symbol
    /// list would silently start recording the shim's own behaviour as the target's.
    busy: bool = false,
    /// Guards `exec_env` alone (#555): an exec from a signal handler that interrupted the
    /// carry on this thread finds it set and drops its own carry. Not `busy`, which would
    /// also stop the shim recording anything else that handler does — recorded before the
    /// array moved here.
    exec_carrying: bool = false,
    seq: u32 = 0,
    /// How far into the trace `seq` has been read. Only complete records advance it, so a
    /// record still being written is read again next time rather than skipped.
    count_scanned: u64 = 0,
    /// Records this thread has written through this slot (v18) — every class `writeRecord`
    /// writes, counted only when the write went out. A thread this one creates carries the
    /// value as of the `pthread_create` call in its `thread_started` record, and the engine
    /// rebuilds this thread's clock at that point from it (ADR 0067). The engine counts the
    /// same records on its side; the one record written outside `writeRecord`, the slot
    /// exhaustion notice, is counted there and not here, which leaves the engine's count
    /// ahead by one on that thread and every edge drawn from it short — the safe side.
    /// Reset in the fork child with the rest of the slot: a child that inherited its
    /// parent's count would tell the engine a creation happened later than it did.
    written: u32 = 0,
    creates: u32 = 0,
    scan_buf: [contract.max_record_len]u8 = @splat(0),
    /// One record is built here and written with a single `write(2)`, so a trace never
    /// ends with half a record even when the process dies mid-run.
    record_buf: [contract.max_record_len]u8 = @splat(0),

    // Scratch space for path resolution and for the exec carry's rebuilt environment
    // (#555). These were arrays on the TARGET thread's stack — up to twenty kilobytes for
    // one interposed call — and a thread whose stack was x86_64's 16 KiB minimum died
    // under a recording shim while it ran to the end without one. Held here instead, one
    // field per function and none shared, so a chain such as `note2 → resolveAt →
    // observe` is safe without anyone proving which buffers are live together.
    //
    // Per-thread storage is enough because every entry point that uses these takes
    // `busy` before touching them, and `observe` and `resolveAt` are called from those
    // entry points only: a signal handler that re-enters the shim on the same thread
    // returns before it reaches a buffer. That argument covers the path buffers and
    // nothing else. `exec_env` has a flag of its own, `exec_carrying`, and the reserve does
    // not carry at all; `noteTraceClose` and both forms of the exec carry reach
    // `record_buf` and `scan_buf` without `busy`, as they did before. On the reserve,
    // `busy` is one non-atomic flag for every thread past the 64th, so two of them can
    // meet in the path buffers as they already could in `record_buf` — a run the engine
    // refuses on `thread-slots-exhausted`.
    resolve_base: [contract.max_path]u8 = @splat(0),
    observe_path: [contract.max_path]u8 = @splat(0),
    observe_aux: [contract.max_path]u8 = @splat(0),
    note1_path: [contract.max_path]u8 = @splat(0),
    note2_path: [contract.max_path]u8 = @splat(0),
    note2_aux: [contract.max_path]u8 = @splat(0),
    unsup2_path: [contract.max_path]u8 = @splat(0),
    unsup2_canon: [contract.max_path]u8 = @splat(0),
    unsup2_aux: [contract.max_path]u8 = @splat(0),
    unsup2_aux_canon: [contract.max_path]u8 = @splat(0),
    unsup_fd_path: [contract.max_path]u8 = @splat(0),
    fd_path: [contract.max_path]u8 = @splat(0),
    exec_env: [max_env_entries + 1]?[*:0]const u8 = @splat(null),
};
const max_threads = 64;
var slots: [max_threads]ThreadState = @splat(.{});
var reserve: ThreadState = .{};
var exhaustion_announced: bool = false;
var active: bool = false;
var table_pid: c_int = 0;

/// The calling thread's id: `gettid` on Linux, `pthread_threadid_np` on Darwin. A raw
/// syscall on Linux, which is what makes `mine` safe to call from the `SIGSYS` handler.
/// 64 bits because a Mach thread id is not bounded by the width of a pid — the same
/// reason the oracle's `Event.id` is.
pub fn currentTid() u64 {
    if (is_darwin) {
        var t: u64 = 0;
        _ = darwin.pthread_threadid_np(null, &t);
        return t;
    }
    return @intCast(std.os.linux.gettid());
}

fn mine() *ThreadState {
    const tid = currentTid();
    // Two passes, not one that takes the first free slot on the way: an exec gives a slot back
    // mid-table, and a thread whose own slot lies past it would claim a second one and leave
    // its counts behind in the first.
    for (&slots) |*s| if (@atomicLoad(u64, &s.tid, .acquire) == tid and adopt(s)) return s;
    for (&slots) |*s| {
        // Our own id again here too: a signal handler that interrupted this pass may have claimed
        // a slot for this thread, and passing over it would give the thread a second one.
        const owner = @atomicLoad(u64, &s.tid, .acquire);
        if (owner == tid and adopt(s)) return s;
        if (owner == 0 and @cmpxchgStrong(u64, &s.tid, 0, tid, .acq_rel, .acquire) == null) {
            @atomicStore(c_int, &s.claimer_pid, c.getpid(), .release);
            return s;
        }
    }
    if (reclaimDeparted(tid)) |s| return s;
    // Announced HERE, at the moment of exhaustion, not at the next `writeRecord` — the
    // first version deferred it there, and review found the gap: the harm exhaustion does
    // is two reserve-sharing threads racing on one `busy`, which drops a record before
    // `writeRecord` is reached, and if no thread writes anything afterwards the trace
    // holds no notice and the run is judged over the hole. Written from a buffer on THIS
    // thread's stack, not the reserve's: the reserve is shared from this call on, and a
    // second thread overflowing at the same moment would be encoding its own record into
    // that buffer while the notice was being written (review, second round — the first
    // version said "nobody else holds it yet", which was true of the first caller and not
    // of the second). The notice is 44 bytes; the stack cost is nothing the SIGSYS
    // handler cannot bear. Written once: the compare-and-swap picks the thread that
    // writes it, and every later overflow finds it written. It is written before the
    // re-entrancy check, so a shim re-entered mid-call announces too — a change from
    // "busy writes nothing", and the safe direction.
    // Only once this image is armed (#753): before `init` the notice would go nowhere and the
    // flag would stay set, so the thread that needs it after `init` would share the reserve
    // unannounced; and while `init` is still writing the header and moving the trace's
    // descriptor, it would land in front of the header or on the descriptor's old number. A
    // thread on the reserve meets this again at its next call, and announces then.
    if (active and @cmpxchgStrong(bool, &exhaustion_announced, false, true, .acq_rel, .acquire) == null) {
        var notice: [64]u8 = undefined;
        const n = contract.encodeRecord(&notice, .{
            .op = .unresolved,
            .seq = 0,
            .pid = @bitCast(c.getpid()),
            .tid = tid,
            .path = "",
            .aux = contract.unresolved_kind.thread_slots_exhausted,
        }) catch return &reserve;
        _ = writeAll(notice[0..n]);
    }
    return &reserve;
}

const reclaiming: c_int = -1;

// A slot found by id but claimed by a process that is not this one: on macOS a `vfork` child
// runs on its parent's thread id, so a slot it claimed is that parent thread's once the child is
// gone. Left with the child's pid, `reclaimDeparted` would take it from the thread using it; and
// one `reclaimDeparted` is already taking is not used, or two threads would share it.
fn adopt(s: *ThreadState) bool {
    while (true) {
        const claimer = @atomicLoad(c_int, &s.claimer_pid, .acquire);
        if (claimer == reclaiming) return false;
        if (claimer == 0 or claimer == table_pid or c.getpid() != table_pid) return true;
        if (@cmpxchgStrong(c_int, &s.claimer_pid, claimer, table_pid, .acq_rel, .acquire) == null) return true;
    }
}

// Not taken while the table has room: a departed claimer costs nothing until then, and `kill`
// on every call would. Arbitrated on `claimer_pid`, not `tid`: a claim writes `tid` first, so a
// second reclaimer reading the new `tid` with the old pid would take the same slot again.
fn reclaimDeparted(tid: u64) ?*ThreadState {
    var self_pid: c_int = 0;
    var saved_errno: ?c_int = null;
    defer if (saved_errno) |e| {
        std.c._errno().* = e;
    };
    for (&slots) |*s| {
        const owner_pid = @atomicLoad(c_int, &s.claimer_pid, .acquire);
        if (owner_pid <= 0 or owner_pid == table_pid) continue;
        if (self_pid == 0) self_pid = c.getpid();
        if (owner_pid == self_pid) continue;
        if (saved_errno == null) saved_errno = std.c._errno().*;
        if (c.kill(owner_pid, 0) == 0 or std.c._errno().* != @backingInt(std.c.E.SRCH)) continue;
        if (@cmpxchgStrong(c_int, &s.claimer_pid, owner_pid, reclaiming, .acq_rel, .acquire) != null) continue;
        s.busy = false;
        s.exec_carrying = false;
        clearCounts(s);
        @atomicStore(c_int, &s.claimer_pid, self_pid, .release);
        @atomicStore(u64, &s.tid, tid, .release);
        // Given back if a signal handler on this thread claimed another slot before the store: two
        // slots for one id would split its counts.
        for (&slots) |*o| if (o != s and @atomicLoad(u64, &o.tid, .acquire) == tid) {
            @atomicStore(c_int, &s.claimer_pid, 0, .release);
            @atomicStore(u64, &s.tid, 0, .release);
            return o;
        };
        return s;
    }
    return null;
}

/// Called from the fork wrapper's child arm, before the child records anything. `vfork`
/// must not do this — the child runs in the parent's memory — and a raw `clone` bypasses
/// the wrapper and inherits the table as it stands: a parent past sixty-four threads that
/// forks through a raw syscall keeps the false refusal, which is the honest direction.
/// The claim words and the counters are cleared and the buffers are not: sixty-five slots
/// of some 72 KB each are nearly five megabytes of copy-on-write pages the child would
/// otherwise touch at once, and every buffer is written whole before it is read.
pub fn resetSlotsInChild() void {
    table_pid = c.getpid();
    for (&slots) |*s| {
        s.tid = 0;
        s.claimer_pid = 0;
        s.busy = false;
        clearCounts(s);
    }
    reserve.tid = 0;
    reserve.busy = false;
    clearCounts(&reserve);
    exhaustion_announced = false;
    // The thread tables (v18): the child has one thread, and it is none of the ones the
    // parent was about to start or could still join. A pending start left `taken` here
    // would leak an entry for the child's whole life; a joinable entry would let a join in
    // the child name a thread of the parent.
    for (&pending_starts) |*e| e.* = .{};
    for (&joinable) |*e| e.* = .{};
}
// `pending_starts` carries a start routine and its argument from `pthread_create` to the
// trampoline the new thread runs first, together with what the new thread's first record
// must say: who created it, how many records that creator had written, and which of the
// creator's creations it is. An entry is claimed by compare-and-swap, returned by the new
// thread as soon as it has copied the entry out, and returned by the creator when
// `pthread_create` fails — a table that only the child returns fills up under repeated
// `EAGAIN` (review). A thread cancelled asynchronously between its creation and its first
// instruction returns nothing; one of sixty-four entries leaks, and when all have leaked
// the creator installs no trampoline, the thread writes no `thread_started`, and the
// engine — which then knows no creator for it — draws no edge to or from its writes. The
// refusing side.
//
// `joinable` maps a live thread's `pthread_t` to the `(creator, ordinal)` pair its
// `thread_started` record carries. **The creator fills it**, right after `pthread_create`
// returns with the value in hand: filled by the new thread it was a race — a creator that
// joins at once looked the value up before the child had run, found nothing, and the join
// recorded `?` on a run that was in order (review). **A joiner reads it before the real
// join**, while the thread is still joinable and the value therefore still its own: read
// after the join returns, the same `pthread_t` can already be the next thread's — glibc
// reuses it at once, measured on virtualenv, whose silent thread and whose pip thread carry
// one value. An entry with the same value is overwritten on insert, because the value's
// previous holder is finished; a full table drops the insert and the later join records
// `?`. A `pthread_t` another thread received through shared memory and joined before its
// creator reached the insert is a window this design leaves open: it resolves to `?` and
// the run is refused, not misjudged.

const PendingStart = struct {
    taken: bool = false,
    routine: ?RoutineFn = null,
    arg: ?*anyopaque = null,
    creator: u64 = 0,
    written: u32 = 0,
    ordinal: u32 = 0,
};
var pending_starts: [max_threads]PendingStart = @splat(.{});

const Joinable = struct {
    pthread: usize = 0,
    creator: u64 = 0,
    ordinal: u32 = 0,
};
const joinable_claiming: usize = 1;
var joinable: [max_threads]Joinable = @splat(.{});

fn claimPendingStart() ?*PendingStart {
    for (&pending_starts) |*e| {
        if (@cmpxchgStrong(bool, &e.taken, false, true, .acq_rel, .acquire) == null) return e;
    }
    return null;
}

/// Claim the entry whose key is `expected` by taking it down to the sentinel, write the
/// payload, publish the value. Two creators racing for one free entry would otherwise both
/// write their payload and the first to publish would publish the other's; and a joiner
/// holding a reused value through shared memory, looking it up while the new holder's
/// creator overwrites the stale entry, reads no match rather than a pair half old and half
/// new — either would name a creation that never happened (review, twice).
fn joinableClaim(e: *Joinable, expected: usize, pthread: usize, creator: u64, ordinal: u32) bool {
    if (@cmpxchgStrong(usize, &e.pthread, expected, joinable_claiming, .acq_rel, .acquire) != null) return false;
    e.creator = creator;
    e.ordinal = ordinal;
    @atomicStore(usize, &e.pthread, pthread, .release);
    return true;
}

fn joinableInsert(pthread: usize, creator: u64, ordinal: u32) void {
    if (pthread == 0 or pthread == joinable_claiming) return;
    for (&joinable) |*e| {
        if (joinableClaim(e, pthread, pthread, creator, ordinal)) return;
    }
    for (&joinable) |*e| {
        if (joinableClaim(e, 0, pthread, creator, ordinal)) return;
    }
}

fn joinableTake(pthread: usize) ?contract.thread_aux.Joined {
    if (pthread == 0 or pthread == joinable_claiming) return null;
    for (&joinable) |*e| {
        if (@atomicLoad(usize, &e.pthread, .acquire) == pthread) {
            const found: contract.thread_aux.Joined = .{ .creator = e.creator, .ordinal = e.ordinal };
            @atomicStore(usize, &e.pthread, 0, .release);
            return found;
        }
    }
    return null;
}

fn trampoline(p: ?*anyopaque) callconv(.c) ?*anyopaque {
    const e: *PendingStart = @ptrCast(@alignCast(p.?));
    const routine = e.routine.?;
    const arg = e.arg;
    const creator = e.creator;
    const written = e.written;
    const ordinal = e.ordinal;
    @atomicStore(bool, &e.taken, false, .release);
    noteThreadStarted(creator, written, ordinal);
    return routine(arg);
}

/// Written from the new thread's own stack, not through a slot: the record has no path and a
/// short `aux`, so a buffer the size of the slot-exhaustion notice's carries it, and being
/// started claims no slot — a thread's first interposed call does, as before. Sixty-four slots
/// are the whole run's, and a pool whose workers never enter a wrapper is judged today however
/// many it creates and must stay judged (review).
fn noteThreadStarted(creator: u64, written: u32, ordinal: u32) void {
    if (!active) return;
    var aux_buf: [contract.thread_aux.max_len]u8 = undefined;
    const aux = contract.thread_aux.started(&aux_buf, creator, written, ordinal) catch return;
    var rec: [128]u8 = undefined;
    const n = contract.encodeRecord(&rec, .{
        .op = .thread_started,
        .seq = 0,
        .pid = @bitCast(c.getpid()),
        .tid = currentTid(),
        .path = "",
        .aux = aux,
    }) catch return;
    _ = writeAll(rec[0..n]);
}

fn noteThreadSync(op: contract.OpClass, who: ?contract.thread_aux.Joined) void {
    if (!active) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;
    var aux_buf: [contract.thread_aux.max_len]u8 = undefined;
    const aux: []const u8 = if (who) |w|
        (contract.thread_aux.joined(&aux_buf, w.creator, w.ordinal) catch contract.thread_aux.unknown)
    else
        contract.thread_aux.unknown;
    writeRecord(ts, op, 0, "", aux);
}

pub fn createThread(thread: *anyopaque, attr: ?*const anyopaque, start_routine: *const anyopaque, arg: ?*anyopaque) c_int {
    if (!active) return callPthreadCreate(thread, attr, start_routine, arg);
    const ts = mine();
    const ordinal = ts.creates + 1;
    const entry = claimPendingStart();
    var rc: c_int = undefined;
    if (entry) |e| {
        e.routine = @ptrCast(@alignCast(start_routine));
        e.arg = arg;
        e.creator = currentTid();
        e.written = ts.written;
        e.ordinal = ordinal;
        rc = callPthreadCreate(thread, attr, @ptrCast(&trampoline), @ptrCast(e));
        if (rc != 0) @atomicStore(bool, &e.taken, false, .release);
    } else {
        rc = callPthreadCreate(thread, attr, start_routine, arg);
    }
    if (rc == 0) {
        ts.creates = ordinal;
        if (entry != null) {
            const handle: *const usize = @ptrCast(@alignCast(thread));
            joinableInsert(handle.*, currentTid(), ordinal);
        }
        noteBoundary(.thread);
    }
    return rc;
}

pub fn joinThread(thread: usize, retval: ?*?*anyopaque) c_int {
    const who = joinableTake(thread);
    return settleSync(.thread_join, thread, who, callPthreadJoin(thread, retval));
}

fn settleSync(op: contract.OpClass, thread: usize, who: ?contract.thread_aux.Joined, rc: c_int) c_int {
    if (rc == 0) {
        noteThreadSync(op, who);
    } else if (who) |w| {
        joinableInsert(thread, w.creator, w.ordinal);
    }
    return rc;
}

pub fn detachThread(thread: usize) c_int {
    const who = joinableTake(thread);
    return settleSync(.thread_detach, thread, who, callPthreadDetach(thread));
}

/// **It no longer gates the kill** (v15). It did, and the reason was addressing: a forked
/// child counted its own operations, so its k-th belonged to nobody and killing there
/// would have reported a landing at the right number from the wrong process. The number
/// is a position in the run now, so the process that reaches k is the one the engine
/// asked about — and gating on this pid would mean a world armed at an awaited child's
/// operation never dies at all. The constraint outlived nothing here: its reason went
/// away and it went with it, rather than staying on as a rule whose comment still cites
/// a mechanism that changed.
var armed_pid: c_int = -1;

fn lookup(comptime T: type, name: [*:0]const u8) ?T {
    const p = c.dlsym(rtld_next, name) orelse return null;
    return @ptrCast(@alignCast(p));
}

fn RealFn(comptime name: [:0]const u8) type {
    return @typeInfo(@TypeOf(@field(real, name))).optional.child;
}

/// The table is filled from this library's own `.init_array`, and another shared library's
/// constructor can run first: the loader orders constructors by dependency, and nothing a
/// library can declare puts its own ahead of an unrelated one's. A call interposed from such a
/// constructor used to reach a null entry and answer `-1` — and `pthread_create`'s callers
/// expect an error number, so a C++ `std::thread` started there threw "Unknown error -1" and
/// the process aborted (OpenImageIO's `iconvert`, ROOT's `rootrm`), where by hand it ran.
///
/// **Nothing is written back.** The lookup is the same `dlsym(RTLD_NEXT)` `resolveAll` makes,
/// and its answer would be the same, but storing it would add a writer to the table beside
/// `resolveAll` — a thread such a constructor started can still be calling while `init` fills
/// it — and none of the readers is atomic. Once `init` has run the entry is there and this is
/// one load, as it was. Before it, every call pays a `dlsym`, and a call made from a signal
/// handler in that window would meet the loader's lock where it used to meet `-1`: a window
/// that opens only before this library's constructor, and only for a handler that calls one
/// of these.
///
/// What such a call does is not recorded — `active` is false — and what keeps that from
/// becoming a verdict is the mark below (`preInitMark`), not this function.
///
/// One more window this opens, unmeasured: a constructor that `dlopen`s a library whose own
/// constructor starts a thread and waits for it, while that thread makes an interposed call —
/// the thread's `dlsym` waits for the loader's lock the `dlopen` holds. ADR 0115 names it.
fn reach(comptime name: [:0]const u8) ?RealFn(name) {
    // Looked up only while the table is still unfilled. After `resolveAll` a null entry is a
    // symbol this C library does not have — an optional one, `pwritev2` before glibc 2.26 —
    // and asking `dlsym` again on every call would only repeat the answer, from a signal
    // handler too.
    //
    // The flag is read first, and with acquire: it is released by `resolveAll` after the last
    // entry, so once it reads true every entry it covers is visible. Read the other way round,
    // a thread a constructor started could see an entry not yet written and then the flag
    // already set, and answer "missing" for a function that exists — #753 again, in a window.
    if (@atomicLoad(bool, &table_filled, .acquire)) return @field(real, name);
    return @field(real, name) orelse lookup(RealFn(name), name);
}

var table_filled: bool = false;

/// Optional symbols (#244, #256): some of these can genuinely be absent — pwritev2 needs
/// glibc 2.26, copy_file_range 2.27, renameat2 2.28, and musl spells some of them
/// differently. Their helpers answer a missing symbol with ENOSYS (`optionalMissing`), because
/// a target that reads errno to decide whether to fall back (Rust std's kernel_copy does
/// exactly this) must see the reason. Of those only `pwritev` exists on macOS, and only its
/// helper has a darwin branch; the rest are Linux-only calls whose lookup is the only path.
fn resolveAll() void {
    inline for (comptime std.meta.fieldNames(@TypeOf(real))) |name| {
        @field(real, name) = lookup(RealFn(name), name);
    }
    @atomicStore(bool, &table_filled, true, .release);
}

fn parseU32(s: []const u8) u32 {
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return 0;
        v = v *% 10 +% (ch - '0');
    }
    return v;
}

/// Initialising lazily — on the first interposed call — would be simpler, but it would
/// make "the shim never loaded" and "the target performed no operations" produce the
/// same empty trace. The `shim_ready` marker written here is what lets the engine tell
/// those apart, so it has to be written whether or not the target does anything.
pub fn init() void {
    // FIRST, before anything else this function does, and whatever mode this process is
    // in: a seccomp filter survives `execve` and a `SIGSYS` handler does not, so an image
    // the target exec'd stands in front of the trap set with the signal back at its
    // default. The trap set includes an open for writing — which is the next thing below
    // — so a handler installed any later is installed too late for the image that needs
    // it most. Measured in a probe of this design (2026-09-11): with the two in the other
    // order, the `cat` an `sh -c` exec'd died of `SIGSYS`, exit 159; in this order both
    // survived. Costless where no filter exists: it only changes a disposition.
    syscalls.installHandler();

    defer if (!active) @atomicStore(u32, &pre_init.word, pre_init.unused, .release);

    if (builtin.os.tag != .macos) resolveAll();

    // The four signal entry points, resolved here rather than on first use. They are
    // exported in every mode — a symbol cannot be exported conditionally — so a target
    // that never asked for `--observe syscalls` still forwards through them, and the
    // forward must not reach `dlsym`: it is not async-signal-safe while `signal` and
    // `sigprocmask` are, so a target calling one of those from inside a signal handler
    // would have met the loader's lock (`syscalls.resolveGuards`, review P1).
    syscalls.resolveGuards();

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
                if (!std.mem.eql(u8, n, normalized)) alt_dir_len = n.len;
            } else |_| {}
        }
    }

    // `O_NOFOLLOW`, and `O_CREAT` stays (#488). The engine unlinks the trace once, before
    // the run; every process the shim is loaded into then opens this same name, and from
    // the second one onward there is nothing in front of the open at all. A link planted
    // there sends these records to whatever it points at — `O_APPEND` with no `O_TRUNC`,
    // so the target gains bytes rather than losing them, and the engine goes on to read
    // that file as the run's account.
    //
    // `O_EXCL` is not the answer here the way it was for the captures (#469): those are
    // opened once by a parent that unlinked first, while this channel is shared — every
    // shim'd process appends to it, so `O_CREAT|O_EXCL` would refuse from the second
    // process onward. A hard link therefore stays unrefused; docs/cli.md says so rather than
    // implying this open is now safe against everything.
    //
    // Dropping `O_CREAT` is not available either: the reproduce line the engine prints
    // names `<work>/trace-repro.bin`, which nothing creates but this open, and three
    // acceptance legs drive the shim directly after removing the file.
    // **`O_RDWR`, not `O_WRONLY`** (v15): the shim reads this file back to learn the run's
    // highest operation number, and it reads it through THIS descriptor rather than a
    // second open of the same path. A second open would be a second chance for the path to
    // resolve somewhere else — the hard-link hole this open's own comment above leaves
    // open — and the number it produced would be the crash point's address, so the address
    // would become choosable from outside. Written as a replacement rather than an added
    // flag because `O_WRONLY | O_RDWR` is 3, which is not an access mode at all
    // (`openIsWriteCapable` pins 3 as invalid); adding it would make this open fail and the
    // engine report `no_shim_marker` with nothing saying why.
    trace_fd = callOpen(tp, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o644);
    if (trace_fd < 0) return;

    // **`trace_fd = -1` is not decoration here.** This exit is reached through a
    // *successful* open, which the `trace_fd < 0` path above never is, and a closed
    // positive number left in the global is exactly the descriptor-reuse hazard the
    // relocation below and `noteTraceClose` exist to close. `active` is still false at this
    // point, so nothing would write through it today; that is an invariant of the order of
    // two statements, not something the type or a test holds.
    //
    // `O_NONBLOCK` stays on the descriptor from here. POSIX leaves it without effect on a
    // regular file, and clearing it would mean `F_SETFL`, which replaces the whole status
    // word: `F_GETFL` and a mask, or `O_APPEND` silently goes with it and every shim'd
    // process starts writing from its own offset over the records already there.
    if (!traceTargetIsOrdinary(trace_fd)) {
        _ = callClose(trace_fd);
        trace_fd = -1;
        return;
    }

    // The channel's one weakness is its number: the shim holds trace_fd as an integer,
    // and a target that closes that number — daemonize loops sweep 3..255 as ordinary
    // hygiene — leaves later trace writes landing in whatever file inherits it.
    // The fallback floor exists because a 256-descriptor rlimit — the macOS default —
    // rejects F_DUPFD at 900; if both floors fail the low number is kept, and a sweep
    // that reaches it still ends in refusal, never in a silent half-account.
    trace_fd = relocateHigh(trace_fd);
    keepName(&trace_path_buf, &trace_path_len, std.mem.span(tp));
    trace_identity = fileIdentity(trace_fd);

    if (c.getenv(contract.env.kill_at)) |k| kill_at = parseU32(std.mem.span(k));
    // Only a run the engine put in its own process group may take the group down; see
    // `contract.env.kill_group` for why the shim cannot decide this for itself.
    kill_group = c.getenv(contract.env.kill_group) != null;

    const ts = mine();
    if (c.getenv(contract.env.seq_base)) |b| ts.seq = parseU32(std.mem.span(b));

    armed_pid = c.getpid();
    table_pid = armed_pid;

    // The filter goes up before the first byte of the trace is written, because
    // `writeAll` has to know which way to issue its own writes. `active` is still false
    // here, so a failed install records nothing and leaves the announcement to say so.
    var observe_note: []const u8 = "";
    if (c.getenv(contract.env.observe)) |raw| {
        if (contract.ObserveMode.parse(std.mem.span(raw))) |mode| switch (mode) {
            .wrappers => {},
            // The engine starts a supervised target without this shim and counts it itself
            // (#217). A shim loaded anyway — `/etc/ld.so.preload`, a wrapper's own LD_PRELOAD —
            // stays silent rather than count the same operations a second time (review).
            .supervised => return,
            .syscalls => observe_note = blk: {
                // Before the filter, not after: a trap can arrive the instant it is up,
                // and the guards are what keep the signal reaching the handler. Set here
                // rather than beside `installHandler` because this one is observable —
                // see its declaration for why the default mode must not have it.
                syscalls.armGuards();
                break :blk switch (syscalls.install()) {
                    .armed => contract.observe_aux.armed,
                    .failed => contract.observe_aux.failed,
                    .unsupported => contract.observe_aux.unsupported,
                };
            },
        } else {
            // An unparseable value is the engine's bug, not the target's. Announcing it
            // as a failed install is what makes the engine refuse rather than silently
            // fall back to the default mode and report a verdict for the wrong one.
            observe_note = contract.observe_aux.failed;
        }
    }

    if (c.lseek(trace_fd, 0, SEEK_END) == 0) {
        var head: [contract.header_len]u8 = undefined;
        const n = contract.encodeHeader(&head) catch return;
        _ = writeAll(head[0..n]);
    }

    takeRunCgroup();

    // **These two statements must stay adjacent, and the engine depends on it.** Once
    // `active` is set this image can write records; `src/engine/trace.zig`'s exec rule
    // reads "a record with no announcement in front of it was written by the image that
    // announced last", which is only true while nothing can be recorded between the flag
    // and the announcement. Putting a statement here that writes a record — or that can
    // fail and return — makes that rule unsound without making any test red, because the
    // property is an ordering rather than a value (ADR 0018's amendment carries the
    // argument and the one case it does not cover).
    active = true;
    // shim_ready re-announces the continuation base as its seq (#123). Through v9
    // this field was always 0; a fresh start still writes 0, so a plain single-image
    // trace is unchanged. After a primary exec record, the engine requires the next
    // shim_ready from the same pid to carry the count the chain left off at — the
    // one piece of evidence a broken chain cannot fake.
    writeRecord(ts, .shim_ready, ts.seq, stateDir(), observe_note);
    // And where this image stands against the run's cgroup, immediately after the
    // announcement (v17).
    announceCgroup(ts);
    // Last: a call made before this function ran, or while it ran, that reached the state
    // (#753). After the cgroup record, which the engine pairs with the announcement.
    reportPreInit(ts);
}

/// The run's cgroup, copied out of the environment while it is still the engine's (v17,
/// #559), and a world's `cgroup.kill` opened now: at the crash point this may be the SIGSYS
/// handler, where a write-capable open would trap on itself.
fn takeRunCgroup() void {
    const rc = c.getenv(contract.env.run_cgroup) orelse return;
    const name = std.mem.span(rc);
    if (name.len == 0 or name.len > run_cgroup_buf.len) return;
    @memcpy(run_cgroup_buf[0..name.len], name);
    run_cgroup_len = name.len;
    // Empty is how the engine says "no crash-point kill here" — the recording run — pinned
    // rather than unset so an operator's shell cannot supply one.
    const kp = c.getenv(contract.env.kill_cgroup) orelse return;
    if (kp[0] == 0) return;
    const kfd = callOpen(kp, O_WRONLY | O_CLOEXEC, 0);
    if (kfd >= 0) kill_cgroup_fd = relocateHigh(kfd);
    keepName(&kill_cgroup_path_buf, &kill_cgroup_path_len, std.mem.span(kp));
    const ap = c.getenv(contract.env.kill_aside) orelse return;
    if (ap[0] == 0) return;
    const afd = callOpen(ap, O_WRONLY | O_CLOEXEC, 0);
    if (afd >= 0) kill_aside_fd = relocateHigh(afd);
    keepName(&kill_aside_path_buf, &kill_aside_path_len, std.mem.span(ap));
}

/// Where this image stands against the run's cgroup, as a `cgroup` record (v17, #559). A
/// standing that cannot be read says `unreadable`: a missing or unreadable answer is not an
/// acknowledgement.
fn announceCgroup(ts: *ThreadState) void {
    if (run_cgroup_len == 0) return;
    writeRecord(ts, .cgroup, 0, stateDir(), notHeldAux(cgroupStanding()) orelse
        if (kill_cgroup_fd >= 0) contract.cgroup_aux.held_kill else contract.cgroup_aux.held);
}

fn notHeldAux(standing: CgroupStanding) ?[]const u8 {
    return switch (standing) {
        .held => null,
        .outside => contract.cgroup_aux.outside,
        .unknown => contract.cgroup_aux.unreadable,
    };
}

const relocation_floor: c_int = 200;

fn relocateHigh(fd: c_int) c_int {
    for ([_]c_int{ 900, relocation_floor }) |floor| {
        const high = c.fcntl(fd, F_DUPFD, floor);
        if (high < 0) continue;
        _ = c.fcntl(high, F_SETFD, FD_CLOEXEC);
        _ = callClose(fd);
        return high;
    }
    return fd;
}

const CgroupStanding = contract.CgroupStanding;

/// Move this process from the run's `work` cgroup up into the run's own (v17, #559), so the
/// crash point's `cgroup.kill` does not end it before its group kill. False when there is
/// nowhere to move to or the kernel refused. The pid is written without `std.fmt`: this can
/// run in the SIGSYS handler, on the stack the README bounds (#555).
fn stepAside() bool {
    if (kill_aside_fd < 0) return false;
    var digits: [12]u8 = undefined;
    return shimWrite(kill_aside_fd, decimal(&digits, @bitCast(c.getpid())));
}

/// `v`'s decimal digits, written at the end of `digits`, without `std.fmt` for `stepAside`'s
/// reason. Returns the slice holding them.
fn decimal(digits: *[12]u8, v0: u32) []const u8 {
    var v = v0;
    var i: usize = digits.len;
    while (true) {
        i -= 1;
        digits[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
        if (v == 0) break;
    }
    return digits[i..];
}

/// Whether this process's group leader stands inside the run's cgroup (#559's second review): the
/// group a crash point's group kill reaches is the run's only then. A leader that is gone, or
/// whose standing cannot be read, is not. The path is formatted by hand for `stepAside`'s reason.
fn groupLeaderHeld() bool {
    const pgid = c.getpgid(0);
    if (pgid <= 0) return false;
    const prefix = "/proc/";
    const suffix = "/cgroup";
    var digits: [12]u8 = undefined;
    const d = decimal(&digits, @bitCast(pgid));
    var path: [32]u8 = undefined;
    @memcpy(path[0..prefix.len], prefix);
    @memcpy(path[prefix.len..][0..d.len], d);
    @memcpy(path[prefix.len + d.len ..][0..suffix.len], suffix);
    path[prefix.len + d.len + suffix.len] = 0;
    const p: [*:0]const u8 = @ptrCast(&path);
    return cgroupStandingAt(p) == .held;
}

fn shimWrite(fd: c_int, bytes: []const u8) bool {
    const n = if (syscalls.armed) syscalls.traceWrite(fd, bytes.ptr, bytes.len) else callWrite(fd, bytes.ptr, bytes.len);
    return n == @as(isize, @intCast(bytes.len));
}

/// The real `open`, libc's `read` (the shim does not interpose it), no allocation: safe in
/// the SIGSYS handler, where a read-only open is outside the trap set.
///
/// **Read a small window at a time, never the file in one buffer.** This runs inside an
/// interposed call and in the SIGSYS handler, where the README bounds the shim's stack
/// (#555) and `spike/check-shim-footprint.sh` holds each function to 1 KiB; the first version
/// held a path-sized buffer and measured 4,688 bytes. The file is one line on a cgroup v2
/// host and a dozen on a hybrid one, whose `0::` line comes last — so a smaller buffer read
/// once would have answered `unknown` there, which is recorded `unreadable` and refuses the run.
fn cgroupStanding() CgroupStanding {
    return cgroupStandingAt("/proc/self/cgroup");
}

fn cgroupStandingAt(proc_path: [*:0]const u8) CgroupStanding {
    const fd = callOpen(proc_path, O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0) return .unknown;
    defer _ = callClose(fd);
    var line: CgroupLine = .{ .run = run_cgroup_buf[0..run_cgroup_len] };
    var window: [128]u8 = undefined;
    while (true) {
        const r = std.c.read(fd, &window, window.len);
        if (r < 0) {
            if (std.c._errno().* == @backingInt(std.posix.E.INTR)) continue;
            return .unknown;
        }
        if (r == 0) break;
        for (window[0..@intCast(r)]) |b| {
            if (line.feed(b)) |answer| return answer;
        }
    }
    return line.finish();
}

const CgroupLine = contract.CgroupLine;
const standingOf = contract.standingOf;

pub fn stateDir() []const u8 {
    return state_dir_buf[0..state_dir_len];
}

fn altDir() []const u8 {
    return alt_dir_buf[0..alt_dir_len];
}

pub fn isInState(path: []const u8) bool {
    if (contract.isInsideDir(path, stateDir())) return true;
    return alt_dir_len != 0 and contract.isInsideDir(path, altDir());
}

/// Containment has to accept both spellings, but the *trace* must hold one: the engine
/// compares paths textually to place crash points, and a run that recorded
/// `/tmp/x/key.json` for the unlink and `/private/tmp/x/key.json` for the open would
/// describe two files where the target touched one.
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
    return writeAllTo(trace_fd, bytes);
}

fn writeAllTo(fd: c_int, bytes: []const u8) bool {
    if (fd < 0) return false;
    var off: usize = 0;
    while (off < bytes.len) {
        // Through the thunk when the filter is up: libc's `write` would trap, the
        // handler would record, and recording writes another record — recursion with
        // no bottom. `traceWrite` carries the sentinel the filter allows.
        const w = if (syscalls.armed)
            syscalls.traceWrite(fd, bytes[off..].ptr, bytes.len - off)
        else
            callWrite(fd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return false;
        off += @intCast(w);
    }
    return true;
}

fn writeRecord(ts: *ThreadState, op: contract.OpClass, s: u32, path: []const u8, aux: []const u8) void {
    if (encodeAndWrite(&ts.record_buf, op, s, path, aux)) ts.written += 1;
}

fn encodeAndWrite(buf: *[contract.max_record_len]u8, op: contract.OpClass, s: u32, path: []const u8, aux: []const u8) bool {
    const rec: contract.Record = .{
        .op = op,
        .seq = s,
        .pid = @bitCast(c.getpid()),
        .tid = currentTid(),
        .path = path,
        .aux = aux,
    };
    const n = contract.encodeRecord(buf, rec) catch return false;
    return writeAll(buf[0..n]);
}

fn keepName(buf: *[contract.max_path + 1]u8, len: *usize, name: []const u8) void {
    if (name.len > contract.max_path) return;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    len.* = name.len;
}

const at_empty_path = 0x1000;

const FileIdentity = struct { dev_major: u32, dev_minor: u32, ino: u64 };

fn fileIdentity(fd: c_int) ?FileIdentity {
    if (is_darwin) return null;
    var stx: std.os.linux.Statx = undefined;
    const rc = std.os.linux.statx(@intCast(fd), "", at_empty_path, .{ .INO = true }, &stx);
    if (std.os.linux.errno(rc) != .SUCCESS or !stx.mask.INO) return null;
    return .{ .dev_major = stx.dev_major, .dev_minor = stx.dev_minor, .ino = stx.ino };
}

fn descriptorClosed(fd: c_int) bool {
    return fd >= 0 and fdStat(fd) == .bad_fd;
}

// Not through libc's `openat` once the filter is up: a write-capable open traps, and a trap that
// meets a moment with SIGSYS blocked ends the process.
fn reopen(name: [*:0]const u8, flags: c_int) c_int {
    if (!syscalls.armed) return callOpen(name, flags, 0);
    const r = syscalls.thunk(@backingInt(std.os.linux.SYS.openat), @bitCast(@as(i64, AT_FDCWD)), @intFromPtr(name), @as(u32, @bitCast(flags)), 0, 0);
    const signed: i64 = @bitCast(r);
    return if (signed < 0) -1 else @intCast(signed);
}

// Back onto the old number, never a new one: the old number is the value every process sharing
// this memory reads, and a `vfork` child that wrote a new one would move its parent's channel to
// a descriptor only the child has.
fn restoreOnto(old: c_int, fresh: c_int) bool {
    const rc = std.os.linux.dup3(fresh, old, @as(u32, @bitCast(O_CLOEXEC)));
    return std.os.linux.errno(rc) == .SUCCESS;
}

// Not below the relocation floors, where the target's next open may take the number.
fn reinstate(old: c_int, name: *const [contract.max_path + 1]u8, name_len: usize) bool {
    if (old < relocation_floor or name_len == 0) return false;
    const fresh = reopen(@ptrCast(name), O_WRONLY | O_CLOEXEC);
    if (fresh < 0) return false;
    defer _ = callClose(fresh);
    return restoreOnto(old, fresh);
}

fn reinstateOrDrop(fd: *c_int, name: *const [contract.max_path + 1]u8, name_len: usize, owner: bool) void {
    if (!descriptorClosed(fd.*) or reinstate(fd.*, name, name_len)) return;
    if (owner) fd.* = -1;
}

fn isTraceFile(fd: c_int) bool {
    return trace_identity != null and std.meta.eql(fileIdentity(fd), trace_identity);
}

// Not through the thread's record buffer: a sweep from a signal handler can land while that
// buffer holds the half-encoded record of the call it interrupted.
fn writeDeathThrough(fd: c_int) void {
    var buf: [64]u8 = undefined;
    const n = contract.encodeRecord(&buf, .{
        .op = .unresolved,
        .seq = 0,
        .pid = @bitCast(c.getpid()),
        .tid = currentTid(),
        .path = "",
        .aux = contract.unresolved_kind.trace_closed,
    }) catch return;
    _ = writeAllTo(fd, buf[0..n]);
}

pub fn afterSweep() void {
    if (is_darwin or !active) return;
    const saved_errno = std.c._errno().*;
    defer std.c._errno().* = saved_errno;
    // A `vfork` child shares these numbers with its parent, whose own descriptors the child's
    // sweep never touched: a -1 written here would silence the parent.
    const owner = c.getpid() == table_pid;
    reinstateOrDrop(&kill_cgroup_fd, &kill_cgroup_path_buf, kill_cgroup_path_len, owner);
    reinstateOrDrop(&kill_aside_fd, &kill_aside_path_buf, kill_aside_path_len, owner);
    if (trace_fd < 0) return;
    const closed = descriptorClosed(trace_fd);
    if (!closed and (trace_identity == null or isTraceFile(trace_fd))) return;
    const fresh = if (trace_path_len > 0) reopen(@ptrCast(&trace_path_buf), O_RDWR | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK) else -1;
    defer if (fresh >= 0) {
        _ = callClose(fresh);
    };
    const same = fresh >= 0 and isTraceFile(fresh);
    // Not restored below the relocation floors, where the target's next open may take the number;
    // nor onto a number that already holds another file, which is the target's now.
    if (same and closed and trace_fd >= relocation_floor and restoreOnto(trace_fd, fresh)) {
        if (otherThreadsHere()) writeDeathThrough(trace_fd);
        return;
    }
    if (same) writeDeathThrough(fresh);
    if (owner) trace_fd = -1;
}

// A slot outlives the thread that claimed it; only a live thread may have
// written while the channel was gone.
fn otherThreadsHere() bool {
    const pid = c.getpid();
    const self = currentTid();
    for (&slots) |*s| {
        const tid = @atomicLoad(u64, &s.tid, .acquire);
        if (tid == 0 or tid == self or @atomicLoad(c_int, &s.claimer_pid, .acquire) != pid) continue;
        const rc = std.os.linux.syscall3(.tgkill, @as(usize, @bitCast(@as(isize, pid))), @intCast(tid), 0);
        if (std.os.linux.errno(rc) != .SRCH) return true;
    }
    return false;
}

pub inline fn callOpen2(comptime name: [:0]const u8, path: [*:0]const u8, flags: c_int) c_int {
    const f = reach(name) orelse return optionalMissingInt();
    return f(path, flags);
}
pub inline fn callOpenat2(comptime name: [:0]const u8, dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    const f = reach(name) orelse return optionalMissingInt();
    return f(dirfd, path, flags);
}

// Not left undone when glibc predates the function: `closefrom` cannot report failure, and a
// target that found the symbol by lookup expects its descriptors gone.
pub fn callClosefrom(low: c_int) void {
    if (reach("closefrom")) |f| return f(low);
    if (callCloseRange(@intCast(@max(low, 0)), std.math.maxInt(c_uint), 0) == 0) return;
    const limit = std.posix.getrlimit(.NOFILE) catch return;
    var fd: c_int = @max(low, 0);
    const top: c_int = @intCast(@min(limit.cur, 1 << 20));
    while (fd < top) : (fd += 1) _ = callClose(fd);
}

pub fn callCloseRange(first: c_uint, last: c_uint, flags: c_int) c_int {
    if (reach("close_range")) |f| return f(first, last, flags);
    const rc = std.os.linux.syscall3(.close_range, first, last, @as(u32, @bitCast(flags)));
    if (std.os.linux.errno(rc) != .SUCCESS) {
        std.c._errno().* = @backingInt(std.os.linux.errno(rc));
        return -1;
    }
    return 0;
}

/// That is legal behaviour — descriptor-hygiene sweeps close numbers they never
/// opened — but it ends observation, and the cost of ignoring it is measured: the
/// number gets re-used for a target file, and the shim's later trace writes land
/// inside it. So the channel announces its death while the descriptor still works
/// (`unresolved`, which the engine refuses on) and then goes silent: with trace_fd
/// at -1, `writeAll` drops everything, and nothing is ever written through a number
/// the target now owns. Called from every wrapper that retires a descriptor —
/// close, fclose, freopen — before the real call retires it.
pub fn noteTraceClose(fd: c_int) void {
    if (fd >= 0 and fd == kill_cgroup_fd) {
        kill_cgroup_fd = -1;
        return;
    }
    if (fd >= 0 and fd == kill_aside_fd) {
        kill_aside_fd = -1;
        return;
    }
    if (!active or fd < 0 or fd != trace_fd) return;
    // The path is empty on purpose: nothing was named here. Before #485 the reason
    // rode in the path field as "trace:closed-by-target", which the engine would
    // now print as the name the file last had — a filename that never existed.
    writeRecord(mine(), .unresolved, 0, "", contract.unresolved_kind.trace_closed);
    trace_fd = -1;
}

const deleted_suffix = " (deleted)";

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
    const link = std.mem.printSentinel(&link_buf, "/proc/self/fd/{d}", .{fd}, 0) catch return null;
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

/// `unresolvable` is set only for the second kind. A directory descriptor that cannot
/// name a path at all — a socket, a pipe — is proof the operation is not in the state
/// directory, and treating that as uncertainty would make ordinary programs
/// unjudgeable. A descriptor whose directory has been unlinked is the opposite: it
/// named something once, and where that was decides whether this matters.
fn resolveAt(ts: *ThreadState, out: []u8, dirfd: c_int, path: [*:0]const u8, unresolvable: *bool) ?[]const u8 {
    unresolvable.* = false;
    const p = std.mem.span(path);
    if (p.len == 0) return null;
    if (p[0] == '/') {
        return contract.normalizePath(out, "/", p) catch {
            unresolvable.* = true;
            return null;
        };
    }

    const base_buf = &ts.resolve_base;
    var base_deleted = false;
    const base = if (dirfd == AT_FDCWD) blk: {
        break :blk cwdPath(base_buf) orelse {
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
        const b = fdPath(base_buf, dirfd, &base_link_deleted) orelse {
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

/// Dropping it silently is the failure this whole tool exists to avoid: the engine
/// would then see a trace that is complete as far as it can tell, and PASS is the
/// honest-looking answer to that. Recorded instead, so the engine can refuse to judge.
fn noteUnresolved(ts: *ThreadState, path: []const u8, kind: []const u8) void {
    writeRecord(ts, .unresolved, 0, path, kind);
}

// **One atomic word holds where this image stands and the mark**, because both change under
// threads: a constructor that ran first can have started threads that are still calling while
// `init` runs, and `init` itself reads the mark. A call that loads `before` and finds no mark
// sets it with a compare-and-swap; `init`, as its last act, swaps in `recording` and reads the
// mark it displaced. A call that loses that race sees `recording` — and so a set `active`, which
// `init` set before the swap and never clears — and is recorded the ordinary way. The path is
// written only by the call that set the mark, and published afterwards: `init` names it when it
// was published in time, and records the mark without it otherwise.
const pre_init = struct {
    const before: u32 = 0;
    const recording: u32 = 1;
    const unused: u32 = 2;
    const stage_mask: u32 = 3;
    const marked: u32 = 1 << 8;
    const published: u32 = 1 << 9;
    var word: u32 = before;
    /// The process that set the mark. Only it hands the mark on across an `exec`: a `vfork`
    /// child shares this memory and must not run `setenv` in it, and a forked child's copy of
    /// the mark belongs to the parent, which reports it at its own `init`.
    var pid: c_int = 0;
    var path_buf: [contract.max_path + 1]u8 = undefined;
    var path_len: usize = 0;
    var carry_entry: [contract.env.before_constructor.len + 1 + contract.max_path + 1]u8 = undefined;
};

fn preInitStage() enum { record, consider, drop } {
    // macOS calls the originals directly from the first instant, so #753 never happened there,
    // and its system libraries make interposed calls in great number while libSystem is still
    // starting: nothing new runs on that platform (ADR 0115's scope).
    if (is_darwin) return .drop;
    const w = @atomicLoad(u32, &pre_init.word, .acquire);
    return switch (w & pre_init.stage_mask) {
        pre_init.recording => .record,
        pre_init.before => if (w & pre_init.marked != 0) .drop else .consider,
        else => .drop,
    };
}

fn preInitDecided() ?bool {
    return switch (preInitStage()) {
        .record => true,
        .drop => false,
        .consider => null,
    };
}

fn fdReadOnly(fd: c_int) bool {
    const fl = c.fcntl(fd, F_GETFL);
    return fl != -1 and (fl & O_ACCMODE) == O_RDONLY;
}

fn preInitMark(path: []const u8) bool {
    while (true) {
        const w = @atomicLoad(u32, &pre_init.word, .acquire);
        if (w & pre_init.stage_mask == pre_init.recording) return true;
        if (w & pre_init.stage_mask != pre_init.before or w & pre_init.marked != 0) return false;
        if (@cmpxchgWeak(u32, &pre_init.word, w, w | pre_init.marked, .acq_rel, .acquire) == null) {
            @atomicStore(c_int, &pre_init.pid, c.getpid(), .release);
            const n = @min(path.len, pre_init.path_buf.len - 1);
            @memcpy(pre_init.path_buf[0..n], path[0..n]);
            pre_init.path_buf[n] = 0;
            pre_init.path_len = n;
            _ = @atomicRmw(u32, &pre_init.word, .Or, pre_init.published, .release);
            return false;
        }
    }
}

/// Inside the state directory, as the engine named it. Read from the environment each time:
/// `init` has not normalised it into `state_dir_buf` yet, and the engine passes both spellings
/// already resolved (`SIDEEYE_STATE_DIR_ALT` is the caller's own).
fn preInitInState(path: []const u8) bool {
    if (c.getenv(contract.env.state_dir)) |sd| {
        const d = std.mem.span(sd);
        if (d.len != 0 and contract.isInsideDir(path, d)) return true;
    }
    if (c.getenv(contract.env.state_dir_alt)) |alt| {
        const d = std.mem.span(alt);
        if (d.len != 0 and contract.isInsideDir(path, d)) return true;
    }
    return false;
}

fn preInitPath(ts: *ThreadState, dirfd: c_int, path: [*:0]const u8) bool {
    var unresolvable = false;
    const resolved = resolveAt(ts, &ts.note1_path, dirfd, path, &unresolvable) orelse
        return if (unresolvable) preInitMark("") else false;
    if (!preInitInState(resolved)) return false;
    return preInitMark(resolved);
}

fn preInit1(dirfd: c_int, path: [*:0]const u8) bool {
    if (preInitDecided()) |decided| return decided;
    const ts = mine();
    if (ts.busy) return false;
    ts.busy = true;
    defer ts.busy = false;
    return preInitPath(ts, dirfd, path);
}

fn preInit2(dirfd: c_int, path: [*:0]const u8, adirfd: c_int, apath: ?[*:0]const u8) bool {
    if (preInitDecided()) |decided| return decided;
    const ts = mine();
    if (ts.busy) return false;
    ts.busy = true;
    defer ts.busy = false;
    if (preInitPath(ts, dirfd, path)) return true;
    if (preInitDecided()) |decided| return decided;
    const a = apath orelse return false;
    return preInitPath(ts, adirfd, a);
}

/// A descriptor's call before `init`. The descriptor may have been opened by an earlier image
/// and inherited — `exec ./prog 2>>"$STATE/log"` — so the open's own mark is not enough: where
/// the descriptor points is asked here, as `noteFdFromTrap` asks once armed (contract v8: no
/// descriptor number is exempt). `statx` and `readlink` only — nothing in `real` is needed.
fn preInitFd(fd: c_int) bool {
    if (preInitDecided()) |decided| return decided;
    if (fd < 0) return false;
    if (fdReadOnly(fd)) return false;
    const ts = mine();
    if (ts.busy) return false;
    ts.busy = true;
    defer ts.busy = false;
    var deleted = false;
    switch (fdKind(fd, &deleted)) {
        .non_path => return false,
        .unresolvable => return preInitMark(""),
        .path_backed => {},
    }
    var link_deleted = false;
    const resolved = fdPath(&ts.fd_path, fd, &link_deleted) orelse return preInitMark("");
    if (!preInitInState(resolved)) return false;
    return preInitMark(resolved);
}

fn preInitAlways() bool {
    return preInitDecided() orelse preInitMark("");
}

/// `init`'s last act: from here every call records itself. A mark left before it becomes one
/// `unresolved` record, after the announcement and the cgroup record — in front of
/// `shim_ready` the engine would read it as another process's (`trace.zig`'s subject rule) and
/// a one-process target's account would speak of a process boundary.
fn reportPreInit(ts: *ThreadState) void {
    const old = @atomicRmw(u32, &pre_init.word, .Xchg, pre_init.recording, .acq_rel);
    if (old & pre_init.marked != 0) {
        const path = if (old & pre_init.published != 0) pre_init.path_buf[0..pre_init.path_len] else "";
        noteUnresolved(ts, path, contract.unresolved_kind.before_constructor);
        return;
    }
    // An image before this one made such a call and `exec`'d before its own constructor could
    // say so; it handed the mark on in the environment (`preInitCarrySet`). Empty is the engine's
    // pin, not a mark.
    if (is_darwin) return;
    const carried = std.mem.span(c.getenv(contract.env.before_constructor) orelse return);
    if (carried.len == 0) return;
    noteUnresolved(ts, if (std.mem.eql(u8, carried, std.mem.span(pre_init_unread))) "" else carried, contract.unresolved_kind.before_constructor);
}

fn preInitCarried() ?[*:0]const u8 {
    if (is_darwin) return null;
    const w = @atomicLoad(u32, &pre_init.word, .acquire);
    if (w & pre_init.stage_mask != pre_init.before or w & pre_init.marked == 0) return null;
    if (@atomicLoad(c_int, &pre_init.pid, .acquire) != c.getpid()) return null;
    // Never empty: the engine pins the variable empty for every child it starts, so that a
    // value in the operator's shell cannot refuse a run, and empty therefore means "no mark".
    if (w & pre_init.published == 0 or pre_init.path_len == 0) return pre_init_unread;
    return @ptrCast(&pre_init.path_buf);
}

const pre_init_unread: [*:0]const u8 = "?";

/// For `execv` and `execvp`, which take the process's environment: an `exec` before `init`
/// would otherwise carry the mark out of existence with the image (#753). Undone by the caller
/// when the exec fails, as `execSeqCarrySet` is.
pub fn preInitCarrySet() bool {
    const v = preInitCarried() orelse return false;
    return c.setenv(contract.env.before_constructor, v, 1) == 0;
}

/// Undoes `preInitCarrySet` after an `exec` that returned, keeping the exec's errno: POSIX
/// lets `unsetenv` touch it, as `execv`'s own carry already allows for.
pub fn preInitCarryUndo() void {
    const saved = std.c._errno().*;
    _ = c.unsetenv(contract.env.before_constructor);
    std.c._errno().* = saved;
}

fn callExecvePreInit(p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    const v = preInitCarried() orelse return callExecve(p, a, e);
    const ts = mine();
    if (ts == &reserve or ts.exec_carrying) return callExecve(p, a, e);
    ts.exec_carrying = true;
    defer ts.exec_carrying = false;
    const entry = std.mem.printSentinel(&pre_init.carry_entry, "{s}={s}", .{ contract.env.before_constructor, std.mem.span(v) }, 0) catch return callExecve(p, a, e);
    return execveAppending(ts, p, a, e, entry.ptr, contract.env.before_constructor ++ "=");
}

/// Returns false when the trace could not be read. The caller records
/// `count-read-failed` and lets the engine refuse: numbering from a count this process
/// happens to remember would give the operation an address that belongs to another one.
///
/// A torn record at the end is not a failure. Records are appended with one `write(2)`
/// each, so a partial one is an operation still being written — the scan stops in front
/// of it, leaves `count_scanned` where it is, and reads it next time. In a run whose
/// operations do not interleave that partial record can only be this process's own; in
/// one where they do, two processes can take the same number, and the engine refuses
/// `sequence_numbering_broken` rather than judging a world at an ambiguous address.
/// Two threads of one process are the same case (v16): each scans from its own slot,
/// both read the trace's maximum, and if both take it the engine refuses — after having
/// refused the run for its second writing thread first.
fn refreshCount(ts: *ThreadState) bool {
    if (trace_fd < 0) return false;
    const end = c.lseek(trace_fd, 0, SEEK_END);
    if (end < 0) return false;
    const size: u64 = @intCast(end);
    if (size <= ts.count_scanned) return true;

    var off: u64 = @max(ts.count_scanned, contract.header_len);
    while (off < size) {
        const want: usize = @intCast(@min(@as(u64, ts.scan_buf.len), size - off));
        const got = c.pread(trace_fd, &ts.scan_buf, want, @intCast(off));
        if (got <= 0) return false;
        const n: usize = @intCast(got);
        var i: usize = 0;
        while (i < n) {
            const d = contract.decodeRecord(ts.scan_buf[i..n]) catch |e| switch (e) {
                // The tail of a record that is still being written, or one that runs past
                // this window. Either way the answer is to stop here: `off` advances by
                // what was consumed, so the next read starts on a record boundary.
                error.Truncated => break,
                else => return false,
            };
            // `kill_landed` counts towards the maximum even though it is a marker, and
            // that is deliberate. It carries the number of the operation the world died
            // in front of, and that operation's own record is never written. Leaving it
            // out would let a sibling still running in the microseconds before the group
            // kill lands take that same number for a real operation — the world would
            // then hold an operation at the address it claims to have died before, with
            // the record count and the maximum agreeing, and nothing would notice.
            // Counting it makes the sibling take the next number instead, which leaves a
            // gap, and a gap is what `sequence_numbering_broken` is for.
            if ((d.rec.op.isKillPoint() or d.rec.op == .kill_landed) and d.rec.seq > ts.seq)
                ts.seq = d.rec.seq;
            i += d.consumed;
        }
        if (i == 0) break;
        off += i;
    }
    ts.count_scanned = off;
    return true;
}

/// `kill(0, …)` is directed at a process group, and XNU delivers a process-directed signal to
/// the first thread in the list that is not a workqueue thread (`get_signalthread`). When the
/// crash point is reached on any other thread, `kill` returns to it. The `_exit` below used to
/// follow directly, on the reading that SIGKILL cannot be caught — true of the process, not of
/// the thread that asked — and a worker writing the state directory reached it before the
/// thread that took the signal had ended the process: from a pthread worker, 263 of 2,000
/// such kills ended by the signal in a C driver on macOS 15.3.1 (BUILDLOG, 2026-09-14).
///
/// `raise` is directed at the calling thread when that is a pthread, so the caller dies in
/// place. On a GCD workqueue thread `pthread_kill` answers `ENOTSUP` and Libc's `raise` falls
/// back to `kill(getpid())`, which returns again; the wait is for that caller, and ends when
/// the thread that took the signal ends the process. It is kept under a second, the smallest
/// `--world-timeout`, because a world still alive at its deadline refuses `child_timed_out`
/// before its landing is judged, which would tell the operator to raise a timeout about a kill
/// that never arrived. That does not keep the two apart: the deadline counts from before the
/// spawn, so a world that reached its crash point with less than the wait left meets it anyway —
/// only where the kill has already failed, and only in the reason given. On a GCD caller this
/// wait is entered at every crash point; until the process ends, a handler the target installed
/// can run on this thread, a signal delivered to it cuts a sleep short — the wait counts sleeps,
/// not time, so a target that signals this thread often shortens the whole of it — and `usleep`
/// is a cancellation point. Not measured: a process whose only threads are several parked workqueue
/// threads, where the one chosen to take the signal need not be the caller.
///
/// On Linux the caller does not return from `kill(0)`, and nothing here after it runs —
/// except in a pid namespace's init, which discards a SIGKILL it sends itself. Where nothing
/// ends the process within the wait, the `_exit` stays, and the world is refused as one that
/// exited on its own, which is then what it is.
fn killAtCrashPoint(group: bool) noreturn {
    if (group) _ = c.kill(0, SIGKILL);
    _ = c.raise(SIGKILL);
    for (0..9) |_| _ = c.usleep(100_000);
    c._exit(@backingInt(contract.ExitCode.setup_error));
}

fn observe(ts: *ThreadState, op: contract.OpClass, raw_path: []const u8, raw_aux: []const u8) void {
    const path = canonical(&ts.observe_path, raw_path);
    const aux = canonical(&ts.observe_aux, raw_aux);

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
        if (!refreshCount(ts)) {
            noteUnresolved(ts, path, contract.unresolved_kind.count_read_failed);
            return;
        }
        ts.seq += 1;
        // The test-apparatus gap (#270): skip number 2, so the second in-scope
        // operation onward is numbered one high — records count n, highest number
        // n+1, with the announcement untouched. This is the one shape the engine's
        // sequence_numbering_broken refusal exists for and that no interposed path
        // produces on its own: a shim that renumbers without re-announcing. Fixed at
        // 2 so any target with two in-scope operations fires it deterministically.
        //
        // Still effective under v15's trace-derived count, and by construction rather
        // than by luck: the gap is applied to the number that gets WRITTEN, so the next
        // `refreshCount` reads 3 back as the run's maximum and hands out 4. Numbering from
        // the trace would only silence this apparatus if `s` were computed separately from
        // the value the gap moves.
        if (shim_build_options.test_seq_gap and ts.seq == 2) ts.seq += 1;
        s = ts.seq;
        // Whoever performs the run's k-th operation dies here (v15), and the whole
        // process group dies with it.
        //
        // Both halves changed together and neither works without the other. The pid
        // guard that stood here — only the process that ran `init` may die — existed
        // because a forked child counted its own operations, so its k-th belonged to
        // nobody; a number is a position in the run now, so `s == kill_at` is exactly the
        // one operation the engine asked about, whichever process reached it. And the
        // death has to reach the group: a child that kills only itself leaves the shell
        // that spawned it to run the next command, so the world would carry operations
        // from after the crash point it claims to have died at. `kill(0, …)` addresses
        // the caller's process group, which is the target's own — the engine makes the
        // direct child a group leader before it execs, and kills that group itself when
        // the run ends (ADR 0002 decision 1).
        //
        // **That containment is now load-bearing in a way it was not.** `raise` could
        // not reach the engine however the group turned out; `kill(0, …)` can, if the
        // `setpgid` in `src/posix.zig` ever failed silently. It no longer can: the child
        // exits 126 rather than exec'ing into a group it does not lead. ADR 0002's
        // amendment carries that argument — the decision's original reasoning covers
        // `kill(-N, …)` sent from outside and says nothing about a signal sent from
        // inside.
        if (kill_at != 0 and s == kill_at) {
            // Landing evidence first, then die. Without this record the claim "we died
            // before the k-th operation" would rest on the engine having set a variable,
            // not on anything the target actually did.
            writeRecord(ts, .kill_landed, s, path, aux);
            // A contained world (v17, #559) is killed twice over, so it loses nothing an
            // uncontained world's group kill took. This process first steps aside, from the
            // run's `work` cgroup up into the run's own; then `work`'s `cgroup.kill` takes every
            // other process of the run however it left the process group; then the group kill
            // takes this process and every process that left the cgroup without leaving the
            // group. The first version wrote `cgroup.kill` alone, which ends the writer too, so
            // nothing could follow it — and a process that had moved to another cgroup but stayed
            // in the group outlived the crash point until the engine's cleanup (review, #559 PR
            // A). Where the step aside fails — a target that changed its uid, a descriptor it
            // closed — the kill is the cgroup's alone, and a `cgroup:kill-alone` record says so
            // first, so the engine refuses the world rather than trust a kill it knows was short.
            if (kill_group and run_cgroup_len > 0) {
                const aside = stepAside();
                // Said before the kill, which ends this process when it lands: without a step
                // aside the group kill below never runs (second review, #559 PR A).
                if (!aside) writeRecord(ts, .cgroup, s, path, contract.cgroup_aux.kill_alone);
                // The group kill reaches the caller's process group, which is the run's only while
                // that group's leader stands inside the run's cgroup: a process that joined another
                // group in the session with `setpgid(0, pgid)` would take that group down with it —
                // the engine's own, or its caller's (second review, #559). Asked before the cgroup
                // kill can end the leader. Where it is not the run's, this process dies alone, and
                // anything of the run left in that group is what the survivor watch is for.
                const group_held = groupLeaderHeld();
                const killed = kill_cgroup_fd >= 0 and shimWrite(kill_cgroup_fd, "1");
                if (aside and killed) killAtCrashPoint(group_held);
                writeRecord(ts, .cgroup, s, path, notHeldAux(cgroupStanding()) orelse contract.cgroup_aux.kill_returned);
                c._exit(@backingInt(contract.ExitCode.setup_error));
            }
            killAtCrashPoint(kill_group);
        }
    } else if (op == .close) {
        // Recorded so the oracle can match it, but never a crash point: SIGKILL closes
        // descriptors anyway, so dying just before close and just after it leave the
        // same bytes on disk.
        if (!contract.isInsideDir(path, stateDir())) return;
    }
    writeRecord(ts, op, s, path, aux);
}

// `note1` / `note2` / `noteFd` / `noteLinkByDescriptor` are the WRAPPER's door and carry
// the gate; the `*FromTrap` names beside them are the handler's and do not. One operation
// reaches the account once because exactly one door is open at a time: under
// `--observe syscalls` the handler counts and the wrappers are silent, otherwise the
// wrappers count and the handler only re-issues (`syscalls.armed`, read by both).
//
// The trap set is exactly the operations `OpClass.isKillPoint` admits (ADR 0059), so the
// class a wrapper is about to record already answers "is the handler counting this" —
// there is no per-wrapper fact to remember and no way for a new wrapper to forget. An
// earlier version of this change wrote the gate at each of the 31 call sites in
// `ops.zig`, which needed a check in `spike/check-shim-coverage.py` to hold them; that
// check went away with the call sites, three reviewers having pointed at the same place.
//
// `copy_file_range` is the one wrapper that records a kill point the handler never sees —
// six arguments leave the filter no register for its marker, so that syscall is not in
// the set. It calls `noteFdFromTrap` for that reason and no other.

inline fn wrapperSilent(op: contract.OpClass) bool {
    return countedAtSyscall() and op.isKillPoint();
}

pub fn note1(op: contract.OpClass, dirfd: c_int, path: [*:0]const u8) void {
    if (wrapperSilent(op)) return;
    note1FromTrap(op, dirfd, path);
}

pub fn note2(
    op: contract.OpClass,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: [*:0]const u8,
) void {
    if (wrapperSilent(op)) return;
    note2FromTrap(op, dirfd, path, adirfd, apath);
}

pub fn noteFd(op: contract.OpClass, fd: c_int) void {
    if (wrapperSilent(op)) return;
    noteFdFromTrap(op, fd);
}

pub fn noteLinkByDescriptor(fd: c_int) void {
    if (countedAtSyscall()) return;
    noteLinkByDescriptorFromTrap(fd);
}

pub fn note1FromTrap(op: contract.OpClass, dirfd: c_int, path: [*:0]const u8) void {
    if (!active and !preInit1(dirfd, path)) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var unresolvable = false;
    const resolved = resolveAt(ts, &ts.note1_path, dirfd, path, &unresolvable) orelse {
        if (unresolvable) noteUnresolved(ts, std.mem.span(path), contract.unresolved_kind.unresolvable_path);
        return;
    };
    observe(ts, op, resolved, "");
}

/// Record that an operation the shim can place but not model touched the state
/// directory (v12): a `RENAME_SWAP`, an `exchangedata`, a rename-via-attrlist. The
/// engine refuses the run on this record (`unsupported_syscall_observed`), the way the
/// oracle's flag refusal does on Linux — and like that refusal it is **scope-gated**:
/// the oracle checks `scope == .outside` before it looks at flags (oracle.zig), so an
/// out-of-scope swap must not refuse here either, or the two platforms answer the same
/// scenario differently. Both endpoints count, per the two-path rule (ADR 0006): a swap
/// with either side inside the state directory mutates it.
pub fn noteUnsupportedInScope2(
    label: [*:0]const u8,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: ?[*:0]const u8,
) void {
    if (!active and !preInit2(dirfd, path, adirfd, apath)) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var unresolvable = false;
    var in_scope = false;
    if (resolveAt(ts, &ts.unsup2_path, dirfd, path, &unresolvable)) |resolved| {
        in_scope = contract.isInsideDir(canonical(&ts.unsup2_canon, resolved), stateDir());
    } else if (unresolvable) {
        noteUnresolved(ts, std.mem.span(path), contract.unresolved_kind.unresolvable_path);
        return;
    }
    if (!in_scope) {
        if (apath) |ap| {
            var aunresolvable = false;
            if (resolveAt(ts, &ts.unsup2_aux, adirfd, ap, &aunresolvable)) |ares| {
                in_scope = contract.isInsideDir(canonical(&ts.unsup2_aux_canon, ares), stateDir());
            } else if (aunresolvable) {
                noteUnresolved(ts, std.mem.span(ap), contract.unresolved_kind.unresolvable_path);
                return;
            }
        }
    }
    if (in_scope) writeRecord(ts, .unsupported, 0, std.mem.span(label), "");
}

pub fn note2FromTrap(
    op: contract.OpClass,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: [*:0]const u8,
) void {
    if (!active and !preInit2(dirfd, path, adirfd, apath)) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var unresolvable = false;
    const resolved = resolveAt(ts, &ts.note2_path, dirfd, path, &unresolvable) orelse {
        if (unresolvable) noteUnresolved(ts, std.mem.span(path), contract.unresolved_kind.unresolvable_path);
        return;
    };
    const aresolved = resolveAt(ts, &ts.note2_aux, adirfd, apath, &unresolvable) orelse {
        // Half of a rename is not something to record as a rename.
        if (unresolvable) noteUnresolved(ts, std.mem.span(apath), contract.unresolved_kind.unresolvable_path);
        return;
    };
    observe(ts, op, resolved, aresolved);
}

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
    const rc = std.os.linux.statx(@intCast(fd), "", at_empty_path, .{ .TYPE = true, .NLINK = true }, &stx);
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

/// **Not `fdKind` below**, which answers a neighbouring question and would be the obvious
/// thing to reach for. Its `.path_backed` covers a directory as well as a regular file, and
/// its three values are about whether an *operation* can be placed inside the state
/// directory — evidence of innocence, evidence of guilt, or a measurement that failed. This
/// asks whether one descriptor can hold an append-only log. Sharing them would tie two
/// questions that move for different reasons.
///
/// **A named function rather than a branch at the open, so that a test can reach it.**
/// `init` does not run in a test binary — which the `O_NOFOLLOW` test at the bottom of
/// this file says about itself ("the call site is held by acceptance instead ... a
/// mutation that drops the flag at the open leaves this test green"). Two rounds of plan
/// review each produced a test that would have stayed green with the whole guard reverted,
/// and the shape of the code is what decided that, not the wording of the tests.
///
/// **`.failed` passes.** It means the measurement could not be taken — a kernel without
/// `statx` — not that a FIFO was found. Refusing on it would turn a host that today
/// refuses `unresolvable_path`, which names a cause, into one that refuses
/// `no_shim_marker`, which names nothing. The same `fdStat` failure usually reaches
/// `noteFd` on the target's first descriptor operation and is answered there — *usually*,
/// because a target that only renames and unlinks by path never reaches `noteFd` at all,
/// and a failed stat with a FIFO actually at the name still ends at `no_shim_marker`,
/// since the engine declines to read one (#400).
///
/// **What passing buys is narrower than "safe", and the narrow claim is the true one.**
/// For a FIFO the write answers `EAGAIN` and `writeAll` gives up, because `O_NONBLOCK`
/// stays on the descriptor. That says nothing about a **block device**: block I/O is
/// synchronous and `O_NONBLOCK` does not reach it, so a stalled device node at this name
/// would block the write the way the open used to block, in the same constructor with the
/// same absent budget. Planting one needs `mknod` and therefore root — which is why this
/// arm is still the right trade, not evidence that the hang is impossible. Nor is any of
/// it safe against `SIGPIPE` if a reader closes mid-write, unchanged from before.
fn traceTargetIsOrdinary(fd: c_int) bool {
    return switch (fdStat(fd)) {
        .ok => |st| (st.mode & S_IFMT) == S_IFREG,
        .failed => true,
        .bad_fd => false,
    };
}

fn fdKind(fd: c_int, deleted: *bool) FdKind {
    switch (fdStat(fd)) {
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

/// The descriptor goes in the kind, not the path. `path` is "the name the file had", and
/// since #485 the engine prints it that way — so `fd:7` sitting there produced "last
/// named fd:7", a filename that never was.
fn noteUnresolvedWithFd(ts: *ThreadState, path: []const u8, kind: []const u8, fd: c_int) void {
    var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
    noteUnresolved(ts, path, contract.unresolved_kind.withFd(&b, kind, fd));
}

fn noteUnresolvedWithOp(ts: *ThreadState, path: []const u8, kind: []const u8, op: contract.OpClass, fd: c_int) void {
    var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
    noteUnresolved(ts, path, contract.unresolved_kind.withOp(&b, kind, op, fd));
}

fn noteUnresolvedFd(ts: *ThreadState, fd: c_int) void {
    noteUnresolvedWithFd(ts, "", contract.unresolved_kind.fd_without_path, fd);
}

pub fn noteUnsupportedInScopeFd(label: [*:0]const u8, fd: c_int) void {
    if (!active and !preInitFd(fd)) return;
    if (fd < 0) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var deleted = false;
    switch (fdKind(fd, &deleted)) {
        .non_path => return,
        .unresolvable => {
            noteUnresolvedFd(ts, fd);
            return;
        },
        .path_backed => {},
    }
    var link_deleted = false;
    const resolved = fdPath(&ts.unsup_fd_path, fd, &link_deleted) orelse {
        noteUnresolvedFd(ts, fd);
        return;
    };
    if (!isInState(resolved)) return;
    writeRecord(ts, .unsupported, 0, std.mem.span(label), "");
}

// A store through a `MAP_SHARED` mapping changes the file with no call behind it, so no
// crash point can be placed before it. A writable mapping of a state file is refused where
// it is made (`noteUnsupportedInScopeFd`, the same refusal Linux's oracle issues). A
// read-only one is remembered here, so that an `mprotect` adding `PROT_WRITE` to it later
// is refused too — macOS has no oracle that sees either call. Only a descriptor opened for
// writing is remembered: the kernel refuses `PROT_WRITE` on a shared mapping of one opened
// read-only (`EACCES`), so the table holds what can become writable and nothing else.
//
// Append-only and lock-free: a slot's `end` is published last, with release, and a reader
// skips a slot whose `end` is still zero. Nothing is ever removed — `munmap` is not
// interposed — so a range the target later unmapped can only add a refusal, never hide a
// store. Past the last slot, every later `PROT_WRITE` mprotect is refused.

pub const PROT_WRITE: c_int = 0x2;
pub const MAP_SHARED: c_int = 0x1;
/// `MAP_ANON` on Darwin; Linux's `MAP_ANONYMOUS`. Darwin passes a VM tag (a positive
/// number) in the descriptor slot of an anonymous mapping, so the flag, not the
/// descriptor, is what says there is no file.
pub const MAP_ANON: c_int = if (is_darwin) 0x1000 else 0x20;
const F_GETFL: c_int = 3;
const shared_map_slots = 32;
const SharedMapSlot = struct { start: usize = 0, end: usize = 0 };
var shared_maps: [shared_map_slots]SharedMapSlot = @splat(.{});
var shared_map_next: usize = 0;
var shared_map_overflow: bool = false;

fn pageUp(len: usize) usize {
    const page = std.heap.pageSize();
    return (len +| (page - 1)) / page * page;
}

pub fn noteSharedMapping(fd: c_int, start: usize, len: usize) void {
    if (!active) return;
    if (fd < 0) return;
    if (fdReadOnly(fd)) return; // read-only: can never become writable
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;
    var deleted = false;
    switch (fdKind(fd, &deleted)) {
        .non_path => return,
        .unresolvable => {},
        .path_backed => {
            var link_deleted = false;
            if (fdPath(&ts.unsup_fd_path, fd, &link_deleted)) |resolved| {
                if (!isInState(resolved)) return;
            }
        },
    }
    const i = @atomicRmw(usize, &shared_map_next, .Add, 1, .monotonic);
    if (i >= shared_map_slots) {
        @atomicStore(bool, &shared_map_overflow, true, .release);
        return;
    }
    shared_maps[i].start = start;
    @atomicStore(usize, &shared_maps[i].end, start +| pageUp(len), .release);
}

pub fn noteMprotectWrite(start: usize, len: usize) void {
    if (!active) return;
    const n = @min(@atomicLoad(usize, &shared_map_next, .acquire), shared_map_slots);
    const overflow = @atomicLoad(bool, &shared_map_overflow, .acquire);
    if (n == 0 and !overflow) return;
    var hit = false;
    const end = start +| pageUp(len);
    for (shared_maps[0..n]) |*m| {
        const e = @atomicLoad(usize, &m.end, .acquire);
        if (e != 0 and start < e and m.start < end) {
            hit = true;
            break;
        }
    }
    if (!hit and !overflow) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;
    writeRecord(ts, .unsupported, 0, if (hit) contract.shared_map_refusal.made_writable else contract.shared_map_refusal.past_table, "");
}

pub fn noteFdFromTrap(op: contract.OpClass, fd: c_int) void {
    if (!active and !preInitFd(fd)) return;
    // The ONLY early return keyed on the descriptor itself. Contract v8: no descriptor
    // number is exempt from observation — not 0/1/2 (a target can dup2 a state file
    // onto any of them; measured as a false PASS before this change), and not the
    // trace fd, whose number a target can close and re-use for a state file. The
    // trace channel protects itself instead of asking for an exemption here: its
    // descriptor is relocated above the hygiene-sweep range at init, and a close()
    // of it announces the channel's death (noteTraceClose) so the engine refuses.
    // Where a descriptor points is decided by asking the kernel, below, every time.
    if (fd < 0) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var deleted = false;
    switch (fdKind(fd, &deleted)) {
        .non_path => return,
        .unresolvable => {
            noteUnresolvedWithOp(ts, "", contract.unresolved_kind.fd_without_path, op, fd);
            return;
        },
        .path_backed => {},
    }

    var link_deleted = false;
    const resolved = fdPath(&ts.fd_path, fd, &link_deleted) orelse {
        // A regular file or directory whose path could not be read back. That is a
        // failed measurement, not evidence of innocence — recorded, so the engine
        // refuses to judge a run whose operations it cannot place.
        noteUnresolvedWithOp(ts, "", contract.unresolved_kind.fd_without_path, op, fd);
        return;
    };
    if (!isInState(resolved)) return;
    if (deleted or link_deleted) {
        noteUnresolvedWithOp(ts, resolved, contract.unresolved_kind.unlinked_fd, op, fd);
        return;
    }
    observe(ts, op, resolved, "");
}

// Linux has to look the original up with `dlsym` and keep it somewhere, so it goes
// through the `real` table. macOS must NOT: interposition is live from the moment the
// library loads, while the constructor that would fill such a table runs much later,
// and every call the system libraries make in between would find it empty. There the
// original is called directly.

const darwin = if (is_darwin) @import("darwin_libc.zig") else struct {};

pub inline fn callOpen(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.open(path, flags, mode);
    const f = reach("open") orelse return optionalMissingInt();
    return f(path, flags, mode);
}
pub inline fn callOpenat(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.openat(dirfd, path, flags, mode);
    const f = reach("openat") orelse return optionalMissingInt();
    return f(dirfd, path, flags, mode);
}
pub inline fn callCreat(path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.creat(path, mode);
    const f = reach("creat") orelse return optionalMissingInt();
    return f(path, mode);
}
pub inline fn callWrite(fd: c_int, buf: [*]const u8, n: usize) isize {
    if (is_darwin) return darwin.write(fd, buf, n);
    const f = reach("write") orelse return optionalMissing();
    return f(fd, buf, n);
}
pub inline fn callPwrite(fd: c_int, buf: [*]const u8, n: usize, off: i64) isize {
    if (is_darwin) return darwin.pwrite(fd, buf, n, off);
    const f = reach("pwrite") orelse return optionalMissing();
    return f(fd, buf, n, off);
}
pub inline fn callWritev(fd: c_int, iov: *const anyopaque, cnt: c_int) isize {
    if (is_darwin) return darwin.writev(fd, iov, cnt);
    const f = reach("writev") orelse return optionalMissing();
    return f(fd, iov, cnt);
}

/// `ENOSYS`, for a symbol `reach` could not find at all. The symbols added by #244 and #256
/// can genuinely be missing, and a -1 with a stale errno is worse than the absence itself:
/// Rust std's kernel_copy reads errno to decide whether to fall back to a read/write loop, so
/// an unset errno turns "this shim cannot see the call" into "the target's copy failed". The
/// rest predate the oldest C library supported here and cannot be missing; they answer the
/// same way rather than a bare -1, which until #753 was also the answer to a table not yet
/// filled — the same -1 for two different things, neither with an errno.
const ENOSYS: c_int = if (is_darwin) 78 else 38;

/// `pthread_create`'s answer for a function `reach` could not find: an error number, as its
/// callers expect, and the one it returns for "insufficient resources". `-1` was what #753
/// met: C++'s `std::thread` threw it as "Unknown error -1" and aborted.
const EAGAIN_value: c_int = @backingInt(std.posix.E.AGAIN);

/// The `FILE *` wrappers' form of the same: null with errno set, not null with whatever errno
/// held.
fn missingFile() ?*FILE {
    std.c._errno().* = ENOSYS;
    return null;
}

fn optionalMissing() isize {
    std.c._errno().* = ENOSYS;
    return -1;
}

pub fn optionalMissingInt() c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}

pub inline fn callPwritev(fd: c_int, iov: *const anyopaque, cnt: c_int, off: i64) isize {
    if (is_darwin) return darwin.pwritev(fd, iov, cnt, off);
    const f = reach("pwritev") orelse return optionalMissing();
    return f(fd, iov, cnt, off);
}
pub inline fn callPwritev2(fd: c_int, iov: *const anyopaque, cnt: c_int, off: i64, flags: c_int) isize {
    const f = reach("pwritev2") orelse return optionalMissing();
    return f(fd, iov, cnt, off, flags);
}
pub inline fn callCopyFileRange(fd_in: c_int, off_in: ?*i64, fd_out: c_int, off_out: ?*i64, len: usize, flags: c_uint) isize {
    const f = reach("copy_file_range") orelse return optionalMissing();
    return f(fd_in, off_in, fd_out, off_out, len, flags);
}
pub inline fn callSendfile(out_fd: c_int, in_fd: c_int, off: ?*i64, count: usize) isize {
    const f = reach("sendfile") orelse return optionalMissing();
    return f(out_fd, in_fd, off, count);
}
pub inline fn callRenameat2(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8, flags: c_uint) c_int {
    const f = reach("renameat2") orelse return optionalMissingInt();
    return f(olddirfd, old, newdirfd, new, flags);
}

pub inline fn callClonefile(src: [*:0]const u8, dst: [*:0]const u8, flags: u32) c_int {
    if (is_darwin) return darwin.clonefile(src, dst, flags);
    return optionalMissingInt();
}
pub inline fn callClonefileat(sfd: c_int, src: [*:0]const u8, dfd: c_int, dst: [*:0]const u8, flags: u32) c_int {
    if (is_darwin) return darwin.clonefileat(sfd, src, dfd, dst, flags);
    return optionalMissingInt();
}
pub inline fn callFclonefileat(srcfd: c_int, dfd: c_int, dst: [*:0]const u8, flags: u32) c_int {
    if (is_darwin) return darwin.fclonefileat(srcfd, dfd, dst, flags);
    return optionalMissingInt();
}
pub inline fn callRenamexNp(old: [*:0]const u8, new: [*:0]const u8, flags: c_uint) c_int {
    if (is_darwin) return darwin.renamex_np(old, new, flags);
    return optionalMissingInt();
}
pub inline fn callRenameatxNp(od: c_int, old: [*:0]const u8, nd: c_int, new: [*:0]const u8, flags: c_uint) c_int {
    if (is_darwin) return darwin.renameatx_np(od, old, nd, new, flags);
    return optionalMissingInt();
}
pub inline fn callExchangedata(p1: [*:0]const u8, p2: [*:0]const u8, opts: c_uint) c_int {
    if (is_darwin) return darwin.exchangedata(p1, p2, opts);
    return optionalMissingInt();
}
pub inline fn callMmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, off: i64) ?*anyopaque {
    if (is_darwin) return darwin.mmap(addr, len, prot, flags, fd, off);
    return @ptrFromInt(std.math.maxInt(usize)); // MAP_FAILED
}
pub inline fn callMprotect(addr: ?*anyopaque, len: usize, prot: c_int) c_int {
    if (is_darwin) return darwin.mprotect(addr, len, prot);
    return optionalMissingInt();
}
pub inline fn callSetattrlist(path: [*:0]const u8, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: c_ulong) c_int {
    if (is_darwin) return darwin.setattrlist(path, al, buf, n, opts);
    return optionalMissingInt();
}
pub inline fn callFsetattrlist(fd: c_int, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: c_ulong) c_int {
    if (is_darwin) return darwin.fsetattrlist(fd, al, buf, n, opts);
    return optionalMissingInt();
}
pub inline fn callSetattrlistat(dirfd: c_int, path: [*:0]const u8, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: u32) c_int {
    if (is_darwin) return darwin.setattrlistat(dirfd, path, al, buf, n, opts);
    return optionalMissingInt();
}
pub inline fn callOpenDprotectedNp(path: [*:0]const u8, flags: c_int, class: c_int, dpflags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.open_dprotected_np(path, flags, class, dpflags, mode);
    return optionalMissingInt();
}
pub inline fn callGuardedOpenNp(path: [*:0]const u8, guard: *const u64, gflags: c_uint, flags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.guarded_open_np(path, guard, gflags, flags, mode);
    return optionalMissingInt();
}
pub inline fn callGuardedOpenDprotectedNp(path: [*:0]const u8, guard: *const u64, gflags: c_uint, flags: c_int, class: c_int, dpflags: c_int, mode: c_uint) c_int {
    if (is_darwin) return darwin.guarded_open_dprotected_np(path, guard, gflags, flags, class, dpflags, mode);
    return optionalMissingInt();
}
pub inline fn callGuardedCloseNp(fd: c_int, guard: *const u64) c_int {
    if (is_darwin) return darwin.guarded_close_np(fd, guard);
    return optionalMissingInt();
}
pub inline fn callGuardedWriteNp(fd: c_int, guard: *const u64, buf: [*]const u8, n: usize) isize {
    if (is_darwin) return darwin.guarded_write_np(fd, guard, buf, n);
    return optionalMissing();
}
pub inline fn callGuardedPwriteNp(fd: c_int, guard: *const u64, buf: [*]const u8, n: usize, off: i64) isize {
    if (is_darwin) return darwin.guarded_pwrite_np(fd, guard, buf, n, off);
    return optionalMissing();
}
pub inline fn callGuardedWritevNp(fd: c_int, guard: *const u64, iov: *const anyopaque, cnt: c_int) isize {
    if (is_darwin) return darwin.guarded_writev_np(fd, guard, iov, cnt);
    return optionalMissing();
}
pub inline fn callRename(old: [*:0]const u8, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.rename(old, new);
    const f = reach("rename") orelse return optionalMissingInt();
    return f(old, new);
}
pub inline fn callRenameat(od: c_int, old: [*:0]const u8, nd: c_int, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.renameat(od, old, nd, new);
    const f = reach("renameat") orelse return optionalMissingInt();
    return f(od, old, nd, new);
}
pub inline fn callUnlink(path: [*:0]const u8) c_int {
    if (is_darwin) return darwin.unlink(path);
    const f = reach("unlink") orelse return optionalMissingInt();
    return f(path);
}
pub inline fn callUnlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int {
    if (is_darwin) return darwin.unlinkat(dirfd, path, flags);
    const f = reach("unlinkat") orelse return optionalMissingInt();
    return f(dirfd, path, flags);
}
pub inline fn callLink(old: [*:0]const u8, new: [*:0]const u8) c_int {
    if (is_darwin) return darwin.link(old, new);
    const f = reach("link") orelse return optionalMissingInt();
    return f(old, new);
}
pub inline fn callLinkat(od: c_int, old: [*:0]const u8, nd: c_int, new: [*:0]const u8, flags: c_int) c_int {
    if (is_darwin) return darwin.linkat(od, old, nd, new, flags);
    const f = reach("linkat") orelse return optionalMissingInt();
    return f(od, old, nd, new, flags);
}
pub inline fn callSymlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int {
    if (is_darwin) return darwin.symlink(target, linkpath);
    const f = reach("symlink") orelse return optionalMissingInt();
    return f(target, linkpath);
}
pub inline fn callSymlinkat(target: [*:0]const u8, newdirfd: c_int, linkpath: [*:0]const u8) c_int {
    if (is_darwin) return darwin.symlinkat(target, newdirfd, linkpath);
    const f = reach("symlinkat") orelse return optionalMissingInt();
    return f(target, newdirfd, linkpath);
}
pub inline fn callFsync(fd: c_int) c_int {
    if (is_darwin) return darwin.fsync(fd);
    const f = reach("fsync") orelse return optionalMissingInt();
    return f(fd);
}
pub inline fn callFdatasync(fd: c_int) c_int {
    // This used to say "Darwin has no fdatasync; fsync is the honest equivalent" and
    // forward to fsync. Measured 2026-08-26: the symbol IS in libSystem — no public
    // header declares it, which is what the older reading was about — so forwarding
    // to fsync handed the target a stronger, slower call than the one it made. They
    // are different contracts (fdatasync may skip the metadata flush), and a shim
    // that substitutes one for the other changes what the target does rather than
    // observing it.
    if (is_darwin) return darwin.fdatasync(fd);
    const f = reach("fdatasync") orelse return optionalMissingInt();
    return f(fd);
}
pub inline fn callClose(fd: c_int) c_int {
    if (is_darwin) return darwin.close(fd);
    const f = reach("close") orelse return optionalMissingInt();
    return f(fd);
}
pub inline fn callFtruncate(fd: c_int, len: i64) c_int {
    if (is_darwin) return darwin.ftruncate(fd, len);
    const f = reach("ftruncate") orelse return optionalMissingInt();
    return f(fd, len);
}
pub inline fn callTruncate(path: [*:0]const u8, len: i64) c_int {
    if (is_darwin) return darwin.truncate(path, len);
    const f = reach("truncate") orelse return optionalMissingInt();
    return f(path, len);
}
pub inline fn callMkdir(path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.mkdir(path, mode);
    const f = reach("mkdir") orelse return optionalMissingInt();
    return f(path, mode);
}
pub inline fn callMkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int {
    if (is_darwin) return darwin.mkdirat(dirfd, path, mode);
    const f = reach("mkdirat") orelse return optionalMissingInt();
    return f(dirfd, path, mode);
}
pub inline fn callRmdir(path: [*:0]const u8) c_int {
    if (is_darwin) return darwin.rmdir(path);
    const f = reach("rmdir") orelse return optionalMissingInt();
    return f(path);
}
pub inline fn callFork() c_int {
    if (is_darwin) return darwin.fork();
    const f = reach("fork") orelse return optionalMissingInt();
    return f();
}
/// Every other wrapper goes through a `call*` function here. `vfork` cannot: any frame
/// alive across its double return is corrupted by the child running on the shared stack,
/// so the *exported wrapper itself* must make the call — as a guaranteed tail call, with
/// this function inlined into it. See `ops.vfork` for the measurements.
pub inline fn realVfork() ?ForkFn {
    if (is_darwin) return darwin.vfork;
    return reach("vfork");
}
pub inline fn callExecve(p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execve(p, a, e);
    const f = reach("execve") orelse return optionalMissingInt();
    return f(p, a, e);
}

/// The subject — and only the subject — may carry its operation count across an
/// exec (#123). A forked or vfork'd child answers `getpid()` differently and is
/// excluded structurally, which is also the vfork-safety argument: the child that
/// POSIX restricts to `_exit` and exec never reaches the environment mutation.
pub fn execCarryAllowed() bool {
    return active and c.getpid() == armed_pid;
}

/// Cap on the envp rebuild for `callExecveSeqCarry`. Entries beyond it mean the
/// carry is DROPPED, never that the target's environment is truncated: a missing
/// SEQ_BASE breaks the chain and refuses downstream, a truncated environment
/// silently changes the target.
const max_env_entries = 1024;

/// The rebuilt array lives in the calling thread's slot, not on its stack (#555): at
/// 8 KB it was the largest single frame the shim took from a target thread. It used to be
/// on the stack for a vfork child's sake — no heap there, and a global is memory the
/// suspended parent shares — and that reason does not reach this point:
/// `execCarryAllowed` admits the armed process only, and a vfork child answers
/// `getpid()` differently and returns before `mine()` is called. The entry's own bytes,
/// 64 of them, stay on the stack.
pub fn callExecveSeqCarry(p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (!active) return callExecvePreInit(p, a, e);
    if (!execCarryAllowed()) return callExecve(p, a, e);
    // The count carried across the image change is the RUN's, not this process's (v15).
    // Without this the base would be whatever this process last handed out, so a subject
    // that awaited a writing child and then replaced its own image would announce a
    // number lower than the trace's — and the engine, whose continuation check reads the
    // trace's own maximum, would refuse a chain that in fact held. A failed read leaves
    // the old value, which the engine then refuses as a broken chain: fail closed either
    // way, and the honest direction of the two.
    const ts = mine();
    // The reserve is shared by every thread past the 64th, and its `exec_env` with it: two
    // of them exec'ing at once would build their environments in the one array. The carry
    // is dropped there. The target's own environment goes through untouched, and the run
    // is refused on `thread-slots-exhausted` already (review, #555).
    if (ts == &reserve) return callExecve(p, a, e);
    // Re-entered on this thread — an exec from a signal handler that interrupted this
    // rebuild — the inner call would overwrite the array the outer one is still filling.
    // The carry is dropped instead: the chain breaks and the engine refuses a broken
    // chain, where a count carried from a half-written array would not be refused.
    if (ts.exec_carrying) return callExecve(p, a, e);
    ts.exec_carrying = true;
    defer ts.exec_carrying = false;
    _ = refreshCount(ts);
    var entry_buf: [64]u8 = undefined;
    const entry = std.mem.printSentinel(&entry_buf, "{s}={d}", .{ contract.env.seq_base, ts.seq }, 0) catch return callExecve(p, a, e);
    return execveAppending(ts, p, a, e, entry.ptr, contract.env.seq_base ++ "=");
}

fn execveAppending(ts: *ThreadState, p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8, entry: [*:0]const u8, comptime prefix: []const u8) c_int {
    const new_env = &ts.exec_env;
    var n: usize = 0;
    var i: usize = 0;
    while (e[i]) |kv| : (i += 1) {
        if (std.mem.startsWith(u8, std.mem.span(kv), prefix)) continue;
        if (n >= max_env_entries) return callExecve(p, a, e);
        new_env[n] = kv;
        n += 1;
    }
    if (n >= max_env_entries) return callExecve(p, a, e);
    new_env[n] = entry;
    new_env[n + 1] = null;
    return callExecve(p, a, @ptrCast(new_env));
}

/// Returns whether the variable was set — the caller unsets it when the exec
/// returns (failure), so a later fork's child does not inherit a stale count.
pub fn execSeqCarrySet() bool {
    if (!execCarryAllowed()) return false;
    // Same refresh, same reason as `callExecveSeqCarry`: the base is the run's count.
    const ts = mine();
    _ = refreshCount(ts);
    var val_buf: [16]u8 = undefined;
    const v = std.mem.printSentinel(&val_buf, "{d}", .{ts.seq}, 0) catch return false;
    return c.setenv(contract.env.seq_base, v.ptr, 1) == 0;
}

pub fn execSeqCarryUnset() void {
    _ = c.unsetenv(contract.env.seq_base);
}
pub inline fn callExecv(p: [*:0]const u8, a: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execv(p, a);
    const f = reach("execv") orelse return optionalMissingInt();
    return f(p, a);
}
pub inline fn callExecvp(p: [*:0]const u8, a: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.execvp(p, a);
    const f = reach("execvp") orelse return optionalMissingInt();
    return f(p, a);
}
pub inline fn callPosixSpawn(pid: ?*anyopaque, p: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.posix_spawn(pid, p, fa, at, a, e);
    const f = reach("posix_spawn") orelse return ENOSYS;
    return f(pid, p, fa, at, a, e);
}
pub inline fn callPosixSpawnp(pid: ?*anyopaque, p: [*:0]const u8, fa: ?*const anyopaque, at: ?*const anyopaque, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
    if (is_darwin) return darwin.posix_spawnp(pid, p, fa, at, a, e);
    const f = reach("posix_spawnp") orelse return ENOSYS;
    return f(pid, p, fa, at, a, e);
}
pub inline fn callPthreadCreate(t: *anyopaque, at: ?*const anyopaque, s: *const anyopaque, arg: ?*anyopaque) c_int {
    if (is_darwin) return darwin.pthread_create(t, at, s, arg);
    const f = reach("pthread_create") orelse return EAGAIN_value;
    return f(t, at, s, arg);
}
// `pthread_join` and `pthread_detach` return an errno value, not -1 with errno set, so a
// symbol `reach` could not find at all is answered `EINVAL` — a value the target's own error
// handling knows. (They were looked up once more before #753 made every wrapper do so.) Interposing these two adds a
// way for a target's joins to fail that v17 did not have; this is what bounds it (review).
const EINVAL_value: c_int = 22;
pub inline fn callPthreadJoin(t: usize, r: ?*?*anyopaque) c_int {
    if (is_darwin) return darwin.pthread_join(t, r);
    const f = reach("pthread_join") orelse return EINVAL_value;
    return f(t, r);
}
pub inline fn callPthreadDetach(t: usize) c_int {
    if (is_darwin) return darwin.pthread_detach(t);
    const f = reach("pthread_detach") orelse return EINVAL_value;
    return f(t);
}
pub inline fn callSetsid() c_int {
    if (is_darwin) return darwin.setsid();
    const f = reach("setsid") orelse return optionalMissingInt();
    return f();
}
pub inline fn callSetpgid(pid: c_int, pgid: c_int) c_int {
    if (is_darwin) return darwin.setpgid(pid, pgid);
    const f = reach("setpgid") orelse return optionalMissingInt();
    return f(pid, pgid);
}
pub inline fn callFopen(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.fopen(path, mode));
    const f = reach("fopen") orelse return missingFile();
    return f(path, mode);
}
pub inline fn callFopen64(path: [*:0]const u8, mode: [*:0]const u8) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.fopen(path, mode));
    const f = reach("fopen64") orelse return missingFile();
    return f(path, mode);
}
pub inline fn callFreopen(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *FILE) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.freopen(path, mode, @ptrCast(stream)));
    const f = reach("freopen") orelse return missingFile();
    return f(path, mode, stream);
}
pub inline fn callFreopen64(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *FILE) ?*FILE {
    if (is_darwin) return @ptrCast(darwin.freopen(path, mode, @ptrCast(stream)));
    const f = reach("freopen64") orelse return missingFile();
    return f(path, mode, stream);
}
pub inline fn callFflush(stream: ?*FILE) c_int {
    if (is_darwin) return darwin.fflush(@ptrCast(stream));
    const f = reach("fflush") orelse return optionalMissingInt();
    return f(stream);
}
pub inline fn callFflushUnlocked(stream: ?*FILE) c_int {
    if (is_darwin) return darwin.fflush(@ptrCast(stream));
    const f = reach("fflush_unlocked") orelse return optionalMissingInt();
    return f(stream);
}
pub inline fn callFclose(stream: *FILE) c_int {
    if (is_darwin) return darwin.fclose(@ptrCast(stream));
    const f = reach("fclose") orelse return optionalMissingInt();
    return f(stream);
}
pub inline fn callFseek(stream: *FILE, off: c_long, whence: c_int) c_int {
    if (is_darwin) return darwin.fseek(@ptrCast(stream), off, whence);
    const f = reach("fseek") orelse return optionalMissingInt();
    return f(stream, off, whence);
}
pub inline fn callFseeko(stream: *FILE, off: i64, whence: c_int) c_int {
    if (is_darwin) return darwin.fseeko(@ptrCast(stream), off, whence);
    const f = reach("fseeko") orelse return optionalMissingInt();
    return f(stream, off, whence);
}
pub inline fn callFseeko64(stream: *FILE, off: i64, whence: c_int) c_int {
    if (is_darwin) return darwin.fseeko(@ptrCast(stream), off, whence);
    const f = reach("fseeko64") orelse return optionalMissingInt();
    return f(stream, off, whence);
}
pub inline fn callRewind(stream: *FILE) void {
    if (is_darwin) return darwin.rewind(@ptrCast(stream));
    const f = reach("rewind") orelse return;
    return f(stream);
}
pub inline fn callFsetpos(stream: *FILE, pos: *const anyopaque) c_int {
    if (is_darwin) return darwin.fsetpos(@ptrCast(stream), pos);
    const f = reach("fsetpos") orelse return optionalMissingInt();
    return f(stream, pos);
}
pub inline fn callFsetpos64(stream: *FILE, pos: *const anyopaque) c_int {
    if (is_darwin) return darwin.fsetpos(@ptrCast(stream), pos);
    const f = reach("fsetpos64") orelse return optionalMissingInt();
    return f(stream, pos);
}

/// Record that a `linkat(…, AT_EMPTY_PATH)` linked a descriptor rather than a named
/// source: its old path is empty, so there is nothing to resolve or place, and the
/// engine must refuse rather than judge a link it cannot address (ADR 0006). Recorded
/// even where an oracle would also catch it, so the platform with no oracle refuses too.
pub fn noteLinkByDescriptorFromTrap(fd: c_int) void {
    if (!active and !preInitAlways()) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;
    // The descriptor is all there is to name here — the old path is empty by construction
    // — so without it two such calls on different files are one indistinguishable
    // sentence. It is not always a *file* descriptor, and the record does not pretend
    // otherwise: `AT_FDCWD` (-100 on Linux, -2 on macOS) reaches this the same way any
    // other value does, and it is recorded as it was passed. A negative number in the
    // report is the caller's own argument, which is what the operator needs to match it
    // against their code; inventing a name for it here would be the `fd:7`-as-a-filename
    // mistake in a new place.
    noteUnresolvedWithFd(ts, "", contract.unresolved_kind.link_by_descriptor, fd);
}

/// Boundary detectors carry no path. Since v3 their presence no longer forces UNKNOWN
/// by itself — the engine decides, with the oracle's help, whether the boundary was
/// tolerable — but they must still all be recorded, because "no boundary seen" is an
/// input to that decision.
pub fn noteBoundary(op: contract.OpClass) void {
    if (!active) return;
    const ts = mine();
    if (ts.busy) return;
    recordBoundary(ts, op);
}

pub const ExecLoan = struct {
    given_back: bool = false,
    seq: u32 = 0,
    count_scanned: u64 = 0,
    written: u32 = 0,
    creates: u32 = 0,
};

pub fn noteExecBoundary() ExecLoan {
    if (!active) return .{};
    const ts = mine();
    if (ts.busy) return .{};
    recordBoundary(ts, .exec);
    return returnSlotBeforeExec(ts);
}

pub fn takeBackAfterFailedExec(loan: ExecLoan) void {
    if (!loan.given_back) return;
    const ts = mine();
    if (ts == &reserve) return;
    ts.seq = loan.seq;
    ts.count_scanned = loan.count_scanned;
    ts.written = loan.written;
    ts.creates = loan.creates;
}

fn recordBoundary(ts: *ThreadState, op: contract.OpClass) void {
    ts.busy = true;
    defer ts.busy = false;
    writeRecord(ts, op, 0, "", "");
    if (run_cgroup_len > 0) if (notHeldAux(cgroupStanding())) |aux|
        writeRecord(ts, .cgroup, 0, stateDir(), aux);
}

fn clearCounts(s: *ThreadState) void {
    s.seq = 0;
    s.count_scanned = 0;
    s.written = 0;
    s.creates = 0;
}

fn returnSlotBeforeExec(ts: *ThreadState) ExecLoan {
    const pid = c.getpid();
    // Not a slot this process found already its own: that is a thread of the table's owner (a
    // `vfork` child answering with its parent's thread id), and zeroing it would restart that
    // thread's counts when the parent resumes.
    if (ts == &reserve or table_pid == 0 or pid == table_pid or ts.claimer_pid != pid) return .{};
    const loan: ExecLoan = .{ .given_back = true, .seq = ts.seq, .count_scanned = ts.count_scanned, .written = ts.written, .creates = ts.creates };
    ts.exec_carrying = false;
    clearCounts(ts);
    @atomicStore(c_int, &ts.claimer_pid, 0, .release);
    @atomicStore(u64, &ts.tid, 0, .release);
    return loan;
}

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
    try std.testing.expect(!isInState("/tmp/x/state2/key.json"));
    try std.testing.expect(!isInState("/etc/passwd"));
}

test "a path under the alternative spelling is recorded under the canonical one" {
    setDirsForTest("/private/tmp/x/state", "/tmp/x/state");
    defer setDirsForTest("", "");

    var buf: [contract.max_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/private/tmp/x/state/key.json",
        canonical(&buf, "/tmp/x/state/key.json"),
    );
    try std.testing.expectEqualStrings(
        "/private/tmp/x/state/key.json",
        canonical(&buf, "/private/tmp/x/state/key.json"),
    );
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

// Split by role for the same reason the engine's options tests are: a failing assertion
// aborts its test, so a mutation that breaks the first one would leave the second's state
// unrecorded.

test "the shipped shim options carry the shipped value (#365)" {
    try std.testing.expect(!shim_build_options.test_seq_gap);
    try std.testing.expect(!shim_build_options.test_observe_fail);
}

test "no second shim build option arrives unchecked (#365)" {
    // The ratchet, as in the engine's: a second option added later with no assertion above
    // would leave the promise false while CI stayed green.
    const decls = @typeInfo(shim_build_options).@"struct".decl_names;
    try std.testing.expectEqual(@as(usize, 2), decls.len);
}

test "a call made before init filled the table reaches the real function, and fills nothing (#753)" {
    if (is_darwin) return error.SkipZigTest;
    // Emptied here rather than assumed empty: other tests in this file call `resolveAll`, and
    // the order tests run in is not this test's to choose. Put back after, for the same reason.
    const saved = real;
    defer real = saved;
    real = .{};
    const saved_filled = table_filled;
    defer table_filled = saved_filled;
    table_filled = false;

    const Routine = struct {
        var ran: bool = false;
        fn run(_: ?*anyopaque) callconv(.c) ?*anyopaque {
            ran = true;
            return null;
        }
    };
    Routine.ran = false;
    var thread: usize = 0;
    try std.testing.expectEqual(@as(c_int, 0), callPthreadCreate(@ptrCast(&thread), null, @ptrCast(&Routine.run), null));
    try std.testing.expectEqual(@as(c_int, 0), callPthreadJoin(thread, null));
    try std.testing.expect(Routine.ran);

    const fd = callOpen("/dev/null", O_RDONLY, 0);
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(c_int, 0), callClose(fd));
    const f = callFopen("/dev/urandom", "r") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(c_int, 0), callFclose(f));

    try std.testing.expect(real.pthread_create == null and real.open == null and real.fopen == null);

    table_filled = true;
    std.c._errno().* = 0;
    try std.testing.expectEqual(@as(c_int, -1), callOpen("/dev/null", O_RDONLY, 0));
    try std.testing.expectEqual(ENOSYS, std.c._errno().*);
}

test "the shim's O_NOFOLLOW actually refuses a symlink (#488)" {
    // Asks the kernel rather than asserting the number. A test that spells the value out
    // is satisfied by whatever the constant happens to say — which is exactly how the
    // engine's copy carried the x86_64 value for all of Linux and left its one caller
    // inert on arm64 (#316), the defect this constant's derivation exists to prevent.
    //
    // What this does NOT reproduce is the call path. The shim's own open goes through libc
    // — dlsym'd on Linux, a direct extern on macOS (`callOpen` above) — and on Linux
    // `real.open` is null in a test binary because `init` never ran.
    // The bits are the same bits; what is measured is that they reach a kernel and refuse
    // a link. The call site is held by acceptance instead — a mutation that drops the flag
    // at the open leaves this test green.
    //
    // A pid-unique directory rather than a fixed name: `zig build test` runs this file in
    // several concurrent binaries, and a shared path passed every single run before
    // failing 66 of 80 paired ones (#28).
    var pb: [160]u8 = undefined;
    const base = std.mem.printSentinel(&pb, "/tmp/sideeye-shim-nofollow-{d}", .{c.getpid()}, 0) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var tb: [160]u8 = undefined;
    const target_z = std.mem.printSentinel(&tb, "{s}/target", .{base}, 0) catch unreachable;
    var lb: [160]u8 = undefined;
    const link_z = std.mem.printSentinel(&lb, "{s}/link", .{base}, 0) catch unreachable;
    defer {
        _ = std.c.unlink(link_z.ptr);
        _ = std.c.unlink(target_z.ptr);
        _ = std.c.rmdir(base.ptr);
    }

    const create: std.posix.O = @bitCast(O_WRONLY | O_CREAT | O_TRUNC);
    const tfd = std.c.open(target_z.ptr, create, @as(c_uint, 0o644));
    try std.testing.expect(tfd >= 0);
    _ = std.c.close(tfd);
    try std.testing.expect(std.c.symlink(target_z.ptr, link_z.ptr) == 0);

    // Both directions. "The open failed" alone would also be true of a path that is not
    // there, so the arm without the flag is what gives the arm with it a meaning.
    const plain: std.posix.O = @bitCast(O_WRONLY);
    const followed = std.c.open(link_z.ptr, plain);
    try std.testing.expect(followed >= 0);
    _ = std.c.close(followed);

    const guarded: std.posix.O = @bitCast(O_WRONLY | O_NOFOLLOW);
    const refused = std.c.open(link_z.ptr, guarded);
    if (refused >= 0) {
        _ = std.c.close(refused);
        return error.NofollowDidNotRefuse;
    }
}

test "the trace open's kind check refuses a pipe and accepts a regular file (#492)" {
    // `pipe()`, not a FIFO opened by name. A FIFO at the trace path is the hazard this
    // guard exists for, so opening one by name here would be reaching through the hazard
    // to check the guard — and a unit test cannot bound its own runtime: the unit-test
    // steps in CI carry no `timeout-minutes`, so an open that blocked would hold a runner
    // for the GitHub default of six hours. `src/posix.zig`'s `kindOfFd` test makes the
    // same choice for the same reason. A pipe is `S_IFIFO` to `fstat`, which is the field
    // this function reads, and it has no filesystem and no possibility of blocking.
    //
    // Unlike the `O_NOFOLLOW` test above, this one **does** hold the call site's decision:
    // the check is a named function, so reverting it turns these assertions red. What it
    // still does not hold is that `init` calls it, or that the open carries `O_NONBLOCK`;
    // those two are acceptance's (`spike/acceptance.sh`, #492 legs).
    var fds: [2]std.c.fd_t = undefined;
    try std.testing.expect(std.c.pipe(&fds) == 0);
    defer _ = std.c.close(fds[0]);
    defer _ = std.c.close(fds[1]);
    try std.testing.expect(!traceTargetIsOrdinary(fds[0]));
    try std.testing.expect(!traceTargetIsOrdinary(fds[1]));

    // The control, and it is what gives the assertions above a meaning: a function that
    // answered `false` for everything would satisfy them while refusing every real trace
    // in every run — the guard failing closed on the whole product rather than on a FIFO.
    //
    // A pid-unique directory: `zig build test` runs this file in several concurrent
    // binaries, and a fixed shared name passed every single run before failing 66 of 80
    // paired ones (#28).
    var bb: [160]u8 = undefined;
    const base = std.mem.printSentinel(&bb, "/tmp/sideeye-shim-tracekind-{d}", .{c.getpid()}, 0) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.mem.printSentinel(&fb, "{s}/f", .{base}, 0) catch unreachable;
    defer {
        _ = std.c.unlink(file_z.ptr);
        _ = std.c.rmdir(base.ptr);
    }
    const create: std.posix.O = @bitCast(O_WRONLY | O_CREAT | O_TRUNC);
    const wfd = std.c.open(file_z.ptr, create, @as(c_uint, 0o644));
    try std.testing.expect(wfd >= 0);
    defer _ = std.c.close(wfd);
    try std.testing.expect(traceTargetIsOrdinary(wfd));

    // A directory answers `false` as well. The call site cannot produce one — `O_WRONLY`
    // on a directory is `EISDIR` — but the property under test is "an ordinary file",
    // not "not a pipe", and a mask that only excluded `S_IFIFO` would pass without this.
    const rdonly: std.posix.O = @bitCast(@as(c_int, 0));
    const dfd = std.c.open(base.ptr, rdonly, @as(c_uint, 0));
    try std.testing.expect(dfd >= 0);
    defer _ = std.c.close(dfd);
    try std.testing.expect(!traceTargetIsOrdinary(dfd));

    try std.testing.expect(!traceTargetIsOrdinary(-1));
}

test "the run's operation count is read back from the trace, and a torn tail is not a failure (v15)" {
    // A pid-unique directory, for the reason the trace-kind test above gives: several
    // concurrent test binaries run this file.
    var bb: [160]u8 = undefined;
    const base = std.mem.printSentinel(&bb, "/tmp/sideeye-shim-count-{d}", .{c.getpid()}, 0) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.mem.printSentinel(&fb, "{s}/trace.bin", .{base}, 0) catch unreachable;
    defer {
        _ = std.c.unlink(file_z.ptr);
        _ = std.c.rmdir(base.ptr);
    }

    const flags: std.posix.O = @bitCast(O_RDWR | O_CREAT | O_TRUNC | O_APPEND);
    const fd = std.c.open(file_z.ptr, flags, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    defer _ = std.c.close(fd);

    // The one global this function reads. Restored on the way out: the rest of this
    // file's tests run in the same binary and must not inherit a live descriptor. The
    // count state is a slot of this test's own (v16), so nothing else needs restoring.
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    trace_fd = fd;
    var ts: ThreadState = .{};

    const append = struct {
        fn record(f: c_int, rec: contract.Record) !void {
            var rbuf: [2 * contract.max_path]u8 = undefined;
            const n = try contract.encodeRecord(&rbuf, rec);
            try std.testing.expectEqual(@as(isize, @intCast(n)), std.c.write(f, &rbuf, n));
        }
        fn bytes(f: c_int, b: []const u8) !void {
            try std.testing.expectEqual(@as(isize, @intCast(b.len)), std.c.write(f, b.ptr, b.len));
        }
    };

    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 0), ts.seq);
    var hbuf: [contract.header_len]u8 = undefined;
    const hn = try contract.encodeHeader(&hbuf);
    try append.bytes(fd, hbuf[0..hn]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 0), ts.seq);

    try append.record(fd, .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" });
    try append.record(fd, .{ .op = .rename, .seq = 2, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "/tmp/s/b" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);

    try append.record(fd, .{ .op = .close, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s/b", .aux = "" });
    try append.record(fd, .{ .op = .unresolved, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s/b", .aux = "unlinked-fd write fd:3" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);

    const scanned_before = ts.count_scanned;
    var partial: [2 * contract.max_path]u8 = undefined;
    const pn = try contract.encodeRecord(&partial, .{ .op = .write, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/c", .aux = "" });
    try append.bytes(fd, partial[0 .. pn - 4]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);
    try std.testing.expectEqual(scanned_before, ts.count_scanned);

    try append.bytes(fd, partial[pn - 4 .. pn]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 3), ts.seq);
    try std.testing.expect(ts.count_scanned > scanned_before);

    try append.record(fd, .{ .op = .kill_landed, .seq = 9, .pid = 7, .tid = 7, .path = "/tmp/s/d", .aux = "" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 9), ts.seq);

    try append.record(fd, .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/e", .aux = "" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 9), ts.seq);

    var other: ThreadState = .{};
    try std.testing.expect(refreshCount(&other));
    try std.testing.expectEqual(@as(u32, 9), other.seq);
    try std.testing.expectEqual(ts.count_scanned, other.count_scanned);

    // At least a record's fixed prefix long (22 bytes since v16), or the decoder would
    // read them as a record still being written and the scan would stop politely in
    // front of them instead of refusing — which is what happened when the prefix grew
    // and this array did not.
    try append.bytes(fd, &[_]u8{ 0xff, 0xff, 1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try std.testing.expect(!refreshCount(&ts));

    trace_fd = -1;
    try std.testing.expect(!refreshCount(&ts));
}

test "slots: one per thread id, claimed once, and the reserve past the last" {
    var table: [3]ThreadState = @splat(.{});
    var exhausted = false;
    const claim = struct {
        fn run(t: []ThreadState, res: *ThreadState, flag: *bool, tid: u64) *ThreadState {
            for (t) |*s| {
                if (@atomicLoad(u64, &s.tid, .acquire) == tid) return s;
            }
            for (t) |*s| {
                if (@cmpxchgStrong(u64, &s.tid, 0, tid, .acq_rel, .acquire) == null) return s;
            }
            flag.* = true;
            return res;
        }
    };
    var res: ThreadState = .{};
    const a = claim.run(&table, &res, &exhausted, 101);
    const b = claim.run(&table, &res, &exhausted, 202);
    try std.testing.expectEqual(a, claim.run(&table, &res, &exhausted, 101));
    try std.testing.expect(a != b);
    try std.testing.expect(!exhausted);
    _ = claim.run(&table, &res, &exhausted, 303);
    try std.testing.expect(!exhausted);
    const d = claim.run(&table, &res, &exhausted, 404);
    try std.testing.expectEqual(&res, d);
    try std.testing.expect(exhausted);
    try std.testing.expectEqual(b, claim.run(&table, &res, &exhausted, 202));
}

test "the fork child starts from an empty slot table, however full the parent's was (v16)" {
    slots[0].tid = 1001;
    slots[0].busy = true;
    slots[0].seq = 5;
    slots[0].count_scanned = 99;
    slots[1].tid = 1002;
    slots[2].tid = 1003;
    reserve.tid = 1004;
    reserve.busy = true;
    exhaustion_announced = true;

    resetSlotsInChild();

    for (slots) |s| {
        try std.testing.expectEqual(@as(u64, 0), s.tid);
        try std.testing.expect(!s.busy);
        try std.testing.expectEqual(@as(u32, 0), s.seq);
        try std.testing.expectEqual(@as(u64, 0), s.count_scanned);
    }
    try std.testing.expectEqual(@as(u64, 0), reserve.tid);
    try std.testing.expect(!reserve.busy);
    try std.testing.expect(!exhaustion_announced);
}

test "mine: the 65th thread takes the reserve, and the notice is in the trace at that moment (v16)" {
    if (builtin.os.tag != .macos) resolveAll();
    var bb: [160]u8 = undefined;
    const base = std.mem.printSentinel(&bb, "/tmp/sideeye-shim-slots-{d}", .{c.getpid()}, 0) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.mem.printSentinel(&fb, "{s}/trace.bin", .{base}, 0) catch unreachable;
    defer {
        _ = std.c.unlink(file_z.ptr);
        _ = std.c.rmdir(base.ptr);
    }
    const flags: std.posix.O = @bitCast(O_RDWR | O_CREAT | O_TRUNC | O_APPEND);
    const fd = std.c.open(file_z.ptr, flags, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    defer _ = std.c.close(fd);
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    trace_fd = fd;
    const saved_active = active;
    defer active = saved_active;
    active = true;
    // Leaves the live table the way the other tests in this binary expect to find it.
    defer resetSlotsInChild();
    // The number itself, because nothing else pins it (#543). The loop below fills the
    // live table by its own length, so it proves the overflow path for whatever
    // `max_threads` happens to be — change it to 128 and every test here stays green while
    // DESIGN §9 goes on telling readers that the sixty-fifth thread is refused. If this
    // line fails, two pages carry the number and both need updating: DESIGN §9's threads
    // paragraph and the threads row of `docs/target-classes.md`.
    try std.testing.expectEqual(@as(usize, 64), slots.len);
    for (&slots, 0..) |*s, i| s.tid = 100_000_000 + @as(u64, i);
    exhaustion_announced = false;

    const got = mine();
    try std.testing.expectEqual(&reserve, got);
    try std.testing.expect(exhaustion_announced);
    var buf: [128]u8 = undefined;
    const n = c.pread(fd, &buf, buf.len, 0);
    try std.testing.expect(n > 0);
    const d = try contract.decodeRecord(buf[0..@intCast(n)]);
    try std.testing.expectEqual(contract.OpClass.unresolved, d.rec.op);
    try std.testing.expectEqualStrings(contract.unresolved_kind.thread_slots_exhausted, d.rec.aux);
    try std.testing.expectEqual(currentTid(), d.rec.tid);
    try std.testing.expectEqual(@as(usize, d.consumed), @as(usize, @intCast(n)));
    try std.testing.expectEqual(&reserve, mine());
    try std.testing.expectEqual(n, c.pread(fd, &buf, buf.len, 0));
}

test "exec carry: builds in the thread's own slot, and not on the reserve or when re-entered (#555)" {
    if (builtin.os.tag != .macos) resolveAll();
    const saved_active = active;
    defer active = saved_active;
    const saved_pid = armed_pid;
    defer armed_pid = saved_pid;
    active = true;
    armed_pid = c.getpid();
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    trace_fd = -1;
    defer resetSlotsInChild();
    resetSlotsInChild();
    const argv = [_]?[*:0]const u8{ "x", null };
    const env = [_]?[*:0]const u8{ "SIDEEYE_TEST_EXEC=1", null };
    const nowhere = "/nonexistent-sideeye-test/exec";

    // Control: the thread's own slot, nothing in the way — the array is built.
    const own = mine();
    try std.testing.expect(own != &reserve);
    own.exec_env[0] = null;
    try std.testing.expectEqual(@as(c_int, -1), callExecveSeqCarry(nowhere, &argv, &env));
    try std.testing.expect(own.exec_env[0] != null);
    try std.testing.expect(!own.exec_carrying);

    {
        // Cleared on the way out even when an assertion fails: `resetSlotsInChild` does not
        // touch the flag, and a later test in this binary would find it set.
        own.exec_env[0] = null;
        own.exec_carrying = true;
        defer own.exec_carrying = false;
        try std.testing.expectEqual(@as(c_int, -1), callExecveSeqCarry(nowhere, &argv, &env));
        try std.testing.expect(own.exec_env[0] == null);
    }

    for (&slots, 0..) |*s, i| s.tid = 100_000_000 + @as(u64, i);
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    exhaustion_announced = true;
    try std.testing.expectEqual(&reserve, mine());
    reserve.exec_env[0] = null;
    try std.testing.expectEqual(@as(c_int, -1), callExecveSeqCarry(nowhere, &argv, &env));
    try std.testing.expect(reserve.exec_env[0] == null);
}

fn armForExecSlotTest() void {
    if (builtin.os.tag != .macos) resolveAll();
    resetSlotsInChild();
    active = true;
    trace_fd = -1;
}

test "an exec in the process that owns the slot table keeps the thread's slot and its counts" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    const own = mine();
    own.written = 5;
    _ = noteExecBoundary();
    try std.testing.expectEqual(currentTid(), @atomicLoad(u64, &own.tid, .acquire));
    try std.testing.expectEqual(@as(u32, 5), own.written);
}

test "a process sharing the slot table without owning it gives back the slot it claimed when it execs" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid() + 1;
    const claimed = mine();
    try std.testing.expect(claimed != &reserve);
    claimed.written = 5;
    _ = noteExecBoundary();
    try std.testing.expectEqual(@as(u64, 0), @atomicLoad(u64, &claimed.tid, .acquire));
    try std.testing.expectEqual(@as(u32, 0), claimed.written);
    try std.testing.expect(!claimed.busy);
    try std.testing.expectEqual(claimed, mine());
}

test "a process sharing the slot table keeps a slot it did not claim itself when it execs" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid() + 1;
    const parents = mine();
    parents.claimer_pid = table_pid;
    parents.written = 5;
    _ = noteExecBoundary();
    try std.testing.expectEqual(currentTid(), @atomicLoad(u64, &parents.tid, .acquire));
    try std.testing.expectEqual(@as(u32, 5), parents.written);
}

test "a thread finds its own slot past a slot an exec gave back" {
    const saved_active = active;
    defer active = saved_active;
    defer resetSlotsInChild();
    if (builtin.os.tag != .macos) resolveAll();
    resetSlotsInChild();
    slots[1].tid = currentTid();
    try std.testing.expectEqual(&slots[1], mine());
    try std.testing.expectEqual(@as(u64, 0), slots[0].tid);
}

test "a thread whose exec fails after it gave its slot back carries on with its counts" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid() + 1;
    const claimed = mine();
    claimed.written = 5;
    claimed.creates = 2;
    const loan = noteExecBoundary();
    try std.testing.expectEqual(@as(u64, 0), @atomicLoad(u64, &claimed.tid, .acquire));
    takeBackAfterFailedExec(loan);
    const again = mine();
    try std.testing.expectEqual(@as(u32, 5), again.written);
    try std.testing.expectEqual(@as(u32, 2), again.creates);
}

test "an exec on the reserve gives nothing back" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid() + 1;
    for (&slots, 0..) |*s, i| s.tid = 100_000_000 + @as(u64, i);
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    exhaustion_announced = true;
    try std.testing.expectEqual(&reserve, mine());
    reserve.written = 3;
    _ = noteExecBoundary();
    try std.testing.expectEqual(@as(u32, 3), reserve.written);
    for (&slots, 0..) |*s, i| try std.testing.expectEqual(100_000_000 + @as(u64, i), s.tid);
}

fn clearThreadTablesForTest() void {
    for (&joinable) |*e| e.* = .{};
    for (&pending_starts) |*e| e.* = .{};
}

test "the joinable table: the creator inserts, the joiner takes once, a reused value is overwritten, a full table drops (v18)" {
    clearThreadTablesForTest();
    defer clearThreadTablesForTest();
    joinableInsert(0x1000, 7, 1);
    joinableInsert(0x2000, 7, 2);
    const a = joinableTake(0x1000) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 7), a.creator);
    try std.testing.expectEqual(@as(u32, 1), a.ordinal);
    try std.testing.expect(joinableTake(0x1000) == null);
    joinableInsert(0x2000, 9, 3);
    const b = joinableTake(0x2000) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 9), b.creator);
    try std.testing.expectEqual(@as(u32, 3), b.ordinal);
    try std.testing.expect(joinableTake(0x2000) == null);
    joinableInsert(0, 7, 4);
    joinableInsert(joinable_claiming, 7, 5);
    try std.testing.expect(joinableTake(0) == null);
    try std.testing.expect(joinableTake(joinable_claiming) == null);
    for (&joinable) |*e| try std.testing.expectEqual(@as(usize, 0), e.pthread);
    var i: usize = 0;
    while (i < max_threads) : (i += 1) joinableInsert(0x10000 + i * 16, 1, @intCast(i + 1));
    joinableInsert(0xFFFF0, 1, 99);
    try std.testing.expect(joinableTake(0xFFFF0) == null);
    try std.testing.expectEqual(@as(u32, 1), (joinableTake(0x10000) orelse return error.TestUnexpectedResult).ordinal);
    try std.testing.expectEqual(@as(u32, 64), (joinableTake(0x10000 + 63 * 16) orelse return error.TestUnexpectedResult).ordinal);
}

test "pending starts: sixty-four claims, the sixty-fifth refused, a release makes room again (v18)" {
    clearThreadTablesForTest();
    defer clearThreadTablesForTest();
    var claimed: [max_threads]*PendingStart = undefined;
    for (&claimed) |*slot| slot.* = claimPendingStart() orelse return error.TestUnexpectedResult;
    try std.testing.expect(claimPendingStart() == null);
    @atomicStore(bool, &claimed[3].taken, false, .release);
    try std.testing.expectEqual(claimed[3], claimPendingStart() orelse return error.TestUnexpectedResult);
}

test "writeRecord counts the records that went out, and the fork child's slots and tables start from zero (v18)" {
    // A pid-unique path, as the other trace tests in this file: `zig build test` runs
    // several binaries at once and a fixed name would be shared between them.
    var bb: [128]u8 = undefined;
    const base = std.mem.printSentinel(&bb, "/tmp/sideeye-shim-written-{d}", .{c.getpid()}, 0) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.mem.printSentinel(&fb, "{s}/trace.bin", .{base}, 0) catch unreachable;
    defer {
        _ = std.c.unlink(file_z.ptr);
        _ = std.c.rmdir(base.ptr);
    }
    const flags: std.posix.O = @bitCast(O_RDWR | O_CREAT | O_TRUNC | O_APPEND);
    const fd = std.c.open(file_z.ptr, flags, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    defer _ = std.c.close(fd);
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    trace_fd = fd;
    clearThreadTablesForTest();
    defer clearThreadTablesForTest();

    var ts: ThreadState = .{};
    ts.tid = 424242;
    writeRecord(&ts, .close, 0, "/tmp/x", "");
    writeRecord(&ts, .thread_join, 0, "", "7 1");
    try std.testing.expectEqual(@as(u32, 2), ts.written);
    trace_fd = -1;
    writeRecord(&ts, .close, 0, "/tmp/x", "");
    try std.testing.expectEqual(@as(u32, 2), ts.written);

    slots[0].written = 5;
    slots[0].creates = 2;
    reserve.written = 3;
    reserve.creates = 1;
    joinableInsert(0x3000, 1, 1);
    const pending = claimPendingStart() orelse return error.TestUnexpectedResult;
    try std.testing.expect(pending.taken);
    resetSlotsInChild();
    try std.testing.expectEqual(@as(u32, 0), slots[0].written);
    try std.testing.expectEqual(@as(u32, 0), slots[0].creates);
    try std.testing.expectEqual(@as(u32, 0), reserve.written);
    try std.testing.expectEqual(@as(u32, 0), reserve.creates);
    try std.testing.expect(joinableTake(0x3000) == null);
    for (&pending_starts) |*e| try std.testing.expect(!e.taken);
}

fn departedPid() !c_int {
    const pid = try zombiePid();
    reap(pid);
    return pid;
}

// Not reaped: running or a zombie, `kill` answers either way, however privileged the test.
fn zombiePid() !c_int {
    const pid = std.c.fork();
    if (pid < 0) return error.SkipZigTest;
    if (pid == 0) std.c._exit(0);
    return pid;
}

fn reap(pid: c_int) void {
    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
}

test "a full table takes back a slot whose claimer has exited, and no slot whose claimer is alive" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid();
    exhaustion_announced = true;
    const zombie = try zombiePid();
    defer reap(zombie);
    const gone = try departedPid();
    for (&slots, 0..) |*s, i| {
        s.tid = 100_000_000 + @as(u64, i);
        s.claimer_pid = zombie;
    }
    slots[6].claimer_pid = 0;
    slots[7].claimer_pid = table_pid;
    slots[5].claimer_pid = gone;
    slots[5].seq = 4;
    slots[5].count_scanned = 77;
    slots[5].written = 9;
    slots[5].creates = 3;
    slots[5].busy = true;
    slots[5].exec_carrying = true;
    std.c._errno().* = 0;

    const got = mine();
    try std.testing.expectEqual(@as(c_int, 0), std.c._errno().*);
    try std.testing.expectEqual(&slots[5], got);
    try std.testing.expectEqual(currentTid(), got.tid);
    try std.testing.expectEqual(c.getpid(), got.claimer_pid);
    try std.testing.expectEqual(@as(u32, 0), got.seq);
    try std.testing.expectEqual(@as(u64, 0), got.count_scanned);
    try std.testing.expectEqual(@as(u32, 0), got.written);
    try std.testing.expectEqual(@as(u32, 0), got.creates);
    try std.testing.expect(!got.busy);
    try std.testing.expect(!got.exec_carrying);
    for (&slots, 0..) |*s, i| if (i != 5) try std.testing.expectEqual(100_000_000 + @as(u64, i), s.tid);
    try std.testing.expectEqual(got, mine());
}

test "a full table whose claimers are all alive still hands out the reserve" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid();
    exhaustion_announced = true;
    const zombie = try zombiePid();
    defer reap(zombie);
    for (&slots, 0..) |*s, i| {
        s.tid = 100_000_000 + @as(u64, i);
        s.claimer_pid = if (i % 2 == 0) zombie else table_pid;
    }
    try std.testing.expectEqual(&reserve, mine());
}

test "a slot found by this thread's id under a departed claimer becomes this process's, and is not taken back" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid();
    exhaustion_announced = true;
    const gone = try departedPid();
    for (&slots, 0..) |*s, i| {
        s.tid = 100_000_000 + @as(u64, i);
        s.claimer_pid = table_pid;
    }
    slots[3].tid = currentTid();
    slots[3].claimer_pid = gone;
    slots[3].written = 7;
    try std.testing.expectEqual(&slots[3], mine());
    try std.testing.expectEqual(table_pid, slots[3].claimer_pid);
    try std.testing.expectEqual(@as(u32, 7), slots[3].written);
}

test "a slot another thread is taking back is not used, even under this thread's id" {
    const saved_active = active;
    defer active = saved_active;
    const saved_fd = trace_fd;
    defer trace_fd = saved_fd;
    defer resetSlotsInChild();
    armForExecSlotTest();
    table_pid = c.getpid();
    for (&slots, 0..) |*s, i| {
        s.tid = 100_000_000 + @as(u64, i);
        s.claimer_pid = table_pid;
    }
    slots[3].tid = currentTid();
    slots[3].claimer_pid = reclaiming;
    slots[6].tid = 0;
    slots[6].claimer_pid = 0;
    try std.testing.expectEqual(&slots[6], mine());
    try std.testing.expectEqual(reclaiming, slots[3].claimer_pid);
}

const sweep_trace_path = "/tmp/sideeye-sweep-test-trace";
const sweep_other_path = "/tmp/sideeye-sweep-test-other";

const SweepTestState = struct {
    active: bool,
    trace_fd: c_int,
    trace_path_len: usize,
    trace_identity: ?FileIdentity,
    kill_cgroup_fd: c_int,
    kill_cgroup_path_len: usize,
    kill_aside_fd: c_int,

    fn save() SweepTestState {
        return .{
            .active = active,
            .trace_fd = trace_fd,
            .trace_path_len = trace_path_len,
            .trace_identity = trace_identity,
            .kill_cgroup_fd = kill_cgroup_fd,
            .kill_cgroup_path_len = kill_cgroup_path_len,
            .kill_aside_fd = kill_aside_fd,
        };
    }

    fn restore(s: SweepTestState) void {
        active = s.active;
        trace_fd = s.trace_fd;
        trace_path_len = s.trace_path_len;
        trace_identity = s.trace_identity;
        kill_cgroup_fd = s.kill_cgroup_fd;
        kill_cgroup_path_len = s.kill_cgroup_path_len;
        kill_aside_fd = s.kill_aside_fd;
        resetSlotsInChild();
    }
};

fn openFileAt(path: [*:0]const u8, at: c_int) !void {
    const fd = callOpen(path, O_RDWR | O_CREAT | O_TRUNC | O_APPEND, 0o600);
    if (fd < 0) return error.SkipZigTest;
    defer _ = callClose(fd);
    if (std.os.linux.errno(std.os.linux.dup3(fd, at, @as(u32, @bitCast(O_CLOEXEC)))) != .SUCCESS) return error.SkipZigTest;
}

fn armSweepTrace(at: c_int) !void {
    armForExecSlotTest();
    kill_cgroup_fd = -1;
    kill_aside_fd = -1;
    try openFileAt(sweep_trace_path, at);
    keepName(&trace_path_buf, &trace_path_len, sweep_trace_path);
    trace_identity = fileIdentity(at);
    trace_fd = at;
}

fn fileHolds(path: [*:0]const u8) []const u8 {
    const S = struct {
        var buf: [256]u8 = undefined;
    };
    const fd = callOpen(path, O_RDONLY, 0);
    if (fd < 0) return "";
    defer _ = callClose(fd);
    const n = std.c.read(fd, &S.buf, S.buf.len);
    return if (n <= 0) "" else S.buf[0..@intCast(n)];
}

fn holdsTraceDeath(path: [*:0]const u8) bool {
    return std.mem.indexOf(u8, fileHolds(path), contract.unresolved_kind.trace_closed) != null;
}

fn withNofileSoftLimit(soft: u64) !std.posix.rlimit {
    const was = try std.posix.getrlimit(.NOFILE);
    std.posix.setrlimit(.NOFILE, .{ .cur = soft, .max = was.max }) catch return error.SkipZigTest;
    return was;
}

test "a sweep that closed the trace puts the same file back on its number, and says nothing" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(950);
    defer _ = callClose(950);
    _ = callClose(950);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, 950), trace_fd);
    try std.testing.expect(isTraceFile(950));
    try std.testing.expectEqualStrings("", fileHolds(sweep_trace_path));
}

test "a sweep whose restore fails says so through the reopened trace before it drops the channel" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(950);
    const was = try withNofileSoftLimit(256);
    defer std.posix.setrlimit(.NOFILE, was) catch {};
    _ = callClose(950);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, -1), trace_fd);
    try std.testing.expect(holdsTraceDeath(sweep_trace_path));
}

test "a process sharing the table without owning it leaves the shared trace number alone when the restore fails" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(950);
    const was = try withNofileSoftLimit(256);
    defer std.posix.setrlimit(.NOFILE, was) catch {};
    table_pid = c.getpid() + 1;
    _ = callClose(950);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, 950), trace_fd);
    try std.testing.expect(holdsTraceDeath(sweep_trace_path));
}

test "a trace below the relocation floor is never put back, and its death goes through the reopened file" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(150);
    _ = callClose(150);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, -1), trace_fd);
    try std.testing.expect(descriptorClosed(150));
    try std.testing.expect(holdsTraceDeath(sweep_trace_path));
}

test "a trace number that now holds another file is dropped with a death, and nothing is written into that file" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(950);
    defer _ = callClose(950);
    _ = callClose(950);
    try openFileAt(sweep_other_path, 950);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, -1), trace_fd);
    try std.testing.expect(!isTraceFile(950));
    try std.testing.expectEqualStrings("", fileHolds(sweep_other_path));
    try std.testing.expect(holdsTraceDeath(sweep_trace_path));
}

fn claimAndLeave() void {
    _ = mine();
}

fn claimAndWait(hold: *std.atomic.Value(bool), claimed: *std.atomic.Value(bool)) void {
    _ = mine();
    claimed.store(true, .release);
    while (hold.load(.acquire)) std.atomic.spinLoopHint();
}

test "a thread that has exited does not count as another thread here, and a live one does" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    armForExecSlotTest();
    _ = mine();
    const gone = try std.Thread.spawn(.{}, claimAndLeave, .{});
    gone.join();
    // Not asked once: `join` returns when the kernel clears the thread's id, a moment before it
    // reaps the thread, and `tgkill` still finds it until then.
    var tries: usize = 0;
    while (otherThreadsHere() and tries < 1000) : (tries += 1) {
        const ms: std.os.linux.timespec = .{ .sec = 0, .nsec = 1_000_000 };
        _ = std.os.linux.nanosleep(&ms, null);
    }
    try std.testing.expect(!otherThreadsHere());

    var hold = std.atomic.Value(bool).init(true);
    var claimed = std.atomic.Value(bool).init(false);
    const live = try std.Thread.spawn(.{}, claimAndWait, .{ &hold, &claimed });
    defer live.join();
    defer hold.store(false, .release);
    while (!claimed.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(otherThreadsHere());
}

test "a sweep that closed cgroup.kill puts the same file back on its number" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    armForExecSlotTest();
    kill_aside_fd = -1;
    try openFileAt(sweep_other_path, 951);
    defer _ = callClose(951);
    const before = fileIdentity(951);
    keepName(&kill_cgroup_path_buf, &kill_cgroup_path_len, sweep_other_path);
    kill_cgroup_fd = 951;
    _ = callClose(951);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, 951), kill_cgroup_fd);
    try std.testing.expect(before != null);
    try std.testing.expect(std.meta.eql(fileIdentity(951), before));
}

test "a sweep that closed cgroup.kill below the relocation floor leaves it closed and drops it" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    armForExecSlotTest();
    kill_aside_fd = -1;
    try openFileAt(sweep_other_path, 150);
    keepName(&kill_cgroup_path_buf, &kill_cgroup_path_len, sweep_other_path);
    kill_cgroup_fd = 150;
    _ = callClose(150);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, -1), kill_cgroup_fd);
    try std.testing.expect(descriptorClosed(150));
}

test "a sweep the trace comes back from still says so when another thread here is alive" {
    if (is_darwin) return error.SkipZigTest;
    const saved = SweepTestState.save();
    defer saved.restore();
    try armSweepTrace(950);
    defer _ = callClose(950);
    _ = mine();
    var hold = std.atomic.Value(bool).init(true);
    var claimed = std.atomic.Value(bool).init(false);
    const live = try std.Thread.spawn(.{}, claimAndWait, .{ &hold, &claimed });
    defer live.join();
    defer hold.store(false, .release);
    while (!claimed.load(.acquire)) std.atomic.spinLoopHint();
    _ = callClose(950);
    afterSweep();
    try std.testing.expectEqual(@as(c_int, 950), trace_fd);
    try std.testing.expect(isTraceFile(950));
    try std.testing.expect(holdsTraceDeath(sweep_trace_path));
}
