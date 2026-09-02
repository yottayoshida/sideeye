//! Direct libc bindings for the engine.
//!
//! The engine deliberately does not use `std.Io`. That layer was reworked wholesale in
//! Zig 0.16 — `std.fs` no longer holds `File` or `Dir`, spawning a child goes through a
//! vtable, and more movement is already scheduled for 0.17. Everything sideeye needs
//! from the operating system is plain POSIX: walk a directory, read and write a file,
//! fork, exec, wait. That surface has been stable for decades.
//!
//! The shim reached the same conclusion first, for a harsher reason: inside somebody
//! else's process there is no heap, no standard-library I/O, and nothing the target
//! has not already initialised (shim/src/common.zig states the rules). It still uses
//! `std` — the allocation-free slices: `std.mem` and `std.fmt` into fixed buffers, and
//! `std.c`/`std.os.linux` as ABI tables. Both halves ending up on the same small set
//! of calls is a convenience, not a coincidence.
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
/// Positional read. `image.zig` walks a handful of fixed-width header fields scattered
/// across an executable and never wants the whole file, so it reads by offset rather
/// than seeking: no cursor to leave in the wrong place between two field reads.
pub extern "c" fn pread(fd: c_int, buf: [*]u8, n: usize, off: i64) isize;
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

// The descriptor-relative half of the calls above (#327). The destructive walk opens its
// root once and reaches every entry through these, so a swap of the root's *pathname*
// after the open cannot redirect a delete.
//
/// Variadic for the reason `open` is, twenty lines up: a fixed four-argument declaration
/// loses `mode` on arm64 macOS, where variadic arguments travel on the stack and fixed
/// ones in registers. The walk only ever passes three, but a declaration that is wrong
/// for the four-argument call is wrong the day somebody makes one.
pub extern "c" fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) c_int;
/// `flags` is 0 for a file, `AT_REMOVEDIR` for a directory — the `unlink`/`rmdir` split
/// expressed as an argument.
pub extern "c" fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int;
pub extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn symlinkat(target: [*:0]const u8, newdirfd: c_int, linkpath: [*:0]const u8) c_int;
/// **Takes ownership of `fd`**: `closedir` closes it, so a descriptor the caller still
/// needs afterwards cannot be handed over.
///
/// **Nor can a `dup` of one**, which is the shape this walk tried first. A duplicate
/// shares the open file description *and its read offset*, so the stream starts wherever
/// the original was left rather than at the beginning — measured on macOS, it cost the
/// walk 144 of 400 entries and returned success. A caller that must read a directory it
/// also holds open takes a fresh description instead: `openat(dirfd, ".", O_RDONLY |
/// O_DIRECTORY)`.
///
/// Declared beside `opendir`/`readdir`, which carry the same pre-existing caveat: on
/// x86-64 Darwin libc resolves these through `$INODE64` aliases, so the plain symbol is
/// the arm64 spelling. Both the development host and the macOS runner are arm64.
pub extern "c" fn fdopendir(fd: c_int) ?*anyopaque;

pub extern "c" fn getpid() c_int;
/// The parent's pid — or, once the parent has died and this process has been reparented,
/// the reaper's: pid 1 or the nearest subreaper on Linux, launchd on macOS. Parentage
/// changes only when the parent dies, so "getppid() no longer answers what it answered at
/// startup" is exactly "the process that launched this run is gone" (#269) — no
/// descriptor to inherit, no signal to arrive at the wrong moment, the same meaning on
/// both platforms.
pub extern "c" fn getppid() c_int;
pub extern "c" fn fork() c_int;
pub extern "c" fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
/// Called in the child between fork and exec, so it moves the command being spawned and
/// nothing else. The engine's own cwd stays put, and `--work`, `--json` and `--state` are
/// still read against it — they are the engine's arguments, not the define's.
///
/// The oracle is the one reader that has to be told separately: it resolves the subject's
/// relative paths from a trace, after the fact, so the engine hands it the same directory
/// it handed this call (`src/main.zig`, the recording run's parse site). The shim needs no
/// telling — it reads the cwd inside the child.
pub extern "c" fn chdir(path: [*:0]const u8) c_int;
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
/// The out-parameter is typed `std.c.siginfo_t` at the call sites (the type, per this
/// file's policy, comes from std.c) but crosses the ABI as an opaque pointer here: the
/// blocking path never reads it, and the budget path reads exactly one field of it,
/// through `siPid` below.
pub extern "c" fn waitid(idtype: c_int, id: c_int, infop: *anyopaque, options: c_int) c_int;
pub extern "c" fn clock_gettime(clockid: c_int, tp: *std.c.timespec) c_int;
pub extern "c" fn nanosleep(req: *const std.c.timespec, rem: ?*std.c.timespec) c_int;
pub extern "c" fn signal(sig: c_int, handler: usize) usize;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
pub extern "c" fn _exit(status: c_int) noreturn;
/// For the one child-side failure that must not become an exit code (#263): a signal
/// death is outside the target's 0..255 and cannot be mistaken for its own status.
pub extern "c" fn abort() noreturn;
pub extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;
/// macOS: fills `buf` with the executable's path (may be non-canonical; realpath it).
/// Returns 0 on success; on too-small buffer returns -1 and writes the needed size.
pub extern "c" fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int;
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;

/// `access` mode: executable. Same value on Linux and the BSDs.
pub const X_OK: c_int = 1;
pub const F_OK: c_int = 0;

/// The only signal in play. Cannot be caught, which is the point: a target that could
/// decline to die would make the crash point a request rather than a fact.
///
/// Typed `u8` so the same constant serves both users — `kill` widens it to `c_int`, and
/// `Term.isSignal` compares it directly. `main.zig` was spelling it as a bare `9`.
pub const SIGKILL: u8 = 9;
/// 2 on both platforms. Sent before SIGKILL to a sidecar because it is the disposition
/// `fs_usage` is built to handle — it is meant to be stopped from a terminal, and it
/// flushes and releases kdebug on the way out. SIGTERM does neither: measured, a
/// capture ended at a stdio flush boundary sixty-four milliseconds in and read like a
/// complete capture of a short window.
pub const SIGINT: u8 = 2;

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
/// Same value on both sides (glibc `bits/waitflags.h`, macOS `sys/wait.h`) — said
/// explicitly, per the rule the comment above states for the agreeing constants.
pub const WNOHANG: c_int = 1;
/// The clock the world budget reads. The number differs per platform — glibc
/// `bits/time.h` says 1, the macOS SDK's `time.h` says 6 — the same shape as WNOWAIT.
pub const CLOCK_MONOTONIC: c_int = if (builtin.os.tag == .linux) 1 else 6;
/// SIGCHLD differs too: 17 on Linux, 20 on Darwin.
pub const SIGCHLD: c_int = if (builtin.os.tag == .linux) 17 else 20;
pub const SIG_DFL: usize = 0;

/// The one siginfo field the budget path reads, behind the one comptime switch that
/// knows the two platforms spell it differently: a flat `pid` on Darwin, nested under
/// `fields.common.first.piduid` in glibc's layout. POSIX pins the semantic this relies
/// on: with WNOHANG and no child ready, a successful `waitid` leaves `si_pid` zero —
/// which is why the struct is zeroed before every call rather than trusted.
pub fn siPid(info: *const std.c.siginfo_t) std.c.pid_t {
    return switch (builtin.os.tag) {
        .macos => info.pid,
        .linux => info.fields.common.first.piduid.pid,
        else => @compileError("unsupported OS"),
    };
}

