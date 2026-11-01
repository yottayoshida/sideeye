const std = @import("std");
const contract = @import("contract");

pub const Finding = union(enum) {
    missed: struct { index: usize, class: contract.OpClass },
    unsupported: []const u8,
    phantom: struct { index: usize, class: contract.OpClass },
};

const Mapping = struct { name: []const u8, class: contract.OpClass };

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
    .{ .name = "fallocate", .class = .truncate },
    .{ .name = "mkdir", .class = .mkdir },
    .{ .name = "mkdirat", .class = .mkdir },
    .{ .name = "rmdir", .class = .rmdir },
    .{ .name = "link", .class = .link },
    .{ .name = "linkat", .class = .link },
    .{ .name = "symlink", .class = .symlink },
    .{ .name = "symlinkat", .class = .symlink },
    .{ .name = "close", .class = .close },
};

const PathArg = struct { dirfd: ?usize, path: usize };

/// The link *content* of `symlink`/`symlinkat` is deliberately not listed: it is a
/// string the target chose, not a path this run touches, and resolving it would let a
/// link whose content spells the state directory be mis-scoped.
const PathSpec = struct { name: []const u8, args: []const PathArg };
const path_syscalls = [_]PathSpec{
    .{ .name = "openat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "openat2", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "mkdirat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "unlinkat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "symlinkat", .args = &.{.{ .dirfd = 1, .path = 2 }} },
    .{ .name = "renameat", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    .{ .name = "renameat2", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    .{ .name = "linkat", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
    .{ .name = "open", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "creat", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "mkdir", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "rmdir", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "unlink", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "truncate", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "symlink", .args = &.{.{ .dirfd = null, .path = 1 }} },
    .{ .name = "rename", .args = &.{ .{ .dirfd = null, .path = 0 }, .{ .dirfd = null, .path = 1 } } },
    .{ .name = "link", .args = &.{ .{ .dirfd = null, .path = 0 }, .{ .dirfd = null, .path = 1 } } },
    // Not scoped by `touchesStateDir` like the rest of the unnamed calls: it sees absolute
    // strings only, and a relative attribute write would go unreported in `metadata_writes`.
    .{ .name = "setxattr", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "lsetxattr", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "removexattr", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "lremovexattr", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "setxattrat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "removexattrat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
};

const xattr_writes = [_][]const u8{
    "setxattr",    "lsetxattr",    "fsetxattr",    "setxattrat",
    "removexattr", "lremovexattr", "fremovexattr", "removexattrat",
};

fn isXattrWrite(name: []const u8) bool {
    for (xattr_writes) |x| {
        if (std.mem.eql(u8, x, name)) return true;
    }
    return false;
}

fn specIn(table: []const PathSpec, name: []const u8) ?PathSpec {
    for (table) |s| {
        if (std.mem.eql(u8, s.name, name)) return s;
    }
    return null;
}

fn pathSpec(name: []const u8) ?PathSpec {
    return specIn(&path_syscalls, name);
}

// Calls refused inside the state, scoped by resolving their path rather than by
// `touchesStateDir`, which sees absolute spellings only and passed a relative one into the state
// by. Not in `path_syscalls`: an empty path there drops the line, and these name their
// descriptor with one.
const unclassified_path_syscalls = [_]PathSpec{
    .{ .name = "mknod", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "mknodat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "acct", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "chroot", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "uselib", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "swapon", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "swapoff", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "umount2", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "mount", .args = &.{.{ .dirfd = null, .path = 1 }} },
    .{ .name = "pivot_root", .args = &.{ .{ .dirfd = null, .path = 0 }, .{ .dirfd = null, .path = 1 } } },
    .{ .name = "fanotify_mark", .args = &.{.{ .dirfd = 3, .path = 4 }} },
    .{ .name = "fspick", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "mount_setattr", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "name_to_handle_at", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "open_tree", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "move_mount", .args = &.{ .{ .dirfd = 0, .path = 1 }, .{ .dirfd = 2, .path = 3 } } },
};

fn unclassifiedPathSpec(name: []const u8) ?PathSpec {
    return specIn(&unclassified_path_syscalls, name);
}

const at_empty_path_linux: u64 = 0x1000;

const EmptyPathTaker = struct { name: []const u8, flags: usize };
const empty_path_takers = [_]EmptyPathTaker{
    .{ .name = "linkat", .flags = 4 },
    .{ .name = "setxattrat", .flags = 2 },
    .{ .name = "removexattrat", .flags = 2 },
};

fn emptyPathNamesNothing(spec: PathSpec, line: []const u8) bool {
    var any_empty = false;
    for (spec.args, 0..) |a, i| {
        const arg = syscallArg(line, a.path) orelse continue;
        if (!std.mem.eql(u8, arg, "\"\"")) continue;
        if (i == 0) for (empty_path_takers) |t| {
            if (std.mem.eql(u8, t.name, spec.name) and
                !flagsLackEmptyPath(syscallArg(line, t.flags))) return false;
        };
        any_empty = true;
    }
    return any_empty;
}

// Flags that cannot be read are not taken for none: the attribute calls are recorded by
// neither witness, so one passed over here would be missing from `metadata_writes`.
fn flagsLackEmptyPath(flags: ?[]const u8) bool {
    const f = flags orelse return false;
    if (std.mem.indexOf(u8, f, "AT_EMPTY_PATH") != null) return false;
    if (std.fmt.parseInt(u64, f, 0)) |v| return v & at_empty_path_linux == 0 else |_| {}
    var tokens = std.mem.splitScalar(u8, f, '|');
    while (tokens.next()) |t| {
        if (!std.mem.startsWith(u8, t, "AT_")) return false;
    }
    return true;
}

const metadata_path_syscalls = [_]PathSpec{
    .{ .name = "chown", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "lchown", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "chmod", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "fchownat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "fchmodat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    // Same signature shape (dirfd, path, mode, flags). Listed from the syscall
    // family, not from what a cohort happened to hit — leaving it out would
    // re-block the exact class #121 unblocks on any newer runner (R1).
    .{ .name = "fchmodat2", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "utimensat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "futimesat", .args = &.{.{ .dirfd = 0, .path = 1 }} },
    .{ .name = "utimes", .args = &.{.{ .dirfd = null, .path = 0 }} },
    .{ .name = "utime", .args = &.{.{ .dirfd = null, .path = 0 }} },
};
const metadata_fd_syscalls = [_][]const u8{ "fchown", "fchmod" };

fn metadataPathSpec(name: []const u8) ?PathSpec {
    return specIn(&metadata_path_syscalls, name);
}

fn isMetadataFd(name: []const u8) bool {
    for (metadata_fd_syscalls) |m| {
        if (std.mem.eql(u8, m, name)) return true;
    }
    return false;
}

fn isFdSyscall(name: []const u8) bool {
    return classify(name) != null and pathSpec(name) == null;
}

const read_only = [_][]const u8{
    "stat",       "lstat",      "fstat",             "newfstatat", "statx",
    "access",     "faccessat",  "readlink",          "readlinkat", "read",
    "pread64",    "readv",      "lseek",             "getdents64", "fcntl",
    "fadvise64",  "statfs",     "fstatfs",           "dup",        "dup2",
    "dup3",       "ioctl",      "mmap",              "munmap",     "mprotect",
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
        "chdir",             "fchdir",     "faccessat2",
    "epoll_ctl",
    // The writes — `setxattr`, `removexattr` and their `l`/`f` forms — are not here: they are
    // set aside as metadata and named in the report, which a read would not be.
     "getxattr",   "lgetxattr",         "fgetxattr",  "listxattr",
    "llistxattr", "flistxattr", "inotify_add_watch", "preadv",     "preadv2",
    "poll",       "ppoll",      "select",            "pselect6",
    // Not counted as `.fsync`: `sync_file_range` writes no metadata and flushes no device
    // cache, and which of these a power-loss model would count is for ADR 0110 to decide.
      "sync_file_range",
    "syncfs",     "readahead",
};

const process_syscalls = [_][]const u8{
    "clone", "clone3", "fork", "vfork", "execve", "execveat", "unshare",
};

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
    if (i > 0 and i < line.len and (line[i] == ' ' or line[i] == '\t')) {
        return std.mem.trimStart(u8, line[i..], " \t");
    }
    return line;
}

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

/// The window a writing child is judged in starts here rather than at its first write.
/// Between the two, the parent is running with the child already alive: a mutation of its
/// own in that gap is ordered against the child's by nothing, and would be admitted if the
/// window began at the child's first operation. `spike/followup-item3/NOTES.md` recorded
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

/// Its own parser rather than `syscallName` plus a suffix, for two reasons the real
/// captures show. A wait that another child's exit interrupted comes back as
/// `<... wait4 resumed>…) = 29`, and `syscallName` answers null for that line — the first
/// `(` it finds is inside `WIFEXITED(s)`, whose prefix is not a name. And `waitid` reports
/// the reaped child in its siginfo (`si_pid=`) while returning 0, so the return value is
/// the wrong field to read for that one member of the family.
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

pub fn holdsId(list: []const Event, id: u64) bool {
    for (list) |e| {
        if (e.id == id) return true;
    }
    return false;
}

fn isSeccompRefusal(raw: []const u8) bool {
    const line = stripPidPrefix(raw);
    if (!std.mem.startsWith(u8, line, "--- SIGSYS ")) return false;
    return std.mem.indexOf(u8, line, "si_code=SYS_SECCOMP") != null;
}

/// The open family is admitted by the filter only when its flags say the call can change
/// something, so it is conditional here too: `isReadOnlyOpen` is the text form of the mask
/// the filter applies, and answers false for every name that is not an open.
///
/// The shim builds a BPF program and this reader parses text, so there is no declaration
/// for the two to share and this is a copy. **The standing drift detector is
/// `spike/check-shim-coverage.py`**, which reads both lists from the code that uses them
/// and compares them in both directions; it runs in CI and inside the acceptance suite.
/// Without it the two failure modes are unequal: a member missing here costs a retraction
/// that should have happened, which the completeness comparison refuses on loudly but in a
/// place that names neither list — while a member here that the filter does not trap is
/// silent, because nothing ever raises the signal that would use it.
fn isTrapped(name: []const u8, line: []const u8) bool {
    const set = [_][]const u8{
        "write",     "pwrite64",  "writev",    "pwritev",   "sendfile",
        "openat",    "openat2",   "renameat",  "renameat2", "unlinkat",
        "mkdirat",   "linkat",    "symlinkat", "truncate",  "ftruncate",
        "fsync",     "fdatasync", "open",      "creat",     "rename",
        "unlink",    "rmdir",     "mkdir",     "link",      "symlink",
        "fallocate",
    };
    for (set) |f| {
        if (!std.mem.eql(u8, name, f)) continue;
        // `openat2` carries its flags inside a struct, and a BPF program cannot follow a
        // pointer — so the filter traps EVERY `openat2` and the handler re-reads the
        // struct to decide whether to record. The other two open spellings have their
        // flags in a register, and there the filter applies the same mask this side reads
        // from the text. Answering "trapped" for a read-only `openat2` is therefore the
        // truth about the filter, not a looser rule (review, P1).
        if (std.mem.eql(u8, name, "openat2")) return true;
        return !isReadOnlyOpen(name, line);
    }
    return false;
}
// The open arm above cannot fire from either of this file's two call sites: both drop a
// read-only open before they get here, for their own reason (it is not an operation on
// either side — ADR 0003). It is written anyway because this predicate answers "does the
// filter trap this", and answering yes for a call the filter admits would be a trap laid
// for the next caller. The test asserts it directly for the same reason; no capture can.

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
    op: ?usize,
    mutation: ?usize,
};

fn takePending(list: *std.ArrayList(PendingWrite), pid: ?u32) ?PendingWrite {
    for (list.items, 0..) |it, i| {
        if (it.pid == pid) return list.swapRemove(i);
    }
    return null;
}

fn setPending(arena: std.mem.Allocator, list: *std.ArrayList(PendingWrite), w: PendingWrite) !void {
    try list.append(arena, w);
}

fn retract(
    arena: std.mem.Allocator,
    q: PendingWrite,
    dead_ops: *std.ArrayList(usize),
    dead_muts: *std.ArrayList(usize),
    out: anytype,
) !void {
    if (q.op) |i| {
        try dead_ops.append(arena, i);
        // A pending entry carrying an `op` index was set on the subject path, which
        // increments this counter before it appends — so the count cannot be zero here.
        // Asserted rather than saturated: `-|` would absorb a future path that sets `.op`
        // without counting the line, and absorbing it is how the count would go quietly wrong.
        std.debug.assert(out.lines_in_scope > 0);
        out.lines_in_scope -= 1;
    }
    if (q.mutation) |i| try dead_muts.append(arena, i);
}

/// Whether interrupted calls are dropped (#217). Set by the engine under `--observe supervised`
/// only, where the counting observer is the kernel's notification: a signal that takes a call
/// back before the engine received it withdraws the notification, so the engine counted nothing
/// and the interrupted entry must not count either. Under the shim it stays off — the shim counts
/// at libc's entry whatever the kernel does next, and a call that returns EINTR without SA_RESTART
/// is one count there and one entry here (review, P1).
pub var fold_restarted: bool = false;

/// strace's spelling of a call a signal interrupted before it completed, read at the END of the
/// line, where strace puts the return: a target-chosen string inside the arguments cannot reach
/// it, because the arguments are followed by `) = <return>` (review, P1 — the first version found
/// the text anywhere in the line, so a write carrying it erased its own entry).
fn isRestartedCall(line: []const u8) bool {
    const t = std.mem.trimEnd(u8, line, " \t\r");
    const tails = [_][]const u8{
        " = ? ERESTARTSYS (To be restarted if SA_RESTART is set)",
        " = ? ERESTARTNOINTR (To be restarted)",
        " = ? ERESTARTNOHAND (To be restarted if no handler)",
        " = ? ERESTART_RESTARTBLOCK (Interrupted by signal)",
    };
    for (tails) |tail| if (std.mem.endsWith(u8, t, tail)) return true;
    return false;
}

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

/// Paths appear two ways in `strace -y` output: quoted arguments, and descriptor
/// annotations like `3</tmp/state/key.json>`. Both are checked with the same
/// component-boundary containment test the shim uses, so `/tmp/state2` is not mistaken
/// for something inside `/tmp/state`.
fn touchesStateDir(line: []const u8, state_dir: []const u8, alt: []const u8) bool {
    return namesStateDir(line, state_dir, alt, true);
}

fn quotesStateDir(line: []const u8, state_dir: []const u8, alt: []const u8) bool {
    return namesStateDir(line, state_dir, alt, false);
}

// An annotation is still skipped whole when it is not tested: a `"` strace leaves inside one would
// start a string there.
fn namesStateDir(line: []const u8, state_dir: []const u8, alt: []const u8, comptime annotations: bool) bool {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] != '"' and line[i] != '<') continue;
        const end = closingIndex(line, i) orelse break;
        if (line[i] == '"' or annotations) {
            var buf: [contract.max_path]u8 = undefined;
            if (unescape(line[i + 1 .. end], &buf)) |candidate| {
                if (candidate.len > 0 and candidate[0] == '/' and insideEither(candidate, state_dir, alt)) return true;
            }
        }
        i = end;
    }
    return false;
}

// An annotation is skipped whole, not counted as a bracket: strace leaves `[`, `{`, `,` and
// `)` in a path unescaped, and a depth count would lose the commas after them.
fn closingIndex(line: []const u8, at: usize) ?usize {
    const close: u8 = if (line[at] == '"') '"' else '>';
    var i = at + 1;
    while (i < line.len) : (i += 1) {
        if (line[i] == '\\') {
            i += 1;
            continue;
        }
        if (line[i] == close) return i;
    }
    return null;
}

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
            '"', '<' => i = closingIndex(line, i) orelse line.len,
            '[', '{' => depth += 1,
            ']', '}' => {
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
    if (arg == index) {
        if (std.mem.lastIndexOf(u8, line, "<unfinished ...>")) |uf| {
            if (uf >= start) return std.mem.trim(u8, line[start..uf], " \t");
        }
    }
    return null;
}

fn returnedPid(line: []const u8) ?u64 {
    const at = std.mem.lastIndexOf(u8, line, " = ") orelse return null;
    const tail = std.mem.trim(u8, line[at + 3 ..], " \t");
    var end: usize = 0;
    while (end < tail.len and std.ascii.isDigit(tail[end])) end += 1;
    if (end == 0) return null;
    const v = std.fmt.parseInt(u64, tail[0..end], 10) catch return null;
    return if (v == 0) null else v;
}

fn traceNumber(text: ?[]const u8) ?u64 {
    const t = std.mem.trim(u8, text orelse return null, " \t");
    if (std.mem.eql(u8, t, "NULL")) return 0;
    if (std.mem.startsWith(u8, t, "0x")) return std.fmt.parseInt(u64, t[2..], 16) catch null;
    return std.fmt.parseInt(u64, t, 10) catch null;
}

fn returnedAddress(line: []const u8) ?u64 {
    const at = std.mem.lastIndexOf(u8, line, " = ") orelse return null;
    const tail = std.mem.trim(u8, line[at + 3 ..], " \t");
    const end = std.mem.indexOfAny(u8, tail, " \t") orelse tail.len;
    if (!std.mem.startsWith(u8, tail[0..end], "0x")) return null;
    return traceNumber(tail[0..end]);
}

fn resumedCall(raw: []const u8) ?[]const u8 {
    const line = stripPidPrefix(raw);
    if (!std.mem.startsWith(u8, line, "<... ")) return null;
    const rest = line["<... ".len..];
    const end = std.mem.indexOf(u8, rest, " resumed>") orelse return null;
    return rest[0..end];
}

const SharedMap = struct { start: u64, end: u64 };

const PendingMap = struct { pid: u32, len: u64 };

fn pageUp(len: u64) u64 {
    const page: u64 = std.heap.pageSize();
    // Saturates rather than wraps: a wrapped end would be a small address, and the range
    // would stop covering what it was asked to cover.
    return (len +| (page - 1)) / page * page;
}

fn overlapsShared(maps: []const SharedMap, start: u64, len: u64) bool {
    const end = start +| pageUp(len);
    for (maps) |m| if (start < m.end and m.start < end) return true;
    return false;
}

fn takePendingMap(list: *std.ArrayList(PendingMap), pid: ?u32) ?u64 {
    const p = pid orelse 0;
    for (list.items, 0..) |e, i| if (e.pid == p) return list.swapRemove(i).len;
    return null;
}

/// The two sides are matched by name, and a name strace prints is the one the file had at
/// that call: opened as `db.tmp` and renamed to `db` before it is mapped, or linked and the
/// first name removed, it no longer matches (second review). So `narrowing` is given up the
/// moment the run renames or links anything, and every state file mapped shared is
/// remembered from then on — refusing more, never less.
fn mapsWritableStateFile(line: []const u8, state: []const u8, alt: []const u8, rw_paths: []const []const u8, narrowing: bool) bool {
    var abuf: [contract.max_path]u8 = undefined;
    const p = argAnnotation(syscallArg(line, 4) orelse return false, &abuf) orelse return false;
    if (!insideEither(p, state, alt)) return false;
    if (!narrowing) return true;
    for (rw_paths) |w| if (std.mem.eql(u8, w, p)) return true;
    return false;
}

fn renamesOrLinks(name: []const u8) bool {
    for ([_][]const u8{ "rename", "renameat", "renameat2", "link", "linkat" }) |n| {
        if (std.mem.eql(u8, name, n)) return true;
    }
    return false;
}

fn isOpenCall(name: []const u8) bool {
    return std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "openat") or
        std.mem.eql(u8, name, "openat2") or std.mem.eql(u8, name, "creat");
}

// Not the last ` = ` on the line, as the numeric results are found: this result is an
// annotation, and a path can hold ` = ` itself.
fn returnedPath(line: []const u8, out: []u8) ?[]const u8 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        switch (line[i]) {
            '"', '<' => i = closingIndex(line, i) orelse return null,
            ' ' => if (std.mem.startsWith(u8, line[i..], " = "))
                return argAnnotation(std.mem.trim(u8, line[i + 3 ..], " \t"), out),
            else => {},
        }
    }
    return null;
}

