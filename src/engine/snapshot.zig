//! The snapshot: `Entry` and `Snapshot`, their diff, their reconciliation against the trace,
//! and the sorted-unique invariant the producers finalize through.
//!
//! The second seam out of `engine.zig` (#491, ADR 0048). Everything else the engine does —
//! the walk that takes a snapshot, the restore that rebuilds one, the judges that compare
//! them — stands on these types, and none of it is reached from here: this file imports
//! the trace (for `Op`, which `reconcile` joins against), `contract` (for the path
//! predicate `relUnderRoot` shares with the shim) and `posix` (for `Kind`), and nothing
//! from `engine.zig`. `engine.zig` re-exports every public declaration of this file.
//!
//! What stays behind, deliberately: the producer's own vocabulary. `SnapshotError`,
//! `SnapshotCaps` and the two size diagnostics are what the walk can fail with, not what
//! a snapshot is; they move with the walk. `finalizeEntries` is here because it is the
//! invariant — sort, then refuse a list `find` cannot search — and both producers end in
//! it; `testSnapshot` is here because it is the fixture that builds under that same
//! finalizer. `scratchMatches` is here because `diffSnapshotsExcept` needs it and the
//! judges can reach it through the facade, whereas the other direction would be a cycle.
//!
//! Comments below name declarations that live elsewhere and are not imported: in
//! `engine.zig`, `walk`, `takeSnapshot`, `restore`, `deleteTreeAt`, `SnapshotError` and
//! `SnapshotCaps` (the producers and the destructive side) and `classify`, `classifyWith`
//! and `L0Plan` (the judges); in `trace.zig`, `isMutation` and the marker classes
//! `shim_ready` and `kill_landed`; in `main.zig`, `observeAgain` and
//! `child_touched_state_dir`. They are prose references, kept so the reasons written next
//! to this code stay next to it.

const std = @import("std");
const contract = @import("contract");
const posix = @import("../posix.zig");
const trace = @import("trace.zig");

const Allocator = std.mem.Allocator;
const Op = trace.Op;

pub const Entry = struct {
    /// Path relative to the state directory root, always using '/'.
    rel: []const u8,
    kind: posix.Kind,
    /// File contents; the link target for a symlink; empty for directories.
    /// A symlink's target is its whole judged identity — the link is never followed,
    /// so what it points AT is outside the snapshot and outside the judgement (#122).
    content: []const u8,
};

/// Counts `rel` comparisons, so a test can assert the *cost* of a lookup rather than only
/// its answer.
///
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

/// What the entry list must satisfy for `find` to be a binary search: sorted by `rel`,
/// and no `rel` twice.
///
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

    /// Binary search over `entries`, which every producer sorts and validates.
    ///
    /// This was a linear scan, and it is called once per file from inside loops in
    /// `classify` and both judges — quadratic in the entry count for every world explored
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

/// The first entry (in the snapshot's sorted order) that `restore` cannot recreate:
/// `.other` — a FIFO, socket or device — and, fail-closed, `.missing`, which `walk`
/// never emits (it drops unresolvable entries on the spot). If a future walk change
/// lets one through, this reports it loudly instead of leaving `restore` to
/// manufacture an absent entry one world later (#5).
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

    // Every supported kind present and nothing flagged: an implementation that flags
    // "anything but .file" — or lumps .dir in with the unsupported — dies here.
    try snap.entries.append(a, .{ .rel = "a.txt", .kind = .file, .content = "x" });
    try snap.entries.append(a, .{ .rel = "d", .kind = .dir, .content = "" });
    try snap.entries.append(a, .{ .rel = "l", .kind = .symlink, .content = "a.txt" });
    try std.testing.expectEqual(@as(?[]const u8, null), firstUnsupportedEntry(snap));

    // Mixed with two unsupported entries: the FIRST in snapshot order is named
    // (walk sorts by rel, so this is deterministic in real snapshots too).
    try snap.entries.append(a, .{ .rel = "m-pipe", .kind = .other, .content = "" });
    try snap.entries.append(a, .{ .rel = "z-sock", .kind = .other, .content = "" });
    try std.testing.expectEqualStrings("m-pipe", firstUnsupportedEntry(snap).?);

    // `.missing` never leaves walk, but an artificial one is flagged, not ignored:
    // fail-closed against a future walk change letting it through.
    var snap2 = Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer snap2.deinit();
    const a2 = snap2.arena.allocator();
    try snap2.entries.append(a2, .{ .rel = "ghost", .kind = .missing, .content = "" });
    try std.testing.expectEqualStrings("ghost", firstUnsupportedEntry(snap2).?);
}

/// One way two snapshots of the same root disagree.
///
/// `rel` borrows from whichever snapshot holds the entry, so a `Difference` is only
/// valid while both snapshots are: the caller renders it before either is deinited.
pub const Difference = struct {
    rel: []const u8,
    how: How,

    pub const How = enum {
        /// Present in the first snapshot, absent from the second.
        only_in_first,
        /// Present in the second, absent from the first — the direction `classify`
        /// structurally cannot report, because it walks the pre-side only.
        only_in_second,
        kind_differs,
        content_differs,
    };
};

