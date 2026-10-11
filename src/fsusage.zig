const std = @import("std");
const contract = @import("contract");
const oracle = @import("oracle.zig");

pub const Defect = union(enum) {
    unparsed: []const u8,
    truncated: []const u8,
    unresolved_fd: []const u8,
    unknown_call: []const u8,
    unresolvable_path: []const u8,
    no_subject,
    missing_sentinel: []const u8,
};

pub const Reading = struct {
    parsed: oracle.Parsed,
    /// Non-null when the capture cannot be read as a complete account. The caller
    /// refuses; it never compares a defective reading.
    defect: ?Defect = null,
    subject_tid: ?[]const u8 = null,
};

const Line = struct {
    call: []const u8,
    middle: []const u8,
    tid: []const u8,
    raw: []const u8,
};

fn callOf(line: []const u8) ?struct { call: []const u8, call_start: usize, middle_start: usize } {
    if (line.len < 20) return null;
    if (line[2] != ':' or line[5] != ':' or line[8] != '.') return null;
    var i: usize = 9;
    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
    if (i == 9) return null;
    while (i < line.len and line[i] == ' ') i += 1;
    const call_start = i;
    while (i < line.len and line[i] != ' ') i += 1;
    if (i == call_start) return null;
    return .{ .call = line[call_start..i], .call_start = call_start, .middle_start = i };
}

fn parseLine(raw: []const u8) ?Line {
    const line = std.mem.trimEnd(u8, raw, " \t\r");
    const left = callOf(line) orelse return null;
    const call = left.call;
    const call_start = left.call_start;
    const i = left.middle_start;
    const right = tailOf(line) orelse return null;
    const middle_end = right.dur_start;
    if (middle_end <= call_start) return null;
    const middle = std.mem.trim(u8, line[i..middle_end], " \t");
    return .{ .call = call, .middle = middle, .tid = right.tid, .raw = raw };
}

fn tailOf(line: []const u8) ?struct { tid: []const u8, dur_start: usize } {
    // Process names carry dots of their own — `com.apple.Virtualization.Virtua.80341932`
    // and `com.netskope.client.Netskope-Cl.80202530` are both real lines from one
    // capture — so the split is the last dot, not the first, and it is taken inside the
    // final whitespace-separated field rather than across the whole line.
    const end = line.len;
    var field_start = end;
    while (field_start > 0 and line[field_start - 1] != ' ') field_start -= 1;
    if (field_start == end) return null;
    const last_field = line[field_start..end];
    const d_rel = std.mem.lastIndexOfScalar(u8, last_field, '.') orelse return null;
    const d = field_start + d_rel;
    if (d + 1 >= end) return null;
    const tid = line[d + 1 .. end];
    if (tid.len == 0) return null;
    for (tid) |c| if (!std.ascii.isDigit(c)) return null;

    // The process name may hold spaces (`Google Chrome He.64625821`), so back up over
    // words until one parses as a duration (`D.DDDDDD`). A `W` flag sits between them
    // on disk-io lines (`0.000221 W libc_toy.80342207`, measured).
    var dur_end: ?usize = null;
    var scan = field_start;
    while (scan > 0) {
        var w_end = scan;
        while (w_end > 0 and line[w_end - 1] == ' ') w_end -= 1;
        if (w_end == 0) break;
        var w_start = w_end;
        while (w_start > 0 and line[w_start - 1] != ' ') w_start -= 1;
        const word = line[w_start..w_end];
        if (isDuration(word)) {
            dur_end = w_start;
            break;
        }
        scan = w_start;
    }
    const dur_start = dur_end orelse return null;
    return .{ .tid = tid, .dur_start = dur_start };
}

fn isDuration(w: []const u8) bool {
    const dot = std.mem.indexOfScalar(u8, w, '.') orelse return false;
    if (dot == 0 or w.len - dot - 1 != 6) return false;
    for (w[0..dot]) |c| if (!std.ascii.isDigit(c)) return false;
    for (w[dot + 1 ..]) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// macOS 15.x pads a cut name with `>`, which is easy to spot. But the cut itself
/// happens on the LEFT, and the committed capture of the deep-path leg shows what that
/// leaves when there is no padding: `ted-component/nested-component/.../state/sentinel`
/// — a pathname with no leading slash, its root gone
/// (`spike/fsusage/captures/P3-deep.cap.txt`). fs_usage prints absolute paths, so a
/// path-shaped field that does not start with `/` is a stump.
///
/// The cap moves between builds (144, 153 and 156 measured on two machines), so
/// neither test is a length.
fn isTruncated(middle: []const u8) bool {
    const t = std.mem.trimEnd(u8, middle, " ");
    if (t.len >= 2 and t[t.len - 1] == '>' and t[t.len - 2] == '>') return true;
    var it = std.mem.tokenizeAny(u8, t, " ");
    while (it.next()) |tok| {
        if (std.mem.indexOfScalar(u8, tok, '/') == null) continue;
        if (tok[0] == '/') return false; // a whole path: the operand survived
        if (tok[0] == '(' or tok[0] == '[') continue; // an annotation that holds a slash
        return true;
    }
    return false;
}

/// `[ 22]` — the call failed. Needed for one thing: a failed `F_DUPFD` produced no
/// descriptor, and the shim's first attempt fails on purpose (it asks for 900 before
/// settling for 200, measured), so the mapping must wait for the one that succeeded.
fn hasErrno(middle: []const u8) bool {
    const lb = std.mem.indexOfScalar(u8, middle, '[') orelse return false;
    const rb = std.mem.indexOfScalarPos(u8, middle, lb, ']') orelse return false;
    const inner = std.mem.trim(u8, middle[lb + 1 .. rb], " ");
    if (inner.len == 0) return false;
    for (inner) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn fdOf(middle: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, middle, " \t");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "F=")) {
            const v = tok[2..];
            if (v.len == 0) return null;
            for (v) |c| if (!std.ascii.isDigit(c)) return null;
            return v;
        }
    }
    return null;
}

const at_fdcwd: i64 = -2;

/// with `/`. Directory-relative: `[N]` immediately followed by `/` and then the operand
/// — `[69]/libsideeye_shim.so` is relative to descriptor 69, and `[-2]//Users/x/f` is
/// `openat(AT_FDCWD, "/Users/x/f")`, the separator fs_usage inserts sitting in front of
/// an operand that is itself absolute. `mkstemp` on macOS opens through exactly that
const Operand = struct { dirfd: ?i64, text: []const u8 };

fn operandOf(middle: []const u8) ?Operand {
    var from: usize = 0;
    while (std.mem.indexOfScalarPos(u8, middle, from, '[')) |lb| {
        const rb = std.mem.indexOfScalarPos(u8, middle, lb, ']') orelse break;
        const inner = std.mem.trim(u8, middle[lb + 1 .. rb], " ");
        if (rb + 1 < middle.len and middle[rb + 1] == '/' and isSignedInt(inner)) {
            const dirfd = std.fmt.parseInt(i64, inner, 10) catch break;
            return .{ .dirfd = dirfd, .text = std.mem.trim(u8, middle[rb + 2 ..], " \t") };
        }
        from = rb + 1;
    }
    const slash = std.mem.indexOfScalar(u8, middle, '/') orelse return null;
    // A `/dev/...` in an annotation field is not the operand; annotations are
    // parenthesised or `KEY=value` shaped and never start the tail.
    if (slash > 0 and middle[slash - 1] != ' ') return null;
    return .{ .dirfd = null, .text = std.mem.trim(u8, middle[slash..], " \t") };
}

fn isSignedInt(t: []const u8) bool {
    if (t.len == 0) return false;
    const digits = if (t[0] == '-') t[1..] else t;
    if (digits.len == 0) return false;
    for (digits) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn joinPath(arena: std.mem.Allocator, dir: []const u8, rel: []const u8) ![]const u8 {
    const d = std.mem.trimEnd(u8, dir, "/");
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ d, rel });
}