// Not searched for anywhere on the line: a quoted path can spell it, and strace leaves `<`
// and `>` unescaped there.
fn isUnfinished(line: []const u8) bool {
    return std.mem.endsWith(u8, line, "<unfinished ...>");
}

fn visiblyFailed(line: []const u8) bool {
    // An unfinished half has no result at all; a ` = -` on it is inside an argument — a file
    // name the target chose (second review).
    if (isUnfinished(line)) return false;
    const at = std.mem.lastIndexOf(u8, line, " = ") orelse return false;
    const rhs = std.mem.trim(u8, line[at + 3 ..], " \t");
    return rhs.len > 0 and rhs[0] == '-';
}

fn isResumedClone(raw: []const u8) bool {
    const line = stripPidPrefix(raw);
    if (!std.mem.startsWith(u8, line, "<... ")) return false;
    const rest = line["<... ".len..];
    const end = std.mem.indexOf(u8, rest, " resumed>") orelse return false;
    return std.mem.eql(u8, rest[0..end], "clone") or std.mem.eql(u8, rest[0..end], "clone3");
}

const at_removedir_linux: u64 = 0x200;

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

const rename_exchange: u64 = 2;
const rename_whiteout: u64 = 4;

/// other than a rename. Reads argument 4 rather than the line, so a FILENAME spelling
/// a flag cannot refuse a plain rename — and falls back to the number, because
/// `strace -X raw` and undecorated builds print `0x2` where a decoding strace prints
/// `RENAME_EXCHANGE`. Reading only the symbol would fail OPEN there: the shim does not
/// record these, so the run would end at `oracle_missed_operation` with a reason that
/// names the wrong problem. `unlinkatRemovesDir` above has carried the same pair of
fn renameat2Flag(line: []const u8, symbol: []const u8, bit: u64) bool {
    const flags = syscallArg(line, 4) orelse return false;
    if (std.mem.indexOf(u8, flags, symbol) != null) return true;
    const v = std.fmt.parseInt(u64, std.mem.trim(u8, flags, " "), 0) catch return false;
    return (v & bit) != 0;
}

const FallocateMode = enum { grows, keeps_size, other };

// Not "has FALLOC_FL_KEEP_SIZE": the kernel takes hole punching only with it, so that test would pass
// `FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE` as a read.
fn fallocateMode(line: []const u8) FallocateMode {
    const arg = std.mem.trim(u8, syscallArg(line, 1) orelse return .other, " ");
    if (std.mem.eql(u8, arg, "FALLOC_FL_KEEP_SIZE")) return .keeps_size;
    const mode = std.fmt.parseInt(u32, arg, 0) catch return .other;
    if (contract.fallocateCounts(mode)) return .grows;
    return if (mode == contract.falloc_keep_size) .keeps_size else .other;
}

fn fallocateRefusal(arena: std.mem.Allocator, line: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "fallocate({s})", .{std.mem.trim(u8, syscallArg(line, 1) orelse "?", " ")});
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

/// The needle is always searched inside one argument, never across the line: a
/// *filename* is attacker-controlled in the only sense that matters here (the target
/// chooses it), and a file called `O_CREAT.bak` or `PROT_WRITE.log` must not change how
/// the syscall around it is classified. Same rule, same reason as `unlinkatRemovesDir`.
fn argContains(line: []const u8, index: usize, needle: []const u8) bool {
    const a = syscallArg(line, index) orelse return false;
    return std.mem.indexOf(u8, a, needle) != null;
}

const clone_refusal = "ioctl(FICLONE)";
const unreadable_ioctl_refusal = "ioctl on a state file whose request could not be read";

const CloneKind = enum { whole, range, unreadable };
const PendingClone = struct { pid: u32, kind: CloneKind };

/// `FICLONERANGE` before `FICLONE`, whose name it contains.
fn cloneKind(name: []const u8, line: []const u8) ?CloneKind {
    if (!std.mem.eql(u8, name, "ioctl")) return null;
    const request = syscallArg(line, 1) orelse return .unreadable;
    for ([_][]const u8{ "FICLONERANGE", "BTRFS_IOC_CLONE_RANGE", "0x4020940d" }) |n| {
        if (std.mem.indexOf(u8, request, n) != null) return .range;
    }
    for ([_][]const u8{ "FICLONE", "BTRFS_IOC_CLONE", "0x40049409" }) |n| {
        if (std.mem.indexOf(u8, request, n) != null) return .whole;
    }
    if (!std.mem.startsWith(u8, request, "_IOC(")) return null;
    const ioc_type = syscallArg(line, 2) orelse return null;
    const ioc_nr = syscallArg(line, 3) orelse return null;
    if (!std.mem.eql(u8, ioc_type, "0x94")) return null;
    if (std.mem.eql(u8, ioc_nr, "0x9")) return .whole;
    if (std.mem.eql(u8, ioc_nr, "0xd")) return .range;
    return null;
}

fn cloneIntoState(line: []const u8, state_dir: []const u8, state_alt: []const u8) bool {
    // Not `false` when the destination cannot be read: that would let an unreadable clone through.
    return descriptorScope(line, 0, state_dir, state_alt) != .outside;
}

/// Only an errno raised before anything is remapped lets a clone through: btrfs can fail a
/// whole-file clone after remapping part of it, and a range clone can fail that way on XFS too.
fn cloneRefuses(kind: CloneKind, finished_line: []const u8) bool {
    if (kind != .whole or !visiblyFailed(finished_line)) return true;
    const at = std.mem.lastIndexOf(u8, finished_line, " = ") orelse return true;
    for ([_][]const u8{ "EOPNOTSUPP", "ENOTSUP", "EXDEV", "EINVAL", "EBADF", "EISDIR", "EPERM", "ETXTBSY", "ENOTTY" }) |e| {
        if (std.mem.indexOf(u8, finished_line[at..], e) != null) return false;
    }
    return true;
}

fn noteClone(arena: std.mem.Allocator, kind: CloneKind, line: []const u8, pid: ?u32, pending: *std.ArrayList(PendingClone), out: *Parsed) !void {
    if (isUnfinished(line)) {
        try pending.append(arena, .{ .pid = pid orelse 0, .kind = kind });
    } else if (cloneRefuses(kind, line) and out.unsupported == null) {
        out.unsupported = try arena.dupe(u8, if (kind == .unreadable) unreadable_ioctl_refusal else clone_refusal);
    }
}

fn takePendingClone(list: *std.ArrayList(PendingClone), pid: ?u32) ?CloneKind {
    const want = pid orelse 0;
    for (list.items, 0..) |c, i| {
        if (c.pid == want) {
            _ = list.swapRemove(i);
            return c.kind;
        }
    }
    return null;
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

const cgroup_move_files = [_][]const u8{ "cgroup.procs", "cgroup.threads", "cgroup.type" };

fn cgroupMove(arena: std.mem.Allocator, name: []const u8, line: []const u8) !?[]const u8 {
    const result = resultText(line);
    if (result) |r| {
        const value = std.mem.trim(u8, if (std.mem.indexOfScalar(u8, r, '=')) |eq| r[eq + 1 ..] else r, " \t");
        if (value.len > 0 and value[0] == '-') return null;
    }
    if (std.mem.eql(u8, name, "clone3")) {
        const flags = syscallArg(line, 0) orelse return null;
        if (std.mem.indexOf(u8, flags, "CLONE_INTO_CGROUP") == null) return null;
        return "a process was created straight into another cgroup (clone3 with CLONE_INTO_CGROUP), where neither the crash-point kill nor the engine's cleanup reaches it";
    }
    const by_handle = std.mem.eql(u8, name, "open_by_handle_at");
    const path_index: ?usize = if (std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "creat"))
        0
    else if (std.mem.eql(u8, name, "openat") or std.mem.eql(u8, name, "openat2"))
        1
    else if (by_handle)
        null
    else
        return null;
    if (by_handle) {
        if (syscallArg(line, 2)) |flags| {
            if (std.mem.indexOf(u8, flags, "O_") != null and std.mem.indexOf(u8, flags, "O_WRONLY") == null and
                std.mem.indexOf(u8, flags, "O_RDWR") == null and std.mem.indexOf(u8, flags, "O_ACCMODE") == null) return null;
        }
    } else if (isReadOnlyOpen(name, line)) return null;
    var pbuf: [contract.max_path]u8 = undefined;
    const named: ?[]const u8 = if (path_index) |i| (if (syscallArg(line, i)) |arg| argPath(arg, &pbuf) else null) else null;
    var abuf: [contract.max_path]u8 = undefined;
    const returned: ?[]const u8 = if (result) |r| argAnnotation(r, &abuf) else null;
    for (cgroup_move_files) |file| {
        for ([_]?[]const u8{ named, returned }) |candidate| {
            const p = candidate orelse continue;
            const is_file = std.mem.eql(u8, p, file) or
                (p.len > file.len and std.mem.endsWith(u8, p, file) and p[p.len - file.len - 1] == '/');
            if (is_file)
                return try std.fmt.allocPrint(arena, "a process opened {s} for writing ({s}): a write there moves a process between cgroups or changes what the run's cgroup.kill can do, so the kills no longer reach every process of the run", .{ file, name });
        }
    }
    return null;
}

/// Found with `syscallArg`'s walk over quotes and brackets, so a path that spells ` = -1`
/// inside the arguments is not taken for the result.
fn resultText(raw: []const u8) ?[]const u8 {
    const line = stripPidPrefix(raw);
    const open = std.mem.indexOfScalar(u8, line, '(') orelse return null;
    var i = open + 1;
    var depth: usize = 0;
    while (i < line.len) : (i += 1) {
        switch (line[i]) {
            '"', '<' => i = closingIndex(line, i) orelse line.len,
            '[', '{' => depth += 1,
            ']', '}' => {
                if (depth > 0) depth -= 1;
            },
            ')' => if (depth == 0) return line[i + 1 ..],
            else => {},
        }
    }
    return null;
}

fn argPath(arg: []const u8, out: []u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, arg, '"') orelse return null;
    const end = closingIndex(arg, q) orelse return null;
    return unescape(arg[q + 1 .. end], out);
}

// Do not hold the result past `out`: it points into `out` whenever the path holds an escape.
fn argAnnotation(arg: []const u8, out: []u8) ?[]const u8 {
    const lt = std.mem.indexOfScalar(u8, arg, '<') orelse return null;
    const gt = closingIndex(arg, lt) orelse return null;
    const raw = arg[lt + 1 .. gt];
    const p = if (std.mem.indexOfScalar(u8, raw, '\\') == null) raw else unescape(raw, out) orelse return null;
    if (p.len == 0 or p[0] != '/') return null;
    return p;
}

fn unescape(text: []const u8, out: []u8) ?[]const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (n >= out.len) return null;
        var ch = text[i];
        if (ch == '\\' and i + 1 < text.len) {
            i += 1;
            ch = switch (text[i]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                'v' => 0x0b,
                'f' => 0x0c,
                '0'...'7' => blk: {
                    var v: u16 = text[i] - '0';
                    var k: usize = 0;
                    while (k < 2 and i + 1 < text.len and text[i + 1] >= '0' and text[i + 1] <= '7') : (k += 1) {
                        i += 1;
                        v = v * 8 + (text[i] - '0');
                    }
                    break :blk @truncate(v);
                },
                else => text[i],
            };
        }
        out[n] = ch;
        n += 1;
    }
    return out[0..n];
}

const Scope = enum { inside, outside, unresolvable };

fn insideEither(path: []const u8, state: []const u8, alt: []const u8) bool {
    if (contract.isInsideDir(path, state)) return true;
    return alt.len != 0 and contract.isInsideDir(path, alt);
}

fn resolvePath(line: []const u8, arg: PathArg, cwd: ?[]const u8, out: []u8) ?[]const u8 {
    const path_arg = syscallArg(line, arg.path) orelse return null;
    var pbuf: [contract.max_path]u8 = undefined;
    const p = argPath(path_arg, &pbuf) orelse return null;
    if (p.len == 0) return null;
    if (p[0] == '/') return contract.normalizePath(out, "/", p) catch null;

    var base: ?[]const u8 = null;
    var bbuf: [contract.max_path]u8 = undefined;
    if (arg.dirfd) |di| {
        if (syscallArg(line, di)) |da| base = argAnnotation(da, &bbuf);
    }
    if (base == null) base = cwd;
    const b = base orelse return null;
    return contract.normalizePath(out, b, p) catch null;
}

fn resolveArg(line: []const u8, arg: PathArg, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    var obuf: [contract.max_path]u8 = undefined;
    const r = resolvePath(line, arg, cwd, &obuf) orelse return .unresolvable;
    return if (insideEither(r, state, alt)) .inside else .outside;
}

fn pathSyscallScope(spec: PathSpec, line: []const u8, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    return foldScope(spec, line, cwd, state, alt, resolveArg);
}

// Not resolution alone: an absolute path into the state at an argument the table does not name (a
// `mount` source) was refused before these calls were resolved, and stays refused.
fn unclassifiedPathScope(spec: PathSpec, line: []const u8, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    if (quotesStateDir(line, state, alt)) return .inside;
    const scope = foldScope(spec, line, cwd, state, alt, unclassifiedArgScope);
    if (std.mem.eql(u8, spec.name, "mount") and mountsAPath(line)) {
        switch (unclassifiedArgScope(line, .{ .dirfd = null, .path = 0 }, cwd, state, alt)) {
            .inside => return .inside,
            .unresolvable => if (scope == .outside) return .unresolvable,
            .outside => {},
        }
    }
    return scope;
}

// Only a bind or a move: any other mount names a file system as its source ("none", "tmpfs"), and
// resolving that against a cwd inside the state would refuse a mount made elsewhere.
fn mountsAPath(line: []const u8) bool {
    return argContains(line, 3, "MS_BIND") or argContains(line, 3, "MS_MOVE");
}

const ArgScope = fn ([]const u8, PathArg, ?[]const u8, []const u8, []const u8) Scope;

fn foldScope(spec: PathSpec, line: []const u8, cwd: ?[]const u8, state: []const u8, alt: []const u8, comptime argScope: ArgScope) Scope {
    var any_unresolvable = false;
    for (spec.args) |a| {
        switch (argScope(line, a, cwd, state, alt)) {
            .inside => return .inside,
            .unresolvable => any_unresolvable = true,
            .outside => {},
        }
    }
    return if (any_unresolvable) .unresolvable else .outside;
}

// An empty or NULL path names the descriptor itself; resolved as a relative name it would refuse
// the call wherever the descriptor points. Only those two: an address strace could not read is
// unresolvable, not absent.
fn unclassifiedArgScope(line: []const u8, a: PathArg, cwd: ?[]const u8, state: []const u8, alt: []const u8) Scope {
    const path_arg = syscallArg(line, a.path) orelse "";
    const names_descriptor = std.mem.eql(u8, path_arg, "\"\"") or std.mem.eql(u8, path_arg, "NULL");
    if (!names_descriptor) return resolveArg(line, a, cwd, state, alt);
    const di = a.dirfd orelse return .outside;
    return descriptorScope(line, di, state, alt);
}

fn descriptorScope(line: []const u8, index: usize, state: []const u8, alt: []const u8) Scope {
    const arg = syscallArg(line, index) orelse return .unresolvable;
    var abuf: [contract.max_path]u8 = undefined;
    const p = argAnnotation(arg, &abuf) orelse return .unresolvable;
    return if (insideEither(p, state, alt)) .inside else .outside;
}

fn syscallSucceeded(line: []const u8) bool {
    const eq = std.mem.lastIndexOfScalar(u8, line, '=') orelse return false;
    const rhs = std.mem.trim(u8, line[eq + 1 ..], " \t");
    return rhs.len > 0 and rhs[0] != '-' and rhs[0] != '?';
}

fn changesPersistentState(name: []const u8, line: []const u8) bool {
    if (isReadOnly(name)) return false;
    if (std.mem.eql(u8, name, "fallocate") and fallocateMode(line) == .keeps_size) return false;
    if (std.mem.eql(u8, name, "close")) return false;
    if ((std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "openat") or
        std.mem.eql(u8, name, "openat2")) and isReadOnlyOpen(name, line)) return false;
    return true;
}

