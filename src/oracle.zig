//! Completeness oracle: read strace's view of the recording run and hold the shim's
//! trace against it.
//!
//! The shim replaces libc symbols; strace watches syscalls. A program that issues
//! syscalls directly — or through a libc entry point nobody thought to interpose —
//! is invisible to the first and plain to the second. Without this comparison, such a
//! target produces an empty trace that is indistinguishable from "performed no file
//! operations", and the honest-looking answer to that is PASS.
//!
//! The two views have different granularity, so they are compared after normalising
//! syscalls to the same `OpClass` the shim records. What is compared is the class
//! sequence, not the raw text.

const std = @import("std");
const contract = @import("contract");

pub const Finding = union(enum) {
    /// The oracle saw an operation on the state directory that the shim did not.
    missed: struct { index: usize, class: contract.OpClass },
    /// A syscall touching the state directory that v0.1 does not model at all.
    unsupported: []const u8,
    /// The shim recorded something the oracle did not: the shim is over-counting.
    phantom: struct { index: usize, class: contract.OpClass },
};

const Mapping = struct { name: []const u8, class: contract.OpClass };

/// syscall -> op class. The list is deliberately explicit: anything touching the state
/// directory that is not here becomes `unsupported`, which is UNKNOWN rather than a
/// silent omission.
const known = [_]Mapping{
    .{ .name = "openat", .class = .open },
    .{ .name = "openat2", .class = .open },
    .{ .name = "open", .class = .open },
    .{ .name = "creat", .class = .open },
    .{ .name = "write", .class = .write },
    .{ .name = "pwrite64", .class = .write },
    .{ .name = "pwrite", .class = .write },
    .{ .name = "writev", .class = .write },
    .{ .name = "pwritev", .class = .write },
    .{ .name = "pwritev2", .class = .write },
    // The kernel's copy primitives (#244). Their EFFECT on the destination is a
    // write — the bytes change, nothing else does — so they take `.write` rather
    // than a class of their own; `link` and `symlink` earned new classes because
    // they create directory entries, which is a different effect. Both are fd
    // syscalls, and `copy_file_range` is the one whose destination is not argument
    // 0 (see `fd_write_args`).
    .{ .name = "copy_file_range", .class = .write },
    .{ .name = "sendfile", .class = .write },
    .{ .name = "sendfile64", .class = .write },
    .{ .name = "rename", .class = .rename },
    .{ .name = "renameat", .class = .rename },
    .{ .name = "renameat2", .class = .rename },
    .{ .name = "unlink", .class = .unlink },
    .{ .name = "unlinkat", .class = .unlink },
    .{ .name = "fsync", .class = .fsync },
    .{ .name = "fdatasync", .class = .fsync },
    .{ .name = "truncate", .class = .truncate },
    .{ .name = "ftruncate", .class = .truncate },
    .{ .name = "ftruncate64", .class = .truncate },
    .{ .name = "mkdir", .class = .mkdir },
    .{ .name = "mkdirat", .class = .mkdir },
    .{ .name = "rmdir", .class = .rmdir },
    .{ .name = "link", .class = .link },
    .{ .name = "linkat", .class = .link },
    .{ .name = "symlink", .class = .symlink },
    .{ .name = "symlinkat", .class = .symlink },
    .{ .name = "close", .class = .close },
};

/// One path argument of a syscall: the index of its path string, and the index of the
/// directory descriptor it is resolved against (null for a legacy form, which resolves
/// against the tracked cwd).
const PathArg = struct { dirfd: ?usize, path: usize };

