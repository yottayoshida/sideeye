const std = @import("std");
const builtin = @import("builtin");

pub const Dirent = std.c.dirent;

pub extern "c" fn opendir(name: [*:0]const u8) ?*anyopaque;
pub extern "c" fn readdir(dirp: *anyopaque) ?*Dirent;
pub extern "c" fn closedir(dirp: *anyopaque) c_int;
///
/// This was a fixed three-argument declaration, and on arm64 macOS that silently loses
/// `mode`: variadic arguments travel on the stack, fixed ones in registers, so the
/// callee read a register the caller never wrote. Every file `restore()` wrote came out
/// with permissions nobody asked for — and since the engine then failed to read its own
/// output, the symptom looked like a shim defect for several rounds. The shim was fine.
pub extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
pub extern "c" fn pread(fd: c_int, buf: [*]u8, n: usize, off: i64) isize;
pub extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
pub extern "c" fn close(fd: c_int) c_int;
pub extern "c" fn dup2(old_fd: c_int, new_fd: c_int) c_int;
pub extern "c" fn lseek(fd: c_int, offset: i64, whence: c_int) i64;
pub const SEEK_SET: c_int = 0;
pub const SEEK_END: c_int = 2;

pub const EINTR: c_int = 4;
pub const ENOENT: c_int = 2;
pub extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
pub extern "c" fn mkdtemp(template: [*:0]u8) ?[*:0]u8;
pub extern "c" fn flock(fd: c_int, operation: c_int) c_int;
pub extern "c" fn ftruncate(fd: c_int, length: i64) c_int;
pub extern "c" fn rmdir(path: [*:0]const u8) c_int;
pub extern "c" fn unlink(path: [*:0]const u8) c_int;
pub extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, bufsiz: usize) isize;
pub extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
pub extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int;

// The descriptor-relative half of the calls above (#327). The destructive walk opens its
// root once and reaches every entry through these, so a swap of the root's *pathname*
// after the open cannot redirect a delete.
//
/// Variadic for the reason `open` is, twenty lines up: a fixed four-argument declaration
/// loses `mode` on arm64 macOS, where variadic arguments travel on the stack and fixed
/// ones in registers. The walk only ever passes three, but a declaration that is wrong
/// for the four-argument call is wrong the day somebody makes one.
pub extern "c" fn openat(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) c_int;
pub extern "c" fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) c_int;
pub extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) c_int;
/// On a held descriptor only: chmod by name follows a link swapped in at that name.
pub extern "c" fn fchmod(fd: c_int, mode: c_uint) c_int;
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
pub extern "c" fn getpgid(pid: c_int) c_int;
extern "c" fn setsid() c_int;
extern "c" fn getsid(pid: c_int) c_int;
pub extern "c" fn getentropy(buf: [*]u8, len: usize) c_int;
pub extern "c" fn getppid() c_int;
pub extern "c" fn fork() c_int;
pub extern "c" fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) c_int;
/// The oracle is the one reader that has to be told separately: it resolves the subject's
/// relative paths from a trace, after the fact, so the engine hands it the same directory
/// it handed this call (`src/main.zig`, the recording run's parse site). The shim needs no
/// telling — it reads the cwd inside the child.
pub extern "c" fn chdir(path: [*:0]const u8) c_int;
pub extern "c" fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) c_int;
pub extern "c" fn waitpid(pid: c_int, status: ?*c_int, options: c_int) c_int;
pub extern "c" fn setpgid(pid: c_int, pgid: c_int) c_int;
pub extern "c" fn kill(pid: c_int, sig: c_int) c_int;
pub extern "c" fn waitid(idtype: c_int, id: c_int, infop: *anyopaque, options: c_int) c_int;
pub extern "c" fn clock_gettime(clockid: c_int, tp: *std.c.timespec) c_int;
pub extern "c" fn nanosleep(req: *const std.c.timespec, rem: ?*std.c.timespec) c_int;
pub extern "c" fn signal(sig: c_int, handler: usize) usize;
pub extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub extern "c" fn unsetenv(name: [*:0]const u8) c_int;
pub extern "c" fn getenv(name: [*:0]const u8) ?[*:0]u8;
pub extern "c" fn isatty(fd: c_int) c_int;
pub extern "c" fn _exit(status: c_int) noreturn;
pub extern "c" fn abort() noreturn;
pub extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;
pub extern "c" fn _NSGetExecutablePath(buf: [*]u8, bufsize: *u32) c_int;
pub extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
pub extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
pub extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;

pub const X_OK: c_int = 1;
pub const F_OK: c_int = 0;

/// The only signal in play. Cannot be caught, which is the point: a target that could
/// decline to die would make the crash point a request rather than a fact.
pub const SIGKILL: u8 = 9;
pub const SIGINT: u8 = 2;

pub const P_PID: c_int = 1;
pub const WEXITED: c_int = 4;
pub const WNOWAIT: c_int = if (builtin.os.tag == .linux) 0x01000000 else 0x00000020;
pub const WNOHANG: c_int = 1;
pub const CLOCK_MONOTONIC: c_int = if (builtin.os.tag == .linux) 1 else 6;
pub const SIGCHLD: c_int = if (builtin.os.tag == .linux) 17 else 20;
pub const SIG_DFL: usize = 0;

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
pub const O_RDWR: c_int = 2;
pub const O_CREAT: c_int = if (builtin.os.tag == .linux) 0o100 else 0x200;
pub const O_TRUNC: c_int = if (builtin.os.tag == .linux) 0o1000 else 0x400;
pub const O_EXCL: c_int = if (builtin.os.tag == .linux) 0o200 else 0x800;
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
pub const O_NONBLOCK: c_int = if (builtin.os.tag == .linux) 0o4000 else 0x0004;
/// The value differs *within* Linux by architecture — 0o400000 on x86_64, 0o100000 on
/// aarch64 — so the `os.tag == .linux` shape every neighbour above uses cannot express
/// it. This declaration carried the x86_64 number for all of Linux, which left the one
/// guard that used it inert on arm64: measured in an arm64 container, a symlink planted
/// at a capture path was opened straight through. The comment at the top of this block
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

pub const O_NOCTTY: c_int = blk: {
    var f: std.posix.O = .{};
    f.NOCTTY = true;
    break :blk @bitCast(f);
};

pub const AT_FDCWD: c_int = std.posix.AT.FDCWD;
pub const AT_REMOVEDIR: c_int = std.posix.AT.REMOVEDIR;

/// else it can see falls to one loud default. `ELOOP` is 40 on Linux and 62 on Darwin, so
/// it cannot be written out the way `EINTR` and `ENOENT` above are; `ENOTDIR` agrees
pub const ELOOP: c_int = @intFromEnum(std.posix.E.LOOP);
pub const EACCES: c_int = @intFromEnum(std.posix.E.ACCES);
pub const EPERM: c_int = @intFromEnum(std.posix.E.PERM);
pub const EIO: c_int = @intFromEnum(std.posix.E.IO);
pub const EEXIST: c_int = @intFromEnum(std.posix.E.EXIST);
pub const ENOTDIR: c_int = @intFromEnum(std.posix.E.NOTDIR);
/// Taken from `std.posix.E` for the same reason as its two neighbours, and with more at
/// stake: this one differs **between operating systems** — 11 on Linux, 35 on Darwin —
/// and it is compared against, not passed in. A wrong value here does not fail loudly;
/// it makes "the peer has not written yet" unrecognisable, so the reader treats it as
/// unreadable and refuses a config that was about to arrive. Every other test stays
/// green while it does that.
pub const EAGAIN: c_int = @intFromEnum(std.posix.E.AGAIN);
pub const ENOLCK: c_int = @intFromEnum(std.posix.E.NOLCK);
pub const EOPNOTSUPP: c_int = @intFromEnum(std.posix.E.OPNOTSUPP);
pub const EBADF: c_int = @intFromEnum(std.posix.E.BADF);

pub const LOCK_EX: c_int = 2;
pub const LOCK_NB: c_int = 4;

pub const DT_UNKNOWN: u8 = 0;
pub const DT_DIR: u8 = 4;
pub const DT_REG: u8 = 8;
pub const DT_LNK: u8 = 10;

/// `readlink` on a non-link fails with EINVAL, which is the cheapest way to ask this
/// question without a `stat` struct. It matters for deletion: `opendir` follows links,
/// so treating "can be opened as a directory" as "is a directory" would let a link
/// inside the state directory redirect a recursive delete outside of it.
pub fn isSymlink(path: [*:0]const u8) bool {
    var buf: [1]u8 = undefined;
    return readlink(path, &buf, buf.len) >= 0;
}

pub const Kind = enum { file, dir, symlink, other, missing };

pub fn kindFromDirent(e: *Dirent) Kind {
    return switch (e.type) {
        DT_DIR => .dir,
        DT_REG => .file,
        DT_LNK => .symlink,
        DT_UNKNOWN => .missing, // "ask again a different way"
        else => .other,
    };
}

pub fn isDirPath(path: [*:0]const u8) bool {
    const d = opendir(path) orelse return false;
    _ = closedir(d);
    return true;
}

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

/// One `lstat` rather than two calls, because the two answers are asked together: the shim
/// search refuses a candidate that is a link **or** that someone else owns, and taking the
/// kind from one syscall and the owner from another would let the file change identity
/// between them — the shape #338 closed elsewhere in this codebase.
///
/// **`mask.UID` is checked on Linux, and not checking it is how this guard would fail
/// open.** `statx` fills only what the mask grants, and an unfilled `uid` reads as 0 — the
/// one value that means "root owns it", which is a value the caller *accepts*. The same
/// gate is on `kindAtNoFollow`'s `TYPE` and `identityOfPath`'s `INO`, for the reason std's
/// own contract gives: "Callers must check this field since support varies by kernel
/// version and filesystem."
/// `uid` is optional because `.missing` has no owner, and the value that would otherwise
/// stand in for one is 0 — which is *root*, an owner the shim search accepts. A caller who
/// grew a use for the uid on a path that is not there would inherit an accept, silently.
pub const OwnedKind = struct { kind: Kind, uid: ?u32 };

pub fn ownedKindNoFollow(path: [*:0]const u8) ClassifyError!OwnedKind {
    return statNoFollow(AT_FDCWD, path, true);
}

/// The one place a `stat` is turned into a `Kind`, shared by the walk's classifier and by
/// the shim search. `want_uid` is what differs and the only thing that differs: on Linux it
/// adds `UID` to the `statx` mask and gates on it, which the walk must not do — a
/// filesystem that answers `TYPE` and not `UID` would start failing every entry it walks,
/// to serve a search of two candidates.
fn statNoFollow(dirfd_: c_int, path: [*:0]const u8, want_uid: bool) ClassifyError!OwnedKind {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const mask: lnx.STATX = if (want_uid) .{ .TYPE = true, .UID = true } else .{ .TYPE = true };
        const rc = lnx.statx(@intCast(dirfd_), path, lnx.AT.SYMLINK_NOFOLLOW, mask, &stx);
        switch (lnx.errno(rc)) {
            .SUCCESS => {},
            .NOENT => return .{ .kind = .missing, .uid = null },
            else => return error.Unclassifiable,
        }
        // std's own contract: "Callers must check this field since support varies by
        // kernel version and filesystem." A mode the kernel never filled in is not a
        // classification, and an unfilled uid reads as 0 — which is root, an owner the
        // shim search *accepts*, so leaving that ungated is how the guard fails open.
        if (!stx.mask.TYPE) return error.Unclassifiable;
        if (want_uid and !stx.mask.UID) return error.Unclassifiable;
        const m: u32 = stx.mode;
        const k: Kind = if (lnx.S.ISLNK(m)) .symlink else if (lnx.S.ISDIR(m)) .dir else if (lnx.S.ISREG(m)) .file else .other;
        return .{ .kind = k, .uid = if (want_uid) stx.uid else null };
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstatat(@intCast(dirfd_), path, &st, std.c.AT.SYMLINK_NOFOLLOW) != 0) {
            if (std.c._errno().* == ENOENT) return .{ .kind = .missing, .uid = null };
            return error.Unclassifiable;
        }
        const m = st.mode;
        const k: Kind = if (std.c.S.ISLNK(m)) .symlink else if (std.c.S.ISDIR(m)) .dir else if (std.c.S.ISREG(m)) .file else .other;
        return .{ .kind = k, .uid = if (want_uid) st.uid else null };
    }
}

pub fn isExecutableRegular(path: [*:0]const u8) bool {
    if (access(path, X_OK) != 0) return false;
    return isRegularFollowing(path);
}

pub fn isRegularFollowing(path: [*:0]const u8) bool {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        if (lnx.errno(lnx.statx(AT_FDCWD, path, 0, .{ .TYPE = true }, &stx)) != .SUCCESS) return false;
        if (!stx.mask.TYPE) return false;
        return lnx.S.ISREG(stx.mode);
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstatat(AT_FDCWD, path, &st, 0) != 0) return false;
        return std.c.S.ISREG(st.mode);
    }
}

/// A `false` here is not the only way the mode can be unavailable — a process the target
/// spawns under different privileges can still fail to install one — so the shim
/// announces its own result too and the engine checks both. This is the cheap half that
/// catches the ordinary case (no `CONFIG_SECCOMP_FILTER`) before anything runs.
pub fn seccompTrapAvailable() bool {
    if (builtin.os.tag != .linux) return false;
    const lnx = std.os.linux;
    var action: u32 = lnx.SECCOMP.RET.TRAP;
    const rc = lnx.syscall3(
        .seccomp,
        lnx.SECCOMP.GET_ACTION_AVAIL,
        0,
        @intFromPtr(&action),
    );
    return lnx.errno(rc) == .SUCCESS;
}

pub fn geteuid() u32 {
    return @intCast(std.c.geteuid());
}

/// **`path` must be a bare entry name.** An absolute path makes `dirfd` irrelevant on both
/// platforms — silently, with no error — which would leave the walk resolving names the
/// descriptor was opened to pin. The one caller passes a name straight out of `readdir`.
///
/// This is the fd-relative form the walk needs, and deliberately not an `openat` probe:
/// `opendir` passes `O_NONBLOCK`, a hand-rolled open does not, and #5 recorded what that
/// costs — "a FIFO with no writer blocks that open forever" is why the open-probe was
/// retired from this file in the first place.
pub fn kindAtNoFollow(dirfd_: c_int, path: [*:0]const u8) ClassifyError!Kind {
    return (try statNoFollow(dirfd_, path, false)).kind;
}

/// A reader that opened with `O_NONBLOCK` needs this: the flag stops the open from
/// waiting on a FIFO's peer, but the read that follows then returns 0, which is
/// indistinguishable from an empty regular file. Measured on macOS with a real FIFO and
/// no writer: `open` succeeds, `fstat` says `S_IFIFO`, `lseek` fails with ESPIPE, and
/// `read` returns 0 with errno untouched. `lseek` failing is **not** the test to write
/// instead — seekability and regular-file-ness are different properties, and a device
/// that seeks would pass a test built on it.
pub fn kindOfFd(fd: c_int) ClassifyError!Kind {
    return (try kindModeOfFd(fd)).kind;
}

/// The read, write and execute bits: what `restore` carries (ADR 0109). Not set-id or sticky —
/// a set-group-ID bit for a group the user is not in is dropped or refused, by platform.
pub const perm_bits: u16 = 0o777;

/// A kind and, where the kernel filled them in, permission bits, from one call. `mode` is null,
/// never 0, when `statx` did not grant `MODE` — `restore` would apply a 0.
pub const KindMode = struct { kind: Kind, mode: ?u16 };

