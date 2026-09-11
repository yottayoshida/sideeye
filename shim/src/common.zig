//! The part of the shim that does not depend on how symbols get replaced.
//!
//! Everything here runs *inside somebody else's process*, which sets the rules:
//! no heap, no standard-library I/O, no locks, no assumptions about what the target
//! has already initialised. State lives in globals; buffers are fixed and static.
//!
//! Through contract v15 this module supported single-threaded targets only — a target
//! that created a thread was refused, so the globals needed no synchronisation, and a
//! lock would have hidden the very condition to report. A run whose threads never write
//! the judged directory is judged now (v16), and its other threads still pass through
//! every interposed entry point, so the state one interposed call needs — the
//! re-entrancy guard, the record buffer, the count scan — is **per thread**, held in a
//! slot keyed by thread id (`ThreadState`, below). What stays process-wide is read-only
//! after `init`. There is still no lock: two threads writing the judged directory are
//! refused by the engine, not serialised here, and `refreshCount`'s comment says why the
//! numbering survives the race that leaves.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
/// Build-time only (#270). `test_seq_gap` is false in every shipped shim — build.zig
/// hardcodes false into libsideeye_shim's own options module regardless of any -D
/// flag, and true only into the separately named libsideeye_shim_testgap that
/// `-Dtest-seq-gap` additionally produces. There is no runtime knob: an environment
/// variable that could bend the numbering would be a production backdoor.
///
/// Since #365 that hardcoded `false` is held by a test at the bottom of this file rather
/// than by this paragraph alone. CI's sha comparison covers the FLAG leaking into the
/// shipped shim; an edit to the literal itself lands in both arms of that comparison and
/// leaves it green.
const shim_build_options = @import("shim_build_options");

/// The syscall-layer observation path (contract v14, Linux only).
///
/// Imported behind a platform test rather than unconditionally: the module speaks
/// seccomp, `ucontext` register offsets and `SIGSYS`, none of which exist on Darwin, and
/// an unconditional import would make the macOS build analyse them. The stub carries the
/// same three names so every use site below reads the same on both platforms.
const syscalls = if (builtin.os.tag == .linux) @import("syscalls.zig") else struct {
    pub var armed: bool = false;
    pub const Install = enum { armed, unsupported, failed };
    pub fn install() Install {
        return .unsupported;
    }
    pub fn traceWrite(_: c_int, _: [*]const u8, _: usize) isize {
        return -1;
    }
};

/// Whether a `write` recorded at a libc entry point would be recorded a second time at
/// the syscall boundary.
///
/// True for exactly the four syscalls `syscalls.zig` traps. `copy_file_range` and
/// `sendfile` are not among them and their wrappers keep recording, because libc never
/// issues those from inside stdio so the wrapper sees every call that is not raw.
/// `pwritev2` is not among them either and is handled a third way — refused rather than
/// counted, for the reason spelled out where its wrapper is (`ops.zig`): neither counting
/// it here nor silencing it is correct on both kernels.
pub inline fn writeCountedAtSyscall() bool {
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
    pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
    /// Reads the trace back to find the run's highest operation number (v15). Not
    /// interposed — the shim wraps writes, not reads — so this extern reaches libc
    /// directly on both platforms, and `--observe syscalls` does not trap it either
    /// (`syscalls.zig` traps `write`/`pwrite64`/`writev`/`pwritev` and nothing else).
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
    /// Coarse, and that is all it is for: the temp-name creators mix it with the pid
    /// and a counter so two runs of one pid do not produce one name sequence (#39).
    /// `time_t` is 64-bit on both platforms this builds for.
    pub extern "c" fn time(t: ?*i64) i64;
    /// Only the subject calls these (execSeqCarrySet guards on getpid == armed_pid),
    /// so the heap they may touch is never a vfork parent's shared one.
    pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
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
/// The two `renameat2` flags that make it something other than a rename (Linux only;
/// values from `std.os.linux.RENAME`'s bit order). NOREPLACE has no constant here
/// because nothing branches on it — it IS a rename, so it takes the default path.
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
/// `struct attrlist.commonattr` bit for the entry's name (v12): the one bit that turns
/// a metadata call into a rename.
pub const ATTR_CMN_NAME: u32 = 0x00000001;
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
/// Public for the same reason as `O_CREAT`: `ops.zig`'s temp-name creators build the
/// open the real `mkstemp` builds, rather than forwarding to it (#39). Read from the
/// two platforms' headers rather than recalled — `O_RDWR` happens to agree and
/// `O_EXCL` does not, which is exactly the pair a memory would get wrong.
pub const O_RDWR: c_int = 0x2;
pub const O_EXCL: c_int = if (is_darwin) 0x800 else 0o200;
/// The access-mode mask and O_TRUNC agree across Linux and Darwin; O_CREAT does not
/// and is branched above. Public for the same reason as the three above: `ops.zig`'s
/// temp-name creators need it to strip what glibc strips out of a caller's flags.
pub const O_ACCMODE: c_int = 0o3;
const O_TRUNC: c_int = if (is_darwin) 0x400 else 0o1000;
/// Derived from `std.posix.O` rather than written out the way this block's other flags are,
/// and it is the only one that must be. (Eight neighbours, five of which branch on the
/// platform: `O_CREAT`, `O_APPEND`, `O_CLOEXEC`, `O_EXCL`, `O_TRUNC`. The other three —
/// `O_WRONLY`, `O_RDWR`, `O_ACCMODE` — agree everywhere and are plain literals.)
///
/// The value differs *within* Linux by architecture — 0o400000 on x86_64, 0o100000 on
/// aarch64 — so the `is_darwin` shape above cannot express it. The engine's copy carried
/// the x86_64 number for all of Linux once, which left the one guard that used it inert on
/// arm64: measured in an arm64 container, a symlink planted at a capture path was opened
/// straight through (#316). The five literals above were checked on three targets then and
/// are right; a sixth written the same way is where the next one goes wrong.
/// `src/posix.zig` derives it for exactly this reason, and this is the same derivation, so
/// the two sides cannot drift apart.
///
/// The `@bitCast` is comptime: no heap, no libc, no runtime code — the rule this file
/// opens with holds.
const O_NOFOLLOW: c_int = blk: {
    var f: std.posix.O = .{};
    f.NOFOLLOW = true;
    break :blk @bitCast(f);
};

/// Derived the same way `O_NOFOLLOW` above is, for a weaker reason: this value does not
/// vary within a platform, so a literal would have been right here. It is derived anyway
/// because the warning in that comment is about the *writing*, not about which values
/// happen to be safe — the next flag written by hand is where the next one goes wrong.
/// Its example is not one of the five literals above; those were checked on three targets
/// and are right. It is the engine's `O_NOFOLLOW`, which carried the x86_64 number for all
/// of Linux and left its one caller inert on arm64 (#316).
/// `src/posix.zig` keeps a literal for the engine's copy of this flag and
/// stays that way: `build.zig` gives this file's test module `contract`,
/// `engine_build_options` and `shim_build_options`, with no edge to `posix.zig`, so a test
/// pinning the two against each other cannot be written from this side. Deriving is what
/// removes the need for one.
const O_NONBLOCK: c_int = blk: {
    var f: std.posix.O = .{};
    f.NONBLOCK = true;
    break :blk @bitCast(f);
};

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
/// The vectored positional writes (#256). `pwritev2` differs only by its trailing
/// flags argument; both keep the descriptor first, so scope reads argument 0 on
/// either observer.
pub const PwritevFn = *const fn (c_int, *const anyopaque, c_int, i64) callconv(.c) isize;
pub const Pwritev2Fn = *const fn (c_int, *const anyopaque, c_int, i64, c_int) callconv(.c) isize;
/// The kernel copy primitives (#244). `copy_file_range` is the one whose destination
/// is not the first argument — src/oracle.zig's `fd_write_args` carries the same fact
/// for the other observer.
pub const CopyFileRangeFn = *const fn (c_int, ?*i64, c_int, ?*i64, usize, c_uint) callconv(.c) isize;
pub const SendfileFn = *const fn (c_int, c_int, ?*i64, usize) callconv(.c) isize;
pub const RenameFn = *const fn ([*:0]const u8, [*:0]const u8) callconv(.c) c_int;
pub const RenameatFn = *const fn (c_int, [*:0]const u8, c_int, [*:0]const u8) callconv(.c) c_int;
/// `renameat2` adds flags, and the flags change what the call MEANS (#256):
/// `RENAME_EXCHANGE` swaps two files atomically and `RENAME_WHITEOUT` creates a
/// whiteout inode — neither is the plain rename `note2(.rename, …)` models.
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
    if (!active or mine().busy) return;
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
    if (writeCountedAtSyscall()) return;
    if (pendingBytes(stream) == 0) return;
    noteFd(.write, c.fileno(stream));
}

