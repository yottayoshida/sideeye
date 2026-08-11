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
    .{ .name = "close", .class = .close },
};

/// Syscalls that read but never change anything on disk. They are not operations
/// sideeye can crash between in any meaningful sense, and counting them would make the
/// two views disagree for no reason.
///
/// `flock` belongs here even though it is not a read: advisory locks live in the kernel
/// and die with the process, so no crash world can be told apart by one. Found by
/// measurement — the first real target to clear the boundary gate (omamori) stopped
/// here instead, on the lock it takes around its audit log.
const read_only = [_][]const u8{
    "stat",   "lstat",     "fstat",   "newfstatat", "statx",
    "access", "faccessat", "readlink", "readlinkat", "read",
    "pread64", "readv",    "lseek",   "getdents64", "fcntl",
    "fadvise64", "statfs",  "fstatfs", "dup",       "dup2",
    "dup3",   "ioctl",     "mmap",    "munmap",     "mprotect",
    "flock",
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
fn touchesStateDir(line: []const u8, state_dir: []const u8) bool {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const open_ch = line[i];
        if (open_ch != '"' and open_ch != '<') continue;
        const close_ch: u8 = if (open_ch == '"') '"' else '>';
        const rest = line[i + 1 ..];
        const end = std.mem.indexOfScalar(u8, rest, close_ch) orelse break;
        const candidate = rest[0..end];
        if (candidate.len > 0 and candidate[0] == '/' and
            contract.isInsideDir(candidate, state_dir)) return true;
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
    return null;
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

pub const Parsed = struct {
    /// The subject's state-directory operation classes, in order.
    classes: std.ArrayList(contract.OpClass),
    /// A state-directory syscall by the subject that v0.1 does not model.
    unsupported: ?[]const u8 = null,
    /// A syscall that stays a hard refusal whoever tolerates what: the subject
    /// replacing its own image, or namespace surgery.
    boundary: ?[]const u8 = null,
    /// A process other than the subject performed a non-read-only operation on the
    /// state directory. This is the condition that decides tolerance, and the oracle is
    /// the only observer that sees it whether or not the child loaded the shim.
    child_touched: bool = false,
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
};

pub fn parse(arena: std.mem.Allocator, text: []const u8, state_dir: []const u8) !Parsed {
    var out: Parsed = .{ .classes = .empty };
    var child_pids: std.ArrayList(u32) = .empty;
    var launched = false;

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        out.lines_seen += 1;

        const pid = pidOf(line);
        const name = syscallName(line) orelse continue;

        // The first execve is strace starting the target: it names the subject.
        // Everything before knowing the subject is the measuring apparatus itself.
        if (!launched) {
            if (std.mem.eql(u8, name, "execve") or std.mem.eql(u8, name, "execveat")) {
                launched = true;
                out.primary_pid = pid;
            }
            continue;
        }

        const is_primary = pid == null or out.primary_pid == null or pid.? == out.primary_pid.?;
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
            // A second execve by the *subject* replaces the image the crash points were
            // read from; a child's execve is just a child becoming what it spawns.
            // unshare is refused from anyone — this tool does not model namespaces.
            // And a clone that carries CLONE_THREAD is not a child at all: it is a
            // thread reached through a raw syscall, past the pthread_create wrapper,
            // and threads are refused for the determinism of the subject itself.
            const is_exec = std.mem.eql(u8, name, "execve") or std.mem.eql(u8, name, "execveat");
            // Whole-line search is fine *here*, unlike the flag checks below: clone's
            // arguments carry no target-chosen strings for a false CLONE_THREAD to
            // hide in, and clone3 prints its flags inside a struct at no fixed index.
            const is_raw_thread = std.mem.startsWith(u8, name, "clone") and
                std.mem.indexOf(u8, line, "CLONE_THREAD") != null;
            if ((is_exec and is_primary) or is_raw_thread or std.mem.eql(u8, name, "unshare")) {
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

        if (!touchesStateDir(line, state_dir)) continue;

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
            // syscall nobody recognises, is a child touching what only the subject may.
            // An open counts as a read when it neither writes nor creates, and a close
            // of an inherited descriptor changes no persistent state (ADR 0003).
            if (is_shared_write_map) {
                out.child_touched = true;
            } else if (std.mem.eql(u8, name, "close") or isReadOnlyOpen(name, line)) {
                // tolerated
            } else if (!isReadOnly(name)) {
                out.child_touched = true;
            }
            continue;
        }
        out.lines_in_scope += 1;

        if (is_shared_write_map) {
            if (out.unsupported == null)
                out.unsupported = try arena.dupe(u8, "mmap(PROT_WRITE|MAP_SHARED)");
            continue;
        }
        if (isReadOnly(name)) continue;
        if (classify(name)) |cls| {
            // Neither of these enters the comparison (ADR 0003). A write-incapable open
            // is not an observed operation on either side; close stays recorded by the
            // shim but cannot be paired across views the shim never saw born.
            if (cls == .close) continue;
            if (cls == .open and isReadOnlyOpen(name, line)) continue;
            const actual: contract.OpClass = if (cls == .unlink and
                std.mem.eql(u8, name, "unlinkat") and unlinkatRemovesDir(line)) .rmdir else cls;
            try out.classes.append(arena, actual);
        } else if (out.unsupported == null) {
            out.unsupported = try arena.dupe(u8, name);
        }
    }
    out.children = child_pids.items.len;
    return out;
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
    try std.testing.expect(touchesStateDir("write(3</tmp/state/key.json>, ...) = 6", "/tmp/state"));
    try std.testing.expect(touchesStateDir("openat(AT_FDCWD</work>, \"/tmp/state/k\", 0) = 3", "/tmp/state"));
    // the case a naive substring search gets wrong
    try std.testing.expect(!touchesStateDir("write(3</tmp/state2/key.json>, ...) = 6", "/tmp/state"));
    try std.testing.expect(!touchesStateDir("openat(AT_FDCWD</work>, \"/etc/passwd\", 0) = 3", "/tmp/state"));
}

test "syscall names are read from the start of the line" {
    try std.testing.expectEqualStrings("openat", syscallName("openat(AT_FDCWD, \"x\") = 3").?);
    try std.testing.expectEqualStrings("pwrite64", syscallName("pwrite64(3, \"x\", 1, 0) = 1").?);
    try std.testing.expectEqual(@as(?[]const u8, null), syscallName("--- SIGKILL ---"));
    try std.testing.expectEqual(@as(?[]const u8, null), syscallName("+++ killed by SIGKILL +++"));
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
    const p = try parse(arena_state.allocator(), text, "/tmp/o/state");
    // close is recorded by the shim but excluded from the comparison (ADR 0003).
    const expected = [_]contract.OpClass{ .open, .write, .fsync, .unlink, .rename };
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);
    // The loader's own openat is outside the state directory and must not be counted;
    // the close is still *examined* (in scope), just not compared.
    try std.testing.expectEqual(@as(usize, 6), p.lines_in_scope);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
    try std.testing.expect(!p.child_touched);
    try std.testing.expectEqual(@as(usize, 0), p.children);
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
    const p = try parse(arena_state.allocator(), symbolic, "/tmp/s");
    const expected = [_]contract.OpClass{.open};
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);

    // Fail-closed: numeric flags are not read-only, they are unparsed. Counted as
    // before — if that miscounts, the run ends UNKNOWN, never PASS.
    const numeric =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", 0x241) = 3</tmp/s/key.json>
        \\
    ;
    const q = try parse(arena_state.allocator(), numeric, "/tmp/s");
    try std.testing.expectEqual(@as(usize, 1), q.classes.items.len);

    // O_RDONLY|O_CREAT creates but cannot write: a mutation, addressable, counted.
    const creating =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/marker", O_RDONLY|O_CREAT, 0644) = 3</tmp/s/marker>
        \\
    ;
    const r = try parse(arena_state.allocator(), creating, "/tmp/s");
    try std.testing.expectEqual(@as(usize, 1), r.classes.items.len);

    // creat spells no flags and always creates: counted.
    const via_creat =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    creat("/tmp/s/new.json", 0644) = 3</tmp/s/new.json>
        \\
    ;
    const s = try parse(arena_state.allocator(), via_creat, "/tmp/s");
    try std.testing.expectEqual(@as(usize, 1), s.classes.items.len);

    // openat2 carries its flags inside the how struct; the symbolic token is still there.
    const via_openat2 =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat2(AT_FDCWD, "/tmp/s/key.json", {flags=O_RDONLY|O_CLOEXEC, mode=0, resolve=0}, 24) = 3</tmp/s/key.json>
        \\
    ;
    const t = try parse(arena_state.allocator(), via_openat2, "/tmp/s");
    try std.testing.expectEqual(@as(usize, 0), t.classes.items.len);

    // An invalid access mode (both low bits set) is spelled `O_ACCMODE` by strace, and
    // the shim counts it (`!= O_RDONLY`). This side must agree — the invalid case must
    // not be the one place the two predicates split.
    const invalid_accmode =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    openat(AT_FDCWD, "/tmp/s/key.json", O_ACCMODE|O_CLOEXEC) = -1 EINVAL (Invalid argument)
        \\
    ;
    const u = try parse(arena_state.allocator(), invalid_accmode, "/tmp/s");
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
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
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\copy_file_range(3</tmp/s/a>, NULL, 4</tmp/s/b>, NULL, 6, 0) = 6
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqualStrings("copy_file_range", p.unsupported.?);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expect(!p.child_touched);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expect(p.child_touched);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expect(!p.child_touched);

    const unknown_sys =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  frobnicate(3</tmp/s/key.json>) = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), unknown_sys, "/tmp/s");
    try std.testing.expect(q.child_touched);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expectEqual(@as(usize, 1), p.classes.items.len);
}