pub const O_RDONLY: c_int = 0;
pub const O_WRONLY: c_int = 1;
pub const O_CREAT: c_int = if (builtin.os.tag == .linux) 0o100 else 0x200;
pub const O_TRUNC: c_int = if (builtin.os.tag == .linux) 0o1000 else 0x400;
pub const O_EXCL: c_int = if (builtin.os.tag == .linux) 0o200 else 0x800;
/// Opening a FIFO with no writer blocks forever, which #5 recorded when an open-probe
/// was used to classify paths and was retired from this file for it (see
/// `kindAtNoFollow`). Regular files are unaffected: open, lseek and read on one answer
/// the same with the flag and without it (measured, `spike/fifo-classification-400.txt`).
///
/// **The flag alone is not the fix, and this is where #400 came from.** It stops the
/// open from waiting; it does not make the read say anything. On a FIFO with no writer
/// the read returns 0 — end of file — so a caller that reads to EOF gets an empty buffer
/// and calls it success.
///
/// **And it is not free, so it does not go everywhere.** A non-blocking read of a pipe
/// whose writer has not written yet fails EAGAIN, and a reader that treats a negative
/// return as unreadable then refuses input that would have arrived. So the flag belongs
/// only where the reader is prepared for that — by classifying the descriptor and
/// refusing, or by recognising EAGAIN and waiting. Who carries it, and which of the two
/// they do:
///
/// - `image.zig` (#398): flag, then `lseek` — ESPIPE ends it there.
/// - `engine.zig`'s `readWhole`, `main.zig`'s `readFileFrom` and `observeCapture`,
///   `mcp.zig`'s `readFile`: flag, then `kindOfFd`. All four read paths the engine
///   itself produced, so nothing legitimate is refused.
/// - `main.zig`'s `readFileAllocCapped`: the flag comes with **either** half of its
///   `ReadMode`, and the two halves answer the same question differently. The case read
///   *classifies*: it needs the open to return so it can ask what the descriptor is, and
///   refuses anything but a regular file. The `--config` read is *bounded*: it may not
///   refuse a pipe — an operator can legitimately name one — so it needs `EAGAIN` where
///   a blocking read would sit somewhere no deadline can see it, and it retries while a
///   peer might still arrive. A reader that asks for neither keeps the blocking open it
///   had; the flag is not free, and a non-blocking read of a pipe whose writer has not
///   written yet fails where waiting would have succeeded (measured — that is exactly
///   how an earlier draft broke `--config`; BUILDLOG 2026-08-30).
///
/// Listing the callers here is deliberate, and so is listing what each does *after* the
/// open: the previous version of this comment named one file and said nothing about the
/// second half, and the sweep that followed #398 looked for refusal *messages* rather
/// than for opens — which is why #400 sat unfound in a function three lines from a
/// comment describing its defect.
pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0o4000 else 0x0004;
/// Derived from `std.posix.O` rather than written out, and it is the only flag in this
/// block that needs to be.
///
/// The value differs *within* Linux by architecture — 0o400000 on x86_64, 0o100000 on
/// aarch64 — so the `os.tag == .linux` shape every neighbour above uses cannot express
/// it. This declaration carried the x86_64 number for all of Linux, which left the one
/// guard that used it inert on arm64: measured in an arm64 container, a symlink planted
/// at a capture path was opened straight through. The comment at the top of this block
/// already recorded three platform constants that were right on one side and quietly
/// plausible on the other; the shape of the declaration is what allowed a fourth.
///
/// The test at the bottom of this file asks the kernel instead of asserting the number,
/// because a test that spells the value out is satisfied by whatever the constant says.
pub const O_NOFOLLOW: c_int = blk: {
    var f: std.posix.O = .{};
    f.NOFOLLOW = true;
    break :blk @bitCast(f);
};

/// Derived for the same reason `O_NOFOLLOW` is, and it is the flag that needs it most:
/// `O_DIRECTORY` differs by architecture within Linux, and a wrong value here does not
/// refuse loudly — it opens things the walk then treats as directories.
pub const O_DIRECTORY: c_int = blk: {
    var f: std.posix.O = .{};
    f.DIRECTORY = true;
    break :blk @bitCast(f);
};

/// Set on the root descriptor the destructive walk holds.
///
/// **Not load-bearing today**, and the honest reason to add it anyway: `runChild*` is only
/// reached after `restore`/`freshDir` have returned, so no fork happens while a root
/// descriptor is open. That ordering is what makes the absence safe, and it is written
/// down nowhere — a descriptor on the state directory is precisely the one that must not
/// survive an exec into the target.
pub const O_CLOEXEC: c_int = blk: {
    var f: std.posix.O = .{};
    f.CLOEXEC = true;
    break :blk @bitCast(f);
};

/// `AT_*` and `AT_FDCWD` differ **by operating system** rather than by architecture —
/// `REMOVEDIR` is 0x0080 on Darwin against 0x200 on Linux, and `AT_FDCWD` is -2 against
/// -100 — so unlike `O_DIRECTORY` the `os.tag` shape every neighbour uses could express
/// them. Taken from std regardless: the block at the top of this file records three
/// defects that were a platform constant right on one side and quietly plausible on the
/// other, and a hand-written table is how a fourth would arrive.
///
/// A wrong `AT_REMOVEDIR` fails loudly — `deleteTree`'s `removed < count` catches it — so
/// it is not in the same danger class as `O_DIRECTORY` above. The derivation is the same;
/// the reason is not.
pub const AT_FDCWD: c_int = std.posix.AT.FDCWD;
pub const AT_REMOVEDIR: c_int = std.posix.AT.REMOVEDIR;

/// The two errno values the destructive walk maps to a refusal of their own; everything
/// else it can see falls to one loud default. `ELOOP` is 40 on Linux and 62 on Darwin, so
/// it cannot be written out the way `EINTR` and `ENOENT` above are; `ENOTDIR` agrees
/// across both but comes from the same place so the pair cannot drift apart.
pub const ELOOP: c_int = @intFromEnum(std.posix.E.LOOP);
pub const EEXIST: c_int = @intFromEnum(std.posix.E.EXIST);
pub const ENOTDIR: c_int = @intFromEnum(std.posix.E.NOTDIR);
/// Taken from `std.posix.E` for the same reason as its two neighbours, and with more at
/// stake: this one differs **between operating systems** — 11 on Linux, 35 on Darwin —
/// and it is compared against, not passed in. A wrong value here does not fail loudly;
/// it makes "the peer has not written yet" unrecognisable, so the reader treats it as
/// unreadable and refuses a config that was about to arrive. Every other test stays
/// green while it does that.
pub const EAGAIN: c_int = @intFromEnum(std.posix.E.AGAIN);

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
    return kindAtNoFollow(AT_FDCWD, path);
}

/// The same classification, relative to an open directory (#327).
///
/// **`path` must be a bare entry name.** An absolute path makes `dirfd` irrelevant on both
/// platforms — silently, with no error — which would leave the walk resolving names the
/// descriptor was opened to pin. The one caller passes a name straight out of `readdir`.
///
/// This is the fd-relative form the walk needs, and deliberately not an `openat` probe:
/// `opendir` passes `O_NONBLOCK`, a hand-rolled open does not, and #5 recorded what that
/// costs — "a FIFO with no writer blocks that open forever" is why the open-probe was
/// retired from this file in the first place.
pub fn kindAtNoFollow(dirfd_: c_int, path: [*:0]const u8) ClassifyError!Kind {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(@intCast(dirfd_), path, lnx.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true }, &stx);
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
        if (std.c.fstatat(@intCast(dirfd_), path, &st, std.c.AT.SYMLINK_NOFOLLOW) != 0) {
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

/// The same classification for a descriptor that is **already open** (#400).
///
/// Deliberately not a second spelling of `kindAtNoFollow`: that one asks what a name
/// refers to *before* anything opens it, and is the form the snapshot walk needs. This
/// one asks what the descriptor turned out to be *after* the open, which is the only
/// form that can answer without a window between the answer and its use — a name can
/// change kind between the two calls, a descriptor cannot.
///
/// A reader that opened with `O_NONBLOCK` needs this: the flag stops the open from
/// waiting on a FIFO's peer, but the read that follows then returns 0, which is
/// indistinguishable from an empty regular file. Measured on macOS with a real FIFO and
/// no writer: `open` succeeds, `fstat` says `S_IFIFO`, `lseek` fails with ESPIPE, and
/// `read` returns 0 with errno untouched. `lseek` failing is **not** the test to write
/// instead — seekability and regular-file-ness are different properties, and a device
/// that seeks would pass a test built on it.
///
/// `.symlink` never comes back from here: `open` follows the link, so the descriptor is
/// the target. `.missing` likewise cannot occur — the descriptor exists.
pub fn kindOfFd(fd: c_int) ClassifyError!Kind {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        // The empty path with AT_EMPTY_PATH is how statx addresses a descriptor itself.
        const rc = lnx.statx(fd, "", lnx.AT.EMPTY_PATH, .{ .TYPE = true }, &stx);
        switch (lnx.errno(rc)) {
            .SUCCESS => {},
            else => return error.Unclassifiable,
        }
        // Same contract as above: a type the kernel did not fill in is not an answer.
        if (!stx.mask.TYPE) return error.Unclassifiable;
        const m: u32 = stx.mode;
        if (lnx.S.ISDIR(m)) return .dir;
        if (lnx.S.ISREG(m)) return .file;
        return .other;
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) return error.Unclassifiable;
        const m = st.mode;
        if (std.c.S.ISDIR(m)) return .dir;
        if (std.c.S.ISREG(m)) return .file;
        return .other;
    }
}

