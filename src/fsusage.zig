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
    /// A directory-relative operand this reader could not place: `[N]/rel` on a
    /// descriptor never seen opened, `[-2]/rel` with no cwd to resolve against, or a
    /// `..` in the operand, on a call that could change state.
    unresolvable_path: []const u8,
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
        // Not a duration: part of the process name, or the `W` flag. Keep walking left.
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

/// `AT_FDCWD` as fs_usage prints it in a directory-descriptor annotation.
const at_fdcwd: i64 = -2;

/// The operand of a line: a pathname, possibly relative to a directory descriptor.
///
/// Two spellings, both measured. Plain: the last whitespace-separated field starting
/// with `/`. Directory-relative: `[N]` immediately followed by `/` and then the operand
/// — `[69]/libsideeye_shim.so` is relative to descriptor 69, and `[-2]//Users/x/f` is
/// `openat(AT_FDCWD, "/Users/x/f")`, the separator fs_usage inserts sitting in front of
/// an operand that is itself absolute. `mkstemp` on macOS opens through exactly that
/// second form, which is how the reader met it: the one line it exists to catch was the
/// one it could not read.
///
/// Errno brackets (`[  2]`) are followed by spaces, never by `/`, so they do not match.
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

/// An absolute pathname for the line, when one can be had without the descriptor table:
/// the plain form, a directory-relative form whose operand is itself absolute, or an
/// `AT_FDCWD`-relative operand joined to `cwd`. Null for anything that needs a
/// descriptor to resolve. Used where the table does not exist yet (the first pass) and
/// by the handshake.
fn pathOf(arena: std.mem.Allocator, middle: []const u8, cwd: []const u8) ?[]const u8 {
    const op = operandOf(middle) orelse return null;
    if (op.text.len != 0 and op.text[0] == '/') return op.text;
    if (op.dirfd) |d| {
        if (d == at_fdcwd and cwd.len != 0) return joinPath(arena, cwd, op.text) catch null;
    }
    return null;
}