/// Which arguments of a path syscall name a filesystem path, so scope is decided from
/// resolved paths and never from a whole-line scan (ADR 0006). A syscall absent from
/// this table and from `fd_syscalls` falls to the conservative whole-line net, which
/// only ever routes to `unsupported`.
///
/// The link *content* of `symlink`/`symlinkat` is deliberately not listed: it is a
/// string the target chose, not a path this run touches, and resolving it would let a
/// link whose content spells the state directory be mis-scoped.
const PathSpec = struct { name: []const u8, args: []const PathArg };
const path_syscalls = [_]PathSpec{
    // *at single-path
    .{ .name = "openat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "openat2", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "mkdirat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "unlinkat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "symlinkat", .args = &.{.{ .dirfd = 1, .path = 2 }} },
    // *at two-path
    .{ .name = "renameat", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    .{ .name = "renameat2", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    .{ .name = "linkat", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    // legacy single-path
    .{ .name = "open", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "creat", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "mkdir", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "rmdir", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "unlink", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "truncate", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "symlink", .args = &.{.{ .dirfd = null, .path = 1 }} },
    // legacy two-path
    .{ .name = "rename", .args = &.{ .{ .dirfd = null, .path = 0 }, .{ .dirfd = null, .path = 1 } } },
    .{ .name = "link", .args = &.{ .{ .dirfd = null, .path = 0 }, .{ .dirfd = null, .path = 1 } } },
};

fn pathSpec(name: []const u8) ?PathSpec {
    for (path_syscalls) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

/// Ownership and permission writes (#121, option b): METADATA the contract
/// deliberately does not judge. The judged state is names, bytes and link targets;
/// these syscalls change none of them, so they are observed and EXCLUDED — from the
/// class comparison (the shim does not interpose them), from kill points, from
/// `unsupported`, and from the child-touch condition. The exclusion is declared per
/// run in the report rather than silently: sqlite fchowns its rollback journal on
/// every write when running as root, and devtodo fchmodats every database rewrite —
/// both measured as whole-target refusals in the #118 cohort before this landed.
const metadata_path_syscalls = [_]PathSpec{
    .{ .name = "chown", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "lchown", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "chmod", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "fchownat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "fchmodat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    // Linux 6.6+: glibc 2.39 issues fchmodat2 for fchmodat(3) with flags != 0.
    // Same signature shape (dirfd, path, mode, flags). Listed from the syscall
    // family, not from what a cohort happened to hit — leaving it out would
    // re-block the exact class #121 unblocks on any newer runner (R1).
    .{ .name = "fchmodat2", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    // The timestamp family (#190, owner-ruled 2026-08-21). This list once said
    // "deliberately absent: widening is its own decision, not a side effect" —
    // the decision came due when the cohort-2 Mercurial explore refused on the
    // single utimensat CPython's shutil issues per transaction-backup copy.
    // Timestamps change none of the judged state (names, bytes, link targets),
    // exactly like ownership and permission; the whole family is listed, not
    // just the spelling one cohort hit. glibc emits futimens as utimensat with
    // a NULL path — that resolves to `.unresolvable`, which counts as observed
    // EVEN when the descriptor points outside the state directory: the note
    // over-reports rather than scoping through the fd, the same honest
    // direction #121 chose for every unresolvable metadata write.
    .{ .name = "utimensat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "futimesat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "utimes", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "utime", .args = &.{.{ .dirfd = null, .path = 0 }} },
};
/// The fd-addressed forms, scoped from the descriptor annotation like every fd
/// syscall (a state path inside some other argument must not scope them in).
const metadata_fd_syscalls = [_][]const u8{ "fchown", "fchmod" };

fn metadataPathSpec(name: []const u8) ?PathSpec {
    for (metadata_path_syscalls) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

fn isMetadataFd(name: []const u8) bool {
    for (metadata_fd_syscalls) |m| {
        if (std.mem.eql(u8, m, name)) return true;
    }
    return false;
}

/// A syscall whose only filesystem target is a descriptor: scope is read from the `<fd>`
/// annotation and never from the quoted arguments — a state-directory string inside a
/// write buffer must not count as touching the state directory (ADR 0006).
///
/// Derived rather than listed: a classified syscall with no path argument (write, fsync,
/// close, ftruncate) is exactly an fd syscall. This makes the "only unknown syscalls
/// reach the whole-line net" invariant structural — every classified syscall is either a
/// path syscall or an fd syscall, so nothing the net scopes in can ever be counted.
fn isFdSyscall(name: []const u8) bool {
    return classify(name) != null and pathSpec(name) == null;
}

/// Syscalls that read but never change anything on disk. They are not operations
/// sideeye can crash between in any meaningful sense, and counting them would make the
/// two views disagree for no reason.
///
/// `flock` belongs here even though it is not a read: advisory locks live in the kernel
/// and die with the process, so no crash world can be told apart by one. Found by
/// measurement — the first real target to clear the boundary gate (omamori) stopped
/// here instead, on the lock it takes around its audit log.
const read_only = [_][]const u8{
    "stat",      "lstat",     "fstat",    "newfstatat", "statx",
    "access",    "faccessat", "readlink", "readlinkat", "read",
    "pread64",   "readv",     "lseek",    "getdents64", "fcntl",
    "fadvise64", "statfs",    "fstatfs",  "dup",        "dup2",
    "dup3",      "ioctl",     "mmap",     "munmap",     "mprotect",
    "flock",
    // `getcwd` reads the working directory and changes nothing; it reaches this list
    // rather than the path table because it has no path *argument* — its result is a
    // string the conservative net would otherwise scope in once the cwd is inside the
    // state directory (a relative-spelling target does exactly that).
        "getcwd",
    // `chdir` and `fchdir` move the CALLING PROCESS's working directory and change no
    // byte and no directory entry (v15). They are here for the same reason `getcwd` is,
    // and the omission had a cost that only showed once a child's operations could be
    // judged: the conservative net — "everything that is not a read is a child touching
    // what only the subject may" — counted a child's `chdir` into the judged directory as
    // a touch. Measured on `pass mv`, whose `git -C <store> rev-parse
    // --is-inside-work-tree` reads and writes nothing: the run refused for that `chdir`,
    // naming a process that "mutated the judged directory". It did not.
    //
    // The subject's own `chdir` never reaches this list — it is handled above, where a
    // successful one moves the cwd this reader resolves relative paths against.
       "chdir",    "fchdir",
};

/// Syscalls that cross a process boundary.
///
/// The shim interposes the libc wrappers for these, but `clone`, `clone3` and a raw
/// `syscall(SYS_clone, …)` go straight past it. The oracle sees them regardless — and
/// since v3 a boundary is no longer an automatic refusal: what decides is whether any
/// process other than the subject touched the state directory. The exceptions that stay
/// hard refusals are the subject replacing its own image (a second `execve` on the
/// primary pid: the crash-point address space does not survive an image change) and
/// `unshare` (namespace surgery this tool does not model).
const process_syscalls = [_][]const u8{
    "clone", "clone3", "fork", "vfork", "execve", "execveat", "unshare",
};

/// Strip the process identifier strace prefixes each line with under `-f`.
///
/// There are two spellings and they are not interchangeable. Writing to a file
/// (`-f -o out`) produces `1234  openat(…)`; interleaved output on a terminal produces
/// `[pid  1234] openat(…)`. Handling only the bracketed form — which is the one that
/// gets written about — silently defeats every syscall-name lookup, and the failure
/// surfaces as the oracle claiming the shim invented operations.
fn stripPidPrefix(line: []const u8) []const u8 {
    if (std.mem.startsWith(u8, line, "[pid")) {
        const close = std.mem.indexOfScalar(u8, line, ']') orelse return line;
        return std.mem.trimStart(u8, line[close + 1 ..], " \t");
    }
    var i: usize = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
    // A bare number followed by whitespace: no syscall is spelled that way.
    if (i > 0 and i < line.len and (line[i] == ' ' or line[i] == '\t')) {
        return std.mem.trimStart(u8, line[i..], " \t");
    }
    return line;
}

/// The pid the same prefix carries, or null when the line has none.
///
/// v0.1 threw this away, which was fine while any second process was an automatic
/// refusal. Deciding whether a boundary is *tolerable* is a question about who did
/// what, and the pid is the only "who" the oracle has.
fn pidOf(line: []const u8) ?u32 {
    var s = line;
    if (std.mem.startsWith(u8, s, "[pid")) {
        s = std.mem.trimStart(u8, s["[pid".len..], " \t");
    }
    var i: usize = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
    if (i == 0) return null;
    if (i < s.len and (s[i] == ' ' or s[i] == '\t' or s[i] == ']')) {
        return std.fmt.parseInt(u32, s[0..i], 10) catch null;
    }
    return null;
}

fn syscallName(raw: []const u8) ?[]const u8 {
    const line = stripPidPrefix(raw);
    const paren = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    const name = line[0..paren];
    if (name.len == 0) return null;
    for (name) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return null;
    }
    return name;
}

/// Which child a process-creating line reports having created, or null (v15).
///
/// The window a writing child is judged in starts here rather than at its first write.
/// Between the two, the parent is running with the child already alive: a mutation of its
/// own in that gap is ordered against the child's by nothing, and would be admitted if the
/// window began at the child's first operation. `spike/followup-item3/NOTES.md` recorded
/// that counterexample the day before this was written and the first implementation
/// shipped past it — review caught it.
///
/// `fork` and `posix_spawn` both reach the kernel as `clone` on Linux, and the resumed
/// spelling appears whenever the child's own lines interleave with the call (measured: the
/// committed `inv-todoman` capture, where the child's first line precedes the resumption
/// that names it).
fn spawnedPid(raw: []const u8) ?u64 {
    const line = stripPidPrefix(raw);
    const family = [_][]const u8{ "clone", "clone3", "fork", "vfork" };
    var is_spawn = false;
    if (std.mem.startsWith(u8, line, "<... ")) {
        const rest = line["<... ".len..];
        const end = std.mem.indexOf(u8, rest, " resumed>") orelse return null;
        for (family) |f| {
            if (std.mem.eql(u8, rest[0..end], f)) is_spawn = true;
        }
    } else {
        for (family) |f| {
            if (std.mem.startsWith(u8, line, f) and line.len > f.len and line[f.len] == '(') is_spawn = true;
        }
    }
    if (!is_spawn) return null;
    // A thread is not a child to be waited for; counting its creation as a window would be
    // reading the wrong event. This catches the one-line form only — a split clone's
    // flags are on the unfinished half and its number on the resumed half, and the
    // caller pairs those through `pending_thread_clone` before asking here (v16).
    if (std.mem.indexOf(u8, line, "CLONE_THREAD") != null) return null;
    return returnedPid(line);
}

/// Which child a wait-family line reports having been reaped, or null (v15).
///
/// Its own parser rather than `syscallName` plus a suffix, for two reasons the real
/// captures show. A wait that another child's exit interrupted comes back as
/// `<... wait4 resumed>…) = 29`, and `syscallName` answers null for that line — the first
/// `(` it finds is inside `WIFEXITED(s)`, whose prefix is not a name. And `waitid` reports
/// the reaped child in its siginfo (`si_pid=`) while returning 0, so the return value is
/// the wrong field to read for that one member of the family.
///
/// A pid here means "somebody waited for this process and collected it". It is not a
/// claim that the waiter was blocked while the child ran: the real captures show a shell
/// blocking in `wait4` for a foreground command and reaping a pipeline stage with
/// `WNOHANG` afterwards, and the second shape is common enough that treating it as a
/// refusal would refuse `pass`. `spike/followup-item3/NOTES.md` measured both.
fn reapedPid(raw: []const u8) ?u64 {
    const line = stripPidPrefix(raw);
    const family = [_][]const u8{ "wait4", "waitid", "wait3", "waitpid" };
    var is_wait = false;
    if (std.mem.startsWith(u8, line, "<... ")) {
        const rest = line["<... ".len..];
        const end = std.mem.indexOf(u8, rest, " resumed>") orelse return null;
        for (family) |f| {
            if (std.mem.eql(u8, rest[0..end], f)) is_wait = true;
        }
    } else {
        for (family) |f| {
            if (std.mem.startsWith(u8, line, f) and line.len > f.len and line[f.len] == '(') is_wait = true;
        }
    }
    if (!is_wait) return null;

    // **A pid coming back is not a collection.** Two shapes return one without reaping it,
    // and both would close a window early — which admits a run that should refuse, the
    // direction that matters:
    //
    //   `wait4(-1, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTSTP}], WUNTRACED, …) = 53`
    //   `waitid(P_PID, 53, {…si_pid=53…}, WEXITED|WNOWAIT, …) = 0`
    //
    // The first reports a child that stopped and is still alive; the second asks for the
    // status and leaves the child reapable. So a status, where the line carries one, has
    // to say the child ended, and `WNOWAIT` disqualifies the line whatever the status
    // says. A line with no status field at all falls through to the return value, which is
    // the shape `wait4(pid, NULL, 0, NULL) = pid` has — nothing there says "stopped", and
    // a caller passing no status buffer has no way to see one either.
    //
    // Before the siginfo read below, not after it: that is where `waitid` answers, so a
    // check placed after it would never see a `waitid` line.
    if (std.mem.indexOf(u8, line, "WNOWAIT") != null) return null;
    if (std.mem.indexOf(u8, line, "WIFSTOPPED") != null or
        std.mem.indexOf(u8, line, "WIFCONTINUED") != null) return null;
    if (std.mem.indexOf(u8, line, "CLD_STOPPED") != null or
        std.mem.indexOf(u8, line, "CLD_CONTINUED") != null or
        std.mem.indexOf(u8, line, "CLD_TRAPPED") != null) return null;

    // `waitid`'s answer, when it has one. Read before the return value because that one
    // is 0 on success and says nothing about which child it was.
    if (std.mem.indexOf(u8, line, "si_pid=")) |at| {
        const tail = line[at + "si_pid=".len ..];
        var end: usize = 0;
        while (end < tail.len and std.ascii.isDigit(tail[end])) end += 1;
        if (end > 0) return std.fmt.parseInt(u64, tail[0..end], 10) catch null;
    }

    // The return value, for the rest of the family. `= -1 ECHILD` and
    // `= ? ERESTARTSYS` both fail to parse, which is the answer: nothing was reaped.
    const at = std.mem.lastIndexOf(u8, line, " = ") orelse return null;
    const tail = std.mem.trim(u8, line[at + 3 ..], " \t");
    var end: usize = 0;
    while (end < tail.len and std.ascii.isDigit(tail[end])) end += 1;
    if (end == 0) return null;
    const v = std.fmt.parseInt(u64, tail[0..end], 10) catch return null;
    return if (v == 0) null else v;
}

/// Note an event. Duplicates are kept deliberately: two operations by one process are two
/// positions, and the ordering rule reads positions.
pub fn noteEvent(arena: std.mem.Allocator, list: *std.ArrayList(Event), id: u64, at: usize) !void {
    try list.append(arena, .{ .id = id, .at = at });
}

/// Whether any event in the list carries this id.
pub fn holdsId(list: []const Event, id: u64) bool {
    for (list) |e| {
        if (e.id == id) return true;
    }
    return false;
}

/// Is this the kernel refusing a syscall under a seccomp filter?
///
/// `--observe syscalls` traps the write family with `SECCOMP_RET_TRAP`, so a write the
/// target issued reaches this reader twice: the refused entry, and the handler's re-issue
/// carrying the sentinel. Only the second one ran. strace prints the signal without being
/// asked — `-e trace=` filters syscalls, not signals — so the flags the engine already
/// passes carry it, measured in `spike/followup-trapwitness/`:
///
///   `14    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_call_addr=0x…, si_syscall=__NR_write, si_arch=…} ---`
///
/// `syscallName` answers null for this shape, so the read has to happen before the name
/// test, beside the reap and spawn readers.
///
/// `si_code` is the discriminator rather than `si_syscall`: a SIGSYS from anywhere else
/// says nothing about a call this reader appended, while the syscall name could only ever
/// repeat what the append side already established — the entry a refusal retracts was
/// restricted to the trapped family when it was recorded, and no filter in this tool traps
/// anything else. An older strace that spells `si_syscall` as a bare number is read the
/// same way here, because the name was never what the decision rested on.
fn isSeccompRefusal(raw: []const u8) bool {
    const line = stripPidPrefix(raw);
    if (!std.mem.startsWith(u8, line, "--- SIGSYS ")) return false;
    return std.mem.indexOf(u8, line, "si_code=SYS_SECCOMP") != null;
}

/// The syscalls `--observe syscalls` traps, spelled as strace prints them.
///
/// The shim builds a BPF program and this reader parses text, so there is no declaration
/// for the two to share and this is a copy. **The standing drift detector is
/// `spike/check-shim-coverage.py`**, which reads both lists from the code that uses them
/// and compares them in both directions; it runs in CI and inside the acceptance suite.
/// Without it the two failure modes are unequal: a member missing here costs a retraction
/// that should have happened, which the completeness comparison refuses on loudly but in a
/// place that names neither list — while a member here that the filter does not trap is
/// silent, because nothing ever raises the signal that would use it.
fn isTrappedWrite(name: []const u8) bool {
    const family = [_][]const u8{ "write", "pwrite64", "writev", "pwritev" };
    for (family) |f| {
        if (std.mem.eql(u8, name, f)) return true;
    }
    return false;
}

/// A write this reader appended that the kernel may not have executed.
///
/// One per process, because the refused call and its signal are not adjacent in the file:
/// another process's lines fall between them freely (measured — see
/// `spike/followup-trapwitness/artifacts/trapped-children.txt`). What cannot fall between
/// them is another line from the SAME process, which is stopped waiting for the signal to
/// be delivered; the refused call's own `<... write resumed>` may, and has no name for
/// `syscallName` to return, so it never reaches the clearing point.
/// The pid is the one `pidOf` read from the line that appended, and the refusal has to
/// carry the same one. A capture whose prefixes appear part-way through — strace omits
/// them while one process runs and starts printing them when a second appears — would set
/// an entry under `null` and offer a numbered refusal for it, so the retraction would not
/// happen. That is the existing fragility of reading pids from prefixes rather than a new
/// one, and it is loud where it lands: the un-retracted entry leaves the oracle one
/// operation ahead and the comparison refuses `oracle_missed_operation`.
const PendingWrite = struct {
    pid: ?u32,
    /// Index into `classes`/`names`/`lines`, or null for a child's write, which only ever
    /// reached `mutations`.
    op: ?usize,
    /// Index into `mutations`, or null where the line carried no pid to attribute it to.
    mutation: ?usize,
};

/// Take this process's pending write out of the list, if it has one.
fn takePending(list: *std.ArrayList(PendingWrite), pid: ?u32) ?PendingWrite {
    for (list.items, 0..) |it, i| {
        // `==` on two optionals is the comparison this needs, `null` to `null` included.
        if (it.pid == pid) return list.swapRemove(i);
    }
    return null;
}

/// Record a write this process may not have executed.
///
/// A plain append, and it stays one: the window-closing `takePending` runs on every line
/// that reaches an append site, so this process has no entry by the time it gets here. An
/// earlier version took first, which was dead code that read as though two entries for one
/// process were reachable.
fn setPending(arena: std.mem.Allocator, list: *std.ArrayList(PendingWrite), w: PendingWrite) !void {
    try list.append(arena, w);
}

/// Rebuild the lists without the retracted entries, once, at the end of the parse.
///
/// Removing an entry the moment its refusal was read would have been wrong: every index
/// another process's pending write holds shifts under it, and the interleaving that makes
/// that possible is in the measured capture. Indices stay stable for the whole parse and
/// the lists are compacted here. `classes`, `names` and `lines` share one mask because
/// they are index-aligned and must stay so (#337).
fn dropRetracted(arena: std.mem.Allocator, out: *Parsed, dead_ops: []const usize, dead_muts: []const usize) !void {
    if (dead_ops.len != 0) {
        const keep = try arena.alloc(bool, out.classes.items.len);
        @memset(keep, true);
        for (dead_ops) |i| {
            // Every index here was `classes.items.len - 1` when it was recorded and the
            // list only grows, so an out-of-range one is a bookkeeping bug. Skipping it
            // would drop the retraction while `lines_in_scope` had already been decremented
            // for it — the count and the list would disagree, and nothing would say so.
            std.debug.assert(i < keep.len);
            keep[i] = false;
        }
        var w: usize = 0;
        for (keep, 0..) |k, i| {
            if (!k) continue;
            out.classes.items[w] = out.classes.items[i];
            out.names.items[w] = out.names.items[i];
            out.lines.items[w] = out.lines.items[i];
            w += 1;
        }
        out.classes.shrinkRetainingCapacity(w);
        out.names.shrinkRetainingCapacity(w);
        out.lines.shrinkRetainingCapacity(w);
    }
    if (dead_muts.len != 0) {
        const keep = try arena.alloc(bool, out.mutations.items.len);
        @memset(keep, true);
        for (dead_muts) |i| {
            std.debug.assert(i < keep.len);
            keep[i] = false;
        }
        var w: usize = 0;
        for (keep, 0..) |k, i| {
            if (!k) continue;
            out.mutations.items[w] = out.mutations.items[i];
            w += 1;
        }
        out.mutations.shrinkRetainingCapacity(w);
    }
}

fn isProcessSyscall(name: []const u8) bool {
    for (process_syscalls) |p| {
        if (std.mem.eql(u8, p, name)) return true;
    }
    return false;
}

/// True when any path mentioned on the line lies inside the state directory.
///
/// Paths appear two ways in `strace -y` output: quoted arguments, and descriptor
/// annotations like `3</tmp/state/key.json>`. Both are checked with the same
/// component-boundary containment test the shim uses, so `/tmp/state2` is not mistaken
/// for something inside `/tmp/state`.
fn touchesStateDir(line: []const u8, state_dir: []const u8, alt: []const u8) bool {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const open_ch = line[i];
        if (open_ch != '"' and open_ch != '<') continue;
        const close_ch: u8 = if (open_ch == '"') '"' else '>';
        const rest = line[i + 1 ..];
        const end = std.mem.indexOfScalar(u8, rest, close_ch) orelse break;
        const candidate = rest[0..end];
        if (candidate.len > 0 and candidate[0] == '/' and insideEither(candidate, state_dir, alt)) return true;
        i += end + 1;
    }
    return false;
}

/// The `index`th top-level argument of a syscall line, or null.
///
/// Arguments are separated by commas at depth zero. Quoted strings are skipped whole and
/// bracketed groups are counted, so neither a comma inside a filename nor a struct
/// argument splits the list. Reading a field this way rather than searching the whole
/// line is what keeps a *filename* from being read as a *flag*.
fn syscallArg(raw: []const u8, index: usize) ?[]const u8 {
    const line = stripPidPrefix(raw);
    const open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    var i = open + 1;
    var start = i;
    var arg: usize = 0;
    var depth: usize = 0;
    while (i < line.len) : (i += 1) {
        switch (line[i]) {
            '"' => {
                i += 1;
                while (i < line.len) : (i += 1) {
                    if (line[i] == '\\') {
                        i += 1; // strace escapes quotes and backslashes inside strings
                        continue;
                    }
                    if (line[i] == '"') break;
                }
            },
            '[', '{', '<' => depth += 1,
            ']', '}', '>' => {
                if (depth > 0) depth -= 1;
            },
            ',' => if (depth == 0) {
                if (arg == index) return std.mem.trim(u8, line[start..i], " \t");
                arg += 1;
                start = i + 1;
            },
            ')' => if (depth == 0) {
                if (arg == index) return std.mem.trim(u8, line[start..i], " \t");
                return null;
            },
            else => {},
        }
    }
    // An unfinished call has no closing parenthesis: strace printed ` <unfinished ...>`
    // where the rest of the line would have gone, because another task's line landed
    // inside the call. The argument being read when the line ran out is whole — strace
    // prints arguments entire — so it is returned the way a `)` would have returned it.
    // Measured (BUILDLOG 2026-09-08): `fsync(4</tmp/s/k> <unfinished ...>` is the shape,
    // and under a second thread it is the shape of every call with one argument; before
    // this arm the oracle's list had no `fsync` and the run refused
    // `oracle_missed_operation` with all seven of the shim's records present.
    if (arg == index) {
        if (std.mem.lastIndexOf(u8, line, "<unfinished ...>")) |uf| {
            if (uf >= start) return std.mem.trim(u8, line[start..uf], " \t");
        }
    }
    return null;
}

/// The value after the last ` = ` on a line, or null where there is none or it is not a
/// non-negative number — the shape a successful `clone` returns its child (or thread) in.
/// Shared by `spawnedPid` and the thread-clone reader so the two cannot disagree about
/// where the number is.
fn returnedPid(line: []const u8) ?u64 {
    const at = std.mem.lastIndexOf(u8, line, " = ") orelse return null;
    const tail = std.mem.trim(u8, line[at + 3 ..], " \t");
    var end: usize = 0;
    while (end < tail.len and std.ascii.isDigit(tail[end])) end += 1;
    if (end == 0) return null;
    const v = std.fmt.parseInt(u64, tail[0..end], 10) catch return null;
    return if (v == 0) null else v;
}

/// Whether this is the `<... clone resumed>` half of a split clone line. The flags live
/// on the other half, so which kind of clone it was has to have been remembered.
fn isResumedClone(raw: []const u8) bool {
    const line = stripPidPrefix(raw);
    if (!std.mem.startsWith(u8, line, "<... ")) return false;
    const rest = line["<... ".len..];
    const end = std.mem.indexOf(u8, rest, " resumed>") orelse return false;
    return std.mem.eql(u8, rest[0..end], "clone") or std.mem.eql(u8, rest[0..end], "clone3");
}

/// `AT_REMOVEDIR` as Linux spells it.
///
/// A hardcoded platform constant is what made the shim disagree with itself across
/// operating systems, so it is worth saying why one is right here: this file parses
/// `strace` output, `strace` exists only on Linux, and the number therefore cannot be
/// read on a platform where it means something else.
const at_removedir_linux: u64 = 0x200;

/// True when an `unlinkat` line asks for a directory removal.
///
/// `unlinkat` is two operations wearing one name, and which one it is decides whether the
/// two views agree: aarch64 Linux has no `rmdir` syscall, so glibc implements `rmdir(3)`
/// as `unlinkat(AT_REMOVEDIR)`. The shim interposes the libc entry point and records
/// `.rmdir`; a name-only mapping here would say `.unlink`, diverge positionally, and
/// report UNKNOWN for a target that did nothing wrong.
fn unlinkatRemovesDir(line: []const u8) bool {
    const flags = syscallArg(line, 2) orelse return false;
    if (std.mem.indexOf(u8, flags, "AT_REMOVEDIR") != null) return true;
    // `strace -X raw`, and some builds, print the flags as a number.
    const v = std.fmt.parseInt(u64, flags, 0) catch return false;
    return (v & at_removedir_linux) != 0;
}

/// `renameat2` flag bits (Linux). Named here because the check below has to read the
/// number as well as the symbol.
const rename_exchange: u64 = 2;
const rename_whiteout: u64 = 4;

/// Whether `renameat2`'s flags argument carries one of the two that make it something
/// other than a rename. Reads argument 4 rather than the line, so a FILENAME spelling
/// a flag cannot refuse a plain rename — and falls back to the number, because
/// `strace -X raw` and undecorated builds print `0x2` where a decoding strace prints
/// `RENAME_EXCHANGE`. Reading only the symbol would fail OPEN there: the shim does not
/// record these, so the run would end at `oracle_missed_operation` with a reason that
/// names the wrong problem. `unlinkatRemovesDir` above has carried the same pair of
/// readings since AT_REMOVEDIR.
fn renameat2Flag(line: []const u8, symbol: []const u8, bit: u64) bool {
    const flags = syscallArg(line, 4) orelse return false;
    if (std.mem.indexOf(u8, flags, symbol) != null) return true;
    const v = std.fmt.parseInt(u64, std.mem.trim(u8, flags, " "), 0) catch return false;
    return (v & bit) != 0;
}

fn classify(name: []const u8) ?contract.OpClass {
    for (known) |m| {
        if (std.mem.eql(u8, m.name, name)) return m.class;
    }
    return null;
}

fn isReadOnly(name: []const u8) bool {
    for (read_only) |r| {
        if (std.mem.eql(u8, r, name)) return true;
    }
    return false;
}

/// True when the `index`th argument exists and contains `needle`.
///
/// The needle is always searched inside one argument, never across the line: a
/// *filename* is attacker-controlled in the only sense that matters here (the target
/// chooses it), and a file called `O_CREAT.bak` or `PROT_WRITE.log` must not change how
/// the syscall around it is classified. Same rule, same reason as `unlinkatRemovesDir`.
fn argContains(line: []const u8, index: usize, needle: []const u8) bool {
    const a = syscallArg(line, index) orelse return false;
    return std.mem.indexOf(u8, a, needle) != null;
}

/// An open that cannot change state, judged from the flags argument — the textual half
/// of `openIsWriteCapable` (shim/src/common.zig, ADR 0003). The two must stay in
/// agreement; the acceptance suite's mutation pair is the standing drift detector.
///
/// **Fail-closed.** An open is called read-only here only when its flags argument was
/// found, contains at least one symbolic `O_` token, and contains none of the
/// write-capable set. Numeric-only flags (`0x241`), a missing argument, or a shape this
/// parser does not recognise are *not* read-only: they are counted as before, and a
/// miscount ends in UNKNOWN — the direction a parse failure must fall. `O_APPEND` is
/// deliberately not in the write set: append without write access cannot write, and
/// append with it is caught by the access-mode tokens.
fn isReadOnlyOpen(name: []const u8, line: []const u8) bool {
    // `creat` is deliberately absent: it implies O_CREAT|O_WRONLY|O_TRUNC without
    // spelling any of them, so there is no flags argument to consult.
    const flags_arg: usize = if (std.mem.eql(u8, name, "open"))
        1
    else if (std.mem.eql(u8, name, "openat") or std.mem.eql(u8, name, "openat2"))
        2
    else
        return false;
    const a = syscallArg(line, flags_arg) orelse return false;
    if (std.mem.indexOf(u8, a, "O_") == null) return false;
    // `O_ACCMODE` is how strace spells an *invalid* access mode (both low bits set) —
    // see its open_access_modes xlat. The shim counts that (`!= O_RDONLY`), so this
    // side must too, or the invalid case would be the one place the predicates split.
    for ([_][]const u8{ "O_WRONLY", "O_RDWR", "O_ACCMODE", "O_CREAT", "O_TRUNC" }) |w| {
        if (std.mem.indexOf(u8, a, w) != null) return false;
    }
    return true;
}

/// The quoted-string content of an argument, with strace's C escapes undone into `out`.
/// Returns null when the argument is not a quoted string (a descriptor, `NULL`, a flag).
fn argPath(arg: []const u8, out: []u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, arg, '"') orelse return null;
    var i = q + 1;
    var n: usize = 0;
    while (i < arg.len) : (i += 1) {
        const ch = arg[i];
        if (ch == '"') return out[0..n];
        if (n >= out.len) return null;
        if (ch == '\\' and i + 1 < arg.len) {
            i += 1;
            const e = arg[i];
            switch (e) {
                'n' => out[n] = '\n',
                't' => out[n] = '\t',
                'r' => out[n] = '\r',
                '0'...'7' => {
                    // Up to three octal digits, as strace escapes non-printables.
                    var v: u16 = e - '0';
                    var k: usize = 0;
                    while (k < 2 and i + 1 < arg.len and arg[i + 1] >= '0' and arg[i + 1] <= '7') : (k += 1) {
                        i += 1;
                        v = v * 8 + (arg[i] - '0');
                    }
                    out[n] = @truncate(v);
                },
                else => out[n] = e, // \" \\ and the rest are literal
            }
        } else {
            out[n] = ch;
        }
        n += 1;
    }
    return null; // unterminated
}

/// The path a `<…>` descriptor annotation carries (`AT_FDCWD</work>` → `/work`,
/// `4</tmp/state>` → `/tmp/state`), or null when the argument has none.
fn argAnnotation(arg: []const u8) ?[]const u8 {
    const lt = std.mem.indexOfScalar(u8, arg, '<') orelse return null;
    const gt = std.mem.indexOfScalarPos(u8, arg, lt + 1, '>') orelse return null;
    const p = arg[lt + 1 .. gt];
    if (p.len == 0 or p[0] != '/') return null;
    return p;
}

const Scope = enum { inside, outside, unresolvable };

fn insideEither(path: []const u8, state: []const u8, alt: []const u8) bool {
    if (contract.isInsideDir(path, state)) return true;
    return alt.len != 0 and contract.isInsideDir(path, alt);
}

/// Resolve one path argument to an absolute, lexically-normalised path in `out`, or null
/// when it cannot be placed — an empty path (a `linkat` `AT_EMPTY_PATH` source), a
/// relative path with no annotation and no known cwd, a path that will not normalise.
/// Absolute paths normalise directly; a relative path resolves against its `dirfd`
/// annotation when the syscall has one, otherwise against the tracked cwd. Both the
/// scope decision (`resolveArg`) and the cwd tracker (`chdir`) resolve paths this way.
fn resolvePath(line: []const u8, arg: PathArg, cwd: ?[]const u8, out: []u8) ?[]const u8 {
    const path_arg = syscallArg(line, arg.path) orelse return null;
    var pbuf: [contract.max_path]u8 = undefined;
    const p = argPath(path_arg, &pbuf) orelse return null;
    if (p.len == 0) return null;
    if (p[0] == '/') return contract.normalizePath(out, "/", p) catch null;

    // Relative: prefer the dirfd annotation, fall back to the tracked cwd.
    var base: ?[]const u8 = null;
    if (arg.dirfd) |di| {
        if (syscallArg(line, di)) |da| base = argAnnotation(da);
    }
    if (base == null) base = cwd;
    const b = base orelse return null;
    return contract.normalizePath(out, b, p) catch null;
}

/// The scope of one path argument. An argument that cannot be placed is `unresolvable`,
/// which the caller turns into a refusal rather than a silent drop.
fn resolveArg(line: []const u8, arg: PathArg, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    var obuf: [contract.max_path]u8 = undefined;
    const r = resolvePath(line, arg, cwd, &obuf) orelse return .unresolvable;
    return if (insideEither(r, state, alt)) .inside else .outside;
}

/// Scope of a path syscall: inside if any of its path arguments is inside (a two-path
/// op touches the state directory when the old or the new path is, ADR 0006);
/// otherwise unresolvable if any argument could not be placed; otherwise outside.
fn pathSyscallScope(spec: PathSpec, line: []const u8, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    var any_unresolvable = false;
    for (spec.args) |a| {
        switch (resolveArg(line, a, cwd, state, alt)) {
            .inside => return .inside,
            .unresolvable => any_unresolvable = true,
            .outside => {},
        }
    }
    return if (any_unresolvable) .unresolvable else .outside;
}

/// True when the syscall's return value marks success. strace prints `= 0`, `= 3`, etc.
/// on success and `= -1 ENOENT (...)` on failure; an unfinished call ends in `<... >` or
/// `?`. Only a successful chdir/fchdir may move the tracked cwd.
fn syscallSucceeded(line: []const u8) bool {
    const eq = std.mem.lastIndexOfScalar(u8, line, '=') orelse return false;
    const rhs = std.mem.trim(u8, line[eq + 1 ..], " \t");
    return rhs.len > 0 and rhs[0] != '-' and rhs[0] != '?';
}

/// Does this syscall change persistent state? Used to decide what an *unresolvable*
/// in-scope operation means: a write we could not place must refuse, a read we could not
/// place changes nothing and is tolerated. Mirrors the read-only handling below.
fn changesPersistentState(name: []const u8, line: []const u8) bool {
    if (isReadOnly(name)) return false;
    if (std.mem.eql(u8, name, "close")) return false;
    if ((std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "openat") or
        std.mem.eql(u8, name, "openat2")) and isReadOnlyOpen(name, line)) return false;
    return true;
}

/// Which argument of an fd syscall names the descriptor being WRITTEN.
///
/// Argument 0 for every syscall that reached this file before #244: `write`, `fsync`,
/// `close`, `ftruncate`, `pwritev` and the metadata pair all put their descriptor
/// first, which is why the rule used to be stated as a fact about fd syscalls in
/// general. `copy_file_range(fd_in, off_in, fd_out, …)` breaks it — argument 0 is the
/// SOURCE. Reading it as the destination gets the answer wrong in both directions: a
/// copy out of the state directory would count as a mutation (there is none), and a
/// copy into it from elsewhere would be missed entirely.
///
/// `sendfile(out_fd, in_fd, …)` needs no entry: its destination is already first.
/// Anything absent from this table keeps the argument-0 default, so adding it changes
/// no existing verdict.
const FdWriteArg = struct { name: []const u8, arg: usize };
const fd_write_args = [_]FdWriteArg{
    .{ .name = "copy_file_range", .arg = 2 },
};

/// The fd syscalls whose descriptor really is argument 0. Written out rather than left
/// to the default (#280).
///
/// `#244` added the table above when `copy_file_range` broke the old blanket rule, and
/// left "anything absent keeps the argument-0 default" — which fixed the datum and not
/// the mechanism. The issue's sentence stayed literally true: *"true for every entry
/// today, enforced by nothing, and a future `known` entry that violates it would
/// silently scope real operations out."* Nothing cross-referenced the classifier against
/// either table, so a new entry inherited argument 0 in silence.
///
/// It cannot now: the test below requires every fd syscall the classifier knows to
/// appear in exactly one of these two lists. Adding a `known` entry that carries its
/// descriptor elsewhere fails until someone says which argument that is, and adding one
/// that really does use argument 0 costs a line here — which is the point, because the
/// line is where the reader learns it was decided rather than defaulted.
const fd_arg0 = [_][]const u8{
    "close",       "fdatasync", "fsync",      "ftruncate",
    "ftruncate64", "pwrite",    "pwrite64",   "pwritev",
    "pwritev2",    "sendfile",  "sendfile64", "write",
    "writev",
};

fn fdWriteArg(name: []const u8) usize {
    for (fd_write_args) |w| {
        if (std.mem.eql(u8, w.name, name)) return w.arg;
    }
    return 0;
}

/// Scope of an fd syscall, read from the annotation of the descriptor it WRITES and
/// never from the quoted arguments — a state-directory string that happens to sit in a
/// write buffer must not scope it in. Which argument that is comes from
/// `fd_write_args` above; the default is argument 0.
fn fdSyscallInScope(line: []const u8, name: []const u8, state: []const u8, alt: []const u8) bool {
    const arg = syscallArg(line, fdWriteArg(name)) orelse return false;
    const p = argAnnotation(arg) orelse return false;
    return insideEither(p, state, alt);
}

/// Something a witness saw, and where in its capture it saw it. The position is an
/// ordinal over the lines this reader examined, which is all any comparison here needs:
/// nothing outside this file reads it as anything but "before" and "after".
pub const Event = struct { id: u64, at: usize };

pub const Parsed = struct {
    /// The subject's state-directory operation classes, in order.
    classes: std.ArrayList(contract.OpClass),
    /// The observer's own name for each entry of `classes`, index-aligned with it and
    /// with `lines` (#337). `openat`, `renameat2` from strace; `open`, `rename` from
    /// fs_usage — each observer's spelling, not a normalised one, because a reader who
    /// goes back to the capture has to find the line again.
    ///
    /// Appended beside `classes` by both producers, which is what makes the alignment
    /// hold: the field exists so a divergence refusal can say WHICH operation it refused
    /// on without the reader parsing the quoted line, and the fs_usage side had this
    /// name in hand (`ln.call`) and was dropping it. Empty entries are possible in
    /// principle (an observer whose line the reader cannot name); the refusal then omits
    /// the field rather than guessing.
    names: std.ArrayList([]const u8),
    /// The raw strace line behind each entry of `classes`, index-aligned. Kept so a
    /// refusal can name the operation it refused on instead of handing the reader a
    /// binary trace to decode by hand (#41). These borrow from the `text` given to
    /// `parse` — no copy, no new allocation-failure path — so the caller keeps that
    /// buffer alive for as long as it reads them (main does: same arena, same scope).
    lines: std.ArrayList([]const u8),
    /// A state-directory syscall by the subject that v0.1 does not model.
    unsupported: ?[]const u8 = null,
    /// A syscall that stays a hard refusal whoever tolerates what: the subject
    /// replacing its own image, or namespace surgery.
    boundary: ?[]const u8 = null,
    /// Every non-read-only state-directory operation this witness placed, with **where in
    /// the capture** it was seen, in the order the lines came (v15).
    ///
    /// Under `strace` that is every process, the subject included, which is what the
    /// ordering rule needs — the writer it most often has to order a child against is the
    /// parent. The `fs_usage` reader fills in the non-subject ids only: it has no oracle
    /// role beyond detection on that platform, where a run with another process in it is
    /// refused for want of an oracle that can account for one. That refusal is
    /// `boundary_without_oracle` and it keys on the SHIM having seen a boundary, so a
    /// child the shim never loaded reaches the admission — and is refused there too,
    /// because a tid is not the pid the shim recorded and no writer will match it.
    ///
    /// The position is the point. Whether a run's operations interleave cannot be decided
    /// from the shim's trace: an awaited child's records sit BETWEEN its parent's, and so
    /// do a racing sibling's, so the record order shows the same picture for the hand-off
    /// and for the race. What separates them is when the child was collected, and the
    /// wait and the writes are in one order only here.
    ///
    /// The id is what the WITNESS attributes a line to: the task id under `strace -f` —
    /// a pid for a process's main thread and a tid for any other thread, which strace
    /// prints in the same column — and a tid under `fs_usage`, which is the only
    /// identifier that reader has. Through v15 the distinction never reached a
    /// comparison, because a run with a thread in it was refused first; since v16 a
    /// thread of the subject is the subject (`subject_tids`, `isSubject`), so an id
    /// here that is not the subject's is a child's. 64-bit because a mach thread id is
    /// not bounded by the width of a pid.
    mutations: std.ArrayList(Event),
    /// Threads of the subject, by the id strace prints for them (v16). Filled from the
    /// subject's own `clone` lines carrying `CLONE_THREAD`, in both spellings strace uses
    /// (one line, or an unfinished half and a resumed half). A line from one of these
    /// is the subject's line: its operations go to `classes`, its relative paths resolve
    /// against the subject's cwd, and its writes are not a child's touch. What this list
    /// does NOT decide is whether more than one of them wrote — that is the shim's
    /// trace to answer, record by record, since every record names its thread.
    subject_tids: std.ArrayList(u64),
    /// The processes some other process waited for and collected, and where. See
    /// `reapedPid` for what this does and does not claim.
    reaps: std.ArrayList(Event),
    /// Where each child process was created. The other end of the window a writing child
    /// is judged in; `spawnedPid` says why it is the creation and not the first write.
    spawns: std.ArrayList(Event),
    /// Distinct pids other than the subject's that appeared at all.
    children: usize = 0,

    /// The subject's pid: whoever performed the launch execve. Null when the trace
    /// carries no pid prefixes, in which case every line is attributed to the subject —
    /// the v0.1 reading, still right for a trace of one process.
    primary_pid: ?u32 = null,
    /// How many lines were examined. Reported so that "no mismatches" can be told
    /// apart from "the oracle file was empty and nothing was compared".
    lines_seen: usize = 0,
    lines_in_scope: usize = 0,
    /// Ownership/permission writes on the state directory, one entry per occurrence
    /// (the syscall name). Observed by this oracle only — the shim does not interpose
    /// them — and excluded from every verdict input (#121, option b); the report
    /// carries them so the exclusion is visible per run.
    metadata_observed: std.ArrayList([]const u8),

    /// Is this id the subject — its main thread, or any thread it created (v16)? The
    /// one place the question is answered, so the child branch of `parse`, the touch
    /// predicate below and the engine's admission (`childrenMayBeJudged`) cannot drift
    /// on what "the subject" means.
    pub fn isSubject(self: Parsed, id: u64) bool {
        if (self.primary_pid) |p| {
            if (id == p) return true;
        }
        for (self.subject_tids.items) |t| {
            if (id == t) return true;
        }
        return false;
    }

    /// Did a process other than the subject mutate the judged directory? Derived from
    /// `mutations` rather than stored beside it: a flag and a list that answer the same
    /// question are two things that can disagree.
    pub fn childTouched(self: Parsed) bool {
        for (self.mutations.items) |m| {
            if (self.primary_pid == null or !self.isSubject(m.id)) return true;
        }
        return false;
    }
};

pub fn parse(arena: std.mem.Allocator, text: []const u8, state_dir: []const u8, state_alt: []const u8, initial_cwd: []const u8) !Parsed {
    var out: Parsed = .{ .classes = .empty, .names = .empty, .lines = .empty, .metadata_observed = .empty, .mutations = .empty, .reaps = .empty, .spawns = .empty, .subject_tids = .empty };
    var child_pids: std.ArrayList(u32) = .empty;
    var launched = false;
    // Callers whose `clone` carried `CLONE_THREAD` and has not resumed yet (v16). strace
    // splits a call whenever another task's line lands inside it, and for a clone that
    // puts the flags on one half and the new task's id on the other; the pid column is
    // what joins them. A thread created by a thread is the same case — the caller is a
    // subject id either way, which is what `isSubject` is asked before the entry is made.
    var pending_thread_clone: std.ArrayList(u32) = .empty;

    // Writes appended but not yet known to have run, and the entries a refusal retracts.
    // See `PendingWrite` and `dropRetracted` for why the removal is deferred to the end.
    var pending: std.ArrayList(PendingWrite) = .empty;
    var dead_ops: std.ArrayList(usize) = .empty;
    var dead_muts: std.ArrayList(usize) = .empty;

    // The subject's working directory, tracked so a relative path with no dirfd
    // annotation (every path syscall on x86-64, where glibc issues the legacy forms)
    // can still be resolved (ADR 0006). Starts at the engine's cwd; the subject's own
    // successful chdir/fchdir move it. Held in `cwd_buf` (not sliced from the strace
    // text, which is normalised away) so it survives past the line that set it.
    var cwd_buf: [contract.max_path]u8 = undefined;
    var cwd: ?[]const u8 = blk: {
        if (initial_cwd.len == 0 or initial_cwd.len > cwd_buf.len) break :blk null;
        @memcpy(cwd_buf[0..initial_cwd.len], initial_cwd);
        break :blk cwd_buf[0..initial_cwd.len];
    };

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        out.lines_seen += 1;

        const pid = pidOf(line);
        // Before the name test, which drops every `<... wait4 resumed>` line: that form
        // has no name this parser can read and it is the one carrying the reaped pid
        // (v15). Gated on `launched` so the apparatus's own waits — strace reaping the
        // process it started the target from — are not the target's.
        if (launched) {
            if (reapedPid(line)) |r| try noteEvent(arena, &out.reaps, r, out.lines_seen);
            // The resumed half of a split clone carries the number and not the flags.
            // Whether it was a thread was decided on the unfinished half and remembered
            // by caller; a remembered one is the subject's new thread and not a spawn.
            if (spawnedPid(line)) |c| {
                if (isResumedClone(line) and takeThreadClone(&pending_thread_clone, pid)) {
                    try out.subject_tids.append(arena, c);
                } else {
                    try noteEvent(arena, &out.spawns, c, out.lines_seen);
                }
            }
            // The kernel refusing a trapped write means the entry appended for it
            // describes a call that did not run (`--observe syscalls`). Here for the same
            // reason as the two readers above: `syscallName` answers null for a
            // `--- … ---` line, and a test in this file pins that.
            if (isSeccompRefusal(line)) {
                if (takePending(&pending, pid)) |q| {
                    if (q.op) |i| {
                        try dead_ops.append(arena, i);
                        // A pending entry carrying an `op` index was set on the subject
                        // path, which increments this counter before it appends — so the
                        // count cannot be zero here. Asserted rather than saturated: `-|`
                        // would absorb a future path that sets `.op` without counting the
                        // line, and absorbing it is how the count would go quietly wrong.
                        std.debug.assert(out.lines_in_scope > 0);
                        out.lines_in_scope -= 1;
                    }
                    if (q.mutation) |i| try dead_muts.append(arena, i);
                }
                continue;
            }
        }
        const name = syscallName(line) orelse continue;

        // Any other line from this process closes the window a refusal could retract in.
        // Without it, a write to a file OUTSIDE the judged state — trapped too, since the
        // filter keys on the syscall number and not on the path — would raise a signal
        // that retracted an unrelated earlier operation of the same process.
        _ = takePending(&pending, pid);

        // The first execve is strace starting the target: it names the subject.
        // Everything before knowing the subject is the measuring apparatus itself.
        if (!launched) {
            if (std.mem.eql(u8, name, "execve") or std.mem.eql(u8, name, "execveat")) {
                launched = true;
                out.primary_pid = pid;
            }
            continue;
        }

        // "The subject" is the process AND its threads (v16). A thread's line can precede
        // the resumption of the clone that names it, the ordering `spawnedPid`'s doc
        // records for a child; such a line is read as a child's here and the process is
        // struck from `child_pids` once the clone resumes, below. If it wrote in the
        // judged directory in that gap it stays a touch — the run refuses rather than
        // admits, which is the direction to be wrong in.
        const is_primary = pid == null or out.primary_pid == null or out.isSubject(pid.?);
        if (!is_primary) {
            var seen = false;
            for (child_pids.items) |p| {
                if (p == pid.?) {
                    seen = true;
                    break;
                }
            }
            if (!seen) try child_pids.append(arena, pid.?);
        }

        if (isProcessSyscall(name)) {
            // A second execve by the *subject* is no longer a refusal here (#123,
            // contract v10): whether the chain of observation survived the image
            // change is the SHIM's evidence to give (the carried count in the next
            // shim_ready), and a chain that broke leaves the shim's records short of
            // these syscalls — the completeness comparison below refuses on that
            // divergence. A child's execve is just a child becoming what it spawns.
            // unshare is refused from anyone — this tool does not model namespaces.
            // A clone that carries CLONE_THREAD is not a child at all: it is a thread,
            // and since v16 a thread of the subject IS the subject — its id joins
            // `subject_tids`, from this line when the number is on it and from the
            // resumed half otherwise. Through v15 this line refused the run; what it
            // refused for (one order for the kill to address) is decided by the shim's
            // trace now, thread by thread. A thread a CHILD created is not entered: the
            // caller is not a subject id, so the thread's lines stay a child's, and a
            // write from it is a touch. Whole-line search is fine *here*, unlike the
            // flag checks below: clone's arguments carry no target-chosen strings for a
            // false CLONE_THREAD to hide in, and clone3 prints its flags inside a struct
            // at no fixed index.
            const is_raw_thread = std.mem.startsWith(u8, name, "clone") and
                std.mem.indexOf(u8, line, "CLONE_THREAD") != null;
            // CLONE_FS shares the working directory: a child holding it can move the
            // subject's cwd out from under the resolution above, so this tool refuses it
            // rather than track a shared fs context (ADR 0006). Same whole-line check as
            // CLONE_THREAD, and safe for the same reason. A thread holds it too — every
            // pthread does — and is not refused for it: a thread's chdir moves the
            // process's cwd, which is the subject's, and the tracker above follows any
            // subject id's chdir since v16.
            const is_shared_fs = std.mem.startsWith(u8, name, "clone") and
                std.mem.indexOf(u8, line, "CLONE_FS") != null;
            if (is_raw_thread) {
                if (is_primary) {
                    if (returnedPid(line)) |t| {
                        try out.subject_tids.append(arena, t);
                    } else if (std.mem.indexOf(u8, line, "<unfinished ...>") != null) {
                        try pending_thread_clone.append(arena, pid orelse 0);
                    }
                    // A failed clone (`= -1 ENOSYS`, the clone3 a kernel declines before
                    // libc falls back to clone) made no thread and enters nothing.
                }
            } else if (is_shared_fs or std.mem.eql(u8, name, "unshare")) {
                if (out.boundary == null) out.boundary = try arena.dupe(u8, name);
            }
            continue;
        }

        // A process that leaves the containment group is one the group kill no longer
        // reaches. The shim records its own view of this, but only for processes that
        // loaded it; the oracle is the only observer of an unshimmed child detaching.
        // The subject's own calls are left to the shim, whose wrapper knows whether the
        // call actually moved anything — the direct child re-electing itself leader is
        // a no-op that must not be refused.
        if (!is_primary and (std.mem.eql(u8, name, "setsid") or std.mem.eql(u8, name, "setpgid"))) {
            if (out.boundary == null) out.boundary = try arena.dupe(u8, name);
            continue;
        }

        // The subject's own successful chdir/fchdir moves the cwd used to resolve
        // relative paths. A child's does not (a fs-sharing child was refused above).
        if (is_primary and std.mem.eql(u8, name, "chdir")) {
            if (syscallSucceeded(line)) {
                // `out` (obuf) is separate from cwd_buf, so resolving a relative chdir
                // against the current cwd does not read its own output; copy after.
                var obuf: [contract.max_path]u8 = undefined;
                if (resolvePath(line, .{ .dirfd = null, .path = 0 }, cwd, &obuf)) |nc| {
                    @memcpy(cwd_buf[0..nc.len], nc);
                    cwd = cwd_buf[0..nc.len];
                } else cwd = null; // could not resolve: relative paths now refuse
            }
            continue;
        }
        if (is_primary and std.mem.eql(u8, name, "fchdir")) {
            if (syscallSucceeded(line)) {
                if (syscallArg(line, 0)) |a| {
                    if (argAnnotation(a)) |dir| {
                        @memcpy(cwd_buf[0..dir.len], dir);
                        cwd = cwd_buf[0..dir.len];
                    } else cwd = null; // no annotation (a raw fd): cwd is now unknown
                }
            }
            continue;
        }

        // Ownership/permission metadata (#121, option b), decided BEFORE the generic
        // scope block because it must bypass both refusal routes below: the subject's
        // branch would call it `unsupported`, and the child branch would call it a
        // touch — while the verdict judges names, bytes and link targets, none of
        // which these change, from anyone. Scope uses the same typed rules; an
        // unresolvable metadata write is counted too — over-reporting an exclusion
        // is the honest direction (the report says "excluded", never "did not
        // happen").
        if (metadataPathSpec(name)) |mspec| {
            if (pathSyscallScope(mspec, line, cwd, state_dir, state_alt) != .outside)
                try out.metadata_observed.append(arena, try arena.dupe(u8, name));
            continue;
        }
        if (isMetadataFd(name)) {
            if (fdSyscallInScope(line, name, state_dir, state_alt))
                try out.metadata_observed.append(arena, try arena.dupe(u8, name));
            continue;
        }

        // Scope, decided by type (ADR 0006). A path syscall resolves its real path
        // arguments; an fd syscall reads only its descriptor annotation; anything else
        // falls to the conservative whole-line net, which only ever routes to
        // `unsupported`. `unresolvable` is a refusal, never a silent drop.
        // **The tracked cwd is the SUBJECT's, so no other process's relative path may be
        // resolved against it** (v15). `resolvePath` falls back to it whenever a line
        // carries no dirfd annotation, which is every legacy-form path syscall — and on
        // x86-64 glibc issues the legacy forms for `rename`, `unlink` and `mkdir`, as the
        // comment on `cwd` above says. A child that moved its own working directory and
        // wrote through a relative path would then be placed at a path it never touched:
        // outside the judged state, silently, and a run with an unaccounted writer in it
        // would be judged.
        //
        // Passing null instead makes that line `.unresolvable`, which the child branch
        // below already treats the way it treats an in-scope one — "nobody can say which
        // kind it was". The hole was opened by this version, not found in it: `chdir`
        // joined the read-only list here (a child changing its own directory changes no
        // byte), and until then the `chdir` itself was the touch that refused the run.
        // The measurement that said the annotation always carries the child's cwd was
        // taken on aarch64 only, where glibc issues the *at forms; review caught the
        // generalisation.
        const scope: Scope = if (pathSpec(name)) |spec|
            pathSyscallScope(spec, line, if (is_primary) cwd else null, state_dir, state_alt)
        else if (isFdSyscall(name))
            (if (fdSyscallInScope(line, name, state_dir, state_alt)) .inside else .outside)
        else
            (if (touchesStateDir(line, state_dir, state_alt)) .inside else .outside);

        if (scope == .outside) continue;

        // Dirtying a MAP_SHARED mapping changes the file with no later write syscall
        // for either observer to see. From the subject that is an unmodelled mutation;
        // from a child it is the touch condition. Read from mmap's prot and flags
        // arguments, not from the line — a filename could spell either token.
        const is_shared_write_map = std.mem.eql(u8, name, "mmap") and
            argContains(line, 2, "PROT_WRITE") and
            argContains(line, 3, "MAP_SHARED");

        if (!is_primary) {
            // The tolerance condition itself. Reads are allowed — they consume no
            // sequence number and change no state — everything else, including a
            // syscall nobody recognises or one whose path could not be placed, is a
            // child touching what only the subject may. `changesPersistentState` is the
            // single predicate for "not a read, not a close, not a write-incapable open"
            // (ADR 0003), so an in-scope and an unresolvable operation are judged alike.
            if (is_shared_write_map or changesPersistentState(name, line)) {
                try noteEvent(arena, &out.mutations, pid.?, out.lines_seen);
                if (isTrappedWrite(name))
                    try setPending(arena, &pending, .{ .pid = pid, .op = null, .mutation = out.mutations.items.len - 1 });
            }
            continue;
        }

        // The subject touched the state directory but the operation could not be placed
        // among the crash points: refuse if it changes state, tolerate if it cannot.
        if (scope == .unresolvable) {
            if (changesPersistentState(name, line) and out.unsupported == null)
                out.unsupported = try arena.dupe(u8, name);
            continue;
        }
        out.lines_in_scope += 1;

        if (is_shared_write_map) {
            if (out.unsupported == null)
                out.unsupported = try arena.dupe(u8, "mmap(PROT_WRITE|MAP_SHARED)");
            continue;
        }
        if (isReadOnly(name)) continue;
        // `linkat` with AT_EMPTY_PATH links a descriptor, not a named source; the shim
        // cannot resolve the empty old path and records `.unresolved`, so the oracle
        // refuses it here rather than count a `.link` the shim never placed (ADR 0006).
        if (std.mem.eql(u8, name, "linkat") and argContains(line, 4, "AT_EMPTY_PATH")) {
            if (out.unsupported == null) out.unsupported = try arena.dupe(u8, "linkat(AT_EMPTY_PATH)");
            continue;
        }
        // `renameat2`'s flags decide what the call MEANS, and two of the three are not
        // renames (#256). `RENAME_EXCHANGE` swaps two files atomically — both names
        // survive, both contents move — and `RENAME_WHITEOUT` leaves a whiteout inode
        // behind the source. Counting either as `.rename` would name an operation
        // whose effect the restore model cannot reproduce, so they are refused here,
        // by flag, the way `linkat(AT_EMPTY_PATH)` is above. `RENAME_NOREPLACE` is a
        // plain rename that declines to clobber, and stays a `.rename`.
        if (std.mem.eql(u8, name, "renameat2")) {
            const exchange = renameat2Flag(line, "RENAME_EXCHANGE", rename_exchange);
            const whiteout = renameat2Flag(line, "RENAME_WHITEOUT", rename_whiteout);
            if (exchange or whiteout) {
                if (out.unsupported == null)
                    out.unsupported = try arena.dupe(u8, if (exchange)
                        "renameat2(RENAME_EXCHANGE)"
                    else
                        "renameat2(RENAME_WHITEOUT)");
                continue;
            }
        }
        if (classify(name)) |cls| {
            // Neither of these enters the comparison (ADR 0003). A write-incapable open
            // is not an observed operation on either side; close stays recorded by the
            // shim but cannot be paired across views the shim never saw born.
            if (cls == .close) continue;
            if (cls == .open and isReadOnlyOpen(name, line)) continue;
            const actual: contract.OpClass = if (cls == .unlink and
                std.mem.eql(u8, name, "unlinkat") and unlinkatRemovesDir(line)) .rmdir else cls;
            try out.classes.append(arena, actual);
            // Index-aligned with `classes`, appended in the same breath so the three
            // lists cannot drift apart (#337).
            try out.names.append(arena, name);
            try out.lines.append(arena, line);
            // And into the positioned list, where the SUBJECT's operations matter as much
            // as a child's (v15): the ordering rule asks whether anyone else wrote while
            // a child had not been collected yet, and the parent is the anyone else that
            // most often has.
            if (pid) |me| try noteEvent(arena, &out.mutations, me, out.lines_seen);
            if (isTrappedWrite(name)) try setPending(arena, &pending, .{
                .pid = pid,
                .op = out.classes.items.len - 1,
                .mutation = if (pid == null) null else out.mutations.items.len - 1,
            });
        } else if (out.unsupported == null) {
            out.unsupported = try arena.dupe(u8, name);
        }
    }
    // A thread's first line can precede the resumption of the clone that names it, so
    // it may have been listed as a child before it was known to be the subject's (v16).
    // Struck now, once every clone has resumed: `children` is a count of PROCESSES the
    // report prints as such, and a thread is not one.
    var kept: usize = 0;
    for (child_pids.items) |c| {
        if (!out.isSubject(c)) {
            child_pids.items[kept] = c;
            kept += 1;
        }
    }
    out.children = kept;
    try dropRetracted(arena, &out, dead_ops.items, dead_muts.items);
    return out;
}

/// Take `pid`'s remembered thread clone out of the list, answering whether there was one.
fn takeThreadClone(list: *std.ArrayList(u32), pid: ?u32) bool {
    const want = pid orelse 0;
    for (list.items, 0..) |p, i| {
        if (p == want) {
            _ = list.swapRemove(i);
            return true;
        }
    }
    return false;
}

/// Compare the two class sequences position by position.
///
/// The first divergence is reported rather than a count: a single missed operation
/// already means every crash point after it is numbered wrongly, so there is nothing
/// useful to say about the rest.
pub fn compare(shim: []const contract.OpClass, oracle: []const contract.OpClass) ?Finding {
    var i: usize = 0;
    while (i < shim.len and i < oracle.len) : (i += 1) {
        if (shim[i] != oracle[i]) {
            return .{ .missed = .{ .index = i, .class = oracle[i] } };
        }
    }
    if (oracle.len > shim.len) return .{ .missed = .{ .index = i, .class = oracle[i] } };
    if (shim.len > oracle.len) return .{ .phantom = .{ .index = i, .class = shim[i] } };
    return null;
}

test "containment uses component boundaries, not string prefixes" {
    try std.testing.expect(touchesStateDir("write(3</tmp/state/key.json>, ...) = 6", "/tmp/state", ""));
    try std.testing.expect(touchesStateDir("openat(AT_FDCWD</work>, \"/tmp/state/k\", 0) = 3", "/tmp/state", ""));
    // the case a naive substring search gets wrong
    try std.testing.expect(!touchesStateDir("write(3</tmp/state2/key.json>, ...) = 6", "/tmp/state", ""));
    try std.testing.expect(!touchesStateDir("openat(AT_FDCWD</work>, \"/etc/passwd\", 0) = 3", "/tmp/state", ""));
}

test "syscall names are read from the start of the line" {
    try std.testing.expectEqualStrings("openat", syscallName("openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("pwrite64", syscallName("pwrite64(3, \"x\", 1, 0) = 1").?);
    try std.testing.expectEqual(@as(?[]const u8, null), syscallName("--- SIGKILL ---"));
    try std.testing.expectEqual(@as(?[]const u8, null), syscallName("+++ killed by SIGKILL +++"));
}

test "a seccomp refusal is told apart from every other signal line" {
    try std.testing.expect(isSeccompRefusal("14    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_call_addr=0xffffb8fddc58, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---"));
    // An older strace spelling the syscall as a number decides the same way: the name
    // was never what the retraction rested on.
    try std.testing.expect(isSeccompRefusal("--- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=64, si_arch=AUDIT_ARCH_X86_64} ---"));
    // A SIGSYS from anywhere else says nothing about a call this reader appended.
    try std.testing.expect(!isSeccompRefusal("14    --- SIGSYS {si_signo=SIGSYS, si_code=SI_USER, si_pid=1, si_uid=0} ---"));
    // Signals this reader has no business retracting on, and an ordinary syscall line.
    try std.testing.expect(!isSeccompRefusal("14    --- SIGKILL ---"));
    try std.testing.expect(!isSeccompRefusal("+++ killed by SIGKILL +++"));
    try std.testing.expect(!isSeccompRefusal("write(3</tmp/o/state/k>, \"x\", 1) = 1"));
}

test "a refused write and its re-issue are one operation (--observe syscalls)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The single-process shape, measured in spike/followup-trapwitness/artifacts/
    // trapped-engine-flags.txt: the refused call, the signal, the re-issue.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_call_addr=0xffff, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 6
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    // The three aligned lists shrink together, and the line kept is the one that ran.
    try std.testing.expectEqual(@as(usize, 1), p.names.items.len);
    try std.testing.expectEqual(@as(usize, 1), p.lines.items.len);
    try std.testing.expect(std.mem.endsWith(u8, p.lines.items[0], "= 6"));
    // Both lines were in scope of the judged state; only one of them happened.
    try std.testing.expectEqual(@as(usize, 1), p.lines_in_scope);
    // And the positioned list the child admission reads (v15) holds one, not two.
    try std.testing.expectEqual(@as(usize, 1), p.mutations.items.len);
}

test "every member of the trapped family is retracted, not just write" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // `write` is the member every other test here uses, and it is the one member whose
    // retraction working proves least about the other three: they reach `isTrappedWrite`
    // through the same list but the oracle spells and places them differently.
    // `spike/check-shim-coverage.py` holds the list against the filter's; this holds the
    // list against the reader that consumes it.
    try std.testing.expect(isTrappedWrite("write"));
    try std.testing.expect(isTrappedWrite("pwrite64"));
    try std.testing.expect(isTrappedWrite("writev"));
    try std.testing.expect(isTrappedWrite("pwritev"));
    // Not trapped: six arguments leave the filter no register for the re-issue marker,
    // so nothing raises a signal for it and an entry here could never fire (ADR 0052).
    try std.testing.expect(!isTrappedWrite("pwritev2"));
    try std.testing.expect(!isTrappedWrite("openat"));

    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    pwrite64(3</tmp/o/state/a>, "x", 1, 0) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_pwrite64, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    pwrite64(3</tmp/o/state/a>, "x", 1, 0) = 1
        \\10    writev(3</tmp/o/state/a>, [{iov_base="y", iov_len=1}], 1) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_writev, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    writev(3</tmp/o/state/a>, [{iov_base="y", iov_len=1}], 1) = 1
        \\10    pwritev(3</tmp/o/state/a>, [{iov_base="z", iov_len=1}], 1, 0) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_pwritev, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    pwritev(3</tmp/o/state/a>, [{iov_base="z", iov_len=1}], 1, 0) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    // Three operations, not six.
    const want = [_]contract.OpClass{ .write, .write, .write };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 3), p.lines_in_scope);
    try std.testing.expectEqual(@as(usize, 3), p.mutations.items.len);
    // And the line kept for each is the one that ran.
    for (p.lines.items) |l| try std.testing.expect(std.mem.endsWith(u8, l, "= 1"));
}