test "a second execve is the target replacing itself, and stays refused" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
        \\execve("/work/toy", ["toy"], 0x7ff) = 0
        \\execve("/bin/sh", ["sh", "-c", "x"], 0x7ff) = 0
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqualStrings("execve", p.boundary.?);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqual(@as(?[]const u8, null), p.boundary);
    try std.testing.expectEqual(@as(usize, 1), p.children);
}

test "a raw clone carrying CLONE_THREAD is a thread, not a child" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // pthread_create is interposed; syscall(SYS_clone, CLONE_THREAD|…) is not. Without
    // this the raw form would be tolerated as a quiet child, and threads are refused
    // for the subject's own determinism, not for what they touch.
    const text =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    clone(child_stack=0x7f, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_THREAD|CLONE_SIGHAND) = 43
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expect(p.boundary != null);
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
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expect(p.boundary != null);

    // The subject's own setsid/setpgid lines are the shim's to judge — its wrapper
    // knows whether the call moved anything, and this parser does not.
    const own =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\42    setpgid(0, 0)                     = 0
        \\
    ;
    const q = try parse(arena_state.allocator(), own, "/tmp/s");
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
    const p = try parse(arena_state.allocator(), subject, "/tmp/s");
    try std.testing.expectEqualStrings("mmap(PROT_WRITE|MAP_SHARED)", p.unsupported.?);

    const child =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const q = try parse(arena_state.allocator(), child, "/tmp/s");
    try std.testing.expect(q.child_touched);

    // A private or read-only mapping changes nothing on disk and stays tolerated.
    const private =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE, 3</tmp/s/key.json>, 0) = 0x7f
        \\
    ;
    const r = try parse(arena_state.allocator(), private, "/tmp/s");
    try std.testing.expect(!r.child_touched);
}