pub fn kindModeOfFd(fd: c_int) ClassifyError!KindMode {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(fd, "", lnx.AT.EMPTY_PATH, .{ .TYPE = true, .MODE = true }, &stx);
        switch (lnx.errno(rc)) {
            .SUCCESS => {},
            else => return error.Unclassifiable,
        }
        if (!stx.mask.TYPE) return error.Unclassifiable;
        const m: u32 = stx.mode;
        const mode: ?u16 = if (stx.mask.MODE) @intCast(m & perm_bits) else null;
        if (lnx.S.ISDIR(m)) return .{ .kind = .dir, .mode = mode };
        if (lnx.S.ISREG(m)) return .{ .kind = .file, .mode = mode };
        return .{ .kind = .other, .mode = mode };
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) return error.Unclassifiable;
        const m = st.mode;
        const mode: ?u16 = @intCast(m & perm_bits);
        if (std.c.S.ISDIR(m)) return .{ .kind = .dir, .mode = mode };
        if (std.c.S.ISREG(m)) return .{ .kind = .file, .mode = mode };
        return .{ .kind = .other, .mode = mode };
    }
}

/// The kind and permission bits of `path` without following its last component; null when they
/// could not be read. Check the kind before using the bits: a name swapped for a link reads as
/// the link, whose bits are 0777.
pub fn kindModeOfPathNoFollow(path: [*:0]const u8) ?KindMode {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(AT_FDCWD, path, lnx.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true, .MODE = true }, &stx);
        if (lnx.errno(rc) != .SUCCESS or !stx.mask.TYPE) return null;
        const m: u32 = stx.mode;
        const k: Kind = if (lnx.S.ISLNK(m)) .symlink else if (lnx.S.ISDIR(m)) .dir else if (lnx.S.ISREG(m)) .file else .other;
        return .{ .kind = k, .mode = if (stx.mask.MODE) @intCast(m & perm_bits) else null };
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstatat(AT_FDCWD, path, &st, std.c.AT.SYMLINK_NOFOLLOW) != 0) return null;
        const m = st.mode;
        const k: Kind = if (std.c.S.ISLNK(m)) .symlink else if (std.c.S.ISDIR(m)) .dir else if (std.c.S.ISREG(m)) .file else .other;
        return .{ .kind = k, .mode = @intCast(m & perm_bits) };
    }
}

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

/// Asked of the descriptor, not the name: `O_NOFOLLOW` stops a symlink and nothing else, and a
/// hard link or a FIFO planted at the name would have its target truncated or block the reader.
pub fn isSoleRegularFile(fd: c_int, owned_by_caller: bool) bool {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
        const rc = lnx.statx(fd, "", lnx.AT.EMPTY_PATH, .{ .TYPE = true, .UID = true, .NLINK = true }, &stx);
        if (lnx.errno(rc) != .SUCCESS) return false;
        if (!stx.mask.TYPE or !stx.mask.UID or !stx.mask.NLINK) return false;
        return lnx.S.ISREG(stx.mode) and stx.nlink == 1 and (!owned_by_caller or stx.uid == geteuid());
    } else {
        var st: std.c.Stat = undefined;
        if (std.c.fstat(fd, &st) != 0) return false;
        return std.c.S.ISREG(st.mode) and st.nlink == 1 and (!owned_by_caller or st.uid == geteuid());
    }
}

pub fn identityOfFd(fd: c_int) IdentityError!Identity {
    if (builtin.os.tag == .linux) {
        const lnx = std.os.linux;
        var stx: lnx.Statx = undefined;
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

pub extern "c" fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;

pub extern "c" fn pipe(fds: *[2]c_int) c_int;

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
    if (s & 0x7f == 0) return .{ .exited = @intCast((s >> 8) & 0xff) };
    if ((s & 0x7f) + 1 >= 2) {
        const sig: u8 = @intCast(s & 0x7f);
        if (sig != 0x7f) return .{ .signaled = sig };
    }
    return .{ .unknown = status };
}

pub const SpawnError = error{ ForkFailed, OutOfMemory, WaitFailed, StdinUnavailable, CaptureUnavailable };

pub const ContainedSpawnError = SpawnError || error{CgroupJoinFailed};

pub const Capture = struct {
    /// Resolved against the ENGINE's working directory, not the child's: this open now
    /// happens in the parent, and it happened before `chdir` even when it lived in the
    /// child (see `runChildImplWithOps`). Every production path passes an absolute path.
    path: []const u8,

    /// Send the child's stderr to the same file. The falsification gate uses this (#134):
    /// its child's output must not reach the transcript unlabeled, and a checker reports
    /// through both streams — the target's own stderr passes through the checker's — so
    /// capturing stdout alone would still leak the exact line class that was once
    /// harvested as world evidence.
    stderr_too: bool = false,

    /// `O_NOFOLLOW` is unconditional below and covers a *symlink* at the name. It does
    /// nothing about a **hard link**, which is the same file rather than a pointer to
    /// one — so a work directory an attacker reached can still turn a capture into an
    /// arbitrary-file truncation with `O_NOFOLLOW` set. `O_EXCL` covers that, and it is
    /// free wherever the caller unlinks the path first, which every work-directory
    /// capture does.
    /// Not set for a capture to `/dev/null` — the device already exists, so
    /// `O_CREAT|O_EXCL` there refuses every time.
    ///
    /// **A work-directory capture added later must set it, for a second reason.** Since
    /// #469 this open happens in the parent, before the fork, where no budget reaches:
    /// a FIFO planted at a non-exclusive capture path would block `O_WRONLY` until a
    /// reader arrived, and the run would hang with nothing to time it out. `O_EXCL`
    /// refuses a FIFO along with everything else already at the name. The two captures
    /// without it today go to `/dev/null`, which nobody but root can replace.
    exclusive: bool = false,
};

fn captureFlags(exclusive: bool) c_int {
    const base: c_int = O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW;
    return if (exclusive) base | O_EXCL else base;
}

/// The variables are applied in the child after `fork`, so the engine's own environment
/// stays clean across worlds — otherwise `SIDEEYE_KILL_AT` from world k would leak into
/// world k+1 and every subsequent run would die at the wrong place.
/// **The signal has to be sent before the child is reaped**, which is why `waitid` appears
/// here at all. `kill(-N, …)` addresses the process group whose id is N, and N is the
/// child's pid. That id is safe to signal only while it is still spoken for: POSIX keeps a
/// pid out of circulation until the process lifetime ends, and a process that has exited
/// but not been waited for is still alive in that sense, still a member of its group, and
/// still holding the group id. Reap first and both become reusable — an unrelated process
/// could be allocated that pid, become a group leader, and receive a `SIGKILL` meant for
/// something that no longer exists.
/// What this does **not** establish is that no descendant remains. A grandchild is
/// reparented away when its parent dies, so it is not this process's child to wait for —
/// `waitpid` returning `ECHILD` says nothing about it. The group signal is the strongest
/// thing available here; confirming the state directory has actually stopped moving is a
/// separate step, and it is an observation rather than a proof.
pub fn runChild(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, null, false, cwd, .kill);
}

pub fn runChildCapture(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    cap: Capture,
    cwd: ?[]const u8,
) SpawnError!Term {
    return runChildImpl(gpa, argv, env_pairs, cap, false, cwd, .kill);
}

pub fn runChildCaptureContained(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    cap: Capture,
    cwd: ?[]const u8,
    cg: ?*CgroupSpawn,
) ContainedSpawnError!Term {
    return runChildImplWithOps(gpa, argv, env_pairs, cap, false, null, cwd, cg, .kill, RealOps) catch |e| switch (e) {
        error.TimedOut => unreachable,
        error.ForkFailed, error.OutOfMemory, error.WaitFailed, error.StdinUnavailable, error.CaptureUnavailable, error.CgroupJoinFailed => |narrow| narrow,
    };
}

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
    cap: Capture,
    budget_ms: ?u64,
    cwd: ?[]const u8,
    cg: ?*CgroupSpawn,
) (ContainedSpawnError || error{TimedOut})!Term {
    return runChildImplWithOps(gpa, argv, env_pairs, cap, false, budget_ms, cwd, cg, .kill, RealOps);
}

pub fn runChildCaptureMinimalEnv(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    cap: Capture,
) SpawnError!Term {
    // No `cwd` parameter, and `null` here rather than a pass-through: this child is the
    // engine re-executing itself, and the engine's own cwd is what `--work`, `--json` and
    // the oracle's path resolution are all read against. A define's `cwd` is applied one
    // level down, by that engine, to the commands it runs.
    return runChildImpl(gpa, argv, env_pairs, cap, true, null, .forward);
}

/// kernel refused (`getentropy` fails only on EFAULT, EIO or a kernel without it). Used
/// for the fs_usage sentinels' names (#549): a name a target can derive from its parent's
/// pid is a name it can forge a capture line for, and eight bytes it never sees is not.
pub fn randomHex(out: *[16]u8) ?[]const u8 {
    var raw: [8]u8 = undefined;
    if (getentropy(&raw, raw.len) != 0) return null;
    const digits = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        out[2 * i] = digits[b >> 4];
        out[2 * i + 1] = digits[b & 0x0f];
    }
    return out[0..];
}

test "randomHex: sixteen lowercase hex digits, and two draws differ" {
    var a: [16]u8 = undefined;
    var b: [16]u8 = undefined;
    const ha = randomHex(&a) orelse return error.TestUnexpectedResult;
    const hb = randomHex(&b) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 16), ha.len);
    for (ha) |c| try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    try std.testing.expect(!std.mem.eql(u8, ha, hb));
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
    if (!dup2Bounded(dup2, nfd, 0)) {
        childArrangeNote("dup2(stdin, 0)");
        abort();
    }
    _ = close(nfd);
}

/// `dup2` under the same nine-attempt `EINTR` bound `adoptStdin` has carried since #263,
/// for every `dup2` the child issues before `exec`. macOS documents `EINTR` for
/// `dup2(2)`; the stdin call retried it and the capture call three lines later did not,
/// so a signal landing between the two was an exit 126 with nothing to say which call.
fn dup2Bounded(dup2_fn: anytype, old_fd: c_int, new_fd: c_int) bool {
    var tries: u32 = 0;
    while (dup2_fn(old_fd, new_fd) < 0) {
        tries += 1;
        if (std.c._errno().* != EINTR or tries >= 9) return false;
    }
    return true;
}

/// Child side, after `fork` and before `exec`: a call the child needs before it can run
/// has failed. Say which one, and with what errno, on fd 2 — still the engine's own
/// stderr at this point, because nothing has been redirected yet — and exit 126, the
/// code this path keeps for "the child could not be arranged". One stack buffer and one
/// `write`, no allocation, no lock: this runs where `adoptStdin` runs. Written on
fn childArrangeFailed(what: []const u8) noreturn {
    childArrangeNote(what);
    _exit(126);
}

/// **The invariant is the group, not the call** (#629). The child must not `exec` while it
/// still shares the engine's group — the shim's crash point kills `kill(0, SIGKILL)`, the
/// caller's whole group, so a target left in the engine's group could take the exploration
/// down with it. `setpgid(0, 0)` is how the child gets there; it is not the only way it can
/// arrive, and this side used to read any non-zero return as "it did not".
fn childEnterOwnGroup() void {
    childEnterOwnGroupWith(setpgid, setsid);
}

fn childEnterOwnGroupWith(setpgid_fn: anytype, setsid_fn: anytype) void {
    if (setpgid_fn(0, 0) == 0) return;
    const err = std.c._errno().*; // read before `getpgid`: a successful call may write errno
    const pid = getpid();
    const group = getpgid(0);
    if (group == pid) {
        var kept: [160]u8 = undefined;
        writeNoteLine(fmtChildGroupKeptNote(&kept, err, pid, getsid(0)));
        return;
    }
    // names a group, and grants a session — and with it a group of its own — otherwise. What
    // the `exec` depends on is the group `getpgid` reports, and every branch below asks for it.
    const setsid_rc = setsid_fn();
    const setsid_err = std.c._errno().*; // read at once: the `getpgid` and `getsid` below may write it
    const now_group = getpgid(0);
    if (now_group == pid) {
        if (setsid_rc >= 0) {
            var left: [160]u8 = undefined;
            writeNoteLine(fmtChildLeftBySetsidNote(&left, err, pid, group));
            return;
        }
        var kept: [192]u8 = undefined;
        writeNoteLine(fmtChildKeptAfterSetsidRefusedNote(&kept, err, setsid_err, pid, getsid(0)));
        return;
    }
    var buf: [128]u8 = undefined; // the bound both exits below are sized to
    if (setsid_rc >= 0) {
        const what = fmtChildSetsidWithoutGroupWhat(&buf, pid, now_group, getsid(0));
        std.c._errno().* = err; // the note's errno is the refused call's, not `getpgid`'s
        childArrangeFailed(what);
    }
    const what = fmtChildBothRefusedWhat(&buf, pid, now_group, getsid(0), err);
    std.c._errno().* = setsid_err;
    childArrangeFailed(what);
}

/// bound as the `dup2`s. Anything else the `write` answers — a reader that is gone
/// (`EPIPE`; with `SIGPIPE` at its default the child dies of that instead), a short
/// write — ends the attempt: the line is worth less than the exit it precedes, so it
/// is never retried past the bound and never waits on anything but the kernel.
fn childArrangeNote(what: []const u8) void {
    // 224: the sentence's own 54 bytes, the longest `what` this file builds (the 128-byte
    // bound on `fmtChildBothRefusedWhat`'s buffer) and the errno tail (` failed, errno ` 15,
    // a `c_int` at its widest 11, the newline), which is 209.
    var buf: [224]u8 = undefined;
    writeNoteLine(fmtChildArrangeNote(&buf, what, std.c._errno().*));
}

/// **One sentence above does not carry over to the surviving note.** "The line is worth less
/// than the exit it precedes" holds for a child that is about to die; the #629 note precedes
/// an `exec`. What the two share is the bound; what the surviving caller inherits is a
/// dependency on fd 2 — `SIGPIPE` keeps its default here, so a stderr that is a pipe with no
/// reader ends a child that was about to run. The engine's own stderr is a terminal, a file
/// or a CI log in every path that reaches here, and the target inherits the same fd a moment
/// later, so this adds a failure mode to a rare branch rather than a new class of one.
fn writeNoteLine(line: []const u8) void {
    var tries: u32 = 0;
    while (write(2, line.ptr, line.len) < 0) {
        tries += 1;
        if (std.c._errno().* != EINTR or tries >= 9) return;
    }
}

fn fmtChildArrangeNote(buf: []u8, what: []const u8, err: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "sideeye: the child could not be arranged before exec: {s} failed, errno {d}\n", .{ what, err }) catch "sideeye: the child could not be arranged before exec\n";
}

/// swapped pair would read as correct. Its buffer is 128: the fixed text is 66 bytes and four
/// `c_int`s at their widest 44, which is 110.
fn fmtChildBothRefusedWhat(buf: []u8, pid: c_int, group: c_int, sid: c_int, setpgid_err: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "setpgid(0, 0) (pid {d}, group {d}, session {d}) failed, errno {d}, then setsid", .{ pid, group, sid, setpgid_err }) catch "setpgid(0, 0) then setsid";
}

/// errno, the one refusal that happened. Its buffer is 128: the fixed text is 86 bytes and
/// three `c_int`s at their widest 33, which is 119.
fn fmtChildSetsidWithoutGroupWhat(buf: []u8, pid: c_int, group: c_int, sid: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "setpgid(0, 0) (pid {d}, group {d}, session {d}; setsid answered 0 and the group did not follow)", .{ pid, group, sid }) catch "setpgid(0, 0) (setsid answered 0 and the group did not follow)";
}