/// What a swap changes and a rename does not: the pair that says a descriptor and a name
/// reach the same object (#338).
///
/// **The two platforms encode `dev` differently and that is deliberate.** Linux composes
/// it from `statx`'s major and minor; Darwin hands back its own `dev_t`, which is signed
/// there and is widened through its bit pattern rather than its value. Nothing serialises
/// an `Identity`, nothing stores one, and nothing compares one taken on one platform with
/// one taken on another — the only comparison is between two taken moments apart in the
/// same process. So the encoding only has to be injective within a run, and the cheapest
/// injective encoding on each platform is the one the platform already gives.
///
/// **What it cannot distinguish is an inode that was freed and handed out again**, and on
/// Linux that is not exotic. Measured 2026-09-01: on overlayfs, removing a directory and
/// creating another at the same path hands back the same number on the very next `mkdir`,
/// three runs of three. APFS gives a new one, three of three. Renaming the old directory
/// aside — the ordinary way one is swapped, and what the engine's tests do — keeps it
/// linked and keeps the numbers apart; removing its last link does not.
///
/// What that admits is narrower than it sounds, and the narrowing is the reason it is
/// recorded rather than closed. A caller comparing identities is guarding a *path* it will
/// then operate on, so the harm of a swap is that something worth keeping arrives at that
/// path — and anything **moved** there carries its own inode and is refused. Only an object
/// the filesystem created after the vetted one was unlinked can inherit the number, which
/// makes it a new and empty directory. Closing even that needs a descriptor held from the
/// moment of the vet, or a per-inode generation number neither platform exposes through a
/// portable stat. ADR 0037 carries the same account.
pub const Identity = struct {
    dev: u64,
    ino: u64,

    pub fn eql(a: Identity, b: Identity) bool {
        return a.dev == b.dev and a.ino == b.ino;
    }

    /// One definition of the encoding per platform, called from both readers below. It was
    /// written out at all four sites first, which is the shape where someone widens the
    /// Linux composition in one of two places and the descriptor and the pathname stop
    /// agreeing about an object they both reached.
    fn fromStatx(stx: anytype) Identity {
        return .{ .dev = (@as(u64, stx.dev_major) << 32) | @as(u64, stx.dev_minor), .ino = stx.ino };
    }

    fn fromStat(st: std.c.Stat) Identity {
        return .{ .dev = @as(u64, @as(u32, @bitCast(st.dev))), .ino = st.ino };
    }
};

/// Failure to identify is never "they match". Every caller refuses on this error, which is
/// why it is an error and not a null: an optional invites `orelse` at the call site, and
/// the one thing that must not happen here is a missing answer read as agreement.
pub const IdentityError = error{Unidentifiable};

/// The identity of what a descriptor holds. Cannot race: the descriptor pins the inode.
pub fn identityOfFd(fd: c_int) IdentityError!Identity {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        // AT_EMPTY_PATH with the empty name is how statx addresses a descriptor itself,
        // the same spelling `kindOfFd` uses above.
        const rc = lnx.statx(fd, "", lnx.AT.EMPTY_PATH, .{ .INO = true }, &stx);
        if (lnx.errno(rc) != .SUCCESS) return error.Unidentifiable;
        // The inode is mask-gated and has to be checked; the device is not — `statx(2)`
        // fills `stx_dev_major`/`stx_dev_minor` unconditionally, outside the mask.
        if (!stx.mask.INO) return error.Unidentifiable;
        return Identity.fromStatx(stx);
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) return error.Unidentifiable;
        return Identity.fromStat(st);
    }
}

/// The identity of whatever a pathname resolves to **right now**.
///
/// Follows links on purpose: the question is what the name means at this instant, not what
/// the last component is. A caller comparing this against a descriptor it already holds is
/// asking whether the name still leads back to the thing it opened, and a link that leads
/// there is not a swap.
///
/// ENOENT is `Unidentifiable` like every other failure. A name that resolves to nothing
/// while a descriptor holds something is precisely a disagreement, not an absence.
pub fn identityOfPath(path: [*:0]const u8) IdentityError!Identity {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(AT_FDCWD, path, 0, .{ .INO = true }, &stx);
        if (lnx.errno(rc) != .SUCCESS) return error.Unidentifiable;
        if (!stx.mask.INO) return error.Unidentifiable;
        return Identity.fromStatx(stx);
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstatat(AT_FDCWD, path, &st, 0) != 0) return error.Unidentifiable;
        return Identity.fromStat(st);
    }
}

/// Whether the descriptor is a FIFO. Asked separately from `kindOfFd`, deliberately.
///
/// `Kind` has no FIFO member: a FIFO and a character device both answer `.other`. Giving
/// it one would touch a classifier that the snapshot walk, `kindFromDirent` and the
/// case-path read all share, and every `else => .other` arm would have to be re-read.
/// The one caller that needs the distinction is the bounded read, where the two mean
/// opposite things: a FIFO's zero-length read is "no peer has written **yet**, ask
/// again", while `/dev/null`'s is "empty, and it will stay empty". Retrying the second
/// spends a whole deadline waiting for an answer that arrived at once — measured, that
/// is `--config /dev/null` going from 0.01 s to the full deadline with a different
/// refusal on the end.
///
/// Failure answers false rather than an error: the caller uses this to decide whether to
/// retry, and "could not tell" must fall to the side that terminates.
pub fn isFifoFd(fd: c_int) bool {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(fd, "", lnx.AT.EMPTY_PATH, .{ .TYPE = true }, &stx);
        if (lnx.errno(rc) != .SUCCESS) return false;
        if (!stx.mask.TYPE) return false;
        return lnx.S.ISFIFO(@as(u32, stx.mode));
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) return false;
        return std.c.S.ISFIFO(st.mode);
    }
}

/// Test apparatus only: the classification above owes its falsification to a real
/// FIFO (#5), and std.c carries no mkfifo. The engine itself never creates one.
pub extern "c" fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;

/// Test apparatus only: `kindOfFd` owes its falsification to a descriptor that is not a
/// regular file, and a pipe is the one the tests can make without touching the
/// filesystem — which is the point, since opening a FIFO by name is the thing the
/// caller of `kindOfFd` is trying to survive.
pub extern "c" fn pipe(fds: *[2]c_int) c_int;

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

/// `WaitFailed` means the direct child's exit status could never be read — not that the
/// child misbehaved. It exists because the alternative is worse: `waitpid` only writes
/// `status` when it succeeds, so a discarded failure leaves the zero it was initialised
/// with, `decodeStatus` reads that as a clean exit, and a world that was killed is
/// reported `kill_did_not_land`. A refusal naming the wait is the honest answer; a
/// confident wrong reason is not (#264).
/// `StdinUnavailable` (#263): `/dev/null` could not be opened, so the child could not be
/// started with its stdin at end-of-file. Raised by the PARENT before any fork, on purpose:
/// the child's exit status is the target's namespace (`expected_status` accepts 0..255, so
/// no code is free for the engine to mean something by), and a failure to arrange the
/// child's descriptors has to reach the caller on a channel the target cannot also use.
pub const SpawnError = error{ ForkFailed, OutOfMemory, WaitFailed, StdinUnavailable };

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
/// `cwd` — where the child starts, `null` for the engine's own. It is a parameter on
/// every wrapper a define's commands reach rather than a field somewhere, so a new spawn
/// site has to say which it wants: a site that silently inherited the engine's cwd would
/// be a define running somewhere its author did not declare, and nothing downstream can
/// see that. `runChildCaptureMinimalEnv` is the one wrapper without it, on purpose — its
/// child is the engine, not a define's command.
///
/// `stdin` — not a parameter, on purpose (#263). Every child these wrappers start, on
/// every path, begins with fd 0 at end-of-file: the engine's own stdin is the caller's
/// terminal or pipe, a fact no committed define can declare and no replay can reproduce,
/// and a target that read it either hung the CLI path forever or saw EOF on the MCP path
/// — two behaviours for one target. There is no spawn site with a reason to inherit
/// (the sudo probe, the demo compiler, the signal helper and the engine's self-exec read
/// nothing), so a per-site choice would only be a way for a new site to inherit by
/// accident. How the descriptor is arranged, and why its failure is a `SpawnError`
/// rather than an exit code, is written at the fork in `runChildImplWithOps`.
pub fn runChild(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, null, false, false, cwd);
}

/// `runChild`, with the child's stdout sent to a file. What a target says on stdout
/// is evidence — the L1 success marker is read from it (ADR 0008) — and evidence
/// belongs in the work directory, not interleaved with the engine's own report.
pub fn runChildCapture(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: []const u8,
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, stdout_path, false, false, cwd);
}

/// `runChildCapture` with a wall-clock budget: the one entry point that can answer
/// `error.TimedOut`, used by the world loop alone (#263). Everything else keeps the
/// plain `SpawnError`, so a caller that never passes a budget cannot receive a timeout
/// by type — the containment that an `unreachable` arm in the caller's error switch
/// would only have checked at run time.
///
/// The budget is a measurement rule, not a physical claim: a child a successful
/// post-deadline observation still sees running is sent SIGKILL and reported TimedOut;
/// one an observation sees exited is accepted as in-budget. What TimedOut promises
/// about waiting is bounded too — the kill's reap runs under a fixed grace, after which
/// the child (uninterruptible sleep, or credentials the group signal cannot reach) is
/// left as a stray for the quiescence check, and the budget path has no unbounded call
/// in it.
///
/// A caller that passes a budget must have reset SIGCHLD to its default disposition
/// first (main does, once for the whole run, when the flag parses): both the kill's
/// safety and the boundedness of the exited-side reap stand on unreaped children
/// staying zombies, and an inherited SIG_IGN — which survives exec — would let the
/// kernel auto-reap them instead.
pub fn runChildCaptureWorld(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: []const u8,
    budget_ms: ?u64,
    cwd: ?[]const u8,
) (SpawnError || error{TimedOut})!Term {
    return runChildImplWithOps(gpa, argv, env_pairs, stdout_path, false, false, budget_ms, cwd, RealOps);
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
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, stdout_path, false, true, cwd);
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
    // No `cwd` parameter, and `null` here rather than a pass-through: this child is the
    // engine re-executing itself, and the engine's own cwd is what `--work`, `--json` and
    // the oracle's path resolution are all read against. A define's `cwd` is applied one
    // level down, by that engine, to the commands it runs.
    return runChildImpl(gpa, argv, env_pairs, stdout_path, true, false, null);
}