fn pathOf(arena: std.mem.Allocator, middle: []const u8, cwd: []const u8) ?[]const u8 {
    const op = operandOf(middle) orelse return null;
    if (op.text.len != 0 and op.text[0] == '/') return op.text;
    if (op.dirfd) |d| {
        if (d == at_fdcwd and cwd.len != 0) return joinPath(arena, cwd, op.text) catch null;
    }
    return null;
}

fn canonicalCall(call: []const u8) []const u8 {
    const suffix = "_nocancel";
    if (std.mem.endsWith(u8, call, suffix)) return call[0 .. call.len - suffix.len];
    return call;
}

fn classOf(call_in: []const u8) ?contract.OpClass {
    const call = canonicalCall(call_in);
    const table = [_]struct { name: []const u8, class: contract.OpClass }{
        .{ .name = "open", .class = .open },
        .{ .name = "guarded_open_np", .class = .open },
        .{ .name = "guarded_open_dprotected_np", .class = .open },
        .{ .name = "guarded_write_np", .class = .write },
        .{ .name = "guarded_pwrite_np", .class = .write },
        .{ .name = "guarded_writev_np", .class = .write },
        .{ .name = "guarded_close_np", .class = .close },
        .{ .name = "openat", .class = .open },
        .{ .name = "open_dprotected", .class = .open },
        .{ .name = "write", .class = .write },
        .{ .name = "pwrite", .class = .write },
        .{ .name = "writev", .class = .write },
        .{ .name = "pwritev", .class = .write },
        .{ .name = "rename", .class = .rename },
        .{ .name = "renameat", .class = .rename },
        .{ .name = "renameatx_np", .class = .rename },
        .{ .name = "renamex_np", .class = .rename },
        .{ .name = "unlink", .class = .unlink },
        .{ .name = "unlinkat", .class = .unlink },
        .{ .name = "fsync", .class = .fsync },
        .{ .name = "fdatasync", .class = .fsync },
        .{ .name = "truncate", .class = .truncate },
        .{ .name = "ftruncate", .class = .truncate },
        .{ .name = "mkdir", .class = .mkdir },
        .{ .name = "mkdirat", .class = .mkdir },
        .{ .name = "rmdir", .class = .rmdir },
        .{ .name = "link", .class = .link },
        .{ .name = "linkat", .class = .link },
        .{ .name = "symlink", .class = .symlink },
        .{ .name = "symlinkat", .class = .symlink },
        .{ .name = "close", .class = .close },
    };
    for (table) |e| if (std.mem.eql(u8, call, e.name)) return e.class;
    return null;
}

/// The predicate has to mean the same thing on both sides of the comparison, and ADR
/// 0003 fixed it for the shim and for strace: write-capable iff the access mode is not
/// `O_RDONLY`, or `O_CREAT` or `O_TRUNC` is set. `fs_usage` spells the same flags as a
/// fixed-width bracket, measured against a real capture: position 1 is `R`, 2 is `W`,
/// 3 is `C` (create) and 5 is `T` (truncate) — `(_WC_T_______)` is the subject's
/// `O_WRONLY|O_CREAT|O_TRUNC`, `(R___________)` a plain read, `(RW__________)` both.
///
/// Fail-closed: a bracket this does not recognise counts as write-capable, so an
/// unfamiliar spelling widens what is compared rather than quietly dropping an
/// operation out of the account.
fn openIsWriteCapable(middle: []const u8) bool {
    const lp = std.mem.indexOfScalar(u8, middle, '(') orelse return true;
    const rp = std.mem.indexOfScalarPos(u8, middle, lp, ')') orelse return true;
    const flags = middle[lp + 1 .. rp];
    if (flags.len < 5) return true;
    if (flags[1] == 'W') return true;
    if (flags[2] == 'C') return true;
    if (flags[4] == 'T') return true;
    return flags[0] != 'R';
}

fn isMetadataCall(call_in: []const u8) bool {
    const call = canonicalCall(call_in);
    const names = [_][]const u8{
        "chmod",    "fchmod", "fchmodat", "chown",     "fchown",      "lchown",
        "fchownat", "utimes", "futimes",  "utimensat", "setattrlist", "chflags",
        "fchflags",
    };
    for (names) |n| if (std.mem.eql(u8, call, n)) return true;
    return false;
}

/// The core of the list is what real captures produced, measured against the state root
/// of an end-to-end run: `lstat64` and `getattrlist` dominate (Spotlight and fseventsd
/// walking a directory that just changed), with `listxattr`, `getxattr` and `access`
/// behind them, and the subject's own `fstat64`/`fcntl` bracketing pairs from the shim.
/// The rest is the read-only family filled in by hand — `read`, `pread`, `readv`,
/// `lseek`, `mmap`, `munmap`, `ioctl`, `select`, and since 2026-09-08 `getattrlistbulk`,
/// `getdirentriesattr`, `searchfs` and the un-suffixed `statfs`/`fstatfs`: the calls a
/// daemon walking a directory issues beside `getattrlist`, which is what a tail-less
/// line's CALL is tested against (see `read`). `mmap` is the one member that is not
/// strictly read-only — a shared writable mapping's writes leave no syscall line — and
/// this reader cannot tell a writable mapping from a read-only one. The shim can, and since
/// contract v19 it refuses a writable shared mapping of a state file, and `PROT_WRITE`
/// added later to a read-only one (#689, ADR 0098): through v18 the two witnesses were
/// symmetric here in seeing nothing, and a run storing through such a mapping passed.
fn isReadOnlyCall(call_in: []const u8) bool {
    const call = canonicalCall(call_in);
    const names = [_][]const u8{
        "stat64",     "stat",      "lstat64",         "lstat",           "fstat64",           "fstat",
        "fstatat64",  "fstatat",   "getattrlist",     "getattrlistat",   "fgetattrlist",      "listxattr",
        "flistxattr", "getxattr",  "fgetxattr",       "access",          "faccessat",         "readlink",
        "readlinkat", "fsgetpath", "getdirentries64", "getdirentries",   "opendir",           "readdir",
        "closedir",   "pathconf",  "fpathconf",       "statfs64",        "fstatfs64",         "getfsstat64",
        "read",       "pread",     "readv",           "lseek",           "mmap",              "munmap",
        "ioctl",      "select",    "exit",            "getattrlistbulk", "getdirentriesattr", "searchfs",
        "statfs",     "fstatfs",
    };
    for (names) |n| if (std.mem.eql(u8, call, n)) return true;
    return false;
}

/// `<SETLK>` and `<GETFD>`. Excluding the whole class would let `F_FULLFSYNC` — which
/// the shim does not record and which is a durability operation on the state — through
/// the unknown-call gate that exists to catch exactly that.
fn fcntlIsInert(middle: []const u8) bool {
    const inert = [_][]const u8{ "<GETPATH>", "<GETFL>", "<SETFL>", "<GETFD>", "<SETFD>", "<GETLK>" };
    for (inert) |n| if (std.mem.indexOf(u8, middle, n) != null) return true;
    return false;
}

fn fcntlDuplicates(middle: []const u8) bool {
    return std.mem.indexOf(u8, middle, "<DUPFD>") != null;
}

/// Disk-io lines, not syscalls. `fs_usage` reports the device traffic a syscall causes
/// on its own lines (`WrData[A]`, `RdData[…]`, `PgIn`), and `spike/fsusage/RESULTS.md`
/// records that a 4 MiB write is one syscall line and two `WrData` lines: counting them
/// as operations would double the account against the shim's, which sees syscalls only.
fn isDiskIo(call: []const u8) bool {
    const prefixes = [_][]const u8{ "WrData", "RdData", "WrMeta", "RdMeta", "PgIn", "PgOut", "CacheHit" };
    for (prefixes) |n| if (std.mem.startsWith(u8, call, n)) return true;
    return false;
}

