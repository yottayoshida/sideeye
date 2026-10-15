const std = @import("std");
const contract = @import("contract");
const posix = @import("../posix.zig");
const trace = @import("trace.zig");

const Allocator = std.mem.Allocator;
const Op = trace.Op;

pub const Entry = struct {
    rel: []const u8,
    kind: posix.Kind,
    content: []const u8,
    /// The read, write and execute bits the walk read for a file or a directory, which `restore`
    /// puts back (ADR 0109); null for a symlink or when nothing was read, and `restore` then
    /// leaves the mode it created with. Not 0 by default — an entry built by hand would come
    /// back 0000. Not judged.
    mode: ?u16 = null,
};

/// Every comparison `find` makes goes through `compareRel` below, which is also the
/// primitive a linear scan would use. That matters: a counter placed only inside a binary
/// search's comparator would read zero for a linear implementation, and the mutation that
/// matters most here — putting the linear scan back — would pass a "comparisons are
/// logarithmic" assertion by never incrementing it.
var rel_comparisons: usize = 0;

fn compareRel(key: []const u8, e: Entry) std.math.Order {
    rel_comparisons += 1;
    return std.mem.order(u8, key, e.rel);
}

/// A value rather than a panic. `find` is called from inside loops, so this cannot run
/// there — an O(n) check per lookup restores the quadratic cost the binary search exists
/// to remove, and `std.debug.assert` would not have made it free either, since it is
/// generated in Debug *and* ReleaseSafe and the release artifacts are ReleaseSafe. It runs
/// once at each producer boundary instead.
pub const OrderProblem = enum { out_of_order, duplicate };

pub fn validateSortedUnique(entries: []const Entry) ?OrderProblem {
    if (entries.len < 2) return null;
    for (entries[1..], 0..) |e, i| {
        switch (std.mem.order(u8, entries[i].rel, e.rel)) {
            .lt => {},
            .eq => return .duplicate,
            .gt => return .out_of_order,
        }
    }
    return null;
}

pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry),

    pub fn deinit(self: *Snapshot) void {
        self.arena.deinit();
    }

    /// (#262). The order it now relies on is a module invariant maintained by the
    /// producers, not something the type can enforce: `entries` is a public, mutable
    /// `ArrayList`, so a caller that appends out of order gets a wrong answer rather than
    /// a refusal. `validateSortedUnique` is what makes that a caught mistake at the two
    /// places snapshots are built.
    pub fn find(self: Snapshot, rel: []const u8) ?Entry {
        const idx = std.sort.binarySearch(Entry, self.entries.items, rel, compareRel) orelse return null;
        return self.entries.items[idx];
    }
};

pub fn firstUnsupportedEntry(snap: Snapshot) ?[]const u8 {
    for (snap.entries.items) |e| {
        if (e.kind == .other or e.kind == .missing) return e.rel;
    }
    return null;
}

test "firstUnsupportedEntry flags exactly the kinds restore cannot recreate" {
    var snap = Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer snap.deinit();
    const a = snap.arena.allocator();

    try snap.entries.append(a, .{ .rel = "a.txt", .kind = .file, .content = "x" });
    try snap.entries.append(a, .{ .rel = "d", .kind = .dir, .content = "" });
    try snap.entries.append(a, .{ .rel = "l", .kind = .symlink, .content = "a.txt" });
    try std.testing.expectEqual(@as(?[]const u8, null), firstUnsupportedEntry(snap));

    try snap.entries.append(a, .{ .rel = "m-pipe", .kind = .other, .content = "" });
    try snap.entries.append(a, .{ .rel = "z-sock", .kind = .other, .content = "" });
    try std.testing.expectEqualStrings("m-pipe", firstUnsupportedEntry(snap).?);

    var snap2 = Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer snap2.deinit();
    const a2 = snap2.arena.allocator();
    try snap2.entries.append(a2, .{ .rel = "ghost", .kind = .missing, .content = "" });
    try std.testing.expectEqualStrings("ghost", firstUnsupportedEntry(snap2).?);
}

/// `rel` borrows from whichever snapshot holds the entry, so a `Difference` is only
/// valid while both snapshots are: the caller renders it before either is deinited.
pub const Difference = struct {
    rel: []const u8,
    how: How,

    pub const How = enum {
        only_in_first,
        only_in_second,
        kind_differs,
        content_differs,
    };
};

pub const DiffCount = struct {
    stored: usize,
    /// Every difference found, whether or not it fit. A caller that reports `stored`
    /// as if it were the total would understate a split on any tree that overflows
    /// the buffer — the counting continues past the buffer for exactly that reason.
    total: usize,

    pub fn equal(self: DiffCount) bool {
        return self.total == 0;
    }
};

pub fn diffSnapshots(first: Snapshot, second: Snapshot, out: []Difference) DiffCount {
    return diffSnapshotsExcept(first, second, out, &.{});
}

pub fn diffSnapshotsExcept(first: Snapshot, second: Snapshot, out: []Difference, scratch: []const []const u8) DiffCount {
    var count: DiffCount = .{ .stored = 0, .total = 0 };
    var i: usize = 0;
    var j: usize = 0;
    const fs = first.entries.items;
    const ss = second.entries.items;
    while (i < fs.len or j < ss.len) {
        const how: Difference.How, const rel: []const u8 = blk: {
            if (i >= fs.len) {
                defer j += 1;
                break :blk .{ .only_in_second, ss[j].rel };
            }
            if (j >= ss.len) {
                defer i += 1;
                break :blk .{ .only_in_first, fs[i].rel };
            }
            switch (std.mem.order(u8, fs[i].rel, ss[j].rel)) {
                .lt => {
                    defer i += 1;
                    break :blk .{ .only_in_first, fs[i].rel };
                },
                .gt => {
                    defer j += 1;
                    break :blk .{ .only_in_second, ss[j].rel };
                },
                .eq => {
                    const f = fs[i];
                    const s = ss[j];
                    i += 1;
                    j += 1;
                    if (f.kind != s.kind) break :blk .{ .kind_differs, f.rel };
                    if (!std.mem.eql(u8, f.content, s.content)) break :blk .{ .content_differs, f.rel };
                    continue;
                },
            }
        };
        if (scratchMatches(scratch, rel)) continue;
        count.total += 1;
        if (count.stored < out.len) {
            out[count.stored] = .{ .rel = rel, .how = how };
            count.stored += 1;
        }
    }
    return count;
}

pub const Unaccounted = struct {
    rel: []const u8,
    how: Difference.How,
    /// A record named the path, but none of the naming records can have put the bytes the
    /// path is left holding (an `open`, an `fsync`, the source of a rename).
    named_without_bytes: bool = false,
};

pub const Reconciled = struct {
    stored: usize,
    total: usize,
    by_rename_prefix: usize,

    pub fn clean(self: Reconciled) bool {
        return self.total == 0;
    }
};

pub fn relUnderRoot(path: []const u8, root: []const u8, alt: []const u8) ?[]const u8 {
    for ([_][]const u8{ root, alt }) |r| {
        if (r.len == 0) continue;
        if (!contract.isInsideDir(path, r)) continue;
        const d = std.mem.trimEnd(u8, r, "/");
        if (path.len <= d.len + 1) return "";
        return path[d.len + 1 ..];
    }
    return null;
}

pub const Link = struct { rel: []const u8, target: []const u8 };

const max_link_hops = 8;

fn appendInto(buf: []u8, n: usize, piece: []const u8) ?usize {
    if (n + piece.len > buf.len) return null;
    @memcpy(buf[n .. n + piece.len], piece);
    return n + piece.len;
}