pub fn noteStdioClose(stream: *FILE) void {
    if (!active or mine().busy) return;
    if (!stdioActive()) return;
    noteFd(.close, c.fileno(stream));
}

/// Whether a flush is due, for the freopen wrapper's explicit pre-flush. Same guards
/// as noteStdioFlush: an inactive shim answers "no" without touching the stream.
pub fn stdioHasPending(stream: *FILE) bool {
    if (!active or mine().busy) return false;
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
/// Whether the crash-point kill may reach the whole process group (v15). False unless the
/// engine says so, which it does only where it has made the target a group leader.
var kill_group: bool = false;
/// Per-thread state (contract v16).
///
/// Through v15 the five fields below were plain globals, and this module's first
/// paragraph said why that was safe: a target that created a thread was refused, so
/// nothing ever shared them. A run whose threads never write the judged directory is
/// judged now, and its worker threads still pass through every interposed entry point —
/// `open` on a library, `write` on a pipe — so the re-entrancy guard, the record buffer
/// and the count scan would be shared between threads the design never meant to share
/// them. Measured before this existed: a worker opening `/dev/null` in a loop set the
/// process-wide `busy`, and the main thread's in-scope write, arriving inside that
/// window, was dropped without a record.
///
/// **Slots keyed by thread id, not `threadlocal`.** A shared object's `threadlocal`
/// compiles to the general-dynamic TLS model, whose first access from a thread takes
/// `__tls_get_addr`'s slow path under the loader's lock; under `--observe syscalls` that
/// first access can happen inside the `SIGSYS` handler, and a lock taken in a signal
/// handler is what this module's rules forbid. Whether it happens depends on the target
/// and on the C library, so a run that worked would prove nothing about the next one. A
/// fixed array keyed by `gettid()` — one syscall, one compare-and-swap — is
/// async-signal-safe by construction. Slots are never freed: nothing here sees a thread
/// end. The 65th thread shares `reserve`, whose `busy` is the old process-wide guard,
/// and the run records `thread-slots-exhausted` once so the engine refuses it rather
/// than judges it.
///
/// Zero-initialised on purpose, not `undefined`: an all-zero global lands in `.bss`,
/// and sixty-five of these — some 72 KB each since the scratch buffers moved in (#555) —
/// are nearly five megabytes the file need not carry. Only the pages a thread touches
/// become memory.
const ThreadState = struct {
    /// Owner's thread id; 0 is free. Written once, by the compare-and-swap in `mine`.
    tid: u64 = 0,
    /// Guards against observing our own work. The path resolution below calls libc, and
    /// while none of those calls are interposed today, a future addition to the symbol
    /// list would silently start recording the shim's own behaviour as the target's.
    busy: bool = false,
    /// Guards `exec_env` alone (#555): an exec from a signal handler that interrupted the
    /// carry on this thread finds it set and drops its own carry. Not `busy`, which would
    /// also stop the shim recording anything else that handler does — recorded before the
    /// array moved here.
    exec_carrying: bool = false,
    /// The highest in-scope operation number this thread knows the RUN to have reached
    /// (v15) — not a count of its own operations. `refreshCount` brings it up to what the
    /// trace holds before every number is handed out, so a parent that resumes after an
    /// awaited child continues from the child's last number instead of from its own.
    seq: u32 = 0,
    /// How far into the trace `seq` has been read. Only complete records advance it, so a
    /// record still being written is read again next time rather than skipped.
    count_scanned: u64 = 0,
    /// Where `refreshCount` decodes. Static rather than a stack array because this runs
    /// from arbitrary interposed calls and, under `--observe syscalls`, from inside the
    /// SIGSYS handler — 8 KB of stack is not a thing to spend there.
    scan_buf: [contract.max_record_len]u8 = [_]u8{0} ** contract.max_record_len,
    /// One record is built here and written with a single `write(2)`, so a trace never
    /// ends with half a record even when the process dies mid-run.
    record_buf: [contract.max_record_len]u8 = [_]u8{0} ** contract.max_record_len,

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
    resolve_base: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    observe_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    observe_aux: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    note1_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    note2_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    note2_aux: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    unsup2_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    unsup2_canon: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    unsup2_aux: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    unsup2_aux_canon: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    unsup_fd_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    fd_path: [contract.max_path]u8 = [_]u8{0} ** contract.max_path,
    exec_env: [max_env_entries + 1]?[*:0]const u8 = [_]?[*:0]const u8{null} ** (max_env_entries + 1),
};
const max_threads = 64;
var slots: [max_threads]ThreadState = [_]ThreadState{.{}} ** max_threads;
var reserve: ThreadState = .{};
/// Whether the exhaustion notice has been written (v16). Taken with a compare-and-swap by
/// the one thread that writes it — two threads overflowing together race for it and one
/// wins — and cleared only by `resetSlotsInChild`. There is no separate "exhausted" flag:
/// one existed and nothing in production read it.
var exhaustion_announced: bool = false;
var active: bool = false;

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

/// This thread's slot, claimed on first sight. Linear over the array on every interposed
/// call: the syscall for the id costs more than the scan does, and both are measured in
/// BUILDLOG (2026-09-08) before the cost is claimed anywhere.
fn mine() *ThreadState {
    const tid = currentTid();
    // One pass: our own slot if we have one, else the first free one seen on the way —
    // claimed by compare-and-swap, and if another thread took it meanwhile, the scan
    // continues from there. Slots are never freed, so a slot seen taken stays taken.
    var i: usize = 0;
    while (i < slots.len) : (i += 1) {
        const owner = @atomicLoad(u64, &slots[i].tid, .acquire);
        if (owner == tid) return &slots[i];
        if (owner == 0 and @cmpxchgStrong(u64, &slots[i].tid, 0, tid, .acq_rel, .acquire) == null) return &slots[i];
    }
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
    if (@cmpxchgStrong(bool, &exhaustion_announced, false, true, .acq_rel, .acquire) == null) {
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

/// After `fork`, in the child (v16). The child inherits the table as the parent had it —
/// every parent thread still claiming its slot, `busy` flags mid-call included — and has
/// exactly one thread, with a new id. Left alone, a parent that had used the table up
/// would leave its single-threaded child no slot at all (a false `thread-slots-exhausted`),
/// and a later thread of the child that reuses a parent thread's id would inherit a slot
/// whose `busy` was true at the fork and record nothing through it. Review found both.
/// Called from the fork wrapper's child arm, before the child records anything. `vfork`
/// must not do this — the child runs in the parent's memory — and a raw `clone` bypasses
/// the wrapper and inherits the table as it stands: a parent past sixty-four threads that
/// forks through a raw syscall keeps the false refusal, which is the honest direction.
/// The claim words and the counters are cleared and the buffers are not: sixty-five slots
/// of some 72 KB each are nearly five megabytes of copy-on-write pages the child would
/// otherwise touch at once, and every buffer is written whole before it is read.
pub fn resetSlotsInChild() void {
    for (&slots) |*s| {
        s.tid = 0;
        s.busy = false;
        s.seq = 0;
        s.count_scanned = 0;
    }
    reserve.tid = 0;
    reserve.busy = false;
    reserve.seq = 0;
    reserve.count_scanned = 0;
    exhaustion_announced = false;
}
/// The pid this shim instance initialised in. Read by `execCarryAllowed` — only the
/// subject carries its operation count across an image change (#123).
///
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

fn resolveAll() void {
    real.open = lookup(OpenFn, "open");
    real.openat = lookup(OpenatFn, "openat");
    real.creat = lookup(CreatFn, "creat");
    real.write = lookup(WriteFn, "write");
    real.pwrite = lookup(PwriteFn, "pwrite");
    real.writev = lookup(WritevFn, "writev");
    // Optional symbols (#244, #256): unlike the wrappers above, these can genuinely
    // be absent — pwritev2 needs glibc 2.26, copy_file_range 2.27, renameat2 2.28,
    // and musl spells some of them differently. `optionalMissing` below turns a null
    // into ENOSYS rather than a bare -1, because a target that reads errno to decide
    // whether to fall back (Rust std's kernel_copy does exactly this) must see the
    // reason. Of these five only `pwritev` exists on macOS, and only its helper has
    // a darwin branch; the rest are Linux-only calls whose lookup is the only path.
    real.pwritev = lookup(PwritevFn, "pwritev");
    real.pwritev2 = lookup(Pwritev2Fn, "pwritev2");
    real.copy_file_range = lookup(CopyFileRangeFn, "copy_file_range");
    real.sendfile = lookup(SendfileFn, "sendfile");
    real.rename = lookup(RenameFn, "rename");
    real.renameat = lookup(RenameatFn, "renameat");
    real.renameat2 = lookup(Renameat2Fn, "renameat2");
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
    // process onward. A hard link therefore stays unrefused; README says so rather than
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
    //
    // `O_NONBLOCK` is the half of #492 that has to be on the open itself: a FIFO with no
    // reader answers `O_WRONLY` by blocking until one arrives, and this open runs from
    // `.init_array` inside a recording run that has nothing to time it out. With the flag
    // it answers `ENXIO` instead. The flag is without effect on a regular file, so the
    // ordinary path is unchanged. **Under `O_RDWR` that reason no longer holds** — a
    // readerless FIFO opens straight away for read-write — so the flag is no longer what
    // keeps this open from hanging. What refuses a FIFO now is `traceTargetIsOrdinary`
    // below, which was already the half of #492 covering a FIFO someone is reading, a
    // device and a socket. The flag stays because it costs nothing on a regular file and
    // because dropping it would need `F_SETFL`, which replaces the whole status word.
    trace_fd = callOpen(tp, O_RDWR | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o644);
    // Refused is silent-then-not-ready, deliberately for now: the engine reports
    // `no_shim_marker` (or, in a world, `kill_did_not_land`) and neither names the path.
    // Saying which of the two it was is a separate promise — it has three call sites that
    // refuse differently — and it is filed rather than folded in here.
    if (trace_fd < 0) return;

    // The other half of #492, and the flag alone does not cover it: a FIFO somebody is
    // *already reading* opens fine, and the records would go into it. So would a device or
    // a socket planted at the name. `traceTargetIsOrdinary` reads what the descriptor
    // turned out to be — the same question `kindOfFd` answers for the engine's read (#400),
    // asked on this side for the first time.
    //
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
    // Only a run the engine put in its own process group may take the group down; see
    // `contract.env.kill_group` for why the shim cannot decide this for itself.
    kill_group = c.getenv(contract.env.kill_group) != null;

    // A self-exec'd image continues the subject's numbering (#123): the exec wrapper
    // of the previous image carried the count here. Absent means a fresh start —
    // for the first image that is correct, and for an image that arrived through a
    // non-interposed exec path (execl family, fexecve, a stripped environment) the
    // fresh start is what the engine's continuation predicate refuses on.
    // Into the initialising thread's own slot: `init` runs from `.init_array`, before the
    // target has created any thread, so this is the main thread's, and the announcement
    // below is written from the same slot.
    const ts = mine();
    if (c.getenv(contract.env.seq_base)) |b| ts.seq = parseU32(std.mem.span(b));

    armed_pid = c.getpid();

    // The filter goes up before the first byte of the trace is written, because
    // `writeAll` has to know which way to issue its own writes. `active` is still false
    // here, so a failed install records nothing and leaves the announcement to say so.
    var observe_note: []const u8 = "";
    if (c.getenv(contract.env.observe)) |raw| {
        if (contract.ObserveMode.parse(std.mem.span(raw))) |mode| switch (mode) {
            .wrappers => {},
            .syscalls => observe_note = switch (syscalls.install()) {
                .armed => contract.observe_aux.armed,
                .failed => contract.observe_aux.failed,
                .unsupported => contract.observe_aux.unsupported,
            },
        } else {
            // An unparseable value is the engine's bug, not the target's. Announcing it
            // as a failed install is what makes the engine refuse rather than silently
            // fall back to the default mode and report a verdict for the wrong one.
            observe_note = contract.observe_aux.failed;
        }
    }

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
        // Through the thunk when the filter is up: libc's `write` would trap, the
        // handler would record, and recording writes another record — recursion with
        // no bottom. `traceWrite` carries the sentinel the filter allows.
        const w = if (syscalls.armed)
            syscalls.traceWrite(trace_fd, bytes[off..].ptr, bytes.len - off)
        else
            callWrite(trace_fd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return false;
        off += @intCast(w);
    }
    return true;
}

/// The pid is taken here, once for every record, rather than accepted from the caller:
/// there is exactly one correct value and it is whoever is executing this line.
///
/// The buffer is the calling thread's (v16). The exhaustion notice is the one record
/// written through the shared `reserve` buffer, and `mine` writes it at the moment of
/// overflow rather than here, so it is in the trace whether or not anything is recorded
/// afterwards.
fn writeRecord(ts: *ThreadState, op: contract.OpClass, s: u32, path: []const u8, aux: []const u8) void {
    encodeAndWrite(&ts.record_buf, op, s, path, aux);
}

fn encodeAndWrite(buf: *[contract.max_record_len]u8, op: contract.OpClass, s: u32, path: []const u8, aux: []const u8) void {
    const rec: contract.Record = .{
        .op = op,
        .seq = s,
        .pid = @bitCast(c.getpid()),
        .tid = currentTid(),
        .path = path,
        .aux = aux,
    };
    const n = contract.encodeRecord(buf, rec) catch return;
    _ = writeAll(buf[0..n]);
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
    // The path is empty on purpose: nothing was named here. Before #485 the reason
    // rode in the path field as "trace:closed-by-target", which the engine would
    // now print as the name the file last had — a filename that never existed.
    writeRecord(mine(), .unresolved, 0, "", contract.unresolved_kind.trace_closed);
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

/// An operation that was seen but could not be placed.
///
/// Dropping it silently is the failure this whole tool exists to avoid: the engine
/// would then see a trace that is complete as far as it can tell, and PASS is the
/// honest-looking answer to that. Recorded instead, so the engine can refuse to judge.
/// `kind` names WHY the operation could not be placed, in the `aux` field (#485).
///
/// The refusal used to be one fixed sentence for every one of these call sites, so two
/// targets failing for different reasons produced identical output and the operator
/// could not tell them apart. `class` and `seq` cannot carry it — this record type
/// always writes `.unresolved` and `0` — and `path` is already spoken for (it is the
/// name the file had, where there was one). `aux` is free here: for `.unresolved` the
/// engine never reads it as a path, because `isMarker()` takes the record out of the
/// snapshot walk's name matching (`engine/snapshot.zig`).
///
/// The argument has no default on purpose: a new call site has to choose a kind, and
/// forgetting it is a compile error rather than a record that says nothing.
fn noteUnresolved(ts: *ThreadState, path: []const u8, kind: []const u8) void {
    writeRecord(ts, .unresolved, 0, path, kind);
}

/// Bring `seq` up to the highest operation number the trace holds (v15).
///
/// The trace is the source of the count because nothing else can be. A parent cannot be
/// told what its children consumed — an environment variable travels one way, and
/// `system()` and `popen()` spawn and wait from inside libc where no wrapper sees them —
/// while the trace is written by every process that records anything and is created fresh
/// for every run, so a number read from it cannot be stale from a previous world.
///
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
                // Anything else means the bytes at this offset are not a record this
                // contract can produce. Whoever wrote them is not the shim, and the count
                // derived from them would be a guess.
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

/// The single place where an operation becomes a counted event, and the single place
/// where the process dies.
fn observe(ts: *ThreadState, op: contract.OpClass, raw_path: []const u8, raw_aux: []const u8) void {
    // Both spellings count; one is recorded.
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
        // The number comes from the run, not from this process (v15). Read before the
        // increment and inside the scope test, so a target that never writes in the judged
        // directory reads nothing at all and an out-of-scope operation costs no syscall.
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
            // The group where the engine arranged one, this process alone otherwise —
            // which is what an operator typing the report's `reproduce` line gets, and
            // what every run got before v15.
            _ = if (kill_group) c.kill(0, SIGKILL) else c.raise(SIGKILL);
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
    writeRecord(ts, op, s, path, aux);
}

pub fn note1(op: contract.OpClass, dirfd: c_int, path: [*:0]const u8) void {
    if (!active) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var unresolvable = false;
    const resolved = resolveAt(ts, &ts.note1_path, dirfd, path, &unresolvable) orelse {
        // Recorded only when the path genuinely could not be determined. A descriptor
        // that names no path at all says the operation is elsewhere, which is an answer.
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
///
/// `noteUnresolved` is deliberately not this function: that one is unconditional, and
/// its one caller class is justified in being so because the *path cannot be resolved*
/// — there is nothing to scope-gate on. Here the paths resolve fine; the operation's
/// meaning is what the model lacks. `label` is the syscall-and-flag spelling the
/// refusal will show ("renamex_np(RENAME_SWAP)"), the same shape Linux's shows.
pub fn noteUnsupportedInScope2(
    label: [*:0]const u8,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: ?[*:0]const u8,
) void {
    if (!active) return;
    const ts = mine();
    if (ts.busy) return;
    ts.busy = true;
    defer ts.busy = false;

    var unresolvable = false;
    var in_scope = false;
    if (resolveAt(ts, &ts.unsup2_path, dirfd, path, &unresolvable)) |resolved| {
        in_scope = contract.isInsideDir(canonical(&ts.unsup2_canon, resolved), stateDir());
    } else if (unresolvable) {
        // Cannot place it, so cannot clear it: the unconditional channel is right
        // exactly here, for the reason its own doc gives.
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

pub fn note2(
    op: contract.OpClass,
    dirfd: c_int,
    path: [*:0]const u8,
    adirfd: c_int,
    apath: [*:0]const u8,
) void {
    if (!active) return;
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

/// Is the trace channel's descriptor backed by an ordinary file? (#492)
///
/// The write side of the answer #400 gave the read. A FIFO at the trace path blocks
/// `O_WRONLY` until a reader arrives, and that open runs from `.init_array` — before
/// `main` — inside a recording run with no budget to time it out (`runChildCapture`, not
/// `runChildCaptureWorld`). `O_NONBLOCK` on the open answers the readerless case with
/// `ENXIO`; this answers every other kind an open can succeed on: a FIFO somebody is
/// already reading, a device, a socket, a directory.
///
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

/// `noteUnresolved` for the operations that went through a descriptor (#485).
///
/// The descriptor goes in the kind, not the path. `path` is "the name the file had", and
/// since #485 the engine prints it that way — so `fd:7` sitting there produced "last
/// named fd:7", a filename that never was.
///
/// The buffer lives here and not at the three call sites, and the format lives in
/// `contract` and not here: a suffix grammar spelled in shim literals is a format the
/// engine reads and nothing defines, which is the half of ADR 0003 that survived #485's
/// narrowing.
fn noteUnresolvedWithFd(ts: *ThreadState, path: []const u8, kind: []const u8, fd: c_int) void {
    var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
    noteUnresolved(ts, path, contract.unresolved_kind.withFd(&b, kind, fd));
}

/// `noteUnresolvedWithFd` where the operation is known as well (#485).
fn noteUnresolvedWithOp(ts: *ThreadState, path: []const u8, kind: []const u8, op: contract.OpClass, fd: c_int) void {
    var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
    noteUnresolved(ts, path, contract.unresolved_kind.withOp(&b, kind, op, fd));
}

/// An fd-addressed operation that was seen but could not be placed. The label names
/// the descriptor because there is no path to name — the point of recording it is
/// that the engine refuses instead of passing.
fn noteUnresolvedFd(ts: *ThreadState, fd: c_int) void {
    noteUnresolvedWithFd(ts, "", contract.unresolved_kind.fd_without_path, fd);
}

/// The fd-taking form of `noteUnsupportedInScope2` (v12): `fsetattrlist` names its file
/// by descriptor. Resolution mirrors `noteFd` below — the same three-way answer, the
/// same refusal on a measurement that failed — and the scope gate is the same one.
pub fn noteUnsupportedInScopeFd(label: [*:0]const u8, fd: c_int) void {
    if (!active) return;
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

pub fn noteFd(op: contract.OpClass, fd: c_int) void {
    if (!active) return;
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
        // Proof, not uncertainty: sockets, pipes and devices are not state-directory
        // entries, so an operation through one is legitimately none of our business.
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
        // The file was inside the state directory and has since been unlinked. Writing
        // through such a descriptor still changes bytes the engine cannot see in any
        // snapshot, so the operation exists but has no address.
        //
        // The descriptor is named for the reason `noteUnresolvedFd` names its own: #485
        // asks for the operation class, the descriptor and the last resolved name, and
        // this is the branch that has all three. Two writes through different unlinked
        // descriptors are otherwise one indistinguishable sentence.
        noteUnresolvedWithOp(ts, resolved, contract.unresolved_kind.unlinked_fd, op, fd);
        return;
    }
    observe(ts, op, resolved, "");
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

/// `ENOSYS`, for the optional symbols below. The wrappers above may return a bare -1
/// when their lookup failed because their symbols cannot actually be missing — every
/// one of them predates the C standard library's oldest supported version here. The
/// symbols added by #244 and #256 can be missing, and a -1 with a stale errno is
/// worse than the absence itself: Rust std's kernel_copy reads errno to decide
/// whether to fall back to a read/write loop, so an unset errno turns "this shim
/// cannot see the call" into "the target's copy failed".
const ENOSYS: c_int = if (is_darwin) 78 else 38;

fn optionalMissing() isize {
    std.c._errno().* = ENOSYS;
    return -1;
}

/// The same, for the wrappers that return `c_int`. Two shapes rather than one so
/// neither call site open-codes the errno store — the version that did was the one
/// that could be fixed on its own and drift.
fn optionalMissingInt() c_int {
    std.c._errno().* = ENOSYS;
    return -1;
}

pub inline fn callPwritev(fd: c_int, iov: *const anyopaque, cnt: c_int, off: i64) isize {
    if (is_darwin) return darwin.pwritev(fd, iov, cnt, off);
    const f = real.pwritev orelse return optionalMissing();
    return f(fd, iov, cnt, off);
}
pub inline fn callPwritev2(fd: c_int, iov: *const anyopaque, cnt: c_int, off: i64, flags: c_int) isize {
    const f = real.pwritev2 orelse return optionalMissing();
    return f(fd, iov, cnt, off, flags);
}
pub inline fn callCopyFileRange(fd_in: c_int, off_in: ?*i64, fd_out: c_int, off_out: ?*i64, len: usize, flags: c_uint) isize {
    const f = real.copy_file_range orelse return optionalMissing();
    return f(fd_in, off_in, fd_out, off_out, len, flags);
}
pub inline fn callSendfile(out_fd: c_int, in_fd: c_int, off: ?*i64, count: usize) isize {
    const f = real.sendfile orelse return optionalMissing();
    return f(out_fd, in_fd, off, count);
}
pub inline fn callRenameat2(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8, flags: c_uint) c_int {
    const f = real.renameat2 orelse return optionalMissingInt();
    return f(olddirfd, old, newdirfd, new, flags);
}

// The macOS-only symbols (v12, #333). Darwin calls the real function directly, the way
// every helper above does; the Linux arm is unreachable in practice — linux.zig never
// exports these names, so nothing on that platform can call the wrappers — and answers
// ENOSYS rather than trapping, so a future mistaken export fails loudly instead of
// undefined.
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
// The guarded family (#299). macOS-only, like the two above: the Linux arm is the
// missing-symbol return, which no caller reaches because nothing on Linux exports these.
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
    // This used to say "Darwin has no fdatasync; fsync is the honest equivalent" and
    // forward to fsync. Measured 2026-08-26: the symbol IS in libSystem — no public
    // header declares it, which is what the older reading was about — so forwarding
    // to fsync handed the target a stronger, slower call than the one it made. They
    // are different contracts (fdatasync may skip the metadata flush), and a shim
    // that substitutes one for the other changes what the target does rather than
    // observing it.
    if (is_darwin) return darwin.fdatasync(fd);
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

/// execve with the current operation count appended to the environment. A stale
/// SEQ_BASE already in the caller's envp (a previous failed exec's leftover) is dropped
/// rather than duplicated.
///
/// The rebuilt array lives in the calling thread's slot, not on its stack (#555): at
/// 8 KB it was the largest single frame the shim took from a target thread. It used to be
/// on the stack for a vfork child's sake — no heap there, and a global is memory the
/// suspended parent shares — and that reason does not reach this point:
/// `execCarryAllowed` admits the armed process only, and a vfork child answers
/// `getpid()` differently and returns before `mine()` is called. The entry's own bytes,
/// 64 of them, stay on the stack.
pub fn callExecveSeqCarry(p: [*:0]const u8, a: [*]const ?[*:0]const u8, e: [*]const ?[*:0]const u8) c_int {
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
    const entry = std.fmt.bufPrintZ(&entry_buf, "{s}={d}", .{ contract.env.seq_base, ts.seq }) catch return callExecve(p, a, e);
    const prefix = contract.env.seq_base ++ "=";
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
    new_env[n] = entry.ptr;
    new_env[n + 1] = null;
    return callExecve(p, a, @ptrCast(new_env));
}

/// setenv-based carry for `execv`/`execvp`, which use the ambient environment.
/// Returns whether the variable was set — the caller unsets it when the exec
/// returns (failure), so a later fork's child does not inherit a stale count.
pub fn execSeqCarrySet() bool {
    if (!execCarryAllowed()) return false;
    // Same refresh, same reason as `callExecveSeqCarry`: the base is the run's count.
    const ts = mine();
    _ = refreshCount(ts);
    var val_buf: [16]u8 = undefined;
    const v = std.fmt.bufPrintZ(&val_buf, "{d}", .{ts.seq}) catch return false;
    return c.setenv(contract.env.seq_base, v.ptr, 1) == 0;
}

pub fn execSeqCarryUnset() void {
    _ = c.unsetenv(contract.env.seq_base);
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
pub fn noteLinkByDescriptor(fd: c_int) void {
    if (!active) return;
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
    ts.busy = true;
    defer ts.busy = false;
    writeRecord(ts, op, 0, "", "");
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

// Split by role for the same reason the engine's options tests are: a failing assertion
// aborts its test, so a mutation that breaks the first one would leave the second's state
// unrecorded.

test "the shipped shim options carry the shipped value (#365)" {
    // Weaker than its counterpart in src/main.zig, and kept anyway for stated reasons.
    // `test_seq_gap` is a bool, so the only edit to build.zig's literal is false -> true,
    // and that edit is loud: a shim skipping number 2 fails every acceptance leg with two
    // in-scope operations. There is no quiet mutation here for this test to be the only
    // net against, unlike the trace caps, which are numbers with a wide quiet range.
    //
    // What it does buy: the promise is universal over the shipped build values, so leaving
    // one of them held by nothing would make it false for a reader who checked; the
    // failure arrives at `zig build test` instead of minutes later in acceptance; and it
    // runs on macOS, where the acceptance suite does not.
    try std.testing.expect(!shim_build_options.test_seq_gap);
    // `test_observe_fail` (contract v14) is the same shape and the same argument: a bool
    // whose only edit is false -> true, and that edit is loud — a shipped shim reporting a
    // failed install makes every `--observe syscalls` run a setup error. The reason it is
    // held here anyway is the one above: the promise is universal over the shipped values.
    try std.testing.expect(!shim_build_options.test_observe_fail);
}

test "no second shim build option arrives unchecked (#365)" {
    // The ratchet, as in the engine's: a second option added later with no assertion above
    // would leave the promise false while CI stayed green.
    const decls = @typeInfo(shim_build_options).@"struct".decls;
    try std.testing.expectEqual(@as(usize, 2), decls.len);
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
    const base = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-shim-nofollow-{d}", .{c.getpid()}) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var tb: [160]u8 = undefined;
    const target_z = std.fmt.bufPrintZ(&tb, "{s}/target", .{base}) catch unreachable;
    var lb: [160]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&lb, "{s}/link", .{base}) catch unreachable;
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
    const base = std.fmt.bufPrintZ(&bb, "/tmp/sideeye-shim-tracekind-{d}", .{c.getpid()}) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/f", .{base}) catch unreachable;
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

    // The `.bad_fd` arm. It cannot arrive at the call site, where the descriptor has just
    // been opened successfully, but the function answers for it and the answer is `false`:
    // there is no file to put records in. `.failed` is deliberately not tested — producing
    // a live descriptor whose `fstat` fails takes a kernel this test cannot arrange, and
    // faking it would be testing the fake.
    try std.testing.expect(!traceTargetIsOrdinary(-1));
}

test "the run's operation count is read back from the trace, and a torn tail is not a failure (v15)" {
    // `refreshCount` is where a number stops being this process's own. The cases below are
    // the ones the mechanism turns on: another process's record raises the count, a
    // partially written record does NOT (it is an operation still happening), a marker
    // that carries a number does, and bytes that are not records at all refuse rather
    // than produce a guess.
    //
    // A pid-unique directory, for the reason the trace-kind test above gives: several
    // concurrent test binaries run this file.
    var bb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, "/tmp/sideeye-shim-count-{d}", .{c.getpid()}) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/trace.bin", .{base}) catch unreachable;
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

    // An empty file, then a header and nothing else: both answer "read fine, nothing to
    // count". A version that treated an empty trace as unreadable would refuse every
    // first operation of every run.
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 0), ts.seq);
    var hbuf: [contract.header_len]u8 = undefined;
    const hn = try contract.encodeHeader(&hbuf);
    try append.bytes(fd, hbuf[0..hn]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 0), ts.seq);

    // Another process's operations raise the count. This is the whole point: pid 8 is not
    // this process, and its numbers are positions in the same run.
    try append.record(fd, .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" });
    try append.record(fd, .{ .op = .rename, .seq = 2, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "/tmp/s/b" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);

    // Records that carry no number leave it alone — a close, and an unplaceable operation.
    try append.record(fd, .{ .op = .close, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s/b", .aux = "" });
    try append.record(fd, .{ .op = .unresolved, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s/b", .aux = "unlinked-fd write fd:3" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);

    // A torn tail: the first bytes of a record and no more. The scan stops in front of it
    // and the count does not move — the operation is still being written, and taking its
    // number now would hand the same number out twice.
    const scanned_before = ts.count_scanned;
    var partial: [2 * contract.max_path]u8 = undefined;
    const pn = try contract.encodeRecord(&partial, .{ .op = .write, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/c", .aux = "" });
    try append.bytes(fd, partial[0 .. pn - 4]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 2), ts.seq);
    try std.testing.expectEqual(scanned_before, ts.count_scanned);

    // Completed, it counts — and the read resumes from where it stopped rather than from
    // the start, which is what `count_scanned` is for.
    try append.bytes(fd, partial[pn - 4 .. pn]);
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 3), ts.seq);
    try std.testing.expect(ts.count_scanned > scanned_before);

    // `kill_landed` is a marker and still counts. A world that died in front of operation
    // 9 never wrote 9's own record, so leaving this out would let a sibling still running
    // take 9 for a real operation at the address the world claims to have died before.
    try append.record(fd, .{ .op = .kill_landed, .seq = 9, .pid = 7, .tid = 7, .path = "/tmp/s/d", .aux = "" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 9), ts.seq);

    // The count never goes backwards: a later record with a smaller number cannot lower
    // it. (The shim does not write this; a hard link at the trace path could.)
    try append.record(fd, .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/e", .aux = "" });
    try std.testing.expect(refreshCount(&ts));
    try std.testing.expectEqual(@as(u32, 9), ts.seq);

    // A second slot scanning the same trace reads the same maximum from its own start
    // (v16): the count is the run's, not the slot's, and a fresh thread does not begin
    // at zero because its scan does.
    var other: ThreadState = .{};
    try std.testing.expect(refreshCount(&other));
    try std.testing.expectEqual(@as(u32, 9), other.seq);
    try std.testing.expectEqual(ts.count_scanned, other.count_scanned);

    // Bytes that are not a record refuse. Numbering past them would mean numbering from
    // whatever this process happened to remember, which is the address of another
    // operation. The caller records `count-read-failed` and the engine refuses the run.
    // At least a record's fixed prefix long (22 bytes since v16), or the decoder would
    // read them as a record still being written and the scan would stop politely in
    // front of them instead of refusing — which is what happened when the prefix grew
    // and this array did not.
    try append.bytes(fd, &[_]u8{ 0xff, 0xff, 1, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 });
    try std.testing.expect(!refreshCount(&ts));

    // A closed channel refuses too, rather than answering from memory.
    trace_fd = -1;
    try std.testing.expect(!refreshCount(&ts));
}

test "slots: one per thread id, claimed once, and the reserve past the last" {
    // Nothing here touches the live table: the test builds its own, the way a fresh
    // process would find it, and drives the claim logic by hand with made-up ids.
    var table = [_]ThreadState{.{}} ** 3;
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
    // The same id comes back to the same slot, not a new one.
    try std.testing.expectEqual(a, claim.run(&table, &res, &exhausted, 101));
    try std.testing.expect(a != b);
    try std.testing.expect(!exhausted);
    _ = claim.run(&table, &res, &exhausted, 303);
    try std.testing.expect(!exhausted);
    // The fourth id finds no free slot: it gets the reserve. (In the live table `mine`
    // writes the exhaustion notice at this moment; the test below drives that path on the
    // real function.)
    const d = claim.run(&table, &res, &exhausted, 404);
    try std.testing.expectEqual(&res, d);
    try std.testing.expect(exhausted);
    // Slots are never freed, so the earlier owners still resolve to theirs.
    try std.testing.expectEqual(b, claim.run(&table, &res, &exhausted, 202));
}

test "the fork child starts from an empty slot table, however full the parent's was (v16)" {
    // Three slots claimed, one of them mid-call, the table marked exhausted — the shape a
    // fork can catch the parent in. The child must see none of it.
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
    // The live table this time, filled by hand with ids no real thread has, and the trace
    // descriptor pointed at a file this test owns — so `mine()` itself runs the overflow
    // path, and what it wrote is read back and decoded. The hand-copied claim logic in the
    // test above cannot show this; review said so.
    if (builtin.os.tag != .macos) resolveAll();
    var bb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, "/tmp/sideeye-shim-slots-{d}", .{c.getpid()}) catch unreachable;
    _ = std.c.mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/trace.bin", .{base}) catch unreachable;
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
    // Leaves the live table the way the other tests in this binary expect to find it.
    defer resetSlotsInChild();
    for (&slots, 0..) |*s, i| s.tid = 100_000_000 + @as(u64, i);
    exhaustion_announced = false;

    const got = mine();
    try std.testing.expectEqual(&reserve, got);
    try std.testing.expect(exhaustion_announced);
    // Read back: exactly one record, the notice, carrying this thread's id.
    var buf: [128]u8 = undefined;
    const n = c.pread(fd, &buf, buf.len, 0);
    try std.testing.expect(n > 0);
    const d = try contract.decodeRecord(buf[0..@intCast(n)]);
    try std.testing.expectEqual(contract.OpClass.unresolved, d.rec.op);
    try std.testing.expectEqualStrings(contract.unresolved_kind.thread_slots_exhausted, d.rec.aux);
    try std.testing.expectEqual(currentTid(), d.rec.tid);
    try std.testing.expectEqual(@as(usize, d.consumed), @as(usize, @intCast(n)));
    // A second overflow takes the reserve again and writes nothing more.
    try std.testing.expectEqual(&reserve, mine());
    try std.testing.expectEqual(n, c.pread(fd, &buf, buf.len, 0));
}

test "exec carry: builds in the thread's own slot, and not on the reserve or when re-entered (#555)" {
    // An exec that cannot succeed, so the carry runs to the end and returns. Whether it
    // built the environment is read off `exec_env[0]`, cleared before each call.
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

    // Re-entered: a carry already in progress on this thread — the array is left alone.
    {
        // Cleared on the way out even when an assertion fails: `resetSlotsInChild` does not
        // touch the flag, and a later test in this binary would find it set.
        own.exec_env[0] = null;
        own.exec_carrying = true;
        defer own.exec_carrying = false;
        try std.testing.expectEqual(@as(c_int, -1), callExecveSeqCarry(nowhere, &argv, &env));
        try std.testing.expect(own.exec_env[0] == null);
    }

    // The reserve: every slot taken by ids no real thread has — the shared array is left
    // alone. The notice is marked written so this test writes nothing.
    for (&slots, 0..) |*s, i| s.tid = 100_000_000 + @as(u64, i);
    const saved_announced = exhaustion_announced;
    defer exhaustion_announced = saved_announced;
    exhaustion_announced = true;
    try std.testing.expectEqual(&reserve, mine());
    reserve.exec_env[0] = null;
    try std.testing.expectEqual(@as(c_int, -1), callExecveSeqCarry(nowhere, &argv, &env));
    try std.testing.expect(reserve.exec_env[0] == null);
}