/// Child side of the stdin discipline (#263): make fd 0 the descriptor the parent
/// opened, then drop the parent's copy. Runs after `fork` and before `exec`, so nothing
/// here allocates. With a valid descriptor in hand `dup2` fails only on `EINTR`, which
/// is retried under the same nine-attempt bound as every other retry in this file — a
/// resumable handler installed by a preloaded library, with its signal arriving
/// continuously, would otherwise spin here under no budget. Anything else is treated
/// as unreachable and the child aborts rather than exiting: an exit code would be the
/// target's (`expected_status` accepts 0..255). A descriptor that already landed on 0
/// — the engine's own stdin was closed — is simply kept: `dup2(0, 0)` would be a no-op
/// and closing it would be the EBADF-at-exec trap this function exists to avoid.
fn adoptStdin(nfd: c_int) void {
    if (nfd == 0) return;
    var tries: u32 = 0;
    while (dup2(nfd, 0) < 0) {
        tries += 1;
        if (std.c._errno().* != EINTR or tries >= 9) abort();
    }
    _ = close(nfd);
}

/// A child the caller does not wait for: started, left running, stopped later.
///
/// Every other spawn here runs a child to completion, because everything else the
/// engine starts is something it is measuring. The macOS oracle is not — `fs_usage`
/// runs *beside* the subject rather than wrapping it (`src/fsusage.zig`), so its
/// lifetime is the caller's to bound, and the caller has to hold the pid to bound it.
///
/// stdout goes to `stdout_path`, opened `O_NOFOLLOW|O_EXCL` regardless of caller:
/// this one runs under `sudo`, so the file it truncates is chosen with root's
/// authority and a pre-planted symlink there is an arbitrary-file overwrite rather
/// than a spoiled capture. The child leaves the engine's process group for the same
/// reason every other spawn does — a terminal SIGINT must not reach it before the
/// caller has read what it captured.
pub fn spawnSidecar(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    stdout_path: []const u8,
) SpawnError!c_int {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const cargv = try arena.alloc(?[*:0]const u8, argv.len + 1);
    for (argv, 0..) |a, i| cargv[i] = (try arena.dupeZ(u8, a)).ptr;
    cargv[argv.len] = null;
    const stdout_z = (try arena.dupeZ(u8, stdout_path)).ptr;

    // Same stdin discipline as every other spawn (#263), same reasons, same shape:
    // opened by the parent, handed to the child, never an exit code. `sudo -n` never
    // prompts, so nothing observable changes here — what changes is that "every child
    // Sideeye forks starts at end-of-file" is one sentence with no exception in it.
    const nfd = RealOps.openDevNull();
    if (nfd < 0) return error.StdinUnavailable;

    const pid = fork();
    if (pid < 0) {
        _ = close(nfd);
        return error.ForkFailed;
    }
    if (pid == 0) {
        _ = setpgid(0, 0);
        adoptStdin(nfd);
        const cfd = open(stdout_z, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_EXCL, @as(c_uint, 0o600));
        if (cfd < 0) _exit(126);
        if (cfd != 1) {
            if (dup2(cfd, 1) < 0) _exit(126);
            _ = close(cfd);
        }
        _ = execvp(cargv[0].?, cargv.ptr);
        _exit(127);
    }
    _ = close(nfd);
    return pid;
}

pub const SidecarEnd = enum { was_running, had_exited, would_not_die };

/// Stop a sidecar and reap it, reporting whether it was still running when asked.
///
/// The answer matters: an observer that had already exited when the recording finished
/// ran out of its own bound, and its capture describes a window that closed early. The
/// caller turns that into a refusal rather than comparing against a truncated account.
///
/// **The signal goes to the process group, and it is SIGINT.** Both were paid for by a
/// measured failure. `spawnSidecar` starts `sudo`, which forks the real observer, so
/// signalling the returned pid reaches the privilege helper and not the process holding
/// the capture. And `fs_usage` buffers its output when stdout is not a terminal: killed
/// on any other signal it dies with the buffer unwritten, leaving a capture that ends
/// cleanly at a flush boundary tens of milliseconds in — which reads exactly like a
/// complete capture of a short window. SIGINT is the disposition that tool is built to
/// handle, since it is meant to be stopped from a terminal.
///
/// A caller signalling a privileged sidecar needs `signal_helper` — the group is root's
/// and an unprivileged parent cannot reach it. It is invoked as
/// `<helper...> kill -<sig> -<pgid>`.
pub fn stopSidecar(gpa: std.mem.Allocator, pid: c_int, signal_helper: []const []const u8, grace_ms: u64) SidecarEnd {
    // WNOHANG first: this is the observation that separates "we stopped it" from
    // "it was already gone", and it has to happen before any signal is sent.
    //
    // A `-1` here is not "still running". `ECHILD` means there is no such child to
    // wait for, which an inherited `SIGCHLD=SIG_IGN` produces by auto-reaping — and a
    // reaped pid may already name a stranger, whose process group this function would
    // then signal *as root*. The repository already holds that rule for the world
    // budget's teardown ("nothing may be signalled on an unpinned id"); it matters more
    // here, because the signal is privileged.
    var st: c_int = 0;
    const first = waitpid(pid, &st, WNOHANG);
    if (first == pid) return .had_exited;
    if (first < 0) return .had_exited;

    signalGroup(gpa, pid, "-INT", signal_helper);
    var waited: u64 = 0;
    while (waited < grace_ms) {
        const w = waitpid(pid, &st, WNOHANG);
        if (w == pid) return .was_running;
        if (w < 0) return .was_running; // reaped underneath us; the id is no longer ours
        sleepForMs(10);
        waited += 10;
    }
    signalGroup(gpa, pid, "-KILL", signal_helper);
    waited = 0;
    while (waited < grace_ms) {
        const w = waitpid(pid, &st, WNOHANG);
        if (w == pid) return .was_running;
        if (w < 0) return .was_running;
        sleepForMs(10);
        waited += 10;
    }
    return .would_not_die;
}

fn signalGroup(gpa: std.mem.Allocator, pgid: c_int, sig: []const u8, helper: []const []const u8) void {
    // The unprivileged attempt first: it is free, and it is the whole story when the
    // sidecar is not privileged.
    const raw: u8 = if (std.mem.eql(u8, sig, "-KILL")) SIGKILL else SIGINT;
    _ = kill(-pgid, @as(c_int, raw));
    if (helper.len == 0) return;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var list: std.ArrayList([]const u8) = .empty;
    for (helper) |h| list.append(arena, h) catch return;
    list.append(arena, "/bin/kill") catch return;
    list.append(arena, sig) catch return;
    const target = std.fmt.allocPrint(arena, "-{d}", .{pgid}) catch return;
    list.append(arena, target) catch return;
    _ = runChildCapture(gpa, list.items, &.{}, "/dev/null", null) catch return;
}

fn runChildImpl(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: ?[]const u8,
    minimal_env: bool,
    capture_stderr: bool,
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImplWithOps(gpa, argv, env_pairs, stdout_path, minimal_env, capture_stderr, null, cwd, RealOps) catch |e| switch (e) {
        // A null budget never takes the timeout branch — see the budget block below,
        // which is the only producer of this error and is gated on `budget_ms != null`.
        error.TimedOut => unreachable,
        error.ForkFailed, error.OutOfMemory, error.WaitFailed, error.StdinUnavailable => |narrow| narrow,
    };
}

/// How long the timeout path waits for its own SIGKILL to produce a reapable child
/// before it stops waiting and leaves a stray (#263). Not a second budget on the
/// target — SIGKILL delivery is the kernel's promise and normally lands in
/// microseconds — but the bound that keeps "the budget path never waits without
/// bound" true when the promise fails: a child pinned in uninterruptible sleep, or
/// one whose credentials the group signal could not reach.
const world_kill_grace_ms: u64 = 5000;

/// The operations the wait-and-teardown section performs, as a comptime seam (#264
/// added the wait; #263 widened it to the whole budget vocabulary). Production always
/// passes `RealOps`; a test passes a type that fakes the parts being driven and
/// delegates the rest. A fake `wait` is expected to delegate group waits (`pid < 0`)
/// to the real `waitpid`, so the test's own children are still reaped while the
/// direct wait is the part being driven.
///
/// The seam exists because the retry and deadline logic is the part that has been
/// wrong — a test that only exercised a pure "did it succeed?" helper would pass
/// against an implementation that ignored the real wait result entirely — and because
/// nine consecutive failures, an interruption storm, or a clock crossing a deadline
/// are not things a test can arrange for real.
const RealOps = struct {
    fn wait(pid: c_int, status: ?*c_int, options: c_int) c_int {
        return waitpid(pid, status, options);
    }
    fn waitidPoll(pid: c_int, info: *std.c.siginfo_t, options: c_int) c_int {
        return waitid(P_PID, pid, @ptrCast(info), options);
    }
    fn killGroup(pid: c_int) void {
        _ = kill(-pid, SIGKILL);
    }
    fn nowMs() u64 {
        return monotonicMs();
    }
    fn sleepMs(ms: u64) void {
        sleepForMs(ms);
    }
    /// The fork itself is on the seam (#263) so a test can assert that a spawn refused
    /// before it — `/dev/null` unavailable — never forked at all. Without this a
    /// "fork count is zero" assertion is vacuous: nothing in the fake could count.
    fn forkChild() c_int {
        return fork();
    }
    /// The child's stdin source, opened in the parent. On the seam for the same reason:
    /// the failure is arranged by a fake, never for real.
    fn openDevNull() c_int {
        return open("/dev/null", O_RDONLY, @as(c_uint, 0));
    }
};