const FdKey = struct { tid: []const u8, fd: []const u8 };

fn fdEql(a: FdKey, b: FdKey) bool {
    return std.mem.eql(u8, a.tid, b.tid) and std.mem.eql(u8, a.fd, b.fd);
}

/// Where an open descriptor points, per (tid, fd). `fs_usage` prints no path on a
/// write, so a write is placed through the open that preceded it on the same thread —
/// and a write with no such open is a hole, not a line to skip.
const FdTable = struct {
    keys: std.ArrayList(FdKey) = .empty,
    in_state: std.ArrayList(bool) = .empty,

    fn set(self: *FdTable, arena: std.mem.Allocator, key: FdKey, in_state: bool) !void {
        for (self.keys.items, 0..) |k, idx| {
            if (fdEql(k, key)) {
                self.in_state.items[idx] = in_state;
                return;
            }
        }
        try self.keys.append(arena, key);
        try self.in_state.append(arena, in_state);
    }

    fn get(self: *const FdTable, key: FdKey) ?bool {
        for (self.keys.items, 0..) |k, idx| {
            if (fdEql(k, key)) return self.in_state.items[idx];
        }
        return null;
    }

    fn clear(self: *FdTable, key: FdKey) void {
        for (self.keys.items, 0..) |k, idx| {
            if (fdEql(k, key)) {
                // Left in place with its mapping dropped: a later write on a reused
                // number must not inherit the old path, and must not resolve either.
                self.in_state.items[idx] = false;
                self.keys.items[idx] = .{ .tid = k.tid, .fd = "" };
                return;
            }
        }
    }
};

/// macOS firmlinks: the data volume is mounted at `/System/Volumes/Data` and grafted
/// into `/`, and `fs_usage` prints the physical path. So a state directory the caller
/// spelled `/Users/x/s` arrives as `/System/Volumes/Data/Users/x/s`. Measured on
/// macOS 15.3.1 — every line of a real capture under `$HOME` carries the prefix, which
/// is why the first version of this module scoped nothing at all.
const firmlink_prefix = "/System/Volumes/Data";

fn physical(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, firmlink_prefix)) {
        const rest = path[firmlink_prefix.len..];
        if (rest.len > 0 and rest[0] == '/') return rest;
    }
    return path;
}

fn mutatingTouch(ln: Line) bool {
    if (isMetadataCall(ln.call)) return true;
    const cls = classOf(ln.call) orelse return false;
    if (cls == .close) return false;
    if (cls == .open) return openIsWriteCapable(ln.middle);
    return true;
}

fn inState(path: []const u8, root: []const u8, alt: []const u8) bool {
    return underRoot(path, root) or underRoot(path, alt);
}

fn appendUnique(arena: std.mem.Allocator, list: *std.ArrayList([]const u8), s: []const u8) !void {
    for (list.items) |t| if (std.mem.eql(u8, t, s)) return;
    try list.append(arena, s);
}

fn underRoot(path_in: []const u8, root_in: []const u8) bool {
    const root = physical(root_in);
    const path = physical(path_in);
    if (root.len == 0) return false;
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (path.len == root.len) return true;
    return path[root.len] == '/';
}

/// Two spellings of one path, for the sentinel and trace-file comparisons that have to
/// be exact rather than prefix-based.
fn samePath(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, physical(a), physical(b));
}

/// spelling the reader uses? The handshake asks this rather than searching the text:
/// a raw substring match found an `fseventsd` line about the sentinel and let a run
/// proceed whose capture the reader could not scope at all (measured, first end-to-end
/// run). A gate looser than the check behind it is not a gate.
pub fn capturesPath(text: []const u8, path: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        const ln = parseLine(raw) orelse continue;
        const op = operandOf(ln.middle) orelse continue;
        const p = if (op.text.len != 0 and op.text[0] == '/') op.text else continue;
        if (samePath(p, path)) return true;
    }
    return false;
}