/// How many differences exist, and how many the caller's buffer could hold.
pub const DiffCount = struct {
    /// Written into `out`, in sorted `rel` order.
    stored: usize,
    /// Every difference found, whether or not it fit. A caller that reports `stored`
    /// as if it were the total would understate a split on any tree that overflows
    /// the buffer — the counting continues past the buffer for exactly that reason.
    total: usize,

    pub fn equal(self: DiffCount) bool {
        return self.total == 0;
    }
};

/// Every way two snapshots of the same root disagree, bounded by the caller's buffer.
///
/// A linear merge, not a lookup loop: both producers sort and validate
/// (`validateSortedUnique`), so one pass answers in O(n+m) and — unlike `classify`,
/// which iterates the pre-side and asks `find` for its partner — an entry present in
/// only the *second* snapshot is reported rather than skipped. That direction is the
/// whole point here: `classify` skipping it is correct for L0 (a file the operation
/// created has no pre-image to be judged hybrid against), and wrong for a
/// repeatability question, where a file only the second run wrote is the split.
pub fn diffSnapshots(first: Snapshot, second: Snapshot, out: []Difference) DiffCount {
    return diffSnapshotsExcept(first, second, out, &.{});
}

/// `diffSnapshots` with a scratch declaration (ADR 0043): a path the declaration matches
/// is left out before it is counted, so `total` is the total of what was compared and no
/// row past the buffer can hide a declared path behind "… and N more".
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
                    // Kind before content: a directory that became a file has an empty
                    // `content` on one side, and reporting that as a content difference
                    // would describe the smaller half of what happened.
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

/// A path the judged state changed at, which no recorded operation accounts for.
pub const Unaccounted = struct {
    rel: []const u8,
    how: Difference.How,
};

/// What the reconciliation found, beside the unaccounted paths themselves.
pub const Reconciled = struct {
    /// Written into the caller's buffer, in `rel` order.
    stored: usize,
    /// Every unaccounted path, whether or not it fit.
    total: usize,
    /// Paths attributed to a directory a recorded `rename` moved in, rather than to an
    /// operation naming them. The engine never saw the source subtree — for a rename
    /// from outside the judged root there is nothing to have seen — so what came with
    /// the move and what a later unrecorded writer added are indistinguishable. The
    /// count is reported rather than hidden: a run with zero here has no such window.
    by_rename_prefix: usize,

    pub fn clean(self: Reconciled) bool {
        return self.total == 0;
    }
};

/// Strip either spelling of the judged root off an absolute path, yielding the same
/// relative form `Entry.rel` uses. Null when the path is under neither.
///
/// Two spellings because a caller can name the root through a symlink: the shim records
/// under the canonical one, but a target that resolves a descriptor gets the other back
/// (`SIDEEYE_STATE_DIR_ALT`, and macOS's `/tmp` → `/private/tmp`). A join that knew only
/// one of them would count half the operations as naming nothing.
fn relUnderRoot(path: []const u8, root: []const u8, alt: []const u8) ?[]const u8 {
    for ([_][]const u8{ root, alt }) |r| {
        if (r.len == 0) continue;
        if (!contract.isInsideDir(path, r)) continue;
        const d = std.mem.trimEnd(u8, r, "/");
        if (path.len <= d.len + 1) return "";
        return path[d.len + 1 ..];
    }
    return null;
}

/// A symlink the judged tree holds, exactly as the snapshot recorded it: `rel` is the
/// link's own path and `target` the bytes it points at (`Entry.content` of a `.symlink`
/// entry — the link is never followed, so the target is stored rather than resolved).
pub const Link = struct { rel: []const u8, target: []const u8 };

/// Substitutions `resolveThroughLinks` will make before giving up. A cycle (`a -> b`,
/// `b -> a`) is legal on disk and has to terminate; eight is past any real layout.
const max_link_hops = 8;

/// Append `piece` to `buf` at `n`, returning the new length or null if it would not fit.
fn appendInto(buf: []u8, n: usize, piece: []const u8) ?usize {
    if (n + piece.len > buf.len) return null;
    @memcpy(buf[n .. n + piece.len], piece);
    return n + piece.len;
}