fn substituteOnce(
    rel: []const u8,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
) ?[]const u8 {
    var chosen: ?Link = null;
    for (links) |l| {
        if (l.rel.len == 0 or l.rel.len > rel.len) continue;
        if (!std.mem.startsWith(u8, rel, l.rel)) continue;
        if (rel.len != l.rel.len and rel[l.rel.len] != '/') continue;
        if (chosen != null) return null;
        chosen = l;
    }
    const link = chosen orelse return null;

    // directory. The segments are then folded the same way either way — an earlier
    // revision folded only the relative branch, and `cur -> /tmp/s/v1/../v2` came out as
    // `v1/../v2`, which matches no snapshot `rel` because those are built by walking the
    // tree and never contain `..`. The shim normalises what it records
    // (`contract.normalizePath`), so the two sides only meet if this side folds too.
    var n: usize = 0;
    var segments = link.target;
    if (link.target.len > 0 and link.target[0] == '/') {
        segments = relUnderRoot(link.target, root, alt) orelse return null;
    } else {
        const parent = if (std.mem.lastIndexOfScalar(u8, link.rel, '/')) |i| link.rel[0..i] else "";
        n = appendInto(scratch, n, parent) orelse return null;
    }
    var it = std.mem.tokenizeScalar(u8, segments, '/');
    while (it.next()) |seg| {
        if (std.mem.eql(u8, seg, ".")) continue;
        if (std.mem.eql(u8, seg, "..")) {
            if (n == 0) return null;
            n = std.mem.lastIndexOfScalar(u8, scratch[0..n], '/') orelse 0;
            continue;
        }
        if (n != 0) n = appendInto(scratch, n, "/") orelse return null;
        n = appendInto(scratch, n, seg) orelse return null;
    }

    const tail = rel[link.rel.len..];
    if (tail.len != 0) {
        if (n != 0) n = appendInto(scratch, n, "/") orelse return null;
        n = appendInto(scratch, n, std.mem.trimStart(u8, tail, "/")) orelse return null;
    }
    if (std.mem.eql(u8, scratch[0..n], rel)) return null;
    return scratch[0..n];
}

/// The substitution reads the snapshots, never the filesystem: the tree at reconcile
/// time is not the tree the operation ran against, and resolving live would answer about
/// the wrong one.
fn resolveThroughLinks(
    rel: []const u8,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
) []const u8 {
    if (links.len == 0) return rel;
    // Two halves, used alternately: `cur` is a slice into the half written last, and
    // `substituteOnce` reads it while writing the result. Handing it the same half would
    // have it overwrite its own input — the chain `a -> b -> c` is where that shows up,
    // and a single-hop test would not have caught it.
    const half = scratch.len / 2;
    if (half == 0) return rel;
    const halves = [2][]u8{ scratch[0..half], scratch[half..] };
    var cur = rel;
    var hops: usize = 0;
    while (hops < max_link_hops) : (hops += 1) {
        cur = substituteOnce(cur, links, root, alt, halves[hops % 2]) orelse return cur;
    }
    return cur;
}

fn actsOnLastComponent(class: contract.OpClass) bool {
    return switch (class) {
        .unlink, .rename, .link, .symlink, .rmdir, .mkdir => true,
        else => false,
    };
}

/// link (R1 of #682/#683's diff). Resolving every component made a record on a link stand
/// for the link's target: `symlink("pkg/f", "new")`, recorded at `new`, read as naming
/// `pkg/f` — so a run that only makes links counted the files they point at as touched, and
/// a change at `pkg/f` that nothing recorded was accounted for by the record that made the
/// link. For a class that acts on the last component, only the directories above it are
/// resolved and the name is put back. `joined` holds that result; on overflow the literal
/// spelling is returned, which matches less rather than more.
fn resolveForRecord(
    lexical: []const u8,
    class: contract.OpClass,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
    joined: []u8,
) []const u8 {
    if (!actsOnLastComponent(class)) return resolveThroughLinks(lexical, links, root, alt, scratch);
    const slash = std.mem.lastIndexOfScalar(u8, lexical, '/') orelse return lexical;
    const parent = resolveThroughLinks(lexical[0..slash], links, root, alt, scratch);
    const base = lexical[slash + 1 ..];
    if (parent.len + 1 + base.len > joined.len) return lexical;
    @memcpy(joined[0..parent.len], parent);
    joined[parent.len] = '/';
    @memcpy(joined[parent.len + 1 ..][0..base.len], base);
    return joined[0 .. parent.len + 1 + base.len];
}

/// The direction is deliberate and one-way. "No operation names this path" is evidence
/// the account is incomplete; "every path is named" is NOT evidence it is complete —
/// a failed syscall leaves a record with no change behind it, and a subtree renamed in
/// from outside is accounted for wholesale. The caller refuses on the first, and must
/// not read the absence of the first as the second.
///
/// `ops` should be every recorded operation, not only the subject's mutating ones: a
/// child that left a record has explained its change, and *who* performed it is a
/// different detector's question (`child_touched_state_dir`).
///
/// A difference that leaves a regular file holding bytes is accounted for only by a record
/// that can have put those bytes there: a write, the destination of a rename or a link, the
/// source of a link whose other name a recorded write names, or a truncate whose result is a
/// prefix of the old bytes followed by zeros. Every other difference — a file left empty, a
/// path removed, a directory, a path `scratch_paths` declares — is accounted for by any record
/// that names it, `open` included, so a created-and-never-written file still explains itself
/// (ADR 0032 §2).
pub fn reconcile(
    diffs: []const Difference,
    ops: []const Op,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    initial: Snapshot,
    final: Snapshot,
    scratch_paths: []const []const u8,
    scratch: []u8,
    out: []Unaccounted,
) Reconciled {
    var res: Reconciled = .{ .stored = 0, .total = 0, .by_rename_prefix = 0 };
    var joined: [contract.max_path]u8 = undefined;
    for (diffs) |d| {
        const left = if (scratchMatches(scratch_paths, d.rel)) null else bytesLeft(d, initial, final);
        var named = false;
        var named_without_bytes = false;
        var by_prefix = false;
        for (ops) |op| {
            if (op.class.isMarker() or op.class.isThreadSync()) continue;
            const ends = [2][]const u8{ op.path, op.aux };
            for (ends, 0..) |p, end| {
                if (p.len == 0) continue;
                const lexical = relUnderRoot(p, root, alt) orelse continue;
                const rel = resolveForRecord(lexical, op.class, links, root, alt, scratch, &joined);
                // BOTH spellings, because a path can name a link or name through it and
                // the two answers are different objects. `unlink("cur")` removes the link
                // and the difference is at `cur`; `unlink("cur/f")` removes a file and the
                // difference is at `v1/f`. Comparing only the substituted form erased the
                // first — measured after the substitution was added: `unlink(cur)` and a
                // `symlink`+`rename` generation swap both went PASS exit 0 → UNKNOWN,
                // naming `cur`. That is the same regression the substitution was written
                // to fix, one level up, and the second revision of this code introduced it.
                if (std.mem.eql(u8, lexical, d.rel) or std.mem.eql(u8, rel, d.rel)) {
                    if (left) |b| if (!canPutBytes(op, end, b, ops, root, alt)) {
                        named_without_bytes = true;
                        continue;
                    };
                    named = true;
                    break;
                }
                if (op.class == .rename and
                    relUnderRoot(op.path, root, alt) == null and
                    d.rel.len > rel.len and std.mem.startsWith(u8, d.rel, rel) and
                    d.rel[rel.len] == '/')
                {
                    by_prefix = true;
                }
            }
            if (named) break;
        }
        if (named) continue;
        if (by_prefix) {
            res.by_rename_prefix += 1;
            continue;
        }
        res.total += 1;
        if (res.stored < out.len) {
            out[res.stored] = .{ .rel = d.rel, .how = d.how, .named_without_bytes = named_without_bytes };
            res.stored += 1;
        }
    }
    return res;
}