pub fn read(
    arena: std.mem.Allocator,
    text: []const u8,
    state_root: []const u8,
    state_alt: []const u8,
    trace_path: []const u8,
    sentinel_start: []const u8,
    sentinel_end: []const u8,
    cwd: []const u8,
    subject_thread_ids: []const u64,
    /// It does NOT make the thread the subject: a started thread that writes through raw
    /// syscalls stays another party's to this witness and refuses as it did.
    started_thread_ids: []const u64,
) !Reading {
    var out: Reading = .{ .parsed = .{ .classes = .empty, .names = .empty, .lines = .empty, .metadata_observed = .empty, .mutations = .empty, .reaps = .empty, .spawns = .empty, .subject_tids = .empty } };
    var fds: FdTable = .{};
    var dup_pending: std.ArrayList(FdKey) = .empty;
    var in_cut_event: bool = false;
    // Set once a relevant thread issues `chdir`/`fchdir`. This reader does not follow
    // the cwd — the strace reader does, through `initial_cwd` plus every successful
    // chdir it sees — so from that point an `AT_FDCWD`-relative operand can no longer
    // be placed by joining it to where the subject *started*, and refuses if it could
    // have changed state. Review constructed the false PASS this closes: cwd `/w`,
    // `chdir("/tmp")`, raw `openat(AT_FDCWD, "st/missed")` — really `/tmp/st/missed`,
    // in the judged directory — joined to `/w` and dropped as out of scope.
    var cwd_moved = false;
    var subject_tid: ?[]const u8 = null;
    var subject_ambiguous = false;
    var saw_start = false;
    var saw_end = false;
    var other_tids: std.ArrayList([]const u8) = .empty;
    // Collected over the whole capture before any of it is judged, because a thread's
    // first named touch can come after the line being decided.
    var state_tids: std.ArrayList([]const u8) = .empty;

    // Two passes rather than one because the subject's identity decides how later lines
    // are attributed, and the trace's first write is not necessarily the first line.
    var it0 = std.mem.splitScalar(u8, text, '\n');
    while (it0.next()) |raw| {
        if (raw.len == 0) continue;
        const ln = parseLine(raw) orelse continue;
        const path = pathOf(arena, ln.middle, cwd) orelse continue;
        // The subject is the thread that opened the trace FOR WRITING. Any line naming
        // the path was the first rule, and on a real capture the last such line was
        // `fseventsd`'s `lstat64` of the file — with a security agent's read-only
        // `open`s before it — so the daemon became the subject and every one of the
        // toy's writes was "a thread other than the subject". Only the shim opens the
        // trace to write; `O_WRONLY|O_CREAT|O_APPEND` printed `(_WCA_______X)` when this
        if (samePath(path, trace_path) and classOf(ln.call) == .open and openIsWriteCapable(ln.middle)) {
            if (subject_tid) |prev| {
                if (!std.mem.eql(u8, prev, ln.tid)) subject_ambiguous = true;
            } else subject_tid = ln.tid;
        }
        if (sentinel_start.len != 0 and samePath(path, sentinel_start)) saw_start = true;
        if (sentinel_end.len != 0 and samePath(path, sentinel_end)) saw_end = true;
        // A thread counts as having touched the judged directory only when it could have
        // changed it: a write-capable open, a mutating call, or a metadata write under
        // the root. A read-only open does not qualify — and that distinction is what a
        // real run refused on. Microsoft Defender (`wdavdaemon_enterprise`) had opened
        // the toy's file read-only to scan it, which made every later write it issued on
        // its own log descriptors "a hole in the account of the judged directory".
        if (inState(path, state_root, state_alt) and mutatingTouch(ln)) {
            try appendUnique(arena, &state_tids, ln.tid);
        }
    }

    if (sentinel_start.len != 0 and !saw_start) {
        out.defect = .{ .missing_sentinel = sentinel_start };
        return out;
    }
    if (sentinel_end.len != 0 and !saw_end) {
        out.defect = .{ .missing_sentinel = sentinel_end };
        return out;
    }
    const subject = subject_tid orelse {
        out.defect = .no_subject;
        return out;
    };
    if (subject_ambiguous) {
        out.defect = .no_subject;
        return out;
    }
    out.subject_tid = subject;

    var subject_tid_text: std.ArrayList([]const u8) = .empty;
    for (subject_thread_ids) |t| {
        try out.parsed.subject_tids.append(arena, t);
        const txt = try std.fmt.allocPrint(arena, "{d}", .{t});
        if (!std.mem.eql(u8, txt, subject)) try subject_tid_text.append(arena, txt);
    }
    var started_tid_text: std.ArrayList([]const u8) = .empty;
    for (started_thread_ids) |t| {
        const txt = try std.fmt.allocPrint(arena, "{d}", .{t});
        if (!std.mem.eql(u8, txt, subject)) try started_tid_text.append(arena, txt);
    }

    const relevant = struct {
        fn f(tid: []const u8, subj: []const u8, tids: []const []const u8) bool {
            if (std.mem.eql(u8, tid, subj)) return true;
            for (tids) |t| if (std.mem.eql(u8, t, tid)) return true;
            return false;
        }
    }.f;

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        if (std.mem.trim(u8, raw, " \t\r").len == 0) continue;
        out.parsed.lines_seen += 1;

        const ln = parseLine(raw) orelse {
            const line = std.mem.trimEnd(u8, raw, " \t\r");
            if (callOf(line) == null) {
                // No timestamp, no CALL: not an event. Inside a cut event — the line
                // above was a head this reader skipped, and its tail has not arrived —
                // this is a fragment of that event: the rest of the name, or the tail
                // itself (the duration and `proc.tid`), which ends the event (measured
                // 2026-09-08 on the CI runner: the head, then `133 LIBARCHIVE.xattr…=B
                // 0.000039 promotedcontentd.13451`; how many fragments a name makes is
                // not measured, so every one up to the tail is taken). Nothing is lost:
                // the head's CALL could not change state. Outside a cut event the same
                // shape is a hole — a fragment of nothing anyone skipped.
                if (in_cut_event) {
                    if (tailOf(line) != null) in_cut_event = false;
                    continue;
                }
                out.defect = .{ .unparsed = raw };
                return out;
            }
            // grammar fails lands here too. If the CALL — the field a cut cannot reach
            // — is one this module knows to read only, or a disk-io line, the line could
            // not have changed state whoever issued it and wherever, which is the reason
            // a parsed line of the same kind is skipped below; so it is not a hole.
            // Anything else still is: a mutating call nobody can be named for is exactly
            // what the account must not omit. A pending dup is untouched by the skip —
            // it is consumed only by a line of its own thread, and this line has none.
            if (callOf(line)) |left| {
                if (isReadOnlyCall(left.call) or isDiskIo(left.call)) {
                    in_cut_event = true;
                    continue;
                }
            }
            out.defect = .{ .unparsed = raw };
            return out;
        };
        in_cut_event = false;

        // recorded writing under the subject's pid. **The predicate, not just the account
        // branch** — it also decides whether a read-only directory open is remembered in
        // the fd table and whether a descriptor this thread opens is kept (`keep` below),
        // and a worker that writes both inside the judged directory and outside it (a log)
        // would otherwise lose the outside descriptor and refuse the run on a `write` it
        // could no longer place.
        const is_subject = std.mem.eql(u8, ln.tid, subject) or blk: {
            for (subject_tid_text.items) |t| {
                if (std.mem.eql(u8, ln.tid, t)) break :blk true;
            }
            break :blk false;
        };
        // Without this the shim's own trace descriptor — opened by the thread that
        // initialises, written by whichever thread recorded an operation — resolves
        // against nothing on a worker's line, and `fs_usage` prints no path on a write, so
        // the run refuses as a hole (#544). That line is not an incidental shape: a worker
        // reaches `subject_thread_ids` at all by having written a record, and writing a
        // record IS a write on that descriptor. The first version of this change widened
        // Within a process an fd number names one open file, so merging the namespace is
        // exact rather than approximate. A tid the trace does not name keeps its own —
        // nothing places it in the subject's process, and a system-wide capture holds
        // other processes using the same small numbers. A thread the shim saw START is in
        // the subject's process too (v18): it shares the namespace, so its own start record
        // — a `write` on the trace descriptor — resolves and is skipped below with the
        // rest of the observer's shadow; it is still not the subject for anything else.
        const is_started = is_subject or blk: {
            for (started_tid_text.items) |t| {
                if (std.mem.eql(u8, ln.tid, t)) break :blk true;
            }
            break :blk false;
        };
        const fd_tid = if (is_started) subject else ln.tid;
        const cls_opt = classOf(ln.call);
        // Widened with `is_subject` for the same reason that predicate was (#544), and it
        // is a different set: `state_tids` is built in the pass above from lines that NAME
        // a path under the root, and a worker's `write F=5` / `fsync F=5` name none — so a
        // thread on the list can be the subject and still not be "relevant". Everything
        // this gates is a refusal (`cwd_moved` on a `chdir`, `.truncated`,
        // `.unresolvable_path`, `.unresolved_fd`, a rename whose visible path is outside
        // the root), so leaving it narrow disables those guards for exactly the threads
        // this change newly admits. Review constructed the case: a worker writes through
        // the main thread's descriptor, then `chdir`s into the state, and a later relative
        // raw operand joins to the STARTING cwd and is dropped as out of scope while it
        // lands inside the judged directory. The verdict does not become a PASS — the
        // snapshot layer still refuses `state_changed_unaccounted` — but the guard ADR
        // 0031 §2b exists to be is off, and the refusal names another wall.
        // It is safe in this order and not the other: before the descriptor namespace was
        // merged above, a
        // worker's write to the shim's own trace descriptor was unresolvable, and this
        // would have turned that into a refusal on every run instead of a hole.
        const is_relevant = is_subject or relevant(ln.tid, subject, state_tids.items);
        const fd = fdOf(ln.middle);

        // Complete a pending dup — strictly. fs_usage prints the dup's source and never
        // its result, so the result has to be inferred, and "the next unknown descriptor
        // this thread touches" (the first rule) could hand a state descriptor the
        // out-of-scope bit of an unrelated source: a thread dups its log, then writes
        // on an inherited state descriptor, and that write is filed as the log's. The
        // rule is now the one measured shape and nothing wider: the very next line by
        // the same thread, an inert `fcntl` (`<SETFD>`, the CLOEXEC the shim sets on its
        // fresh descriptor) on a number the table does not know. Anything else by that
        // thread drops the pending dup, and the real target's later writes refuse as
        // unresolved — the fail-closed side. A line skipped above as tail-less and
        // read-only has no thread and neither completes nor drops anything: it cannot
        // be the inert `fcntl` (not in the read-only list), so no dup completes on it.
        {
            var i: usize = 0;
            while (i < dup_pending.items.len) {
                const d = dup_pending.items[i];
                // `ln.tid` and NOT `fd_tid`, unlike the table itself. The merged namespace
                // says "one fd number, one open file, process-wide"; this is a different
                // claim — a WINDOW, one line wide, opened by a thread and closed by that
                // thread's very next line. Keyed process-wide, a worker's line lands in
                // the window main opened and either completes the dup against the wrong
                // descriptor or consumes it and drops the shim's trace fd from the table,
                // which makes the run's outcome depend on the scheduler. #544's first
                if (!std.mem.eql(u8, d.tid, ln.tid)) {
                    i += 1;
                    continue;
                }
                const is_inert_fcntl = std.mem.eql(u8, canonicalCall(ln.call), "fcntl") and fcntlIsInert(ln.middle);
                if (fd) |f| {
                    if (is_inert_fcntl and fds.get(.{ .tid = fd_tid, .fd = f }) == null and !std.mem.eql(u8, d.fd, f)) {
                        if (fds.get(.{ .tid = fd_tid, .fd = d.fd })) |src_in_state|
                            try fds.set(arena, .{ .tid = fd_tid, .fd = f }, src_in_state);
                    }
                }
                _ = dup_pending.swapRemove(i);
            }
        }

        if (std.mem.eql(u8, canonicalCall(ln.call), "fcntl")) {
            if (fcntlDuplicates(ln.middle)) {
                if (!hasErrno(ln.middle)) {
                    // `ln.tid`, for the reason the loop above carries: the window is one
                    // thread's next line, not a process-wide fact about a descriptor.
                    if (fd) |src| try dup_pending.append(arena, .{ .tid = ln.tid, .fd = src });
                }
                continue;
            }
            if (fcntlIsInert(ln.middle)) continue;
            // Any other command falls through to the scope decision below: `F_FULLFSYNC`
            // on a state descriptor reaches the unknown-call refusal there, and the same
            // command on a descriptor outside the root is nobody's business.
        }

        // Where does this line point? Resolved before anything can skip it, so a
        // read-only open of a directory still enters the table for the
        // directory-relative operations that follow it.
        var path: ?[]const u8 = null; // absolute
        var dir_scope: ?bool = null; // placed through a directory descriptor
        var path_unresolvable = false;
        if (operandOf(ln.middle)) |op| {
            if (op.text.len != 0 and op.text[0] == '/') {
                path = op.text;
            } else if (op.dirfd) |d| {
                if (std.mem.indexOf(u8, op.text, "..") != null) {
                    // `..` can leave the directory the operand is relative to. The table
                    // holds a scope bit, not a path, and a textual join to the cwd
                    // would place `../st/x` wherever the string says rather than where
                    // the kernel goes; neither can be trusted, so neither is tried.
                    path_unresolvable = true;
                } else if (d == at_fdcwd) {
                    if (cwd.len != 0 and !cwd_moved) path = try joinPath(arena, cwd, op.text) else path_unresolvable = true;
                } else {
                    const key = try std.fmt.allocPrint(arena, "{d}", .{d});
                    if (fds.get(.{ .tid = fd_tid, .fd = key })) |in| dir_scope = in else path_unresolvable = true;
                }
            } else path_unresolvable = true;
        }
        const scope_known: ?bool = if (path) |p| inState(p, state_root, state_alt) else dir_scope;

        // A call that cannot change state is not a hole whatever happened to its path.
        // Decided before the truncation check, because the truncation check is where a
        // real run refused: dyld's `stat64` of a framework path under
        // `/System/Volumes/Preboot/Cryptexes/...` is longer than the display width, and
        // every process issues hundreds of them at start-up — 353 in one measured
        // capture of the subject, plus one `access`, and not a single mutating call.
        if (is_relevant and (std.mem.eql(u8, canonicalCall(ln.call), "chdir") or std.mem.eql(u8, canonicalCall(ln.call), "fchdir") or std.mem.eql(u8, canonicalCall(ln.call), "__pthread_chdir") or std.mem.eql(u8, canonicalCall(ln.call), "__pthread_fchdir"))) {
            cwd_moved = true;
            continue;
        }
        if (isReadOnlyCall(ln.call) or isDiskIo(ln.call)) continue;
        if (cls_opt == .open and !openIsWriteCapable(ln.middle)) {
            if (fd) |f| {
                if (scope_known) |in| {
                    if (is_subject or in) try fds.set(arena, .{ .tid = fd_tid, .fd = f }, in);
                }
            }
            continue;
        }

        if (isTruncated(ln.middle) and is_relevant) {
            out.defect = .{ .truncated = raw };
            return out;
        }

        // Descriptor bookkeeping runs for every line that carries one, whether or not
        // the line is in scope: a descriptor opened outside the state root and later
        // written must resolve to "not in scope", not to "unknown".
        if (cls_opt) |cls| {
            if (cls == .open) {
                const keep = is_subject or (scope_known orelse false);
                if (keep) {
                    if (fd) |f| {
                        if (scope_known) |in| {
                            try fds.set(arena, .{ .tid = fd_tid, .fd = f }, in);
                        } else if (is_relevant) {
                            out.defect = .{ .unresolvable_path = raw };
                            return out;
                        }
                    }
                }
            } else if (cls == .close) {
                if (fd) |f| fds.clear(.{ .tid = fd_tid, .fd = f });
                continue;
            }
        }

        // The shim's own trace writes and the sentinels are the observer's shadow, not
        // the target's work — skipped here, AFTER the descriptor bookkeeping above, so
        // the shim's `open F=3 trace.bin` is in the table for the dup to inherit from.
        if (path) |p| {
            if (samePath(p, trace_path)) continue;
            if (sentinel_start.len != 0 and samePath(p, sentinel_start)) continue;
            if (sentinel_end.len != 0 and samePath(p, sentinel_end)) continue;
        }

        var in_scope = false;
        if (scope_known) |in| {
            in_scope = in;
        } else if (path_unresolvable) {
            // The `c != .close` test that used to sit inside this unwrap is gone: a close
            // **The unwrap itself stays**, and a first draft of this change dropped it
            // together with the test — which was not behaviour-preserving and was caught
            // in review. A line `classOf` does not map returns null here and must go on
            // falling through to `continue`: `fcntl`'s non-inert commands are deliberately
            // outside that table (see the comment above the `fcntl` handling), and
            // refusing on one would make a single lock call from a thread that once
            // touched the judged directory refuse the whole run. Nothing pins the removal
            // of the test — the branch cannot be entered by a close, so mutating it
            // changes no behaviour — and what holds it is the reachability above.
            if (is_relevant) {
                if (cls_opt) |_| {
                    out.defect = .{ .unresolvable_path = raw };
                    return out;
                }
            }
            continue;
        } else if (fd) |f| {
            const known = fds.get(.{ .tid = fd_tid, .fd = f }) orelse {
                // Same reachability as above: a close never gets here. The unwrap is kept
                // for the same reason it is kept there — an unmapped call must fall
                // through, not refuse.
                if (cls_opt) |_| {
                    if (is_relevant) {
                        out.defect = .{ .unresolved_fd = raw };
                        return out;
                    }
                }
                continue;
            };
            in_scope = known;
        }
        if (!in_scope) {
            // A rename is the one class this witness reports partially: fs_usage prints
            // the OLD path and never the destination (measured, RESULTS.md P3). So a
            // rename whose visible path is outside the root may still have moved a file
            // INTO it, and dropping it here is exactly the hole ADR 0031 promised to
            // close — the raw-fork child's `rename(outside, state/x)` that neither
            // witness would otherwise report. Kept as a divergence candidate: the
            // comparison has no shim record to match it against, so it refuses.
            if (cls_opt) |c| {
                if (c == .rename and is_relevant) {
                    out.defect = .{ .unresolved_fd = raw };
                    return out;
                }
            }
            continue;
        }
        out.parsed.lines_in_scope += 1;

        if (isMetadataCall(ln.call)) {
            try out.parsed.metadata_observed.append(arena, try arena.dupe(u8, ln.call));
            continue;
        }
        const cls = cls_opt orelse {
            out.defect = .{ .unknown_call = raw };
            return out;
        };

        if (!is_subject) {
            if (std.fmt.parseInt(u64, ln.tid, 10)) |n| {
                try oracle.noteEvent(arena, &out.parsed.mutations, n, out.parsed.lines_seen);
            } else |_| {}
            try appendUnique(arena, &other_tids, ln.tid);
            out.parsed.children = other_tids.items.len;
            continue;
        }

        try out.parsed.classes.append(arena, cls);
        try out.parsed.names.append(arena, ln.call);
        try out.parsed.lines.append(arena, ln.raw);
    }

    return out;
}