/// Resolve one symlinked prefix of `rel`, writing the result into `scratch`.
///
/// Null when no link applies, when the result would not fit, or when the link points
/// outside the judged root — in that last case nothing under it can be a difference
/// either, because the snapshot does not follow links, so leaving `rel` alone is right.
fn substituteOnce(
    rel: []const u8,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
) ?[]const u8 {
    // Longest match: `a` and `a/b` may both be links, and the deeper one is the one the
    // path actually crossed last.
    // Exactly one link, or none. Within one snapshot at most one can match: the walk does
    // not descend into a symlink, so a link's ancestor is never itself a link. Two can
    // only both appear because the tree changed shape between the samples — `a` a
    // directory holding `a/b` in one and a link in the other — and then the substitution
    // has no ordering to pick with, the same bind a retargeted link puts it in. An
    // earlier revision took the longest match, which is a rule that answers rather than
    // an answer, and could not be tested with a tree that can exist.
    var chosen: ?Link = null;
    for (links) |l| {
        if (l.rel.len == 0 or l.rel.len > rel.len) continue;
        if (!std.mem.startsWith(u8, rel, l.rel)) continue;
        if (rel.len != l.rel.len and rel[l.rel.len] != '/') continue;
        if (chosen != null) return null;
        chosen = l;
    }
    const link = chosen orelse return null;

    // One folding pass for both spellings of a target. An absolute one starts empty and
    // contributes its root-relative remainder; a relative one starts at the link's own
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
            // Above the root is outside the judged tree, and is treated the way an
            // absolute target pointing outside is: no substitution at all.
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

/// The physical spelling of a path the shim recorded lexically.
///
/// The shim normalises path arguments lexically (`contract.normalizePath`), so an
/// operation on `cur/f` where `cur -> v1` is recorded as `cur/f` while the snapshot,
/// which never follows a link, holds the difference at `v1/f`. Joining the two spellings
/// without this turned a fully observed run into a refusal naming a path nothing had
/// gone wrong with — measured: one `unlink` through an interior symlink, PASS on the
/// shipped 1.0.0 and UNKNOWN here, with a control on the same file spelled directly
/// still passing.
///
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

/// Every path the state changed at that no recorded operation names.
///
/// The general form of the zero-ops detector: that one asks whether the state moved
/// while *nothing* was counted, which stays silent the moment one operation is
/// recorded — a target whose libc write is seen and whose raw write is not looks
/// exactly like one that was fully observed (#405, measured). This asks the same
/// question per path.
///
/// The direction is deliberate and one-way. "No operation names this path" is evidence
/// the account is incomplete; "every path is named" is NOT evidence it is complete —
/// a failed syscall leaves a record with no change behind it, and a subtree renamed in
/// from outside is accounted for wholesale. The caller refuses on the first, and must
/// not read the absence of the first as the second.
///
/// `ops` should be every recorded operation, not only the subject's mutating ones: a
/// child that left a record has explained its change, and *who* performed it is a
/// different detector's question (`child_touched_state_dir`). `open` counts as naming
/// a path for the same reason — excluding it makes the zero-ops form stricter and this
/// form wrong, since a create-then-write pair would otherwise refuse on its own file.
pub fn reconcile(
    diffs: []const Difference,
    ops: []const Op,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    scratch: []u8,
    out: []Unaccounted,
) Reconciled {
    var res: Reconciled = .{ .stored = 0, .total = 0, .by_rename_prefix = 0 };
    for (diffs) |d| {
        var named = false;
        var by_prefix = false;
        for (ops) |op| {
            if (op.class.isMarker()) continue;
            const ends = [2][]const u8{ op.path, op.aux };
            for (ends) |p| {
                if (p.len == 0) continue;
                const lexical = relUnderRoot(p, root, alt) orelse continue;
                const rel = resolveThroughLinks(lexical, links, root, alt, scratch);
                // BOTH spellings, because a path can name a link or name through it and
                // the two answers are different objects. `unlink("cur")` removes the link
                // and the difference is at `cur`; `unlink("cur/f")` removes a file and the
                // difference is at `v1/f`. Comparing only the substituted form erased the
                // first — measured after the substitution was added: `unlink(cur)` and a
                // `symlink`+`rename` generation swap both went PASS exit 0 → UNKNOWN,
                // naming `cur`. That is the same regression the substitution was written
                // to fix, one level up, and the second revision of this code introduced it.
                if (std.mem.eql(u8, lexical, d.rel) or std.mem.eql(u8, rel, d.rel)) {
                    named = true;
                    break;
                }
                // A directory the target moved IN carries its children with it, and one
                // record is all there is to carry them: the source subtree lived outside
                // the judged root, so it was never snapshotted and which descendants
                // arrived with the move cannot be recovered. Attributing them to the move
                // is the only rule that does not refuse `papis add`, whose whole shape is
                // building a document folder outside the root and renaming it in.
                //
                // The source test carries the whole condition. An earlier revision paired
                // it with "and the matched end is the destination", which reads well and
                // decides nothing: reaching here means this end resolved under the root,
                // so if the *source* does not, this end cannot be the source. Measured —
                // widening it to either end left the suite green. It is deleted rather
                // than kept as documentation, for the same reason the `rel.len > 0` guard
                // one revision earlier was: a condition that cannot change an answer is
                // read as protection that is not there.
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
            out[res.stored] = .{ .rel = d.rel, .how = d.how };
            res.stored += 1;
        }
    }
    return res;
}

/// Collect the judged tree's symlinks for `reconcile`.
///
/// Both snapshots, because a link the operation crossed may have been removed before the
/// final sample or created after the initial one, and either way the path the shim
/// recorded went through it.
///
/// **A link whose target changed during the run contributes nothing.** Neither answer is
/// right and the reconciliation has no way to pick: it holds no ordering between the
/// retarget and the operations, so first-wins and last-wins each excuse a path the target
/// never touched under the other reading. Measured with `cur` moving `v1 -> v2`: reading
/// the initial spelling made an unrecorded write to `v1/f` come out accounted-for, and
/// reading the final one made it a refusal — from the same records. Dropping the link
/// means operations spelled through it fall back to their literal path, match nothing,
/// and refuse. That is the fail-closed side, and it is the side a detector belongs on.
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

/// Every reconcile test goes through this so the scratch buffer is one decision, and so
/// a signature change lands in one place rather than in fifteen call sites.
fn reconcileIn(
    diffs: []const Difference,
    ops: []const Op,
    links: []const Link,
    root: []const u8,
    alt: []const u8,
    out: []Unaccounted,
) Reconciled {
    var scratch: [2048]u8 = undefined;
    return reconcile(diffs, ops, links, root, alt, &scratch, out);
}

test "reconcile: a change no operation names is unaccounted (#405)" {
    // The measured shape. The parent's libc write is recorded and names `from-parent`;
    // the raw-forked child's write is recorded nowhere at all. Before this, one recorded
    // mutation was enough to silence the zero-ops detector and the run PASSed with the
    // child's file in the judged directory.
    const root = "/tmp/s";
    const diffs = [_]Difference{
        .{ .rel = "from-parent", .how = .only_in_second },
        .{ .rel = "from-raw-child", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .open, .seq = 1, .pid = 7, .path = "/tmp/s/from-parent", .aux = "" },
        .{ .class = .write, .seq = 2, .pid = 7, .path = "/tmp/s/from-parent", .aux = "" },
    };
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, root, "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r.total);
    try std.testing.expectEqual(@as(usize, 1), r.stored);
    try std.testing.expectEqualStrings("from-raw-child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
    try std.testing.expect(!r.clean());
}

test "reconcile: an open with no write still names the path it created" {
    // `isMutation` excludes `open` on purpose — it makes the zero-ops form stricter.
    // Here the same exclusion would be wrong: a file created by open and never written
    // is a change its own record explains, and refusing on it is a false refusal.
    const diffs = [_]Difference{.{ .rel = "made", .how = .only_in_second }};
    const ops = [_]Op{.{ .class = .open, .seq = 1, .pid = 7, .path = "/tmp/s/made", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: only a rename grants a subtree, and only from outside the root" {
    // Three shapes that differ ONLY in the operation, against one difference under a
    // directory. The umbrella exists because a subtree moved in from outside was never
    // snapshotted; each of the other two has its source in `initial`, so absorbing them
    // would hide exactly what this detector is for. The first revision of this code
    // checked neither the class-plus-end nor the source, and an outside review's mutation
    // deleting `op.class == .rename` survived the whole suite.
    const diffs = [_]Difference{
        .{ .rel = "d", .how = .only_in_second },
        .{ .rel = "d/child", .how = .only_in_second },
    };
    var buf: [4]Unaccounted = undefined;

    // Moved in from outside: the umbrella applies, and the child is counted, not refused.
    const moved_in = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .path = "/outside/staging", .aux = "/tmp/s/d" }};
    const r_in = reconcileIn(&diffs, &moved_in, &.{}, "/tmp/s", "", &buf);
    try std.testing.expect(r_in.clean());
    try std.testing.expectEqual(@as(usize, 1), r_in.by_rename_prefix);

    // Renamed within the root: the source subtree IS in the snapshot, so nothing is
    // absorbed and the unnamed child is refused.
    const within = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .path = "/tmp/s/old", .aux = "/tmp/s/d" }};
    const r_within = reconcileIn(&diffs, &within, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r_within.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r_within.by_rename_prefix);

    // Not a rename at all: an `open` on the directory names the directory and nothing
    // below it.
    const opened = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .path = "/outside/staging", .aux = "/tmp/s/elsewhere" },
        .{ .class = .open, .seq = 2, .pid = 7, .path = "/tmp/s/d", .aux = "" },
    };
    const r_open = reconcileIn(&diffs, &opened, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r_open.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r_open.by_rename_prefix);
}