fn fmtChildLeftBySetsidNote(buf: []u8, err: c_int, pid: c_int, was_group: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "sideeye: setpgid(0, 0) failed, errno {d}, so the child left group {d} with setsid and now leads its own (pid {d}); continuing\n", .{ err, was_group, pid }) catch "sideeye: setpgid(0, 0) failed and the child left the engine's group with setsid\n";
}

fn fmtChildGroupKeptNote(buf: []u8, err: c_int, pid: c_int, sid: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "sideeye: setpgid(0, 0) failed, errno {d}, but the child already leads its own group (pid {d}, session {d}); continuing\n", .{ err, pid, sid }) catch "sideeye: setpgid(0, 0) failed and the child already leads its own group\n";
}

/// go through, so this world keeps its controlling terminal, unlike the #632 branch. Opens the
/// way the other two surviving notes do, which is what `spike/thread-kill-lands.sh` counts by.
/// Its buffer is 192: the fixed text is 138 bytes and four `c_int`s at their widest 44, which
/// is 182 — the 160 the other notes use would not hold it, and a note that does not fit falls
/// back to a sentence without its numbers.
fn fmtChildKeptAfterSetsidRefusedNote(buf: []u8, err: c_int, setsid_err: c_int, pid: c_int, sid: c_int) []const u8 {
    return std.fmt.bufPrint(buf, "sideeye: setpgid(0, 0) failed, errno {d}, then setsid failed, errno {d}, but the child leads its own group by then (pid {d}, session {d}); continuing\n", .{ err, setsid_err, pid, sid }) catch "sideeye: setpgid(0, 0) failed, then setsid failed, but the child leads its own group by then; continuing\n";
}

test "dup2Bounded retries EINTR up to nine times and returns any other failure at once" {
    const Fake = struct {
        var calls: u32 = 0;
        var fail_eintr: u32 = 0; // how many leading calls fail with EINTR
        var fail_other: bool = false; // the first call fails with a non-EINTR errno
        fn dup2(_: c_int, _: c_int) c_int {
            calls += 1;
            if (fail_other) {
                std.c._errno().* = ENOENT;
                return -1;
            }
            if (calls <= fail_eintr) {
                std.c._errno().* = EINTR;
                return -1;
            }
            return 0;
        }
    };
    Fake.calls = 0;
    Fake.fail_eintr = 3;
    Fake.fail_other = false;
    try std.testing.expect(dup2Bounded(Fake.dup2, 5, 1));
    try std.testing.expectEqual(@as(u32, 4), Fake.calls);
    Fake.calls = 0;
    Fake.fail_eintr = 1000;
    try std.testing.expect(!dup2Bounded(Fake.dup2, 5, 1));
    try std.testing.expectEqual(@as(u32, 9), Fake.calls);
    Fake.calls = 0;
    Fake.fail_eintr = 0;
    Fake.fail_other = true;
    try std.testing.expect(!dup2Bounded(Fake.dup2, 5, 1));
    try std.testing.expectEqual(@as(u32, 1), Fake.calls);
}

test "the child's arrangement note names the call and the errno, on one line" {
    var buf: [160]u8 = undefined;
    const line = fmtChildArrangeNote(&buf, "dup2(capture, 1)", 4);
    try std.testing.expectEqualStrings("sideeye: the child could not be arranged before exec: dup2(capture, 1) failed, errno 4\n", line);
    var tiny: [8]u8 = undefined;
    const fallback = fmtChildArrangeNote(&tiny, "setpgid(0, 0)", 1);
    try std.testing.expect(std.mem.endsWith(u8, fallback, "\n"));
    const kept = fmtChildGroupKeptNote(&buf, 1, 4242, 4242);
    try std.testing.expectEqualStrings("sideeye: setpgid(0, 0) failed, errno 1, but the child already leads its own group (pid 4242, session 4242); continuing\n", kept);
    try std.testing.expect(std.mem.endsWith(u8, fmtChildGroupKeptNote(&tiny, 1, 4242, 4242), "\n"));
    // The third note (#632) names the group left behind — the engine's — and the pid now
    // leading a session of its own, with two distinct numbers so the pair cannot swap unseen.
    try std.testing.expectEqualStrings("sideeye: setpgid(0, 0) failed, errno 1, so the child left group 22 with setsid and now leads its own (pid 11); continuing\n", fmtChildLeftBySetsidNote(&buf, 1, 11, 22));
    try std.testing.expect(std.mem.endsWith(u8, fmtChildLeftBySetsidNote(&tiny, 1, 11, 22), "\n"));
    // The fourth note (#651) carries two errnos in the order the calls were made, then the
    // two ids — four distinct numbers, so no pair can swap unseen — and falls back whole.
    try std.testing.expectEqualStrings("sideeye: setpgid(0, 0) failed, errno 13, then setsid failed, errno 1, but the child leads its own group by then (pid 11, session 22); continuing\n", fmtChildKeptAfterSetsidRefusedNote(&buf, 13, 1, 11, 22));
    try std.testing.expectEqualStrings("sideeye: setpgid(0, 0) failed, then setsid failed, but the child leads its own group by then; continuing\n", fmtChildKeptAfterSetsidRefusedNote(&tiny, 13, 1, 11, 22));
    // The `what` of the exit that both refusals reach (#651): the state, then `setpgid`'s own
    // errno, then the call whose errno the arrangement note appends. Four distinct numbers, so
    // a pair swapped in the format string is a failure here rather than a diagnosis that
    // misnames the state at the one moment it is read; too small, the calls still name
    // themselves rather than nothing.
    try std.testing.expectEqualStrings("setpgid(0, 0) (pid 11, group 22, session 33) failed, errno 44, then setsid", fmtChildBothRefusedWhat(&buf, 11, 22, 33, 44));
    try std.testing.expectEqualStrings("setpgid(0, 0) then setsid", fmtChildBothRefusedWhat(&tiny, 11, 22, 33, 44));
    try std.testing.expectEqualStrings("setpgid(0, 0) (pid 11, group 22, session 33; setsid answered 0 and the group did not follow)", fmtChildSetsidWithoutGroupWhat(&buf, 11, 22, 33));
    try std.testing.expectEqualStrings("setpgid(0, 0) (setsid answered 0 and the group did not follow)", fmtChildSetsidWithoutGroupWhat(&tiny, 11, 22, 33));
}

test "a child refused setsid because it already leads a group of its own runs (#651)" {
    const Fake = struct {
        var setsid_accepted = false;
        fn setpgidRefused(_: c_int, _: c_int) c_int {
            // EACCES, not the EPERM the real `setsid` refusal carries: two different numbers,
            // so the note's order of errnos is a failure here rather than a swapped diagnosis.
            std.c._errno().* = 13;
            return -1;
        }
        fn setsidRefused() c_int {
            if (setpgid(0, 0) != 0) _exit(14); // the stand-in for the parent's rescue did not land: nothing below is the state under test
            const rc = setsid();
            if (rc == 0) setsid_accepted = true; // the kernel let a group leader start a session: the branch under test was never reached
            return rc;
        }
    };
    var fds: [2]c_int = undefined;
    try std.testing.expect(pipe(&fds) == 0);
    const parent_sid = getsid(0);
    const pid = fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) {
        _ = close(fds[0]);
        if (dup2(fds[1], 2) < 0) _exit(10);
        childEnterOwnGroupWith(Fake.setpgidRefused, Fake.setsidRefused);
        if (Fake.setsid_accepted) _exit(13);
        if (getsid(0) == getpid()) _exit(12); // a session of its own means `setsid` went through: not this branch
        if (getpgid(0) != getpid()) _exit(11); // the invariant, asked of the kernel
        _exit(7);
    }
    _ = close(fds[1]);
    var buf: [256]u8 = undefined;
    const n = read(fds[0], &buf, buf.len);
    _ = close(fds[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    try std.testing.expectEqual(Term{ .exited = 7 }, decodeStatus(status));
    try std.testing.expect(n > 0);
    var expect: [224]u8 = undefined;
    const line = try std.fmt.bufPrint(&expect, "sideeye: setpgid(0, 0) failed, errno 13, then setsid failed, errno 1, but the child leads its own group by then (pid {d}, session {d}); continuing\n", .{ pid, parent_sid });
    try std.testing.expectEqualStrings(line, buf[0..@intCast(n)]);
}

test "a child the kernel will not move out of the engine's group leaves it with setsid (#632)" {
    const Fake = struct {
        fn setpgid(_: c_int, _: c_int) c_int {
            std.c._errno().* = 1; // EPERM, the errno all five CI occurrences carried
            return -1;
        }
    };
    var fds: [2]c_int = undefined;
    try std.testing.expect(pipe(&fds) == 0);
    const parent_group = getpgid(0);
    const pid = fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) {
        _ = close(fds[0]);
        if (dup2(fds[1], 2) < 0) _exit(10);
        // No guard for "already leads its own group" here: `fork` may not hand this child a
        // pid matching an active group id (POSIX), so it cannot be leading one. The check
        // this test rests on is the `_exit(12)` below, which asks the kernel afterwards.
        childEnterOwnGroupWith(Fake.setpgid, setsid);
        if (getpgid(0) != getpid()) _exit(12);
        _exit(7);
    }
    _ = close(fds[1]);
    var buf: [256]u8 = undefined;
    const n = read(fds[0], &buf, buf.len);
    _ = close(fds[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    try std.testing.expectEqual(Term{ .exited = 7 }, decodeStatus(status));
    try std.testing.expect(n > 0);
    const note = buf[0..@intCast(n)];
    var expect: [160]u8 = undefined;
    const said = try std.fmt.bufPrint(&expect, "errno 1, so the child left group {d} with setsid and now leads its own (pid {d})", .{ parent_group, pid });
    try std.testing.expect(std.mem.indexOf(u8, note, said) != null);
}

test "a child that can leave the engine's group by neither call exits 126, naming both refusals (#629, #632, #651)" {
    const Fake = struct {
        fn setpgid(_: c_int, _: c_int) c_int {
            std.c._errno().* = 1; // EPERM
            return -1;
        }
        fn setsid() c_int {
            // A different errno from the `setpgid` fake on purpose: the note carries each
            // call's errno in its own place — `setpgid`'s inside the `what`, `setsid`'s on the
            // tail — and the whole line is compared, so a swap or a drop fails here rather
            // than passing as a diagnosis that misnames the call.
            std.c._errno().* = 13; // EACCES
            return -1;
        }
    };
    var fds: [2]c_int = undefined;
    try std.testing.expect(pipe(&fds) == 0);
    const parent_group = getpgid(0);
    const pid = fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) {
        _ = close(fds[0]);
        if (dup2(fds[1], 2) < 0) _exit(10);
        childEnterOwnGroupWith(Fake.setpgid, Fake.setsid);
        _exit(7); // reached only if the refusal was swallowed
    }
    _ = close(fds[1]);
    var buf: [256]u8 = undefined;
    const n = read(fds[0], &buf, buf.len);
    _ = close(fds[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    try std.testing.expectEqual(Term{ .exited = 126 }, decodeStatus(status));
    try std.testing.expect(n > 0);
    // The whole line, not a substring: `errno 1` is a substring of `errno 13`, so a search
    // for the first would pass with the second in its place (review of the #651 plan). The
    // group is the parent's, read again after the second refusal, and the session is the one
    // both processes share.
    var expect: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&expect, "sideeye: the child could not be arranged before exec: setpgid(0, 0) (pid {d}, group {d}, session {d}) failed, errno 1, then setsid failed, errno 13\n", .{ pid, parent_group, getsid(0) });
    try std.testing.expectEqualStrings(line, buf[0..@intCast(n)]);
}

test "a child that already leads its own group runs, and says so, when setpgid(0, 0) is refused (#629)" {
    // The refusal is the kernel's own. `man 2 setpgid` allows a self-call exactly one
    // EPERM — "the process indicated by the pid argument is a session leader" — so a child
    // that has called `setsid` reaches the real refusal, with no fake in the path to make
    // the test true by construction. Such a child also leads a group of its own, which is
    var fds: [2]c_int = undefined;
    try std.testing.expect(pipe(&fds) == 0);
    const pid = fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) {
        _ = close(fds[0]);
        if (dup2(fds[1], 2) < 0) _exit(10); // the note is what this test reads
        if (setsid() < 0) _exit(11);
        // Vacuity guard: if this kernel accepts the call, the test never reaches the
        // branch it is about, and says so with a code of its own instead of passing.
        if (setpgid(0, 0) == 0) _exit(12);
        childEnterOwnGroup();
        _exit(7);
    }
    _ = close(fds[1]);
    var buf: [256]u8 = undefined;
    const n = read(fds[0], &buf, buf.len);
    _ = close(fds[0]);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    try std.testing.expectEqual(Term{ .exited = 7 }, decodeStatus(status));
    try std.testing.expect(n > 0);
    const note = buf[0..@intCast(n)];
    try std.testing.expect(std.mem.startsWith(u8, note, "sideeye: setpgid(0, 0) failed, errno "));
    try std.testing.expect(std.mem.indexOf(u8, note, "already leads its own group") != null);
}

test "the group the fallback asks for is not one every child already has (#629)" {
    // The contrast for the test above: a child that has arranged nothing is in the
    // ENGINE's group, so `getpgid(0) == getpid()` answers no and the 126 exit is still
    // reachable. Without this, "already leads its own group" could be true of every child
    // and the fix would be a way of never refusing anything.
    const pid = fork();
    try std.testing.expect(pid >= 0);
    if (pid == 0) _exit(if (getpgid(0) == getpid()) 1 else 0);
    var status: c_int = 0;
    _ = waitpid(pid, &status, 0);
    try std.testing.expectEqual(Term{ .exited = 0 }, decodeStatus(status));
}

/// stdout goes to `stdout_path`, opened `O_NOFOLLOW|O_EXCL` regardless of caller:
/// this one runs under `sudo`, so the file it truncates is chosen with root's
/// authority and a pre-planted symlink there is an arbitrary-file overwrite rather
/// than a spoiled capture. The child leaves the engine's process group for the same
/// reason every other spawn does — a terminal SIGINT must not reach it before the
/// caller has read what it captured.
///
/// **The capture is opened here, in the parent, like the stdin below it** (#469). It
/// used to be opened in the child, where a failure could only be `_exit(126)` — and the
/// caller reads this pid back through the fs_usage handshake, whose loop sees the child
/// gone and reports "another fs_usage still holds the kernel trace facility". A blocked
/// capture path came back as a diagnosis about somebody else's process, which is the
/// misattribution class #469 exists to remove; it reaches the caller as
/// `error.CaptureUnavailable` now, and the handshake never sees it.
pub fn spawnSidecar(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    stdout_path: []const u8,
    stderr_path: ?[]const u8,
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
    const nfd = RealOps.openDevNull();
    if (nfd < 0) return error.StdinUnavailable;

    // The same flag expression `runChildImpl*` uses, through the same function, so the
    // two forks in this file cannot answer a planted link differently — which is the
    // whole shape of #469, one level up.
    const cfd = RealOps.openCapture(stdout_z, captureFlags(true));
    if (cfd < 0) {
        _ = close(nfd);
        return error.CaptureUnavailable;
    }
    const efd: c_int = if (stderr_path) |ep| RealOps.openCapture((try arena.dupeZ(u8, ep)).ptr, captureFlags(true)) else -1;
    if (stderr_path != null and efd < 0) {
        _ = close(nfd);
        _ = close(cfd);
        return error.CaptureUnavailable;
    }

    var old_mask: std.c.sigset_t = undefined;
    blockInterrupts(&old_mask);
    const pid = fork();
    if (pid < 0) {
        restoreMask(&old_mask);
        _ = close(nfd);
        _ = close(cfd);
        if (efd >= 0) _ = close(efd);
        return error.ForkFailed;
    }
    if (pid == 0) {
        childRestoreSignals(&old_mask);
        // **A failure here must not be exec'd through** (v15). Since the shim kills the
        // run's crash point with `kill(0, SIGKILL)` — the caller's whole process group,
        // because killing one process leaves the shell that spawned it to run the next
        // command — a target that never got its own group is a target in the ENGINE's
        // group, and that signal would take the exploration with it. The result used to
        childEnterOwnGroup();
        adoptStdin(nfd);
        if (cfd != 1) {
            if (!dup2Bounded(dup2, cfd, 1)) childArrangeFailed("dup2(capture, 1)");
            _ = close(cfd);
        }
        if (efd >= 0 and efd != 2) {
            if (!dup2Bounded(dup2, efd, 2)) childArrangeFailed("dup2(stderr capture, 2)");
            _ = close(efd);
        }
        _ = execvp(cargv[0].?, cargv.ptr);
        _exit(127);
    }
    noteSidecar(pid);
    restoreMask(&old_mask);
    _ = close(nfd);
    _ = close(cfd);
    if (efd >= 0) _ = close(efd);
    return pid;
}

/// The path a descriptor's file has now, through `F_GETPATH`; macOS only, null elsewhere and when
/// the call fails.
pub fn pathOfFd(fd: c_int, buf: *[1024]u8) ?[]const u8 {
    if (comptime builtin.os.tag != .macos) return null;
    if (std.c.fcntl(fd, std.c.F.GETPATH, buf) == -1) return null;
    return std.mem.sliceTo(buf, 0);
}

pub const SidecarEnd = enum { was_running, had_exited, would_not_die };

/// **The signal goes to the process group, and it is SIGINT.** Both were paid for by a
/// measured failure. `spawnSidecar` starts `sudo`, which forks the real observer, so
/// signalling the returned pid reaches the privilege helper and not the process holding
/// the capture. And `fs_usage` buffers its output when stdout is not a terminal: killed
/// on any other signal it dies with the buffer unwritten, leaving a capture that ends
/// cleanly at a flush boundary tens of milliseconds in — which reads exactly like a
/// complete capture of a short window. SIGINT is the disposition that tool is built to
/// handle, since it is meant to be stopped from a terminal.
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
    _ = runChildCapture(gpa, list.items, &.{}, .{ .path = "/dev/null" }, null) catch return;
}