/// Monotonic milliseconds, on the clock a deadline can trust.
///
/// Public because its callers want it for unrelated reasons and none should own a second
/// copy: the wait loop's deadline reaches it through `RealOps` (a seam a test
/// substitutes), preflight's `--twice` reads it directly to report the interval it
/// actually observed between the two runs (#199) — a reported gap derived from the
/// sleep it asked for rather than the clock would be the measurement describing its
/// own intent — and the bounded config read uses it to stop waiting for a peer that is
/// not coming (#400 follow-up).
pub fn monotonicMs() u64 {
    var ts: std.c.timespec = undefined;
    // A compile-time-constant, valid clockid cannot produce EINVAL, and a stack
    // pointer cannot produce EFAULT (POSIX clock_gettime). The same shape as the
    // world loop's `bufPrint … catch unreachable`: a cannot-happen made loud
    // rather than a garbage value read silently.
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) unreachable;
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}

/// Sleep, best effort: a signal that interrupts the wait leaves it short, and no
/// caller here re-arms it. Every caller tolerates that — the wait loop re-reads the
/// clock, preflight measures the interval rather than assuming it, and the bounded
/// config read (#400 follow-up) re-reads the clock on each pass as well.
pub fn sleepForMs(ms: u64) void {
    var ts: std.c.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    _ = nanosleep(&ts, null);
}