test "reconcile: a rename whose destination is the root itself absorbs nothing" {
    // `relUnderRoot` answers `""` for the root, and `""` is a prefix of every path. What
    // stops it covering the whole run is the separator test — the character after the
    // prefix has to be `/`, and a relative `rel` never starts with one. Pinned here
    // because the first revision leaned on a `rel.len > 0` guard instead, which was
    // unreachable for the same reason and so could be deleted with no test turning red.
    const diffs = [_]Difference{
        .{ .rel = "a", .how = .only_in_second },
        .{ .rel = "a/b", .how = .only_in_second },
    };
    const ops = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .path = "/outside/x", .aux = "/tmp/s" }};
    var buf: [4]Unaccounted = undefined;
    const r = reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 2), r.total);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
}

test "reconcile: a rename is read at both ends (papis, TOY_LINK_IN)" {
    // `path` is the old name and `aux` the new one. Reading only `path` refuses every
    // target that builds outside the judged root and moves the result in — measured on
    // `spike/cohort3/papis`, whose single recorded operation is exactly that renameat,
    // with the source under /tmp and outside the library.
    const diffs = [_]Difference{
        .{ .rel = "probe-doc", .how = .only_in_second },
        .{ .rel = "linked-in", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .path = "/tmp/outside/staging", .aux = "/tmp/s/probe-doc" },
        .{ .class = .link, .seq = 2, .pid = 7, .path = "/tmp/outside/src", .aux = "/tmp/s/linked-in" },
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
        .{ .class = .rename, .seq = 1, .pid = 7, .path = "/tmp/outside/staging", .aux = "" },
        .{ .class = .link, .seq = 2, .pid = 7, .path = "/tmp/outside/src", .aux = "" },
    };
    const r_control = reconcileIn(&diffs, &path_only, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 2), r_control.total);
    try std.testing.expectEqual(@as(usize, 0), r_control.by_rename_prefix);
}