fn runChildImpl(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    capture: ?Capture,
    minimal_env: bool,
    cwd: ?[]const u8,
    stop: ChildStop,
) SpawnError!Term {
    return runChildImplWithOps(gpa, argv, env_pairs, capture, minimal_env, null, cwd, null, stop, RealOps) catch |e| switch (e) {
        error.TimedOut => unreachable,
        error.CgroupJoinFailed => unreachable,
        error.ForkFailed, error.OutOfMemory, error.WaitFailed, error.StdinUnavailable, error.CaptureUnavailable => |narrow| narrow,
    };
}

pub const world_kill_grace_ms: u64 = 5000;

const max_cgroup_path = 1024;

/// cgroup v2 lets a delegated process move others only within its own subtree (the kernel
/// documentation's "Delegation Containment"), so a run's cgroup has to be a child of the one
/// the engine is in. It is offered only when writing the engine's own pid to its own
/// `cgroup.procs` succeeds — the permission check a real move passes, which `access(W_OK)`
/// does not see — and a trial child cgroup carries a `cgroup.kill`.
pub const CgroupHome = struct {
    dir: [:0]const u8,
    rel: []const u8,
};

var cgroup_home_state: enum { unprobed, absent, present } = .unprobed;
var cgroup_home_dir_buf: [max_cgroup_path]u8 = undefined;
var cgroup_home_rel_buf: [max_cgroup_path]u8 = undefined;
var cgroup_home: CgroupHome = undefined;

pub fn cgroupHome() ?CgroupHome {
    switch (cgroup_home_state) {
        .present => return cgroup_home,
        .absent => return null,
        .unprobed => {},
    }
    cgroup_home_state = .absent;
    if (builtin.os.tag != .linux) return null;
    var mbuf: [16 * 1024]u8 = undefined;
    const mount = cgroup2Mount(readSmallFile("/proc/self/mountinfo", &mbuf) orelse return null) orelse return null;
    var cbuf: [4096]u8 = undefined;
    const rel = cgroup2Path(readSmallFile("/proc/self/cgroup", &cbuf) orelse return null) orelse return null;
    if (rel.len == 0 or rel.len >= cgroup_home_rel_buf.len) return null;
    const dir = std.fmt.bufPrintZ(&cgroup_home_dir_buf, "{s}{s}", .{ mount, if (std.mem.eql(u8, rel, "/")) "" else rel }) catch return null;
    var pid_buf: [16]u8 = undefined;
    const pid_s = std.fmt.bufPrint(&pid_buf, "{d}", .{getpid()}) catch return null;
    var procs_buf: [max_cgroup_path + 32]u8 = undefined;
    const procs = std.fmt.bufPrintZ(&procs_buf, "{s}/cgroup.procs", .{dir}) catch return null;
    if (!writeSmallFile(procs.ptr, pid_s)) return null;
    var trial_buf: [max_cgroup_path + 32]u8 = undefined;
    // A random name, for the reason `CgroupSpawn.init` gives: an engine killed between this
    // mkdir and the rmdir leaves the directory behind, and a pid-derived name would meet it.
    var probe_hex: [16]u8 = undefined;
    const probe_tag = randomHex(&probe_hex) orelse return null;
    const trial = std.fmt.bufPrintZ(&trial_buf, "{s}/sideeye-probe-{s}", .{ dir, probe_tag }) catch return null;
    if (mkdir(trial.ptr, 0o755) != 0) return null;
    defer _ = rmdir(trial.ptr);
    var kill_buf: [max_cgroup_path + 64]u8 = undefined;
    const kill_path = std.fmt.bufPrintZ(&kill_buf, "{s}/cgroup.kill", .{trial}) catch return null;
    if (access(kill_path.ptr, F_OK) != 0) return null;
    @memcpy(cgroup_home_rel_buf[0..rel.len], rel);
    cgroup_home = .{ .dir = dir, .rel = cgroup_home_rel_buf[0..rel.len] };
    cgroup_home_state = .present;
    return cgroup_home;
}

fn cgroup2Mount(mountinfo: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, mountinfo, '\n');
    while (lines.next()) |line| {
        const sep = std.mem.indexOf(u8, line, " - ") orelse continue;
        var tail = std.mem.tokenizeScalar(u8, line[sep + 3 ..], ' ');
        const fstype = tail.next() orelse continue;
        if (!std.mem.eql(u8, fstype, "cgroup2")) continue;
        var fields = std.mem.tokenizeScalar(u8, line[0..sep], ' ');
        var i: usize = 0;
        var root: []const u8 = "";
        var point: []const u8 = "";
        while (fields.next()) |f| : (i += 1) {
            if (i == 3) root = f;
            if (i == 4) {
                point = f;
                break;
            }
        }
        if (!std.mem.eql(u8, root, "/") or point.len == 0 or std.mem.indexOfScalar(u8, point, '\\') != null) return null;
        return point;
    }
    return null;
}

fn cgroup2Path(self_cgroup: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, self_cgroup, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "0::")) return line[3..];
    }
    return null;
}