// Tests. The fixtures are lines copied from real captures taken on macOS 15.3.1 and
// on the CI runner (26.5.2) — the two shapes that differ — rather than composed from
// the man page, which is wrong about both the truncation marker and the tail format.

const testing = std.testing;

const cap_line = "18:51:42.041795  open              F=3        (_WC_T_______)  /tmp/st/load                                    0.000383   loadprobe.79512937";

test "parseLine takes the call, the tid and the middle" {
    const ln = parseLine(cap_line).?;
    try testing.expectEqualStrings("open", ln.call);
    try testing.expectEqualStrings("79512937", ln.tid);
    try testing.expect(std.mem.indexOf(u8, ln.middle, "F=3") != null);
    try testing.expect(std.mem.indexOf(u8, ln.middle, "/tmp/st/load") != null);
}

test "a process name with spaces still parses" {
    const l = "09:00:00.000001  write             F=1   B=0x7                                  0.000010   Google Chrome He.64625821";
    const ln = parseLine(l).?;
    try testing.expectEqualStrings("write", ln.call);
    try testing.expectEqualStrings("64625821", ln.tid);
}

test "both measured truncation shapes are stumps, and a whole path is not" {
    try testing.expect(isTruncated("  .../missing-d>>>>>>>>>>>>>>>>"));
    const real_stump = "F=3        (_WC_T__________)  ted-component/nested-component/nested-component/state/sentinel-start";
    try testing.expect(isTruncated(real_stump));
    try testing.expect(!isTruncated("F=3        (_WC_T_______)  /Users/i.yoshida/w/state/keep"));
    try testing.expect(!isTruncated("F=3    B=0x5"));
}