test "reconcile: a renamed-in directory carries its children, and the count says so" {
    // The residue this cannot close. `papis add` renames a folder in from outside the
    // judged root; the engine never snapshotted the source, so which descendants came
    // with the move is unknowable. They are attributed to the move — and counted, so a
    // run with a window says how wide it is instead of hiding it.
    const diffs = [_]Difference{
        .{ .rel = "probe-doc", .how = .only_in_second },
        .{ .rel = "probe-doc/info.yaml", .how = .only_in_second },
        .{ .rel = "probe-doc/paper.pdf", .how = .only_in_second },
    };
    const ops = [_]Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .path = "/tmp/outside/staging", .aux = "/tmp/s/probe-doc" },
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
    // A caller can name the root through a symlink; macOS resolves /tmp to /private/tmp.
    // A join that knew one spelling would count operations under the other as naming
    // nothing, and refuse a fully observed run.
    const diffs = [_]Difference{.{ .rel = "key.json", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/private/tmp/s/key.json", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "/private/tmp/s", &buf).clean());
    // Control: with no alt spelling the same operation names nothing.
    try std.testing.expect(!reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: an operation naming the root itself is a name, not a skip" {
    // `relUnderRoot` returns `""` rather than null when the path IS the root. Answering
    // null instead reads as "this operation is outside the judged tree", and the change
    // at the root would be refused with the record that explains it sitting right there.
    const diffs = [_]Difference{.{ .rel = "", .how = .kind_differs }};
    const ops = [_]Op{.{ .class = .rmdir, .seq = 1, .pid = 7, .path = "/tmp/s", .aux = "" }};
    var buf: [2]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
    // Control: the same difference with the operation one level up is outside the tree.
    const outside = [_]Op{.{ .class = .rmdir, .seq = 1, .pid = 7, .path = "/tmp", .aux = "" }};
    try std.testing.expect(!reconcileIn(&diffs, &outside, &.{}, "/tmp/s", "", &buf).clean());
}

test "reconcile: markers and out-of-scope operations never name a path" {
    // A marker's path field is not a path the target operated on: `shim_ready` carries
    // the state directory, `unsupported` a syscall spelling, `kill_landed` and
    // `unresolved` the path the engine was talking about. Any of them accepted as a name
    // attributes a change to a record that describes no change.
    //
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
        .{ .class = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .class = .unsupported, .seq = 0, .pid = 7, .path = "/tmp/s/decoy-a", .aux = "" },
        .{ .class = .kill_landed, .seq = 0, .pid = 7, .path = "/tmp/s/decoy-b", .aux = "" },
        .{ .class = .unresolved, .seq = 0, .pid = 7, .path = "/tmp/s/decoy-c", .aux = "" },
        .{ .class = .write, .seq = 1, .pid = 7, .path = "/elsewhere/f", .aux = "" },
    };
    var buf: [8]Unaccounted = undefined;
    try std.testing.expectEqual(@as(usize, 4), reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).total);
}

test "reconcile: a path recorded through an interior symlink names what the snapshot holds" {
    // Measured, not reasoned: one `unlink` through `cur -> v1` PASSed on the shipped
    // 1.0.0 and refused here, naming `v1/f` — a fully observed run turned into UNKNOWN by
    // a spelling. The shim normalises path arguments lexically and records `cur/f`; the
    // snapshot never follows a link and holds the difference at `v1/f`.
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .only_in_first }};
    const ops = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    var buf: [4]Unaccounted = undefined;

    // Absolute link target, and the relative spelling of the same link.
    const abs = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v1" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &abs, "/tmp/s", "", &buf).clean());
    const rel_target = [_]Link{.{ .rel = "cur", .target = "v1" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &rel_target, "/tmp/s", "", &buf).clean());
    const dotted = [_]Link{.{ .rel = "links/cur", .target = "../v1" }};
    const via_dotted = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .path = "/tmp/s/links/cur/f", .aux = "" }};
    try std.testing.expect(reconcileIn(&diffs, &via_dotted, &dotted, "/tmp/s", "", &buf).clean());

    // Control: with no link recorded, the same operation names nothing — so the leg above
    // measures the substitution and not a join that accepts any path.
    try std.testing.expect(!reconcileIn(&diffs, &ops, &.{}, "/tmp/s", "", &buf).clean());
    // Control: a link that points somewhere else does not launder the path either.
    const wrong = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v2" }};
    try std.testing.expect(!reconcileIn(&diffs, &ops, &wrong, "/tmp/s", "", &buf).clean());
}