fn readSmallFile(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const fd = open(path, O_RDONLY | O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = close(fd);
    var n: usize = 0;
    while (n < buf.len) {
        const r = read(fd, buf[n..].ptr, buf.len - n);
        if (r < 0) {
            if (std.c._errno().* == EINTR) continue;
            return null;
        }
        if (r == 0) break;
        n += @intCast(r);
    }
    return buf[0..n];
}

fn writeSmallFile(path: [*:0]const u8, bytes: []const u8) bool {
    const fd = open(path, O_WRONLY | O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return false;
    defer _ = close(fd);
    return write(fd, bytes.ptr, bytes.len) == @as(isize, @intCast(bytes.len));
}

pub const CgroupSpawn = struct {
    world: bool,
    dir_buf: [max_cgroup_path + 64]u8 = undefined,
    dir_len: usize = 0,
    rel_buf: [max_cgroup_path + 64]u8 = undefined,
    rel_len: usize = 0,
    work_buf: [max_cgroup_path + 72]u8 = undefined,
    work_len: usize = 0,
    kill_buf: [max_cgroup_path + 96]u8 = undefined,
    kill_len: usize = 0,
    aside_buf: [max_cgroup_path + 80]u8 = undefined,
    aside_len: usize = 0,
    procs_fd: c_int = -1,

    joined: bool = false,
    stopped: bool = false,
    lingering: [128]u32 = undefined,
    lingering_len: usize = 0,
    lingering_more: bool = false,

    /// The name carries sixteen hex digits of kernel entropy beside the engine's pid, not a
    /// counter. A cgroup outlives an engine killed before its cleanup, and an engine in a
    /// container starts at the same small pid time after time, so a pid-and-counter name is
    /// exactly the name the next engine would `mkdir` — and a directory already there would
    /// refuse the spawn as a setup error instead of containing it.
    pub fn init(home: CgroupHome, world: bool) ?CgroupSpawn {
        var self: CgroupSpawn = .{ .world = world };
        var hex: [16]u8 = undefined;
        const tag = randomHex(&hex) orelse return null;
        const d = std.fmt.bufPrintZ(&self.dir_buf, "{s}/sideeye-{d}-{s}", .{ home.dir, getpid(), tag }) catch return null;
        self.dir_len = d.len;
        const sep: []const u8 = if (std.mem.endsWith(u8, home.rel, "/")) "" else "/";
        const r = std.fmt.bufPrint(&self.rel_buf, "{s}{s}sideeye-{d}-{s}", .{ home.rel, sep, getpid(), tag }) catch return null;
        self.rel_len = r.len;
        const w = std.fmt.bufPrintZ(&self.work_buf, "{s}/work", .{d}) catch return null;
        self.work_len = w.len;
        const k = std.fmt.bufPrintZ(&self.kill_buf, "{s}/cgroup.kill", .{w}) catch return null;
        self.kill_len = k.len;
        const a = std.fmt.bufPrintZ(&self.aside_buf, "{s}/cgroup.procs", .{d}) catch return null;
        self.aside_len = a.len;
        return self;
    }
    pub fn dir(self: *const CgroupSpawn) [:0]const u8 {
        return self.dir_buf[0..self.dir_len :0];
    }
    pub fn relPath(self: *const CgroupSpawn) []const u8 {
        return self.rel_buf[0..self.rel_len];
    }
    pub fn killPath(self: *const CgroupSpawn) [:0]const u8 {
        return self.kill_buf[0..self.kill_len :0];
    }
    pub fn workDir(self: *const CgroupSpawn) [:0]const u8 {
        return self.work_buf[0..self.work_len :0];
    }
    pub fn asidePath(self: *const CgroupSpawn) [:0]const u8 {
        return self.aside_buf[0..self.aside_len :0];
    }
    pub fn removeDirs(self: *const CgroupSpawn) void {
        _ = rmdir(self.workDir().ptr);
        _ = rmdir(self.dir().ptr);
    }
};

const ESRCH: c_int = @intFromEnum(std.posix.E.SRCH);

/// rest. Null only when there is no such process. A file that exists and cannot be read or
/// parsed answers `?`, which a caller asking "is it dead?" must read as no — the survivor
/// check (contract v17, #559) refuses on it rather than trusting a read it could not make.
pub fn processState(pid: u32) ?u8 {
    var pbuf: [32]u8 = undefined;
    const path = std.fmt.bufPrintZ(&pbuf, "/proc/{d}/stat", .{pid}) catch return '?';
    const fd = open(path.ptr, O_RDONLY | O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return if (std.c._errno().* == ENOENT) null else '?';
    defer _ = close(fd);
    var buf: [1024]u8 = undefined;
    const got = while (true) {
        const r = read(fd, &buf, buf.len);
        if (r < 0 and std.c._errno().* == EINTR) continue;
        break r;
    };
    if (got < 0) return if (std.c._errno().* == ESRCH) null else '?';
    return statState(buf[0..@intCast(got)]) orelse '?';
}

/// command name. The LAST `)`, because the name is the process's own choice and may hold
/// spaces and parentheses of its own.
fn statState(stat: []const u8) ?u8 {
    const paren = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return null;
    if (paren + 2 >= stat.len or stat[paren + 1] != ' ') return null;
    return stat[paren + 2];
}

fn cgroupMakeReal(cg: *CgroupSpawn) bool {
    if (mkdir(cg.dir().ptr, 0o755) != 0) return false;
    if (mkdir(cg.workDir().ptr, 0o755) != 0) {
        _ = rmdir(cg.dir().ptr);
        return false;
    }
    var buf: [max_cgroup_path + 96]u8 = undefined;
    const procs = std.fmt.bufPrintZ(&buf, "{s}/cgroup.procs", .{cg.workDir()}) catch {
        cg.removeDirs();
        return false;
    };
    cg.procs_fd = open(procs.ptr, O_WRONLY | O_CLOEXEC, @as(c_uint, 0));
    if (cg.procs_fd < 0) {
        cg.removeDirs();
        return false;
    }
    return true;
}

fn cgroupJoinReal(cg: *CgroupSpawn, pid: c_int) bool {
    defer {
        _ = close(cg.procs_fd);
        cg.procs_fd = -1;
    }
    var buf: [16]u8 = undefined;
    const pid_s = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch return false;
    return write(cg.procs_fd, pid_s.ptr, pid_s.len) == @as(isize, @intCast(pid_s.len));
}

/// What is read is `work`'s and R's own `cgroup.procs`, not those of cgroups a target made
/// below them: a writer that moved into one of those is killed with the rest and not named,
/// which is what an uncontained engine's group kill does with every lingering writer.
fn cgroupStopReal(cg: *CgroupSpawn, read_lingering: bool) void {
    if (!cg.joined) return;
    var events_buf: [max_cgroup_path + 80]u8 = undefined;
    const events = std.fmt.bufPrintZ(&events_buf, "{s}/cgroup.events", .{cg.dir()}) catch return;
    var ev_buf: [256]u8 = undefined;
    if (read_lingering) lingering: {
        const ev = readSmallFile(events.ptr, &ev_buf) orelse break :lingering;
        if (std.mem.indexOf(u8, ev, "populated 1") == null) break :lingering;
        noteLingering(cg, cg.workDir());
        noteLingering(cg, cg.dir());
    }
    var kill_buf: [max_cgroup_path + 80]u8 = undefined;
    const kill_path = std.fmt.bufPrintZ(&kill_buf, "{s}/cgroup.kill", .{cg.dir()}) catch return;
    _ = writeSmallFile(kill_path.ptr, "1");
    const deadline = monotonicMs() + world_kill_grace_ms;
    while (true) {
        if (readSmallFile(events.ptr, &ev_buf)) |ev| {
            if (std.mem.indexOf(u8, ev, "populated 0") != null) {
                cg.stopped = true;
                break;
            }
        }
        if (monotonicMs() >= deadline) break;
        sleepForMs(2);
    }
    cg.removeDirs();
}

/// The pids in one cgroup's `cgroup.procs`, added to `cg.lingering`. A list longer than the
/// read holds counts as more than the array holds, not as the pids that fitted.
fn noteLingering(cg: *CgroupSpawn, dir: []const u8) void {
    var procs_buf: [max_cgroup_path + 96]u8 = undefined;
    const procs = std.fmt.bufPrintZ(&procs_buf, "{s}/cgroup.procs", .{dir}) catch return;
    var list_buf: [4096]u8 = undefined;
    const list = readSmallFile(procs.ptr, &list_buf) orelse return;
    if (list.len == list_buf.len) cg.lingering_more = true;
    var it = std.mem.tokenizeScalar(u8, list, '\n');
    while (it.next()) |t| {
        const lingering_pid = std.fmt.parseInt(u32, t, 10) catch continue;
        if (cg.lingering_len < cg.lingering.len) {
            cg.lingering[cg.lingering_len] = lingering_pid;
            cg.lingering_len += 1;
        } else cg.lingering_more = true;
    }
}

/// delegates the rest. A fake `wait` is expected to delegate group waits (`pid < 0`)
/// to the real `waitpid`, so the test's own children are still reaped while the
/// direct wait is the part being driven.
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
    fn openDevNull() c_int {
        return open("/dev/null", O_RDONLY, @as(c_uint, 0));
    }
    /// The child's stdout capture, opened in the parent since #469. On the seam beside
    /// `openDevNull` and `forkChild` so a test can assert the pair that matters: the
    /// spawn refused, and it refused BEFORE the fork. A fake is expected to delegate
    /// here rather than answer — the flags are what the tests are about, and a fake
    /// that returned a number of its own would measure nothing.
    fn openCapture(path: [*:0]const u8, flags: c_int) c_int {
        return open(path, flags, @as(c_uint, 0o600));
    }
    fn cgroupMake(cg: *CgroupSpawn) bool {
        return cgroupMakeReal(cg);
    }
    fn cgroupJoin(cg: *CgroupSpawn, pid: c_int) bool {
        return cgroupJoinReal(cg, pid);
    }
    fn cgroupStop(cg: *CgroupSpawn, read_lingering: bool) void {
        cgroupStopReal(cg, read_lingering);
    }
};

pub fn monotonicMs() u64 {
    var ts: std.c.timespec = undefined;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) unreachable;
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}

/// Not one `nanosleep`: `stopSidecar` counts its grace in calls, and a signal would shorten it.
pub fn sleepForMs(ms: u64) void {
    var ts: std.c.timespec = .{ .sec = @intCast(ms / 1000), .nsec = @intCast((ms % 1000) * 1_000_000) };
    var rem: std.c.timespec = undefined;
    while (nanosleep(&ts, &rem) != 0 and std.c._errno().* == EINTR) ts = rem;
}

/// `forward`, not `kill`, for an engine the MCP server started: killed, it could not stop its own children.
pub const ChildStop = enum(u1) { kill, forward };

const interrupt_signals = [_]std.c.SIG{ .INT, .TERM, .HUP, .PIPE };

var interrupt_hook: ?*const fn (c_int) noreturn = null;
var interrupt_sig = std.atomic.Value(c_int).init(0);
/// Cleared before every reaping wait: a reaped id may already name a stranger.
var live_child = std.atomic.Value(u64).init(0);
var sidecar_pgid = std.atomic.Value(c_int).init(0);
var stopping_depth = std.atomic.Value(u32).init(0);
var saved_sigchld: std.c.Sigaction = undefined;
var sigchld_changed = false;
var saved_sigalrm: std.c.Sigaction = undefined;

/// Not a direct `kill`: a test stands in for a child the signal cannot reach.
pub var interrupt_kill: *const fn (c_int, c_int) callconv(.c) c_int = kill;

/// Kept equal to `world_kill_grace_ms`, in the seconds `alarm` takes.
const interrupt_grace_s: c_uint = 5;
/// An engine handed the signal stops its own child (`interrupt_grace_s`) and `fs_usage` (twice
/// `stopSidecar`'s 5 s) before it ends; a shorter wait would name it while it does.
const forward_grace_s: c_uint = 20;

fn interruptMask() std.c.sigset_t {
    var set: std.c.sigset_t = undefined;
    _ = std.c.sigemptyset(&set);
    for (interrupt_signals) |sig| _ = std.c.sigaddset(&set, sig);
    _ = std.c.sigaddset(&set, .ALRM);
    return set;
}

/// ADR 0124.
pub fn installInterruptHandlers(hook: *const fn (c_int) noreturn) void {
    interrupt_hook = hook;
    var cur: std.c.Sigaction = undefined;
    // Not left at an inherited SIG_IGN: children would be auto-reaped, and the handler must never
    // signal an id nobody holds.
    if (std.c.sigaction(.CHLD, null, &cur) == 0 and cur.handler.handler == std.c.SIG.IGN) {
        saved_sigchld = cur;
        sigchld_changed = true;
        var dfl = cur;
        dfl.handler = .{ .handler = std.c.SIG.DFL };
        _ = std.c.sigaction(.CHLD, &dfl, null);
    }
    var act: std.c.Sigaction = .{ .handler = .{ .handler = onInterrupt }, .mask = interruptMask(), .flags = std.c.SA.RESTART };
    for (interrupt_signals) |sig| {
        if (std.c.sigaction(sig, null, &cur) != 0) continue;
        // No handler for a signal ignored at startup: `nohup` and a script's `&` job rely on the ignore.
        if (cur.handler.handler == std.c.SIG.IGN) continue;
        _ = std.c.sigaction(sig, &act, null);
    }
    _ = std.c.sigaction(.ALRM, null, &saved_sigalrm);
    act.handler = .{ .handler = onGraceOver };
    _ = std.c.sigaction(.ALRM, &act, null);
}

pub fn noteSidecar(pgid: c_int) void {
    sidecar_pgid.store(pgid, .seq_cst);
    if (pgid == 0) stopIfInterrupted();
}

/// Without it, a recorded signal would stop the `sudo -n /bin/kill` that stopping fs_usage runs.
pub fn beginStopping() void {
    _ = stopping_depth.fetchAdd(1, .seq_cst);
}

pub fn endStopping() void {
    if (stopping_depth.fetchSub(1, .seq_cst) == 1) stopIfInterrupted();
}

pub fn stopIfInterrupted() void {
    const sig = interrupt_sig.load(.seq_cst);
    if (sig == 0 or stopping_depth.load(.seq_cst) != 0) return;
    // Not left armed: the alarm would cut the stop of fs_usage short.
    _ = std.c.alarm(0);
    if (interrupt_hook) |hook| hook(sig);
}

/// The `_exit` is not dead code: the kernel does not end PID 1 by a signal left at its default.
fn defaultAction() std.c.Sigaction {
    var dfl: std.c.Sigaction = .{ .handler = .{ .handler = std.c.SIG.DFL }, .mask = undefined, .flags = 0 };
    _ = std.c.sigemptyset(&dfl.mask);
    return dfl;
}

pub fn dieBySignal(sig: c_int) noreturn {
    const dfl = defaultAction();
    const s: std.c.SIG = @enumFromInt(sig);
    _ = std.c.sigaction(s, &dfl, null);
    var set: std.c.sigset_t = undefined;
    _ = std.c.sigemptyset(&set);
    _ = std.c.sigaddset(&set, s);
    _ = std.c.sigprocmask(std.c.SIG.UNBLOCK, &set, null);
    _ = kill(getpid(), sig);
    _exit(128 + sig);
}

fn liveChildWord(pgid: c_int, stop: ChildStop) u64 {
    return (@as(u64, @intCast(pgid)) << 1) | @intFromEnum(stop);
}

fn onInterrupt(s: std.c.SIG) callconv(.c) void {
    const saved_errno = std.c._errno().*;
    defer std.c._errno().* = saved_errno;
    const sig: c_int = @intCast(@intFromEnum(s));
    const first = interrupt_sig.cmpxchgStrong(0, sig, .seq_cst, .seq_cst) == null;
    const word = live_child.load(.seq_cst);
    // No waiting on a second signal, even mid-stop: whoever sent it will not wait.
    if (!first) graceOver(interrupt_sig.load(.seq_cst), 0);
    if (stopping_depth.load(.seq_cst) != 0) return;
    if (word != 0) {
        const pgid: c_int = @intCast(word >> 1);
        const to: c_int = if (word & 1 == @intFromEnum(ChildStop.forward)) sig else SIGKILL;
        if (interrupt_kill(-pgid, to) != 0 and std.c._errno().* == ESRCH) _ = interrupt_kill(pgid, to);
        _ = std.c.alarm(if (word & 1 == @intFromEnum(ChildStop.forward)) forward_grace_s else interrupt_grace_s);
        return;
    }
    if (sidecar_pgid.load(.seq_cst) != 0) return;
    writeStopLine(sig, 0);
    dieBySignal(sig);
}

fn onGraceOver(_: std.c.SIG) callconv(.c) void {
    const saved_errno = std.c._errno().*;
    defer std.c._errno().* = saved_errno;
    const sig = interrupt_sig.load(.seq_cst);
    if (sig == 0 or stopping_depth.load(.seq_cst) != 0) return;
    graceOver(sig, live_child.load(.seq_cst));
}

fn graceOver(sig: c_int, word: u64) noreturn {
    // SIGINT, not SIGKILL: fs_usage flushes its capture on it, and sudo passes it on.
    const observer = sidecar_pgid.load(.seq_cst);
    if (observer != 0) _ = kill(-observer, SIGINT);
    writeStopLine(sig, if (word != 0) @intCast(word >> 1) else 0);
    dieBySignal(sig);
}

/// No allocation and one `write`: this runs in a signal handler.
pub fn writeStopLine(sig: c_int, left_pgid: c_int) void {
    var buf: [160]u8 = undefined;
    const line = fmtStopLine(&buf, sig, left_pgid);
    _ = write(2, line.ptr, line.len);
}

/// Hand-built rather than through `std.fmt`, which is not on POSIX's list for a handler.
fn fmtStopLine(buf: *[160]u8, sig: c_int, left_pgid: c_int) []const u8 {
    var n: usize = 0;
    const put = struct {
        fn text(b: *[160]u8, at: *usize, t: []const u8) void {
            @memcpy(b[at.*..][0..t.len], t);
            at.* += t.len;
        }
        fn num(b: *[160]u8, at: *usize, v: c_int) void {
            var digits: [12]u8 = undefined;
            var x: u32 = @intCast(@max(v, 0));
            var i: usize = digits.len;
            while (true) {
                i -= 1;
                digits[i] = @intCast('0' + x % 10);
                x /= 10;
                if (x == 0) break;
            }
            text(b, at, digits[i..]);
        }
    };
    put.text(buf, &n, "sideeye: stopped by signal ");
    put.num(buf, &n, sig);
    if (left_pgid != 0) {
        put.text(buf, &n, "; process group ");
        put.num(buf, &n, left_pgid);
        put.text(buf, &n, " did not end and is left running");
    }
    put.text(buf, &n, "\n");
    return buf[0..n];
}

test "the stop line names the signal, and the group left running when there is one" {
    var buf: [160]u8 = undefined;
    try std.testing.expectEqualStrings("sideeye: stopped by signal 15\n", fmtStopLine(&buf, 15, 0));
    try std.testing.expectEqualStrings("sideeye: stopped by signal 2; process group 2147483647 did not end and is left running\n", fmtStopLine(&buf, 2, 2147483647));
}

/// Without it, a handler could run between a fork and the child's registration and miss the child.
pub fn blockInterrupts(old: *std.c.sigset_t) void {
    const set = interruptMask();
    _ = std.c.sigprocmask(std.c.SIG.BLOCK, &set, old);
}

pub fn restoreMask(old: *const std.c.sigset_t) void {
    _ = std.c.sigprocmask(std.c.SIG.SETMASK, old, null);
}

fn childRestoreSignals(old: *const std.c.sigset_t) void {
    if (sigchld_changed) _ = std.c.sigaction(.CHLD, &saved_sigchld, null);
    // Not after the mask comes back: until it leaves the engine's group, a terminal's SIGINT reaches
    // this child too, and the engine's handler must not run in it.
    if (interrupt_hook != null) {
        var cur: std.c.Sigaction = undefined;
        const dfl = defaultAction();
        for (interrupt_signals) |sig| {
            if (std.c.sigaction(sig, null, &cur) == 0 and cur.handler.handler != std.c.SIG.IGN)
                _ = std.c.sigaction(sig, &dfl, null);
        }
        _ = std.c.sigaction(.ALRM, &saved_sigalrm, null);
    }
    restoreMask(old);
}

fn registerLiveChild(pid: c_int, stop: ChildStop) void {
    live_child.store(liveChildWord(pid, stop), .seq_cst);
}

fn clearLiveChild() void {
    live_child.store(0, .seq_cst);
}

fn runChildImplWithOps(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    capture: ?Capture,
    minimal_env: bool,
    budget_ms: ?u64,
    cwd: ?[]const u8,
    cg: ?*CgroupSpawn,
    stop: ChildStop,
    comptime Ops: type,
) (ContainedSpawnError || error{TimedOut})!Term {
    stopIfInterrupted();
    const r = runChildSpawnAndWait(gpa, argv, env_pairs, capture, minimal_env, budget_ms, cwd, cg, stop, Ops);
    clearLiveChild();
    // Before the caller sees the child's end: a child this process killed must not be read as a
    // setup that died of a signal or a world that reached its crash point.
    stopIfInterrupted();
    return r;
}

fn runChildSpawnAndWait(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    env_pairs: []const [2][]const u8,
    capture: ?Capture,
    minimal_env: bool,
    budget_ms: ?u64,
    cwd: ?[]const u8,
    cg: ?*CgroupSpawn,
    stop: ChildStop,
    comptime Ops: type,
) (ContainedSpawnError || error{TimedOut})!Term {
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
    const envp: ?[*]const ?[*:0]const u8 = if (minimal_env) blk: {
        const list = try arena.alloc(?[*:0]const u8, env_pairs.len + 1);
        for (env_pairs, 0..) |kv, i|
            list[i] = (try std.fmt.allocPrintSentinel(arena, "{s}={s}", .{ kv[0], kv[1] }, 0)).ptr;
        list[env_pairs.len] = null;
        break :blk list.ptr;
    } else null;
    const capture_z: ?[*:0]const u8 = if (capture) |cap| (try arena.dupeZ(u8, cap.path)).ptr else null;

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

    const cfd: c_int = if (capture_z) |cz| blk: {
        const fd = Ops.openCapture(cz, captureFlags(capture.?.exclusive));
        if (fd < 0) {
            _ = close(nfd);
            return error.CaptureUnavailable;
        }
        break :blk fd;
    } else -1;

    // The run's cgroup (v17, #559), made and its `cgroup.procs` opened here, before the fork,
    // for #469's reason: a failure is a named spawn error on the caller's channel, never a code
    // in the target's exit-status namespace. The pipe is how the child waits — after it leads
    // its own group, before it execs — until the parent has moved it: a child that execs first
    // runs, however briefly, outside the cgroup that is meant to stop it.
    var join_pipe: [2]c_int = .{ -1, -1 };
    // Not blocked after the mkdir: a handler running before the child's registration would find nothing
    // to stop and end the process, leaving the directory behind.
    var old_mask: std.c.sigset_t = undefined;
    blockInterrupts(&old_mask);
    if (cg) |spawn_cg| {
        if (!Ops.cgroupMake(spawn_cg)) {
            restoreMask(&old_mask);
            _ = close(nfd);
            if (cfd >= 0) _ = close(cfd);
            return error.CgroupJoinFailed;
        }
        if (pipe(&join_pipe) != 0) {
            if (spawn_cg.procs_fd >= 0) _ = close(spawn_cg.procs_fd);
            spawn_cg.procs_fd = -1;
            spawn_cg.removeDirs();
            restoreMask(&old_mask);
            _ = close(nfd);
            if (cfd >= 0) _ = close(cfd);
            return error.CgroupJoinFailed;
        }
    }

    const pid = Ops.forkChild();
    if (pid < 0) {
        restoreMask(&old_mask);
        _ = close(nfd);
        if (cfd >= 0) _ = close(cfd);
        if (cg) |spawn_cg| {
            _ = close(join_pipe[0]);
            _ = close(join_pipe[1]);
            if (spawn_cg.procs_fd >= 0) _ = close(spawn_cg.procs_fd);
            spawn_cg.procs_fd = -1;
            spawn_cg.removeDirs();
        }
        return error.ForkFailed;
    }
    if (pid == 0) {
        childRestoreSignals(&old_mask);
        // Before exec, so the target never runs in the engine's group — and 126 rather
        // than a discarded result, for the reason `runChildImpl`'s copy of this line
        // carries: the shim's crash-point kill now addresses the caller's whole group,
        // so a target sharing the engine's group could kill the exploration.
        childEnterOwnGroup();
        if (join_pipe[0] >= 0) {
            // Wait to be moved into the run's cgroup (v17, #559). One byte means the parent
            // moved it; anything else — the move failed, or the parent is gone — means this
            // child must not run at all.
            _ = close(join_pipe[1]);
            var byte: [1]u8 = undefined;
            const got = while (true) {
                const r = read(join_pipe[0], &byte, 1);
                if (r < 0 and std.c._errno().* == EINTR) continue;
                break r;
            };
            if (got != 1) childArrangeFailed("waiting to be moved into the run's cgroup");
            _ = close(join_pipe[0]);
        }
        // stdin first, before any capture: a child that could not be given its stdin
        // must not run at all. The retry bound, the abort, and the fd-0 case are all
        // in `adoptStdin`, shared with the sidecar's fork.
        adoptStdin(nfd);
        if (cfd >= 0) {
            // A capture that cannot be arranged must not fall back to the engine's own
            // stdout: a world whose evidence went to the wrong stream would read as
            // "marker never appeared".
            if (cfd != 1) {
                if (!dup2Bounded(dup2, cfd, 1)) childArrangeFailed("dup2(capture, 1)");
                _ = close(cfd);
            }
            if (capture.?.stderr_too) {
                // Both streams into the capture: a partial capture would leak the
                // other stream to the inherited fds — the exact failure this variant
                // exists to prevent. 126 for the same reason as the dup2 above.
                if (!dup2Bounded(dup2, 1, 2)) childArrangeFailed("dup2(1, 2)");
            }
            if (minimal_env) {
                // The child (a config's operation, untrusted) must not write to the MCP
                // transport on fd 2 either: stderr → the same capture file. (fd 0 was
                // already pointed at /dev/null above, for every child, not only this
                // path — #263.) Higher fds are closed so no inherited descriptor (the
                // JSON-RPC stdin among them) survives into the child.
                if (!dup2Bounded(dup2, 1, 2)) childArrangeFailed("dup2(1, 2)"); // stderr → capture
                var fd: c_int = 3;
                while (fd < 256) : (fd += 1) _ = close(fd);
            }
        }
        // 125 is its own code: 126 still carries two meanings the engine cannot tell
        // apart (a `dup2` failure here, and a target that genuinely exits 126), and
        // adding a third would make the ambiguity structural rather than local. The
        // parent resolves and vets this path before the fork, so reaching here means
        // the directory went away between the vet and the exec.
        if (cwd_z) |cz| {
            if (chdir(cz) != 0) _exit(125);
        }
        if (envp) |ep| {
            _ = execve(argv_z[0].?, argv_z.ptr, ep);
        } else {
            for (env_z) |kv| _ = setenv(kv[0], kv[1], 1);
            _ = execvp(argv_z[0].?, argv_z.ptr);
        }
        _exit(127);
    }
    // The capture's copy matters more than stdin's — held open, the engine would keep a
    // descriptor on a work-directory file for the whole run, and every later world's
    // open would add another.
    _ = close(nfd);
    if (cfd >= 0) _ = close(cfd);
    // Repeated in the parent to close the window where the child has not been scheduled
    // yet. Whichever call runs first wins; the second fails harmlessly (EACCES once the
    // child has exec'd, ESRCH if it has already exited, and since #632 EPERM when the child
    // has left for a session of its own, which this call may not cross). The result is
    // discarded for all of them: the child checks its own group, and that check is the one
    // the `exec` depends on.
    _ = setpgid(pid, pid);
    registerLiveChild(pid, stop);
    restoreMask(&old_mask);

    if (cg) |spawn_cg| {
        if (!Ops.cgroupJoin(spawn_cg, pid)) {
            _ = kill(pid, SIGKILL);
            clearLiveChild();
            _ = close(join_pipe[1]);
            _ = close(join_pipe[0]);
            var reaped: c_int = 0;
            while (waitpid(pid, &reaped, 0) < 0 and std.c._errno().* == EINTR) {}
            spawn_cg.removeDirs();
            return error.CgroupJoinFailed;
        }
        spawn_cg.joined = true;
        // The read end stays open in this process until the go-ahead is written. A child that
        // died before reading it — its own `setpgid` failed, or something outside killed it —
        // would otherwise leave a pipe with no reader, and the write raises SIGPIPE here
        // (review, #559 PR A).
        _ = write(join_pipe[1], "1", 1);
        _ = close(join_pipe[1]);
        _ = close(join_pipe[0]);
    }

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
                // classifies toward the child. This is the measurement rule the
                // member's doc promises, not a proof the child finished its work
                // inside the budget. Only a *successful* post-deadline observation
                // can answer .timed_out; a failing one lands above in .waitid_broke
                // and kills nothing.
                if (past_deadline) break :poll .timed_out;
                past_deadline = true;
                continue :poll;
            }
            Ops.sleepMs(@min(interval, deadline - now));
            interval = @min(interval * 2, 10);
        };
        switch (outcome) {
            .exited => {
                // What is still in the run's cgroup is read before anything is killed (v17).
                if (cg) |spawn_cg| Ops.cgroupStop(spawn_cg, true);
                Ops.killGroup(pid);
                // The direct reap may block: the child was observed exited and the
                // default disposition holds it zombie, so the wait returns without
                // waiting. The group drain may NOT block — the target can have put
                // other processes in the group directly, and if the SIGKILL failed
                // to land on one of them (uninterruptible sleep, changed
                // credentials) a blocking drain would hang the very path that
                // promises not to. Survivors are strays for the quiescence check.
                var status: c_int = 0;
                clearLiveChild();
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
                if (cg) |spawn_cg| Ops.cgroupStop(spawn_cg, false);
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
                clearLiveChild();
                reap: while (true) {
                    const wrc = Ops.wait(pid, null, WNOHANG);
                    if (wrc == pid) break :reap;
                    if (wrc < 0 and std.c._errno().* != EINTR) break :reap;
                    const gnow = Ops.nowMs();
                    if (gnow >= grace_deadline) break :reap;
                    Ops.sleepMs(@min(ginterval, grace_deadline - gnow));
                    ginterval = @min(ginterval * 2, 10);
                }
                while (Ops.wait(-pid, null, WNOHANG) > 0) {}
                return error.TimedOut;
            },
            .waitid_broke => {
                // Nothing was signalled (see the loop comment), so nothing here may
                // block on a child that might still be running: one non-blocking reap
                // attempt, a non-blocking drain, and the same refusal the blocking
                // branch gives a broken wait. A live child this leaves behind is a
                // stray; the stray is what the quiescence check is for.
                if (cg) |spawn_cg| Ops.cgroupStop(spawn_cg, false);
                clearLiveChild();
                _ = Ops.wait(pid, null, WNOHANG);
                while (Ops.wait(-pid, null, WNOHANG) > 0) {}
                return error.WaitFailed;
            },
        }
    } else {
        var info: [256]u8 align(16) = undefined;
        const observed = while (true) {
            if (waitid(P_PID, pid, &info, WEXITED | WNOWAIT) == 0) break true;
            if (std.c._errno().* != EINTR) break false;
        };
        if (observed) {
            if (cg) |spawn_cg| Ops.cgroupStop(spawn_cg, true);
            Ops.killGroup(pid);
        } else if (cg) |spawn_cg| Ops.cgroupStop(spawn_cg, false);
        // If `waitid` failed the id is not pinned, so nothing is signalled: sending SIGKILL to
        // a group that may have been recycled is worse than leaving a stray process. The stray
        // is what the quiescence check is for.
    }

    // Retried rather than assumed. `status` is only written when the call succeeds, so a
    // discarded failure leaves it zero, `decodeStatus` reads a killed world as a clean
    // exit, and the world is reported as `kill_did_not_land` — the wrong reason. Same class
    // as the ordering defect above: a wait call's side effect trusted without checking that
    // the call happened.
    var status: c_int = 0;
    clearLiveChild();
    const wait_failed = for (0..9) |_| {
        if (Ops.wait(pid, &status, 0) >= 0) break false;
        if (std.c._errno().* != EINTR) break true;
    } else true;

    // This runs *before* the wait failure is returned. Returning early would skip the drain
    // and leave behind the direct child itself — never reaped, since reaping it is exactly
    // what just failed. A fix for a wrong verdict must not introduce a process leak.
    while (Ops.wait(-pid, null, 0) > 0) {}

    if (wait_failed) return error.WaitFailed;
    return decodeStatus(status);
}