/// Argument 0 for every syscall that reached this file before #244: `write`, `fsync`,
/// `close`, `ftruncate`, `pwritev` and the metadata pair all put their descriptor
/// first, which is why the rule used to be stated as a fact about fd syscalls in
/// general. `copy_file_range(fd_in, off_in, fd_out, …)` breaks it — argument 0 is the
/// SOURCE. Reading it as the destination gets the answer wrong in both directions: a
/// copy out of the state directory would count as a mutation (there is none), and a
/// copy into it from elsewhere would be missed entirely.
const FdWriteArg = struct { name: []const u8, arg: usize };
const fd_write_args = [_]FdWriteArg{
    .{ .name = "copy_file_range", .arg = 2 },
};

const fd_arg0 = [_][]const u8{
    "close",       "fdatasync", "fsync",      "ftruncate",
    "ftruncate64", "pwrite",    "pwrite64",   "pwritev",
    "pwritev2",    "sendfile",  "sendfile64", "write",
    "writev",      "fallocate",
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
    return descriptorScope(line, fdWriteArg(name), state, alt) == .inside;
}

pub const Event = struct { id: u64, at: usize };

pub const Parsed = struct {
    classes: std.ArrayList(contract.OpClass),
    names: std.ArrayList([]const u8),
    /// binary trace to decode by hand (#41). These borrow from the `text` given to
    /// `parse` — no copy, no new allocation-failure path — so the caller keeps that
    /// buffer alive for as long as it reads them (main does: same arena, same scope).
    lines: std.ArrayList([]const u8),
    unsupported: ?[]const u8 = null,
    boundary: ?[]const u8 = null,
    detached: ?[]const u8 = null,
    cgroup_move: ?[]const u8 = null,
    /// Under `strace` that is every process, the subject included, which is what the
    /// ordering rule needs — the writer it most often has to order a child against is the
    /// parent. The `fs_usage` reader fills in the non-subject ids only: it has no oracle
    /// role beyond detection on that platform, where a run with another process in it is
    /// refused for want of an oracle that can account for one. That refusal is
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
    /// here that is not the subject's is a child's — **under a witness that names
    /// processes.** Under one that names only threads it is a child's *or* a thread the
    /// list does not hold, and `childrenMayBeJudged` says which it can establish rather
    /// than picking (#544, ADR 0060). 64-bit because a mach thread id is not bounded by
    /// the width of a pid.
    mutations: std.ArrayList(Event),
    /// Threads of the subject (v16). **Two readers fill this, from different evidence.**
    /// The strace reader fills it from the subject's own `clone` lines carrying
    /// `CLONE_THREAD`, in both spellings strace uses (one line, or an unfinished half and
    /// a resumed half), by the id strace prints for them. The fs_usage reader cannot: its
    /// capture names no process anywhere, so it is handed the ids the shim recorded
    /// writing under the subject's pid and fills the list from those (#544, ADR 0060) —
    /// which is a narrower set, since a thread the shim never recorded writing is not on
    /// it. A line from one of these is the subject's line: its operations go to `classes`,
    /// its relative paths resolve against the subject's cwd, and its writes are not a
    /// child's touch. What this list does NOT decide is whether more than one of them
    /// wrote — that is the shim's trace to answer, record by record, since every record
    /// names its thread.
    subject_tids: std.ArrayList(u64),
    reaps: std.ArrayList(Event),
    spawns: std.ArrayList(Event),
    /// Distinct ids other than the subject's — and **the two readers count different
    /// things**, which went unwritten until #544 while an argument about what is reachable
    /// rested on it. The strace reader counts pids that appeared AT ALL. The fs_usage
    /// reader counts tids that MUTATED the judged directory, because it fills this and
    /// `mutations` at the same place (`src/fsusage.zig`, the `!is_subject` arm); its
    /// capture is system-wide, so counting every id that appeared would count the
    /// neighbours.
    ///
    /// What rests on the difference: `toleratedChildrenClause` in `src/main.zig` says "N
    /// other process(es) observed; none touched the state directory", and it can only be
    /// reached where this is non-zero while nothing was touched — the strace side alone.
    /// Widen the fs_usage side to match the strace sentence and that clause starts saying
    /// "process" about thread ids, which is the claim #544 spent its length removing.
    children: usize = 0,

    primary_pid: ?u32 = null,
    lines_seen: usize = 0,
    lines_in_scope: usize = 0,
    metadata_observed: std.ArrayList([]const u8),

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
    var pending_thread_clone: std.ArrayList(u32) = .empty;
    // still to come (#689). Not keyed by process: a forked child shares the parent's
    // mappings, and a range left after an `munmap` (not traced) can only add a refusal.
    var shared_maps: std.ArrayList(SharedMap) = .empty;
    var pending_maps: std.ArrayList(PendingMap) = .empty;
    var rw_paths: std.ArrayList([]const u8) = .empty;
    var pending_rw_open: std.ArrayList(u32) = .empty;
    var pending_clones: std.ArrayList(PendingClone) = .empty;
    var rw_narrowing = true;

    var pending: std.ArrayList(PendingWrite) = .empty;
    var dead_ops: std.ArrayList(usize) = .empty;
    var dead_muts: std.ArrayList(usize) = .empty;

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
            if (resumedCall(line)) |rc| {
                if (std.mem.eql(u8, rc, "mmap") or std.mem.eql(u8, rc, "mremap")) {
                    if (takePendingMap(&pending_maps, pid)) |len| {
                        if (returnedAddress(line)) |addr| try shared_maps.append(arena, .{ .start = addr, .end = addr +| pageUp(len) });
                    }
                } else if (std.mem.eql(u8, rc, "ioctl")) {
                    if (takePendingClone(&pending_clones, pid)) |kind| {
                        if (cloneRefuses(kind, line) and out.unsupported == null)
                            out.unsupported = try arena.dupe(u8, if (kind == .unreadable) unreadable_ioctl_refusal else clone_refusal);
                    }
                } else if (isOpenCall(rc) and takeThreadClone(&pending_rw_open, pid)) {
                    var abuf: [contract.max_path]u8 = undefined;
                    if (returnedPath(line, &abuf)) |p| {
                        if (insideEither(p, state_dir, state_alt)) try rw_paths.append(arena, try arena.dupe(u8, p));
                    }
                }
            }
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
                if (takePending(&pending, pid)) |q| try retract(arena, q, &dead_ops, &dead_muts, &out);
                continue;
            }
            // A call a signal interrupted before it ran (#217): strace prints its entry and
            // then `= ? ERESTARTSYS` (or another `ERESTART*`), and the call is restarted by the
            // kernel under SA_RESTART or answers EINTR without one — either way this entry
            // did not change the state, and the restarted call, if any, is its own line.
            if (fold_restarted and isRestartedCall(line)) {
                if (takePending(&pending, pid)) |q| {
                    if (resumedCall(line) != null) try retract(arena, q, &dead_ops, &dead_muts, &out);
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

        if (!launched) {
            if (std.mem.eql(u8, name, "execve") or std.mem.eql(u8, name, "execveat")) {
                launched = true;
                out.primary_pid = pid;
            }
            continue;
        }

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

        // A move between cgroups (v17, #559), from any process, and here rather than below
        // because the process-syscall branch `continue`s a clone3 away.
        if (out.cgroup_move == null) out.cgroup_move = try cgroupMove(arena, name, line);

        // Not decided by the result: a trapped call's first line ends in ENOSYS or whatever
        // the register held, and a split call carries its result on the resumed half. Not
        // after the narrowing below: an empty rename's trapped first line would end it.
        if (pathSpec(name)) |spec| {
            if (emptyPathNamesNothing(spec, line)) continue;
        }

        // Here, ahead of the scope rules, because `mprotect` and `mremap` name no path and
        // would be dropped as outside the state.
        if (renamesOrLinks(name) and !visiblyFailed(line)) rw_narrowing = false;
        if (isOpenCall(name) and !isReadOnlyOpen(name, line)) {
            var rbuf: [contract.max_path]u8 = undefined;
            if (isUnfinished(line)) {
                try pending_rw_open.append(arena, pid orelse 0);
            } else if (returnedPath(line, &rbuf)) |p| {
                if (insideEither(p, state_dir, state_alt)) try rw_paths.append(arena, try arena.dupe(u8, p));
            }
        }
        if (std.mem.eql(u8, name, "mmap") and argContains(line, 3, "MAP_SHARED") and
            !argContains(line, 2, "PROT_WRITE") and mapsWritableStateFile(line, state_dir, state_alt, rw_paths.items, rw_narrowing))
        {
            if (traceNumber(syscallArg(line, 1))) |len| {
                if (isUnfinished(line)) {
                    try pending_maps.append(arena, .{ .pid = pid orelse 0, .len = len });
                } else if (returnedAddress(line)) |addr| {
                    try shared_maps.append(arena, .{ .start = addr, .end = addr +| pageUp(len) });
                }
            }
        }
        if (std.mem.eql(u8, name, "mremap")) {
            if (traceNumber(syscallArg(line, 0))) |old| if (traceNumber(syscallArg(line, 1))) |old_len| if (traceNumber(syscallArg(line, 2))) |new_len| {
                if (overlapsShared(shared_maps.items, old, @max(old_len, 1))) {
                    if (isUnfinished(line)) {
                        try pending_maps.append(arena, .{ .pid = pid orelse 0, .len = new_len });
                    } else if (returnedAddress(line)) |addr| {
                        try shared_maps.append(arena, .{ .start = addr, .end = addr +| pageUp(new_len) });
                    }
                }
            };
            continue;
        }
        if (std.mem.eql(u8, name, "mprotect") or std.mem.eql(u8, name, "pkey_mprotect")) {
            if (argContains(line, 2, "PROT_WRITE") and !visiblyFailed(line)) {
                if (traceNumber(syscallArg(line, 0))) |addr| if (traceNumber(syscallArg(line, 1))) |len| {
                    if (overlapsShared(shared_maps.items, addr, len) and out.unsupported == null)
                        out.unsupported = try arena.dupe(u8, contract.shared_map_refusal.made_writable);
                };
            }
            continue;
        }

        if (isProcessSyscall(name)) {
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
                    } else if (isUnfinished(line)) {
                        try pending_thread_clone.append(arena, pid orelse 0);
                    }
                }
            } else if (is_shared_fs or std.mem.eql(u8, name, "unshare")) {
                if (out.boundary == null) out.boundary = try arena.dupe(u8, name);
            }
            continue;
        }

        // The subject's own calls are left to the shim, whose wrapper knows whether the
        // call actually moved anything — the direct child re-electing itself leader is
        // a no-op that must not be refused.
        if (!is_primary and (std.mem.eql(u8, name, "setsid") or std.mem.eql(u8, name, "setpgid"))) {
            if (out.detached == null) out.detached = try arena.dupe(u8, name);
            continue;
        }

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
                    var abuf: [contract.max_path]u8 = undefined;
                    const dir = argAnnotation(a, &abuf) orelse "";
                    if (dir.len > 0 and dir.len <= cwd_buf.len) {
                        @memcpy(cwd_buf[0..dir.len], dir);
                        cwd = cwd_buf[0..dir.len];
                    } else cwd = null;
                }
            }
            continue;
        }

        const own_cwd = if (is_primary) cwd else null;

        // Ownership/permission metadata (#121, option b), decided BEFORE the generic
        // scope block because it must bypass both refusal routes below: the subject's
        // branch would call it `unsupported`, and the child branch would call it a
        // touch — while the verdict judges names, bytes and link targets, none of
        // which these change, from anyone. Scope uses the same typed rules; an
        // unresolvable metadata write is counted too — over-reporting an exclusion
        // is the honest direction (the report says "excluded", never "did not
        // happen").
        if (metadataPathSpec(name)) |mspec| {
            if (pathSyscallScope(mspec, line, own_cwd, state_dir, state_alt) != .outside)
                try out.metadata_observed.append(arena, try arena.dupe(u8, name));
            continue;
        }
        if (isMetadataFd(name)) {
            if (fdSyscallInScope(line, name, state_dir, state_alt))
                try out.metadata_observed.append(arena, try arena.dupe(u8, name));
            continue;
        }
        if (isXattrWrite(name)) {
            const in = if (pathSpec(name)) |spec|
                pathSyscallScope(spec, line, own_cwd, state_dir, state_alt) != .outside
            else
                fdSyscallInScope(line, name, state_dir, state_alt);
            if (in) try out.metadata_observed.append(arena, try arena.dupe(u8, name));
            continue;
        }

        // **The tracked cwd is the SUBJECT's, so no other process's relative path may be
        // resolved against it** (v15). `resolvePath` falls back to it whenever a line
        // carries no dirfd annotation, which is every legacy-form path syscall — and on
        // x86-64 glibc issues the legacy forms for `rename`, `unlink` and `mkdir`, as the
        // comment on `cwd` above says. A child that moved its own working directory and
        // wrote through a relative path would then be placed at a path it never touched:
        // outside the judged state, silently, and a run with an unaccounted writer in it
        // would be judged.
        const scope: Scope = if (pathSpec(name)) |spec|
            pathSyscallScope(spec, line, own_cwd, state_dir, state_alt)
        else if (unclassifiedPathSpec(name)) |spec|
            unclassifiedPathScope(spec, line, own_cwd, state_dir, state_alt)
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
            argContains(line, 3, "MAP_SHARED") and !visiblyFailed(line);

        if (!is_primary) {
            // A child's writable shared mapping is refused as the subject's is (#689 review):
            // as a touch alone, a child whose other writes the shim recorded is admitted by
            // the v15 rule, and the stores through the mapping ride a PASS.
            if (is_shared_write_map and out.unsupported == null)
                out.unsupported = try arena.dupe(u8, contract.shared_map_refusal.writable);
            if (std.mem.eql(u8, name, "fallocate") and fallocateMode(line) == .other and out.unsupported == null)
                out.unsupported = try fallocateRefusal(arena, line);
            if (cloneKind(name, line)) |kind| {
                if (cloneIntoState(line, state_dir, state_alt)) try noteClone(arena, kind, line, pid, &pending_clones, &out);
            }
            if (is_shared_write_map or changesPersistentState(name, line)) {
                try noteEvent(arena, &out.mutations, pid.?, out.lines_seen);
                if (isTrapped(name, line))
                    try setPending(arena, &pending, .{ .pid = pid, .op = null, .mutation = out.mutations.items.len - 1 });
            }
            continue;
        }

        if (scope == .unresolvable) {
            if (changesPersistentState(name, line) and out.unsupported == null)
                out.unsupported = try arena.dupe(u8, name);
            continue;
        }
        out.lines_in_scope += 1;

        if (is_shared_write_map) {
            if (out.unsupported == null)
                out.unsupported = try arena.dupe(u8, contract.shared_map_refusal.writable);
            continue;
        }
        // Not after `isReadOnly`: `ioctl` is on that list.
        if (cloneKind(name, line)) |kind| {
            if (cloneIntoState(line, state_dir, state_alt)) try noteClone(arena, kind, line, pid, &pending_clones, &out);
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
        if (std.mem.eql(u8, name, "fallocate")) switch (fallocateMode(line)) {
            .grows => {},
            .keeps_size => continue,
            .other => {
                if (out.unsupported == null) out.unsupported = try fallocateRefusal(arena, line);
                continue;
            },
        };
        if (classify(name)) |cls| {
            if (cls == .close) continue;
            if (cls == .open and isReadOnlyOpen(name, line)) continue;
            const actual: contract.OpClass = if (cls == .unlink and
                std.mem.eql(u8, name, "unlinkat") and unlinkatRemovesDir(line)) .rmdir else cls;
            try out.classes.append(arena, actual);
            // Index-aligned with `classes`, appended in the same breath so the three
            // lists cannot drift apart (#337).
            try out.names.append(arena, name);
            try out.lines.append(arena, line);
            if (pid) |me| try noteEvent(arena, &out.mutations, me, out.lines_seen);
            if (isTrapped(name, line) or fold_restarted) try setPending(arena, &pending, .{
                .pid = pid,
                .op = out.classes.items.len - 1,
                .mutation = if (pid == null) null else out.mutations.items.len - 1,
            });
        } else if (out.unsupported == null) {
            out.unsupported = try arena.dupe(u8, name);
        }
    }
    if (pending_clones.items.len > 0 and out.unsupported == null)
        out.unsupported = try arena.dupe(u8, if (pending_clones.items[0].kind == .unreadable) unreadable_ioctl_refusal else clone_refusal);
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

