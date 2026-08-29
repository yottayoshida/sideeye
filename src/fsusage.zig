//! The macOS completeness oracle: read `fs_usage`'s view of the recording run and hold
//! the shim's trace against it.
//!
//! Same job as `oracle.zig` does with strace, same output type, compared by the same
//! `oracle.compare`. What differs is everything about the witness.
//!
//! **It is not a wrapper.** strace execs the target; `fs_usage` runs beside it, reading
//! the kernel's trace buffer. So the capture is not bounded by the target's lifetime,
//! and nothing about it proves the observer was alive for the whole run — the caller
//! bounds the window with sentinels and this module refuses a capture whose sentinels
//! are missing.
//!
//! **It cannot follow children by pid.** `fs_usage`'s pid filter does not follow a fork
//! (measured, `spike/fsusage/RESULTS.md`), so filtering by the subject's pid leaves a
//! raw-forked child invisible to this witness exactly where it is already invisible to
//! the shim — which is #405, reachable on the shipped build. The capture is therefore
//! taken unfiltered and scoped by the state root: a write into that root appears here
//! whoever performed it.
//!
//! **It prints thread ids, not pids.** With the filter gone, something has to say which
//! lines are the subject's. The shim writes its trace to `SIDEEYE_TRACE_PATH` and only
//! the subject carries the shim, so the tid that writes to the trace path is the
//! subject. No trace-contract field is added for this — a contract bump orphans every
//! saved case (#279) — and the identification is self-checking: no such tid, no verdict.
//!
//! **Everything it cannot resolve is a refusal.** A write whose descriptor was never
//! opened in the window, a path truncated by the display cap, a CALL this module does
//! not know, a line the grammar does not match: each of those is a hole in the account,
//! and an account with a hole must not be reported as agreement. The grammar itself is
//! ported from `spike/fsusage/classify.py`, which was written against real captures on
//! two machines rather than from the man page.

const std = @import("std");
const contract = @import("contract");
const oracle = @import("oracle.zig");

/// Why a capture cannot be read as a complete account. Every one of these is a refusal
/// at the call site; none of them is a divergence, because a divergence is a statement
/// about what the two witnesses saw and these say the witness itself is unreadable.
pub const Defect = union(enum) {
    /// The grammar did not match a line. Never skipped: an unparsed line is an
    /// operation this module cannot rule out.
    unparsed: []const u8,
    /// A pathname cut by the display cap. The state root's own prefix may be gone, so
    /// the line cannot be scoped either way.
    truncated: []const u8,
    /// A `write`/`fsync`/`ftruncate` on a descriptor with no `open` in the window.
    /// Inherited descriptors land here; so does a capture that started too late.
    unresolved_fd: []const u8,
    /// A CALL touching the state root that this module does not map to an OpClass.
    unknown_call: []const u8,
    /// No tid wrote to the trace path, so the subject could not be identified.
    no_subject,
    /// A sentinel the caller placed was not in the capture.
    missing_sentinel: []const u8,
};

pub const Reading = struct {
    parsed: oracle.Parsed,
    /// Non-null when the capture cannot be read as a complete account. The caller
    /// refuses; it never compares a defective reading.
    defect: ?Defect = null,
    /// The tid identified as the subject, for the account line.
    subject_tid: ?[]const u8 = null,
};

/// One parsed line. `middle` holds the fields between the CALL and the duration —
/// descriptors, errno brackets, byte counts and the pathname, in `fs_usage`'s order.
const Line = struct {
    call: []const u8,
    middle: []const u8,
    tid: []const u8,
    raw: []const u8,
};