const BytesLeft = struct { old: []const u8, new: []const u8 };

fn bytesLeft(d: Difference, initial: Snapshot, final: Snapshot) ?BytesLeft {
    if (d.how == .only_in_first) return null;
    const after = final.find(d.rel) orelse return null;
    if (after.kind != .file or after.content.len == 0) return null;
    const before: []const u8 = if (initial.find(d.rel)) |b| (if (b.kind == .file) b.content else "") else "";
    return .{ .old = before, .new = after.content };
}

/// The source of a rename is not counted, nor the source of a link unless its other name was
/// written: a target that moves or links `cfg` aside and puts new bytes at `cfg` through a call
/// nothing records would otherwise be accounted for by the move.
fn canPutBytes(op: Op, end: usize, b: BytesLeft, ops: []const Op, root: []const u8, alt: []const u8) bool {
    return switch (op.class) {
        .write => true,
        .rename => end == 1,
        .link => end == 1 or writtenAfter(ops, op, root, alt),
        .truncate => isPrefixThenZeros(b.old, b.new),
        else => false,
    };
}

fn writtenAfter(ops: []const Op, link: Op, root: []const u8, alt: []const u8) bool {
    const want = relUnderRoot(link.aux, root, alt) orelse return false;
    for (ops) |o| {
        if (o.class != .write or o.seq <= link.seq) continue;
        const got = relUnderRoot(o.path, root, alt) orelse continue;
        if (std.mem.eql(u8, got, want)) return true;
    }
    return false;
}

fn isPrefixThenZeros(old: []const u8, new: []const u8) bool {
    const k = std.mem.indexOfDiff(u8, old, new) orelse return true;
    for (new[@min(k, new.len)..]) |c| if (c != 0) return false;
    return true;
}

pub fn collectLinks(a: Allocator, first: Snapshot, second: Snapshot, out: *std.ArrayList(Link)) !void {
    for ([_]Snapshot{ first, second }) |snap| {
        for (snap.entries.items) |e| {
            if (e.kind != .symlink) continue;
            var seen = false;
            for (out.items, 0..) |l, i| {
                if (!std.mem.eql(u8, l.rel, e.rel)) continue;
                seen = true;
                if (!std.mem.eql(u8, l.target, e.content)) _ = out.orderedRemove(i);
                break;
            }
            if (!seen) try out.append(a, .{ .rel = e.rel, .target = e.content });
        }
    }
}

/// **Two classes never count, and the ancestor rule is a rename's alone.** Each of the
/// three is a measured way for this answer to say "touched" about a path no crash world
/// could show changed, which turns an exploration where nothing could fail back into a
/// PASS (R1 of the plan):
/// - `fsync` changes nothing under the process-crash model — every completed write is
///   already durable — so a world killed in front of it holds what the world before it held.
/// - `mkdir` on a judged path cannot succeed while that path is there, and a judged path is
///   there before and after the operation; for it to be created again, something else must
///   first have named it (or renamed a directory above it), and that operation counts. The
///   shim records a `mkdir` before it knows the answer, so `os.makedirs(…, exist_ok=True)`
///   leaves one per existing component.
/// - Above a judged path, only a rename moves it. `unlink` and `open` fail on a directory,
///   `rmdir` needs it empty — its children named first — and a parent's `fsync` or `mkdir`
///   is the commonest record of all: matched as an ancestor, it would make every path
///   beneath it "touched".
pub fn namedByMutation(
    rel: []const u8,
    ops: []const Op,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
) bool {
    var joined: [contract.max_path]u8 = undefined;
    for (ops) |op| {
        if (!op.class.isKillPoint()) continue;
        if (op.class == .fsync or op.class == .mkdir) continue;
        const ends = [2][]const u8{ op.path, op.aux };
        for (ends) |p| {
            if (p.len == 0) continue;
            const lexical = relUnderRoot(p, root, alt) orelse continue;
            const resolved = resolveForRecord(lexical, op.class, links, root, alt, scratch, &joined);
            if (std.mem.eql(u8, lexical, rel) or std.mem.eql(u8, resolved, rel)) return true;
            if (op.class == .rename and (isStrictAncestor(lexical, rel) or isStrictAncestor(resolved, rel))) return true;
        }
    }
    return false;
}

fn isStrictAncestor(dir: []const u8, rel: []const u8) bool {
    return dir.len > 0 and rel.len > dir.len and std.mem.startsWith(u8, rel, dir) and rel[dir.len] == '/';
}