test "a state path holding bytes strace escapes is counted as an ASCII one is" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Case = struct { what: []const u8, state: []const u8, lines: []const u8 };
    const cases = [_]Case{
        .{ .what = "non-ASCII (measured, strace 6.1)", .state = "/tmp/\xe3\x83\x87/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/\343\203\207/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/\343\203\207/s/k>
        \\42    write(3</tmp/\343\203\207/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a quote and angle brackets (measured)", .state = "/tmp/a\"b<c>/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/a\"b<c>/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/a\"b\74c\76/s/k>
        \\42    write(3</tmp/a\"b\74c\76/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "an open bracket, which strace does not escape (measured)", .state = "/tmp/a[b/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/a[b/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/a[b/s/k>
        \\42    write(3</tmp/a[b/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a brace (measured)", .state = "/tmp/a{b/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/a{b/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/a{b/s/k>
        \\42    write(3</tmp/a{b/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a backslash (measured)", .state = "/tmp/a\\b/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/a\\b/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/a\\b/s/k>
        \\42    write(3</tmp/a\\b/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a vertical tab, one of strace's one-letter escapes (measured)", .state = "/tmp/a\x0bb/s", .lines =
        \\42    openat(AT_FDCWD</work>, "/tmp/a\vb/s/k", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 3</tmp/a\vb/s/k>
        \\42    write(3</tmp/a\vb/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a directory descriptor whose annotation is escaped", .state = "/tmp/\xe3\x83\x87/s", .lines =
        \\42    openat(5</tmp/\343\203\207/s>, "k", O_WRONLY|O_TRUNC) = 3</tmp/\343\203\207/s/k>
        \\42    write(3</tmp/\343\203\207/s/k>, "v\n", 2) = 2
        \\
        },
        .{ .what = "a directory descriptor whose path ends in a backslash", .state = "/tmp/x\\", .lines =
        \\42    openat(5</tmp/x\\>, "k", O_WRONLY|O_TRUNC) = 3</tmp/x\\/k>
        \\42    write(3</tmp/x\\/k>, "v\n", 2) = 2
        \\
        },
    };
    for (cases) |c| {
        const text = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n{s}", .{c.lines});
        const p = try parse(a, text, c.state, "", "/work");
        const want = [_]contract.OpClass{ .open, .write };
        std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items) catch |e| {
            std.debug.print("case: {s}\n", .{c.what});
            return e;
        };
        try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    }
    const child = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  write(3</tmp/\\343\\203\\207/s/k>, \"v\\n\", 2) = 2\n";
    const q = try parse(a, child, "/tmp/\xe3\x83\x87/s", "", "/work");
    try std.testing.expect(q.childTouched());
}

test "a state file opened for writing under a name holding ' = ' is remembered, so a shared map of it made writable refuses" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD</work>, "/tmp/s/x = y", O_RDWR) = 3</tmp/s/x = y>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/x = y>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
    ;
    const p = try parse(a, text, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mprotect(PROT_WRITE) on a shared mapping of a state file", p.unsupported orelse "(none)");
}

test "a quoted path spelling '<unfinished ...>' does not make a finished open look split" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD</work>, "/tmp/s/x<unfinished ...>", O_RDWR) = 3</tmp/s/x\74unfinished ...\76>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/x\74unfinished ...\76>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
    ;
    const p = try parse(a, text, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mprotect(PROT_WRITE) on a shared mapping of a state file", p.unsupported orelse "(none)");
}

test "a restarted write whose data spells ' resumed>' does not retract the operation before it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\45    execve("/tmp/toy-sig", ["toy-sig", "rotate"], 0x7ff) = 0
        \\45    write(3</tmp/sg/f>, "x\n", 2) = 2
        \\45    write(3</tmp/sg/f>, " resumed>", 9) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)
        \\45    write(3</tmp/sg/f>, " resumed>", 9) = 9
        \\
    ;
    fold_restarted = true;
    defer fold_restarted = false;
    const p = try parse(arena_state.allocator(), text, "/tmp/sg", "", "/work");
    try std.testing.expectEqualSlices(contract.OpClass, &.{ .write, .write }, p.classes.items);
}

test "an fchdir into a directory whose escaped annotation is long moves the cwd, and one past the buffer leaves it unknown" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    for ([_]struct { bytes: usize, fits: bool }{ .{ .bytes = 1500, .fits = true }, .{ .bytes = 4200, .fits = false } }) |c| {
        var escaped: std.ArrayList(u8) = .empty;
        var decoded: std.ArrayList(u8) = .empty;
        try escaped.appendSlice(a, "/tmp/");
        try decoded.appendSlice(a, "/tmp/");
        for (0..c.bytes) |_| {
            try escaped.appendSlice(a, "\\343");
            try decoded.append(a, 0xe3);
        }
        const text = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    fchdir(5<{s}>) = 0\n42    open(\"k\", O_WRONLY|O_CREAT, 0644) = 3\n", .{escaped.items});
        const p = try parse(a, text, decoded.items, "", "/work");
        if (c.fits) {
            try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
            try std.testing.expectEqualSlices(contract.OpClass, &.{.open}, p.classes.items);
        } else {
            try std.testing.expectEqualStrings("open", p.unsupported orelse "(none)");
        }
    }
}

test "containment uses component boundaries, not string prefixes" {
    try std.testing.expect(touchesStateDir("write(3</tmp/state/key.json>, ...) = 6", "/tmp/state", ""));
    try std.testing.expect(touchesStateDir("openat(AT_FDCWD</work>, \"/tmp/state/k\", 0) = 3", "/tmp/state", ""));
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
    try std.testing.expect(isSeccompRefusal("--- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=64, si_arch=AUDIT_ARCH_X86_64} ---"));
    try std.testing.expect(!isSeccompRefusal("14    --- SIGSYS {si_signo=SIGSYS, si_code=SI_USER, si_pid=1, si_uid=0} ---"));
    try std.testing.expect(!isSeccompRefusal("14    --- SIGKILL ---"));
    try std.testing.expect(!isSeccompRefusal("+++ killed by SIGKILL +++"));
    try std.testing.expect(!isSeccompRefusal("write(3</tmp/o/state/k>, \"x\", 1) = 1"));
}

test "a line that ends at its closing parenthesis, with no result, is read without stopping the parse" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expect((try cgroupMove(a, "close", "10    close(3)")) == null);
    try std.testing.expect((try cgroupMove(a, "openat", "10    openat(AT_FDCWD, \"/sys/fs/cgroup/x/cgroup.procs\", O_WRONLY)")) != null);
    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    close(3)
        \\10    write(3</tmp/o/state/a>, "x", 1) = 1
        \\
    ;
    const p = try parse(a, text, "/tmp/o/state", "", "/work");
    try std.testing.expect(p.classes.items.len > 0);
}

test "a refused write and its re-issue are one operation (--observe syscalls)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

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
    try std.testing.expectEqual(@as(usize, 1), p.names.items.len);
    try std.testing.expectEqual(@as(usize, 1), p.lines.items.len);
    try std.testing.expect(std.mem.endsWith(u8, p.lines.items[0], "= 6"));
    try std.testing.expectEqual(@as(usize, 1), p.lines_in_scope);
    try std.testing.expectEqual(@as(usize, 1), p.mutations.items.len);
}

test "every member of the trapped family is retracted, not just write" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    try std.testing.expect(isTrapped("write", ""));
    try std.testing.expect(isTrapped("pwrite64", ""));
    try std.testing.expect(isTrapped("writev", ""));
    try std.testing.expect(isTrapped("pwritev", ""));
    try std.testing.expect(!isTrapped("pwritev2", ""));
    try std.testing.expect(!isTrapped("copy_file_range", ""));
    try std.testing.expect(!isTrapped("close", ""));

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
    const want = [_]contract.OpClass{ .write, .write, .write };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 3), p.lines_in_scope);
    try std.testing.expectEqual(@as(usize, 3), p.mutations.items.len);
    for (p.lines.items) |l| try std.testing.expect(std.mem.endsWith(u8, l, "= 1"));
}

test "a refused open, rename or unlink is retracted the way a refused write is (#542)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const text =
        \\10    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\10    openat(AT_FDCWD, "/tmp/o/state/a.tmp", O_WRONLY|O_CREAT|O_EXCL, 0600) = -1 ENOSYS (Function not implemented)
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_openat, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    openat(AT_FDCWD, "/tmp/o/state/a.tmp", O_WRONLY|O_CREAT|O_EXCL, 0600) = 3</tmp/o/state/a.tmp>
        \\10    renameat(AT_FDCWD, "/tmp/o/state/a.tmp", AT_FDCWD, "/tmp/o/state/a") = -1 ENOSYS (Function not implemented)
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_renameat, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    renameat(AT_FDCWD, "/tmp/o/state/a.tmp", AT_FDCWD, "/tmp/o/state/a") = 0
        \\10    unlinkat(AT_FDCWD, "/tmp/o/state/old", 0) = -1 ENOSYS (Function not implemented)
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_unlinkat, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    unlinkat(AT_FDCWD, "/tmp/o/state/old", 0) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/work");
    const want = [_]contract.OpClass{ .open, .rename, .unlink };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 3), p.mutations.items.len);
    for (p.lines.items) |l| try std.testing.expect(std.mem.indexOf(u8, l, "ENOSYS") == null);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
}

test "a read-only open is not in the trap set, whatever spelling it arrives in (#542)" {
    const ro_at = "10    openat(AT_FDCWD, \"/tmp/o/state/a\", O_RDONLY|O_CLOEXEC) = 3";
    const rw_at = "10    openat(AT_FDCWD, \"/tmp/o/state/a\", O_RDWR) = 3";
    try std.testing.expect(!isTrapped("openat", ro_at));
    try std.testing.expect(isTrapped("openat", rw_at));

    try std.testing.expect(!isTrapped("open", "10    open(\"/tmp/o/state/a\", O_RDONLY) = 3"));
    try std.testing.expect(isTrapped("open", "10    open(\"/tmp/o/state/a\", O_WRONLY|O_CREAT, 0644) = 3"));
    try std.testing.expect(isTrapped(
        "openat2",
        "10    openat2(AT_FDCWD, \"/tmp/o/state/a\", {flags=O_RDONLY|O_CLOEXEC, mode=0, resolve=0}, 24) = 3",
    ));
    try std.testing.expect(isTrapped(
        "openat2",
        "10    openat2(AT_FDCWD, \"/tmp/o/state/a\", {flags=O_RDWR|O_CREAT, mode=0600, resolve=0}, 24) = 3",
    ));

    try std.testing.expect(isTrapped("creat", "10    creat(\"/tmp/o/state/a\", 0644) = 3"));
}

test "a refused write is retracted whatever the register held (x86-64)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

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
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 2), p.mutations.items.len);
    try std.testing.expect(holdsId(p.mutations.items, 10));
    try std.testing.expect(holdsId(p.mutations.items, 11));
    try std.testing.expect(p.childTouched());
}

test "the subject's own refused write survives the unfinished shape too" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

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

    // The control for the line that closes the window. Delete the `takePending` after the
    // name test and stdout's signal retracts the write to the judged state, leaving the
    // sequence empty. An earlier draft of this test put a `renameat` where the first write
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
    const expected = [_]contract.OpClass{ .open, .write, .fsync, .unlink, .rename };
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);
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
    try std.testing.expectEqual(@as(usize, 6), p.lines_in_scope);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expect(!p.childTouched());
    try std.testing.expectEqual(@as(usize, 0), p.children);
}

test "relative paths resolve by annotation and by tracked cwd (ADR 0006)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

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
    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  symlinkat("/tmp/s/secret", AT_FDCWD</work>, "/other/link") = 0
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), o.unsupported);
    try std.testing.expectEqual(@as(usize, 0), o.lines_in_scope);

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

    const child =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\12  fchmodat(AT_FDCWD</work>, "/tmp/s/db", 0600, 0) = 0
        \\
    ;
    const c = try parse(arena_state.allocator(), child, "/tmp/s", "", "/work");
    try std.testing.expect(!c.childTouched());
    try std.testing.expectEqual(@as(usize, 1), c.metadata_observed.items.len);

    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  chmod("/etc/passwd", 0644) = -1 EPERM (Operation not permitted)
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), o.metadata_observed.items.len);

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

    const outside =
        \\9  execve("/work/t", ["t"], 0x0) = 0
        \\9  utimensat(AT_FDCWD</work>, "/etc/passwd", [{tv_sec=1, tv_nsec=0}, {tv_sec=1, tv_nsec=0}], 0) = 0
        \\
    ;
    const o = try parse(arena_state.allocator(), outside, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), o.metadata_observed.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), o.unsupported);

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
    const in_in =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  linkat(AT_FDCWD</repo>, "state/tmp_obj", AT_FDCWD</repo>, "state/ab/final", 0) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), in_in, "/repo/state", "", "/repo");
    const want = [_]contract.OpClass{.link};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);

    const out_in =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  link("/tmp/scratch/obj", "/repo/state/name") = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), out_in, "/repo/state", "", "/repo");
    try std.testing.expectEqualSlices(contract.OpClass, &want, q.classes.items);

    const empty =
        \\9  execve("/work/git", ["git"], 0x0) = 0
        \\9  linkat(3</tmp/x>, "", AT_FDCWD</repo>, "state/name", AT_EMPTY_PATH) = 0
        \\
    ;
    const r = try parse(arena_state.allocator(), empty, "/repo/state", "", "/repo");
    try std.testing.expectEqualStrings("linkat(AT_EMPTY_PATH)", r.unsupported.?);
}

test "a path call given the empty path changes nothing, in every shape the trace prints it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const Case = struct { what: []const u8, lines: []const u8 };
    const cases = [_]Case{
        .{ .what = "one line", .lines =
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "trapped under --observe syscalls", .lines =
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0) = -1 ENOSYS (Function not implemented)
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_unlinkat, si_arch=AUDIT_ARCH_AARCH64} ---
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "trapped, the first line holding what the register held", .lines =
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0) = 0
        \\10    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_unlinkat, si_arch=AUDIT_ARCH_X86_64} ---
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "split by another thread's line", .lines =
        \\10    unlinkat(AT_FDCWD</tmp/o/state>, "", 0 <unfinished ...>
        \\12    read(7</tmp/o/state/db.wal>, "", 4096) = 0
        \\10    <... unlinkat resumed>) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "unlink", .lines =
        \\10    unlink("") = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "a rename whose source is empty", .lines =
        \\10    renameat(AT_FDCWD</tmp/o/state>, "", AT_FDCWD</tmp/o/state>, "key.json") = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "a link whose new name is empty", .lines =
        \\10    linkat(AT_FDCWD</tmp/o/state>, "key.json", AT_FDCWD</tmp/o/state>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "a link whose first name is empty, without AT_EMPTY_PATH (link(3) on aarch64)", .lines =
        \\10    linkat(AT_FDCWD</tmp/o/state>, "", AT_FDCWD</tmp/o/state>, "key.json", 0) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "an attribute write through an empty path, flags 0", .lines =
        \\10    setxattrat(5</tmp/o/state>, "", 0, "user.k", {value="1", size=1, flags=0}, 16) = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "an attribute removal through an empty path, symbolic flags without AT_EMPTY_PATH", .lines =
        \\10    removexattrat(5</tmp/o/state>, "", AT_SYMLINK_NOFOLLOW, "user.k") = -1 ENOENT (No such file or directory)
        \\
        },
        .{ .what = "the legacy attribute write", .lines =
        \\10    setxattr("", "user.k", "1", 1, 0) = -1 ENOENT (No such file or directory)
        \\
        },
    };
    for (cases) |c| {
        const text = try std.mem.concat(arena_state.allocator(), u8, &.{
            "10    execve(\"/work/toy\", [\"toy\", \"rotate\"], 0x7ff) = 0\n", c.lines,
        });
        const p = try parse(arena_state.allocator(), text, "/tmp/o/state", "", "/tmp/o/state");
        std.testing.expectEqual(@as(?[]const u8, null), p.unsupported) catch |e| {
            std.debug.print("refused: {s}\n", .{c.what});
            return e;
        };
        std.testing.expectEqual(@as(usize, 0), p.classes.items.len) catch |e| {
            std.debug.print("counted: {s}\n", .{c.what});
            return e;
        };
    }
}

test "a child's call given the empty path does not touch the judged directory" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const shapes = [_][]const u8{
        \\4242  unlinkat(AT_FDCWD</tmp/s>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        ,
        \\4242  unlinkat(AT_FDCWD</tmp/s>, "", 0) = -1 ENOSYS (Function not implemented)
        \\4242  --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_unlinkat, si_arch=AUDIT_ARCH_AARCH64} ---
        \\4242  unlinkat(AT_FDCWD</tmp/s>, "", 0) = -1 ENOENT (No such file or directory)
        \\
        ,
    };
    for (shapes) |lines| {
        const text = try std.mem.concat(arena_state.allocator(), u8, &.{
            "42    execve(\"/work/toy\", [\"toy\", \"rotate\"], 0x7ff) = 0\n",
            "42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n",
            lines,
        });
        const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
        try std.testing.expectEqual(@as(usize, 0), p.mutations.items.len);
        try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    }
}

test "an empty path that names a file through its descriptor is still not passed over" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const head = "9  execve(\"/work/git\", [\"git\"], 0x0) = 0\n";
    const a = arena_state.allocator();

    const linkats = [_][]const u8{
        "9  linkat(3</tmp/x>, \"\", AT_FDCWD</repo>, \"state/ENOENT\", AT_EMPTY_PATH) = 0\n",
        "9  linkat(3</tmp/x>, \"\", AT_FDCWD</repo>, \"state/name\", 0x1000) = 0\n",
        "9  linkat(3</tmp/x>, \"\", AT_FDCWD</repo>, \"state/name\", AT_SYMLINK_FOLLOW|0x1000) = 0\n",
    };
    for (linkats) |l| {
        const p = try parse(a, try std.mem.concat(a, u8, &.{ head, l }), "/repo/state", "", "/repo");
        try std.testing.expect(p.unsupported != null or p.classes.items.len == 1);
    }

    const xattrs = [_][]const u8{
        "9  setxattrat(5</repo/state>, \"\", AT_EMPTY_PATH, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n",
        "9  removexattrat(5</repo/state>, \"\", AT_EMPTY_PATH, \"user.k\") = 0\n",
        "9  setxattrat(5</repo/state>, \"\", 0x1000, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n",
        "9  setxattrat(5</repo/state>, \"\", AT_SYMLINK_NOFOLLOW|0x1000, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n",
        "9  removexattrat(5</repo/state>, \"\" <unfinished ...>\n",
    };
    for (xattrs) |l| {
        const p = try parse(a, try std.mem.concat(a, u8, &.{ head, l }), "/repo/state", "", "/repo");
        std.testing.expect(p.unsupported == null and p.metadata_observed.items.len == 1) catch |e| {
            std.debug.print("passed over: {s}", .{l});
            return e;
        };
    }
}

test "sync_file_range and syncfs on a state file change nothing, from the subject or a child" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\42    execve("/work/dpkg", ["dpkg"], 0x7ff) = 0
        \\42    sync_file_range(3</tmp/s/status-new>, 0, 0, SYNC_FILE_RANGE_WRITE) = 0
        \\42    syncfs(3</tmp/s/status-new>) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  sync_file_range(5</tmp/s/info/x.list>, 0, 0, SYNC_FILE_RANGE_WAIT_BEFORE|SYNC_FILE_RANGE_WRITE|SYNC_FILE_RANGE_WAIT_AFTER) = 0
        \\4242  syncfs(5</tmp/s/info/x.list>) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.mutations.items.len);

    const control =
        \\42    execve("/work/dpkg", ["dpkg"], 0x7ff) = 0
        \\42    fallocate(3</tmp/s/status-new>, FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE, 0, 4096) = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), control, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("fallocate(FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE)", q.unsupported.?);
}