test "a refused write is retracted whatever the register held (x86-64)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // On aarch64 the refused call's return reads as the fd; on x86-64 glibc renders it
    // `-1 ENOSYS`. Neither is promised, so the retraction keys on the signal — this is
    // the shape that would break a rule keyed on the return value instead.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = -1 ENOSYS (Function not implemented)
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_X86_64} ---
        \\10    write(3</tmp/o/state/key.json>, "key=2\n", 6) = 6
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
}

test "a refusal retracts only its own process's write, whoever wrote in between" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The interleaving is the reason the retraction cannot pop the last entry: pid 11
    // appends between pid 10's write and pid 10's signal, and pid 10's is retracted
    // first. Both writes are one operation each once their refusals are read.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/a>, "x", 1) = 3
        \\11    write(4</tmp/o/state/b>, "y", 1) = 4
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(3</tmp/o/state/a>, "x", 1) = 1
        \\11    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\11    write(4</tmp/o/state/b>, "y", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    // The subject's list: its own write, once.
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    // The positioned list carries both processes, one entry each.
    try std.testing.expectEqual(@as(usize, 2), p.mutations.items.len);
    try std.testing.expect(holdsId(p.mutations.items, 10));
    try std.testing.expect(holdsId(p.mutations.items, 11));
    try std.testing.expect(p.childTouched());
}