fn runChildImplWithOps(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    stdout_path: ?[]const u8,
    minimal_env: bool,
    capture_stderr: bool,
    budget_ms: ?u64,
    cwd: ?[]const u8,
    comptime Ops: type,
) (SpawnError || error{TimedOut})!Term {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Duplicated before the fork: after it, the child is in the one place where an
    // allocation must not happen (a malloc lock held by another thread at fork time is
    // held forever in the child), and this is the same rule the argv and env arrays
    // above already follow.
    const cwd_z: ?[*:0]const u8 = if (cwd) |c| (try arena.dupeZ(u8, c)).ptr else null;

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

    // The budget clock starts before the fork: the child is runnable the moment fork
    // returns, and time the parent spends unscheduled between fork and its first poll
    // belongs to the world's wall-clock budget, not to nobody. Guarded, so a null
    // budget still never reads the clock.
    const budget_t0: u64 = if (budget_ms != null) Ops.nowMs() else 0;

    // Every child starts with its stdin at end-of-file (#263). The descriptor is opened
    // HERE, in the parent, before the fork: a failure is then a named spawn error on the
    // caller's channel, and never a code in the target's exit-status namespace (the
    // first design had the child `_exit(123)`; `expected_status` accepts 0..255, so 123
    // is a status a define may legitimately declare, and the parent would have misread
    // that target). No O_CLOEXEC, on purpose: when the engine's own fd 0 is closed this
    // open returns 0, `dup2(0, 0)` is a no-op, and a close-on-exec flag would then shut
    // fd 0 at exec — the child would read EBADF, not EOF. The child handles that case by
    // keeping the descriptor where it landed; the parent closes its copy either way.
    const nfd = Ops.openDevNull();
    if (nfd < 0) return error.StdinUnavailable;

    const pid = Ops.forkChild();
    if (pid < 0) {
        _ = close(nfd);
        return error.ForkFailed;
    }
    if (pid == 0) {
        // Before exec, so the target never runs in the engine's group.
        _ = setpgid(0, 0);
        // stdin first, before any capture: a child that could not be given its stdin
        // must not run at all. The retry bound, the abort, and the fd-0 case are all
        // in `adoptStdin`, shared with the sidecar's fork.
        adoptStdin(nfd);
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
                // The child (a config's operation, untrusted) must not write to the MCP
                // transport on fd 2 either: stderr → the same capture file. (fd 0 was
                // already pointed at /dev/null above, for every child, not only this
                // path — #263.) Higher fds are closed so no inherited descriptor (the
                // JSON-RPC stdin among them) survives into the child.
                _ = dup2(1, 2); // stderr → capture
                var fd: c_int = 3;
                while (fd < 256) : (fd += 1) _ = close(fd);
            }
        }
        // After the descriptor work above and before exec. Placed here so a capture the
        // child could not open still reports 126 rather than being pre-empted by a cwd
        // that also failed — one refusal per cause, and the earlier one wins.
        //
        // 125 is its own code: 126 already carries two meanings the engine cannot tell
        // apart (`checker_not_falsified` says so at the checker probe), and adding a
        // third would make the ambiguity structural rather than local. The parent
        // resolves and vets this path before the fork, so reaching here means the
        // directory went away between the vet and the exec.
        if (cwd_z) |cz| {
            if (chdir(cz) != 0) _exit(125);
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
    // The parent's copy of the child's stdin source: the child has its own by now.
    _ = close(nfd);
    // Repeated in the parent to close the window where the child has not been scheduled
    // yet. Whichever call runs first wins; the second fails harmlessly (EACCES once the
    // child has exec'd, ESRCH if it has already exited).
    _ = setpgid(pid, pid);

    // Wait for the child to finish, but leave it reapable so its pid — and therefore the
    // group id about to be signalled — cannot be handed to anything else.
    if (budget_ms) |budget| {
        // The bounded wait (#263). Same WNOWAIT discipline as the blocking branch
        // below, plus WNOHANG and a monotonic deadline. Every path out of this block
        // returns from inside it — the blocking reap-and-drain below belongs to the
        // null-budget branch alone — and none of them contains an unbounded call.
        const deadline = budget_t0 + budget;
        var interval: u64 = 1;
        var eintr_streak: u32 = 0;
        var past_deadline = false;
        const outcome: enum { exited, timed_out, waitid_broke } = poll: while (true) {
            var info: std.c.siginfo_t = std.mem.zeroes(std.c.siginfo_t);
            const rc = Ops.waitidPoll(pid, &info, WEXITED | WNOWAIT | WNOHANG);
            if (rc != 0) {
                // An interruption is retried — bounded by the same nine-attempt
                // discipline as the blocking reap below, because a storm of them
                // would otherwise poll forever without ever reaching the clock, and
                // "the budget path never waits without bound" has to hold against
                // the storm too. Exhaustion joins every other failure in the
                // permanent arm, and the permanent arm does NOT kill: ECHILD here
                // can mean an inherited SIGCHLD disposition auto-reaped the child,
                // and a reaped child's pid may already name a stranger. The
                // conservative rule of the blocking branch holds — nothing is
                // signalled on an unpinned id. A failed call is not an observation
                // of "still running" either, so it can never answer .timed_out.
                if (std.c._errno().* == EINTR) {
                    eintr_streak += 1;
                    if (eintr_streak < 9) continue :poll;
                }
                break :poll .waitid_broke;
            }
            eintr_streak = 0;
            if (siPid(&info) == pid) break :poll .exited;
            const now = Ops.nowMs();
            if (now >= deadline) {
                // The deadline has passed and this successful poll saw the child
                // running. One more successful observation is taken — immediately,
                // no sleep — before the verdict, so a child that exited between the
                // last sleep and the deadline check is accepted: the boundary race
                // classifies toward the child. This is the measurement rule the
                // member's doc promises, not a proof the child finished its work
                // inside the budget. Only a *successful* post-deadline observation
                // can answer .timed_out; a failing one lands above in .waitid_broke
                // and kills nothing.
                if (past_deadline) break :poll .timed_out;
                past_deadline = true;
                continue :poll;
            }
            // Adaptive: a fast world pays ~1ms, a hung one converges to 10ms polls.
            Ops.sleepMs(@min(interval, deadline - now));
            interval = @min(interval * 2, 10);
        };
        switch (outcome) {
            .exited => {
                // The successful observation pinned the id (WNOWAIT consumed
                // nothing, and with SIGCHLD at default an exited child is a zombie,
                // not a recycled pid), so the group signal is safe — the blocking
                // branch's own argument.
                Ops.killGroup(pid);
                // The direct reap may block: the child was observed exited and the
                // default disposition holds it zombie, so the wait returns without
                // waiting. The group drain may NOT block — the target can have put
                // other processes in the group directly, and if the SIGKILL failed
                // to land on one of them (uninterruptible sleep, changed
                // credentials) a blocking drain would hang the very path that
                // promises not to. Survivors are strays for the quiescence check.
                var status: c_int = 0;
                const wait_failed = for (0..9) |_| {
                    if (Ops.wait(pid, &status, 0) >= 0) break false;
                    if (std.c._errno().* != EINTR) break true;
                } else true;
                while (Ops.wait(-pid, null, WNOHANG) > 0) {}
                if (wait_failed) return error.WaitFailed;
                return decodeStatus(status);
            },
            .timed_out => {
                // The observation one line up saw the child alive, and the default
                // SIGCHLD disposition holds it zombie once it dies, so the id is
                // pinned here too.
                Ops.killGroup(pid);
                // Reap under a grace, not without bound: SIGKILL normally produces a
                // reapable child in microseconds, and when it cannot — uninterruptible
                // sleep, or credentials the group signal does not reach — the child is
                // left as a stray for the quiescence check rather than hanging the
                // very path that exists to end a hang. The kill's rc is deliberately
                // not consulted for the verdict: the budget expiry was measured, and
                // a group-kill rc of 0 would not prove delivery to the direct child
                // anyway.
                const grace_deadline = Ops.nowMs() + world_kill_grace_ms;
                var ginterval: u64 = 1;
                reap: while (true) {
                    const wrc = Ops.wait(pid, null, WNOHANG);
                    if (wrc == pid) break :reap;
                    if (wrc < 0 and std.c._errno().* != EINTR) break :reap;
                    const gnow = Ops.nowMs();
                    if (gnow >= grace_deadline) break :reap;
                    Ops.sleepMs(@min(ginterval, grace_deadline - gnow));
                    ginterval = @min(ginterval * 2, 10);
                }
                // The drain still runs before the error is returned — the discipline
                // the blocking branch states — but non-blocking here, for the same
                // reason as the grace above.
                while (Ops.wait(-pid, null, WNOHANG) > 0) {}
                return error.TimedOut;
            },
            .waitid_broke => {
                // Nothing was signalled (see the loop comment), so nothing here may
                // block on a child that might still be running: one non-blocking reap
                // attempt, a non-blocking drain, and the same refusal the blocking
                // branch gives a broken wait. A live child this leaves behind is a
                // stray; the stray is what the quiescence check is for.
                _ = Ops.wait(pid, null, WNOHANG);
                while (Ops.wait(-pid, null, WNOHANG) > 0) {}
                return error.WaitFailed;
            },
        }
    } else {
        var info: [256]u8 align(16) = undefined;
        if (waitid(P_PID, pid, &info, WEXITED | WNOWAIT) == 0) {
            // Everything the target left behind, in one signal, while the id is still pinned.
            _ = kill(-pid, SIGKILL);
        }
        // If `waitid` failed the id is not pinned, so nothing is signalled: sending SIGKILL to
        // a group that may have been recycled is worse than leaving a stray process. The stray
        // is what the quiescence check is for.
    }

    // Retried rather than assumed. `status` is only written when the call succeeds, so a
    // discarded failure leaves it zero, `decodeStatus` reads a killed world as a clean
    // exit, and the world is reported as `kill_did_not_land` — the wrong reason. Same class
    // as the ordering defect above: a wait call's side effect trusted without checking that
    // the call happened.
    //
    // The retry is EINTR-only. This comment used to say there was "no errno binding here to
    // tell a retryable interruption from a permanent failure", and spent the same eight
    // attempts on both. That was wrong: `EINTR` is declared at the top of this file and
    // `std.c._errno()` is already used in it. A permanent failure now refuses at once
    // instead of being retried into the same wrong answer, and the bound stays for the
    // interruption case so an unbounded loop cannot hang.
    // Nine attempts: the call, plus eight retries for interruption. Counted by the loop
    // rather than by hand — a hand-incremented version of this spent one attempt fewer,
    // depending on whether the bound was tested before or after the increment, and a test
    // is what noticed. `else` runs only when the range is exhausted without a `break`.
    var status: c_int = 0;
    const wait_failed = for (0..9) |_| {
        if (Ops.wait(pid, &status, 0) >= 0) break false;
        if (std.c._errno().* != EINTR) break true;
    } else true;

    // Reap what is still ours. Usually nothing: grandchildren belong to init the moment
    // the direct child dies. The loop exists so the engine does not accumulate zombies
    // from a target that put several processes in the group directly.
    //
    // This runs *before* the wait failure is returned. Returning early would skip the drain
    // and leave behind the direct child itself — never reaped, since reaping it is exactly
    // what just failed. A fix for a wrong verdict must not introduce a process leak.
    while (Ops.wait(-pid, null, 0) > 0) {}

    if (wait_failed) return error.WaitFailed;
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

/// An Ops whose direct wait the tests can drive, everything else real (see `RealOps`).
/// Nine consecutive `waitpid` failures are not something a test can arrange for real.
///
/// Group waits (`pid < 0`) are delegated to the real `waitpid`, so the drain actually reaps
/// this test's children; only the direct child's wait is faked. State is file-scope because
/// the seam takes plain functions: `zig build test` runs this file in several concurrent
/// *binaries*, but the tests inside one binary run in sequence, so resetting at the top of
/// each test is enough (a shared *path* would not be — see #28 below).
const FakeWait = struct {
    /// Same value on Linux and Darwin, like `EINTR` at the top of this file.
    const ECHILD: c_int = 10;

    var direct_calls: u32 = 0;
    var drain_calls: u32 = 0;
    var eintr_budget: u32 = 0;
    var permanent: bool = false;
    var deliver_status: c_int = 0;
    var fork_calls: u32 = 0;
    var devnull_fails: bool = false;

    fn reset() void {
        direct_calls = 0;
        drain_calls = 0;
        eintr_budget = 0;
        permanent = false;
        deliver_status = 0;
        fork_calls = 0;
        devnull_fails = false;
    }

    fn forkChild() c_int {
        fork_calls += 1;
        return fork();
    }
    fn openDevNull() c_int {
        if (devnull_fails) {
            std.c._errno().* = EINTR; // any errno: the caller reads only the sign
            return -1;
        }
        return RealOps.openDevNull();
    }

    fn wait(pid: c_int, status: ?*c_int, options: c_int) c_int {
        if (pid < 0) {
            drain_calls += 1;
            return waitpid(pid, status, options);
        }
        direct_calls += 1;
        if (permanent) {
            std.c._errno().* = ECHILD;
            return -1;
        }
        if (eintr_budget > 0) {
            eintr_budget -= 1;
            std.c._errno().* = EINTR;
            return -1;
        }
        if (status) |s| s.* = deliver_status;
        return 0;
    }

    // The rest of the Ops surface, real: these three tests drive the retry decision
    // only, and a null budget never touches the clock or sleep (a fourth test pins that).
    const waitidPoll = RealOps.waitidPoll;
    const killGroup = RealOps.killGroup;
    const nowMs = RealOps.nowMs;
    const sleepMs = RealOps.sleepMs;
};

test "a wait that fails permanently refuses instead of reporting a clean exit" {
    FakeWait.reset();
    FakeWait.permanent = true;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, null, null, FakeWait);

    // Before #264 this returned `.exited = 0`: `status` keeps the zero it was initialised
    // with, and every explored world is expected to die by signal, so the engine reported
    // `kill_did_not_land` — a confident wrong reason rather than a refusal.
    try std.testing.expectError(error.WaitFailed, r);
    // A permanent failure is not an interruption, so it is not retried into the same answer.
    try std.testing.expectEqual(@as(u32, 1), FakeWait.direct_calls);
    // The drain still ran: returning the error early would skip it and leave behind the
    // child whose reaping is exactly what just failed.
    try std.testing.expect(FakeWait.drain_calls >= 1);
}

test "an interrupted wait is retried and the status that finally arrives is the one decoded" {
    FakeWait.reset();
    FakeWait.eintr_budget = 3;
    FakeWait.deliver_status = 0x0100; // exit(1)
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, null, null, FakeWait);

    // The status written by the call that succeeded — not the zero the loop started with.
    try std.testing.expectEqual(Term{ .exited = 1 }, term);
    // Three interruptions, then the call that worked.
    try std.testing.expectEqual(@as(u32, 4), FakeWait.direct_calls);
}

test "an interruption that never stops is bounded rather than looping forever" {
    FakeWait.reset();
    FakeWait.eintr_budget = std.math.maxInt(u32);
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, null, null, FakeWait);

    try std.testing.expectError(error.WaitFailed, r);
    // The first call plus the eight retries the bound allows.
    try std.testing.expectEqual(@as(u32, 9), FakeWait.direct_calls);
    try std.testing.expect(FakeWait.drain_calls >= 1);
}

test "a child whose stdin cannot be pointed at /dev/null is refused by name and never forked (#263)" {
    FakeWait.reset();
    FakeWait.devnull_fails = true;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, null, null, FakeWait);

    try std.testing.expectError(error.StdinUnavailable, r);
    // Refused BEFORE the fork: the parent opens the descriptor, so a child that could
    // not have its stdin arranged does not exist to have an exit status at all. `fork`
    // is on the seam precisely so this zero is a measurement and not a tautology.
    try std.testing.expectEqual(@as(u32, 0), FakeWait.fork_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeWait.direct_calls);
}