test "reconcile: link substitution follows a chain and survives a cycle" {
    // The chain is where a single scratch buffer would have had `substituteOnce`
    // overwrite its own input; the cycle is why the hop count is bounded. Neither shape
    // is exotic — `latest -> stable -> v1` is an ordinary release layout.
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/latest/f", .aux = "" }};
    const chain = [_]Link{
        .{ .rel = "latest", .target = "stable" },
        .{ .rel = "stable", .target = "v1" },
    };
    var buf: [4]Unaccounted = undefined;
    try std.testing.expect(reconcileIn(&diffs, &ops, &chain, "/tmp/s", "", &buf).clean());

    // A cycle terminates and refuses rather than spinning: reaching here at all is the
    // assertion.
    const cyc = [_]Link{
        .{ .rel = "a", .target = "b" },
        .{ .rel = "b", .target = "a" },
    };
    const cyc_ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a/f", .aux = "" }};
    try std.testing.expect(!reconcileIn(&diffs, &cyc_ops, &cyc, "/tmp/s", "", &buf).clean());
}

test "reconcile: an operation on the link itself names the link, not its target" {
    // The second regression the substitution introduced, and the mirror of the one it
    // fixed. `unlink("cur")` removes the LINK; the difference is at `cur`. Substituting
    // first and comparing only the result rewrote the record's `cur` to `v1` and left the
    // difference at `cur` named by nobody. Measured end to end: PASS exit 0 on the merge
    // base, UNKNOWN exit 2 naming `cur` after the substitution was added.
    const links = [_]Link{.{ .rel = "cur", .target = "v1" }};
    var buf: [4]Unaccounted = undefined;

    const removed = [_]Difference{.{ .rel = "cur", .how = .only_in_first }};
    const unlink_link = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .path = "/tmp/s/cur", .aux = "" }};
    try std.testing.expect(reconcileIn(&removed, &unlink_link, &links, "/tmp/s", "", &buf).clean());

    // The generation swap ADR 0032 names as the motivating layout: build the new link
    // beside the old one, then rename it over. Both records are on the link itself.
    const swapped = [_]Difference{.{ .rel = "cur", .how = .content_differs }};
    const swap_ops = [_]Op{
        .{ .class = .symlink, .seq = 1, .pid = 7, .path = "/tmp/s/cur.tmp", .aux = "" },
        .{ .class = .rename, .seq = 2, .pid = 7, .path = "/tmp/s/cur.tmp", .aux = "/tmp/s/cur" },
    };
    try std.testing.expect(reconcileIn(&swapped, &swap_ops, &links, "/tmp/s", "", &buf).clean());

    // Control: the substituted spelling still works alongside it, so accepting the
    // literal one has not replaced the resolution with a join that ignores links.
    const through = [_]Difference{.{ .rel = "v1/f", .how = .only_in_first }};
    const unlink_through = [_]Op{.{ .class = .unlink, .seq = 1, .pid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    try std.testing.expect(reconcileIn(&through, &unlink_through, &links, "/tmp/s", "", &buf).clean());
    // Control: accepting both spellings is not accepting everything.
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
    const linked = [_]Op{.{ .class = .link, .seq = 1, .pid = 7, .path = "/outside/src", .aux = "/tmp/s/d" }};
    const r = reconcileIn(&diffs, &linked, &.{}, "/tmp/s", "", &buf);
    try std.testing.expectEqual(@as(usize, 1), r.total);
    try std.testing.expectEqualStrings("d/child", buf[0].rel);
    try std.testing.expectEqual(@as(usize, 0), r.by_rename_prefix);
    // Control: the same shape as a rename does take it, so the leg measures the class and
    // not something both records fail.
    const renamed = [_]Op{.{ .class = .rename, .seq = 1, .pid = 7, .path = "/outside/src", .aux = "/tmp/s/d" }};
    try std.testing.expectEqual(@as(usize, 1), reconcileIn(&diffs, &renamed, &.{}, "/tmp/s", "", &buf).by_rename_prefix);
}

test "reconcile: a link matches whole components, and never picks between two" {
    // Two shapes one prefix test away from each other. `cur` must not match `current`,
    // and where `a` and `a/b` are both links the deeper one is the one the path crossed
    // last. Both branches were reachable and neither was measured.
    var buf: [4]Unaccounted = undefined;
    // `cur -> v1` must leave `current/f` alone. The difference is the one a partial-
    // component substitution WOULD produce — `current/f` minus `cur` plus `v1` — so a
    // record on `current/f` must not name it. Asserting instead that `current/f` itself
    // stays clean measures nothing: the literal spelling names it either way, which is
    // exactly what the first version of this leg did and why the mutation survived it.
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/current/f", .aux = "" }};
    const near = [_]Link{.{ .rel = "cur", .target = "v1" }};
    const mangled = [_]Difference{.{ .rel = "v1/rent/f", .how = .content_differs }};
    try std.testing.expect(!reconcileIn(&mangled, &ops, &near, "/tmp/s", "", &buf).clean());
    // Control: the run whose record names the path literally is still clean.
    const diffs = [_]Difference{.{ .rel = "current/f", .how = .content_differs }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &near, "/tmp/s", "", &buf).clean());

    // Two links on one path can only come from the tree changing shape between the two
    // samples — `a` a directory holding `a/b` in one, a link in the other. There is no
    // ordering to pick with, so nothing is substituted and the run refuses.
    // The difference is what picking one of them lands on, so choosing names it and
    // refusing to choose does not.
    //
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
    const deep_ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a/b/f", .aux = "" }};
    const one_reading = [_]Difference{.{ .rel = "y/f", .how = .content_differs }};
    try std.testing.expect(!reconcileIn(&one_reading, &deep_ops, &ambiguous, "/tmp/s", "", &buf).clean());
    // Control: on its own that link does resolve to exactly this spelling, so the leg
    // measures the refusal to choose and not a substitution that could not have produced
    // the difference anyway.
    const only_deep = [_]Link{.{ .rel = "a/b", .target = "/tmp/s/y" }};
    try std.testing.expect(reconcileIn(&one_reading, &deep_ops, &only_deep, "/tmp/s", "", &buf).clean());
}