test "the subject's own refused write survives the unfinished shape too" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The split entry/resumption shape is not a child's: it appears whenever another
    // process's lines interleave with the call, and the subject is as exposed to that as a
    // child is. The child test above covers `mutations`; this one covers the three aligned
    // lists and the in-scope count, which the child path never touches.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/key.json>, "k", 1 <unfinished ...>
        \\11    openat(AT_FDCWD</work>, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
        \\10    <... write resumed>)              = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(3</tmp/o/state/key.json>, "k", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 1), p.names.items.len);
    try std.testing.expectEqual(@as(usize, 1), p.lines.items.len);
    try std.testing.expectEqual(@as(usize, 1), p.lines_in_scope);
    try std.testing.expect(std.mem.endsWith(u8, p.lines.items[0], "= 1"));
}

test "the process that appended last is not the one whose refusal comes first" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The mirror of the interleaving test above: pid 11 appends second and is refused
    // first. `takePending` uses `swapRemove`, so the list's order after a take is not the
    // order things were added in — a lookup that leant on that order would pass one of
    // these two tests and fail the other.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/a>, "x", 1) = 3
        \\11    write(4</tmp/o/state/b>, "y", 1) = 4
        \\11    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\11    write(4</tmp/o/state/b>, "y", 1) = 1
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(3</tmp/o/state/a>, "x", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 2), p.mutations.items.len);
    try std.testing.expect(holdsId(p.mutations.items, 10));
    try std.testing.expect(holdsId(p.mutations.items, 11));
    try std.testing.expectEqual(@as(usize, 1), p.lines_in_scope);
}