test "fd and operand come out of the middle, in both spellings" {
    const ln = parseLine(cap_line).?;
    try testing.expectEqualStrings("3", fdOf(ln.middle).?);
    const plain = operandOf(ln.middle).?;
    try testing.expect(plain.dirfd == null);
    try testing.expectEqualStrings("/tmp/st/load", plain.text);
    const rel = operandOf("F=3        (RWC__E______)  [-2]//tmp/st/tmp-oepJXu").?;
    try testing.expectEqual(@as(i64, -2), rel.dirfd.?);
    try testing.expectEqualStrings("/tmp/st/tmp-oepJXu", rel.text);
    const viafd = operandOf("F=6        (_WC_T_______)  [5]/inside").?;
    try testing.expectEqual(@as(i64, 5), viafd.dirfd.?);
    try testing.expectEqualStrings("inside", viafd.text);
    const err = operandOf("[  2]           /tmp/st/missing").?;
    try testing.expect(err.dirfd == null);
    try testing.expectEqualStrings("/tmp/st/missing", err.text);
}

test "underRoot does not accept a sibling whose name shares the prefix" {
    try testing.expect(underRoot("/tmp/st/load", "/tmp/st"));
    try testing.expect(underRoot("/tmp/st", "/tmp/st"));
    try testing.expect(!underRoot("/tmp/state-other/load", "/tmp/st"));
}

test "a firmlinked capture path scopes to the root the caller spelled" {
    try testing.expect(underRoot("/System/Volumes/Data/Users/x/s/f", "/Users/x/s"));
    try testing.expect(underRoot("/Users/x/s/f", "/Users/x/s"));
    try testing.expect(underRoot("/System/Volumes/Data/Users/x/s/f", "/System/Volumes/Data/Users/x/s"));
    try testing.expect(!underRoot("/System/Volumes/Data/Users/x/other/f", "/Users/x/s"));
    try testing.expectEqualStrings("/System/Volumes/DataX/y", physical("/System/Volumes/DataX/y"));
}

test "the handshake predicate is the reader's, not a substring search" {
    const text = "20:55:29.949643  lstat64                                /System/Volumes/Data/Users/i.yoshida/w/state/.sideeye-fsusage-open                          0.000007   fseventsd.80246391\n";
    try testing.expect(capturesPath(text, "/Users/i.yoshida/w/state/.sideeye-fsusage-open"));
    try testing.expect(!capturesPath(text, "/Users/i.yoshida/w/state/.sideeye-fsusage-close"));
    try testing.expect(!capturesPath("garbage /Users/i.yoshida/w/state/.sideeye-fsusage-open\n", "/Users/i.yoshida/w/state/.sideeye-fsusage-open"));
}

test "a listed worker's chdir still arms the relative-operand guard" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The `chdir` goes to the root's PARENT, which is where ADR 0031 §2b's own example
    // goes: a `chdir` INTO the judged directory is in scope and refuses as an unknown call
    // instead, so it would fail this test for a different reason. Outside the root it is
    // dropped silently, which is the shape that disables the guard rather than tripping
    // another one.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   main.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   main.111\n" ++
        "10:00:00.000003  open              F=5   (_WC_T_______)  /tmp/st/data          0.000100   main.111\n" ++
        "10:00:00.000004  write             F=5   B=0x4                                 0.000100   work.222\n" ++
        "10:00:00.000005  fsync             F=5                                         0.000100   work.222\n" ++
        "10:00:00.000006  chdir                   /tmp                                  0.000100   work.222\n" ++
        // `openat` with the flags bracket, which is what a real capture prints for a
        // dirfd-relative operand. Spelled `open` with no bracket, this line would be
        // write-capable only through `openIsWriteCapable`'s fail-safe default for an
        // unrecognised bracket — the test would pass on the default rather than on a shape
        // fs_usage produces.
        "10:00:00.000007  openat            F=6   (_WC_T_______)  [-2]/st/sneak         0.000100   work.222\n" ++
        "10:00:00.000008  open              F=2   /tmp/st/sentinel-b                    0.000100   main.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/work", &.{222}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }

    // The other side of the same capture, so the discrimination is pinned rather than
    // demonstrated once by hand. With no list the worker is not the subject, its `chdir`
    // is another party's and is ignored, and the relative operand resolves outside the
    // root and is dropped — which is the correct reading when nothing says that thread
    // belongs to the judged process. A change that makes `state_tids` cover this thread,
    // or that drops the widening, moves one of these two and fails here.
    const unlisted = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/work", &.{}, &.{});
    try testing.expect(unlisted.defect == null);
}

test "a worker thread's write to the shim's own trace descriptor is not a hole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   /tmp/st/data                          0.000100   subj.222\n" ++
        "10:00:00.000004  write             F=9   B=0x20                                0.000100   subj.222\n" ++
        "10:00:00.000005  write             F=5   B=0x4                                 0.000100   subj.222\n" ++
        "10:00:00.000006  write             F=9   B=0x20                                0.000100   subj.222\n" ++
        "10:00:00.000007  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{222}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.mutations.items.len);
    // The trace writes are the observer's shadow and must not be counted; the worker's own
    // `open` and `write` on `/tmp/st/data` must be. "No hole" and "counted" are different
    // claims and only the first was asserted here at first.
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
}