test "fallocate in mode 0 on a state file is a truncate, FALLOC_FL_KEEP_SIZE alone is a read, and any other mode is refused by name" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const grows = try parse(a,
        \\42    execve("/work/flatpak", ["flatpak"], 0x7ff) = 0
        \\42    fallocate(6</tmp/s/repo/tmp.cGA6LE>, 0, 0, 42) = 0
        \\42    fallocate(6</tmp/s/repo/tmp.cGA6LE>, 0x0, 0, 42) = 0
        \\
    , "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), grows.unsupported);
    try std.testing.expectEqual(@as(usize, 2), grows.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.truncate, grows.classes.items[0]);
    const keeps = try parse(a,
        \\42    execve("/work/x", ["x"], 0x7ff) = 0
        \\42    fallocate(6</tmp/s/a>, FALLOC_FL_KEEP_SIZE, 0, 42) = 0
        \\42    fallocate(6</tmp/s/a>, 0x1, 0, 42) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  fallocate(5</tmp/s/b>, FALLOC_FL_KEEP_SIZE, 0, 42) = 0
        \\
    , "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), keeps.unsupported);
    const child_punch = try parse(a,
        \\42    execve("/work/x", ["x"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  fallocate(5</tmp/s/b>, FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE, 0, 42) = 0
        \\
    , "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("fallocate(FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE)", child_punch.unsupported orelse "(none)");
    try std.testing.expectEqual(@as(usize, 0), keeps.classes.items.len);
    try std.testing.expectEqual(@as(usize, 0), keeps.mutations.items.len);
    for ([_][]const u8{ "FALLOC_FL_KEEP_SIZE|FALLOC_FL_PUNCH_HOLE", "0x3", "FALLOC_FL_ZERO_RANGE", "FALLOC_FL_COLLAPSE_RANGE" }) |mode| {
        const line = try std.fmt.allocPrint(a, "42    execve(\"/work/x\", [\"x\"], 0x7ff) = 0\n42    fallocate(6</tmp/s/a>, {s}, 0, 42) = 0\n", .{mode});
        const other = try parse(a, line, "/tmp/s", "", "/work");
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "fallocate({s})", .{mode}), other.unsupported orelse "(none)");
    }
}

test "readahead, posix_fadvise and madvise on a state file change nothing, from the subject or a child" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\42    execve("/work/ldb", ["ldb"], 0x7ff) = 0
        \\42    readahead(3</tmp/s/000008.sst>, 0, 4096) = 0
        \\42    fadvise64(3</tmp/s/000008.sst>, 0, 0, POSIX_FADV_WILLNEED) = 0
        \\42    mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, 3</tmp/s/000008.sst>, 0) = 0xffff9a000000
        \\42    madvise(0xffff9a000000, 4096, MADV_WILLNEED) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  readahead(5</tmp/s/MANIFEST-000005>, 0, 65536) = 0
        \\4242  fadvise64(5</tmp/s/MANIFEST-000005>, 0, 0, POSIX_FADV_SEQUENTIAL) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
    try std.testing.expectEqual(@as(usize, 0), p.mutations.items.len);
}

fn parseCloneRun(a: std.mem.Allocator, pid: []const u8, lines: []const u8) !Parsed {
    const head = if (std.mem.eql(u8, pid, "9"))
        "9  execve(\"/bin/cp\", [\"cp\"], 0x0) = 0\n"
    else
        "9  execve(\"/bin/sh\", [\"sh\"], 0x0) = 0\n9  clone(child_stack=NULL, flags=SIGCHLD) = 10\n";
    const text = try std.fmt.allocPrint(a, "{s}{s}  openat(AT_FDCWD</w>, \"/s/key.txt\", O_WRONLY|O_TRUNC) = 4</s/key.txt>\n{s}", .{ head, pid, lines });
    return parse(a, text, "/s", "", "/w");
}

test "a reflink clone into the judged state refuses, from the subject or a child, in the spellings strace prints (#814)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const spellings = [_][]const u8{
        "ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3) = 0",
        "ioctl(4</s/key.txt>, BTRFS_IOC_CLONE_RANGE or FICLONERANGE, {src_fd=3</o/src>, src_offset=4096, src_length=4096, dest_offset=4096}) = 0",
        "ioctl(4</s/key.txt>, _IOC(_IOC_WRITE, 0x94, 0x9, 0x4), 3) = 0",
        "ioctl(4</s/key.txt>, _IOC(_IOC_WRITE, 0x94, 0xd, 0x20), 0xffffd0a8b9c8) = 0",
        "ioctl(4</s/key.txt>, 0x40049409, 3) = 0",
        "ioctl(4</s/key.txt>, 0x4020940d, 0xffffd0a8b9c8) = 0",
        // A range clone that failed may have remapped part of the range first.
        "ioctl(4</s/key.txt>, BTRFS_IOC_CLONE_RANGE or FICLONERANGE, {src_fd=3</o/src>, src_offset=0, src_length=8192, dest_offset=0}) = -1 EINVAL (Invalid argument)",
    };
    for (spellings) |line| {
        for ([_][]const u8{ "9", "10" }) |pid| {
            const p = try parseCloneRun(a, pid, try std.fmt.allocPrint(a, "{s}  {s}\n", .{ pid, line }));
            try std.testing.expectEqualStrings("ioctl(FICLONE)", p.unsupported orelse "(none)");
        }
    }
}

test "a clone split across two lines is judged by the half that carries its result" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const unfinished = "9  ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3 <unfinished ...>\n10 epoll_pwait(5<anon_inode:[eventpoll]>, [], 1024, 0, NULL, 8) = 0\n";
    const failed = try parseCloneRun(a, "9", try std.fmt.allocPrint(a, "{s}9  <... ioctl resumed>) = -1 EOPNOTSUPP (Operation not supported)\n", .{unfinished}));
    try std.testing.expectEqual(@as(?[]const u8, null), failed.unsupported);
    const done = try parseCloneRun(a, "9", try std.fmt.allocPrint(a, "{s}9  <... ioctl resumed>) = 0\n", .{unfinished}));
    try std.testing.expectEqualStrings("ioctl(FICLONE)", done.unsupported orelse "(none)");
    const never = try parseCloneRun(a, "9", unfinished);
    try std.testing.expectEqualStrings("ioctl(FICLONE)", never.unsupported orelse "(none)");
    // A range clone that failed after its split is refused like one on a single line.
    const range = try parseCloneRun(a, "9", "9  ioctl(4</s/key.txt>, BTRFS_IOC_CLONE_RANGE or FICLONERANGE, {src_fd=3</o/src>, src_offset=0, src_length=8192, dest_offset=0} <unfinished ...>\n9  <... ioctl resumed>) = -1 EINVAL (Invalid argument)\n");
    try std.testing.expectEqualStrings("ioctl(FICLONE)", range.unsupported orelse "(none)");
    // Each half is paired by its own pid: the child's failed ioctl in between does not settle
    // the subject's clone.
    const interleaved = try parseCloneRun(a, "10", "9  ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3 <unfinished ...>\n" ++
        "10 ioctl(4</s/key.txt>, TCGETS <unfinished ...>\n10 <... ioctl resumed>, 0xffffd0a8b9c8) = -1 ENOTTY (Inappropriate ioctl for device)\n" ++
        "9  <... ioctl resumed>) = 0\n");
    try std.testing.expectEqualStrings("ioctl(FICLONE)", interleaved.unsupported orelse "(none)");
}

test "a whole-file clone is read as a read only when its errno says nothing was remapped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const early = try parseCloneRun(a, "9", "9  ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3) = -1 EXDEV (Invalid cross-device link)\n");
    try std.testing.expectEqual(@as(?[]const u8, null), early.unsupported);
    const midway = try parseCloneRun(a, "9", "9  ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3) = -1 ENOSPC (No space left on device)\n");
    try std.testing.expectEqualStrings("ioctl(FICLONE)", midway.unsupported orelse "(none)");
}

test "an ioctl that changes nothing in the state is still read-only: a failed whole clone, a clone out of the state, a block-size query" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const lines = [_][]const u8{
        "ioctl(4</s/key.txt>, BTRFS_IOC_CLONE or FICLONE, 3) = -1 EOPNOTSUPP (Operation not supported)",
        "ioctl(5</o/copy>, BTRFS_IOC_CLONE_RANGE or FICLONERANGE, {src_fd=4</s/key.txt>, src_offset=0, src_length=4096, dest_offset=0}) = 0",
        "ioctl(4</s/key.txt>, FIGETBSZ, [4096]) = 0",
        "ioctl(4</s/key.txt>, TCGETS, 0xffffd0a8b9c8) = -1 ENOTTY (Inappropriate ioctl for device)",
    };
    for (lines) |line| {
        for ([_][]const u8{ "9", "10" }) |pid| {
            const p = try parseCloneRun(a, pid, try std.fmt.allocPrint(a, "{s}  {s}\n", .{ pid, line }));
            try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
        }
    }
}

test "an ioctl on a state file whose request cannot be read refuses" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const split = try parseCloneRun(a, "9", "9  ioctl(4</s/key.txt> <unfinished ...>\n");
    try std.testing.expectEqualStrings("ioctl on a state file whose request could not be read", split.unsupported orelse "(none)");
}

test "an ioctl into a state file whose name holds a quote is read as the clone it is" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text = "9  execve(\"/bin/cp\", [\"cp\"], 0x0) = 0\n9  ioctl(4</s/a\\\"b>, BTRFS_IOC_CLONE or FICLONE, 3) = 0\n";
    const p = try parse(a, text, "/s", "", "/w");
    try std.testing.expectEqualStrings("ioctl(FICLONE)", p.unsupported orelse "(none)");
    const split = try parse(a, "9  execve(\"/bin/cp\", [\"cp\"], 0x0) = 0\n9  ioctl(4</s/a\\\"b>, BTRFS_IOC_CLONE or FICLONE, 3 <unfinished ...>\n9  <... ioctl resumed>) = 0\n", "/s", "", "/w");
    try std.testing.expectEqualStrings("ioctl(FICLONE)", split.unsupported orelse "(none)");
}

test "an unresolvable relative path refuses instead of dropping" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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

    const symbolic =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s", O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_DIRECTORY) = 4</tmp/s>
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\
    ;
    const p = try parse(arena_state.allocator(), symbolic, "/tmp/s", "", "/work");
    const expected = [_]contract.OpClass{.open};
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);

    const numeric =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", 0x241) = 3</tmp/s/key.json>
        \\
    ;
    const q = try parse(arena_state.allocator(), numeric, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), q.classes.items.len);

    const creating =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/marker", O_RDONLY|O_CREAT, 0644) = 3</tmp/s/marker>
        \\
    ;
    const r = try parse(arena_state.allocator(), creating, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), r.classes.items.len);

    const via_creat =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    creat("/tmp/s/new.json", 0644) = 3</tmp/s/new.json>
        \\
    ;
    const s = try parse(arena_state.allocator(), via_creat, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), s.classes.items.len);

    const via_openat2 =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat2(AT_FDCWD, "/tmp/s/key.json", {flags=O_RDONLY|O_CLOEXEC, mode=0, resolve=0}, 24) = 3</tmp/s/key.json>
        \\
    ;
    const t = try parse(arena_state.allocator(), via_openat2, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), t.classes.items.len);

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
    try std.testing.expect(!unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/AT_REMOVEDIR.bak\", 0) = 0"));
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", AT_REMOVEDIR) = 0"));
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", 0x200) = 0"));
    try std.testing.expect(unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/sub\", 512) = 0"));
    try std.testing.expect(!unlinkatRemovesDir("unlinkat(AT_FDCWD, \"/tmp/s/f\", 0) = 0"));
    try std.testing.expect(unlinkatRemovesDir("13    unlinkat(AT_FDCWD, \"/tmp/s/sub\", AT_REMOVEDIR) = 0"));
}

test "arguments are split on top-level commas only" {
    const line = "renameat(AT_FDCWD</w>, \"/tmp/s/a,b\", AT_FDCWD</w>, \"/tmp/s/c\") = 0";
    try std.testing.expectEqualStrings("\"/tmp/s/a,b\"", syscallArg(line, 1).?);
    try std.testing.expectEqualStrings("\"/tmp/s/c\"", syscallArg(line, 3).?);
    try std.testing.expectEqual(@as(?[]const u8, null), syscallArg(line, 4));
    const st = "newfstatat(AT_FDCWD, \"/tmp/s/k\", {st_mode=S_IFREG|0644, st_size=6}, 0) = 0";
    try std.testing.expectEqualStrings("0", syscallArg(st, 3).?);
}

test "a syscall v0.1 does not model is reported rather than skipped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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

    const noreplace =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/key.json.tmp", AT_FDCWD, "/tmp/s/key.json", RENAME_NOREPLACE) = 0
        \\
    ;
    const p_nr = try parse(a, noreplace, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_nr.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.rename, p_nr.classes.items[0]);
    try std.testing.expectEqual(@as(?[]const u8, null), p_nr.unsupported);

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

    const lookalike =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\renameat2(AT_FDCWD, "/tmp/s/RENAME_EXCHANGE.bak", AT_FDCWD, "/tmp/s/key.json", 0) = 0
        \\
    ;
    const p_lk = try parse(a, lookalike, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), p_lk.unsupported);
    try std.testing.expectEqual(contract.OpClass.rename, p_lk.classes.items[0]);

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

    const into =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\copy_file_range(3</other/a>, NULL, 4</tmp/s/key.json>, NULL, 6, 0) = 6
        \\
    ;
    const p_in = try parse(a, into, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_in.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.write, p_in.classes.items[0]);
    try std.testing.expectEqual(@as(?[]const u8, null), p_in.unsupported);

    const out_of =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\copy_file_range(3</tmp/s/key.json>, NULL, 4</other/b>, NULL, 6, 0) = 6
        \\
    ;
    const p_out = try parse(a, out_of, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 0), p_out.classes.items.len);
    try std.testing.expectEqual(@as(?[]const u8, null), p_out.unsupported);

    const sf =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\sendfile(4</tmp/s/key.json>, 3</other/a>, NULL, 6) = 6
        \\
    ;
    const p_sf = try parse(a, sf, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p_sf.classes.items.len);
    try std.testing.expectEqual(contract.OpClass.write, p_sf.classes.items[0]);

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