/// CALL name to the class the shim would have recorded. Only calls that can change
/// state are mapped; read-only calls return null and are ignored, matching ADR 0003's
/// predicate on the shim side. `close` is recorded but never a crash point.
/// `fs_usage` prints the `_nocancel` spelling of a call when the target used the
/// variant that is not a cancellation point — `open_nocancel`, `write_nocancel` and
/// eight more that `spike/fsusage/classify.py` enumerates one by one. They are the same
/// call. Stripped in one place rather than listed in three tables, so a spelling this
/// version has not seen still lands on its own class instead of on the unknown-call
/// refusal: the enumeration is what a port drops, and this one dropped nine of ten.
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
        // The rest of the guarded family (#299). SQLite writes through these, and the
        // shim interposes all six as of that change; classifying them here is what
        // makes the oracle able to contradict the shim's account of them.
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
fn isMetadataCall(call_in: []const u8) bool {
    const call = canonicalCall(call_in);
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
fn isReadOnlyCall(call_in: []const u8) bool {
    const call = canonicalCall(call_in);
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

/// Could this line have changed the directory it names? Write-capable opens, mutating
/// classes and metadata writes; not reads, not `close`.
fn mutatingTouch(ln: Line) bool {
    if (isMetadataCall(ln.call)) return true;
    const cls = classOf(ln.call) orelse return false;
    if (cls == .close) return false;
    if (cls == .open) return openIsWriteCapable(ln.middle);
    return true;
}

/// Append unless it is already there. Two copies of this loop had drifted apart inside
/// one function — one with a `break`, one without — which is what a third copy would
/// have cost.
/// Under either spelling of the judged root. `underRoot` already answers false for an
/// empty root, so the `alt.len != 0` guard three call sites carried was always true.
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
        // Sentinels are absolute, so no cwd and no table are needed here.
        const op = operandOf(ln.middle) orelse continue;
        const p = if (op.text.len != 0 and op.text[0] == '/') op.text else continue;
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
    /// Where the subject started, for `openat(AT_FDCWD, relative)`. The strace reader
    /// takes the same thing as `initial_cwd`. Empty means a relative operand cannot be
    /// placed and refuses if it could have changed state.
    cwd: []const u8,
) !Reading {
    var out: Reading = .{ .parsed = .{ .classes = .empty, .names = .empty, .lines = .empty, .metadata_observed = .empty } };
    var fds: FdTable = .{};
    var dup_pending: std.ArrayList(FdKey) = .empty;
    // Set once a relevant thread issues `chdir`/`fchdir`. This reader does not follow
    // the cwd — the strace reader does, through `initial_cwd` plus every successful
    // chdir it sees — so from that point an `AT_FDCWD`-relative operand can no longer
    // be placed by joining it to where the subject *started*, and refuses if it could
    // have changed state. Review constructed the false PASS this closes: cwd `/w`,
    // `chdir("/tmp")`, raw `openat(AT_FDCWD, "st/missed")` — really `/tmp/st/missed`,
    // in the judged directory — joined to `/w` and dropped as out of scope.
    var cwd_moved = false;
    var subject_tid: ?[]const u8 = null;
    // Two threads opened the trace for writing: a shimmed child beside the subject.
    // This backend follows no children (ADR 0031 §2), so it cannot say whose account
    // is whose and refuses rather than picking one.
    var subject_ambiguous = false;
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
        const path = pathOf(arena, ln.middle, cwd) orelse continue;
        // The subject is the thread that opened the trace FOR WRITING. Any line naming
        // the path was the first rule, and on a real capture the last such line was
        // `fseventsd`'s `lstat64` of the file — with a security agent's read-only
        // `open`s before it — so the daemon became the subject and every one of the
        // toy's writes was "a thread other than the subject". Only the shim opens the
        // trace to write; `O_WRONLY|O_CREAT|O_APPEND`, `(_WCA_______X)` on disk.
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
        // A reader that only read the root cannot have altered it through what it read.
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

        const is_subject = std.mem.eql(u8, ln.tid, subject);
        // Asked once per line, not once per test. `classOf` is a linear walk of the
        // call table and `relevant` a linear walk of the touching-thread list; a
        // capture measured at 5,558,556 lines pays for every extra ask.
        const cls_opt = classOf(ln.call);
        const is_relevant = relevant(ln.tid, subject, state_tids.items);
        const fd = fdOf(ln.middle);

        // Complete a pending dup — strictly. fs_usage prints the dup's source and never
        // its result, so the result has to be inferred, and "the next unknown descriptor
        // this thread touches" (the first rule) could hand a state descriptor the
        // out-of-scope bit of an unrelated source: a thread dups its log, then writes
        // on an inherited state descriptor, and that write is filed as the log's. The
        // rule is now the one measured shape and nothing wider: the very next line by
        // the same thread, an inert `fcntl` (`<SETFD>`, the CLOEXEC the shim sets on its
        // fresh descriptor) on a number the table does not know. Anything else drops
        // the pending dup, and the real target's later writes refuse as unresolved —
        // the fail-closed side.
        {
            var i: usize = 0;
            while (i < dup_pending.items.len) {
                const d = dup_pending.items[i];
                if (!std.mem.eql(u8, d.tid, ln.tid)) {
                    i += 1;
                    continue;
                }
                const is_inert_fcntl = std.mem.eql(u8, canonicalCall(ln.call), "fcntl") and fcntlIsInert(ln.middle);
                if (fd) |f| {
                    if (is_inert_fcntl and fds.get(.{ .tid = ln.tid, .fd = f }) == null and !std.mem.eql(u8, d.fd, f)) {
                        if (fds.get(.{ .tid = ln.tid, .fd = d.fd })) |src_in_state|
                            try fds.set(arena, .{ .tid = ln.tid, .fd = f }, src_in_state);
                    }
                }
                // Consumed either way: the window was this one line.
                _ = dup_pending.swapRemove(i);
            }
        }

        if (std.mem.eql(u8, canonicalCall(ln.call), "fcntl")) {
            if (fcntlDuplicates(ln.middle)) {
                // fs_usage prints the SOURCE descriptor and not the result, so the
                // mapping is completed on the next line this thread issues on a
                // descriptor the table does not know — which on a real capture is the
                // shim's own trace: `open F=3`, `fcntl F=3 [22] <DUPFD>` (the 900 floor
                // fails), `fcntl F=3 <DUPFD>`, then `fcntl F=200 <SETFD>`, `close F=3`,
                // `write F=200`. The first version of this file did not follow the dup
                // and refused every run on the shim's first trace write.
                if (!hasErrno(ln.middle)) {
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
                    if (fds.get(.{ .tid = ln.tid, .fd = key })) |in| dir_scope = in else path_unresolvable = true;
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
            // Not an operation (ADR 0003), but a directory opened read-only is what
            // later `openat([N], ...)` lines resolve through, so it is remembered when
            // it can be placed. Unplaceable read-only opens are simply not remembered;
            // whatever resolves through them later refuses on its own.
            if (fd) |f| {
                if (scope_known) |in| {
                    if (is_subject or in) try fds.set(arena, .{ .tid = ln.tid, .fd = f }, in);
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
                // Only descriptors whose later use could matter are remembered. The
                // capture is system-wide: one measured run held 5,558,556 lines,
                // 26,228 distinct (tid, fd) pairs — and 22 lines touching the judged
                // directory. Anything the subject opens is kept (its own descriptors
                // decide its account), and anything under the root whoever opened it
                // (that is what `child_touched` is read from).
                const keep = is_subject or (scope_known orelse false);
                if (keep) {
                    if (fd) |f| {
                        if (scope_known) |in| {
                            try fds.set(arena, .{ .tid = ln.tid, .fd = f }, in);
                        } else if (is_relevant) {
                            // A write-capable open this reader cannot place, by a thread
                            // whose account matters: a descriptor into who-knows-where.
                            out.defect = .{ .unresolvable_path = raw };
                            return out;
                        }
                    }
                }
            } else if (cls == .close) {
                if (fd) |f| fds.clear(.{ .tid = ln.tid, .fd = f });
                continue;
            }
        }

        // The shim's own trace writes and the sentinels are the observer's shadow, not
        // the target's work — skipped here, AFTER the descriptor bookkeeping above, so
        // the shim's `open F=3 trace.bin` is in the table for the dup to inherit from.
        // The line still counts toward `lines_seen`.
        if (path) |p| {
            if (samePath(p, trace_path)) continue;
            if (sentinel_start.len != 0 and samePath(p, sentinel_start)) continue;
            if (sentinel_end.len != 0 and samePath(p, sentinel_end)) continue;
        }

        // Is this line about the judged directory?
        var in_scope = false;
        if (scope_known) |in| {
            in_scope = in;
        } else if (path_unresolvable) {
            if (is_relevant) {
                if (cls_opt) |c| {
                    if (c != .close) {
                        out.defect = .{ .unresolvable_path = raw };
                        return out;
                    }
                }
            }
            continue;
        } else if (fd) |f| {
            // Pathless: `write F=3 B=0x7`. Resolve through the open, or refuse.
            const known = fds.get(.{ .tid = ln.tid, .fd = f }) orelse {
                // Only calls that could change state make an unresolved descriptor a
                // hole; a read on an inherited descriptor is not this module's problem.
                if (cls_opt) |c| {
                    if (c != .close and is_relevant) {
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
            // The condition #405 is about, and the reason the capture is unfiltered:
            // a process other than the subject mutated the judged directory, and this
            // witness is the only one that sees it whether or not the shim was loaded.
            out.parsed.child_touched = true;
            try appendUnique(arena, &other_tids, ln.tid);
            out.parsed.children = other_tids.items.len;
            continue;
        }

        try out.parsed.classes.append(arena, cls);
        // fs_usage's own spelling of the call, which this reader already has and used to
        // drop — a divergence refusal names it the same way the strace side does (#337).
        try out.parsed.names.append(arena, ln.call);
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


test "fd and operand come out of the middle, in both spellings" {
    const ln = parseLine(cap_line).?;
    try testing.expectEqualStrings("3", fdOf(ln.middle).?);
    const plain = operandOf(ln.middle).?;
    try testing.expect(plain.dirfd == null);
    try testing.expectEqualStrings("/tmp/st/load", plain.text);
    // The directory-relative spelling, verbatim: AT_FDCWD and an absolute operand.
    const rel = operandOf("F=3        (RWC__E______)  [-2]//tmp/st/tmp-oepJXu").?;
    try testing.expectEqual(@as(i64, -2), rel.dirfd.?);
    try testing.expectEqualStrings("/tmp/st/tmp-oepJXu", rel.text);
    // A descriptor-relative operand keeps its relative text.
    const viafd = operandOf("F=6        (_WC_T_______)  [5]/inside").?;
    try testing.expectEqual(@as(i64, 5), viafd.dirfd.?);
    try testing.expectEqualStrings("inside", viafd.text);
    // An errno bracket is not a directory descriptor.
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        // A write-capable open with no operand at all: nothing to place it by.
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
}

test "a truncated read-only line from the subject is not a hole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // Verbatim from the run that refused: dyld probing a framework path longer than the
    // display width, from the subject's own thread. 353 of these in one capture.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:23:17.677297  stat64                 [  2]           /System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/CoreServices.framework>>>                                                                              0.000001   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
}

test "a truncated mutating line from the subject still refuses" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The control for the test above: the same cut on a call that CAN change state is
    // the hole the rule exists for.
    const text =
        "10:00:00.000001  open              F=9   /work/trace.bin                       0.000100   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                    0.000100   subj.111\n" ++
        "10:00:00.000003  unlink                                 /System/Volumes/Data/Users/x/some/very/long/dir/na>>>                                     0.000001   subj.111\n" ++
        "10:00:00.000004  open              F=2   /tmp/st/sentinel-b                    0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .truncated => {},
        else => return error.WrongDefect,
    }
}

test "the shim's dup of its own trace descriptor is followed, and a daemon reading the trace is not the subject" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The shape of a real capture, line for line: fseventsd stats the trace file, a
    // security agent opens it read-only, then the subject opens it for writing, fails
    // to dup to the 900 floor, dups to 200, closes 3 and writes through 200 — and then
    // does its one real operation on the judged directory.
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect == null);
    try testing.expectEqualStrings("111", r.subject_tid.?);
    try testing.expect(!r.parsed.child_touched);
    // Two, not three: `close` is a lifecycle op the shim records and the strace oracle
    // drops from the compared sequence (`oracle.zig`, `if (cls == .close) continue`),
    // and the two accounts have to be shaped alike. This test first asserted three and
    // was wrong; the real capture said two and the strace reader said why.
    try testing.expectEqual(@as(usize, 2), r.parsed.classes.items.len);
    try testing.expectEqual(contract.OpClass.open, r.parsed.classes.items[0]);
    try testing.expectEqual(contract.OpClass.write, r.parsed.classes.items[1]);
    // The three lists are index-aligned, and a divergence refusal reads `names[i]` for
    // the operation `classes[i]` diverged on (#337). Only `classes` was ever asserted
    // here, so an append that drifted would have gone unnoticed on this side — the
    // strace reader pins the same property for its own two lists.
    try testing.expectEqual(r.parsed.classes.items.len, r.parsed.names.items.len);
    try testing.expectEqual(r.parsed.classes.items.len, r.parsed.lines.items.len);
    // fs_usage's own spelling, not a normalised one: a reader who goes back to the
    // capture has to be able to find the line again.
    try testing.expectEqualStrings("open", r.parsed.names.items[0]);
    try testing.expectEqualStrings("write", r.parsed.names.items[1]);
}

test "a neighbour that only read the judged directory is not made relevant by it" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // Verbatim shape of the refusal: a security agent opens a state file read-only to
    // scan it, then writes to a log descriptor it held before the capture began.
    const text =
        "10:36:22.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:36:22.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:36:22.000003  open              F=17       (R___________)  /tmp/st/keep                      0.000072   wdavdaemon_enterprise.555\n" ++
        "10:36:22.388237  write             F=22  B=0xad                                                 0.000071   wdavdaemon_enterprise.555\n" ++
        "10:36:22.000005  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect == null);
    try testing.expect(!r.parsed.child_touched);
}

test "a neighbour that opened the judged directory for writing is relevant, and its unknown write is a hole" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // The control: the same neighbour, but the open under the root was write-capable.
    // That descriptor is tracked; a second, unknown one it then writes on is exactly the
    // descriptor-into-the-root-we-never-saw-opened that the rule exists for.
    const text =
        "10:36:22.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:36:22.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:36:22.000003  open              F=17       (_W__________)  /tmp/st/keep                      0.000072   neighbour.555\n" ++
        "10:36:22.388237  write             F=22  B=0xad                                                 0.000071   neighbour.555\n" ++
        "10:36:22.000005  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    // Verbatim from the run that refused: the creation mkstemp issues past the shim.
    // `[-2]` is AT_FDCWD and the `//` is fs_usage's separator before an absolute operand.
    const text =
        "10:39:10.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:39:10.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:39:10.143604  openat            F=3        (RWC__E______)  [-2]//tmp/st/tmp-oepJXu                0.000360   subj.111\n" ++
        "10:39:10.143700  write             F=3   B=0x3                                                  0.000004   subj.111\n" ++
        "10:39:10.143701  close             F=3                                                          0.000002   subj.111\n" ++
        "10:39:10.200000  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect != null);
    switch (r.defect.?) {
        .unresolvable_path => {},
        else => return error.WrongDefect,
    }
    // With a cwd it resolves, and lands outside the root.
    const r2 = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/elsewhere");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/tmp/work");
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
    // Review's construction: started in /tmp/work, moved to /tmp, then a raw
    // openat(AT_FDCWD, "st/missed") — really /tmp/st/missed, inside the judged
    // directory — which a join to the starting cwd would have placed at
    // /tmp/work/st/missed and dropped.
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  chdir                                  /tmp                                    0.000010   subj.111\n" ++
        "10:00:00.000004  openat            F=6        (_WC_T_______)  [-2]/st/missed                    0.000010   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "/tmp/work");
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
    // Review's construction: the subject dups a descriptor that points outside the
    // root, then its next line is a write on an inherited descriptor nobody opened. The
    // first rule mapped that descriptor to the out-of-scope source and dropped the
    // write; the write must instead be the unresolved hole it is.
    const text =
        "10:00:00.000001  open              F=9        (_WCA_______X)  /work/trace.bin                   0.000010   subj.111\n" ++
        "10:00:00.000002  open              F=1   /tmp/st/sentinel-a                                     0.000100   subj.111\n" ++
        "10:00:00.000003  open              F=4        (_W__________)  /var/log/mine                     0.000010   subj.111\n" ++
        "10:00:00.000004  fcntl             F=4   <DUPFD>                                                0.000003   subj.111\n" ++
        "10:00:00.000005  write             F=7   B=0x3                                                  0.000004   subj.111\n" ++
        "10:00:00.000006  open              F=2   /tmp/st/sentinel-b                                     0.000100   subj.111\n";
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
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
    const r = try read(a, text, "/tmp/st", "", "/work/trace.bin", "/tmp/st/sentinel-a", "/tmp/st/sentinel-b", "");
    try testing.expect(r.defect == null);
    try testing.expectEqual(@as(usize, 0), r.parsed.classes.items.len);
}