test "reconcile: a link retargeted mid-run is not used to name anything" {
    // Neither reading is right, so neither is taken. With `cur` moving `v1 -> v2`, the
    // same records excuse `v1/f` under the initial spelling and refuse it under the final
    // one — the reconciliation holds no ordering between the retarget and the operations,
    // so any choice invents one. Dropping the link refuses, which is the side a detector
    // belongs on.
    const diffs = [_]Difference{.{ .rel = "v1/f", .how = .only_in_second }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
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

    // Control: a link that did NOT move survives collection and does name the path, so
    // the leg measures the retarget and not collection failing on every input.
    var steady: std.ArrayList(Link) = .empty;
    defer steady.deinit(std.testing.allocator);
    try collectLinks(std.testing.allocator, before, before, &steady);
    try std.testing.expectEqual(@as(usize, 1), steady.items.len);
    try std.testing.expect(reconcileIn(&diffs, &ops, steady.items, "/tmp/s", "", &buf).clean());
}

test "reconcile: an absolute link target is folded like a relative one" {
    // `.` and `..` were folded on the relative branch only, so `cur -> /tmp/s/v1/../v2`
    // resolved to `v1/../v2/f` — a spelling no snapshot `rel` can hold, because those are
    // built by walking the tree. A refusal on a run whose record names the path.
    const diffs = [_]Difference{.{ .rel = "v2/f", .how = .content_differs }};
    const ops = [_]Op{.{ .class = .write, .seq = 1, .pid = 7, .path = "/tmp/s/cur/f", .aux = "" }};
    var buf: [4]Unaccounted = undefined;
    const dotted = [_]Link{.{ .rel = "cur", .target = "/tmp/s/v1/../v2" }};
    try std.testing.expect(reconcileIn(&diffs, &ops, &dotted, "/tmp/s", "", &buf).clean());
    // Control: a target that climbs out of the judged root substitutes nothing.
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

    // only_in_first and only_in_second in one comparison, so a merge that advances the
    // wrong cursor cannot pass by reporting the right count with the wrong sides.
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
    // `new` sorts before `same`, `gone` before both: the merge must not assume the
    // caller's construction order.
    std.mem.sort(Entry, b2.entries.items, {}, lessThanRel);
    const c2 = diffSnapshots(a2, b2, &buf);
    try std.testing.expectEqual(@as(usize, 2), c2.total);
    try std.testing.expectEqual(@as(usize, 2), c2.stored);
    try std.testing.expectEqualStrings("gone", buf[0].rel);
    try std.testing.expectEqual(Difference.How.only_in_first, buf[0].how);
    try std.testing.expectEqualStrings("new", buf[1].rel);
    try std.testing.expectEqual(Difference.How.only_in_second, buf[1].how);

    // kind before content: the pre-side is an empty directory, the post-side a file
    // with bytes. Reporting `content_differs` here would name the smaller half.
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
    // Five entries only the second snapshot has, into a buffer that holds two. A
    // `total` that stopped at the buffer would report a two-path split for a
    // five-path one — the understatement this field exists to prevent.
    for ([_][]const u8{ "a", "b", "c", "d", "e" }) |rel|
        try b.entries.append(ba, .{ .rel = rel, .kind = .file, .content = "z" });
    var small: [2]Difference = undefined;
    const c = diffSnapshots(a, b, &small);
    try std.testing.expectEqual(@as(usize, 5), c.total);
    try std.testing.expectEqual(@as(usize, 2), c.stored);
    try std.testing.expect(!c.equal());
}

test "a Difference that escapes its snapshot must own its bytes" {
    // The ownership rule this file's `Difference` doc states, held by a test rather than
    // by a comment. `only_in_second` is the only kind that borrows from the SECOND
    // snapshot, and a caller that frees that snapshot before rendering reads freed
    // memory — which is exactly what `main.zig`'s `observeAgain` did until review found
    // it (reproduced there as a segfault).
    //
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
        // Same shape as `observeAgain`: the second snapshot is a local, released by
        // this block's own `defer`, while the differences outlive it.
        var second = Snapshot{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
        defer second.deinit();
        const sa = second.arena.allocator();
        const owned = try sa.dupe(u8, "only-in-second.txt");
        try second.entries.append(sa, .{ .rel = owned, .kind = .file, .content = "x" });

        const out = try arena.alloc(Difference, 4);
        const count = diffSnapshots(first, second, out);
        try std.testing.expectEqual(@as(usize, 1), count.total);
        try std.testing.expectEqual(Difference.How.only_in_second, out[0].how);
        // The copy under test. Deleting these two lines is the defect, and the
        // assertion below then reads 0xAA.
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

/// Sort, then check what `find` will assume. Both producers end here, so neither can
/// acquire the ordering without the check that goes with it — the two used to be separate
/// statements repeated in each, and deleting one of them left the other's test green.
///
/// Sorting also makes restore create parents before children, and makes two snapshots of
/// the same tree compare equal regardless of directory iteration order. A duplicate `rel`
/// would mean `walk` emitted the same path twice, which no directory traversal should
/// produce — the sort would not catch it, and a binary search would silently pick either
/// one (#262).
pub fn finalizeEntries(snap: *Snapshot) error{EntriesNotSortedUnique}!void {
    std.mem.sort(Entry, snap.entries.items, {}, lessThanRel);
    if (validateSortedUnique(snap.entries.items)) |_| return error.EntriesNotSortedUnique;
}

/// Whether `rel` is a declared scratch path or lies beneath one (ADR 0043). One rule for
/// the path itself and its subtree: `rel == p`, or `rel` starts with `p` followed by `/`.
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

/// A snapshot built from literal pairs, for tests.
///
/// Sorts, like `takeSnapshot` does. It did not, and that made the sorted order an
/// accident of one producer rather than a property every `Snapshot` has — which is
/// exactly what `find` now depends on. Ten of its call sites (most of them the judge
/// tests, which stayed in `engine.zig`) pass their pairs in an order that is not
/// lexicographic, so a `find` that assumed sorting would have returned wrong answers
/// there rather than failing loudly (#262).
///
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
    // The same finalizer `takeSnapshot` uses, so a fixture cannot be built under weaker
    // rules than a real snapshot.
    try finalizeEntries(&snap);
    return snap;
}

/// A linear scan over the same entries, kept here as the oracle the binary search is
/// checked against. It is deliberately the implementation `find` used to have, and it
/// counts through the same primitive, so the "comparisons are logarithmic" test below
/// measures both the same way.
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

    // Every key that is present.
    for (snap.entries.items) |e| {
        const got = snap.find(e.rel) orelse return error.MissingEntry;
        const want = linearFind(snap, e.rel) orelse return error.MissingEntry;
        try std.testing.expectEqualStrings(want.rel, got.rel);
        try std.testing.expectEqualStrings(want.content, got.content);
    }

    // Absent keys on all three sides of the range: below the first, between two, above
    // the last. A binary search that mishandles its bounds typically fails at exactly one
    // of these, so a single absent key would not be enough.
    for ([_][]const u8{ "aaa", "kz.json", "zzzz" }) |missing| {
        try std.testing.expect(snap.find(missing) == null);
        try std.testing.expect(linearFind(snap, missing) == null);
    }
}

test "find costs a logarithmic number of comparisons, not a linear one" {
    const gpa = std.testing.allocator;

    // 1024 entries, lexicographically ordered by construction ("e0000".."e1023").
    var names: [1024][8]u8 = undefined;
    var pairs: [1024][2][]const u8 = undefined;
    for (0..1024) |i| {
        _ = std.fmt.bufPrint(&names[i], "e{d:0>4}", .{i}) catch unreachable;
        pairs[i] = .{ names[i][0..5], "x" };
    }
    var snap = try testSnapshot(gpa, &pairs);
    defer snap.deinit();

    // The worst-case present key and an absent one. log2(1024) = 10, so a correct binary
    // search needs at most 11 comparisons; the linear scan this replaced needs 1024 for
    // the last entry.
    //
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

    // Sorted and unique: no problem.
    try std.testing.expect(validateSortedUnique(try mk(arena, &.{ "a", "b", "c" })) == null);
    // Fewer than two entries cannot violate either half.
    try std.testing.expect(validateSortedUnique(try mk(arena, &.{"only"})) == null);
    try std.testing.expect(validateSortedUnique(try mk(arena, &.{})) == null);

    // The two failures are reported apart. A check that only asked "is this
    // non-decreasing?" would pass the duplicate case, leaving the uniqueness half of the
    // invariant unverified — and `std.mem.sort` does not remove duplicates, so that half
    // is reachable.
    try std.testing.expectEqual(OrderProblem.out_of_order, validateSortedUnique(try mk(arena, &.{ "b", "a" })).?);
    try std.testing.expectEqual(OrderProblem.duplicate, validateSortedUnique(try mk(arena, &.{ "a", "a" })).?);
    // Adjacent duplicates in the middle of an otherwise sorted list.
    try std.testing.expectEqual(OrderProblem.duplicate, validateSortedUnique(try mk(arena, &.{ "a", "b", "b", "c" })).?);
}

test "the producers refuse a snapshot that violates the order find searches by" {
    const gpa = std.testing.allocator;
    // Reaches `testSnapshot`'s own boundary check: the pairs sort fine, but two of them
    // carry the same rel. This is what catches a validator that exists but is never
    // called from a producer.
    try std.testing.expectError(
        error.EntriesNotSortedUnique,
        testSnapshot(gpa, &.{ .{ "dup.txt", "one\n" }, .{ "dup.txt", "two\n" } }),
    );
}