test "every child starts with its stdin at /dev/null, on the plain path with no capture (#263)" {
    FakeWait.reset();
    // Read out of the child, like the cwd test below: the property is about the forked
    // process's fd 0, and a test that inspected this process would pass against an
    // implementation that redirected the engine instead. `-ef` compares identities, so
    // this asks "is fd 0 the null device", not "does reading it give EOF" — an inherited
    // closed fd or an empty pipe would answer the weaker question the same way. The
    // plain path (no capture, not minimal_env) is chosen because that is the one the
    // MCP-only redirect never covered: setup and the checker run through it.
    const is_null = [_][]const u8{ "/bin/sh", "-c", "[ /dev/stdin -ef /dev/null ]" };
    const term = try runChildImplWithOps(std.testing.allocator, &is_null, &.{}, null, false, false, null, null, FakeWait);
    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.fork_calls);
}

test "a declared cwd is where the child starts; null leaves it at the engine's" {
    // Read out of the child rather than asserted about the parent: the whole point of
    // the chdir is that it happens in the forked process and nowhere else, and a test
    // that checked this process's cwd would pass against an implementation that moved
    // the engine — the one outcome the design refuses.
    //
    // `/usr` rather than a scratch directory: it exists on both target platforms and is
    // not a symlink on either, so `pwd` answers the same bytes that went in. A path that
    // resolves elsewhere (macOS `/tmp` → `/private/tmp`) would fail this for a reason
    // that has nothing to do with the chdir.
    const at_usr = [_][]const u8{ "/bin/sh", "-c", "[ \"$(pwd)\" = /usr ]" };

    const moved = try runChild(std.testing.allocator, &at_usr, &.{}, "/usr");
    try std.testing.expectEqual(@as(u8, 0), moved.exited);

    // The control. Without it, an implementation that chdir'd to /usr unconditionally —
    // ignoring the parameter entirely — would satisfy the assertion above. This test
    // process does not run in /usr, so the same command must now answer non-zero.
    const stayed = try runChild(std.testing.allocator, &at_usr, &.{}, null);
    try std.testing.expect(stayed.exited != 0);
}

/// An Ops whose whole budget vocabulary the tests script (#263): the waitid poll
/// answers from a play-list, the clock advances a fixed step per read, sleeps and
/// kills are counted rather than performed — except that the group kill and group
/// waits delegate to the real calls so the test's own forked child is still cleaned
/// up. What this buys over `FakeWait`: a deadline crossing, an interruption storm at
/// the poll, and a SIGKILL that never lands are all drivable in zero real time.
const FakeBudget = struct {
    const Poll = union(enum) { running, exited, err: c_int };

    var script: []const Poll = &.{};
    var script_i: usize = 0;
    var direct_waits: []const c_int = &.{};
    var direct_wait_i: usize = 0;
    var deliver_status: c_int = 0;
    var now: u64 = 0;
    var now_step: u64 = 0;
    var kill_calls: u32 = 0;
    var sleep_calls: u32 = 0;
    var clock_calls: u32 = 0;
    var blocking_direct_waits: u32 = 0;
    var blocking_group_waits: u32 = 0;
    var drain_calls: u32 = 0;

    fn reset() void {
        script = &.{};
        script_i = 0;
        direct_waits = &.{};
        direct_wait_i = 0;
        deliver_status = 0;
        now = 0;
        now_step = 0;
        kill_calls = 0;
        sleep_calls = 0;
        clock_calls = 0;
        blocking_direct_waits = 0;
        blocking_group_waits = 0;
        drain_calls = 0;
    }

    fn setSiPid(info: *std.c.siginfo_t, pid: std.c.pid_t) void {
        switch (builtin.os.tag) {
            .macos => info.pid = pid,
            .linux => info.fields.common.first.piduid.pid = pid,
            else => unreachable,
        }
    }

    fn waitidPoll(pid: c_int, info: *std.c.siginfo_t, options: c_int) c_int {
        _ = options;
        const step = if (script_i < script.len) script[script_i] else script[script.len - 1];
        script_i += 1;
        switch (step) {
            .running => return 0,
            .exited => {
                setSiPid(info, @intCast(pid));
                return 0;
            },
            .err => |e| {
                std.c._errno().* = e;
                return -1;
            },
        }
    }
    fn killGroup(pid: c_int) void {
        kill_calls += 1;
        // Delegated, so the real forked child's group is genuinely signalled and the
        // real drain below finds only corpses.
        _ = kill(-pid, SIGKILL);
    }
    fn nowMs() u64 {
        clock_calls += 1;
        now += now_step;
        return now;
    }
    fn sleepMs(ms: u64) void {
        _ = ms;
        sleep_calls += 1;
    }
    // The budget tests drive the deadline logic only; the spawn itself is real.
    const forkChild = RealOps.forkChild;
    const openDevNull = RealOps.openDevNull;
    fn wait(pid: c_int, status: ?*c_int, options: c_int) c_int {
        if (pid < 0) {
            drain_calls += 1;
            if (options == 0) blocking_group_waits += 1;
            return waitpid(pid, status, options);
        }
        if (options == 0) blocking_direct_waits += 1;
        if (direct_wait_i < direct_waits.len) {
            const rc = direct_waits[direct_wait_i];
            direct_wait_i += 1;
            if (rc > 0) {
                if (status) |s| s.* = deliver_status;
                return pid;
            }
            if (rc < 0) std.c._errno().* = FakeWait.ECHILD;
            return rc;
        }
        if (status) |s| s.* = deliver_status;
        return pid;
    }
};

test "a world over budget is sent SIGKILL after a final observation, reaped under the grace, and refused TimedOut (#263)" {
    FakeBudget.reset();
    // First poll: alive, past the deadline. Second (final) observation: still alive
    // → timeout. The clock's first read is the pre-fork budget_t0.
    FakeBudget.script = &.{ .running, .running };
    FakeBudget.direct_waits = &.{1}; // the grace reap succeeds at once
    FakeBudget.now_step = 100;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 10, null, FakeBudget);

    try std.testing.expectError(error.TimedOut, r);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    // The drain ran before the error was returned, and nothing in the path blocked.
    try std.testing.expect(FakeBudget.drain_calls >= 1);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "si_pid zero is 'still running', not 'exited': the poll keeps polling until the field names the child (#263)" {
    FakeBudget.reset();
    // Two honest not-yet answers, then the child. rc==0 alone must not be read as exit.
    FakeBudget.script = &.{ .running, .running, .exited };
    FakeBudget.deliver_status = 0; // exit(0) once the shared reap runs
    FakeBudget.now_step = 1; // deadline 1000 is never approached
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 1000, null, FakeBudget);

    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    // All three polls were consumed: an implementation that treated the first rc==0
    // as an exit would have stopped at one.
    try std.testing.expectEqual(@as(usize, 3), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(u32, 2), FakeBudget.sleep_calls);
    // The exited side of the budget path drains without blocking too: the target can
    // have put other processes in the group directly, and one of them surviving the
    // SIGKILL must not hang the path that promises not to wait without bound.
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "a null budget never touches the budget vocabulary: no clock, no sleep, no poll (#263)" {
    FakeBudget.reset();
    FakeBudget.deliver_status = 0;
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, null, null, FakeBudget);

    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.clock_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(usize, 0), FakeBudget.script_i);
}

test "a child the final observation sees exited is accepted, not timed out — the boundary race classifies toward the child (#263)" {
    FakeBudget.reset();
    // Alive at the poll, deadline crossed, exited by the final observation.
    FakeBudget.script = &.{ .running, .exited };
    FakeBudget.deliver_status = 0;
    FakeBudget.now_step = 100;
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 10, null, FakeBudget);

    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "a poll interruption retries under the same deadline; a permanent poll failure kills nothing and refuses without blocking (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{ .{ .err = EINTR }, .{ .err = EINTR }, .{ .err = FakeWait.ECHILD } };
    FakeBudget.direct_waits = &.{0}; // the one non-blocking reap attempt: nothing there
    FakeBudget.now_step = 1;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 1000, null, FakeBudget);

    try std.testing.expectError(error.WaitFailed, r);
    // ECHILD can mean an inherited SIGCHLD disposition auto-reaped the child, and a
    // reaped child's pid may already name a stranger: nothing may be signalled on an
    // unpinned id.
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.kill_calls);
    // Interruptions retried without sleeping, and nothing in the path blocked.
    try std.testing.expectEqual(@as(usize, 3), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expect(FakeBudget.drain_calls >= 1);
}

