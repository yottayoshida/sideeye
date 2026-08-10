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

/// Syscalls that read but never change anything. They are not operations sideeye can
/// crash between in any meaningful sense, and counting them would make the two views
/// disagree for no reason.
const read_only = [_][]const u8{
    "stat",   "lstat",     "fstat",   "newfstatat", "statx",
    "access", "faccessat", "readlink", "readlinkat", "read",
    "pread64", "readv",    "lseek",   "getdents64", "fcntl",
    "fadvise64", "statfs",  "fstatfs", "dup",       "dup2",
    "dup3",   "ioctl",     "mmap",    "munmap",     "mprotect",
};

/// Syscalls that leave the single-process, single-thread region v0.1 can reason about.
///
/// The shim interposes the libc wrappers for these, but `clone`, `clone3` and a raw
/// `syscall(SYS_clone, …)` go straight past it. Without the oracle watching for them,
/// a target whose *child* touches the state directory while the parent performs
/// ordinary operations passes every structural detector: something was mutated, so
/// `state_changed_without_ops` stays quiet, and the parent's own trace looks complete.
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

pub const Parsed = struct {
    classes: std.ArrayList(contract.OpClass),
    unsupported: ?[]const u8 = null,
    /// A process- or thread-creating syscall, named. Unlike the shim's boundary
    /// detectors this also catches the raw forms the shim cannot see.
    boundary: ?[]const u8 = null,
    /// How many lines were examined. Reported so that "no mismatches" can be told
    /// apart from "the oracle file was empty and nothing was compared".
    lines_seen: usize = 0,
    lines_in_scope: usize = 0,
};

pub fn parse(arena: std.mem.Allocator, text: []const u8, state_dir: []const u8) !Parsed {
    var out: Parsed = .{ .classes = .empty };
    var execs: usize = 0;

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        out.lines_seen += 1;

        const name = syscallName(line) orelse continue;

        // Checked before the state-directory filter: creating a process is out of
        // bounds regardless of which files it goes on to touch, and the child's own
        // operations may never mention the directory in the parent's view at all.
        if (isProcessSyscall(name)) {
            // The very first execve is strace starting the target. Counting it would
            // report every single run as having created a child process — the
            // measuring apparatus flagging its own act of measuring.
            if (std.mem.eql(u8, name, "execve") or std.mem.eql(u8, name, "execveat")) {
                execs += 1;
                if (execs == 1) continue;
            }
            if (out.boundary == null) out.boundary = try arena.dupe(u8, name);
            continue;
        }

        if (!touchesStateDir(line, state_dir)) continue;
        out.lines_in_scope += 1;

        if (isReadOnly(name)) continue;
        if (classify(name)) |cls| {
            const actual: contract.OpClass = if (cls == .unlink and
                std.mem.eql(u8, name, "unlinkat") and unlinkatRemovesDir(line)) .rmdir else cls;
            try out.classes.append(arena, actual);
        } else if (out.unsupported == null) {
            out.unsupported = try arena.dupe(u8, name);
        }
    }
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
    const expected = [_]contract.OpClass{ .open, .write, .fsync, .close, .unlink, .rename };
    try std.testing.expectEqualSlices(contract.OpClass, &expected, p.classes.items);
    // The loader's own openat is outside the state directory and must not be counted.
    try std.testing.expectEqual(@as(usize, 6), p.lines_in_scope);
    try std.testing.expectEqual(@as(?[]const u8, null), p.unsupported);
}

test "unlinkat with AT_REMOVEDIR is a directory removal, matching the shim" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    // aarch64 Linux has no rmdir syscall; glibc's rmdir(3) becomes this. The shim
    // records .rmdir because it interposes the libc entry point, so a name-only mapping
    // here would disagree and blame a correct target.
    const text =
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
    const text = "copy_file_range(3</tmp/s/a>, NULL, 4</tmp/s/b>, NULL, 6, 0) = 6\n";
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqualStrings("copy_file_range", p.unsupported.?);
}

test "read-only syscalls do not enter the comparison" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const text =
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

test "process-creating syscalls are caught even outside the state directory" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // The child's work never mentions the parent's state directory here, and the parent
    // performs a perfectly ordinary write. Without the process check this parses as one
    // clean operation and nothing else.
    const text =
        \\openat(AT_FDCWD, "/tmp/s/key.json", O_WRONLY|O_CREAT, 0644) = 3</tmp/s/key.json>
        \\clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 4242
        \\[pid  4242] write(5</elsewhere/f>, "x", 1) = 1
        \\
    ;
    const p = try parse(arena_state.allocator(), text, "/tmp/s");
    try std.testing.expectEqualStrings("clone", p.boundary.?);
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

test "a second execve is the target replacing itself, and counts" {
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

test "a raw clone3 is caught the same way" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const p = try parse(arena_state.allocator(), "clone3({flags=0}, 88) = 777\n", "/tmp/s");
    try std.testing.expectEqualStrings("clone3", p.boundary.?);
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