test "a refusal with no re-issue leaves nothing behind at end of input" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The shape README warns about: a process the shim could not be loaded into inherits
    // the filter, has no handler to re-issue with, and dies on its first write. The refused
    // entry is the only one, and the capture ends with the retraction already recorded — so
    // the write must not survive as an operation, and nothing may be left pending for a
    // later line to consume.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/key.json>, "k", 1) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    +++ killed by SIGSYS +++
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.names.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.lines.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.mutations.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.lines_in_scope);
}

test "a trapped write OUTSIDE the judged state retracts nothing" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The filter keys on the syscall number, not on the path, so a write to stdout is
    // refused and re-issued exactly like an in-scope one — and nothing was appended for
    // it to retract. What must survive is the in-scope write that ALREADY RAN: the
    // re-issue leaves an entry standing, and the next signal belongs to a different call.
    //
    // The control for the line that closes the window. Delete the `takePending` after the
    // name test and stdout's signal retracts the write to the judged state, leaving the
    // sequence empty. An earlier draft of this test put a `renameat` where the first write
    // is, which set no pending entry at all — it passed with the window-closing line
    // deleted, and the mutation run is what said so.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    write(3</tmp/o/state/key.json>, "x", 1) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(3</tmp/o/state/key.json>, "x", 1) = 1
        \\10    write(1</dev/null>, "hi", 2) = 3
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    write(1</dev/null>, "hi", 2) = 2
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 1), p.mutations.items.len);
    try std.testing.expectEqual(@as(usize, 1), p.lines_in_scope);
}