/// `HH:MM:SS.uuuuuu  CALL  <middle>  D.DDDDDD [W ]proc.tid`
///
/// Process names contain spaces (`Google Chrome He.64625821`, measured on the owner's
/// laptop and absent from the CI runner, which is why a `\S+` grammar passed there and
/// refused here), so the process field is taken as everything before the LAST dot on
/// the line's tail. The duration is the anchor: it is the only field whose shape is
/// fixed, and everything left of it is the CALL plus its arguments.
fn parseLine(raw: []const u8) ?Line {
    const line = std.mem.trimEnd(u8, raw, " \t\r");
    if (line.len < 20) return null;

    // Timestamp: HH:MM:SS.uuuuuu — wide mode always carries the fractional part.
    if (line[2] != ':' or line[5] != ':' or line[8] != '.') return null;
    var i: usize = 9;
    while (i < line.len and std.ascii.isDigit(line[i])) i += 1;
    if (i == 9) return null;
    while (i < line.len and line[i] == ' ') i += 1;

    // CALL
    const call_start = i;
    while (i < line.len and line[i] != ' ') i += 1;
    if (i == call_start) return null;
    const call = line[call_start..i];

    // The tail: `proc.tid`, tid being the digits after the LAST dot of the LAST field.
    //
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

    // Left of the process name sits the duration, and before that the middle.
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
        if (!std.mem.eql(u8, word, "W")) {
            // Part of the process name; keep walking left.
        }
        scan = w_start;
    }
    const middle_end = dur_end orelse return null;
    if (middle_end <= call_start) return null;
    const middle = std.mem.trim(u8, line[i..middle_end], " \t");
    return .{ .call = call, .middle = middle, .tid = tid, .raw = raw };
}

fn isDuration(w: []const u8) bool {
    // D.DDDDDD — at least one digit, a dot, exactly six digits.
    const dot = std.mem.indexOfScalar(u8, w, '.') orelse return false;
    if (dot == 0 or w.len - dot - 1 != 6) return false;
    for (w[0..dot]) |c| if (!std.ascii.isDigit(c)) return false;
    for (w[dot + 1 ..]) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// Was this line's pathname cut by the display width?
///
/// Two shapes, and the first version of this module implemented only one of them.
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
    // A stump: the tail looks like a path (it holds a separator) but has no root. The
    // annotation fields fs_usage puts before the operand — `F=3`, `B=0x5`, `[  2]`,
    // `(_WC_T__)`, `D=0x...` — never contain a slash, so a slash outside them means the
    // operand is present, and an operand with no leading `/` means it was cut.
    var it = std.mem.tokenizeAny(u8, t, " ");
    while (it.next()) |tok| {
        if (std.mem.indexOfScalar(u8, tok, '/') == null) continue;
        if (tok[0] == '/') return false; // a whole path: the operand survived
        if (tok[0] == '(' or tok[0] == '[') continue; // an annotation that holds a slash
        return true;
    }
    return false;
}

/// `[  2]` — the call failed and changed nothing. Present on every failing mode
/// measured (seven of seven), so a failed call is recognised rather than inferred.
fn errnoPresent(middle: []const u8) bool {
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

/// The pathname is the last whitespace-separated field that starts with `/`.
/// Directory names hold spaces and non-ASCII (`wei rd-ステート` printed byte for byte,
/// measured), so this takes everything from the first `/`-leading token to the end
/// rather than tokenising the path itself.
fn pathOf(middle: []const u8) ?[]const u8 {
    const slash = std.mem.indexOfScalar(u8, middle, '/') orelse return null;
    // A `/dev/...` in an annotation field is not the operand; annotations are
    // parenthesised or `KEY=value` shaped and never start the tail.
    if (slash > 0 and middle[slash - 1] != ' ') return null;
    return std.mem.trim(u8, middle[slash..], " \t");
}

/// CALL name to the class the shim would have recorded. Only calls that can change
/// state are mapped; read-only calls return null and are ignored, matching ADR 0003's
/// predicate on the shim side. `close` is recorded but never a crash point.
fn classOf(call: []const u8) ?contract.OpClass {
    const table = [_]struct { name: []const u8, class: contract.OpClass }{
        .{ .name = "open", .class = .open },
        .{ .name = "guarded_open_np", .class = .open },
        .{ .name = "openat", .class = .open },
        .{ .name = "write", .class = .write },
        .{ .name = "pwrite", .class = .write },
        .{ .name = "writev", .class = .write },
        .{ .name = "pwritev", .class = .write },
        .{ .name = "rename", .class = .rename },
        .{ .name = "renameat", .class = .rename },
        .{ .name = "renameatx_np", .class = .rename },
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
        .{ .name = "close_nocancel", .class = .close },
    };
    for (table) |e| if (std.mem.eql(u8, call, e.name)) return e.class;
    return null;
}

/// Is this `open` write-capable, in ADR 0003's sense?
///
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
    // Anything but a bare read is write-capable; so is create or truncate.
    if (flags[1] == 'W') return true;
    if (flags[2] == 'C') return true;
    if (flags[4] == 'T') return true;
    return flags[0] != 'R';
}