test "faccessat2 and epoll_ctl on the state directory are reads, for the subject and for a child (#542)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Case = struct { what: []const u8, line: []const u8 };
    const cases = [_]Case{
        .{ .what = "faccessat2 on a state file", .line = "faccessat2(AT_FDCWD</work>, \"/tmp/s/a.pdf\", W_OK, AT_EACCESS) = 0" },
        .{ .what = "faccessat2 from a cwd inside the state", .line = "faccessat2(AT_FDCWD</tmp/s/app>, \"/usr/local/bin/\", F_OK, AT_EACCESS) = 0" },
        .{ .what = "epoll_ctl of a state file", .line = "epoll_ctl(4<anon_inode:[eventpoll]>, EPOLL_CTL_ADD, 3</tmp/s/key.json>, {events=EPOLLIN|EPOLLOUT|EPOLLRDHUP|EPOLLET, data=0x0}) = -1 EPERM (Operation not permitted)" },
        .{ .what = "epoll_ctl split across two lines", .line = "epoll_ctl(4<anon_inode:[eventpoll]>, EPOLL_CTL_ADD, 3</tmp/s/key.json>, {events=EPOLLIN, data=0x0} <unfinished ...>\n42    <... epoll_ctl resumed>) = -1 EPERM (Operation not permitted)" },
    };
    for (cases) |c| {
        const subject = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    {s}\n", .{c.line});
        const p = try parse(a, subject, "/tmp/s", "", "/work");
        if (p.unsupported) |u| {
            std.debug.print("{s}: the subject was refused on {s}\n", .{ c.what, u });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(p.lines_in_scope >= 1);
        try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
        const child = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  {s}\n", .{try std.mem.replaceOwned(u8, a, c.line, "\n42    ", "\n4242  ")});
        const q = try parse(a, child, "/tmp/s", "", "/work");
        if (q.childTouched()) {
            std.debug.print("{s}: the child was counted as touching the state\n", .{c.what});
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqual(@as(usize, 1), q.children);
    }
    // The control: a call nobody names, on the same kind of line, still refuses — the list
    // grew by two names, not into a rule that waves through anything unrecognised.
    const unknown_sys = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    frobnicate(3</tmp/s/key.json>) = 0\n";
    const r = try parse(a, unknown_sys, "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("frobnicate", r.unsupported.?);
}

test "extended-attribute reads, inotify_add_watch, preadv and the polls are reads; xattr writes are metadata, from the subject and a child" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Case = struct { what: []const u8, line: []const u8 };
    const reads = [_]Case{
        .{ .what = "getxattr (real: vim)", .line = "getxattr(\"/tmp/s/a.txt\", \"system.posix_acl_access\", 0xffffcd859420, 132) = -1 ENODATA (No data available)" },
        .{ .what = "lgetxattr", .line = "lgetxattr(\"/tmp/s/a.txt\", \"security.selinux\", 0xffff0000, 255) = -1 ENODATA (No data available)" },
        .{ .what = "fgetxattr", .line = "fgetxattr(3</tmp/s/a.txt>, \"user.mime_type\", 0xffff0000, 64) = -1 ENODATA (No data available)" },
        .{ .what = "listxattr (real: dotdrop)", .line = "listxattr(\"/tmp/s/home/.bashrc\", \"\", 256) = 0" },
        .{ .what = "llistxattr", .line = "llistxattr(\"/tmp/s/home/.bashrc\", \"\", 256) = 0" },
        .{ .what = "flistxattr", .line = "flistxattr(3</tmp/s/zones/public.xml>, \"\", 256) = 0" },
        .{ .what = "inotify_add_watch (real: fish)", .line = "inotify_add_watch(4<anon_inode:inotify>, \"/tmp/s/fish\", IN_MODIFY|IN_MOVED_TO) = 1" },
        .{ .what = "preadv", .line = "preadv(3</tmp/s/key.json>, [{iov_base=\"key=1\\n\", iov_len=16}], 1, 0) = 6" },
        .{ .what = "preadv2", .line = "preadv2(3</tmp/s/key.json>, [{iov_base=\"key=1\\n\", iov_len=16}], 1, 0, RWF_NOWAIT) = 6" },
        .{ .what = "poll", .line = "poll([{fd=3</tmp/s/key.json>, events=POLLIN}], 1, 0) = 1 ([{fd=3, revents=POLLIN}])" },
        .{ .what = "ppoll (real shape: jj)", .line = "ppoll([{fd=0</dev/null>, events=0}, {fd=3</tmp/s/key.json>, events=0}], 2, {tv_sec=0, tv_nsec=0}, NULL, 8) = 0 (Timeout)" },
        .{ .what = "select", .line = "select(4, [3</tmp/s/key.json>], NULL, NULL, {tv_sec=0, tv_usec=0}) = 1 (in [3], left {tv_sec=0, tv_usec=0})" },
        .{ .what = "pselect6", .line = "pselect6(4, [3</tmp/s/key.json>], NULL, NULL, {tv_sec=0, tv_nsec=0}, NULL) = 1 (in [3], left {tv_sec=0, tv_nsec=0})" },
    };
    for (reads) |c| {
        const subject = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    {s}\n", .{c.line});
        const p = try parse(a, subject, "/tmp/s", "", "/work");
        if (p.unsupported) |u| {
            std.debug.print("{s}: the subject was refused on {s}\n", .{ c.what, u });
            return error.TestUnexpectedResult;
        }
        try std.testing.expect(p.lines_in_scope >= 1);
        try std.testing.expectEqual(@as(usize, 0), p.classes.items.len);
        const child = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  {s}\n", .{c.line});
        const q = try parse(a, child, "/tmp/s", "", "/work");
        if (q.childTouched() or q.unsupported != null) {
            std.debug.print("{s}: the child was counted as touching the state\n", .{c.what});
            return error.TestUnexpectedResult;
        }
        try std.testing.expectEqual(@as(usize, 1), q.children);
    }
    const writes = [_]Case{
        .{ .what = "setxattr (real: vim)", .line = "setxattr(\"/tmp/s/a.txt\", \"system.posix_acl_access\", \"\\2\\0\\0\\0\", 28, 0) = 0" },
        .{ .what = "lsetxattr", .line = "lsetxattr(\"/tmp/s/a.txt\", \"user.x\", \"1\", 1, 0) = 0" },
        .{ .what = "fsetxattr", .line = "fsetxattr(3</tmp/s/a.txt>, \"user.x\", \"1\", 1, 0) = 0" },
        .{ .what = "removexattr", .line = "removexattr(\"/tmp/s/a.txt\", \"user.x\") = 0" },
        .{ .what = "lremovexattr", .line = "lremovexattr(\"/tmp/s/a.txt\", \"user.x\") = 0" },
        .{ .what = "fremovexattr", .line = "fremovexattr(3</tmp/s/a.txt>, \"user.x\") = 0" },
    };
    for (writes) |c| {
        const subject = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    {s}\n", .{c.line});
        const p = try parse(a, subject, "/tmp/s", "", "/work");
        const name = c.what[0 .. std.mem.indexOfScalar(u8, c.what, ' ') orelse c.what.len];
        if (p.unsupported != null or p.classes.items.len != 0 or p.metadata_observed.items.len != 1 or
            !std.mem.eql(u8, p.metadata_observed.items[0], name))
        {
            std.debug.print("{s}: the subject's write was not reported as metadata\n", .{c.what});
            return error.TestUnexpectedResult;
        }
        const child = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  {s}\n", .{c.line});
        const q = try parse(a, child, "/tmp/s", "", "/work");
        try std.testing.expectEqual(@as(usize, 1), q.children);
        if (q.unsupported != null or q.childTouched() or q.metadata_observed.items.len != 1 or
            !std.mem.eql(u8, q.metadata_observed.items[0], name))
        {
            std.debug.print("{s}: a child's write was not reported as metadata\n", .{c.what});
            return error.TestUnexpectedResult;
        }
    }
}

test "an extended-attribute write through a descriptor outside the state is not named, and one through an empty path is named wherever it points" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const head = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n";
    for ([_][]const u8{
        "42    fsetxattr(3</etc/x>, \"user.k\", \"1\", 1, 0) = 0\n",
        "42    fremovexattr(3</etc/x>, \"user.k\") = 0\n",
    }) |l| {
        const p = try parse(a, try std.mem.concat(a, u8, &.{ head, l }), "/tmp/s", "", "/work");
        try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
        try std.testing.expectEqual(@as(usize, 0), p.metadata_observed.items.len);
    }
    const empty = try parse(a, head ++ "42    setxattrat(5</etc>, \"\", AT_EMPTY_PATH, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), empty.metadata_observed.items.len);
}

test "an extended-attribute write is reported through a relative path as it is through an absolute one" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Case = struct { what: []const u8, lines: []const u8, observed: ?[]const u8 };
    const cases = [_]Case{
        .{ .what = "setxattr, relative to the cwd", .observed = "setxattr", .lines = "42    setxattr(\"s/key.json\", \"user.k\", \"1\", 1, 0) = 0\n" },
        .{ .what = "lsetxattr, relative to the cwd", .observed = "lsetxattr", .lines = "42    lsetxattr(\"s/key.json\", \"user.k\", \"1\", 1, 0) = 0\n" },
        .{ .what = "removexattr, relative to the cwd", .observed = "removexattr", .lines = "42    removexattr(\"s/key.json\", \"user.k\") = 0\n" },
        .{ .what = "lremovexattr, relative to the cwd", .observed = "lremovexattr", .lines = "42    lremovexattr(\"s/key.json\", \"user.k\") = 0\n" },
        .{ .what = "setxattrat through AT_FDCWD", .observed = "setxattrat", .lines = "42    setxattrat(AT_FDCWD</tmp>, \"s/key.json\", 0, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n" },
        .{ .what = "removexattrat through AT_FDCWD", .observed = "removexattrat", .lines = "42    removexattrat(AT_FDCWD</tmp>, \"s/key.json\", 0, \"user.k\") = 0\n" },
        .{ .what = "setxattrat through a directory descriptor in the state", .observed = "setxattrat", .lines = "42    setxattrat(5</tmp/s>, \"key.json\", 0, \"user.k\", {value=\"1\", size=1, flags=0}, 16) = 0\n" },
        .{ .what = "setxattr relative to a cwd the subject moved into the state", .observed = "setxattr", .lines = "42    chdir(\"/tmp/s\") = 0\n42    setxattr(\"key.json\", \"user.k\", \"1\", 1, 0) = 0\n" },
        .{ .what = "control: setxattr relative to the cwd, outside the state", .observed = null, .lines = "42    setxattr(\"other/x\", \"user.k\", \"1\", 1, 0) = 0\n" },
        .{ .what = "control: setxattr on an absolute path outside the state", .observed = null, .lines = "42    setxattr(\"/etc/x\", \"user.k\", \"1\", 1, 0) = 0\n" },
        .{ .what = "control: the cwd moved out of the state before a relative write", .observed = null, .lines = "42    chdir(\"/tmp/s\") = 0\n42    chdir(\"..\") = 0\n42    setxattr(\"key.json\", \"user.k\", \"1\", 1, 0) = 0\n" },
    };
    for (cases) |c| {
        const text = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n{s}", .{c.lines});
        const p = try parse(a, text, "/tmp/s", "", "/tmp");
        try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
        if (c.observed) |r| {
            std.testing.expect(p.metadata_observed.items.len == 1 and std.mem.eql(u8, p.metadata_observed.items[0], r)) catch |e| {
                std.debug.print("case: {s}\n", .{c.what});
                return e;
            };
        } else if (p.metadata_observed.items.len != 0) {
            std.debug.print("case: {s} reported as {s}\n", .{ c.what, p.metadata_observed.items[0] });
            return error.TestUnexpectedResult;
        }
    }
    const child = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  setxattr(\"s/key.json\", \"user.k\", \"1\", 1, 0) = 0\n";
    const q = try parse(a, child, "/tmp/s", "", "/tmp");
    try std.testing.expectEqual(@as(?[]const u8, null), q.unsupported);
    try std.testing.expect(!q.childTouched());
    try std.testing.expectEqual(@as(usize, 1), q.metadata_observed.items.len);
    const child_outside = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n4242  setxattr(\"/etc/x\", \"user.k\", \"1\", 1, 0) = 0\n";
    const r = try parse(a, child_outside, "/tmp/s", "", "/tmp");
    try std.testing.expectEqual(@as(?[]const u8, null), r.unsupported);
    try std.testing.expectEqual(@as(usize, 0), r.metadata_observed.items.len);
    const no_cwd = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n42    setxattr(\"s/key.json\", \"user.k\", \"1\", 1, 0) = 0\n";
    const u = try parse(a, no_cwd, "/tmp/s", "", "");
    try std.testing.expectEqual(@as(?[]const u8, null), u.unsupported);
    try std.testing.expectEqual(@as(usize, 1), u.metadata_observed.items.len);
}

test "both of strace's -f pid prefixes are stripped" {
    try std.testing.expectEqualStrings("openat", syscallName("[pid  1234] openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("clone", syscallName("[pid 99] clone(child_stack=NULL) = 100").?);
    try std.testing.expectEqualStrings("openat", syscallName("13    openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("write", syscallName("7\twrite(3, \"x\", 1) = 1").?);
    try std.testing.expectEqualStrings("write", syscallName("write(3, \"x\", 1) = 1").?);
}

test "a child that stays out of the state directory is not a refusal" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

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
    const want = [_]contract.OpClass{.write};
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 0), p.spawns.items.len);
}

test "CLONE_FS without CLONE_THREAD still refuses (v16)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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
    try std.testing.expectEqualStrings("4</tmp/s/k>", syscallArg("50    fsync(4</tmp/s/k> <unfinished ...>", 0).?);
    try std.testing.expectEqualStrings("6", syscallArg("50    write(4</tmp/s/k>, \"key=2\\n\", 6 <unfinished ...>", 2).?);
    try std.testing.expectEqual(@as(?[]const u8, null), syscallArg("50    fsync(4</tmp/s/k> <unfinished ...>", 1));
    try std.testing.expectEqualStrings("4</tmp/s/k>", syscallArg("50    fsync(4</tmp/s/k>) = 0", 0).?);
}

test "an unshimmed child detaching is caught by the oracle" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  setsid()                          = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
    try std.testing.expect(p.detached != null);
    try std.testing.expect(p.boundary == null);

    const own =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    setpgid(0, 0)                     = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), own, "/tmp/s", "", "/work");
    try std.testing.expectEqual(@as(?[]const u8, null), q.boundary);
    try std.testing.expectEqual(@as(?[]const u8, null), q.detached);
}

test "a shared writable mapping of a state file is a mutation nobody models" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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

    const private =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const r = try parse(arena_state.allocator(), private, "/tmp/s", "", "/work");
    try std.testing.expect(!r.childTouched());
}

test "a shared mapping of a state file made writable later is refused, and nothing else is (#689, ADR 0098)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const want = "mprotect(PROT_WRITE) on a shared mapping of a state file";
    const Case = struct { what: []const u8, text: []const u8, refused: ?[]const u8 };
    const cases = [_]Case{
        .{ .what = "read-only shared map, then PROT_WRITE", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a child's writable shared map (the v15 touch alone admitted it)", .refused = "mmap(PROT_WRITE|MAP_SHARED)", .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f
        \\
        },
        .{ .what = "an mprotect overlapping the range only in part", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000010000
        \\42    mprotect(0x7f0000000000, 0x11000, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a forked child's mprotect on the parent's mapping", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\4242  mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a split mmap whose address is on the resumed half", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0 <unfinished ...>
        \\43    getpid() = 43
        \\42    <... mmap resumed>) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a range mremap moved", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mremap(0x7f0000000000, 8192, 65536, MREMAP_MAYMOVE) = 0x7f1000000000
        \\42    mprotect(0x7f1000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a duplicate mremap makes of the pages, with old_len 0", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mremap(0x7f0000000000, 0, 8192, MREMAP_MAYMOVE) = 0x7f3000000000
        \\42    mprotect(0x7f3000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a write-capable open split across its resumed half", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR <unfinished ...>
        \\43    getpid() = 43
        \\42    <... openat resumed>) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "opened for writing as one name, renamed, then mapped (second review)", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db.tmp", O_RDWR|O_CREAT, 0644) = 3</tmp/s/db.tmp>
        \\42    rename("/tmp/s/db.tmp", "/tmp/s/db") = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "opened for writing outside the state, renamed in, then mapped", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/work/staging", O_RDWR|O_CREAT, 0644) = 3</work/staging>
        \\42    renameat2(AT_FDCWD, "/work/staging", AT_FDCWD, "/tmp/s/db", RENAME_NOREPLACE) = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "linked, the first name removed, then mapped through the old descriptor", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/a", O_RDWR) = 3</tmp/s/a>
        \\42    link("/tmp/s/a", "/tmp/s/b") = 0
        \\42    unlink("/tmp/s/a") = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/a (deleted)>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a split writable shared map whose file name holds ' = -'", .refused = "mmap(PROT_WRITE|MAP_SHARED)", .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/x = -1>, 0 <unfinished ...>
        \\43    getpid() = 43
        \\42    <... mmap resumed>) = 0x7f0000000000
        \\
        },
        .{ .what = "a read-only open mapped, unmapped, and the address made writable by something else (memmap2)", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDONLY|O_CLOEXEC) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a read-only open mapped and made writable, after a trapped rename of the empty path", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDONLY|O_CLOEXEC) = 3</tmp/s/db>
        \\42    renameat(AT_FDCWD</tmp/s>, "", AT_FDCWD</tmp/s>, "db") = 4294967196
        \\42    --- SIGSYS {si_signo=SIGSYS, si_code=SYS_SECCOMP, si_syscall=__NR_renameat, si_arch=AUDIT_ARCH_X86_64} ---
        \\42    renameat(AT_FDCWD</tmp/s>, "", AT_FDCWD</tmp/s>, "db") = -1 ENOENT (No such file or directory)
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "an mprotect that failed", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = -1 EACCES (Permission denied)
        \\
        },
        .{ .what = "a writable shared mapping that failed", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/db>, 0) = -1 EACCES (Permission denied)
        \\
        },
        .{ .what = "an anonymous mapping made writable (a JIT)", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a shared mapping of a file outside the state", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</usr/lib/gconv/gconv-modules.cache>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a private mapping of a state file made writable", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mmap(NULL, 8192, PROT_READ, MAP_PRIVATE, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a failed mapping remembers nothing", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = -1 ENOMEM (Cannot allocate memory)
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a read-only shared map kept read-only (bbolt's shape, writes through pwrite)", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 4096, PROT_READ) = 0
        \\42    mprotect(0x7f2000000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
    };
    for (cases) |c| {
        const p = try parse(a, c.text, "/tmp/s", "", "/work");
        if (c.refused) |r| {
            std.testing.expectEqualStrings(r, p.unsupported orelse "(none)") catch |e| {
                std.debug.print("case: {s}\n", .{c.what});
                return e;
            };
        } else if (p.unsupported) |u| {
            std.debug.print("case: {s} refused as {s}\n", .{ c.what, u });
            return error.TestUnexpectedResult;
        }
    }
}

test "a mapping call whose length is near 2^64 is read without overflowing, and still refused where it overlaps a shared state map" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const want = "mprotect(PROT_WRITE) on a shared mapping of a state file";
    const Case = struct { what: []const u8, text: []const u8, refused: ?[]const u8 };
    const cases = [_]Case{
        .{ .what = "a failed mremap of (size_t)-1 with no shared map", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mremap(NULL, 18446744073709551615, 4096, 0) = -1 EINVAL (Invalid argument)
        \\
        },
        .{ .what = "a split mprotect of (size_t)-1, whose failure is not shown yet", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    mprotect(0x7f0000000000, 18446744073709551615, PROT_READ|PROT_WRITE <unfinished ...>
        \\43    getpid() = 43
        \\42    <... mprotect resumed>) = -1 ENOMEM (Cannot allocate memory)
        \\
        },
        .{ .what = "a read-only shared map of (size_t)-1 bytes covers the rest of the address space", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 18446744073709551615, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7fff00000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "a split read-only shared map of (size_t)-1 bytes, its address on the resumed half", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 18446744073709551615, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0 <unfinished ...>
        \\43    getpid() = 43
        \\42    <... mmap resumed>) = 0x7f0000000000
        \\42    mprotect(0x7fff00000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "an mremap of a shared state map to (size_t)-1 bytes", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mremap(0x7f0000000000, 8192, 18446744073709551615, MREMAP_MAYMOVE) = 0x7f1000000000
        \\42    mprotect(0x7fff00000000, 4096, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "an mprotect(PROT_WRITE) of (size_t)-1 bytes over a shared state map", .refused = want, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000000000, 18446744073709551615, PROT_READ|PROT_WRITE) = 0
        \\
        },
        .{ .what = "an mprotect(PROT_WRITE) of (size_t)-1 bytes starting above every shared map", .refused = null, .text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/db", O_RDWR) = 3</tmp/s/db>
        \\42    mmap(NULL, 8192, PROT_READ, MAP_SHARED, 3</tmp/s/db>, 0) = 0x7f0000000000
        \\42    mprotect(0x7f0000100000, 18446744073709551615, PROT_READ|PROT_WRITE) = 0
        \\
        },
    };
    for (cases) |c| {
        const p = try parse(a, c.text, "/tmp/s", "", "/work");
        if (c.refused) |r| {
            std.testing.expectEqualStrings(r, p.unsupported orelse "(none)") catch |e| {
                std.debug.print("case: {s}\n", .{c.what});
                return e;
            };
        } else if (p.unsupported) |u| {
            std.debug.print("case: {s} refused as {s}\n", .{ c.what, u });
            return error.TestUnexpectedResult;
        }
    }
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

    const nothing = [_]contract.OpClass{};
    const missed = compare(&nothing, &a).?;
    try std.testing.expectEqual(@as(usize, 0), missed.missed.index);
    try std.testing.expectEqual(contract.OpClass.open, missed.missed.class);

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

    const swapped = [_]contract.OpClass{ .open, .unlink, .rename };
    const mid = compare(&a, &swapped).?;
    try std.testing.expectEqual(@as(usize, 1), mid.missed.index);
}

test "every fd syscall the classifier knows declares which argument holds its descriptor (#280)" {
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

    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    wait4(29,  <unfinished ...>"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, 0xffffd4dafb20, WNOHANG, NULL) = -1 ECHILD (No child processes)"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("38    <... wait4 resumed>0xffffd8be1d4c, 0, NULL) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)"));

    try std.testing.expectEqual(@as(?u64, 4242), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=4242, si_uid=0, si_status=0}, WEXITED, NULL) = 0"));

    // Not waits. The second is the control that matters: a line ending in a number is
    // not a reap, and a reader that only looked at the tail would count every successful
    // `openat` as one.
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    exit_group(0)                     = ?"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    openat(AT_FDCWD</w>, \"/tmp/s/a\", O_WRONLY|O_CREAT, 0644) = 29"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    <... openat resumed>) = 29"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("28    wait4ever(1) = 7"));
}