test "a child's refused write is one mutation, across the unfinished shape" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The shape measured with children running: the refused call is split across an
    // unfinished entry and a resumption, the signal arrives after BOTH, and the handler's
    // own record write sits between the signal and the re-issue. `syscallName` answers
    // null for the resumption, which is why it does not close the window.
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\11    write(3</tmp/o/state/from-child-b.txt>, "b\n", 2 <unfinished ...>
        \\11    <... write resumed>)              = 3
        \\11    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_write, si_arch=AUDIT_ARCH_AARCH64} ---
        \\11    write(900</tmp/o/t.bin>, "rec", 3) = 47
        \\11    write(3</tmp/o/state/from-child-b.txt>, "b\n", 2) = 2
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    // One write by one child, not two. This is the count the child admission reads.
    try std.testing.expectEqual(@as(usize, 1), p.mutations.items.len);
    try std.testing.expectEqual(@as(u64, 11), p.mutations.items[0].id);
    try std.testing.expect(p.childTouched());
}

test "parse extracts the class sequence the shim should have recorded" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const text =
        \\execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\openat(AT_FDCWD</work>, "/tmp/o/state/key.json.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/o/state/key.json.tmp>
        \\write(3</tmp/o/state/key.json.tmp>, "key=2\n", 6) = 6
        \\fsync(3</tmp/o/state/key.json.tmp>)     = 0
        \\close(3</tmp/o/state/key.json.tmp>)     = 0
        \\unlinkat(AT_FDCWD</work>, "/tmp/o/state/key.json", 0) = 0
        \\renameat(AT_FDCWD</work>, "/tmp/o/state/key.json.tmp", AT_FDCWD</work>, "/tmp/o/state/key.json") = 0
        \\openat(AT_FDCWD</work>, "/etc/ld.so.cache", O_RDONLY|O_CLOEXEC) = 3
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    // close is recorded by the shim but excluded from the comparison (ADR 0003).
    const expected = [_]contract.OpClass{ .open, .write, .fsync, .unlink, .rename };
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);
    // Each class keeps the raw line it came from, index-aligned, so a refusal can
    // name the operation it refused on (#41).
    try std.testing.expectEqual(p.classes.items.len, p.lines.items.len);
    try std.testing.expect(std.mem.indexOf(u8, p.lines.items[3], "unlinkat") != null);
    try std.testing.expect(std.mem.indexOf(u8, p.lines.items[4], "renameat") != null);
    // And the name beside each, in this reader's own spelling — the third list a
    // divergence refusal reads (#337). Asserted here rather than left to the Linux
    // acceptance leg: deleting the `names.append` above passed every unit test until
    // this line existed, while the fs_usage side had its alignment pinned.
    try std.testing.expectEqual(p.classes.items.len, p.names.items.len);
    try std.testing.expectEqualStrings("unlinkat", p.names.items[3]);
    try std.testing.expectEqualStrings("renameat", p.names.items[4]);
    // The loader's own openat is outside the state directory and must not be counted;
    // the close is still *examined* (in scope), just not compared.
    try std.testing.expectEqual(@as(usize, 6), p.lines_in_scope);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expect(!p.childTouched());
    try std.testing.expectEqual(@as(usize, 0), p.children);
}

test "relative paths resolve by annotation and by tracked cwd (ADR 0006)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // aarch64: every relative call is an *at with an AT_FDCWD annotation, tracked across
    // a relative chdir. x86-64: the legacy forms carry no annotation and resolve against
    // the tracked cwd. Both spellings of the same operations must reach the same classes.
    const annotated =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  mkdirat(AT_FDCWD</repo>, "state/sub", 0755) = 0
        \\9  openat(AT_FDCWD</repo>, "state/a", O_WRONLY|O_CREAT, 0644) = 3</repo/state/a>
        \\9  chdir("state") = 0
        \\9  mkdirat(AT_FDCWD</repo/state>, "sub2", 0755) = 0
        \\
    ;
    const a = try parse(arena_state.allocator(), annotated, "/repo/state", "", "/repo");
    const want = [_]contract.OpClass{ .mkdir, .open, .mkdir };
    try std.testing.expectEqualSlices(contract.OpClass, &want, a.classes.items);

    const legacy =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  mkdir("state/sub", 0755) = 0
        \\9  open("state/a", O_WRONLY|O_CREAT, 0644) = 3
        \\9  chdir("state") = 0
        \\9  mkdir("sub2", 0755) = 0
        \\
    ;
    const l = try parse(arena_state.allocator(), legacy, "/repo/state", "", "/repo");
    try std.testing.expectEqualSlices(contract.OpClass, &want, l.classes.items);
}

test "a failed chdir does not move the tracked cwd" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The relative mkdir must still resolve against /repo, not the directory the failed
    // chdir named — otherwise a failed chdir could push operations out of scope.
    const text =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  chdir("elsewhere") = -1 ENOENT (No such file or directory)
        \\9  mkdir("state/sub", 0755) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/repo/state", "", "/repo");
    const want = [_]contract.OpClass{.mkdir};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
}

test "a state-directory string inside a write buffer is not scope" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The false-positive the whole-line scan had: the write is to fd 1 (a pipe), and the
    // buffer merely contains the state path. It must not be counted as a state write.
    const text =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  write(1</dev/pts/0>, "/tmp/s/key.json\n", 16) = 16
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expectEqual(@as(usize, 0), p.lines_in_scope);
}

test "a symlink whose content spells the state directory is judged by its link path" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // symlinkat(target, dirfd, linkpath): the first argument is the link *content*, not
    // a path this run touches. A target of "/tmp/s/x" with a linkpath outside the state
    // directory must not be scoped in.
    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  symlinkat("/tmp/s/secret", AT_FDCWD</work>, "/other/link") = 0
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), o.unsupported);
    try std.testing.expectEqual(@as(usize, 0), o.lines_in_scope);

    // A symlink whose *link path* is inside the state directory is in scope and, since
    // contract v9 (#122), a first-class operation — both spellings reach the same class
    // the shim records.
    const inside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  symlink("../secret", "/tmp/s/link") = 0
        \\9  symlinkat("../secret2", AT_FDCWD</work>, "/tmp/s/link2") = 0
        \\
    ;
    const i = try parse(arena_state.allocator(), inside, "/tmp/s", "", "/work");
    const want = [_]contract.OpClass{ .symlink, .symlink };
    try std.testing.expectEqualSlices(contract.OpClass, &want, i.classes.items);
    try std.testing.expectEqual(@as(?[]const u8, null), i.unsupported);
}

test "ownership and permission writes are recorded-only, from anyone (#121)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The two measured shapes from the #118 cohort — sqlite's journal fchown (fd
    // form) and devtodo's fchmodat (path form) — plus a legacy chmod, all on the
    // state directory, interleaved with a real write. The write must still be the
    // only counted class; the metadata must be observed, not `unsupported`.
    const subject =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  openat(AT_FDCWD</work>, "/tmp/s/db", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/db>
        \\9  fchown(3</tmp/s/db>, 0, 0) = 0
        \\9  write(3</tmp/s/db>, "x", 1) = 1
        \\9  fchmodat(AT_FDCWD</work>, "/tmp/s/db", 0600, 0) = 0
        \\9  fchmodat2(AT_FDCWD</work>, "/tmp/s/db", 0600, AT_SYMLINK_NOFOLLOW) = 0
        \\9  chmod("/tmp/s/db", 0644) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), subject, "/tmp/s", "", "/work");
    const want = [_]contract.OpClass{ .open, .write };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expectEqual(@as(usize, 4), p.metadata_observed.items.len);
    try std.testing.expectEqualStrings("fchown", p.metadata_observed.items[0]);
    try std.testing.expectEqualStrings("fchmodat", p.metadata_observed.items[1]);
    try std.testing.expectEqualStrings("fchmodat2", p.metadata_observed.items[2]);
    try std.testing.expectEqualStrings("chmod", p.metadata_observed.items[3]);

    // A CHILD's metadata write bypasses the touch condition for the same reason it
    // bypasses `unsupported`: it changes nothing the verdict judges.
    const child =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\12  fchmodat(AT_FDCWD</work>, "/tmp/s/db", 0600, 0) = 0
        \\
    ;
    const c = try parse(arena_state.allocator(), child, "/tmp/s", "", "/work");
    try std.testing.expect(!c.childTouched());
    try std.testing.expectEqual(@as(usize, 1), c.metadata_observed.items.len);

    // Outside the state directory: none of our business, not even as a note.
    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  chmod("/etc/passwd", 0644) = -1 EPERM (Operation not permitted)
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), o.metadata_observed.items.len);

    // Unresolvable (a relative chmod with no cwd): counted as observed —
    // over-reporting an exclusion is the honest direction — and never `unsupported`.
    const unresolvable =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  chmod("state/db", 0644) = 0
        \\
    ;
    const u = try parse(arena_state.allocator(), unresolvable, "/tmp/s", "", "");
    try std.testing.expectEqual(@as(?[]const u8, null), u.unsupported);
    try std.testing.expectEqual(@as(usize, 1), u.metadata_observed.items.len);
}

test "timestamp writes are recorded-only, like ownership and permission (#190)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The measured shape from the cohort-2 Mercurial explore: CPython's shutil
    // touches timestamps once per transaction-backup copy. All five spellings —
    // the *at path form, the NULL-path form glibc emits for futimens (resolves
    // `.unresolvable`, counted as observed — the honest over-reporting
    // direction), and the three legacy forms — interleaved with a real write.
    // The write must still be the only counted class beside the open; the
    // timestamps must be observed, never `unsupported`.
    const subject =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  openat(AT_FDCWD</work>, "/tmp/s/db", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/db>
        \\9  write(3</tmp/s/db>, "x", 1) = 1
        \\9  utimensat(AT_FDCWD</work>, "/tmp/s/db", [{tv_sec=1, tv_nsec=0}, {tv_sec=1, tv_nsec=0}], 0) = 0
        \\9  utimensat(3</tmp/s/db>, NULL, [UTIME_NOW, UTIME_NOW], 0) = 0
        \\9  utimes("/tmp/s/db", [{tv_sec=1, tv_usec=0}, {tv_sec=1, tv_usec=0}]) = 0
        \\9  futimesat(AT_FDCWD</work>, "/tmp/s/db", [{tv_sec=1, tv_usec=0}, {tv_sec=1, tv_usec=0}]) = 0
        \\9  utime("/tmp/s/db", {actime=1, modtime=1}) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), subject, "/tmp/s", "", "/work");
    const want = [_]contract.OpClass{ .open, .write };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expectEqual(@as(usize, 5), p.metadata_observed.items.len);
    try std.testing.expectEqualStrings("utimensat", p.metadata_observed.items[0]);
    try std.testing.expectEqualStrings("utimensat", p.metadata_observed.items[1]);
    try std.testing.expectEqualStrings("utimes", p.metadata_observed.items[2]);
    try std.testing.expectEqualStrings("futimesat", p.metadata_observed.items[3]);
    try std.testing.expectEqualStrings("utime", p.metadata_observed.items[4]);

    // Outside the state directory: none of our business, not even as a note.
    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  utimensat(AT_FDCWD</work>, "/etc/passwd", [{tv_sec=1, tv_nsec=0}, {tv_sec=1, tv_nsec=0}], 0) = 0
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), o.metadata_observed.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), o.unsupported);

    // The NULL-path form on an OUTSIDE descriptor is still counted: the path is
    // unresolvable, and the exclusion over-reports rather than scoping through
    // the fd. This pins the over-report as intent, not accident.
    const outside_fd =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  utimensat(3</etc/passwd>, NULL, [UTIME_NOW, UTIME_NOW], 0) = 0
        \\
    ;
    const of = try parse(arena_state.allocator(), outside_fd, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), of.metadata_observed.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), of.unsupported);
}

test "the conservative net is still alive after the symlink class landed" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The falsification #122 demands for its own change: adding symlink to the class
    // table must not have widened what silently passes. mknod is the next-nearest
    // state-touching syscall with no class — it must still route to `unsupported`
    // through the whole-line net, exactly as symlink itself did before v9.
    const text =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  mknod("/tmp/s/fifo", S_IFIFO|0644, 0) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mknod", p.unsupported.?);
}

test "link is first-class and counts when either endpoint is inside" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The git loose-object idiom: link a tmp object into place.
    const in_in =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  linkat(AT_FDCWD</repo>, "state/tmp_obj", AT_FDCWD</repo>, "state/ab/final", 0) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), in_in, "/repo/state", "", "/repo");
    const want = [_]contract.OpClass{.link};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);

    // outside -> state: the source is outside, the new name is inside. Still a state
    // mutation, still counted (the either-endpoint rule).
    const out_in =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  link("/tmp/scratch/obj", "/repo/state/name") = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), out_in, "/repo/state", "", "/repo");
    try std.testing.expectEqualSlices(contract.OpClass, &want, q.classes.items);

    // AT_EMPTY_PATH links a descriptor: unplaceable source, refused.
    const empty =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  linkat(3</tmp/x>, "", AT_FDCWD</repo>, "state/name", AT_EMPTY_PATH) = 0
        \\
    ;
    const r = try parse(arena_state.allocator(), empty, "/repo/state", "", "/repo");
    try std.testing.expectEqualStrings("linkat(AT_EMPTY_PATH)", r.unsupported.?);
}

test "an unresolvable relative path refuses instead of dropping" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // A legacy mkdir with no annotation and no known cwd (the engine passed none) cannot
    // be placed. It must not be silently dropped — a state mutation the tool cannot see.
    const text =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  mkdir("state/sub", 0755) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/repo/state", "", "");
    try std.testing.expectEqualStrings("mkdir", p.unsupported.?);
}

test "the state alt spelling is inside the state directory" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // macOS hands the subject /tmp/x while the engine resolved /private/tmp/x; a path
    // under either spelling must be in scope.
    const text =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  openat(AT_FDCWD</work>, "/tmp/x/key", O_WRONLY|O_CREAT, 0644) = 3</tmp/x/key>
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/private/tmp/x", "/tmp/x", "/work");
    const want = [_]contract.OpClass{.open};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
}

test "a fs-sharing clone is refused as a boundary" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  clone(child_stack=NULL, flags=CLONE_FS|SIGCHLD) = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("clone", p.boundary.?);
}