test "a worker thread the shim recorded is the subject, and only when it is named" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   /tmp/st/data                          0.000100   subj.222\n" ++
        "10:00:00.000004  write             F=5   B=0x4                                 0.000100   subj.222\n" ++
        "10:00:00.000005  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";

    const named = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{222}, &.{});
    try testing.expect(named.defect == null);
    try testing.expectEqual(@as(usize, 0), named.parsed.mutations.items.len);
    try testing.expectEqual(@as(usize, 0), named.parsed.children);
    try testing.expect(named.parsed.isSubject(222));
    // And the positive side, which the first version of this test left out: "not another
    // party's" is not the same as "counted". A reader that quietly dropped the worker's
    // operations would satisfy every assertion above and then fail on a real run as
    // `oracle_missed_operation`, because the shim's account holds two operations this one
    // does not. The promise is that the run is explored and JUDGED, so the operations
    // reaching the comparison is part of it.
    try testing.expectEqual(@as(usize, 2), named.parsed.classes.items.len);

    // The control, and the reason this test is a pair: without the list the widened
    // predicate would be indistinguishable from one that calls every thread the subject.
    const unnamed = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(unnamed.defect == null);
    try testing.expect(unnamed.parsed.mutations.items.len > 0);
    try testing.expectEqual(@as(u64, 222), unnamed.parsed.mutations.items[0].id);
    try testing.expectEqual(@as(usize, 1), unnamed.parsed.children);
    try testing.expect(!unnamed.parsed.isSubject(222));
}

test "a thread the shim never recorded stays another party's, list or no list" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // A writer whose operations the shim never recorded — one going straight to syscalls.
    // No kill-point record of its own, so it is not in the list handed here. The list
    // NOT a raw `clone`, which is what this comment said until #543. That thread's writes
    // through libc are recorded under the subject's pid, so its tid would be in the list
    // and this fixture would be measuring the opposite case. The test was green for a
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   /tmp/st/data                          0.000100   subj.333\n" ++
        "10:00:00.000004  write             F=5   B=0x4                                 0.000100   subj.333\n" ++
        "10:00:00.000005  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{222}, &.{});
    try testing.expect(r.defect == null);
    try testing.expect(r.parsed.mutations.items.len > 0);
    try testing.expectEqual(@as(u64, 333), r.parsed.mutations.items[0].id);
    try testing.expectEqual(@as(usize, 1), r.parsed.children);
    try testing.expect(!r.parsed.isSubject(333));
}

test "a started thread that wrote nothing through the shim shares the descriptor namespace: its start record is not a hole, its raw write stays another party's (v18)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  write             F=9   B=0x40                                0.000100   subj.333\n" ++
        "10:00:00.000004  open              F=5   /tmp/st/raw                           0.000100   subj.333\n" ++
        "10:00:00.000005  write             F=5   B=0x2                                 0.000100   subj.333\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{333});
    try testing.expect(r.defect == null);
    try testing.expect(r.parsed.mutations.items.len > 0);
    try testing.expectEqual(@as(u64, 333), r.parsed.mutations.items[0].id);
    try testing.expectEqual(@as(usize, 1), r.parsed.children);
    try testing.expect(!r.parsed.isSubject(333));
    // The control: with no started list the same capture is a hole, which is what CI
    const before = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(before.defect != null);
    switch (before.defect.?) {
        .unresolved_fd => {},
        else => return error.TestUnexpectedResult,
    }
}

test "a write on a descriptor nobody opened is a hole, not a skipped line" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  write             F=9   B=0x4                                 0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n" ++
        "10:00:00.000005  write             F=7   B=0x1                                 0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolved_fd => {},
        else => return error.WrongDefect,
    }
}

test "an open whose path cannot be read is a hole, not a descriptor to trust later" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=6   (_WC_T_______)                        0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
}

test "a truncated read-only line from the subject is not a hole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:23:17.677297  stat64                 [  2]           /System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/CoreServices.framework>>>                                                                              0.000001   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
}

test "a truncated mutating line from the subject still refuses" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  unlink                                 /System/Volumes/Data/Users/x/some/very/long/dir/na>>>                                     0.000001   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .truncated => {},
        else => return error.WrongDefect,
    }
}

test "a tail-less read-only line from nobody is not a hole; a tail-less mutating one still is" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const daemon = "13:47:23.434908  getattrlist            [  2]           ontentd/APCS-TEMP/U\xcc\x82.@?e\xcc\x81\xc3\x9f\xc2\xb6?w?\xc2\xa5@P?&?^w\xc2\xaf>I\xcc\x80R\xc2\xa6\xc3\xb7a\xcc\x88??\xc2\xa5\xc3\x86I\xcc\x80o\xcc\x81i\xcc\x81\xc2\xaf\xc2\xb6?T?\\A\xcc\x80\xc2\xb9C\xcc\xa7 i\xcc\x802?}?9? i\xcc\x82??\xc2\xa1\xc2\xb1A\xcc\x8a?P-?V?";
    const head =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n";
    const tail = "\n10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const text = head ++ daemon ++ tail;
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
    try testing.expectEqual(@as(usize, 0), r.parsed.mutations.items.len);
    const mutating = "13:47:23.434908  write                  [  2]           ontentd/APCS-TEMP/U\xcc\x82.@?e\xcc\x81\xc3\x9f\xc2\xb6?w?\xc2\xa5@P?&?^w\xc2\xaf>I\xcc\x80R\xc2\xa6\xc3\xb7a\xcc\x88??\xc2\xa5\xc3\x86I\xcc\x80o\xcc\x81i\xcc\x81\xc2\xaf\xc2\xb6?T?\\A\xcc\x80\xc2\xb9C\xcc\xa7 i\xcc\x802?}?9? i\xcc\x82??\xc2\xa1\xc2\xb1A\xcc\x8a?P-?V?";
    const text2 = head ++ mutating ++ tail;
    const r2 = try read(a, text2, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r2.defect != null);
    try testing.expect(r2.defect.? == .unparsed);
}

test "the lines after a skipped cut head, up to its tail, are fragments of that event; the same lines elsewhere are holes" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const head_line = "13:47:23.434908  getattrlist            [  2]           ontentd/APCS-TEMP/U\xcc\x82.@?e\xcc\x81\xc3\x9f\xc2\xb6?w?\xc2\xa5@P?&?^w\xc2\xaf>I\xcc\x80R\xc2\xa6\xc3\xb7a\xcc\x88??\xc2\xa5\xc3\x86I\xcc\x80o\xcc\x81i\xcc\x81\xc2\xaf\xc2\xb6?T?\\A\xcc\x80\xc2\xb9C\xcc\xa7 i\xcc\x802?}?9? i\xcc\x82??\xc2\xa1\xc2\xb1A\xcc\x8a?P-?V?";
    const tail_line = "133 LIBARCHIVE.xattr.com.apple.macl=B    0.000039   promotedcontentd.13451";
    const middle_line = "just bytes with no timestamp and no tail";
    const whole_line = "10:00:00.000003  stat64                 [  2]           /tmp/elsewhere                       0.000010   other.222";
    const before =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n";
    const after = "\n10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const Case = struct { text: []const u8, hole: bool, why: []const u8 };
    const cases = [_]Case{
        .{ .text = before ++ head_line ++ "\n" ++ tail_line ++ after, .hole = false, .why = "head then tail: one event, skipped whole" },
        .{ .text = before ++ head_line ++ "\n" ++ middle_line ++ "\n" ++ tail_line ++ after, .hole = false, .why = "a name that makes three fragments: all of them the same event" },
        .{ .text = before ++ head_line ++ "\n" ++ whole_line ++ "\n" ++ tail_line ++ after, .hole = true, .why = "a whole line ends the event; a tail after it is nobody's" },
        .{ .text = before ++ tail_line ++ after, .hole = true, .why = "a tail with no cut head before it" },
        .{ .text = before ++ middle_line ++ after, .hole = true, .why = "a fragment with no cut head before it" },
        .{ .text = before ++ head_line ++ "\n" ++ tail_line ++ "\n" ++ tail_line ++ after, .hole = true, .why = "the first tail ended the event; the second is nobody's" },
    };
    for (cases) |c| {
        const r = try read(a, c.text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
        if (c.hole) {
            testing.expect(r.defect != null) catch |e| {
                std.debug.print("expected a hole: {s}\n", .{c.why});
                return e;
            };
            try testing.expect(r.defect.? == .unparsed);
        } else {
            testing.expect(r.defect == null) catch |e| {
                std.debug.print("expected no hole: {s}\n", .{c.why});
                return e;
            };
            try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
            try testing.expectEqual(@as(usize, 0), r.parsed.mutations.items.len);
        }
    }
}