const InterruptTest = struct {
    const SIGTERM_: c_int = 15;
    const SIGHUP_: c_int = 1;
    const SIGPIPE_: c_int = 13;
    const SIG_IGN_: usize = 1;

    fn die(sig: c_int) noreturn {
        dieBySignal(sig);
    }

    fn killRefused(_: c_int, _: c_int) callconv(.c) c_int {
        std.c._errno().* = EPERM;
        return -1;
    }

    fn eofWithin(fd: c_int, ms: u64) bool {
        const deadline = monotonicMs() + ms;
        var pfd = [1]std.c.pollfd{.{ .fd = fd, .events = std.c.POLL.IN, .revents = 0 }};
        while (true) {
            if (std.c.poll(&pfd, 1, 50) > 0) {
                var b: [64]u8 = undefined;
                const n = read(fd, &b, b.len);
                if (n == 0) return true;
                if (n < 0) return false;
            }
            if (monotonicMs() >= deadline) return false;
        }
    }

    fn byteWithin(fd: c_int, ms: c_int) ?u8 {
        var pfd = [1]std.c.pollfd{.{ .fd = fd, .events = std.c.POLL.IN, .revents = 0 }};
        if (std.c.poll(&pfd, 1, ms) <= 0) return null;
        var b: [1]u8 = undefined;
        return if (read(fd, &b, 1) == 1) b[0] else null;
    }

    fn pidWithin(fd: c_int) !c_int {
        var b: [16]u8 = undefined;
        var n: usize = 0;
        while (n < b.len) : (n += 1) {
            b[n] = byteWithin(fd, 10_000) orelse return error.NeverRan;
            if (b[n] == ' ') break;
        }
        return std.fmt.parseInt(c_int, b[0..n], 10) catch error.NeverRan;
    }

    /// Killed only while unreaped: after the reap the id may name a stranger.
    fn waitWithin(pid: c_int, ms: u64) ?Term {
        const deadline = monotonicMs() + ms;
        while (monotonicMs() < deadline) {
            var status: c_int = 0;
            if (waitpid(pid, &status, WNOHANG) == pid) return decodeStatus(status);
            sleepForMs(20);
        }
        _ = kill(pid, SIGKILL);
        _ = waitpid(pid, null, 0);
        return null;
    }

    /// Not after the holder's pipe end is closed: the group's id may have been reused by then.
    fn endGroupIfHeld(group: c_int, holder: c_int) void {
        if (!eofWithin(holder, 0)) _ = kill(-group, SIGKILL);
    }

    const Run = struct {
        engine: c_int,
        child_group: c_int,
        held: c_int,
        err: c_int,

        fn end(r: Run) void {
            endGroupIfHeld(r.child_group, r.held);
            if (waitpid(r.engine, null, WNOHANG) == 0) {
                _ = kill(r.engine, SIGKILL);
                _ = waitpid(r.engine, null, 0);
            }
            _ = close(r.held);
            _ = close(r.err);
        }
    };

    fn start(setup: *const fn () void) !Run {
        var ready: [2]c_int = undefined;
        var held: [2]c_int = undefined;
        var err: [2]c_int = undefined;
        if (pipe(&ready) != 0 or pipe(&held) != 0 or pipe(&err) != 0) return error.Setup;
        const pid = fork();
        if (pid < 0) return error.Setup;
        if (pid == 0) {
            _ = close(ready[0]);
            _ = close(held[0]);
            _ = close(err[0]);
            if (dup2(err[1], 2) < 0) _exit(10);
            setup();
            installInterruptHandlers(die);
            var buf: [96]u8 = undefined;
            const line = std.fmt.bufPrint(&buf, "printf '%d ' $$ >&{d}; exec sleep 300", .{ready[1]}) catch _exit(11);
            const term = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch _exit(12);
            _exit(switch (term) {
                .exited => |c| c,
                else => 13,
            });
        }
        _ = close(ready[1]);
        _ = close(held[1]);
        _ = close(err[1]);
        defer _ = close(ready[0]);
        const child = pidWithin(ready[0]) catch {
            _ = kill(pid, SIGKILL);
            _ = waitpid(pid, null, 0);
            return error.ChildNeverRan;
        };
        return .{ .engine = pid, .child_group = child, .held = held[0], .err = err[0] };
    }

    fn nothing() void {}
    fn ignoreHup() void {
        _ = signal(SIGHUP_, SIG_IGN_);
    }
    fn refuseKill() void {
        interrupt_kill = killRefused;
    }
};

test "a run told to stop ends the child it waits on, then ends by the same signal (#819)" {
    for ([_]c_int{ InterruptTest.SIGTERM_, InterruptTest.SIGPIPE_ }) |sig| {
        const r = try InterruptTest.start(InterruptTest.nothing);
        defer r.end();
        try std.testing.expectEqual(@as(c_int, 0), kill(r.engine, sig));
        try std.testing.expectEqual(@as(?Term, .{ .signaled = @intCast(sig) }), InterruptTest.waitWithin(r.engine, 10_000));
        try std.testing.expect(InterruptTest.eofWithin(r.held, 10_000));
    }
}

test "a signal ignored when the run starts stays ignored, by the run and by what it starts (#819)" {
    var ready: [2]c_int = undefined;
    var go: [2]c_int = undefined;
    if (pipe(&ready) != 0 or pipe(&go) != 0) return error.Setup;
    const engine = fork();
    if (engine < 0) return error.Setup;
    if (engine == 0) {
        _ = close(ready[0]);
        _ = close(go[1]);
        InterruptTest.ignoreHup();
        installInterruptHandlers(InterruptTest.die);
        var buf: [128]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "kill -HUP $$; printf r >&{d}; read x <&{d}", .{ ready[1], go[0] }) catch _exit(11);
        const term = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch _exit(12);
        _exit(switch (term) {
            .exited => |c| c,
            else => 13,
        });
    }
    _ = close(ready[1]);
    _ = close(go[0]);
    defer _ = close(ready[0]);
    const lived = InterruptTest.byteWithin(ready[0], 10_000);
    if (lived == null) _ = close(go[1]);
    try std.testing.expectEqual(@as(?u8, 'r'), lived);
    try std.testing.expectEqual(@as(c_int, 0), kill(engine, InterruptTest.SIGHUP_));
    sleepForMs(300);
    try std.testing.expectEqual(@as(isize, 2), write(go[1], "x\n", 2));
    _ = close(go[1]);
    try std.testing.expectEqual(@as(?Term, .{ .exited = 0 }), InterruptTest.waitWithin(engine, 10_000));
}