test "the parse collects who wrote and who was reaped (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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
    try std.testing.expectEqual(@as(usize, 3), p.mutations.items.len);
    try std.testing.expectEqual(@as(u64, 42), p.mutations.items[0].id);
    try std.testing.expectEqual(@as(u64, 4242), p.mutations.items[1].id);
    try std.testing.expectEqual(@as(u64, 42), p.mutations.items[2].id);
    try std.testing.expectEqual(@as(usize, 1), p.reaps.items.len);
    try std.testing.expectEqual(@as(u64, 4242), p.reaps.items[0].id);
    try std.testing.expect(p.reaps.items[0].at > p.mutations.items[1].at);
    try std.testing.expect(p.reaps.items[0].at < p.mutations.items[2].at);
    try std.testing.expectEqual(@as(usize, 2), p.classes.items.len);
}

test "a child nobody waited for leaves the reaped set empty (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
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
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, [{WIFSTOPPED(s) && WSTOPSIG(s) == SIGTSTP}], WUNTRACED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("47    wait4(-1, [{WIFCONTINUED(s)}], WCONTINUED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_EXITED, si_pid=4242, si_status=0}, WEXITED|WNOWAIT, NULL) = 0"));
    try std.testing.expectEqual(@as(?u64, null), reapedPid("42    waitid(P_PID, 4242, {si_signo=SIGCHLD, si_code=CLD_STOPPED, si_pid=4242, si_status=SIGTSTP}, WSTOPPED, NULL) = 0"));

    // The control: the same calls when the child really did end. Without these the four
    // above would be satisfied by a function that answered null to everything.
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WUNTRACED, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(-1, [{WIFSIGNALED(s) && WTERMSIG(s) == SIGKILL}], 0, NULL) = 53"));
    try std.testing.expectEqual(@as(?u64, 53), reapedPid("47    wait4(53, NULL, 0, NULL) = 53"));
}

test "where a child was created, read from both spellings (v15)" {
    try std.testing.expectEqual(@as(?u64, 29), spawnedPid("28    clone(child_stack=NULL, flags=CLONE_CHILD_CLEARTID|SIGCHLD, child_tidptr=0xff) = 29"));
    try std.testing.expectEqual(@as(?u64, 26), spawnedPid("25    <... clone resumed>)              = 26"));
    try std.testing.expectEqual(@as(?u64, 50), spawnedPid("49    clone(child_stack=0xffff97ff0000, flags=CLONE_VM|CLONE_VFORK|SIGCHLD) = 50"));
    try std.testing.expectEqual(@as(?u64, 4242), spawnedPid("42    clone3({flags=0, exit_signal=SIGCHLD}, 88) = 4242"));

    try std.testing.expectEqual(@as(?u64, null), spawnedPid("42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_THREAD|CLONE_SIGHAND) = 43"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    clone(child_stack=NULL, flags=SIGCHLD <unfinished ...>"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    clone(child_stack=NULL, flags=SIGCHLD) = -1 EAGAIN (Resource temporarily unavailable)"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("29    <... clone resumed>)              = 0"));
    // Not spawns. The second is the control: a line ending in a number is not a creation.
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    wait4(29, NULL, 0, NULL) = 29"));
    try std.testing.expectEqual(@as(?u64, null), spawnedPid("28    openat(AT_FDCWD, \"/tmp/s/a\", O_WRONLY) = 29"));
}

test "a child's relative path is not resolved against the subject's directory (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const text =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\4242  chdir("/tmp/s") = 0
        \\4242  rename("a", "b") = 0
        \\42    wait4(4242, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], 0, NULL) = 4242
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s", "", "/work");
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

    const subject_relative =
        \\42    execve("/work/toy", ["toy", "rotate"], 0x7ff) = 0
        \\42    rename("key", "key.bak") = 0
        \\
    ;
    const r = try parse(arena_state.allocator(), subject_relative, "/tmp/s", "", "/work");
    try std.testing.expect(!r.childTouched());
    try std.testing.expectEqual(@as(usize, 0), r.classes.items.len);
}

test "a move between cgroups is seen from any process, and a read, a failure or a look-alike name is not one (v17, #559)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const launch = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n";
    const moves = [_][]const u8{
        "4242  openat(AT_FDCWD, \"/sys/fs/cgroup/elsewhere/cgroup.procs\", O_WRONLY|O_TRUNC) = 3</sys/fs/cgroup/elsewhere/cgroup.procs>\n",
        "42    openat(5</sys/fs/cgroup/elsewhere>, \"cgroup.threads\", O_WRONLY) = 3</sys/fs/cgroup/elsewhere/cgroup.threads>\n",
        "42    openat(AT_FDCWD, \"/sys/fs/cgroup/sideeye-1-ab/cgroup.type\", O_WRONLY <unfinished ...>\n",
        "4242  clone3({flags=CLONE_INTO_CGROUP, exit_signal=SIGCHLD, stack=NULL, stack_size=0, cgroup=5</sys/fs/cgroup/elsewhere>}, 88) = 4243\n",
        "42    open_by_handle_at(3</sys/fs/cgroup>, {handle_bytes=8, handle_type=254, f_handle=0x0100000000000000}, O_WRONLY|O_CLOEXEC) = 4</sys/fs/cgroup/elsewhere/cgroup.procs>\n",
        "42    openat(AT_FDCWD, \"/sys/fs/cgroup/a = -1 E/cgroup.procs\", O_WRONLY) = 3</sys/fs/cgroup/a = -1 E/cgroup.procs>\n",
    };
    for (moves) |m| {
        const text = try std.mem.concat(a, u8, &.{ launch, m });
        const p = try parse(a, text, "/tmp/s", "", "/work");
        if (p.cgroup_move == null) {
            std.debug.print("not seen as a move: {s}", .{m});
            return error.TestUnexpectedResult;
        }
    }
    const not_moves = [_][]const u8{
        "42    openat(AT_FDCWD, \"/proc/self/cgroup\", O_RDONLY|O_CLOEXEC) = 3</proc/42/cgroup>\n",
        "42    openat(AT_FDCWD, \"/sys/fs/cgroup/x/cgroup.procs\", O_RDONLY) = 3</sys/fs/cgroup/x/cgroup.procs>\n",
        "42    openat(AT_FDCWD, \"/sys/fs/cgroup/x/cgroup.procs\", O_WRONLY) = -1 EACCES (Permission denied)\n",
        "42    openat(AT_FDCWD, \"/tmp/s/not-cgroup.procs\", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/not-cgroup.procs>\n",
        "4242  clone3({flags=CLONE_VM|CLONE_FS, exit_signal=0}, 88) = 4243\n",
        "42    open_by_handle_at(3</sys/fs/cgroup>, {handle_bytes=8, handle_type=254, f_handle=0x01}, O_RDONLY) = 4</sys/fs/cgroup/elsewhere/cgroup.procs>\n",
        "4242  clone3({flags=CLONE_INTO_CGROUP, cgroup=5</sys/fs/cgroup/elsewhere>}, 88) = -1 EPERM (Operation not permitted)\n",
    };
    for (not_moves) |m| {
        const text = try std.mem.concat(a, u8, &.{ launch, m });
        const p = try parse(a, text, "/tmp/s", "", "/work");
        if (p.cgroup_move != null) {
            std.debug.print("taken for a move: {s}", .{m});
            return error.TestUnexpectedResult;
        }
    }
    const early = try parse(a, "4242  openat(AT_FDCWD, \"/sys/fs/cgroup/x/cgroup.procs\", O_WRONLY) = 3\n", "/tmp/s", "", "/work");
    try std.testing.expect(early.cgroup_move == null);
}

test "a call a signal interrupted before it ran is not counted, in either shape strace prints it (#217)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\45    execve("/tmp/toy-sig", ["toy-sig", "rotate"], 0x7ff) = 0
        \\45    write(3</tmp/sg/f.tmp>, "x\n", 2 <unfinished ...>
        \\46    kill(45, SIGUSR1 <unfinished ...>
        \\45    <... write resumed>)              = ? ERESTARTSYS (To be restarted if SA_RESTART is set)
        \\46    <... kill resumed>)               = 0
        \\45    --- SIGUSR1 {si_signo=SIGUSR1, si_code=SI_USER, si_pid=45, si_uid=0} ---
        \\45    write(3</tmp/sg/f.tmp>, "x\n", 2) = 2
        \\45    openat(AT_FDCWD</work>, "/tmp/sg/f.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0644) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)
        \\45    --- SIGUSR1 {si_signo=SIGUSR1, si_code=SI_USER, si_pid=45, si_uid=0} ---
        \\45    openat(AT_FDCWD</work>, "/tmp/sg/f.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 4</tmp/sg/f.tmp>
        \\
    ;
    fold_restarted = true;
    defer fold_restarted = false;
    const p = try parse(arena_state.allocator(), text, "/tmp/sg", "", "/work");
    const want = [_]contract.OpClass{ .write, .open };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
    try std.testing.expectEqual(@as(usize, 2), p.lines_in_scope);
    try std.testing.expect(std.mem.endsWith(u8, p.lines.items[0], "= 2"));
}

test "the control: the same calls without the interruption are counted once each (#217)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\45    execve("/tmp/toy-sig", ["toy-sig", "rotate"], 0x7ff) = 0
        \\45    write(3</tmp/sg/f.tmp>, "x\n", 2 <unfinished ...>
        \\46    kill(45, SIGUSR1 <unfinished ...>
        \\45    <... write resumed>)              = 2
        \\45    write(3</tmp/sg/f.tmp>, "x\n", 2) = 2
        \\45    openat(AT_FDCWD</work>, "/tmp/sg/f.tmp", O_WRONLY|O_CREAT|O_TRUNC, 0644) = 4</tmp/sg/f.tmp>
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/sg", "", "/work");
    const want = [_]contract.OpClass{ .write, .write, .open };
    try std.testing.expectEqualSlices(contract.OpClass, &want, p.classes.items);
}

test "outside --observe supervised an interrupted call still counts, as the shim at libc's entry counts it (#217 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\45    execve("/tmp/toy", ["toy", "rotate"], 0x7ff) = 0
        \\45    write(3</tmp/sg/f.tmp>, "x\\n", 2) = ? ERESTARTSYS (To be restarted if SA_RESTART is set)
        \\45    --- SIGUSR1 {si_signo=SIGUSR1, si_code=SI_USER, si_pid=45, si_uid=0} ---
        \\45    write(3</tmp/sg/f.tmp>, "x\\n", 2) = 2
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/sg", "", "/work");
    try std.testing.expectEqual(@as(usize, 2), p.classes.items.len);
}

test "a target-chosen string cannot pass for strace's interrupted-call return (#217 review)" {
    try std.testing.expect(!isRestartedCall("45    write(3</s/f>, \" = ? ERESTARTSYS (To be restarted if SA_RESTART is set)\", 57) = 57"));
    try std.testing.expect(isRestartedCall("45    <... write resumed>)              = ? ERESTARTSYS (To be restarted if SA_RESTART is set)"));
    try std.testing.expect(isRestartedCall("45    openat(AT_FDCWD</w>, \"/s/f\", O_WRONLY) = ? ERESTARTNOINTR (To be restarted)"));
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    fold_restarted = true;
    defer fold_restarted = false;
    const text =
        \\45    execve("/tmp/toy", ["toy", "rotate"], 0x7ff) = 0
        \\45    write(3</tmp/sg/f>, " = ? ERESTARTSYS (To be restarted if SA_RESTART is set)", 57) = 57
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/sg", "", "/work");
    try std.testing.expectEqual(@as(usize, 1), p.classes.items.len);
}

// Not extended past the strace the CI installs (6.8): calls a newer strace adds are not printed by
// that one, so the reader never sees them.
const strace_file_class = [_][]const u8{
    "access",     "acct",              "chdir",             "chmod",        "chown",      "chroot",
    "creat",      "execve",            "execveat",          "faccessat",    "faccessat2", "fanotify_mark",
    "fchmodat",   "fchmodat2",         "fchownat",          "fsconfig",     "fspick",     "futimesat",
    "getcwd",     "getxattr",          "inotify_add_watch", "lchown",       "lgetxattr",  "link",
    "linkat",     "listxattr",         "llistxattr",        "lremovexattr", "lsetxattr",  "lstat",
    "mkdir",      "mkdirat",           "mknod",             "mknodat",      "mount",      "mount_setattr",
    "move_mount", "name_to_handle_at", "newfstatat",        "open",         "open_tree",  "openat",
    "openat2",    "pivot_root",        "quotactl",          "readlink",     "readlinkat", "removexattr",
    "rename",     "renameat",          "renameat2",         "rmdir",        "setxattr",   "stat",
    "statfs",     "statx",             "swapoff",           "swapon",       "symlink",    "symlinkat",
    "truncate",   "umount2",           "unlink",            "unlinkat",     "uselib",     "utime",
    "utimensat",  "utimes",
};

const UnspelledCall = struct { name: []const u8, why: []const u8 };
const unspelled_file_calls = [_]UnspelledCall{
    .{ .name = "execve", .why = "a process call: its path names the image to run, and the reader decides on it before any scope" },
    .{ .name = "execveat", .why = "the same, for the descriptor-relative form" },
    .{ .name = "chdir", .why = "the call the relative spellings below are built from" },
    .{ .name = "getcwd", .why = "no path argument: strace prints the result, not an argument" },
    .{ .name = "fsconfig", .why = "its path argument holds a plain value (FSCONFIG_SET_STRING's \"tmpfs\", say) for every command but FSCONFIG_SET_PATH and FSCONFIG_SET_PATH_EMPTY, so resolving it would refuse calls made elsewhere" },
    .{ .name = "quotactl", .why = "strace prints its command as QCMD(...), and syscallArg does not nest that comma, so no later argument can be read; ioctl's _IOC(...) is read through that same split" },
};