test "the shim's dup of its own trace descriptor is followed, and a daemon reading the trace is not the subject" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "21:03:21.587700  lstat64                                /work/trace.bin                        0.000005   fseventsd.999\n" ++
        "21:03:21.587701  open              F=27       (R___________)  /work/trace.bin                   0.000010   wdavdaemon.888\n" ++
        "21:03:21.587753  open              F=3        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "21:03:21.587757  fcntl             F=3   [ 22] <DUPFD>                                          0.000001   subj.111\n" ++
        "21:03:21.587760  fcntl             F=3   <DUPFD>                                                0.000003   subj.111\n" ++
        "21:03:21.587761  fcntl             F=200 <SETFD>                                                0.000001   subj.111\n" ++
        "21:03:21.587763  close             F=3                                                          0.000003   subj.111\n" ++
        "21:03:21.587764  lseek             F=200 O=0x00000000 <SEEK_END>                                0.000001   subj.111\n" ++
        "21:03:21.587809  write             F=200 B=0xc                                                  0.000045   subj.111\n" ++
        "21:03:21.587900  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "21:03:21.588000  open              F=3        (_WC_T_______)  /tmp/st/keep                      0.000010   subj.111\n" ++
        "21:03:21.588001  write             F=3   B=0x3                                                  0.000004   subj.111\n" ++
        "21:03:21.588002  close             F=3                                                          0.000002   subj.111\n" ++
        "21:03:21.588100  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqualStrings("111", r.subject_tid.?);
    try testing.expect(!r.parsed.childTouched());
    // Two, not three: `close` is a lifecycle op the shim records and the strace oracle
    // drops from the compared sequence (`oracle.zig`, `if (cls == .close) continue`),
    // and the two accounts have to be shaped alike. This test first asserted three and
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
    try testing.expectEqual(contract.OpClass.open, r.parsed.classes.items[0]);
    try testing.expectEqual(contract.OpClass.write, r.parsed.classes.items[1]);
    // The three lists are index-aligned, and a divergence refusal reads `names[i]` for
    // the operation `classes[i]` diverged on (#337). Only `classes` was ever asserted
    // here, so an append that drifted would have gone unnoticed on this side — the
    // strace reader pins the same property for its own two lists.
    try testing.expectEqual(r.parsed.classes.items.len, r.parsed.names.items.len);
    try testing.expectEqual(r.parsed.classes.items.len, r.parsed.lines.items.len);
    try testing.expectEqualStrings("open", r.parsed.names.items[0]);
    try testing.expectEqualStrings("write", r.parsed.names.items[1]);
}

test "a neighbour that only read the judged directory is not made relevant by it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:36:22.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:36:22.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:36:22.000003  open              F=17       (R___________)  /tmp/st/keep                      0.000072   wdavdaemon_enterprise.555\n" ++
        "10:36:22.388237  write             F=22  B=0xad                                                 0.000071   wdavdaemon_enterprise.555\n" ++
        "10:36:22.000005  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expect(!r.parsed.childTouched());
}

test "a neighbour that opened the judged directory for writing is relevant, and its unknown write is a hole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:36:22.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:36:22.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:36:22.000003  open              F=17       (_W__________)  /tmp/st/keep                      0.000072   neighbour.555\n" ++
        "10:36:22.388237  write             F=22  B=0xad                                                 0.000071   neighbour.555\n" ++
        "10:36:22.000005  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolved_fd => {},
        else => return error.WrongDefect,
    }
}

test "openat through AT_FDCWD with an absolute operand is the mkstemp line, and it is an operation" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:39:10.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:39:10.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:39:10.143604  openat            F=3        (RWC__E______)  [-2]//tmp/st/tmp-oepJXu                0.000360   subj.111\n" ++
        "10:39:10.143700  write             F=3   B=0x3                                                  0.000004   subj.111\n" ++
        "10:39:10.143701  close             F=3                                                          0.000002   subj.111\n" ++
        "10:39:10.200000  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
    try testing.expectEqual(contract.OpClass.open, r.parsed.classes.items[0]);
    try testing.expectEqual(contract.OpClass.write, r.parsed.classes.items[1]);
}

test "a directory opened read-only places the openat that follows through it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5        (R___________)  /tmp/st                           0.000010   subj.111\n" ++
        "10:00:00.000004  openat            F=6        (_WC_T_______)  [5]/inside                        0.000010   subj.111\n" ++
        "10:00:00.000005  write             F=6   B=0x3                                                  0.000004   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
}

test "a relative operand with no cwd, on a call that could change state, refuses" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  openat            F=6        (_WC_T_______)  [-2]/relative/file                0.000010   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
    const r2 = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/elsewhere", &.{}, &.{});
    try testing.expect(r2.defect == null);
    try testing.expectEqual(@as(usize, 0), r2.parsed.classes.items.len);
}

test "a relative operand with .. is unplaceable through AT_FDCWD too" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  openat            F=6        (_WC_T_______)  [-2]/../st/x                      0.000010   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/tmp/work", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
}

test "after the subject chdirs, a relative operand that could change state refuses" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  chdir                                  /tmp                                    0.000010   subj.111\n" ++
        "10:00:00.000004  openat            F=6        (_WC_T_______)  [-2]/st/missed                    0.000010   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/tmp/work", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
}

test "a dup completes only on the next line, and only onto an inert fcntl of an unknown descriptor" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=4        (_W__________)  /var/log/mine                     0.000010   subj.111\n" ++
        "10:00:00.000004  fcntl             F=4   <DUPFD>                                                0.000003   subj.111\n" ++
        "10:00:00.000005  write             F=7   B=0x3                                                  0.000004   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolved_fd => {},
        else => return error.WrongDefect,
    }
}

test "a missing sentinel refuses before anything is compared" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .missing_sentinel => |p| try testing.expectEqualStrings("/tmp/st/sentinel-b", p),
        else => return error.WrongDefect,
    }
}

test "no tid writes the trace: the subject cannot be named and the run refuses" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000003  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .no_subject => {},
        else => return error.WrongDefect,
    }
}

test "a second tid mutating the judged directory is recorded in the touch set" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=3   /tmp/st/from-parent                   0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=3   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  open              F=4   /tmp/st/from-raw-child                0.000100   subj.222\n" ++
        "10:00:00.000006  write             F=4   B=0x9                                 0.000100   subj.222\n" ++
        "10:00:00.000007  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expect(r.parsed.childTouched());
    try testing.expectEqual(@as(usize, 1), r.parsed.children);
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
    try testing.expectEqual(contract.OpClass.open, r.parsed.classes.items[0]);
    try testing.expectEqual(contract.OpClass.write, r.parsed.classes.items[1]);
}

test "an unknown CALL inside the judged directory refuses rather than being ignored" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  exchangedata            /tmp/st/thing                         0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unknown_call => {},
        else => return error.WrongDefect,
    }
}

test "a failed call in the judged directory is still an operation, as it is for strace" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // This test asserted the opposite until review pointed at the mismatch. The shim
    // places its kill before the effect, so a failed attempt is still an address, and
    // `oracle.zig` reads success only to follow chdir. An fs_usage reader that dropped
    // errno lines made every failing target a phantom divergence.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  unlink            [  2]  /tmp/st/missing                      0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 1), r.parsed.classes.items.len);
    try testing.expectEqual(contract.OpClass.unlink, r.parsed.classes.items[0]);
}

test "work outside the judged directory is not the subject's account" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=5   /somewhere/else                       0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=5   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "", &.{}, &.{});
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
}