test "a child the signal cannot reach is named and left once the grace has run (#819)" {
    const t0 = monotonicMs();
    const r = try InterruptTest.start(InterruptTest.refuseKill);
    defer r.end();
    try std.testing.expectEqual(@as(c_int, 0), kill(r.engine, InterruptTest.SIGTERM_));
    try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(r.engine, 12_000));
    const took = monotonicMs() - t0;
    try std.testing.expect(took >= 4_000 and took < 9_000);
    var line_buf: [256]u8 = undefined;
    const n = read(r.err, &line_buf, line_buf.len);
    try std.testing.expect(n > 0);
    var want: [96]u8 = undefined;
    const named = try std.fmt.bufPrint(&want, "process group {d} did not end and is left running", .{r.child_group});
    try std.testing.expect(std.mem.indexOf(u8, line_buf[0..@intCast(n)], named) != null);
    try std.testing.expect(!InterruptTest.eofWithin(r.held, 200));
}

test "a second signal ends the run at once, without waiting out the grace (#819)" {
    const t0 = monotonicMs();
    const r = try InterruptTest.start(InterruptTest.refuseKill);
    defer r.end();
    try std.testing.expectEqual(@as(c_int, 0), kill(r.engine, InterruptTest.SIGTERM_));
    sleepForMs(300);
    try std.testing.expectEqual(@as(c_int, 0), kill(r.engine, InterruptTest.SIGHUP_));
    try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(r.engine, 12_000));
    try std.testing.expect(monotonicMs() - t0 < 3_000);
    var line_buf: [256]u8 = undefined;
    const n = read(r.err, &line_buf, line_buf.len);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.indexOf(u8, line_buf[0..@intCast(n)], "left running") == null);
}

const ObserverTest = struct {
    var cap_buf: [96]u8 = undefined;

    fn spawn(talk: c_int) !c_int {
        _ = signal(SIGINT, SIG_DFL);
        const cap_path = try std.fmt.bufPrint(&cap_buf, "/tmp/sideeye-observer-{d}-{d}", .{ getpid(), talk });
        var line_buf: [160]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "printf '%d ' $$ >&{d}; trap 'printf i >&{d}; exit 0' INT; while :; do sleep 0.1; done", .{ talk, talk });
        const pid = spawnSidecar(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, cap_path, null) catch return error.Setup;
        var zb: [96]u8 = undefined;
        _ = unlink((std.fmt.bufPrintZ(&zb, "{s}", .{cap_path}) catch return pid).ptr);
        return pid;
    }

    fn slowStop(sig: c_int) noreturn {
        beginStopping();
        sleepForMs(7_000);
        dieBySignal(sig);
    }

    fn standIn(talk: *[2]c_int, told: *[2]c_int, then: *const fn (observer: c_int, told_w: c_int) void) !c_int {
        if (pipe(talk) != 0 or pipe(told) != 0) return error.Setup;
        const engine = fork();
        if (engine < 0) return error.Setup;
        if (engine == 0) {
            _ = close(talk[0]);
            _ = close(told[0]);
            installInterruptHandlers(InterruptTest.die);
            const observer = spawn(talk[1]) catch _exit(10);
            _ = kill(getpid(), InterruptTest.SIGTERM_);
            _ = write(told[1], "k", 1);
            then(observer, told[1]);
            _exit(0);
        }
        _ = close(talk[1]);
        _ = close(told[1]);
        return engine;
    }

    fn startAChild(_: c_int, told_w: c_int) void {
        var buf: [64]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "printf c >&{d}", .{told_w}) catch return;
        _ = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch {};
    }

    fn observerGone(_: c_int, _: c_int) void {
        noteSidecar(0);
    }

    fn stopEnds(_: c_int, _: c_int) void {
        beginStopping();
        endStopping();
    }

    fn expectEndsAt(then: *const fn (observer: c_int, told_w: c_int) void) !void {
        var talk: [2]c_int = undefined;
        var told: [2]c_int = undefined;
        const engine = try standIn(&talk, &told, then);
        defer _ = close(talk[0]);
        defer _ = close(told[0]);
        const observer = InterruptTest.pidWithin(talk[0]) catch 0;
        defer if (observer != 0) InterruptTest.endGroupIfHeld(observer, talk[0]);
        try std.testing.expectEqual(@as(?u8, 'k'), InterruptTest.byteWithin(told[0], 10_000));
        try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(engine, 10_000));
        try std.testing.expectEqual(@as(?u8, null), InterruptTest.byteWithin(told[0], 0));
    }
};

test "a signal taken while only an observer runs waits for it, and takes effect before the next child starts (#819)" {
    try ObserverTest.expectEndsAt(ObserverTest.startAChild);
}

test "a signal that waited for an observer takes effect when the observer is gone (#819)" {
    try ObserverTest.expectEndsAt(ObserverTest.observerGone);
}

test "a signal taken during a stop takes effect when the stop ends (#819)" {
    try ObserverTest.expectEndsAt(ObserverTest.stopEnds);
}

test "a second signal ends the run even while it is stopping (#819)" {
    const t0 = monotonicMs();
    var ready: [2]c_int = undefined;
    if (pipe(&ready) != 0) return error.Setup;
    const engine = fork();
    if (engine < 0) return error.Setup;
    if (engine == 0) {
        _ = close(ready[0]);
        installInterruptHandlers(ObserverTest.slowStop);
        var buf: [96]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "printf r >&{d}; exec sleep 300", .{ready[1]}) catch _exit(11);
        _ = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch _exit(12);
        _exit(13);
    }
    _ = close(ready[1]);
    defer _ = close(ready[0]);
    try std.testing.expectEqual(@as(?u8, 'r'), InterruptTest.byteWithin(ready[0], 10_000));
    try std.testing.expectEqual(@as(c_int, 0), kill(engine, InterruptTest.SIGTERM_));
    sleepForMs(1_000);
    try std.testing.expectEqual(@as(c_int, 0), kill(engine, InterruptTest.SIGHUP_));
    try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(engine, 15_000));
    try std.testing.expect(monotonicMs() - t0 < 4_500);
}

test "stopping after a signal is not cut short by the grace that was for the child (#819)" {
    const t0 = monotonicMs();
    var err: [2]c_int = undefined;
    var ready: [2]c_int = undefined;
    if (pipe(&err) != 0 or pipe(&ready) != 0) return error.Setup;
    const engine = fork();
    if (engine < 0) return error.Setup;
    if (engine == 0) {
        _ = close(err[0]);
        _ = close(ready[0]);
        if (dup2(err[1], 2) < 0) _exit(10);
        installInterruptHandlers(ObserverTest.slowStop);
        var buf: [96]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "printf r >&{d}; exec sleep 300", .{ready[1]}) catch _exit(11);
        _ = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch _exit(12);
        _exit(13);
    }
    _ = close(err[1]);
    _ = close(ready[1]);
    defer _ = close(err[0]);
    defer _ = close(ready[0]);
    try std.testing.expectEqual(@as(?u8, 'r'), InterruptTest.byteWithin(ready[0], 10_000));
    try std.testing.expectEqual(@as(c_int, 0), kill(engine, InterruptTest.SIGTERM_));
    try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(engine, 15_000));
    try std.testing.expect(monotonicMs() - t0 >= 6_500);
    var line_buf: [256]u8 = undefined;
    const n = read(err[0], &line_buf, line_buf.len);
    try std.testing.expect(n >= 0);
    try std.testing.expect(std.mem.indexOf(u8, line_buf[0..@intCast(n)], "left running") == null);
}

test "a run that ends on its grace stops the observer too (#819)" {
    var talk: [2]c_int = undefined;
    var ready: [2]c_int = undefined;
    if (pipe(&talk) != 0 or pipe(&ready) != 0) return error.Setup;
    const engine = fork();
    if (engine < 0) return error.Setup;
    if (engine == 0) {
        _ = close(talk[0]);
        _ = close(ready[0]);
        InterruptTest.refuseKill();
        installInterruptHandlers(InterruptTest.die);
        _ = ObserverTest.spawn(talk[1]) catch _exit(10);
        var buf: [96]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "printf '%d ' $$ >&{d}; exec sleep 300", .{ready[1]}) catch _exit(11);
        _ = runChild(std.heap.page_allocator, &.{ "/bin/sh", "-c", line }, &.{}, null) catch _exit(12);
        _exit(13);
    }
    _ = close(talk[1]);
    _ = close(ready[1]);
    defer _ = close(talk[0]);
    defer _ = close(ready[0]);
    const observer = try InterruptTest.pidWithin(talk[0]);
    defer InterruptTest.endGroupIfHeld(observer, talk[0]);
    const child = try InterruptTest.pidWithin(ready[0]);
    defer InterruptTest.endGroupIfHeld(child, ready[0]);
    try std.testing.expectEqual(@as(c_int, 0), kill(engine, InterruptTest.SIGTERM_));
    try std.testing.expectEqual(@as(?Term, .{ .signaled = 15 }), InterruptTest.waitWithin(engine, 12_000));
    try std.testing.expectEqual(@as(?u8, 'i'), InterruptTest.byteWithin(talk[0], 3_000));
}

test "exit status decoding distinguishes exit from signal" {
    try std.testing.expectEqual(Term{ .exited = 0 }, decodeStatus(0x0000));
    try std.testing.expectEqual(Term{ .exited = 1 }, decodeStatus(0x0100));
    try std.testing.expectEqual(Term{ .signaled = 9 }, decodeStatus(9));
    try std.testing.expect(decodeStatus(9).isSignal(9));
    try std.testing.expect(!decodeStatus(0x0000).isSignal(9));
}

const FakeWait = struct {
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
        cgroup_make_calls = 0;
        cgroup_join_fails = false;
        cgroup_join_kills_child = false;
        events_len = 0;
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
    /// Delegated, never faked: the capture tests below are about what the real `open`
    /// does with the real flags against a real planted path. A fake answering here
    /// would turn "the kernel refused a symlink" into "the fake said -1", which is the
    /// same vacuity `O_NOFOLLOW actually refuses a symlink` exists to avoid. What
    /// `FakeWait` contributes to those tests is `fork_calls` — the count that says the
    /// refusal happened before the fork.
    const openCapture = RealOps.openCapture;

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

    const waitidPoll = RealOps.waitidPoll;
    fn killGroup(pid: c_int) void {
        event('K');
        RealOps.killGroup(pid);
    }
    const nowMs = RealOps.nowMs;
    const sleepMs = RealOps.sleepMs;

    var cgroup_make_calls: u32 = 0;
    var cgroup_join_fails: bool = false;
    var cgroup_join_kills_child: bool = false;
    var events: [8]u8 = undefined;
    var events_len: usize = 0;
    fn event(e: u8) void {
        if (events_len < events.len) {
            events[events_len] = e;
            events_len += 1;
        }
    }
    fn cgroupMake(cg: *CgroupSpawn) bool {
        _ = cg;
        cgroup_make_calls += 1;
        return true;
    }
    fn cgroupJoin(cg: *CgroupSpawn, pid: c_int) bool {
        _ = cg;
        if (cgroup_join_kills_child) {
            _ = kill(pid, SIGKILL);
            // Until it has exited, not until the signal is sent: a child still alive holds the
            // pipe's read end, and the write the test is about would have a reader.
            var info: std.c.siginfo_t = undefined;
            while (waitid(P_PID, pid, &info, WEXITED | WNOWAIT) < 0 and std.c._errno().* == EINTR) {}
        }
        return !cgroup_join_fails;
    }
    fn cgroupStop(cg: *CgroupSpawn, read_lingering: bool) void {
        _ = cg;
        event(if (read_lingering) 'L' else 'S');
    }
};

test "a wait that fails permanently refuses instead of reporting a clean exit" {
    FakeWait.reset();
    FakeWait.permanent = true;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeWait);

    try std.testing.expectError(error.WaitFailed, r);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.direct_calls);
    try std.testing.expect(FakeWait.drain_calls >= 1);
}

test "an interrupted wait is retried and the status that finally arrives is the one decoded" {
    FakeWait.reset();
    FakeWait.eintr_budget = 3;
    FakeWait.deliver_status = 0x0100; // exit(1)
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeWait);

    try std.testing.expectEqual(Term{ .exited = 1 }, term);
    try std.testing.expectEqual(@as(u32, 4), FakeWait.direct_calls);
}

test "an interruption that never stops is bounded rather than looping forever" {
    FakeWait.reset();
    FakeWait.eintr_budget = std.math.maxInt(u32);
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeWait);

    try std.testing.expectError(error.WaitFailed, r);
    try std.testing.expectEqual(@as(u32, 9), FakeWait.direct_calls);
    try std.testing.expect(FakeWait.drain_calls >= 1);
}

test "a child whose stdin cannot be pointed at /dev/null is refused by name and never forked (#263)" {
    FakeWait.reset();
    FakeWait.devnull_fails = true;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeWait);

    try std.testing.expectError(error.StdinUnavailable, r);
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
    const term = try runChildImplWithOps(std.testing.allocator, &is_null, &.{}, null, false, null, null, null, .kill, FakeWait);
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

/// A scratch directory for the capture tests below, pid-unique because `zig build test`
/// runs the same test in several concurrent binaries and a fixed name passes every
/// single run before failing most paired ones (CLAUDE.md, #28).
const CaptureFixture = struct {
    base: [160]u8 = undefined,
    base_len: usize = 0,

    fn init(self: *CaptureFixture, tag: []const u8) ![:0]const u8 {
        const b = try std.fmt.bufPrintZ(&self.base, "/tmp/sideeye-capture-{s}-{d}", .{ tag, getpid() });
        self.base_len = b.len;
        _ = mkdir(b.ptr, 0o755);
        return b;
    }

    /// Read a whole small file back. `O_NOFOLLOW` is deliberately absent: these tests
    /// assert about the file a link POINTS AT, which is reached by following one.
    fn slurp(path_z: [*:0]const u8, buf: []u8) ![]u8 {
        const fd = open(path_z, O_RDONLY, @as(c_uint, 0));
        if (fd < 0) return error.CouldNotRead;
        defer _ = close(fd);
        const n = read(fd, buf.ptr, buf.len);
        if (n < 0) return error.CouldNotRead;
        return buf[0..@intCast(n)];
    }

    fn writeAt(path_z: [*:0]const u8, bytes: []const u8) !void {
        const fd = open(path_z, O_WRONLY | O_CREAT | O_TRUNC, @as(c_uint, 0o644));
        if (fd < 0) return error.CouldNotWrite;
        defer _ = close(fd);
        if (write(fd, bytes.ptr, bytes.len) != @as(isize, @intCast(bytes.len))) return error.CouldNotWrite;
    }
};