test "namedByMutation: a write, a truncating open and either end of a rename name a judged path" {
    var scratch: [2048]u8 = undefined;
    const root = "/tmp/s";
    const write = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg.json", .aux = "" }};
    try std.testing.expect(namedByMutation("cfg.json", &write, &.{}, root, "", &scratch));
    const open = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg.json", .aux = "" }};
    try std.testing.expect(namedByMutation("cfg.json", &open, &.{}, root, "", &scratch));
    const swap = [_]Op{
        .{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg.json.tmp", .aux = "" },
        .{ .class = .rename, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/cfg.json.tmp", .aux = "/tmp/s/cfg.json" },
    };
    try std.testing.expect(namedByMutation("cfg.json", &swap, &.{}, root, "", &scratch));
    const alt_write = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/private/tmp/s/cfg.json", .aux = "" }};
    try std.testing.expect(namedByMutation("cfg.json", &alt_write, &.{}, root, "/private/tmp/s", &scratch));
    // A judged path nothing named: the control the assertions above are measured against.
    try std.testing.expect(!namedByMutation("keep.txt", &swap, &.{}, root, "", &scratch));
}

test "namedByMutation: fsync and mkdir never count, and only a rename counts from above" {
    var scratch: [2048]u8 = undefined;
    const root = "/tmp/s";
    const ops = [_]Op{
        .{ .class = .mkdir, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .class = .mkdir, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/sub", .aux = "" },
        .{ .class = .fsync, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/sub/keep.txt", .aux = "" },
        .{ .class = .fsync, .seq = 4, .pid = 7, .tid = 7, .path = "/tmp/s/sub", .aux = "" },
        .{ .class = .open, .seq = 5, .pid = 7, .tid = 7, .path = "/tmp/s/sub/new.txt", .aux = "" },
        .{ .class = .write, .seq = 6, .pid = 7, .tid = 7, .path = "/tmp/s/sub/new.txt", .aux = "" },
        .{ .class = .close, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/sub/keep.txt", .aux = "" },
    };
    try std.testing.expect(!namedByMutation("sub/keep.txt", &ops, &.{}, root, "", &scratch));
    try std.testing.expect(!namedByMutation("sub", &ops, &.{}, root, "", &scratch));
    const moved = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/sub", .aux = "/tmp/s/old" }};
    try std.testing.expect(namedByMutation("sub/keep.txt", &moved, &.{}, root, "", &scratch));
    const sibling = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/su", .aux = "/tmp/s/sv" }};
    try std.testing.expect(!namedByMutation("sub/keep.txt", &sibling, &.{}, root, "", &scratch));
    const whole = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "/tmp/t" }};
    try std.testing.expect(!namedByMutation("sub/keep.txt", &whole, &.{}, root, "", &scratch));
    const unl = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/sub", .aux = "" }};
    try std.testing.expect(!namedByMutation("sub/keep.txt", &unl, &.{}, root, "", &scratch));
}

test "namedByMutation: an operation spelled through an interior symlink names what it reached" {
    var scratch: [2048]u8 = undefined;
    const root = "/tmp/s";
    const links = [_]Link{.{ .rel = "cur", .target = "v1" }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    try std.testing.expect(namedByMutation("v1/f", &ops, &links, root, "", &scratch));
    const ren = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/g", .aux = "/tmp/s/cur/f" }};
    try std.testing.expect(namedByMutation("v1/f", &ren, &links, root, "", &scratch));
    const outside = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/other/v1/f", .aux = "" }};
    try std.testing.expect(!namedByMutation("v1/f", &outside, &links, root, "", &scratch));
}

test "namedByMutation: an operation on a link itself does not name what the link points at (R1 of the diff)" {
    var scratch: [2048]u8 = undefined;
    const root = "/tmp/s";
    const made = [_]Link{.{ .rel = "new", .target = "pkg/f" }};
    const symlink_op = [_]Op{.{ .class = .symlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/new", .aux = "" }};
    try std.testing.expect(!namedByMutation("pkg/f", &symlink_op, &made, root, "", &scratch));
    const to_dir = [_]Link{.{ .rel = "cur", .target = "v1" }};
    const unlink_op = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur", .aux = "" }};
    try std.testing.expect(!namedByMutation("v1", &unlink_op, &to_dir, root, "", &scratch));
    const rename_op = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur", .aux = "/tmp/s/old" }};
    try std.testing.expect(!namedByMutation("v1/f", &rename_op, &to_dir, root, "", &scratch));
    const link_op = [_]Op{.{ .class = .link, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/new", .aux = "/tmp/s/new2" }};
    try std.testing.expect(!namedByMutation("pkg/f", &link_op, &made, root, "", &scratch));
    const rmdir_op = [_]Op{.{ .class = .rmdir, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur", .aux = "" }};
    try std.testing.expect(!namedByMutation("v1", &rmdir_op, &to_dir, root, "", &scratch));
    const open_op = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/new", .aux = "" }};
    try std.testing.expect(namedByMutation("pkg/f", &open_op, &made, root, "", &scratch));
    const write_op = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/new", .aux = "" }};
    try std.testing.expect(namedByMutation("pkg/f", &write_op, &made, root, "", &scratch));
    const inner = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    try std.testing.expect(namedByMutation("v1/f", &inner, &to_dir, root, "", &scratch));
}

fn reconcileIn(
    diffs: []const Difference,
    ops: []const Op,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    out: []Unaccounted,
) Reconciled {
    var scratch: [2048]u8 = undefined;
    const empty: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    return reconcile(diffs, ops, links, root, alt, empty, empty, &.{}, &scratch, out);
}

fn reconcileWithContents(
    diffs: []const Difference,
    ops: []const Op,
    before: []const Entry,
    after: []const Entry,
    out: []Unaccounted,
) Reconciled {
    return reconcileWithContentsExcept(diffs, ops, before, after, &.{}, out);
}

fn reconcileWithContentsExcept(
    diffs: []const Difference,
    ops: []const Op,
    before: []const Entry,
    after: []const Entry,
    scratch_paths: []const []const u8,
    out: []Unaccounted,
) Reconciled {
    var scratch: [2048]u8 = undefined;
    const initial: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .{ .items = @constCast(before), .capacity = before.len, .pointer_stability = .{} } };
    const final: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .{ .items = @constCast(after), .capacity = after.len, .pointer_stability = .{} } };
    return reconcile(diffs, ops, &.{}, "/tmp/s", "", initial, final, scratch_paths, &scratch, out);
}

test "reconcile: a file left holding bytes is accounted for only by a record that can have put them there (#814)" {
    const changed = [_]Difference{.{ .rel = "key.txt", .how = .content_differs }};
    const old = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD\n" }};
    const new = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "NEW-CONTENT\n" }};
    var buf: [2]Unaccounted = undefined;

    // The reflink `cp` and the io_uring write: an `open(O_TRUNC)` is all either witness records.
    const opened = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" }};
    const r_open = reconcileWithContents(&changed, &opened, &old, &new, &buf);
    try std.testing.expectEqual(@as(usize, 1), r_open.total);
    try std.testing.expect(buf[0].named_without_bytes);

    const fsynced = [_]Op{.{ .class = .fsync, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &fsynced, &old, &new, &buf).total);

    // Control: the same open beside a recorded write is accounted for.
    const written = [_]Op{
        .{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" },
        .{ .class = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" },
    };
    try std.testing.expect(reconcileWithContents(&changed, &written, &old, &new, &buf).clean());

    // A new file filled by a clone, never written: the open that created it is not enough.
    const made = [_]Difference{.{ .rel = "key.txt", .how = .only_in_second }};
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&made, &opened, &.{}, &new, &buf).total);
}

test "reconcile: an open still accounts for a file it left empty, created or truncated" {
    var buf: [2]Unaccounted = undefined;
    const opened = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" }};
    const empty = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "" }};
    const created = [_]Difference{.{ .rel = "key.txt", .how = .only_in_second }};
    try std.testing.expect(reconcileWithContents(&created, &opened, &.{}, &empty, &buf).clean());
    const truncated = [_]Difference{.{ .rel = "key.txt", .how = .content_differs }};
    const old = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD\n" }};
    try std.testing.expect(reconcileWithContents(&truncated, &opened, &old, &empty, &buf).clean());
}

test "reconcile: a truncate accounts only for the old bytes cut short or padded with zeros" {
    var buf: [2]Unaccounted = undefined;
    const changed = [_]Difference{.{ .rel = "key.txt", .how = .content_differs }};
    const truncate = [_]Op{.{ .class = .truncate, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/key.txt", .aux = "" }};
    const old = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD-CONTENT-LONG\n" }};

    const cut = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD" }};
    try std.testing.expect(reconcileWithContents(&changed, &truncate, &old, &cut, &buf).clean());
    const padded = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD-CONTENT-LONG\n\x00\x00\x00" }};
    try std.testing.expect(reconcileWithContents(&changed, &truncate, &old, &padded, &buf).clean());
    const zeros = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "\x00\x00\x00\x00" }};
    try std.testing.expect(reconcileWithContents(&changed, &truncate, &old, &zeros, &buf).clean());

    // `ftruncate(fd, 0)` and then bytes through io_uring: a shorter different content, and the
    // old bytes with a non-zero tail. Neither is what a truncate can leave.
    const shorter = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "NEW\n" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &truncate, &old, &shorter, &buf).total);
    const tail = [_]Entry{.{ .rel = "key.txt", .kind = .file, .content = "OLD-CONTENT-LONG\nTAIL\n" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &truncate, &old, &tail, &buf).total);
}

test "reconcile: only the destination of a rename accounts for the bytes a file is left holding" {
    var buf: [2]Unaccounted = undefined;
    const changed = [_]Difference{.{ .rel = "cfg", .how = .content_differs }};
    const old = [_]Entry{.{ .rel = "cfg", .kind = .file, .content = "OLD\n" }};
    const new = [_]Entry{.{ .rel = "cfg", .kind = .file, .content = "NEW\n" }};
    const moved_aside = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg", .aux = "/tmp/s/cfg.bak" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &moved_aside, &old, &new, &buf).total);
    const swapped_in = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg.tmp", .aux = "/tmp/s/cfg" }};
    try std.testing.expect(reconcileWithContents(&changed, &swapped_in, &old, &new, &buf).clean());
}

test "reconcile: the source of a link accounts for a file's bytes only when its other name was written" {
    var buf: [2]Unaccounted = undefined;
    const changed = [_]Difference{.{ .rel = "cfg", .how = .content_differs }};
    const old = [_]Entry{.{ .rel = "cfg", .kind = .file, .content = "OLD\n" }};
    const new = [_]Entry{.{ .rel = "cfg", .kind = .file, .content = "NEW\n" }};
    // `ln cfg cfg.orig` and new bytes at `cfg` from a reflink: only the link and the
    // truncating open are recorded.
    const linked_aside = [_]Op{
        .{ .class = .link, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg", .aux = "/tmp/s/cfg.orig" },
        .{ .class = .open, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/cfg", .aux = "" },
    };
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &linked_aside, &old, &new, &buf).total);
    // A write through the other name changes this name's bytes, and accounts for them.
    const written_through = [_]Op{
        .{ .class = .link, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cfg", .aux = "/tmp/s/alias" },
        .{ .class = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/alias", .aux = "" },
    };
    try std.testing.expect(reconcileWithContents(&changed, &written_through, &old, &new, &buf).clean());
    // A write to that name before the link reached a different file.
    const written_before = [_]Op{
        .{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/alias", .aux = "" },
        .{ .class = .link, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/cfg", .aux = "/tmp/s/alias" },
    };
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContents(&changed, &written_before, &old, &new, &buf).total);
}

test "reconcile: a path declared scratch is accounted for by any record that names it" {
    var buf: [2]Unaccounted = undefined;
    const changed = [_]Difference{.{ .rel = "cache/index", .how = .content_differs }};
    const old = [_]Entry{.{ .rel = "cache/index", .kind = .file, .content = "v1" }};
    const new = [_]Entry{.{ .rel = "cache/index", .kind = .file, .content = "v2" }};
    const opened = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cache/index", .aux = "" }};
    try std.testing.expect(reconcileWithContentsExcept(&changed, &opened, &old, &new, &.{"cache"}, &buf).clean());
    try std.testing.expectEqual(@as(usize, 1), reconcileWithContentsExcept(&changed, &opened, &old, &new, &.{"elsewhere"}, &buf).total);
}

test "reconcile: a change no operation names is unaccounted (#405)" {
    const root = "/tmp/s";
    const diffs = [_]Difference{
        .{ .rel = "from-parent", .how = .only_in_second },
        .{ .rel = "from-raw-child", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/from-parent", .aux = "" },
        .{ .class = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/from-parent", .aux = "" },
    };
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, root, "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r.total);
    try std.testing.expectEqual(@as(usize, 1), r.stored);
    try std.testing.expectEqualStrings("from-raw-child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
    try std.testing.expect(!r.clean());
}

test "reconcile: an open names the path it created when nothing says what the file holds" {
    const diffs = [_]Difference{.{ .rel = "made", .how = .only_in_second }};
    const ops = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/made", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: only a rename grants a subtree, and only from outside the root" {
    const diffs = [_]Difference{
        .{ .rel = "d", .how = .only_in_second },
        .{ .rel = "d/child", .how = .only_in_second },
    };
    var buf: [4]Unaccounted = undefined;

    const moved_in = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/outside/staging", .aux = "/tmp/s/d" }};
    const r_in = reconcileIn(&diffs, &moved_in, &.{}, "/tmp/s", "", &buf);
    try std.testing.expect(r_in.clean());
    try std.testing.expectEqual(@as(usize, 1), r_in.by_rename_prefix);

    const within = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/old", .aux = "/tmp/s/d" }};
    const r_within = reconcileIn(&diffs, &within, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r_within.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r_within.by_rename_prefix);

    const opened = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/outside/staging", .aux = "/tmp/s/elsewhere" },
        .{ .class = .open, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/d", .aux = "" },
    };
    const r_open = reconcileIn(&diffs, &opened, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r_open.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r_open.by_rename_prefix);
}

test "reconcile: a rename whose destination is the root itself absorbs nothing" {
    const diffs = [_]Difference{
        .{ .rel = "a", .how = .only_in_second },
        .{ .rel = "a/b", .how = .only_in_second },
    };
    const ops = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/outside/x", .aux = "/tmp/s" }};
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 2), r.total);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
}

test "reconcile: a rename is read at both ends (papis, TOY_LINK_IN)" {
    const diffs = [_]Difference{
        .{ .rel = "probe-doc", .how = .only_in_second },
        .{ .rel = "linked-in", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/outside/staging", .aux = "/tmp/s/probe-doc" },
        .{ .class = .link, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/outside/src", .aux = "/tmp/s/linked-in" },
    };
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf);
    try std.testing.expect(r.clean());
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
    // Control: the same records with the `aux` end blanked leave both differences
    // unaccounted, so the leg above measures the aux read and not a join that accepts
    // everything.
    //
    // The control this replaced swapped the two ends, and was declared and then
    // discarded (`_ = swapped;`). Running it — after an outside review read the test
    // rather than its comment — showed it would not have measured anything: swapping
    // moves the in-root spelling from `aux` to `path`, where an exact match names the
    // difference just the same. A control that cannot fail is the same evidence as no
    // control, and only running it tells the two apart.
    const path_only = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/outside/staging", .aux = "" },
        .{ .class = .link, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/outside/src", .aux = "" },
    };
    const r_control = reconcileIn(&diffs, &path_only, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 2), r_control.total);
    try std.testing.expectEqual(@as(usize, 0), r_control.by_rename_prefix);
}

test "reconcile: a renamed-in directory carries its children, and the count says so" {
    const diffs = [_]Difference{
        .{ .rel = "probe-doc", .how = .only_in_second },
        .{ .rel = "probe-doc/info.yaml", .how = .only_in_second },
        .{ .rel = "probe-doc/paper.pdf", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/outside/staging", .aux = "/tmp/s/probe-doc" },
    };
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf);
    try std.testing.expect(r.clean());
    try std.testing.expectEqual(@as(usize, 2), r.by_rename_prefix);
    // Control: a sibling that is NOT under the renamed directory stays unaccounted, so
    // the prefix rule absorbs the subtree and not the whole run.
    const with_sibling = [_]Difference{
        .{ .rel = "probe-doc", .how = .only_in_second },
        .{ .rel = "probe-doc/info.yaml", .how = .only_in_second },
        .{ .rel = "probe-docs-elsewhere", .how = .only_in_second },
    };
    const r2 = reconcileIn(&with_sibling, &ops, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r2.total);
    try std.testing.expectEqualStrings("probe-docs-elsewhere", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 1), r2.by_rename_prefix);
}

test "reconcile: the alt spelling of the root joins the same paths" {
    const diffs = [_]Difference{.{ .rel = "key.json", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/private/tmp/s/key.json", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "/private/tmp/s", &buf).clean());
    try std.testing.expect(!reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: an operation naming the root itself is a name, not a skip" {
    const diffs = [_]Difference{.{ .rel = "", .how = .kind_differs }};
    const ops = [_]Op{.{ .class = .rmdir, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
    const outside = [_]Op{.{ .class = .rmdir, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp", .aux = "" }};
    try std.testing.expect(!reconcileIn(&diffs, &outside, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: markers and out-of-scope operations never name a path" {
    // Every marker class gets a decoy UNDER the root that would name a difference if the
    // class test let it through. An earlier version used `unsupported` with a syscall
    // spelling for its path, which is outside the root and therefore dropped for the
    // wrong reason — narrowing the marker test to `shim_ready` alone left the suite green.
    const diffs = [_]Difference{
        .{ .rel = "", .how = .content_differs },
        .{ .rel = "decoy-a", .how = .only_in_second },
        .{ .rel = "decoy-b", .how = .only_in_second },
        .{ .rel = "decoy-c", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .class = .unsupported, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/decoy-a", .aux = "" },
        .{ .class = .kill_landed, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/decoy-b", .aux = "" },
        .{ .class = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/decoy-c", .aux = "" },
        .{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/elsewhere/f", .aux = "" },
    };
    var buf: [8]Unaccounted = undefined;
    try std.testing.expectEqual(@as(usize, 4), reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).total);
}

test "reconcile: a path recorded through an interior symlink names what the snapshot holds" {
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .only_in_first }};
    const ops = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    var buf: [4]Unaccounted = undefined;

    const abs = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v1" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &abs, "/tmp/s", "", &buf).clean());
    const rel_target = [_]Link{.{ .rel = "cur", .target = "v1" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &rel_target, "/tmp/s", "", &buf).clean());
    const dotted = [_]Link{.{ .rel = "links/cur", .target = "../v1" }};
    const via_dotted = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/links/cur/f", .aux = "" }};
    try std.testing.expect(reconcileIn(&diffs, &via_dotted, &dotted, "/tmp/s", "", &buf).clean());

    // Control: with no link recorded, the same operation names nothing — so the leg above
    // measures the substitution and not a join that accepts any path.
    try std.testing.expect(!reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
    const wrong = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v2" }};
    try std.testing.expect(!reconcileIn(&diffs, &ops, &wrong, "/tmp/s", "", &buf).clean());
}

test "reconcile: link substitution follows a chain and survives a cycle" {
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/latest/f", .aux = "" }};
    const chain = [_]Link{
        .{ .rel = "latest", .target = "stable" },
        .{ .rel = "stable", .target = "v1" },
    };
    var buf: [4]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &chain, "/tmp/s", "", &buf).clean());

    const cyc = [_]Link{
        .{ .rel = "a", .target = "b" },
        .{ .rel = "b", .target = "a" },
    };
    const cyc_ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a/f", .aux = "" }};
    try std.testing.expect(!reconcileIn(&diffs, &cyc_ops, &cyc, "/tmp/s", "", &buf).clean());
}

test "reconcile: a record that makes a link does not account for a change at its target (R1 of the diff)" {
    const links = [_]Link{.{ .rel = "new", .target = "pkg/f" }};
    var buf: [4]Unaccounted = undefined;
    const diffs = [_]Difference{
        .{ .rel = "new", .how = .only_in_second },
        .{ .rel = "pkg/f", .how = .content_differs },
    };
    const ops = [_]Op{.{ .class = .symlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/new", .aux = "" }};
    const r = reconcileIn(&diffs, &ops, &links, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r.total);
    try std.testing.expectEqualStrings("pkg/f", buf[0].rel);
    const to_dir = [_]Link{.{ .rel = "cur", .target = "v1" }};
    const dir_diffs = [_]Difference{.{ .rel = "v1", .how = .kind_differs }};
    const mk = [_]Op{.{ .class = .mkdir, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur", .aux = "" }};
    const r2 = reconcileIn(&dir_diffs, &mk, &to_dir, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r2.total);
}

test "reconcile: an operation on the link itself names the link, not its target" {
    const links = [_]Link{.{ .rel = "cur", .target = "v1" }};
    var buf: [4]Unaccounted = undefined;

    const removed = [_]Difference{.{ .rel = "cur", .how = .only_in_first }};
    const unlink_link = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur", .aux = "" }};
    try std.testing.expect(reconcileIn(&removed, &unlink_link, &links, "/tmp/s", "", &buf).clean());

    const swapped = [_]Difference{.{ .rel = "cur", .how = .content_differs }};
    const swap_ops = [_]Op{
        .{ .class = .symlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur.tmp", .aux = "" },
        .{ .class = .rename, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/cur.tmp", .aux = "/tmp/s/cur" },
    };
    try std.testing.expect(reconcileIn(&swapped, &swap_ops, &links, "/tmp/s", "", &buf).clean());

    const through = [_]Difference{.{ .rel = "v1/f", .how = .only_in_first }};
    const unlink_through = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    try std.testing.expect(reconcileIn(&through, &unlink_through, &links, "/tmp/s", "", &buf).clean());
    const other = [_]Difference{.{ .rel = "v2/f", .how = .only_in_first }};
    try std.testing.expect(!reconcileIn(&other, &unlink_through, &links, "/tmp/s", "", &buf).clean());
}

test "reconcile: only a rename grants a subtree — a link into the root does not" {
    // The class test's own falsification. An earlier version of the leg above used an
    // `.open` for its not-a-rename case, and `.open` carries no `aux`, so it never
    // reached the class test at all: deleting `op.class == .rename` left the suite green.
    // `.link` is the class that does reach it — two paths, destination inside the root,
    // source outside — and it must not take the umbrella.
    const diffs = [_]Difference{
        .{ .rel = "d", .how = .only_in_second },
        .{ .rel = "d/child", .how = .only_in_second },
    };
    var buf: [4]Unaccounted = undefined;
    const linked = [_]Op{.{ .class = .link, .seq = 1, .pid = 7, .tid = 7, .path = "/outside/src", .aux = "/tmp/s/d" }};
    const r = reconcileIn(&diffs, &linked, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
    // Control: the same shape as a rename does take it, so the leg measures the class and
    // not something both records fail.
    const renamed = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/outside/src", .aux = "/tmp/s/d" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileIn(&diffs, &renamed, &.{}, "/tmp/s", "", &buf).by_rename_prefix);
}

test "reconcile: a link matches whole components, and never picks between two" {
    var buf: [4]Unaccounted = undefined;
    // `cur -> v1` must leave `current/f` alone. The difference is the one a partial-
    // component substitution WOULD produce — `current/f` minus `cur` plus `v1` — so a
    // record on `current/f` must not name it. Asserting instead that `current/f` itself
    // stays clean measures nothing: the literal spelling names it either way, which is
    // exactly what the first version of this leg did and why the mutation survived it.
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/current/f", .aux = "" }};
    const near = [_]Link{.{ .rel = "cur", .target = "v1" }};
    const mangled = [_]Difference{.{ .rel = "v1/rent/f", .how = .content_differs }};
    try std.testing.expect(!reconcileIn(&mangled, &ops, &near, "/tmp/s", "", &buf).clean());
    const diffs = [_]Difference{.{ .rel = "current/f", .how = .content_differs }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &near, "/tmp/s", "", &buf).clean());

    // The targets are absolute for a reason the first two versions of this leg missed. A
    // relative target is joined to its link's own directory, so a result under `a/…` gets
    // rewritten again by the `a` link on the next hop, and both readings end up somewhere
    // neither difference is — which makes a chooser and a refuser agree, and lets the
    // mutation live. Absolute targets land outside the links' reach and the two readings
    // stay apart.
    const ambiguous = [_]Link{
        .{ .rel = "a", .target = "/tmp/s/x" },
        .{ .rel = "a/b", .target = "/tmp/s/y" },
    };
    const deep_ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a/b/f", .aux = "" }};
    const one_reading = [_]Difference{.{ .rel = "y/f", .how = .content_differs }};
    try std.testing.expect(!reconcileIn(&one_reading, &deep_ops, &ambiguous, "/tmp/s", "", &buf).clean());
    // Control: on its own that link does resolve to exactly this spelling, so the leg
    // measures the refusal to choose and not a substitution that could not have produced
    // the difference anyway.
    const only_deep = [_]Link{.{ .rel = "a/b", .target = "/tmp/s/y" }};
    try std.testing.expect(reconcileIn(&one_reading, &deep_ops, &only_deep, "/tmp/s", "", &buf).clean());
}

test "reconcile: a link retargeted mid-run is not used to name anything" {
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .only_in_second }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    var buf: [4]Unaccounted = undefined;

    var links: std.ArrayList(Link) = .empty;
    defer links.deinit(std.testing.allocator);

    var before = Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer before.deinit();
    try before.entries.append(before.arena.allocator(), .{ .rel = "cur", .kind = .symlink, .content = "v1" });
    var after = Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer after.deinit();
    try after.entries.append(after.arena.allocator(), .{ .rel = "cur", .kind = .symlink, .content = "v2" });

    try collectLinks(std.testing.allocator, before, after, &links);
    try std.testing.expectEqual(@as(usize, 0), links.items.len);
    try std.testing.expect(!reconcileIn(&diffs, &ops, links.items, "/tmp/s", "", &buf).clean());

    var steady: std.ArrayList(Link) = .empty;
    defer steady.deinit(std.testing.allocator);
    try collectLinks(std.testing.allocator, before, before, &steady);
    try std.testing.expectEqual(@as(usize, 1), steady.items.len);
    try std.testing.expect(reconcileIn(&diffs, &ops, steady.items, "/tmp/s", "", &buf).clean());
}

test "reconcile: an absolute link target is folded like a relative one" {
    const diffs = [_]Difference{.{ .rel = "v2/f", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    var buf: [4]Unaccounted = undefined;
    const dotted = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v1/../v2" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &dotted, "/tmp/s", "", &buf).clean());
    const escaping = [_]Link{.{ .rel = "cur", .target = "../outside" }};
    try std.testing.expect(!reconcileIn(&diffs, &ops, &escaping, "/tmp/s", "", &buf).clean());
}

test "reconcile: the buffer bounds what is stored, never what is counted" {
    const diffs = [_]Difference{
        .{ .rel = "a", .how = .only_in_second },
        .{ .rel = "b", .how = .only_in_second },
        .{ .rel = "c", .how = .only_in_second },
    };
    var buf: [1]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &[_]Op{}, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 3), r.total);
    try std.testing.expectEqual(@as(usize, 1), r.stored);
}

test "diffSnapshots reports both directions, kind and content" {
    const gpa = std.testing.allocator;
    const Pair = struct { rel: []const u8, kind: posix.Kind, content: []const u8 };
    const build = struct {
        fn f(a: std.mem.Allocator, items: []const Pair) !Snapshot {
            var snap = Snapshot{ .arena = std.heap.ArenaAllocator.init(a), .entries = .empty };
            const arena = snap.arena.allocator();
            for (items) |it| try snap.entries.append(arena, .{ .rel = it.rel, .kind = it.kind, .content = it.content });
            return snap;
        }
    }.f;

    var buf: [8]Difference = undefined;

    // Equal: the control. An implementation that reported every entry as a difference
    // would pass every other leg below and die here.
    var a1 = try build(gpa, &.{
        .{ .rel = "a", .kind = .file, .content = "1" },
        .{ .rel = "d", .kind = .dir, .content = "" },
    });
    defer a1.deinit();
    var b1 = try build(gpa, &.{
        .{ .rel = "a", .kind = .file, .content = "1" },
        .{ .rel = "d", .kind = .dir, .content = "" },
    });
    defer b1.deinit();
    try std.testing.expect(diffSnapshots(a1, b1, &buf).equal());

    var a2 = try build(gpa, &.{
        .{ .rel = "gone", .kind = .file, .content = "x" },
        .{ .rel = "same", .kind = .file, .content = "s" },
    });
    defer a2.deinit();
    var b2 = try build(gpa, &.{
        .{ .rel = "same", .kind = .file, .content = "s" },
        .{ .rel = "new", .kind = .file, .content = "y" },
    });
    defer b2.deinit();
    std.mem.sort(Entry, b2.entries.items, {}, lessThanRel);
    const c2 = diffSnapshots(a2, b2, &buf);
    try std.testing.expectEqual(@as(usize, 2), c2.total);
    try std.testing.expectEqual(@as(usize, 2), c2.stored);
    try std.testing.expectEqualStrings("gone", buf[0].rel);
    try std.testing.expectEqual(Difference.How.only_in_first, buf[0].how);
    try std.testing.expectEqualStrings("new", buf[1].rel);
    try std.testing.expectEqual(Difference.How.only_in_second, buf[1].how);

    var a3 = try build(gpa, &.{.{ .rel = "x", .kind = .dir, .content = "" }});
    defer a3.deinit();
    var b3 = try build(gpa, &.{.{ .rel = "x", .kind = .file, .content = "bytes" }});
    defer b3.deinit();
    const c3 = diffSnapshots(a3, b3, &buf);
    try std.testing.expectEqual(@as(usize, 1), c3.total);
    try std.testing.expectEqual(Difference.How.kind_differs, buf[0].how);

    var a4 = try build(gpa, &.{.{ .rel = "x", .kind = .file, .content = "one" }});
    defer a4.deinit();
    var b4 = try build(gpa, &.{.{ .rel = "x", .kind = .file, .content = "two" }});
    defer b4.deinit();
    const c4 = diffSnapshots(a4, b4, &buf);
    try std.testing.expectEqual(@as(usize, 1), c4.total);
    try std.testing.expectEqual(Difference.How.content_differs, buf[0].how);
}

test "diffSnapshots keeps counting past the caller's buffer" {
    const gpa = std.testing.allocator;
    var a = Snapshot{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer a.deinit();
    var b = Snapshot{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer b.deinit();
    const ba = b.arena.allocator();
    for ([_][]const u8{ "a", "b", "c", "d", "e" }) |rel|
        try b.entries.append(ba, .{ .rel = rel, .kind = .file, .content = "z" });
    var small: [2]Difference = undefined;
    const c = diffSnapshots(a, b, &small);
    try std.testing.expectEqual(@as(usize, 5), c.total);
    try std.testing.expectEqual(@as(usize, 2), c.stored);
    try std.testing.expect(!c.equal());
}

test "a Difference that escapes its snapshot must own its bytes" {
    // The overwrite below is the whole trick. Without it a freed arena's pages are
    // usually still readable and the assertion passes by luck — measured: the shell
    // acceptance leg that drives this same path stayed green against the defect. Taking
    // the pages back and filling them with 0xAA turns the bug into an ordinary string
    // mismatch a CI log can show, instead of a segfault or a silent pass.
    const gpa = std.testing.allocator;
    var caller = std.heap.ArenaAllocator.init(gpa);
    defer caller.deinit();
    const arena = caller.allocator();

    var first = Snapshot{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer first.deinit();

    const diffs = blk: {
        var second = Snapshot{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
        defer second.deinit();
        const sa = second.arena.allocator();
        const owned = try sa.dupe(u8, "only-in-second.txt");
        try second.entries.append(sa, .{ .rel = owned, .kind = .file, .content = "x" });

        const out = try arena.alloc(Difference, 4);
        const count = diffSnapshots(first, second, out);
        try std.testing.expectEqual(@as(usize, 1), count.total);
        try std.testing.expectEqual(Difference.How.only_in_second, out[0].how);
        for (out[0..count.stored]) |*d| d.rel = try arena.dupe(u8, d.rel);
        break :blk out[0..count.stored];
    };

    var claims: [8][]u8 = undefined;
    var claimed: usize = 0;
    defer {
        for (claims[0..claimed]) |c| gpa.free(c);
    }
    while (claimed < claims.len) : (claimed += 1) {
        claims[claimed] = try gpa.alloc(u8, 64 * 1024);
        @memset(claims[claimed], 0xAA);
    }

    try std.testing.expectEqualStrings("only-in-second.txt", diffs[0].rel);
}

fn lessThanRel(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.rel, b.rel);
}

/// Sorting also makes restore create parents before children, and makes two snapshots of
/// the same tree compare equal regardless of directory iteration order. A duplicate `rel`
/// would mean `walk` emitted the same path twice, which no directory traversal should
/// produce — the sort would not catch it, and a binary search would silently pick either
/// one (#262).
pub fn finalizeEntries(snap: *Snapshot) error{EntriesNotSortedUnique}!void {
    std.mem.sort(Entry, snap.entries.items, {}, lessThanRel);
    if (validateSortedUnique(snap.entries.items)) |_| return error.EntriesNotSortedUnique;
}

/// The snapshot spells a directory as `foo`, never `foo/`, so a subtree-only form would
/// miss the directory's own pair — the pair #164 made enter the plan — and `foobar` must
/// not match `foo`, which the slash after the prefix is there to say.
pub fn scratchMatches(scratch: []const []const u8, rel: []const u8) bool {
    for (scratch) |p| {
        if (std.mem.eql(u8, rel, p)) return true;
        if (rel.len > p.len and std.mem.startsWith(u8, rel, p) and rel[p.len] == '/') return true;
    }
    return false;
}

test "scratchMatches: the path itself and its subtree, never a sibling sharing the prefix" {
    const decl = [_][]const u8{ "COMMIT_EDITMSG", ".hg/wcache" };
    try std.testing.expect(scratchMatches(&decl, "COMMIT_EDITMSG"));
    try std.testing.expect(scratchMatches(&decl, ".hg/wcache"));
    try std.testing.expect(scratchMatches(&decl, ".hg/wcache/checkisexec"));
    try std.testing.expect(!scratchMatches(&decl, ".hg/wcachex"));
    try std.testing.expect(!scratchMatches(&decl, "COMMIT_EDITMSG.bak"));
    try std.testing.expect(!scratchMatches(&decl, ".hg"));
    try std.testing.expect(!scratchMatches(&.{}, "COMMIT_EDITMSG"));
}

/// Sorting can change which violation a test observes: `classify` walks `pre.entries`
/// in order into `plan.files`, and both judges return on the first violation in that
/// list. Every fixture built with this arranges one violation at a time, so the reported answer
/// does not move — but a fixture with two would be decided by this sort.
pub fn testSnapshot(gpa: Allocator, pairs: []const [2][]const u8) !Snapshot {
    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    // As in `takeSnapshot`. Needed here from the moment this function grew a second way to
    // fail: the validation below returns after the arena already holds the duped entries,
    // and the caller has no snapshot to `deinit`.
    errdefer snap.arena.deinit();
    const arena = snap.arena.allocator();
    for (pairs) |p| {
        try snap.entries.append(arena, .{
            .rel = try arena.dupe(u8, p[0]),
            .kind = .file,
            .content = try arena.dupe(u8, p[1]),
        });
    }
    try finalizeEntries(&snap);
    return snap;
}

fn linearFind(snap: Snapshot, rel: []const u8) ?Entry {
    for (snap.entries.items) |e| {
        if (compareRel(rel, e) == .eq) return e;
    }
    return null;
}

test "find answers exactly as a linear scan does, present and absent" {
    const gpa = std.testing.allocator;
    var snap = try testSnapshot(gpa, &.{
        .{ "audit.log", "a\n" },
        .{ "key.json", "k\n" },
        .{ "receipt.txt", "r\n" },
        .{ "zz.bin", "z\n" },
    });
    defer snap.deinit();

    for (snap.entries.items) |e| {
        const got = snap.find(e.rel) orelse return error.MissingEntry;
        const want = linearFind(snap, e.rel) orelse return error.MissingEntry;
        try std.testing.expectEqualStrings(want.rel, got.rel);
        try std.testing.expectEqualStrings(want.content, got.content);
    }

    for ([_][]const u8{ "aaa", "kz.json", "zzzz" }) |missing| {
        try std.testing.expect(snap.find(missing) == null);
        try std.testing.expect(linearFind(snap, missing) == null);
    }
}

test "find costs a logarithmic number of comparisons, not a linear one" {
    const gpa = std.testing.allocator;

    var names: [1024][8]u8 = undefined;
    var pairs: [1024][2][]const u8 = undefined;
    for (0..1024) |i| {
        _ = std.fmt.bufPrint(&names[i], "e{d:0>4}", .{i}) catch unreachable;
        pairs[i] = .{ names[i][0..5], "x" };
    }
    var snap = try testSnapshot(gpa, &pairs);
    defer snap.deinit();

    // The lower bound matters as much as the upper one. An upper bound alone is satisfied
    // by zero, and zero is exactly what the implementation this replaced produces — it
    // compared with `std.mem.eql` directly, never through the counted primitive. `find`
    // reverting to that code would have passed a bare `<= 11` by never incrementing at
    // all: measured, not reasoned about. Requiring at least one comparison over a
    // non-empty snapshot is what makes this measure the lookup instead of its absence.
    for ([_][]const u8{ "e1023", "e9999" }) |key| {
        rel_comparisons = 0;
        _ = snap.find(key);
        try std.testing.expect(rel_comparisons > 0);
        try std.testing.expect(rel_comparisons <= 11);
    }

    // The control: the same lookup through the linear oracle, counted the same way. If
    // this did not blow past the bound, the counter would not be measuring anything.
    rel_comparisons = 0;
    _ = linearFind(snap, "e1023");
    try std.testing.expect(rel_comparisons == 1024);
}

test "validateSortedUnique separates disorder from duplication" {
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const mk = struct {
        fn f(a: Allocator, rels: []const []const u8) ![]Entry {
            const out = try a.alloc(Entry, rels.len);
            for (rels, 0..) |r, i| out[i] = .{ .rel = r, .kind = .file, .content = "" };
            return out;
        }
    }.f;

    try std.testing.expect(validateSortedUnique(try mk(arena, &.{ "a", "b", "c" })) == null);
    try std.testing.expect(validateSortedUnique(try mk(arena, &.{"only"})) == null);
    try std.testing.expect(validateSortedUnique(try mk(arena, &.{})) == null);

    try std.testing.expectEqual(OrderProblem.out_of_order, validateSortedUnique(try mk(arena, &.{ "b", "a" })).?);
    try std.testing.expectEqual(OrderProblem.duplicate, validateSortedUnique(try mk(arena, &.{ "a", "a" })).?);
    try std.testing.expectEqual(OrderProblem.duplicate, validateSortedUnique(try mk(arena, &.{ "a", "b", "b", "c" })).?);
}

test "the producers refuse a snapshot that violates the order find searches by" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.EntriesNotSortedUnique,
        testSnapshot(gpa, &.{ .{ "dup.txt", "one\n" }, .{ "dup.txt", "two\n" } }),
    );
}

test "a mode alone is not a difference: the judgement reads kind and content (#678)" {
    const gpa = std.testing.allocator;
    var a = try testSnapshot(gpa, &.{.{ "key", "same" }});
    defer a.deinit();
    var b = try testSnapshot(gpa, &.{.{ "key", "same" }});
    defer b.deinit();
    a.entries.items[0].mode = 0o600;
    b.entries.items[0].mode = 0o644;
    var out: [4]Difference = undefined;
    try std.testing.expectEqual(@as(usize, 0), diffSnapshots(a, b, &out).total);
    b.entries.items[0].content = "other";
    try std.testing.expectEqual(@as(usize, 1), diffSnapshots(a, b, &out).total);
}