test "a write-incapable open by the subject leaves the comparison, fail-closed" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The rustix shape from the first real target: a read-only directory open the shim
    // cannot see. Excluded here so the two accounts can agree about what matters.
    const symbolic =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 4</tmp/s>
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\
    ;
    const p = try parse(arena_state.allocator(), symbolic, "/tmp/s", "", "/work");
    const expected = [_]contract.OpClass{.open};
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);

    // Fail-closed: numeric flags are not read-only, they are unparsed. Counted as
    // before — if that miscounts, the run ends UNKNOWN, never PASS.
    const numeric =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", 0x241) = 3</tmp/s/key.json>
        \\
    ;
    const q = try parse(arena_state.allocator(), numeric, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), q.classes.items.len);

    // O_RDONLY|O_CREAT creates but cannot write: a mutation, addressable, counted.
    const creating =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/marker", O_RDONLY|O_CREAT, 0644) = 3</tmp/s/marker>
        \\
    ;
    const r = try parse(arena_state.allocator(), creating, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), r.classes.items.len);

    // creat spells no flags and always creates: counted.
    const via_creat =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    creat("/tmp/s/new.json", 0644) = 3</tmp/s/new.json>
        \\
    ;
    const s = try parse(arena_state.allocator(), via_creat, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), s.classes.items.len);

    // openat2 carries its flags inside the how struct; the symbolic token is still there.
    const via_openat2 =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat2(AT_FDCWD, "/tmp/s/key.json", {flags=O_RDONLY|O_CLOEXEC, mode=0, resolve=0}, 24) = 3</tmp/s/key.json>
        \\
    ;
    const t = try parse(arena_state.allocator(), via_openat2, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), t.classes.items.len);

    // An invalid access mode (both low bits set) is spelled `O_ACCMODE` by strace, and
    // the shim counts it (`!= O_RDONLY`). This side must agree — the invalid case must
    // not be the one place the two predicates split.
    const invalid_accmode =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", O_ACCMODE|O_CLOEXEC) = -1 EINVAL (Invalid argument)
        \\
    ;
    const u = try parse(arena_state.allocator(), invalid_accmode, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), u.classes.items.len);
}

test "unlinkat with AT_REMOVEDIR is a directory removal, matching the shim" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // aarch64 Linux has no rmdir syscall; glibc's rmdir(3) becomes this. The shim
    // records .rmdir because it interposes the libc entry point, so a name-only mapping
    // here would disagree and blame a correct target.
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\unlinkat(AT_FDCWD, "/tmp/s/sub", AT_REMOVEDIR) = 0
        \\unlinkat(AT_FDCWD, "/tmp/s/key.json", 0) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    const expected = [_]contract.OpClass{ .rmdir, .unlink };
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);
}

test "the AT_REMOVEDIR flag is read from the flags argument, not from the line" {
    // A filename is attacker-controlled in the only sense that matters here: the target
    // chooses it. Searching the whole line for the flag name lets a *file* called
    // AT_REMOVEDIR be classified as a *directory removal*, which diverges from the shim
    // and reports UNKNOWN for a target that did nothing wrong.
    try std.testing.expect(!unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/AT_REMOVEDIR.bak\", 0) = 0"));
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", AT_REMOVEDIR) = 0"));
    // Numeric spelling: `strace -X raw`, and some builds by default.
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", 0x200) = 0"));
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", 512) = 0"));
    try std.testing.expect(!unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/f\", 0) = 0"));
    // A pid prefix must not shift the argument positions.
    try std.testing.expect(unlinkatRemovesDir("13    unlinkat(AT_FDCWD, \"/tmp/s/sub\", AT_REMOVEDIR) = 0"));
}

test "arguments are split on top-level commas only" {
    const line = "renameat(AT_FDCWD</w>, \"/tmp/s/a,b\", AT_FDCWD</w>, \"/tmp/s/c\") = 0";
    try std.testing.expectEqualStrings("\"/tmp/s/a,b\"", syscallArg(line, 1).?);
    try std.testing.expectEqualStrings("\"/tmp/s/c\"", syscallArg(line, 3).?);
    try std.testing.expectEqual(@as(?[]const u8, null), syscallArg(line, 4));
    // A struct argument is one argument, however many commas it contains.
    const st = "newfstatat(AT_FDCWD, \"/tmp/s/k\", {st_mode=S_IFREG|0644, st_size=6}, 0) = 0";
    try std.testing.expectEqualStrings("0", syscallArg(st, 3).?);
}

test "a syscall v0.1 does not model is reported rather than skipped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // `mknod` stands where `copy_file_range` used to: a state-directory syscall that
    // changes persistent state and has no class. The example had to move when #244
    // classified copy_file_range — and the case it demonstrates has not, so the
    // demonstration keeps a live subject rather than retiring with its old one.
    // (`spike/acceptance.sh` drives the same syscall end to end for the same reason.)
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\mknod("/tmp/s/fifo", S_IFIFO|0644) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mknod", p.unsupported.?);
}

test "renameat2's flags decide whether it is a rename at all (#256)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    // RENAME_NOREPLACE is a plain rename that declines to clobber — the shape a real
    // target produced (`spike/cohort2/probes/raw/bun.strace`, bun's cache write).
    const noreplace =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/key.json.tmp", AT_FDCWD, "/tmp/s/key.json", RENAME_NOREPLACE) = 0
        \\
    ;
    const p_nr = try parse(a, noreplace, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_nr.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.rename, p_nr.classes.items[0]);
    try std.testing.expectEqual(@as(?[]const u8, null), p_nr.unsupported);

    // EXCHANGE swaps two files: both names survive and both contents move, which the
    // snapshot/restore model does not reproduce. Refused by flag name rather than
    // counted, so the report says which flag it refused on.
    const exchange =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/a", AT_FDCWD, "/tmp/s/b", RENAME_EXCHANGE) = 0
        \\
    ;
    const p_ex = try parse(a, exchange, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("renameat2(RENAME_EXCHANGE)", p_ex.unsupported.?);
    try std.testing.expectEqual(@as(usize, 0), p_ex.classes.items.len);

    const whiteout =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/a", AT_FDCWD, "/tmp/s/b", RENAME_WHITEOUT) = 0
        \\
    ;
    const p_wo = try parse(a, whiteout, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("renameat2(RENAME_WHITEOUT)", p_wo.unsupported.?);

    // The flag test reads argument 4, not the line: a FILENAME spelling a flag must
    // not refuse a plain rename. Same trap the AT_REMOVEDIR test guards above.
    const lookalike =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/RENAME_EXCHANGE.bak", AT_FDCWD, "/tmp/s/key.json", 0) = 0
        \\
    ;
    const p_lk = try parse(a, lookalike, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p_lk.unsupported);
    try std.testing.expectEqual(contract.OpClass.rename, p_lk.classes.items[0]);

    // `strace -X raw` (and any build without the flag decoder) prints the number.
    // Reading only the symbolic spelling would let EXCHANGE through as a plain
    // rename — the same fail-open `unlinkatRemovesDir` already guards against.
    const numeric =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/a", AT_FDCWD, "/tmp/s/b", 0x2) = 0
        \\
    ;
    const p_num = try parse(a, numeric, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("renameat2(RENAME_EXCHANGE)", p_num.unsupported.?);
}

test "a copy's scope is decided by its destination, not its argument 0 (#244)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    // Into the state directory: a write that counts. Argument 0 is the SOURCE and
    // sits outside, so an argument-0 reading calls this out of scope and loses it.
    const into =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\copy_file_range(3</other/a>, NULL, 4</tmp/s/key.json>, NULL, 6, 0) = 6
        \\
    ;
    const p_in = try parse(a, into, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_in.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.write, p_in.classes.items[0]);
    try std.testing.expectEqual(@as(?[]const u8, null), p_in.unsupported);

    // Out of the state directory: the state is only read, so nothing is counted. An
    // argument-0 reading calls this a write — the false FAIL side of the same bug.
    const out_of =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\copy_file_range(3</tmp/s/key.json>, NULL, 4</other/b>, NULL, 6, 0) = 6
        \\
    ;
    const p_out = try parse(a, out_of, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), p_out.classes.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), p_out.unsupported);

    // sendfile needs no table entry: its destination is already argument 0. Pinned
    // here so a later "simplification" that drops the default cannot pass quietly.
    const sf =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\sendfile(4</tmp/s/key.json>, 3</other/a>, NULL, 6) = 6
        \\
    ;
    const p_sf = try parse(a, sf, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_sf.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.write, p_sf.classes.items[0]);

    // The default itself: an ordinary fd write is still read from argument 0.
    const w =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\pwritev(3</tmp/s/key.json>, [{iov_base="key=", iov_len=4}], 1, 0) = 4
        \\
    ;
    const p_w = try parse(a, w, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_w.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.write, p_w.classes.items[0]);
}

test "read-only syscalls do not enter the comparison" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\newfstatat(AT_FDCWD, "/tmp/s/key.json", {st_mode=S_IFREG|0644}, 0) = 0
        \\read(3</tmp/s/key.json>, "key=1\n", 4096) = 6
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
    try std.testing.expectEqual(@as(usize, 2), p.lines_in_scope);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
}

test "both of strace's -f pid prefixes are stripped" {
    // Bracketed form: interleaved output.
    try std.testing.expectEqualStrings("openat", syscallName("[pid  1234] openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("clone", syscallName("[pid 99] clone(child_stack=NULL) = 100").?);
    // Bare-number form: what `-f -o file` actually writes. Missing this one made every
    // line unparseable while the parser still looked like it worked.
    try std.testing.expectEqualStrings("openat", syscallName("13    openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("write", syscallName("7\twrite(3, \"x\", 1) = 1").?);
    // No prefix at all, unchanged.
    try std.testing.expectEqualStrings("write", syscallName("write(3, \"x\", 1) = 1").?);
}

test "a child that stays out of the state directory is not a refusal" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // v0.1 refused on the bare clone. The rule now is about what the child *did*: this
    // one wrote somewhere else entirely, so the subject's account remains complete and
    // the crash-point numbering remains unique.
    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  write(5</elsewhere/f>, "x", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expect(!p.childTouched());
    try std.testing.expectEqual(@as(usize, 1), p.children);
    try std.testing.expectEqual(@as(usize, 1), p.classes.items.len);
}

test "a child that writes into the state directory is the refusal condition" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // Same shape, one difference: where the child's write landed. This is the raw-clone
    // case the shim cannot see at all — the child never loaded it — and the reason
    // boundary tolerance exists only where an oracle does.
    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  write(5</tmp/s/key.json>, "x", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.childTouched());
    try std.testing.expectEqual(@as(usize, 1), p.children);
}

test "a child reading the state directory is tolerated" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // Reads consume no sequence number and change no state; refusing them would fail
    // every helper that inspects a config file. The line between read and write is the
    // read_only list, and an unknown syscall from a child falls on the refusing side.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  read(3</tmp/s/key.json>, "key=1\n", 4096) = 6
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(!p.childTouched());

    const unknown_sys =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  frobnicate(3</tmp/s/key.json>) = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), unknown_sys, "/tmp/s", "", "/work");
    try std.testing.expect(q.childTouched());
}

test "the launch execve is not mistaken for the target creating a child" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // strace's own act of starting the target appears as the first execve.
    const text =
        \\execve("/work/spike/out/toy-bug", ["toy-bug", "rotate"], 0x7ff) = 0
        \\openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expectEqual(@as(usize, 1), p.classes.items.len);
}

test "a second execve by the subject is no longer the oracle's refusal (#123)" {
    // Whether the chain of observation survived the image change is the shim's
    // evidence to give; a chain that broke leaves the shim's records short of the
    // oracle's syscalls, and the completeness comparison refuses on that. The
    // oracle itself stays quiet here — asserted so a reintroduced exec refusal
    // cannot come back silently.
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\execve("/bin/sh", ["sh", "-c", "x"], 0x7ff) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.boundary == null);
}

test "a child's execve is the child becoming something, not a refusal" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // posix_spawn appears as exactly this: a clone, then the child's execve. Refusing
    // the child's exec would refuse every spawn, which is the shape this change exists
    // to admit.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_VFORK|SIGCHLD) = 4242
        \\4242  execve("/bin/true", ["true"], 0x7ff) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expectEqual(@as(usize, 1), p.children);
}

test "a raw clone carrying CLONE_THREAD is a thread of the subject, not a child and not a boundary (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // Through v15 this line refused the run (`p.boundary != null` was the assertion
    // here). The thread's id is the subject's now, and CLONE_FS — which every pthread
    // carries — does not refuse on its own when CLONE_THREAD is beside it.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_THREAD|CLONE_SIGHAND) = 43
        \\43    write(3</tmp/s/key.json>, "k", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expect(p.isSubject(43));
    try std.testing.expect(!p.childTouched());
    try std.testing.expectEqual(@as(usize, 0), p.children);
    // The thread's write is the subject's write: it is in the class list the shim's
    // account is compared against, not in a child's touch.
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 0), p.spawns.items.len);
}

test "CLONE_FS without CLONE_THREAD still refuses (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The control for the test above: the reason a thread is admitted (its chdir is the
    // subject's) does not hold for a separate process sharing the fs context, so the
    // ADR 0006 refusal stands for it.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=0x7f, flags=CLONE_FS|SIGCHLD) = 43
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.boundary != null);
    try std.testing.expect(!p.isSubject(43));
}

test "a thread clone split across an unfinished and a resumed line is still the subject's (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The shape a second thread produces for the third: strace prints the flags on the
    // unfinished half and the new id on the resumed half. The measured capture that
    // motivated `pending_thread_clone` is the busy-thread toy's; a `clone3` refused
    // `ENOSYS` in front of it is the shape a kernel without clone3 produces, and it
    // enters nothing.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone3({flags=CLONE_VM|CLONE_FS|CLONE_THREAD, exit_signal=0}, 88) = -1 ENOSYS (Function not implemented)
        \\42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND, parent_tid=[43]) = 43
        \\43    clone(child_stack=0x7e, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND <unfinished ...>
        \\42    write(3</tmp/s/key.json>, "k", 1) = 1
        \\43    <... clone resumed>, parent_tid=[44]) = 44
        \\44    write(3</tmp/s/key.json>, "k", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.isSubject(43));
    try std.testing.expect(p.isSubject(44));
    try std.testing.expect(!p.childTouched());
    try std.testing.expectEqual(@as(usize, 0), p.children);
    try std.testing.expectEqual(@as(usize, 0), p.spawns.items.len);
    try std.testing.expectEqual(@as(usize, 2), p.classes.items.len);
}

test "a thread whose first line precedes its clone's resumption is not a child (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The ordering `spawnedPid`'s doc records for a child, on a thread: the new task is
    // scheduled before the parent's clone returns. Its out-of-scope line is read as a
    // child's at the time and struck from the count once the clone resumes.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND <unfinished ...>
        \\43    set_robust_list(0x7e, 24) = 0
        \\42    <... clone resumed>, parent_tid=[43]) = 43
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.isSubject(43));
    try std.testing.expectEqual(@as(usize, 0), p.children);
}

test "a thread a child created stays the child's (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The caller of the thread clone is a child, not a subject id, so the thread is not
    // entered — and its write is a touch, the way any of the child's writes would be.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND) = 4243
        \\4243  write(3</tmp/s/key.json>, "k", 1) = 1
        \\42    wait4(4242, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(!p.isSubject(4243));
    try std.testing.expect(p.childTouched());
}