test "a symlink at the capture path is refused before the fork, and what it points at is untouched (#469)" {
    // **`exclusive` is false here, and that is what makes this test about `O_NOFOLLOW`.**
    // Written first with it true, and the mutation that removes `O_NOFOLLOW` survived:
    // POSIX has `O_CREAT|O_EXCL` fail on a symlink too (EEXIST), so `O_EXCL` was
    // answering and the flag under test was never consulted. Non-exclusive is also the
    // shape two production captures actually take — the sudo probe and the group-signal
    // helper both go to `/dev/null` — so this is the configuration that would otherwise
    // have no symlink guard at all.
    var fx: CaptureFixture = .{};
    const base = try fx.init("nofollow");
    var sb: [200]u8 = undefined;
    const sentinel_z = try std.fmt.bufPrintZ(&sb, "{s}/outside", .{base});
    var cb: [200]u8 = undefined;
    const cap_z = try std.fmt.bufPrintZ(&cb, "{s}/capture", .{base});
    defer {
        _ = unlink(cap_z.ptr);
        _ = unlink(sentinel_z.ptr);
        _ = rmdir(base.ptr);
    }

    // Content, not just existence: a test that only asked whether the file still existed
    // would pass against a write that followed the link and truncated it.
    const keep = "bytes that must survive\n";
    try CaptureFixture.writeAt(sentinel_z.ptr, keep);

    // The control first, so the refusal below is about the link and not about this
    // directory, these flags, or this child. Without it, an implementation that failed
    // every capture would satisfy every assertion in the refusal half.
    // `FakeWait.wait` answers from `deliver_status`, which `reset` sets to 0, so the
    // `Term` below is the fake's number and not the child's: what says the child ran
    // and reached its capture is `fork_calls` and the bytes read back. The `Term`
    // assertion is kept as the shape check it is — the call returned a value rather
    // than an error — and named here so it is not mistaken for a measurement.
    const say = [_][]const u8{ "/bin/sh", "-c", "printf hello" };
    FakeWait.reset();
    const ok = try runChildImplWithOps(std.testing.allocator, &say, &.{}, .{ .path = cap_z }, false, null, null, null, .kill, FakeWait);
    try std.testing.expectEqual(Term{ .exited = 0 }, ok);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.fork_calls);
    var rb: [64]u8 = undefined;
    try std.testing.expectEqualStrings("hello", try CaptureFixture.slurp(cap_z.ptr, &rb));

    _ = unlink(cap_z.ptr);
    try std.testing.expect(symlink(sentinel_z.ptr, cap_z.ptr) == 0);

    FakeWait.reset();
    const refused = runChildImplWithOps(std.testing.allocator, &say, &.{}, .{ .path = cap_z }, false, null, null, null, .kill, FakeWait);
    try std.testing.expectError(error.CaptureUnavailable, refused);
    try std.testing.expectEqual(@as(u32, 0), FakeWait.fork_calls);

    // The bytes outside are untouched, which is the whole point. `expectEqualStrings`
    // rather than an existence check: a followed write truncates first and would leave
    // an empty file that still exists.
    var rb2: [64]u8 = undefined;
    try std.testing.expectEqualStrings(keep, try CaptureFixture.slurp(sentinel_z.ptr, &rb2));

    try std.testing.expectEqual(Kind.symlink, try kindOfPathNoFollow(cap_z.ptr));
}

test "a hard link at an exclusive capture path is refused too, and /dev/null still works (#469)" {
    // `O_NOFOLLOW` does nothing here: a hard link is the same file, not a pointer to
    // one, so the test above passes against an implementation that stops at that flag.
    // `O_EXCL` is what refuses this, and it is free wherever the caller unlinks first —
    // which every work-directory capture does.
    var fx: CaptureFixture = .{};
    const base = try fx.init("excl");
    var sb: [200]u8 = undefined;
    const sentinel_z = try std.fmt.bufPrintZ(&sb, "{s}/outside", .{base});
    var cb: [200]u8 = undefined;
    const cap_z = try std.fmt.bufPrintZ(&cb, "{s}/capture", .{base});
    defer {
        _ = unlink(cap_z.ptr);
        _ = unlink(sentinel_z.ptr);
        _ = rmdir(base.ptr);
    }

    const keep = "bytes that must survive\n";
    try CaptureFixture.writeAt(sentinel_z.ptr, keep);
    if (link(sentinel_z.ptr, cap_z.ptr) != 0) return error.SkipZigTest; // no hard links here

    const say = [_][]const u8{ "/bin/sh", "-c", "printf hello" };
    FakeWait.reset();
    const refused = runChildImplWithOps(std.testing.allocator, &say, &.{}, .{ .path = cap_z, .exclusive = true }, false, null, null, null, .kill, FakeWait);
    try std.testing.expectError(error.CaptureUnavailable, refused);
    try std.testing.expectEqual(@as(u32, 0), FakeWait.fork_calls);
    var rb: [64]u8 = undefined;
    try std.testing.expectEqualStrings(keep, try CaptureFixture.slurp(sentinel_z.ptr, &rb));

    // Control A: `/dev/null` always exists, so an implementation that made `exclusive`
    // unconditional would refuse the sudo probe and the group-signal helper — the two
    // production captures that go there — on every run.
    //
    // `fork_calls` is what carries this one. Nothing can be read back from `/dev/null`,
    // and the `Term` comes from the fake's `deliver_status`; the count of 1 is the
    // measurement that the parent did not refuse before forking.
    FakeWait.reset();
    const to_null = try runChildImplWithOps(std.testing.allocator, &say, &.{}, .{ .path = "/dev/null" }, false, null, null, null, .kill, FakeWait);
    try std.testing.expectEqual(Term{ .exited = 0 }, to_null);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.fork_calls);

    // Control B: the same exclusive capture at a name holding nothing succeeds, so the
    // refusal above is about what was at the path and not about `exclusive` itself.
    _ = unlink(cap_z.ptr);
    FakeWait.reset();
    const ok = try runChildImplWithOps(std.testing.allocator, &say, &.{}, .{ .path = cap_z, .exclusive = true }, false, null, null, null, .kill, FakeWait);
    try std.testing.expectEqual(Term{ .exited = 0 }, ok);
    var rb2: [64]u8 = undefined;
    try std.testing.expectEqualStrings("hello", try CaptureFixture.slurp(cap_z.ptr, &rb2));
}

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
        FakeWait.event('K');
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
    const cgroupMake = FakeWait.cgroupMake;
    const cgroupJoin = FakeWait.cgroupJoin;
    const cgroupStop = FakeWait.cgroupStop;
    const forkChild = RealOps.forkChild;
    const openDevNull = RealOps.openDevNull;
    const openCapture = RealOps.openCapture;
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
    FakeBudget.script = &.{ .running, .running };
    FakeBudget.direct_waits = &.{1}; // the grace reap succeeds at once
    FakeBudget.now_step = 100;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 10, null, null, .kill, FakeBudget);

    try std.testing.expectError(error.TimedOut, r);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    try std.testing.expect(FakeBudget.drain_calls >= 1);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "si_pid zero is 'still running', not 'exited': the poll keeps polling until the field names the child (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{ .running, .running, .exited };
    FakeBudget.deliver_status = 0; // exit(0) once the shared reap runs
    FakeBudget.now_step = 1; // deadline 1000 is never approached
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 1000, null, null, .kill, FakeBudget);

    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    try std.testing.expectEqual(@as(usize, 3), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(u32, 2), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "a null budget never touches the budget vocabulary: no clock, no sleep, no poll (#263)" {
    FakeBudget.reset();
    FakeBudget.deliver_status = 0;
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeBudget);

    try std.testing.expectEqual(Term{ .exited = 0 }, term);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.clock_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(usize, 0), FakeBudget.script_i);
}

test "a child the final observation sees exited is accepted, not timed out — the boundary race classifies toward the child (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{ .running, .exited };
    FakeBudget.deliver_status = 0;
    FakeBudget.now_step = 100;
    const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 10, null, null, .kill, FakeBudget);

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
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 1000, null, null, .kill, FakeBudget);

    try std.testing.expectError(error.WaitFailed, r);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(usize, 3), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.sleep_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expect(FakeBudget.drain_calls >= 1);
}

test "an interruption storm cannot poll forever: the ninth consecutive interruption refuses WaitFailed and kills nothing (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{.{ .err = EINTR }};
    FakeBudget.direct_waits = &.{0}; // the one non-blocking reap attempt: nothing there
    FakeBudget.now_step = 1;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 1000, null, null, .kill, FakeBudget);

    try std.testing.expectError(error.WaitFailed, r);
    try std.testing.expectEqual(@as(usize, 9), FakeBudget.script_i);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.kill_calls);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_direct_waits);
    try std.testing.expectEqual(@as(u32, 0), FakeBudget.blocking_group_waits);
}

test "a SIGKILL that never lands exhausts the grace, drains without blocking, and still answers TimedOut (#263)" {
    FakeBudget.reset();
    FakeBudget.script = &.{ .running, .running };
    FakeBudget.direct_waits = &.{ 0, 0, 0, 0, 0, 0, 0, 0 };
    FakeBudget.now_step = 3000;
    const r = runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 10, null, null, .kill, FakeBudget);

    try std.testing.expectError(error.TimedOut, r);
    try std.testing.expectEqual(@as(u32, 1), FakeBudget.kill_calls);
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

test "a contained spawn's cgroup is stopped on every exit, and read for what lingered only where the child ended on its own (v17, #559)" {
    const home: CgroupHome = .{ .dir = "/nonexistent-cgroup-home", .rel = "/" };
    {
        FakeWait.reset();
        var cg = CgroupSpawn.init(home, true) orelse return error.TestUnexpectedResult;
        const term = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, &cg, .kill, FakeWait);
        try std.testing.expectEqual(Term{ .exited = 0 }, term);
        try std.testing.expect(cg.joined);
        try std.testing.expectEqual(@as(u32, 1), FakeWait.cgroup_make_calls);
        try std.testing.expectEqualStrings("LK", FakeWait.events[0..FakeWait.events_len]);
    }
    {
        FakeWait.reset();
        FakeBudget.reset();
        FakeBudget.script = &.{.exited};
        FakeBudget.now_step = 1;
        var cg = CgroupSpawn.init(home, true) orelse return error.TestUnexpectedResult;
        _ = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 1000, null, &cg, .kill, FakeBudget);
        // Read before the kill: the other way round the stop reads an emptied cgroup and
        // names nothing, and the counts above would not notice.
        try std.testing.expectEqualStrings("LK", FakeWait.events[0..FakeWait.events_len]);
    }
    {
        FakeWait.reset();
        FakeBudget.reset();
        FakeBudget.script = &.{ .running, .running };
        FakeBudget.direct_waits = &.{1};
        FakeBudget.now_step = 100;
        var cg = CgroupSpawn.init(home, true) orelse return error.TestUnexpectedResult;
        try std.testing.expectError(error.TimedOut, runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 10, null, &cg, .kill, FakeBudget));
        try std.testing.expectEqualStrings("KS", FakeWait.events[0..FakeWait.events_len]);
    }
    {
        FakeWait.reset();
        FakeBudget.reset();
        FakeBudget.script = &.{.{ .err = FakeWait.ECHILD }};
        var cg = CgroupSpawn.init(home, true) orelse return error.TestUnexpectedResult;
        try std.testing.expectError(error.WaitFailed, runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, 1000, null, &cg, .kill, FakeBudget));
        try std.testing.expectEqualStrings("S", FakeWait.events[0..FakeWait.events_len]);
    }
    {
        FakeWait.reset();
        _ = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, null, .kill, FakeWait);
        try std.testing.expectEqual(@as(u32, 0), FakeWait.cgroup_make_calls);
        try std.testing.expect(std.mem.indexOfAny(u8, FakeWait.events[0..FakeWait.events_len], "LS") == null);
    }
}

test "a child whose move into the run's cgroup fails never runs, and the spawn says why (v17, #559)" {
    const home: CgroupHome = .{ .dir = "/nonexistent-cgroup-home", .rel = "/" };
    var mbuf: [128]u8 = undefined;
    const mark = std.fmt.bufPrintZ(&mbuf, "/tmp/sideeye-cgroup-join-{d}", .{getpid()}) catch unreachable;
    _ = unlink(mark.ptr);
    var cbuf: [160]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cbuf, "touch {s}", .{mark}) catch unreachable;

    FakeWait.reset();
    FakeWait.cgroup_join_fails = true;
    var refused = CgroupSpawn.init(home, false) orelse return error.TestUnexpectedResult;
    try std.testing.expectError(error.CgroupJoinFailed, runChildImplWithOps(std.testing.allocator, &.{ "/bin/sh", "-c", cmd }, &.{}, null, false, null, null, &refused, .kill, FakeWait));
    try std.testing.expect(!refused.joined);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.fork_calls);
    try std.testing.expect(access(mark.ptr, F_OK) != 0);

    // Control: the same spawn with the move succeeding runs the command, so the absence above
    // is the refusal's and not a command that could never have left a mark.
    FakeWait.reset();
    var joined = CgroupSpawn.init(home, false) orelse return error.TestUnexpectedResult;
    _ = try runChildImplWithOps(std.testing.allocator, &.{ "/bin/sh", "-c", cmd }, &.{}, null, false, null, null, &joined, .kill, FakeWait);
    try std.testing.expect(access(mark.ptr, F_OK) == 0);
    _ = unlink(mark.ptr);
}

test "the cgroup2 mount and a process's cgroup are read from what the kernel prints (v17, #559)" {
    const mountinfo =
        "22 28 0:21 / /proc rw,nosuid shared:12 - proc proc rw\n" ++
        "30 25 0:26 / /sys/fs/cgroup rw,nosuid,nodev,noexec,relatime shared:9 - cgroup2 cgroup2 rw,nsdelegate\n";
    try std.testing.expectEqualStrings("/sys/fs/cgroup", cgroup2Mount(mountinfo).?);
    try std.testing.expect(cgroup2Mount("22 28 0:21 / /proc rw,nosuid shared:12 - proc proc rw\n") == null);
    try std.testing.expect(cgroup2Mount("30 25 0:26 /user.slice /sys/fs/cgroup rw shared:9 - cgroup2 cgroup2 rw\n") == null);
    try std.testing.expectEqualStrings("/user.slice/session-2.scope", cgroup2Path("0::/user.slice/session-2.scope\n").?);
    try std.testing.expect(cgroup2Path("12:memory:/x\n") == null);
}

test "a spawn's cgroup is named under the engine's, in both spellings (v17, #559)" {
    const cg = CgroupSpawn.init(.{ .dir = "/sys/fs/cgroup/a", .rel = "/a" }, true) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, cg.dir(), "/sys/fs/cgroup/a/sideeye-"));
    try std.testing.expect(std.mem.startsWith(u8, cg.relPath(), "/a/sideeye-"));
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s}/work", .{cg.dir()}), cg.workDir());
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s}/cgroup.kill", .{cg.workDir()}), cg.killPath());
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "{s}/cgroup.procs", .{cg.dir()}), cg.asidePath());
    const at_root = CgroupSpawn.init(.{ .dir = "/sys/fs/cgroup", .rel = "/" }, false) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, at_root.relPath(), "/sideeye-"));
}

test "a process's state is read after the last parenthesis, whatever its name holds (v17, #559)" {
    try std.testing.expectEqual(@as(?u8, 'S'), statState("123 (bash) S 1 123 123 0 -1"));
    try std.testing.expectEqual(@as(?u8, 'Z'), statState("7 (a) b) (c) Z 1 7 7"));
    try std.testing.expectEqual(@as(?u8, null), statState("7 (truncated"));
    try std.testing.expectEqual(@as(?u8, null), statState("7 (x)"));
    if (builtin.os.tag == .linux) {
        const own = processState(@intCast(getpid())) orelse return error.TestUnexpectedResult;
        try std.testing.expect(own != 'Z' and own != 'X' and own != '?');
        try std.testing.expectEqual(@as(?u8, null), processState(std.math.maxInt(u32)));
    }
}

test "a child that dies before its go-ahead does not take the engine down with a write to a pipe nobody reads (v17, #559)" {
    FakeWait.reset();
    FakeWait.cgroup_join_kills_child = true;
    // At its default, as the engine meets it started from a shell: a disposition inherited from
    // whatever ran this test binary would make the write fail quietly and the test vacuous.
    const sigpipe: c_int = 13; // Linux and Darwin alike
    const previous = signal(sigpipe, SIG_DFL);
    defer _ = signal(sigpipe, previous);
    const home: CgroupHome = .{ .dir = "/nonexistent-cgroup-home", .rel = "/" };
    var cg = CgroupSpawn.init(home, false) orelse return error.TestUnexpectedResult;
    _ = try runChildImplWithOps(std.testing.allocator, &.{"true"}, &.{}, null, false, null, null, &cg, .kill, FakeWait);
    try std.testing.expect(cg.joined);
    try std.testing.expectEqual(@as(u32, 1), FakeWait.fork_calls);
}