// Not read from `path_syscalls`: a position copied from the table would agree with the table's own
// mistake.
const SpelledCall = struct { name: []const u8, args: []const []const u8, result: []const u8 = " = 0" };
const spelled_calls = [_]SpelledCall{
    .{ .name = "open", .args = &.{ "@P0", "O_WRONLY|O_CREAT|O_TRUNC", "0644" }, .result = " = 3<@A0>" },
    .{ .name = "creat", .args = &.{ "@P0", "0644" }, .result = " = 3<@A0>" },
    .{ .name = "openat", .args = &.{ "@D0", "@P0", "O_WRONLY|O_CREAT|O_TRUNC", "0644" }, .result = " = 3<@A0>" },
    .{ .name = "openat2", .args = &.{ "@D0", "@P0", "{flags=O_WRONLY|O_CREAT|O_TRUNC, mode=0644, resolve=0}", "24" }, .result = " = 3<@A0>" },
    .{ .name = "open_tree", .args = &.{ "@D0", "@P0", "OPEN_TREE_CLONE" }, .result = " = 3<@A0>" },
    .{ .name = "mkdir", .args = &.{ "@P0", "0755" } },
    .{ .name = "mkdirat", .args = &.{ "@D0", "@P0", "0755" } },
    .{ .name = "mknod", .args = &.{ "@P0", "S_IFREG|0644" } },
    .{ .name = "mknodat", .args = &.{ "@D0", "@P0", "S_IFREG|0644" } },
    .{ .name = "unlink", .args = &.{"@P0"} },
    .{ .name = "unlinkat", .args = &.{ "@D0", "@P0", "0" } },
    .{ .name = "rmdir", .args = &.{"@P0"} },
    .{ .name = "rename", .args = &.{ "@P0", "@P1" } },
    .{ .name = "renameat", .args = &.{ "@D0", "@P0", "@D1", "@P1" } },
    .{ .name = "renameat2", .args = &.{ "@D0", "@P0", "@D1", "@P1", "0" } },
    .{ .name = "link", .args = &.{ "@P0", "@P1" } },
    .{ .name = "linkat", .args = &.{ "@D0", "@P0", "@D1", "@P1", "0" } },
    .{ .name = "symlink", .args = &.{ "\"t\"", "@P0" } },
    .{ .name = "symlinkat", .args = &.{ "\"t\"", "@D0", "@P0" } },
    .{ .name = "truncate", .args = &.{ "@P0", "0" } },
    .{ .name = "chmod", .args = &.{ "@P0", "0644" } },
    .{ .name = "fchmodat", .args = &.{ "@D0", "@P0", "0644" } },
    .{ .name = "fchmodat2", .args = &.{ "@D0", "@P0", "0644", "0" } },
    .{ .name = "chown", .args = &.{ "@P0", "1000", "1000" } },
    .{ .name = "lchown", .args = &.{ "@P0", "1000", "1000" } },
    .{ .name = "fchownat", .args = &.{ "@D0", "@P0", "1000", "1000", "0" } },
    .{ .name = "utime", .args = &.{ "@P0", "NULL" } },
    .{ .name = "utimes", .args = &.{ "@P0", "NULL" } },
    .{ .name = "futimesat", .args = &.{ "@D0", "@P0", "NULL" } },
    .{ .name = "utimensat", .args = &.{ "@D0", "@P0", "NULL", "0" } },
    .{ .name = "setxattr", .args = &.{ "@P0", "\"user.k\"", "\"1\"", "1", "0" } },
    .{ .name = "lsetxattr", .args = &.{ "@P0", "\"user.k\"", "\"1\"", "1", "0" } },
    .{ .name = "removexattr", .args = &.{ "@P0", "\"user.k\"" } },
    .{ .name = "lremovexattr", .args = &.{ "@P0", "\"user.k\"" } },
    .{ .name = "setxattrat", .args = &.{ "@D0", "@P0", "0", "\"user.k\"", "{value=\"1\", size=1, flags=0}", "16" } },
    .{ .name = "removexattrat", .args = &.{ "@D0", "@P0", "0", "\"user.k\"" } },
    .{ .name = "getxattr", .args = &.{ "@P0", "\"user.k\"", "NULL", "0" }, .result = " = 1" },
    .{ .name = "lgetxattr", .args = &.{ "@P0", "\"user.k\"", "NULL", "0" }, .result = " = 1" },
    .{ .name = "listxattr", .args = &.{ "@P0", "NULL", "0" }, .result = " = 7" },
    .{ .name = "llistxattr", .args = &.{ "@P0", "NULL", "0" }, .result = " = 7" },
    .{ .name = "stat", .args = &.{ "@P0", "{st_mode=S_IFREG|0644, st_size=2, ...}" } },
    .{ .name = "lstat", .args = &.{ "@P0", "{st_mode=S_IFREG|0644, st_size=2, ...}" } },
    .{ .name = "newfstatat", .args = &.{ "@D0", "@P0", "{st_mode=S_IFREG|0644, st_size=2, ...}", "0" } },
    .{ .name = "statx", .args = &.{ "@D0", "@P0", "AT_STATX_SYNC_AS_STAT", "STATX_ALL", "{stx_mask=STATX_ALL, ...}" } },
    .{ .name = "statfs", .args = &.{ "@P0", "{f_type=EXT2_SUPER_MAGIC, ...}" } },
    .{ .name = "access", .args = &.{ "@P0", "F_OK" } },
    .{ .name = "faccessat", .args = &.{ "@D0", "@P0", "F_OK" } },
    .{ .name = "faccessat2", .args = &.{ "@D0", "@P0", "F_OK", "0" } },
    .{ .name = "readlink", .args = &.{ "@P0", "\"t\"", "4096" }, .result = " = 1" },
    .{ .name = "readlinkat", .args = &.{ "@D0", "@P0", "\"t\"", "4096" }, .result = " = 1" },
    .{ .name = "inotify_add_watch", .args = &.{ "4<anon_inode:inotify>", "@P0", "IN_MODIFY" }, .result = " = 1" },
    .{ .name = "fanotify_mark", .args = &.{ "4<anon_inode:[fanotify]>", "FAN_MARK_ADD", "FAN_MODIFY", "@D0", "@P0" } },
    .{ .name = "name_to_handle_at", .args = &.{ "@D0", "@P0", "{handle_bytes=128 => 8, handle_type=1, f_handle=0x0102030405060708}", "[42]", "0" } },
    .{ .name = "acct", .args = &.{"@P0"} },
    .{ .name = "chroot", .args = &.{"@P0"} },
    .{ .name = "uselib", .args = &.{"@P0"} },
    .{ .name = "mount", .args = &.{ "\"none\"", "@P0", "\"tmpfs\"", "0", "NULL" } },
    .{ .name = "umount2", .args = &.{ "@P0", "0" } },
    .{ .name = "pivot_root", .args = &.{ "@P0", "@P1" } },
    .{ .name = "move_mount", .args = &.{ "@D0", "@P0", "@D1", "@P1", "0" } },
    .{ .name = "mount_setattr", .args = &.{ "@D0", "@P0", "0", "{attr_set=MOUNT_ATTR_RDONLY, attr_clr=0, propagation=0, userns_fd=0}", "32" } },
    .{ .name = "fspick", .args = &.{ "@D0", "@P0", "FSPICK_CLOEXEC" }, .result = " = 3" },
    .{ .name = "swapon", .args = &.{ "@P0", "0" } },
    .{ .name = "swapoff", .args = &.{"@P0"} },
};

fn spelledCall(name: []const u8) ?SpelledCall {
    for (spelled_calls) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

fn spelledPosition(c: SpelledCall, token: []const u8) ?usize {
    for (c.args, 0..) |a, i| if (std.mem.eql(u8, a, token)) return i;
    return null;
}

const SpellingSlot = struct { dirfd: []const u8, path: []const u8, suffix: []const u8 };
const spelling_slots = [2]SpellingSlot{
    .{ .dirfd = "@D0", .path = "@P0", .suffix = "" },
    .{ .dirfd = "@D1", .path = "@P1", .suffix = "2" },
};

fn isUnspelled(name: []const u8) bool {
    for (unspelled_file_calls) |u| if (std.mem.eql(u8, u.name, name)) return true;
    return false;
}

fn isStraceFileCall(name: []const u8) bool {
    for (strace_file_class) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

test "every call strace prints a path for is spelled below, or says why it is not" {
    for (strace_file_class) |name| {
        const spelled = spelledCall(name) != null;
        const unspelled = isUnspelled(name);
        if (spelled == unspelled) {
            std.debug.print("{s}: spelled={}, unspelled={}\n", .{ name, spelled, unspelled });
            return error.TestUnexpectedResult;
        }
    }
    for (unspelled_file_calls) |u| try std.testing.expect(isStraceFileCall(u.name));
}

test "the reader's path tables name the argument strace prints the path in" {
    var checked: usize = 0;
    for (path_syscalls ++ metadata_path_syscalls ++ unclassified_path_syscalls) |spec| {
        const c = spelledCall(spec.name) orelse {
            std.debug.print("{s} is in a path table and spelled nowhere\n", .{spec.name});
            return error.TestUnexpectedResult;
        };
        for (spec.args, spelling_slots[0..spec.args.len], 0..) |arg, slot, i| {
            std.testing.expectEqual(spelledPosition(c, slot.path), arg.path) catch |e| {
                std.debug.print("{s}: path {d}\n", .{ spec.name, i });
                return e;
            };
            std.testing.expectEqual(spelledPosition(c, slot.dirfd), arg.dirfd) catch |e| {
                std.debug.print("{s}: dirfd {d}\n", .{ spec.name, i });
                return e;
            };
        }
        checked += 1;
    }
    try std.testing.expect(checked > 20);
}

const SpellingPrefix = struct { raw: []const u8, quoted: []const u8, annotated: []const u8 };
// Not produced by an escaper here: a second implementation of strace's escaping would read its own
// mistakes as the reader's.
const spelling_prefixes = [_]SpellingPrefix{
    .{ .raw = "/tmp/p", .quoted = "/tmp/p", .annotated = "/tmp/p" },
    .{ .raw = "/tmp/\xe3\x83\x87", .quoted = "/tmp/\\343\\203\\207", .annotated = "/tmp/\\343\\203\\207" },
    .{ .raw = "/tmp/a\"b<c>", .quoted = "/tmp/a\\\"b<c>", .annotated = "/tmp/a\\\"b\\74c\\76" },
    .{ .raw = "/tmp/a\\b", .quoted = "/tmp/a\\\\b", .annotated = "/tmp/a\\\\b" },
    .{ .raw = "/tmp/a\x0bb", .quoted = "/tmp/a\\vb", .annotated = "/tmp/a\\vb" },
    .{ .raw = "/tmp/a[b", .quoted = "/tmp/a[b", .annotated = "/tmp/a[b" },
    .{ .raw = "/tmp/a{b", .quoted = "/tmp/a{b", .annotated = "/tmp/a{b" },
};

const SpellingPlace = struct { what: []const u8, base: []const u8, rel: []const u8, target: []const u8, outside: bool };
const spelling_places = [_]SpellingPlace{
    .{ .what = "from the state's parent", .base = "", .rel = "s/k", .target = "/s/k", .outside = false },
    .{ .what = "from the state", .base = "/s", .rel = "k", .target = "/s/k", .outside = false },
    .{ .what = "from inside the state", .base = "/s/d", .rel = "k", .target = "/s/d/k", .outside = false },
    .{ .what = "out of the state by ..", .base = "/s", .rel = "../x", .target = "/x", .outside = true },
    .{ .what = "beside the state", .base = "", .rel = "o/k", .target = "/o/k", .outside = true },
};

const Spelling = enum { absolute, cwd, dirfd, fchdir, first_absolute, second_absolute };

const SpelledRun = struct {
    unsupported: ?[]const u8,
    classes: []const contract.OpClass,
    metadata: []const []const u8,
    mutations: usize,

    fn counted(self: SpelledRun) bool {
        return self.unsupported != null or self.classes.len > 0 or self.metadata.len > 0 or self.mutations > 0;
    }

    fn same(a: SpelledRun, b: SpelledRun) bool {
        if (!std.mem.eql(u8, a.unsupported orelse "", b.unsupported orelse "")) return false;
        if (!std.mem.eql(contract.OpClass, a.classes, b.classes)) return false;
        if (a.metadata.len != b.metadata.len) return false;
        for (a.metadata, b.metadata) |x, y| if (!std.mem.eql(u8, x, y)) return false;
        return a.mutations == b.mutations;
    }
};

fn spelledText(a: std.mem.Allocator, c: SpelledCall, pre: SpellingPrefix, at: SpellingPlace, how: Spelling, child: bool) ![]const u8 {
    const who = if (child) "4242  " else "42    ";
    const base_annot = try std.mem.concat(a, u8, &.{ pre.annotated, at.base });
    const base_quoted = try std.mem.concat(a, u8, &.{ pre.quoted, at.base });
    var lines: std.ArrayList(u8) = .empty;
    try lines.appendSlice(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n");
    if (child) try lines.appendSlice(a, "42    clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242\n");
    switch (how) {
        .absolute, .dirfd => {},
        .cwd, .first_absolute, .second_absolute => try lines.print(a, "{s}chdir(\"{s}\") = 0\n", .{ who, base_quoted }),
        .fchdir => try lines.print(a, "{s}fchdir(5<{s}>) = 0\n", .{ who, base_annot }),
    }
    const dir = try std.mem.concat(a, u8, &.{ if (how == .dirfd) "5<" else "AT_FDCWD<", base_annot, ">" });
    var args: std.ArrayList([]const u8) = .empty;
    for (c.args) |arg| {
        var out = arg;
        for (spelling_slots, 0..) |slot, i| {
            const absolute = switch (how) {
                .absolute => true,
                .first_absolute => i == 0,
                .second_absolute => i == 1,
                else => false,
            };
            if (std.mem.eql(u8, arg, slot.dirfd)) out = if (absolute) "AT_FDCWD</work>" else dir;
            if (std.mem.eql(u8, arg, slot.path)) out = if (absolute)
                try std.mem.concat(a, u8, &.{ "\"", pre.quoted, at.target, slot.suffix, "\"" })
            else
                try std.mem.concat(a, u8, &.{ "\"", at.rel, slot.suffix, "\"" });
        }
        try args.append(a, out);
    }
    const result = try std.mem.replaceOwned(u8, a, c.result, "@A0", try std.mem.concat(a, u8, &.{ pre.annotated, at.target }));
    try lines.print(a, "{s}{s}({s}){s}\n", .{ who, c.name, try std.mem.join(a, ", ", args.items), result });
    return lines.items;
}

fn spelledRun(a: std.mem.Allocator, text: []const u8, state: []const u8) !SpelledRun {
    const p = try parse(a, text, state, "", "/work");
    return .{ .unsupported = p.unsupported, .classes = p.classes.items, .metadata = p.metadata_observed.items, .mutations = p.mutations.items.len };
}

test "a call is judged the same however strace spells its path: absolute, from the cwd, from a descriptor, escaped" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var mismatches: usize = 0;
    var compared: usize = 0;
    for (spelled_calls) |c| {
        const at_form = spelledPosition(c, spelling_slots[0].dirfd) != null;
        const two_paths = spelledPosition(c, spelling_slots[1].path) != null;
        for (spelling_prefixes) |pre| for (spelling_places) |place| for ([_]bool{ false, true }) |child| {
            const state = try std.mem.concat(a, u8, &.{ pre.raw, "/s" });
            const reference = try spelledRun(a, try spelledText(a, c, pre, place, .absolute, child), state);
            if (!child and place.outside and reference.counted()) {
                mismatches += 1;
                std.debug.print("counted outside the state: {s}, prefix {s}, {s}: {?s}/{any}/{d}md/{d}m\n", .{
                    c.name, pre.quoted, place.what, reference.unsupported, reference.classes, reference.metadata.len, reference.mutations,
                });
            }
            for ([_]Spelling{ .cwd, .dirfd, .fchdir, .first_absolute, .second_absolute }) |how| {
                if (how == .dirfd and !at_form) continue;
                if ((how == .first_absolute or how == .second_absolute) and !two_paths) continue;
                const run = try spelledRun(a, try spelledText(a, c, pre, place, how, child), state);
                compared += 1;
                // Not held to equality: a child's cwd is not followed, so its relative path that names
                // no descriptor is counted wherever it points.
                const agrees = if (child and !at_form)
                    (!reference.counted() or run.counted())
                else
                    SpelledRun.same(reference, run);
                if (!agrees) {
                    mismatches += 1;
                    std.debug.print("spelling mismatch: {s} {s}, prefix {s}, {s}, {s}: absolute {?s}/{any}/{d}md/{d}m, this {?s}/{any}/{d}md/{d}m\n", .{
                        c.name,                @tagName(how),     pre.quoted,             place.what,          if (child) "child" else "subject",
                        reference.unsupported, reference.classes, reference.metadata.len, reference.mutations, run.unsupported,
                        run.classes,           run.metadata.len,  run.mutations,
                    });
                }
            }
        };
    }
    try std.testing.expect(compared > 1000);
    std.testing.expectEqual(@as(usize, 0), mismatches) catch |e| {
        std.debug.print("{d} of {d} spellings judged differently from the absolute one\n", .{ mismatches, compared });
        return e;
    };
}

test "a call that names its descriptor with an empty or NULL path is placed where the descriptor points, and one whose path strace could not read is refused" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const Case = struct { lines: []const u8, refused: ?[]const u8 };
    const cases = [_]Case{
        .{ .refused = "name_to_handle_at", .lines = "42    name_to_handle_at(5</tmp/s/k>, \"\", {handle_bytes=128 => 8, handle_type=1, f_handle=0x01}, [42], AT_EMPTY_PATH) = 0\n" },
        .{ .refused = null, .lines = "42    name_to_handle_at(5</work/k>, \"\", {handle_bytes=128 => 8, handle_type=1, f_handle=0x01}, [42], AT_EMPTY_PATH) = 0\n" },
        .{ .refused = "fanotify_mark", .lines = "42    fanotify_mark(4<anon_inode:[fanotify]>, FAN_MARK_ADD, FAN_MODIFY, 5</tmp/s>, NULL) = 0\n" },
        .{ .refused = null, .lines = "42    fanotify_mark(4<anon_inode:[fanotify]>, FAN_MARK_ADD, FAN_MODIFY, 5</work>, NULL) = 0\n" },
        .{ .refused = "open_tree", .lines = "42    open_tree(5</tmp/s>, \"\", AT_EMPTY_PATH|OPEN_TREE_CLONE) = 3\n" },
        .{ .refused = null, .lines = "42    open_tree(5</work>, \"\", AT_EMPTY_PATH|OPEN_TREE_CLONE) = 3\n" },
        .{ .refused = "mknod", .lines = "42    mknod(0x7ffd12345678, S_IFREG|0644) = 0\n" },
        .{ .refused = "mknodat", .lines = "42    mknodat(5</work>, 0x7ffd12345678, S_IFREG|0644) = 0\n" },
    };
    for (cases) |c| {
        const text = try std.fmt.allocPrint(a, "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n{s}", .{c.lines});
        const p = try parse(a, text, "/tmp/s", "", "/work");
        std.testing.expectEqualStrings(c.refused orelse "(none)", p.unsupported orelse "(none)") catch |e| {
            std.debug.print("case: {s}", .{c.lines});
            return e;
        };
    }
}

test "a bind or move mount whose source is inside the state is refused however it is spelled, and one naming a file system is not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const header = "42    execve(\"/work/toy\", [\"toy\"], 0x7ff) = 0\n";
    const bind = try parse(a, header ++ "42    mount(\"/tmp/s/x\", \"/mnt\", NULL, MS_BIND, NULL) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mount", bind.unsupported orelse "(none)");
    const tmpfs = try parse(a, header ++ "42    chdir(\"/tmp/s\") = 0\n42    mount(\"none\", \"/mnt\", \"tmpfs\", 0, NULL) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("(none)", tmpfs.unsupported orelse "(none)");
    const relative_bind = try parse(a, header ++ "42    chdir(\"/tmp\") = 0\n42    mount(\"s/x\", \"/mnt\", NULL, MS_BIND, NULL) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mount", relative_bind.unsupported orelse "(none)");
    const relative_move = try parse(a, header ++ "42    chdir(\"/tmp/s\") = 0\n42    mount(\"x\", \"/mnt\", NULL, MS_MOVE, NULL) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("mount", relative_move.unsupported orelse "(none)");
    const bind_elsewhere = try parse(a, header ++ "42    chdir(\"/tmp\") = 0\n42    mount(\"o/x\", \"/mnt\", NULL, MS_BIND, NULL) = 0\n", "/tmp/s", "", "/work");
    try std.testing.expectEqualStrings("(none)", bind_elsewhere.unsupported orelse "(none)");
}