test "syscallArg reads the argument an unfinished call ran out on (v16)" {
    // The measured shape: an fd-only call, split by another thread's line. Before this
    // the reader found no `)` and answered null, so `fsync` never reached the class list.
    try std.testing.expectEqualStrings("4</tmp/s/k>", syscallArg("50    fsync(4</tmp/s/k> <unfinished ...>", 0).?);
    // A later argument of a wider call, same ending.
    try std.testing.expectEqualStrings("6", syscallArg("50    write(4</tmp/s/k>, \"key=2\\n\", 6 <unfinished ...>", 2).?);
    // And an index past the arguments that were printed is still nothing.
    try std.testing.expectEqual(@as(?[]const u8, null), syscallArg("50    fsync(4</tmp/s/k> <unfinished ...>", 1));
    // The finished shapes read as they did.
    try std.testing.expectEqualStrings("4</tmp/s/k>", syscallArg("50    fsync(4</tmp/s/k>) = 0", 0).?);
}

test "an unshimmed child detaching is caught by the oracle" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The group kill no longer reaches a process that setsids away, and a child that
    // never loaded the shim records nothing. The oracle is the only witness.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  setsid()                          = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.boundary != null);

    // The subject's own setsid/setpgid lines are the shim's to judge — its wrapper
    // knows whether the call moved anything, and this parser does not.
    const own =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    setpgid(0, 0)                     = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), own, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), q.boundary);
}

test "a shared writable mapping of a state file is a mutation nobody models" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // Dirtying MAP_SHARED pages changes the file with no later write syscall for
    // either observer to see. From the subject: unsupported. From a child: the touch.
    const subject =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const p = try parse(arena_state.allocator(), subject, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mmap(PROT_WRITE|MAP_SHARED)", p.unsupported.?);

    const child =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const q = try parse(arena_state.allocator(), child, "/tmp/s", "", "/work");
    try std.testing.expect(q.childTouched());

    // A private or read-only mapping changes nothing on disk and stays tolerated.
    const private =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const r = try parse(arena_state.allocator(), private, "/tmp/s", "", "/work");
    try std.testing.expect(!r.childTouched());
}

test "a child's read-only open is a read, and its writing open is the touch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const reading =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  openat(AT_FDCWD, "/tmp/s/key.json", O_RDONLY|O_CLOEXEC) = 3</tmp/s/key.json>
        \\
    ;
    const p = try parse(arena_state.allocator(), reading, "/tmp/s", "", "/work");
    try std.testing.expect(!p.childTouched());

    const writing =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\
    ;
    const q = try parse(arena_state.allocator(), writing, "/tmp/s", "", "/work");
    try std.testing.expect(q.childTouched());

    // creat never spells its flags, and it always creates.
    const creating =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  creat("/tmp/s/new.json", 0644) = 3</tmp/s/new.json>
        \\
    ;
    const r = try parse(arena_state.allocator(), creating, "/tmp/s", "", "/work");
    try std.testing.expect(r.childTouched());
}

test "a filename spelling a flag does not change how the call is classified" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The target chooses its filenames; the classifier must read flags from the flags
    // argument only. Both cases below are harmless operations wearing dangerous names.
    const read_with_scary_name =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  openat(AT_FDCWD, "/tmp/s/O_CREAT.bak", O_RDONLY|O_CLOEXEC) = 3</tmp/s/O_CREAT.bak>
        \\
    ;
    const p = try parse(arena_state.allocator(), read_with_scary_name, "/tmp/s", "", "/work");
    try std.testing.expect(!p.childTouched());

    const private_map_of_scary_name =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, 3</tmp/s/PROT_WRITE.MAP_SHARED.log>, 0) = 0x7f
        \\
    ;
    const q = try parse(arena_state.allocator(), private_map_of_scary_name, "/tmp/s", "", "/work");
    try std.testing.expect(!q.childTouched());
}

test "pids are read from both prefix spellings" {
    try std.testing.expectEqual(@as(?u32, 1234), pidOf("[pid  1234] openat(AT_FDCWD, \"x\") = 3"));
    try std.testing.expectEqual(@as(?u32, 13), pidOf("13    openat(AT_FDCWD, \"x\") = 3"));
    try std.testing.expectEqual(@as(?u32, 7), pidOf("7\twrite(3, \"x\", 1) = 1"));
    try std.testing.expectEqual(@as(?u32, null), pidOf("write(3, \"x\", 1) = 1"));
}

test "compare finds the first divergence and the direction of it" {
    const a = [_]contract.OpClass{ .open, .write, .rename };
    try std.testing.expectEqual(@as(?Finding, null), compare(&a, &a));

    // The raw-syscall case: the oracle saw everything, the shim saw nothing.
    const nothing = [_]contract.OpClass{};
    const missed = compare(&nothing, &a).?;
    try std.testing.expectEqual(@as(usize, 0), missed.missed.index);
    try std.testing.expectEqual(contract.OpClass.open, missed.missed.class);

    // A shorter oracle means the shim invented an operation.
    const short = [_]contract.OpClass{ .open, .write };
    const phantom = compare(&a, &short).?;
    try std.testing.expectEqual(contract.OpClass.rename, phantom.phantom.class);
    // The index is exactly the oracle's length, and that is load-bearing beyond this
    // function: a phantom is by definition a position the oracle's account does not
    // reach, so there is no oracle line to name there. `divergenceDetail` guards its
    // read with `index < oracle_lines.len` for that reason, and `divergence_syscall`
    // (#337) is written inside that guard — so the field stays absent on this refusal
    // rather than naming the wrong operation.
    try std.testing.expectEqual(short.len, phantom.phantom.index);

    // Divergence in the middle is reported at the position it happens.
    const swapped = [_]contract.OpClass{ .open, .unlink, .rename };
    const mid = compare(&a, &swapped).?;
    try std.testing.expectEqual(@as(usize, 1), mid.missed.index);
}

test "every fd syscall the classifier knows declares which argument holds its descriptor (#280)" {
    // `fdSyscallInScope` reads one argument and decides scope from it. Which argument
    // comes from `fd_write_args`, defaulting to 0 -- a default that used to apply to
    // anything nobody had thought about. This makes the classifier and the two tables
    // agree: exactly one of them names each fd syscall, so a new `known` entry is a
    // decision rather than an inheritance.
    for (known) |m| {
        if (pathSpec(m.name) != null) continue; // a path syscall, not scoped by fd
        var declared: usize = 0;
        for (fd_write_args) |w| {
            if (std.mem.eql(u8, w.name, m.name)) declared += 1;
        }
        for (fd_arg0) |n| {
            if (std.mem.eql(u8, n, m.name)) declared += 1;
        }
        if (declared != 1) {
            std.debug.print(
                "fd syscall '{s}' is named by {d} of the two argument tables, wanted exactly 1\n",
                .{ m.name, declared },
            );
            return error.FdArgumentUndeclared;
        }
    }
    // The tables name nothing the classifier does not know, and nothing that is scoped
    // by a path rather than a descriptor: either kind of row would sit here reading as
    // coverage while the forward loop skipped past it. Review measured the second one --
    // adding "open" to `fd_arg0` left the suite green, because the forward loop
    // `continue`s on a path syscall and the reverse check only asked about `classify`.
    for (fd_arg0) |n| {
        try std.testing.expect(classify(n) != null);
        try std.testing.expect(pathSpec(n) == null);
    }
    for (fd_write_args) |w| {
        try std.testing.expect(classify(w.name) != null);
        try std.testing.expect(pathSpec(w.name) == null);
    }
}

test "a wait's reaped child is read from both spellings, and from waitid's siginfo (v15)" {
    // Every line here except the `waitid` one is copied out of a capture taken with the
    // engine's own flags (`spike/followup-item3/artifacts/`), because the shapes this has
    // to survive are not the ones a hand-written example produces: a wait interrupted by
    // another child comes back as a `resumed>` line whose first parenthesis belongs to
    // `WIFEXITED(s)`, and `syscallName` answers null for it.
    try std.testing.expectEqual(@as(?u64, 29), reapedPid("28    <... wait4 resumed>[{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 29"));
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WNOHANG, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, 40), reapedPid("38    wait4(40, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 40"));

    // The call going in carries no answer yet — the child is still running.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    wait4(29,  <unfinished ...>"));
    // Nothing to reap, and a wait the arrival of another child's SIGCHLD restarted.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, 0xffffd4dafb20, WNOHANG, NULL) = -1 ECHILD (No child processes)"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("38    <... wait4 resumed>0xffffd8be1d4c, 0, NULL) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)"));

    // `waitid` returns 0 and names the child in its siginfo, so the return value is the
    // wrong field for this one member of the family.
    try std.testing.expectEqual(@as(?u64, 4242), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=4242, si_uid=0, si_status=0}, WEXITED, NULL) = 0"));

    // Not waits. The second is the control that matters: a line ending in a number is
    // not a reap, and a reader that only looked at the tail would count every successful
    // `openat` as one.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    exit_group(0)                     = ?"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    openat(AT_FDCWD</w>, \"/tmp/s/a\", O_WRONLY|O_CREAT, 0644) = 29"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    <... openat resumed>) = 29"));
    // A name that merely starts with one of the family's.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    wait4ever(1) = 7"));
}

test "the parse collects who wrote and who was reaped (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The slice's shape: the subject writes, an awaited child writes, the subject writes
    // again. Both sets are what the admission compares against the shim's own account.
    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/a", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/a>
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\42    wait4(4242,  <unfinished ...>
        \\4242  rename("/tmp/s/a", "/tmp/s/b") = 0
        \\4242  +++ exited with 0 +++
        \\42    <... wait4 resumed>[{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4242
        \\42    openat(AT_FDCWD, "/tmp/s/c", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/c>
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    // Three mutations in line order: the subject's, the child's, the subject's again —
    // and the reap between the child's and the subject's second, which is what makes the
    // shape a hand-off rather than a race.
    try std.testing.expectEqual(@as(usize, 3), p.mutations.items.len);
    try std.testing.expectEqual(@as(u64, 42), p.mutations.items[0].id);
    try std.testing.expectEqual(@as(u64, 4242), p.mutations.items[1].id);
    try std.testing.expectEqual(@as(u64, 42), p.mutations.items[2].id);
    try std.testing.expectEqual(@as(usize, 1), p.reaps.items.len);
    try std.testing.expectEqual(@as(u64, 4242), p.reaps.items[0].id);
    try std.testing.expect(p.reaps.items[0].at > p.mutations.items[1].at);
    try std.testing.expect(p.reaps.items[0].at < p.mutations.items[2].at);
    // The subject's own two operations are still the ones compared against the shim's
    // account, unchanged by any of this.
    try std.testing.expectEqual(@as(usize, 2), p.classes.items.len);
}

test "a child nobody waited for leaves the reaped set empty (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // The control for the test above, and the one condition of the three that this
    // parser alone decides: the same capture with the wait removed.
    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  rename("/tmp/s/a", "/tmp/s/b") = 0
        \\42    openat(AT_FDCWD, "/tmp/s/c", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/c>
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.childTouched());
    try std.testing.expectEqual(@as(usize, 0), p.reaps.items.len);
}

test "a pid coming back from a wait is not always a collection (v15)" {
    // The two shapes that report a child without collecting it. Both would close the
    // window a writing child is judged in, which admits a run that should refuse — the
    // direction a guard must not fail in.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTSTP}], WUNTRACED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, [{WIFCONTINUED(s)}], WCONTINUED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=4242, si_status=0}, WEXITED|WNOWAIT, NULL) = 0"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_STOPPED, si_pid=4242, si_status=SIGTSTP}, WSTOPPED, NULL) = 0"));

    // The control: the same calls when the child really did end. Without these the four
    // above would be satisfied by a function that answered null to everything.
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WUNTRACED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(-1, [{WIFSIGNALED(s) && WTERMSIG(s) == SIGKILL}], 0, NULL) = 53"));
    // A wait with no status buffer says nothing about stopping, and a caller that passed
    // none could not have seen a stop either.
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(53, NULL, 0, NULL) = 53"));
}

test "where a child was created, read from both spellings (v15)" {
    // `fork` and `posix_spawn` both reach the kernel as `clone` here; the resumed form
    // appears whenever the child's own lines interleave with the call, which the
    // committed `inv-todoman` capture shows happening for an ordinary fork+exec.
    try std.testing.expectEqual(@as(?u64, 29), spawnedPid("28    clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|SIGCHLD, child_tidptr=0xff) = 29"));
    try std.testing.expectEqual(@as(?u64, 26), spawnedPid("25    <... clone resumed>)              = 26"));
    try std.testing.expectEqual(@as(?u64, 50), spawnedPid("49    clone(child_stack=0xffff97ff0000, flags=CLONE_VM|CLONE_VFORK|SIGCHLD) = 50"));
    try std.testing.expectEqual(@as(?u64, 4242), spawnedPid("42    clone3({flags=0, exit_signal=SIGCHLD}, 88) = 4242"));

    // A thread is not a child something waits for; it is refused by name elsewhere, and
    // reading its creation as a window would be reading the wrong event.
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND) = 43"));
    // The call going in, and the failure.
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    clone(child_stack=NULL, flags=SIGCHLD <unfinished ...>"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    clone(child_stack=NULL, flags=SIGCHLD) = -1 EAGAIN (Resource temporarily unavailable)"));
    // In the child, where clone returns 0. The child does not learn its own pid here.
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("29    <... clone resumed>)              = 0"));
    // Not spawns. The second is the control: a line ending in a number is not a creation.
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    wait4(29, NULL, 0, NULL) = 29"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    openat(AT_FDCWD, \"/tmp/s/a\", O_WRONLY) = 29"));
}

test "a child's relative path is not resolved against the subject's directory (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The x86-64 shape: glibc issues the legacy `rename`, so the line carries no dirfd
    // annotation and nothing in it says where the child's working directory was. The
    // subject's is `/work`, and resolving against it would place this write outside the
    // judged state — silently, in a run that has no other witness for it, because this
    // child never loaded the shim.
    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  chdir("/tmp/s") = 0
        \\4242  rename("a", "b") = 0
        \\42    wait4(4242, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    // Unplaceable, and unplaceable is judged the way in-scope is: the run has a writer
    // whose operations nobody can locate.
    try std.testing.expect(p.childTouched());

    // The control, and the reason this test is not satisfied by a parser that gave up on
    // every child: the same child writing through an absolute path is placed, and placed
    // OUTSIDE, so it is not a touch at all.
    const outside =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  rename("/elsewhere/a", "/elsewhere/b") = 0
        \\42    wait4(4242, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4242
        \\
    ;
    const q = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expect(!q.childTouched());

    // And the subject's own relative path still resolves against its cwd, which is what
    // the tracked directory is for. `/work/key` is outside `/tmp/s`; the point is that it
    // was placed at all rather than falling to unresolvable.
    const subject_relative =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    rename("key", "key.bak") = 0
        \\
    ;
    const r = try parse(arena_state.allocator(), subject_relative, "/tmp/s", "", "/work");
    try std.testing.expect(!r.childTouched());
    try std.testing.expectEqual(@as(usize, 0), r.classes.items.len);
}