/// Ownership/permission/timestamp writes: observed and excluded from judgement (#121),
/// reported so the exclusion is visible per run.
fn isMetadataCall(call: []const u8) bool {
    const names = [_][]const u8{
        "chmod",    "fchmod",  "fchmodat", "chown", "fchown", "lchown",
        "fchownat", "utimes",  "futimes",  "utimensat", "setattrlist",
        "chflags",  "fchflags",
    };
    for (names) |n| if (std.mem.eql(u8, call, n)) return true;
    return false;
}

/// Calls that read and change nothing. Named exhaustively rather than inferred, because
/// the rule below refuses anything it does not recognise: a state-directory call this
/// module cannot classify is a hole, and "probably harmless" is not a classification.
///
/// The list is the one a real capture produced. Measured against the state root of an
/// end-to-end run: `lstat64` and `getattrlist` dominate (Spotlight and fseventsd walking
/// a directory that just changed), with `listxattr`, `getxattr` and `access` behind
/// them, and the subject's own `fstat64`/`fcntl` bracketing pairs from the shim.
fn isReadOnlyCall(call: []const u8) bool {
    const names = [_][]const u8{
        "stat64",     "stat",       "lstat64",    "lstat",     "fstat64",   "fstat",
        "fstatat64",  "fstatat",    "getattrlist", "getattrlistat", "fgetattrlist",
        "listxattr",  "flistxattr", "getxattr",   "fgetxattr", "access",    "faccessat",
        "readlink",   "readlinkat", "fsgetpath",  "getdirentries64",
        "getdirentries", "opendir",  "readdir",   "closedir",  "pathconf",  "fpathconf",
        "statfs64",   "fstatfs64",  "getfsstat64", "read",     "pread",     "readv",
        "lseek",      "mmap",       "munmap",     "ioctl",     "select",    "exit",
    };
    for (names) |n| if (std.mem.eql(u8, call, n)) return true;
    return false;
}

/// `fcntl` carries its command in an annotation, so it is classified by command rather
/// than waved through as a class.
///
/// The shim's own descriptor resolution is `<GETPATH>`, and a real capture of one run
/// holds 32 of those beside `<SETFD>`, `<GETFL>`, `<SETFL>`, `<SETLKW>`, `<DUPFD>`,
/// `<SETLK>` and `<GETFD>`. Excluding the whole class would let `F_FULLFSYNC` — which
/// the shim does not record and which is a durability operation on the state — through
/// the unknown-call gate that exists to catch exactly that.
///
/// Returns true when this `fcntl` neither changes state nor moves a descriptor.
fn fcntlIsInert(middle: []const u8) bool {
    const inert = [_][]const u8{ "<GETPATH>", "<GETFL>", "<SETFL>", "<GETFD>", "<SETFD>", "<GETLK>" };
    for (inert) |n| if (std.mem.indexOf(u8, middle, n) != null) return true;
    return false;
}

/// A `fcntl` that duplicates a descriptor, so the fd table has to follow it. Without
/// this a write on the duplicate resolves against nothing and refuses — measured as
/// two `<DUPFD>` lines in one ordinary run.
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
///
/// Stripped rather than added to the root: the prefix belongs to the witness's
/// spelling, and a root that already carries it (a caller who passed the physical
/// path) still matches, since stripping is idempotent here.
const firmlink_prefix = "/System/Volumes/Data";

fn physical(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, firmlink_prefix)) {
        const rest = path[firmlink_prefix.len..];
        if (rest.len > 0 and rest[0] == '/') return rest;
    }
    return path;
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

/// Does a line in this capture name `path`, under the same grammar and the same path
/// spelling the reader uses? The handshake asks this rather than searching the text:
/// a raw substring match found an `fseventsd` line about the sentinel and let a run
/// proceed whose capture the reader could not scope at all (measured, first end-to-end
/// run). A gate looser than the check behind it is not a gate.
pub fn capturesPath(text: []const u8, path: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        const ln = parseLine(raw) orelse continue;
        const p = pathOf(ln.middle) orelse continue;
        if (samePath(p, path)) return true;
    }
    return false;
}