test "a child's read-only open is a read, and its writing open is the touch" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const reading =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  openat(AT_FDCWD, "/tmp/s/key.json", O_RDONLY|O_CLOEXEC) = 3</tmp/s/key.json>
        \\
    ;
    const p = try parse(arena_state.allocator(), reading, "/tmp/s");
    try std.testing.expect(!p.child_touched);

    const writing =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\
    ;
    const q = try parse(arena_state.allocator(), writing, "/tmp/s");
    try std.testing.expect(q.child_touched);

    // creat never spells its flags, and it always creates.
    const creating =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  creat("/tmp/s/new.json", 0644) = 3</tmp/s/new.json>
        \\
    ;
    const r = try parse(arena_state.allocator(), creating, "/tmp/s");
    try std.testing.expect(r.child_touched);
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
    const p = try parse(arena_state.allocator(), read_with_scary_name, "/tmp/s");
    try std.testing.expect(!p.child_touched);

    const private_map_of_scary_name =
        \\42    execve("/work/toy", ["toy"], 0x7ff) = 0
        \\4242  mmap(NULL, 4096, PROT_READ, MAP_PRIVATE, 3</tmp/s/PROT_WRITE.MAP_SHARED.log>, 0) = 0x7f
        \\
    ;
    const q = try parse(arena_state.allocator(), private_map_of_scary_name, "/tmp/s");
    try std.testing.expect(!q.child_touched);
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

    // Divergence in the middle is reported at the position it happens.
    const swapped = [_]contract.OpClass{ .open, .unlink, .rename };
    const mid = compare(&a, &swapped).?;
    try std.testing.expectEqual(@as(usize, 1), mid.missed.index);
}