test "an interruption storm cannot poll forever: the ninth consecutive interruption refuses WaitFailed and kills nothing (#263)" {
    FakeBudget.reset();
    // One step that repeats: a poll interrupted every single time. Without the bound
    // this loop never reaches the clock, and the budget silently stops existing.
    FakeBudget.script = &.{.{ .err = EINTR }};
    FakeBudget.direct_waits = &.{0}; // the one non-blocking reap attempt: nothing there
    FakeBudget.now_step = 1;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 1000, null, FakeBudget);

    try std.testing.expectError(error.WaitFailed, r);
    // Nine attempts — the blocking reap's own discipline — then refusal, no kill:
    // an interrupted call is not an observation, so it must never become .timed_out.
    try std.testing.expectEqual(@as(usize, 9), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "a SIGKILL that never lands exhausts the grace, drains without blocking, and still answers TimedOut (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{ .running, .running };
    // The direct child never becomes reapable — uninterruptible sleep, or credentials
    // the group signal could not reach.
    FakeBudget.direct_waits = &.{ 0, 0, 0, 0, 0, 0, 0, 0 };
    FakeBudget.now_step = 3000;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, false, 10, null, FakeBudget);

    try std.testing.expectError(error.TimedOut, r);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    // The stray is left behind; nothing blocked waiting for it.
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expect(FakeBudget.drain_calls >= 1);
    try std.testing.expect(FakeBudget.sleep_calls >= 1);
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

test "EAGAIN is what the kernel returns for a non-blocking read with a peer and no data" {
    // Asks the kernel rather than asserting the number, the same way the O_NOFOLLOW test
    // below does and for the same reason: the value differs by operating system (11 on
    // Linux, 35 on Darwin) and is only ever compared against. A wrong constant does not
    // fail — it makes "the writer has not written yet" unrecognisable, and the reader
    // that depends on it stops retrying while every other test stays green.
    var bb: [128]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-eagain-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, @as(c_uint, 0o755));
    var fb: [160]u8 = undefined;
    const fifo_z = std.fmt.bufPrintZ(&fb, "{s}/p", .{base}) catch unreachable;
    _ = unlink(fifo_z.ptr);
    try std.testing.expect(mkfifo(fifo_z.ptr, @as(c_uint, 0o644)) == 0);
    defer {
        _ = unlink(fifo_z.ptr);
        _ = rmdir(base.ptr);
    }

    const rfd = open(fifo_z.ptr, O_RDONLY | O_NONBLOCK, @as(c_uint, 0));
    try std.testing.expect(rfd >= 0);
    defer _ = close(rfd);

    // Before the writer exists the same read answers 0 — end of file — which is the
    // *other* branch of the retry rule. Pinning both here keeps the two apart: they look
    // identical to a caller that only checks "did I get bytes".
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(@as(isize, 0), read(rfd, &buf, buf.len));

    const wfd = open(fifo_z.ptr, O_WRONLY, @as(c_uint, 0));
    try std.testing.expect(wfd >= 0);
    defer _ = close(wfd);

    const n = read(rfd, &buf, buf.len);
    try std.testing.expect(n < 0);
    try std.testing.expectEqual(EAGAIN, std.c._errno().*);
}

test "O_NOFOLLOW actually refuses a symlink" {
    // Asks the kernel rather than asserting the number. A test spelling the value out is
    // satisfied by whatever the constant happens to say, which is how this constant
    // carried the x86_64 value for all of Linux and left its one caller inert on arm64.
    var pb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-nofollow-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, 0o755);
    var tb: [160]u8 = undefined;
    const target_z = std.fmt.bufPrintZ(&tb, "{s}/target", .{base}) catch unreachable;
    var lb: [160]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&lb, "{s}/link", .{base}) catch unreachable;
    defer {
        _ = unlink(link_z.ptr);
        _ = unlink(target_z.ptr);
        _ = rmdir(base.ptr);
    }

    const tfd = open(target_z.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(tfd >= 0);
    _ = close(tfd);
    try std.testing.expect(symlink(target_z.ptr, link_z.ptr) == 0);

    // Without the flag the link opens; with it the open must fail. Both directions,
    // because "the open failed" alone would also be true of a path that does not exist.
    const followed = open(link_z.ptr, O_WRONLY, @as(c_uint, 0));
    try std.testing.expect(followed >= 0);
    _ = close(followed);

    const refused = open(link_z.ptr, O_WRONLY | O_NOFOLLOW, @as(c_uint, 0));
    if (refused >= 0) {
        _ = close(refused);
        return error.NofollowDidNotRefuse;
    }
}

test "O_DIRECTORY actually refuses a regular file" {
    // A regular file, deliberately, and not the symlink the neighbour above uses: on a
    // symlink the open fails because of O_NOFOLLOW whatever O_DIRECTORY happens to say,
    // so that shape cannot discriminate this constant at all. A wrong O_DIRECTORY does
    // not refuse loudly either — it opens things the destructive walk then recurses into.
    var pb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-odirectory-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, 0o755);
    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/plain", .{base}) catch unreachable;
    defer {
        _ = unlink(file_z.ptr);
        _ = rmdir(base.ptr);
    }
    const wfd = open(file_z.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(wfd >= 0);
    _ = close(wfd);

    // Both directions, and the errno: without the flag the file opens; with it the open
    // must fail with ENOTDIR specifically. "It failed" alone is also true of a path that
    // does not exist, which is what a zeroed flag plus a typo would look like.
    const opened = open(file_z.ptr, O_RDONLY, @as(c_uint, 0));
    try std.testing.expect(opened >= 0);
    _ = close(opened);

    const refused = open(file_z.ptr, O_RDONLY | O_DIRECTORY | O_NOFOLLOW, @as(c_uint, 0));
    if (refused >= 0) {
        _ = close(refused);
        return error.ODirectoryDidNotRefuse;
    }
    try std.testing.expectEqual(ENOTDIR, std.c._errno().*);
}

test "kindOfFd answers about the descriptor, and a pipe is not a regular file (#400)" {
    // A pipe, not a FIFO opened by name. `kindOfFd` exists because opening a FIFO by
    // name is the thing that hangs, so a test that opened one would be reaching through
    // the hazard to check the guard — and would hang for real if `O_NONBLOCK` ever came
    // off the caller. `pipe()` yields the same class of descriptor with no filesystem
    // and no possibility of blocking.
    var fds: [2]c_int = undefined;
    try std.testing.expect(pipe(&fds) == 0);
    defer _ = close(fds[0]);
    defer _ = close(fds[1]);
    try std.testing.expectEqual(Kind.other, try kindOfFd(fds[0]));

    // pid-unique for the same reason as the neighbour above (#28).
    var bb: [128]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-kindfd-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, @as(c_uint, 0o755));

    // The control. Without it, a `kindOfFd` that answered `.other` for everything would
    // pass the assertion above — the refusal would fire on every case file ever read and
    // the test would still be green.
    var fb: [160]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fb, "{s}/f", .{base}) catch unreachable;
    const wfd = open(file_z.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(wfd >= 0);
    _ = close(wfd);
    const rfd = open(file_z.ptr, O_RDONLY | O_NONBLOCK, @as(c_uint, 0));
    try std.testing.expect(rfd >= 0);
    try std.testing.expectEqual(Kind.file, try kindOfFd(rfd));
    _ = close(rfd);

    // A directory is its own answer, not `.file`: the caller tests `!= .file`, so this
    // pins that a directory is refused too rather than read.
    const dfd = open(base.ptr, O_RDONLY | O_DIRECTORY, @as(c_uint, 0));
    try std.testing.expect(dfd >= 0);
    try std.testing.expectEqual(Kind.dir, try kindOfFd(dfd));
    _ = close(dfd);

    _ = unlink(file_z.ptr);
    _ = rmdir(base.ptr);
}

test "kindAtNoFollow reads the descriptor it is given, not the name alone" {
    // Same entry name under two directories, different kinds. A classifier that ignored
    // its dirfd — or an absolute path, which makes the kernel ignore it — would answer
    // identically for both, so this is the shape that catches the mistake the function's
    // doc warns about.
    var pb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-kindat-{d}", .{getpid()}) catch unreachable;
    _ = mkdir(base.ptr, 0o755);
    var ab: [160]u8 = undefined;
    const a_z = std.fmt.bufPrintZ(&ab, "{s}/a", .{base}) catch unreachable;
    var bb: [160]u8 = undefined;
    const b_z = std.fmt.bufPrintZ(&bb, "{s}/b", .{base}) catch unreachable;
    var afb: [160]u8 = undefined;
    const a_x = std.fmt.bufPrintZ(&afb, "{s}/a/x", .{base}) catch unreachable;
    var bdb: [160]u8 = undefined;
    const b_x = std.fmt.bufPrintZ(&bdb, "{s}/b/x", .{base}) catch unreachable;
    defer {
        _ = unlink(a_x.ptr);
        _ = rmdir(b_x.ptr);
        _ = rmdir(a_z.ptr);
        _ = rmdir(b_z.ptr);
        _ = rmdir(base.ptr);
    }
    try std.testing.expect(mkdir(a_z.ptr, 0o755) == 0);
    try std.testing.expect(mkdir(b_z.ptr, 0o755) == 0);
    const fd_file = open(a_x.ptr, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd_file >= 0);
    _ = close(fd_file);
    try std.testing.expect(mkdir(b_x.ptr, 0o755) == 0);

    const fa = open(a_z.ptr, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fa >= 0);
    defer _ = close(fa);
    const fb2 = open(b_z.ptr, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fb2 >= 0);
    defer _ = close(fb2);

    try std.testing.expectEqual(Kind.file, try kindAtNoFollow(fa, "x"));
    try std.testing.expectEqual(Kind.dir, try kindAtNoFollow(fb2, "x"));
}