/// Read one capture. `state_root` and `state_alt` are the judged directory's two
/// spellings (`/tmp` and `/private/tmp` resolve to one place on macOS); `trace_path`
/// is where the shim writes, and identifies the subject; the sentinels are paths the
/// caller created before and after the recording, both of which must appear.
pub fn read(
    arena: std.mem.Allocator,
    text: []const u8,
    state_root: []const u8,
    state_alt: []const u8,
    trace_path: []const u8,
    sentinel_start: []const u8,
    sentinel_end: []const u8,
) !Reading {
    var out: Reading = .{ .parsed = .{ .classes = .empty, .lines = .empty, .metadata_observed = .empty } };
    var fds: FdTable = .{};
    var subject_tid: ?[]const u8 = null;
    var saw_start = false;
    var saw_end = false;
    var other_tids: std.ArrayList([]const u8) = .empty;
    // Threads that name a path under the judged root anywhere in the capture.
    //
    // The capture is unfiltered, so it holds every process on the machine, and most of
    // them hold descriptors opened long before it started. Their unresolvable writes
    // and their truncated paths are not holes in the account of *this* directory —
    // they are not about this directory at all. Measured the hard way: the first
    // end-to-end run with a complete capture refused on `com.docker.backend`'s
    // `write F=96`.
    //
    // Collected over the whole capture before any of it is judged, because a thread's
    // first named touch can come after the line being decided.
    var state_tids: std.ArrayList([]const u8) = .empty;

    // First pass: identify the subject by who writes the trace, and find the sentinels.
    // Two passes rather than one because the subject's identity decides how later lines
    // are attributed, and the trace's first write is not necessarily the first line.
    var it0 = std.mem.splitScalar(u8, text, '\n');
    while (it0.next()) |raw| {
        if (raw.len == 0) continue;
        const ln = parseLine(raw) orelse continue;
        const path = pathOf(ln.middle) orelse continue;
        if (samePath(path, trace_path)) subject_tid = ln.tid;
        if (sentinel_start.len != 0 and samePath(path, sentinel_start)) saw_start = true;
        if (sentinel_end.len != 0 and samePath(path, sentinel_end)) saw_end = true;
        if (underRoot(path, state_root) or (state_alt.len != 0 and underRoot(path, state_alt))) {
            var known = false;
            for (state_tids.items) |t| {
                if (std.mem.eql(u8, t, ln.tid)) known = true;
            }
            if (!known) try state_tids.append(arena, ln.tid);
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
    out.subject_tid = subject;

    // Whether a hole in this line would be a hole in the account of the judged
    // directory. The subject always counts; so does any thread that named a path under
    // the root. Everything else is a neighbour going about its business.
    const relevant = struct {
        fn f(tid: []const u8, subj: []const u8, tids: []const []const u8) bool {
            if (std.mem.eql(u8, tid, subj)) return true;
            for (tids) |t| if (std.mem.eql(u8, t, tid)) return true;
            return false;
        }
    }.f;

    // Second pass: the account.
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        if (std.mem.trim(u8, raw, " \t\r").len == 0) continue;
        out.parsed.lines_seen += 1;

        const ln = parseLine(raw) orelse {
            out.defect = .{ .unparsed = raw };
            return out;
        };

        if (isTruncated(ln.middle) and relevant(ln.tid, subject, state_tids.items)) {
            out.defect = .{ .truncated = raw };
            return out;
        }

        // A failed call is NOT dropped. The shim records the attempt — it places the
        // kill immediately before the effect, so an attempt that fails is still an
        // address — and `oracle.zig` only consults success to track chdir's cwd, never
        // to decide whether a line is an operation. Dropping them here would make every
        // failing target a phantom divergence against an account that has them.
        //
        // The observation that a failed call carries its errno and its path (measured,
        // seven modes of seven) is what makes the two accounts line up, not a licence
        // to discard the line.

        const is_subject = std.mem.eql(u8, ln.tid, subject);
        const path = pathOf(ln.middle);
        const fd = fdOf(ln.middle);

        // The shim's own trace writes and the sentinels are the observer's shadow,
        // not the target's work. Classified here rather than filtered above so the
        // line still counts toward `lines_seen`.
        if (path) |p| {
            if (samePath(p, trace_path)) continue;
            if (sentinel_start.len != 0 and samePath(p, sentinel_start)) continue;
            if (sentinel_end.len != 0 and samePath(p, sentinel_end)) continue;
        }

        // Descriptor bookkeeping runs for every line that carries one, whether or not
        // the line is in scope: a descriptor opened outside the state root and later
        // written must resolve to "not in scope", not to "unknown".
        if (classOf(ln.call)) |cls| {
            if (cls == .open) {
                // A read-only open changes nothing and is not an observed operation on
                // either side (ADR 0003). Skipped before the descriptor bookkeeping so
                // a pathless one — `fs_usage` prints six of them in a real capture,
                // all reads — is not mistaken for a hole.
                if (!openIsWriteCapable(ln.middle)) continue;
                if (fd) |f| {
                    const p = path orelse {
                        if (relevant(ln.tid, subject, state_tids.items)) {
                            out.defect = .{ .unresolved_fd = raw };
                            return out;
                        }
                        continue;
                    };
                    try fds.set(arena, .{ .tid = ln.tid, .fd = f }, underRoot(p, state_root) or
                        (state_alt.len != 0 and underRoot(p, state_alt)));
                }
            } else if (cls == .close) {
                if (fd) |f| fds.clear(.{ .tid = ln.tid, .fd = f });
                continue;
            }
        }

        // Is this line about the judged directory?
        var in_scope = false;
        if (path) |p| {
            in_scope = underRoot(p, state_root) or (state_alt.len != 0 and underRoot(p, state_alt));
        } else if (fd) |f| {
            // Pathless: `write F=3 B=0x7`. Resolve through the open, or refuse.
            const known = fds.get(.{ .tid = ln.tid, .fd = f }) orelse {
                // Only calls that could change state make an unresolved descriptor a
                // hole; a read on an inherited descriptor is not this module's problem.
                if (classOf(ln.call)) |c| {
                    if (c != .close and relevant(ln.tid, subject, state_tids.items)) {
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
            if (classOf(ln.call)) |c| {
                if (c == .rename and relevant(ln.tid, subject, state_tids.items)) {
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
        if (std.mem.eql(u8, ln.call, "fcntl")) {
            if (fcntlDuplicates(ln.middle)) {
                // The duplicate inherits where the original pointed. fs_usage prints
                // the source descriptor; the new number appears on the following
                // operations, so the safe reading is that an unresolvable write after
                // a dup refuses — which it already does — rather than guessing a
                // mapping the line does not carry.
                continue;
            }
            if (fcntlIsInert(ln.middle)) continue;
            out.defect = .{ .unknown_call = raw };
            return out;
        }
        if (isReadOnlyCall(ln.call) or isDiskIo(ln.call)) continue;

        const cls = classOf(ln.call) orelse {
            out.defect = .{ .unknown_call = raw };
            return out;
        };

        if (!is_subject) {
            // The condition #405 is about, and the reason the capture is unfiltered:
            // a process other than the subject mutated the judged directory, and this
            // witness is the only one that sees it whether or not the shim was loaded.
            out.parsed.child_touched = true;
            var seen = false;
            for (other_tids.items) |t| {
                if (std.mem.eql(u8, t, ln.tid)) seen = true;
            }
            if (!seen) {
                try other_tids.append(arena, ln.tid);
                out.parsed.children += 1;
            }
            continue;
        }

        try out.parsed.classes.append(arena, cls);
        try out.parsed.lines.append(arena, ln.raw);
    }

    return out;
}

// ---------------------------------------------------------------------------------
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
    // Padded, macOS 15.x.
    try testing.expect(isTruncated("  .../missing-d>>>>>>>>>>>>>>>>"));
    // Unpadded and cut from the left — the shape the first version of this module
    // missed entirely. Copied byte for byte from the committed capture of the
    // deep-path leg, spike/fsusage/captures/P3-deep.cap.txt.
    const real_stump = "F=3        (_WC_T__________)  ted-component/nested-component/nested-component/state/sentinel-start";
    try testing.expect(isTruncated(real_stump));
    // A whole path is not a stump, however long.
    try testing.expect(!isTruncated("F=3        (_WC_T_______)  /Users/i.yoshida/w/state/keep"));
    // Neither is a line with no operand at all.
    try testing.expect(!isTruncated("F=3    B=0x5"));
}

test "an errno bracket marks a call that changed nothing" {
    try testing.expect(errnoPresent("open      [  2] (_WC_T__)  /tmp/st/missing"));
    try testing.expect(!errnoPresent("open      F=3  (_WC_T__)  /tmp/st/load"));
    // A byte count is not an errno.
    try testing.expect(!errnoPresent("write     F=3  B=0x7"));
}

test "fd and path come out of the middle" {
    const ln = parseLine(cap_line).?;
    try testing.expectEqualStrings("3", fdOf(ln.middle).?);
    try testing.expectEqualStrings("/tmp/st/load", pathOf(ln.middle).?);
}

test "underRoot does not accept a sibling whose name shares the prefix" {
    try testing.expect(underRoot("/tmp/st/load", "/tmp/st"));
    try testing.expect(underRoot("/tmp/st", "/tmp/st"));
    try testing.expect(!underRoot("/tmp/state-other/load", "/tmp/st"));
}

test "a firmlinked capture path scopes to the root the caller spelled" {
    // Measured on macOS 15.3.1: every line of a real capture under $HOME arrives as
    // /System/Volumes/Data/Users/..., and the first version of this module — which
    // compared the spellings directly — scoped zero lines and refused every run.
    try testing.expect(underRoot("/System/Volumes/Data/Users/x/s/f", "/Users/x/s"));
    try testing.expect(underRoot("/Users/x/s/f", "/Users/x/s"));
    try testing.expect(underRoot("/System/Volumes/Data/Users/x/s/f", "/System/Volumes/Data/Users/x/s"));
    // The prefix is not a wildcard: a different root still does not match.
    try testing.expect(!underRoot("/System/Volumes/Data/Users/x/other/f", "/Users/x/s"));
    // And a directory that merely begins with the prefix's letters is not stripped.
    try testing.expectEqualStrings("/System/Volumes/DataX/y", physical("/System/Volumes/DataX/y"));
}

test "the handshake predicate is the reader's, not a substring search" {
    // The line that broke the first end-to-end run: a system daemon touching the
    // sentinel, in the firmlinked spelling. It must count as "the capture names this
    // path" only through the same grammar the reader uses.
    const text = "20:55:29.949643  lstat64                                /System/Volumes/Data/Users/i.yoshida/w/state/.sideeye-fsusage-open                          0.000007   fseventsd.80246391\n";
    try testing.expect(capturesPath(text, "/Users/i.yoshida/w/state/.sideeye-fsusage-open"));
    try testing.expect(!capturesPath(text, "/Users/i.yoshida/w/state/.sideeye-fsusage-close"));
    // A line the grammar cannot read does not count, even if the bytes are present.
    try testing.expect(!capturesPath("garbage /Users/i.yoshida/w/state/.sideeye-fsusage-open\n", "/Users/i.yoshida/w/state/.sideeye-fsusage-open"));
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
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
    // The second `unresolved_fd` site: the line carries a descriptor but nothing this
    // module can scope. Refusing here is what keeps a later write on that descriptor
    // from resolving against a path nobody established. Found by a mutation run — the
    // first version of this file had the branch and no test, and killing it SURVIVED.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=6   (_WC_T_______)                        0.000100   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .no_subject => {},
        else => return error.WrongDefect,
    }
}

test "a second tid mutating the judged directory sets child_touched" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The #405 shape: the subject writes through libc, a second thread of execution
    // writes into the same root, and only this witness sees the second one.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=3   /tmp/st/from-parent                   0.000100   subj.111\n" ++
        "10:00:00.000004  write             F=3   B=0x7                                 0.000100   subj.111\n" ++
        "10:00:00.000005  open              F=4   /tmp/st/from-raw-child                0.000100   subj.222\n" ++
        "10:00:00.000006  write             F=4   B=0x9                                 0.000100   subj.222\n" ++
        "10:00:00.000007  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
    try testing.expect(r.defect == null);
    try testing.expect(r.parsed.child_touched);
    try testing.expectEqual(@as(usize, 1), r.parsed.children);
    // The subject's own account is unaffected by the intruder's lines.
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b");
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
}
