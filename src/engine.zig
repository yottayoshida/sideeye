//! The exploration engine: snapshot the state, run the target under the shim, kill it
//! at each operation in turn, and judge what is left behind.
//!
//! Every verdict this file produces has to survive one question: could it be wrong in
//! the direction of saying PASS when something was missed? The structural detectors
//! exist because of that question, and they run before any world is explored — if the
//! recording run is not trustworthy, exploring five hundred worlds built on it only
//! multiplies the untrustworthiness.

const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");
/// Read for the ancestor-probe entry below (#358); zero effect on a shipped build.
const build_options = @import("engine_build_options");

const Allocator = std.mem.Allocator;

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
        count.total += 1;
        if (count.stored < out.len) {
            out[count.stored] = .{ .rel = rel, .how = how };
            count.stored += 1;
        }
    }
    return count;
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

/// `EntriesNotSortedUnique` means the snapshot came out of `walk` in a shape `find` cannot
/// search: out of order, or holding the same `rel` twice. Neither should be reachable — the
/// sort above guarantees the first and a directory traversal cannot produce the second — so
/// this is the check refusing rather than letting a binary search answer from a list that
/// does not satisfy its precondition (#262).
pub const SnapshotError = error{ OutOfMemory, ReadFailed, TooDeep, PathTooLong, ClassifyFailed, EntriesNotSortedUnique, FileTooLarge, TreeTooLarge };

/// How deep the snapshot walk descends before refusing — **and how deep `deleteTreeAt`
/// descends before refusing to delete**, which is the reason to think twice before tuning
/// it: raising this widens what `restore` will empty, not only what the snapshot will
/// read. ADR 0024 cites it as the descriptor bound for the same reason.
///
/// `pub` because the refusal names it (#351): an operator told only "could not snapshot"
/// has no way to learn what to change. Compared with a strict `>`, so a tree of exactly
/// this many levels is fine and one level more is not — measured at 32 passing and 33
/// refusing, and refusal text must say "deeper than N", never "cap N".
pub const max_depth = 32;

/// The per-FILE byte cap on snapshot reads (#265). Every other read in the pipeline
/// is capped (the case file at 1 MiB, the MCP report at 4 MiB); the snapshot path
/// runs hundreds of times per explore over target-sized data and was the unbounded
/// one — a single multi-gigabyte state file turned the judgment into an OOM kill
/// with no report. L0 judgment is byte-level comparison, so the tree is held in memory
/// whole: pre and post coexist, and **four snapshots are live at once** where the crashed
/// sequence re-samples (`main.zig`'s `initial`, `final`, `crashed`, `crashed_again`).
/// One file at exactly this cap leaves the arena holding **100,663,448 bytes** (96.0 MiB),
/// so the largest resident pair is near 192 MiB.
///
/// **Both of those numbers replace wrong ones, measured by #323.** The count said three;
/// `crashed_again` predates this comment by a fortnight, so it was wrong when written
/// rather than gone stale. And the pair was given as "near 128 MiB", which reasoned from
/// file size straight to memory — the arena costs 1.50x what it holds, which is
/// `ArenaAllocator`'s own node growth factor and not a property of the tree.
///
/// Per file. The tree's total is bounded separately, by `max_state_tree_bytes` — this
/// constant is not that ceiling and never was, which is what the sentence here used to
/// say when there was no other ceiling to point at.
pub const max_state_file_bytes: usize = 64 * 1024 * 1024;

/// The whole-snapshot ceiling (#323). `max_state_file_bytes` bounds one read; nothing
/// bounded the sum, so a tree of files each comfortably under the per-file cap — 60 MiB
/// a thousand times over — passed every check and ended in an OOM kill with no report,
/// which is the failure the per-file cap exists to remove. Under Linux's overcommit the
/// allocator's own `OutOfMemory` never arrives to be handled: the pages are touched, so
/// the kernel kills the process. This ceiling is what makes running out of memory
/// reportable at all on that platform. (macOS is unmeasured here; `mmap` may fail first
/// and reach `error.OutOfMemory`.)
///
/// **What is measured is the arena, not the tree.** The count is
/// `ArenaAllocator.queryCapacity()` — the backing memory the snapshot has actually taken —
/// rather than a sum of file sizes. A sum has no term for what an entry costs beside its
/// content, and the shape that exposes that is not exotic: **50,000 empty files hold
/// 12,959,676 bytes against a content sum of zero**. Asking the allocator also covers,
/// without naming any of them, the symlink target dupe, the `rel` that `.missing`
/// allocates and drops, and the entry list's own growth.
///
/// The check runs once per directory entry. It is not throttled: `ArenaAllocator` sizes
/// each node at least 1.5x its predecessor, so the node count is logarithmic in the total
/// and `queryCapacity` is a walk of tens of pointers, not thousands.
///
/// **What the arena costs above the content, measured.** With `readWhole` reserving from
/// the file's own length, one file costs a flat **1.50x** — 100,663,448 bytes for 64 MiB,
/// 50,331,800 for 32 MiB, 1,573,016 for 1 MiB — which is the node growth factor and
/// nothing else. Several large files cost more, because a request that does not fit the
/// current node takes a new one sized 1.5x *(node + request)*: two 64 MiB files reach
/// 336 MiB. So the ceiling is not a statement about how many bytes of files a tree may
/// hold, and the refusal says which of the two it is reporting.
///
/// **That term still orders trees by something other than their size, and the reservation
/// did not remove it.** It removed the stranding term, which had two 32 MiB files costing
/// more than two 64 MiB ones. What is left inverts a different pair: at this ceiling,
/// **two 50 MiB files (100 MiB of content) are refused at 262 MiB while four 32 MiB files
/// (128 MiB) are accepted at 168 MiB** — a strictly smaller tree, in files and in bytes,
/// refused where a larger one passes. Fewer, larger reads cost more than more, smaller
/// ones, and the ceiling counts the cost.
///
/// **The value, and what it accepts, measured rather than derived.** At 256 MiB every
/// 128 MiB-of-content shape tried is accepted — 4x32, 8x16, 16x8, 64x2 MiB — while in the
/// two-file family the boundary is far lower: **2x48 MiB (96 MiB) is accepted and 2x49 MiB
/// (98 MiB) is refused**, so "128 MiB of content fits" is not a rule that can be read off
/// the shapes above. 256 MiB of content is refused in every shape tried.
///
/// **What selected this value is that table, not a contradiction argument.** A ceiling
/// must clear one file at the per-file cap, or it would refuse a tree holding exactly what
/// the other ceiling permits — 256 MiB clears that at 96 MiB with room, and so would 128.
/// **It does not clear two such files** (336 MiB), and no value below that could; the
/// criterion is about n=1 and says nothing about n=2. 128 MiB was rejected on the table
/// instead: there two 32 MiB files (64 MiB of content, 168 MiB of arena) are refused, and
/// refusing a 64 MiB tree is further from what an operator expects than refusing a 98 MiB
/// one.
///
/// It is not derived from the corpus, which would put it five orders of magnitude lower;
/// the corpus is the check that it refuses nothing real. Four defines can be built on the
/// machine this was measured on, and their snapshots cost **888, 846, 846 and 544 bytes**
/// (`cargo` and `cargo-r2` build the same tree, which is why three numbers cover four
/// defines). That is **4 of the 45** files matching `grep -rl '^state = ' --include='*.toml'`
/// — the count includes the quickstart and dogfood defines, not only `spike/**/ops/`, and
/// counts define files rather than distinct state trees. The rest need tools this machine
/// does not have (borg, hg, jj, poetry, black, papis, himalaya, topydo, abook, khal, stow,
/// pass, buku, calcurse, devtodo, watson), and what was measured is the pre-state each
/// `setup.sh` builds, not the tree after the operation has run.
///
/// Four snapshots are live at once at the widest point (`main.zig`'s `initial`, `final`,
/// `crashed`, `crashed_again`), so a completed run's resident judgement data is bounded
/// by four times this, plus the two trace arenas. The run that refuses may hold more, for
/// the node-growth reason above, and then exits. Raising this value is not the safe
/// direction: here a refusal is the good outcome, and the alternative to refusing is the
/// unreported death above.
pub const max_state_tree_bytes: usize = 256 * 1024 * 1024;

/// Both ceilings, together, so a call site cannot supply one without the other.
///
/// **A tree can break both, and which one is reported depends on `readdir` order.** The
/// per-file cap wins for whatever entry the walk reaches first, because `readWhole` returns
/// before the entry is appended and the tree accounting never sees it. Both refusals are
/// honest and both produce the same verdict, so this is a property rather than a defect —
/// recorded because it is the same order-dependence `TreeTooLargeDiag` cites when it
/// declines to name a largest contributor, and leaving it unsaid in one place while relying
/// on it in the other is how a codebase ends up arguing with itself.
pub const SnapshotCaps = struct {
    file: usize,
    tree: usize,

    /// What production passes. Every non-test call site uses this rather than spelling
    /// the constants, so the shipped pair has one definition.
    pub const shipped: SnapshotCaps = .{ .file = max_state_file_bytes, .tree = max_state_tree_bytes };
};

/// Which file broke the cap, for the refusal that names it (#265). Zig errors carry
/// no payload, and the snapshot's own arena dies with the error — so the caller
/// hands this fixed-size, caller-owned box in and reads it back on error.FileTooLarge.
pub const FileTooLargeDiag = struct {
    rel_buf: [contract.max_path]u8 = undefined,
    rel_len: usize = 0,
    /// From lseek(SEEK_END) at the moment the cap broke; null when even that failed
    /// (the refusal then says "over the cap" and no more — a size nobody measured
    /// must not appear in the message).
    size: ?u64 = null,

    pub fn rel(self: *const FileTooLargeDiag) []const u8 {
        return self.rel_buf[0..self.rel_len];
    }
};

/// What the whole-tree refusal can say (#323), filled at the moment the ceiling broke.
///
/// **Every field describes what the walk had read, not the tree.** The walk stops at the
/// break, so `content` and `entries` are a prefix in directory-iteration order and the
/// tree is larger than both by an unmeasured amount. Continuing in an accounting-only
/// mode would make them the tree's real figures, and was rejected: the continuation still
/// runs `TooDeep`, `PathTooLong`, `ClassifyFailed` and `readLinkTarget`'s `ReadFailed`,
/// and `walk`'s `opendir(...) orelse return` treats an unopenable directory as empty — so
/// either a later failure replaces this refusal or the "real" total silently omits a
/// subtree. `FileTooLargeDiag.size` above settles the same question the other way: a size
/// nobody measured must not appear in the message. The message says which of the two
/// these are, and points at `du`/`find` for the rest.
pub const TreeTooLargeDiag = struct {
    /// `ArenaAllocator.queryCapacity()` when the ceiling broke — the quantity capped.
    reached: usize = 0,
    /// File and symlink content bytes appended before the break. Reproducible with `du`
    /// only for the prefix that was read, which is why the message says so.
    content: u64 = 0,
    /// Entries appended before the break, `.dir` and `.other` included.
    entries: u64 = 0,
};

/// The caller-owned box both snapshot refusals report through. One struct rather than two
/// optional pointers so a call site that wants either gets both: the walk decides which
/// ceiling broke, and a caller cannot be in a position to have passed only the other one.
pub const SnapshotDiag = struct {
    file: FileTooLargeDiag = .{},
    tree: TreeTooLargeDiag = .{},
};

fn joinZ(buf: []u8, a: []const u8, b: []const u8) error{PathTooLong}![:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, "{s}/{s}", .{ a, b }) catch return error.PathTooLong;
    return s;
}

/// The cap is a parameter for the same reason readLinkTarget's buffer is one: against
/// the production constant a test would need a 64 MiB fixture to see the refusal fire,
/// so the boundary would be a claim nobody falsifies — against a small cap the tests
/// below fire it for real. `size_out`, when given, receives the file's size from
/// lseek(SEEK_END) at the moment the cap breaks (null if even that fails): the
/// refusal that names the file wants to name its size, and the read loop stopped
/// before it could know.
fn readWhole(arena: Allocator, path: [*:0]const u8, max: usize, size_out: ?*?u64) SnapshotError![]const u8 {
    const fd = posix.open(path, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return error.ReadFailed;
    defer _ = posix.close(fd);

    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;

    // Ask the file how long it is and take that much at once, instead of doubling the way
    // there (#323). The size is a HINT and nothing below trusts it: the loop still reads
    // to EOF, so a file that grows keeps growing the list and one that shrinks just
    // over-reserved. What it changes is the arena.
    //
    // `ArenaAllocator` never frees, and its resize fast path only extends the allocation
    // sitting at the end of the current node — so a doubling list that outgrows its node
    // is copied into a new one (sized 1.5x its predecessor) and the old copy is stranded
    // there for the life of the snapshot. Measured before this: one 64 MiB file left the
    // arena holding 113,780,014 bytes, and — because where the growth falls relative to a
    // node boundary decides how much is stranded — the cost was not even monotonic in the
    // tree, with two 32 MiB files costing more than two 64 MiB ones. A ceiling read off
    // the arena inherits both, and "a tree that fits and a bigger tree that does not"
    // stops being a property an operator can predict. After: 100,663,448 for the same
    // file, a flat 1.50x that is the arena's node growth factor and nothing else.
    //
    // Reserved exactly, never `max + chunk` on a small file: over-reserving 64 KiB per
    // entry is the shape a state tree of many small files is made of.
    const reserve_from = posix.lseek(fd, 0, posix.SEEK_END);
    if (reserve_from > 0) {
        if (posix.lseek(fd, 0, posix.SEEK_SET) < 0) return error.ReadFailed;
        const len: usize = @intCast(reserve_from);
        // Past the cap the read stops one chunk over it, so that is all it can need.
        //
        // **A failed reservation is not an error.** The other caller of this function is
        // `readTraceCapped`, whose catch collapses everything except `FileTooLarge` into
        // an empty `TraceInfo` — which the engine reads as `no_shim_marker`. Returning
        // `OutOfMemory` from here would turn "the trace is larger than this engine will
        // read" into "the shim never initialised" whenever the reservation could not be
        // met, which is the exact relabelling the cap's own comment says is worse than
        // having no cap. Dropping it leaves the read loop to grow as it did before this
        // reservation existed, so the failure path is the one that was there already.
        list.ensureTotalCapacityPrecise(arena, if (len <= max) len else max +| chunk.len) catch {};
    }
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try list.appendSlice(arena, chunk[0..@intCast(n)]);
        if (list.items.len > max) {
            if (size_out) |so| {
                const end = posix.lseek(fd, 0, posix.SEEK_END);
                so.* = if (end >= 0) @intCast(end) else null;
            }
            return error.FileTooLarge;
        }
    }
    return list.items;
}

/// What the walk carries down the recursion unchanged. It was seven parameters before the
/// tree ceiling needed an arena handle and a second diag, which would have made ten; the
/// reason for the struct is that plain, not a claim that it makes a mistake unbuildable.
const WalkCtx = struct {
    /// The arena *state*, not just its allocator: the ceiling is read off it.
    arena_state: *std.heap.ArenaAllocator,
    entries: *std.ArrayList(Entry),
    root: []const u8,
    caps: SnapshotCaps,
    diag: ?*SnapshotDiag,
    content: u64 = 0,
    seen: u64 = 0,

    fn arena(self: *const WalkCtx) Allocator {
        return self.arena_state.allocator();
    }

    /// Charge one entry and refuse if the snapshot's arena has passed its ceiling.
    ///
    /// Called once per directory entry, after everything that entry allocates — so the
    /// overshoot is one entry's allocations rather than a batch's, and `.missing`, which
    /// allocates `rel` and appends nothing, is charged like the rest because the arena
    /// still holds it.
    fn charge(self: *WalkCtx, content_len: usize) SnapshotError!void {
        self.content += content_len;
        self.seen += 1;
        const reached = self.arena_state.queryCapacity();
        if (reached <= self.caps.tree) return;
        if (self.diag) |d| d.tree = .{ .reached = reached, .content = self.content, .entries = self.seen };
        return error.TreeTooLarge;
    }
};

fn walk(ctx: *WalkCtx, rel_prefix: []const u8, depth: usize) SnapshotError!void {
    if (depth > max_depth) return error.TooDeep;

    const arena = ctx.arena();
    var dir_buf: [contract.max_path]u8 = undefined;
    const dir_path = if (rel_prefix.len == 0)
        std.fmt.bufPrintZ(&dir_buf, "{s}", .{ctx.root}) catch return error.PathTooLong
    else
        try joinZ(&dir_buf, ctx.root, rel_prefix);

    const dirp = posix.opendir(dir_path.ptr) orelse return;
    defer _ = posix.closedir(dirp);

    while (posix.readdir(dirp)) |ent| {
        const name = posix.direntName(ent);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const rel = if (rel_prefix.len == 0)
            try arena.dupe(u8, name)
        else
            try std.fmt.allocPrint(arena, "{s}/{s}", .{ rel_prefix, name });

        var full_buf: [contract.max_path]u8 = undefined;
        const full = try joinZ(&full_buf, ctx.root, rel);
        var kind = posix.kindFromDirent(ent);
        // Some filesystems leave dirent.type unset; ask the path directly then —
        // without opening it (a FIFO would block) and without following links (#5).
        if (kind == .missing) kind = posix.kindOfPathNoFollow(full.ptr) catch
            // Fail-closed: an entry that cannot be classified must not silently
            // vanish from the snapshot — that would route it around #5's refusal.
            return error.ClassifyFailed;

        // Bytes this entry added to the arena's content, for the refusal's account.
        var charged: usize = 0;
        switch (kind) {
            .dir => {
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .dir, .content = "" });
                // Charged before descending, so the ceiling is not reached only on the
                // way back up out of a deep subtree.
                try ctx.charge(0);
                try walk(ctx, rel, depth + 1);
                continue;
            },
            .file => {
                var size: ?u64 = null;
                const content = readWhole(arena, full.ptr, ctx.caps.file, &size) catch |e| {
                    if (e == error.FileTooLarge) if (ctx.diag) |d| {
                        d.file.rel_len = @min(rel.len, d.file.rel_buf.len);
                        @memcpy(d.file.rel_buf[0..d.file.rel_len], rel[0..d.file.rel_len]);
                        d.file.size = size;
                    };
                    return e;
                };
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .file, .content = content });
                charged = content.len;
            },
            .symlink => {
                // The link itself, never what it points at: readlink, no following.
                var tbuf: [contract.max_path]u8 = undefined;
                const target = readLinkTarget(full.ptr, &tbuf) orelse return error.ReadFailed;
                const held = try arena.dupe(u8, target);
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .symlink, .content = held });
                charged = held.len;
            },
            // Sockets, FIFOs and devices are recorded as present but opaque — so the
            // engine can refuse honestly: restore cannot recreate them, and since #5
            // any snapshot carrying one stops the run (`unsupported_state_entry`)
            // instead of exploring a tree the recording never had. (Symlinks left
            // this bucket in #122: they are first-class above.)
            .other => try ctx.entries.append(arena, .{ .rel = rel, .kind = .other, .content = "" }),
            // Nothing is appended — but `rel` was allocated above and the arena keeps it,
            // so this is charged too. A tree that churns temporary files (which is most
            // of what this engine watches) reaches here often.
            .missing => {},
        }
        try ctx.charge(charged);
    }
}

/// Read a symlink's target into `buf`, fail-closed: null on error AND on a result
/// that fills the buffer, because readlink reports no truncation — an exact fit and
/// a cut-off target return the same length, and a truncated target restored later
/// would be a different link. The buffer is a parameter so the boundary is testable:
/// against `max_path` (== PATH_MAX) no real platform can make readlink fill it, so a
/// guard buried in `walk` would be a claim nobody can falsify (R1); against a small
/// buffer the test below fires it for real.
fn readLinkTarget(path_z: [*:0]const u8, buf: []u8) ?[]const u8 {
    const n = posix.readlink(path_z, buf.ptr, buf.len);
    if (n < 0 or @as(usize, @intCast(n)) >= buf.len) return null;
    return buf[0..@intCast(n)];
}

fn lessThanRel(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.rel, b.rel);
}

pub fn takeSnapshot(gpa: Allocator, root: []const u8) SnapshotError!Snapshot {
    return takeSnapshotCapped(gpa, root, SnapshotCaps.shipped, null);
}

/// The capped form (#265, widened to the tree total by #323): production call sites pass
/// `SnapshotCaps.shipped` and a diag so the refusal can name what broke; tests pass small
/// caps so both boundaries are falsifiable without 64 MiB fixtures.
pub fn takeSnapshotCapped(gpa: Allocator, root: []const u8, caps: SnapshotCaps, diag: ?*SnapshotDiag) SnapshotError!Snapshot {
    var snap: Snapshot = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .entries = .empty,
    };
    errdefer snap.arena.deinit();

    var ctx: WalkCtx = .{
        .arena_state = &snap.arena,
        .entries = &snap.entries,
        .root = root,
        .caps = caps,
        .diag = diag,
    };
    try walk(&ctx, "", 0);
    try finalizeEntries(&snap);
    return snap;
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
fn finalizeEntries(snap: *Snapshot) error{EntriesNotSortedUnique}!void {
    std.mem.sort(Entry, snap.entries.items, {}, lessThanRel);
    if (validateSortedUnique(snap.entries.items)) |_| return error.EntriesNotSortedUnique;
}

pub const RestoreError = error{ PathTooLong, DeleteFailed, CreateFailed, UnsafeRoot };

/// Locations a destructive root must not name, nor sit inside.
///
/// A denylist, not a safety boundary: it stops the mistake that has a name — a system
/// path where a scratch path was meant — and claims nothing about the ones that do not.
/// The depth test below cannot carry this. Measured on this repository's own corpus of
/// committed state paths, depth ranks danger backwards: `/tmp/quickstart-state` (the
/// shipped quickstart define) is shallower than `/var/lib/myapp` (what the quickstart
/// used to suggest), so any "at least N components" rule refuses the former while
/// accepting the latter.
///
/// Entries are spelled the way a root arrives here. Both call sites hand over the
/// realpath'd spelling, and on macOS `/etc` and `/var/lib` resolve through `/private`,
/// so a list written in the pre-resolution spelling is silently inert on that platform.
///
/// `/var` itself is deliberately absent: `$TMPDIR` on macOS resolves to
/// `/private/var/folders/...`, and denying that tree would refuse the platform's own
/// scratch space.
///
/// `/opt` and `/srv` are absent for a different reason, and it is a judgement rather than
/// a measurement. They are site-local trees an operator populates, so `/opt/myapp/state`
/// is a plausible scratch copy in a way `/var/lib/myapp` is not — and there is no
/// override flag here, so a wrong entry is a wall rather than a warning. The corpus this
/// list was measured against contains nothing under either, which means that measurement
/// says nothing about them in the direction that matters.
///
/// sunset: **the condition that used to stand here was wrong, and #327 is what showed it.**
/// It said to delete this list once the destructive path held the root open by descriptor,
/// because that closes the swap window `assertRootResolvesToItself` only narrows. The walk
/// now does hold the root open — and nothing about this list is discharged by it. Holding
/// `/etc` by descriptor deletes `/etc` just as thoroughly; the swap window is about keeping
/// a correct target, and this list is about being handed a wrong one. Two neighbouring
/// defences, written as if one subsumed the other.
///
/// The list also has a second consumer whose *immediate* job is naming rather than
/// deleting: `mcp.zig` runs `assertSafeNamingRoot` on `SIDEEYE_MCP_ROOT` at startup. A
/// sunset phrased around deletion would authorise removing the list while that vet still
/// depends on it. **"No delete behind it" would be too strong**: with
/// `SIDEEYE_MCP_STATE_ROOT` unset the server passes the root itself as the destruction
/// range (`mcp.zig`'s fallback), so what that vet admits is what a replayed case may
/// then empty, one level down.
///
/// **Both consumers now depend on the list twice over** (#329 for the naming vet, #358 for
/// the destructive one). The entries are read outwards as well as inwards, so deleting the
/// list would not merely stop refusing roots inside these trees — it would also stop
/// refusing their ancestors, silently, since no separate ancestor rule exists to survive.
/// On the destructive side that means a root one level above a system tree becomes
/// something the engine will empty. It would additionally remove one of the three checks
/// that currently refuse a root of "/", which is the fail-open case. None of that changes
/// the conditions below; it changes how much goes with the list when they are met.
///
/// So: delete this list when **neither consumer can be handed a mistyped location** —
/// (1) the destructive root stops being a hand-written value. It arrives from exactly two
///     places — `--state` and a case's `define.state` — and both would have to become
///     engine-derived. (`SIDEEYE_MCP_ROOT` and `--state-under` are deliberately not on
///     that list: they *constrain* where a root may resolve and never supply one. Putting
///     them here would repeat the conflation this note is being corrected for.); and
/// (2) the startup vet in `mcp.zig` no longer needs a name-based refusal.
///
/// Rejected as conditions, both recorded because they are the tempting ones: an override
/// flag arriving (the `/opt`/`/srv` paragraph above turns on there being no such flag, so
/// its arrival is a reason to *list* those trees, not to drop the list), and measuring zero
/// accidents in the corpus (a guard whose job is to make the accident impossible cannot be
/// retired by the accident not happening — that measurement cannot tell the two apart).
const denied_trees = shipped_denied_trees ++ probe_denied_trees;

const shipped_denied_trees = [_][]const u8{
    "/usr",  "/etc",   "/bin", "/sbin", "/lib", "/lib64",
    "/boot", "/dev",   "/proc", "/sys",
    "/var/lib", "/var/db", "/var/spool",
    // Linux resolves /var/run to /run and /var/lock to /run/lock, so the /var spellings
    // never arrive here; both are listed because a distribution that keeps them real
    // would send the other one. Same reason the /private entries below exist.
    "/var/run", "/run",
    "/System", "/Library", "/Applications",
    "/private/etc", "/private/var/lib", "/private/var/db", "/private/var/spool",
    "/private/var/run",
};

/// Empty in every shipped build; one synthetic entry under `-Dtest-ancestor-probe` (#358).
///
/// The outward read refuses a root that is an ancestor of a denied entry. The only such
/// root the destructive predicate did not already refuse by depth is `/private/var` —
/// root-owned and macOS-only, so acceptance cannot plant a sentinel in it and watch the
/// sentinel die. This entry manufactures the same shape somewhere acceptance can write:
/// its parent `/tmp/se-anc-probe` is an ancestor with two components.
///
/// **Both spellings, because the root arrives resolved.** On macOS `/tmp/se-anc-probe`
/// resolves to `/private/tmp/se-anc-probe`, and a list written only in the pre-resolution
/// spelling is silently inert there — the failure the `/private/*` entries above exist
/// for. The leg itself runs on Linux only; the list does not depend on that.
const probe_denied_trees: [if (build_options.ancestor_probe) 2 else 0][]const u8 =
    if (build_options.ancestor_probe)
        .{ "/tmp/se-anc-probe/x", "/private/tmp/se-anc-probe/x" }
    else
        .{};

/// Scratch roots that are legitimate parents but never legitimate targets.
///
/// These are matched exactly, not as trees: `/tmp/x/state` is the ordinary case and must
/// pass. The depth test rejects `/tmp` and `/home` as typed **on the destructive side**
/// (the naming side has no depth test since #329), but every call site hands over the
/// resolved spelling, and on macOS `/tmp` arrives as `/private/tmp` with two components —
/// deep enough to pass. Without these entries the guard's own stated intent ("`/tmp` is
/// rejected") does not hold on the platform the tool is developed on.
const denied_exact = [_][]const u8{
    "/tmp",     "/private/tmp", "/var/tmp", "/private/var/tmp",
    "/var/folders", "/private/var/folders",
    "/home",    "/Users",       "/Volumes", "/mnt",
    "/media",   "/root",
};

/// Refuses to operate on a root that is suspiciously shallow, or that names a location
/// nothing sacrificial belongs in.
///
/// restore() deletes the directory tree before rebuilding it. That is the one
/// genuinely destructive thing the engine does, and it runs once per explored world,
/// so a mistaken root would be applied hundreds of times before anyone noticed.
///
/// Lexical only, and the caller must hand over the resolved spelling: "/tmp/../etc"
/// spells safe and resolves unsafe. `assertRootResolvesToItself` covers the other direction —
/// a root that resolved safely and was then swapped.
pub fn assertSafeRoot(root: []const u8) RestoreError!void {
    var slashes: usize = 0;
    for (root) |ch| {
        if (ch == '/') slashes += 1;
    }
    // "/", "/tmp", "/home" and friends are rejected; "/tmp/x/state" is accepted.
    if (slashes < 2) return error.UnsafeRoot;
    try assertRootNotDeniedOrAncestor(root);
}

/// The checks both roots share: shape, and the two denylists read **in both directions**.
///
/// Split out for `assertSafeNamingRoot`, which needs all of these and not the depth
/// rule above. **Both clauses of the first test stay here**: the naming side happens to
/// guarantee a non-empty root before calling, the destructive side does not, and
/// dropping `root.len == 0` on the strength of the caller that does not need it turns
/// `assertSafeRoot("")` from a refusal into an out-of-bounds index.
///
/// **The outward read lives here rather than in one predicate (#358).** #329 added it to
/// the naming side alone, because removing the depth rule there left ancestors uncovered.
/// The destructive side kept its depth rule — which catches `/private` and `/var` but not
/// `/private/var`, the one ancestor deep enough to pass it. So the predicate that only
/// names files refused a location the predicate that empties directories accepted. Put in
/// the shared helper, the asymmetry is not a thing anyone has to remember: neither
/// predicate can be given the read without the other getting it.
fn assertRootNotDeniedOrAncestor(root: []const u8) RestoreError!void {
    if (root.len == 0 or root[0] != '/') return error.UnsafeRoot;
    if (std.mem.endsWith(u8, root, "/")) return error.UnsafeRoot;
    for (denied_exact) |d| {
        if (std.mem.eql(u8, root, d)) return error.UnsafeRoot;
    }
    // `isInsideDir` rather than `startsWith`: the latter refuses "/var/library" for
    // naming "/var/lib", and a component-boundary test is already written here.
    for (denied_trees) |d| {
        if (contract.isInsideDir(root, d)) return error.UnsafeRoot;
    }
    // Outward: is the root a parent of somewhere denied? One loop over both lists, not
    // one per list — written as two, each half's marginal covered set is empty **for the
    // shipped lists**, because there every entry has a sibling in the other list under the
    // same parent, so deleting either loop alone left every test green (measured during
    // #329). That symmetry is a property of those lists and not of the code: the
    // ancestor-probe build adds an entry with no `denied_exact` sibling. A single loop
    // cannot be half deleted either way.
    for (denied_exact ++ denied_trees) |d| {
        if (contract.isInsideDir(d, root)) return error.UnsafeRoot;
    }
}

/// Refuses a root that must not name files: the same locations `assertSafeRoot` denies,
/// **plus their ancestors**, and without the depth rule (#329).
///
/// The two differences are one decision. The depth rule is a proxy for danger, and the
/// proxy was already broken: `/var` resolves to `/private/var` on macOS, two components,
/// and started the server. What the lists actually encode is a set of places, and both
/// are read inwards only — `isInsideDir(root, d)` asks whether the root is *inside* a
/// denied tree, so an ancestor like `/private` or `/var` passes every one of them and
/// was refused only by the depth rule that could not see it on one of the two platforms.
/// Reading them outwards as well — `isInsideDir(d, root)`, the same predicate with the
/// arguments swapped — states the property directly, and a root that is a proper
/// ancestor of a denied entry is refused whatever its depth.
///
/// **This is a trade, not a tightening.** Measured over both lists, the outward read
/// closes exactly `/var`, `/private` and `/private/var`; dropping the depth rule opens
/// every depth-1 path in neither list (`/opt`, `/cores`, `/nix`, and whatever a host has
/// at `/`). That is accepted on ADR 0010's operational precondition — the root is the
/// operator's own workspace, not attacker-writable — and not on any claim that the
/// boundary got narrower.
///
/// The destructive predicate keeps the depth rule and, **since #358, has the outward read
/// too** — it lives in the shared helper now, so neither predicate can be given it alone.
/// This paragraph used to say `--state /var` still passed `assertSafeRoot`, which was the
/// gap #358 closed.
///
/// **What this admits is not confined to naming.** With `SIDEEYE_MCP_STATE_ROOT` unset the
/// server hands the root to the engine as the destruction range, so every depth-1 path
/// this now accepts is a directory whose *children* a replayed case may name and empty.
/// `/work` and `/repo` are the intended shape; `/opt` also passes and is where installed
/// software lives. The relaxation is defensible on ADR 0010's precondition — the root is
/// the operator's own workspace — and the README says which directories that excludes,
/// because the lists cannot.
///
/// Lexical only, like `assertSafeRoot`, and the caller must hand over the resolved
/// spelling: `/opt/../var` and `//var` and `/.` all pass here. `mcp.zig` realpaths before
/// calling, which is what makes that safe and is the reason the caveat is written down
/// rather than left to the one caller that currently honours it.
pub fn assertSafeNamingRoot(root: []const u8) RestoreError!void {
    // "/" — and "" only incidentally, which is worth stating precisely because the first
    // draft of this comment got it wrong. `""` never reaches the outward read at all:
    // `assertRootNotDeniedOrAncestor` returns at its `root.len == 0` clause, and `endsWith("", "/")`
    // is false. `""` is carried by that clause, as the note on the helper says. What this
    // line covers on top of the checks below is therefore **"/" alone, and even that is
    // already covered twice** — the trailing-slash test catches it, and so does the
    // outward read, since `isInsideDir(x, "/")` is true for every absolute x. So this
    // line's covered set is empty, and it is here anyway because **it is the only
    // unconditional carrier of the property**. The trailing-slash test is the destructive
    // side's spelling hygiene and may be revised on its own merits; the outward read
    // holds only while the lists are non-empty, and the sunset note above describes the
    // conditions for deleting them.
    // What fails if all three go is fail-open, not fail-closed: a root of "/" does not
    // weaken the naming boundary, it removes it (`contract.isInsideDir(x, "/")` is true
    // for every absolute path — the input `mcp.zig`'s startup vet exists to eliminate).
    if (root.len <= 1) return error.UnsafeRoot;
    // The outward read moved into the shared helper in #358, so it is no longer written
    // here. Both predicates now get it from one place.
    try assertRootNotDeniedOrAncestor(root);
}

/// Confirms the root still resolves to itself, immediately before it is emptied.
///
/// `assertSafeRoot` is lexical and the resolution behind it happens once, before
/// `--setup` runs. Between those two moments the root can be replaced: a setup command
/// (or the recorded operation, which runs hundreds of times) that leaves a symlink where
/// the state directory was sends the delete somewhere else entirely. `deleteTree` refuses
/// to recurse into a symlinked *entry*, but it reaches the root through `opendir`, which
/// follows one.
///
/// One `realpath` covers the swaps that change the pathname's resolution: the root
/// itself replaced by a link, any parent component replaced by one, or the root moved. A
/// root that is simply gone is not a swap — `deleteTree` already returns silently for it
/// — so ENOENT passes.
///
/// **This is resolution, not identity, and the name says so on purpose.** A replacement
/// that leaves the canonical pathname alone is invisible here: a bind mount over the same
/// path resolves to itself while naming a different tree, and in a privileged container
/// that is a real move rather than a theoretical one. Comparing the device and inode
/// captured at resolution time would cover it, and needs that pair threaded from the call
/// site — filed rather than done.
///
/// Nor does this close the window it does cover: the check and the `opendir` are two
/// syscalls, and a swap between them is not detected.
///
/// **That sentence used to continue "Both gaps have the same fix, the root held open by
/// descriptor for the whole delete", and it was wrong** — the twin of the denylist's
/// sunset note, sitting in the function that note stands beside, and missed by the batch
/// that corrected the other one (#327, ADR 0024). The descriptor fixes **neither** gap. It
/// pins whatever tree is there at open time, so a bind mount established *before* the open
/// is pinned wrong; and the check-to-open race is untouched, because the check and the open
/// are still two syscalls. What the descriptor closes is a different window — open to
/// end-of-walk — which is where every entry used to be re-resolved by name, once per entry
/// and once per pass, giving a resident racer as many attempts as there are entries.
///
/// The fix for both gaps is the one named two paragraphs up, comparing device and inode,
/// and the descriptor makes it cheap rather than redundant: one side of that comparison is
/// now an open descriptor. Still filed rather than done (ADR 0024, Alternatives).
fn assertRootResolvesToItself(root: []const u8) RestoreError!void {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    // No separate symlink test. An earlier version asked `isSymlink` first, justified as
    // keeping two failures distinguishable — measured, deleting it left every test green,
    // because the comparison below already refuses a linked root by the only thing that
    // matters: it resolves somewhere else. The one case it could have added, a dangling
    // link, never reaches here — `main.zig` cannot resolve such a `--state` at all.
    var real_buf: [contract.max_path]u8 = undefined;
    const resolved = posix.realpath(root_z.ptr, &real_buf) orelse {
        if (std.c._errno().* == posix.ENOENT) return; // nothing there to delete
        return error.UnsafeRoot; // cannot look: refuse rather than delete blind
    };
    if (!std.mem.eql(u8, std.mem.span(resolved), root)) return error.UnsafeRoot;
}

/// What opening the destructive root found.
///
/// `absent` is a variant rather than an error because the two callers disagree about it:
/// `deleteTree` has nothing to delete and is done, while `freshDir` has already failed its
/// `mkdir`, so an absent root there means a missing parent — the silent no-op that flag
/// exists to remove. One `open`, two meanings, and neither may be assumed by the other.
const RootOpen = union(enum) { fd: c_int, absent };

/// Open a directory for the destructive walk, pinned by descriptor (#327).
///
/// Holding the descriptor is what closes the swap window: every delete below is relative
/// to the inode opened here, so replacing the *pathname* afterwards redirects nothing.
/// `O_NOFOLLOW` additionally refuses a root that is itself a link.
///
/// **This does not replace `assertRootResolvesToItself`, and the callers still run it.**
/// `O_NOFOLLOW` is about the final component only: with root `/a/b/state`, replacing
/// `/a/b` with a link to somewhere else opens *that* tree, and this function would then
/// delete it race-free and thoroughly. Pinning identity is not the same property as
/// picking the right target — the same distinction the denylist's note gets wrong above.
///
/// The errno map is caller-visible. `ENOTDIR` becoming `UnsafeRoot` is a deliberate
/// reclassification: a regular file where the state directory should be used to arrive as
/// `DeleteFailed` through the `opendir` probe this replaces.
fn openRootDir(root: []const u8) RestoreError!RootOpen {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    const fd = posix.open(
        root_z.ptr,
        posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC,
        @as(c_uint, 0),
    );
    if (fd >= 0) return .{ .fd = fd };
    return switch (std.c._errno().*) {
        posix.ENOENT => .absent,
        posix.ELOOP, posix.ENOTDIR => error.UnsafeRoot,
        // Everything else — EACCES, EMFILE, ENFILE, EPERM under an LSM, ENAMETOOLONG —
        // is loud. A default arm that fell through to `absent` would turn "cannot look"
        // into "nothing there", which is the substitution this file keeps refusing.
        else => error.DeleteFailed,
    };
}

/// The path-taking entry to the walk: opens the root once, then everything is relative to
/// that descriptor. An absent root is nothing to delete, which is what `opendir` returning
/// null used to mean here.
fn deleteTree(root: []const u8) RestoreError!void {
    switch (try openRootDir(root)) {
        .absent => return,
        .fd => |fd| {
            const r = deleteTreeAt(fd, 0);
            _ = posix.close(fd);
            return r;
        },
    }
}

fn deleteTreeAt(dirfd: c_int, depth: usize) RestoreError!void {
    if (depth > max_depth) return error.DeleteFailed;

    // Removed in passes, reopening the directory each time.
    //
    // Names must be collected before anything is deleted — removing entries while
    // iterating a DIR* is not portable — so a fixed buffer bounds how many can be held
    // at once. The first version stopped quietly at that bound, which left the previous
    // world's files in place and made an L2 checker report a violation at crash point k
    // that was really residue from k-1. Turning it into a hard error fixed the silence
    // and introduced a worse limit: a state directory with more than 256 entries in one
    // directory became unexplorable, reported as SETUP ERROR with no mention of a buffer.
    // Neither is a limit worth having. A pass that takes as many as fit and then reopens
    // drains a directory of any size, and the buffer stops being part of the contract.
    while (true) {
        var names_buf: [4096]u8 = undefined;
        var names_len: usize = 0;
        var offsets: [256]struct { start: usize, len: usize, dtype: u8 } = undefined;
        var count: usize = 0;
        var buffer_full = false;

        {
            // `fdopendir` takes ownership of the descriptor it is handed and `closedir`
            // closes it, so it cannot be given `dirfd` — that has to outlive the stream
            // for the `unlinkat`s below.
            //
            // **And it cannot be given `dup(dirfd)` either**, which is what this loop tried
            // first. A duplicate shares the open file description, *including the read
            // offset*, and neither libc rewinds it in `fdopendir`. Pass two then resumed
            // where pass one stopped, found nothing past the tail, and the `count == 0`
            // branch below read that as an empty directory — returning success over a
            // directory it had not drained. Measured on macOS: 144 of 400 entries left
            // behind, no error. `removed < count` cannot catch it because every entry that
            // was *collected* was removed; the loss is in the collection.
            //
            // `openat(dirfd, ".")` is a fresh description at offset zero, which is the
            // property the pre-descriptor `opendir(path)` supplied and the only part of it
            // this rewrite had to keep. No `O_NOFOLLOW`: "." is the directory itself.
            const stream_fd = posix.openat(dirfd, ".", posix.O_RDONLY | posix.O_DIRECTORY | posix.O_CLOEXEC, @as(c_uint, 0));
            if (stream_fd < 0) return error.DeleteFailed;
            const dirp = posix.fdopendir(stream_fd) orelse {
                _ = posix.close(stream_fd);
                return error.DeleteFailed;
            };
            defer _ = posix.closedir(dirp);
            // The entry type is collected with the name, because it is the only
            // description of the entry that has not followed a symlink yet.
            while (posix.readdir(dirp)) |ent| {
                const name = posix.direntName(ent);
                if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
                if (count >= offsets.len or names_len + name.len > names_buf.len) {
                    buffer_full = true;
                    break;
                }
                @memcpy(names_buf[names_len..][0..name.len], name);
                offsets[count] = .{ .start = names_len, .len = name.len, .dtype = ent.type };
                names_len += name.len;
                count += 1;
            }
        }

        if (count == 0) {
            // Nothing collected. Either the directory is empty — done — or a single name
            // was too long to hold, which would otherwise loop forever making no progress.
            if (buffer_full) return error.DeleteFailed;
            return;
        }

        var removed: usize = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const name = names_buf[offsets[i].start..][0..offsets[i].len];
            // The bare entry name, which is the only spelling that keeps `dirfd`
            // meaningful: an absolute path makes the kernel ignore the descriptor,
            // silently, on both platforms.
            var name_buf: [contract.max_path]u8 = undefined;
            const name_z = std.fmt.bufPrintZ(&name_buf, "{s}", .{name}) catch return error.PathTooLong;

            // Recurse only into a real directory, never into a symlink that points at one.
            //
            // The first version asked `isDirPath`, which calls `opendir` and therefore
            // follows links: a link inside the state directory pointing outside it would
            // have redirected this recursive delete out of the tree, once per explored
            // world. `assertSafeRoot` cannot see that — it only inspects the root string.
            // Unlinking a symlink removes the link itself, which is what is wanted here.
            //
            // The DT_UNKNOWN fallback asks `fstatat` and deliberately not an `openat`
            // probe. `opendir` passes `O_NONBLOCK`; a hand-rolled open does not, and
            // posix.zig records what that costs — "a FIFO with no writer blocks that open
            // forever" is why the open-probe was retired from this project once already
            // (#5 R1). The descriptor-relative form of that same classifier has the
            // property this walk wants for free: it cannot follow a link and it cannot
            // resolve outside `dirfd`.
            const dt = offsets[i].dtype;
            const recurse = switch (dt) {
                posix.DT_DIR => true,
                posix.DT_UNKNOWN => (posix.kindAtNoFollow(dirfd, name_z.ptr) catch
                    return error.DeleteFailed) == .dir,
                else => false, // DT_REG, DT_LNK and everything else: remove the entry itself
            };
            if (recurse) {
                // An entry that stopped being a directory between `readdir` and here fails
                // this open and is left uncounted — `removed < count` below turns that
                // into a loud refusal, the same outcome the old failed `rmdir` produced.
                const child = posix.openat(
                    dirfd,
                    name_z.ptr,
                    posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC,
                    @as(c_uint, 0),
                );
                if (child >= 0) {
                    const r = deleteTreeAt(child, depth + 1);
                    _ = posix.close(child);
                    try r;
                    if (posix.unlinkat(dirfd, name_z.ptr, posix.AT_REMOVEDIR) == 0) removed += 1;
                }
            } else {
                if (posix.unlinkat(dirfd, name_z.ptr, 0) == 0) removed += 1;
            }
        }

        // Every collected entry must actually have been removed. The first version
        // required only `removed > 0`, which let a PARTIAL failure — three siblings
        // gone, one held by permissions — return as success and leave residue for the
        // next world to be judged against: the exact "violation at crash point k that
        // was really residue from k-1" this function's own history records. The path
        // became reachable when #121 stopped refusing chmod-capable targets (R1); an
        // unreadable 0000-mode directory, for instance, is skipped silently by
        // opendir above and its rmdir then fails here. Failing loudly turns that
        // into SETUP ERROR instead of a fabricated counterexample.
        if (removed < count) return error.DeleteFailed;
        if (!buffer_full) return;
    }
}

/// Empty a state directory, creating it if missing (`replay --fresh-state`, #69).
/// The call site passes the realpath'd spelling: `assertSafeRoot` is lexical, and
/// "/tmp/../etc" spells safe while resolving unsafe — resolution is the guard's
/// other half. Failing loudly is the point: a fresh-state that could not do its
/// job and said nothing would be the exact silent no-op the flag exists to remove.
pub fn freshDir(root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    if (posix.mkdir(root_z.ptr, 0o755) == 0) return; // did not exist: created empty
    try assertRootResolvesToItself(root);
    switch (try openRootDir(root)) {
        // `mkdir` failed AND nothing is there: a missing parent. Loud, and this is the one
        // place the two meanings of an absent root diverge — `deleteTree` treats it as
        // "nothing to delete" and returns. A `--fresh-state` that could not do its job and
        // said nothing is the exact silent no-op this flag exists to remove, so the shared
        // open cannot be allowed to carry `deleteTree`'s reading here. A regular file or a
        // permission wall stay loud too, through `openRootDir`'s map.
        .absent => return error.DeleteFailed,
        // Empties the children; the root directory itself stays in place.
        .fd => |fd| {
            const r = deleteTreeAt(fd, 0);
            _ = posix.close(fd);
            return r;
        },
    }
}

pub fn restore(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    try assertRootResolvesToItself(root);

    // Created *before* the descriptor is taken, not after the delete where it used to sit.
    // Once the root is held open, a `mkdir` on the pathname makes a different directory
    // than the one the walk and every creation below are pinned to, and each `mkdirat`
    // would then run against an unlinked inode. Before the open there is nothing to
    // disagree with: a root that is simply gone is recreated here, as it always was.
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    _ = posix.mkdir(root_z.ptr, 0o755);

    // One descriptor for the whole call: the delete and the rebuild are pinned to the same
    // inode, so a swap between them redirects neither. What it does not pin is the interior
    // — `e.rel` is a multi-component path, and its intermediate components are still
    // resolved by name below. Those directories were made by this loop moments earlier.
    const fd = switch (try openRootDir(root)) {
        .absent => return error.CreateFailed, // the mkdir above failed and nothing is there
        .fd => |f| f,
    };
    defer _ = posix.close(fd);

    try deleteTreeAt(fd, 0);

    for (snap.entries.items) |e| {
        var rel_buf: [contract.max_path]u8 = undefined;
        const rel_z = std.fmt.bufPrintZ(&rel_buf, "{s}", .{e.rel}) catch return error.PathTooLong;
        switch (e.kind) {
            // The only creation whose failure used to be silent — harmless exactly
            // while dir-to-dir pairs were unjudged, and a tool-manufactured
            // `missing` the moment they are judged (#164): a world starting without
            // an empty directory the recording had would read as the target's
            // violation. Strict on purpose, no EEXIST tolerance: the tree was
            // emptied above and the root itself never appears in these entries
            // (walk records children only), so an existing directory here has no
            // legitimate source — it is a leftover the delete failed to remove,
            // and accepting it would let world k judge world k-1's residue.
            .dir => if (posix.mkdirat(fd, rel_z.ptr, 0o755) != 0) return error.CreateFailed,
            .symlink => {
                // Recreate the link with the recorded target, verbatim. The target is
                // a string, not a path this function resolves — a dangling link is
                // restored dangling, which is what the snapshot recorded.
                var tz_buf: [contract.max_path]u8 = undefined;
                const tz = std.fmt.bufPrintZ(&tz_buf, "{s}", .{e.content}) catch return error.PathTooLong;
                if (posix.symlinkat(tz.ptr, fd, rel_z.ptr) != 0) return error.CreateFailed;
            },
            .file => {
                const wfd = posix.openat(fd, rel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC | posix.O_CLOEXEC, @as(c_uint, 0o644));
                if (wfd < 0) return error.CreateFailed;
                var off: usize = 0;
                while (off < e.content.len) {
                    const w = posix.write(wfd, e.content[off..].ptr, e.content.len - off);
                    // Breaking here and returning success would start the next world from
                    // a truncated file, and judgeL0 would then report a hybrid — a
                    // counterexample manufactured by the tool rather than found in the
                    // target. readWhole distinguishes these cases; this loop did not.
                    if (w <= 0) {
                        _ = posix.close(wfd);
                        return error.CreateFailed;
                    }
                    off += @intCast(w);
                }
                _ = posix.close(wfd);
            },
            // Unreachable from any explored path since #5's refusal fires on every
            // snapshot before restore runs — kept loud, not silent: an `.other` that
            // somehow arrives here would otherwise become a tool-manufactured
            // `missing` in the next world's judgement, the exact shape #5 demoted.
            .other, .missing => return error.CreateFailed,
        }
    }
}

// ---------------------------------------------------------------------------------

pub const Op = struct {
    class: contract.OpClass,
    seq: u32,
    pid: u32,
    path: []const u8,
    aux: []const u8,
};

pub const TraceInfo = struct {
    arena: std.heap.ArenaAllocator,
    ops: std.ArrayList(Op),
    saw_header: bool = false,
    version_mismatch: bool = false,
    saw_shim_ready: bool = false,
    /// The shim saw an operation it could not place. Any verdict computed from a trace
    /// containing one is a verdict about an incomplete picture.
    saw_unresolved: bool = false,
    /// The syscall-and-flag spelling of the first in-scope operation the shim could
    /// place but not model (v12, macOS: `RENAME_SWAP`, `exchangedata`). Borrows from
    /// the trace buffer. On Linux this refusal comes from the oracle instead, and
    /// this field stays null.
    first_unsupported: ?[]const u8 = null,
    kill_landed_seq: ?u32 = null,
    /// Who wrote the kill_landed record. `seq == k` alone is not landing evidence: a
    /// child inheriting SIDEEYE_KILL_AT counts its own operations, and its k-th is not
    /// the subject's.
    kill_landed_pid: ?u32 = null,
    kill_point_count: u32 = 0,
    mutation_count: u32 = 0,
    boundary: ?contract.OpClass = null,
    /// The boundaries that stay refusals regardless of tolerance, which are not the
    /// same set for every process: the *subject* replacing its image or creating a
    /// thread breaks addressing and determinism, while a **child** exec'ing is just a
    /// spawn doing what spawns do. `detached` is hard from anyone — escape is escape.
    /// Kept separately from `boundary` because "first boundary" can be a tolerable
    /// fork that arrives before the record that must refuse the run.
    hard_boundary: ?contract.OpClass = null,
    truncated: bool = false,
    /// The subject: whoever wrote the first `shim_ready`. The trace file is created by
    /// the first process to initialise, which is the process the engine launched —
    /// children come later, whether forked (init already done) or spawned (their init
    /// appends behind the subject's).
    primary_pid: ?u32 = null,
    /// A kill-point (or kill_landed) record from a process other than the subject.
    /// Crash points are numbered per process, so such an operation has no unique
    /// address; any run containing one is refused rather than mis-attributed.
    foreign_kill_point: bool = false,
    /// Any record at all from another process — a spawned child announcing itself
    /// counts. Evidence that the run crossed a process boundary even if no boundary
    /// record was written (a raw clone, say).
    foreign_pid_seen: bool = false,
    /// Subject execs whose chain was proven unbroken (#123): the exec record was
    /// followed by a `shim_ready` from the same pid carrying exactly the operation
    /// count the chain left off at. Such an exec is a continuation, not a boundary.
    exec_continuations: u32 = 0,
    /// A subject exec whose continuation evidence never arrived, arrived with the
    /// wrong count, or was pre-empted by another exec. `hard_boundary` is set to
    /// `.exec` alongside this; the flag exists so the refusal can say WHICH way the
    /// image change escaped observation.
    exec_chain_broken: bool = false,
    /// How many kill-point records the subject wrote. `kill_point_count` is the
    /// MAXIMUM seq; if the two disagree the numbering has gaps or duplicates — a
    /// restarted counter after an unobserved exec is exactly a duplicate — and any
    /// address computed from the trace may name a different operation than the one
    /// that ran (#123, R1 C7: prefixHash misses duplicates, logicalAddress takes
    /// the last match; a verdict over renumbered ops is a verdict about nothing).
    primary_kill_records: u32 = 0,
    /// The trace read broke its cap (#324). Distinct from `truncated`, which is the
    /// writer's side: a record that ends mid-way says the shim stopped writing, while
    /// this says the reader refused to hold what the shim did write. Without the
    /// distinction both arrive as an empty TraceInfo, and the caller reads an empty
    /// TraceInfo as "the shim never initialised".
    too_large: bool = false,
    /// The trace's size from `lseek(SEEK_END)` at the moment the cap broke; null when
    /// even that failed, in which case the refusal names the cap and no more (#265's
    /// rule: a size nobody measured must not appear in the message).
    too_large_size: ?u64 = null,

    pub fn deinit(self: *TraceInfo) void {
        self.arena.deinit();
    }

    /// The logical address of crash point k: the operation it happens before, and the
    /// one it happens after. Reported instead of a bare counter so a saved case can be
    /// recognised as no longer applying when the code changes. Only the subject's
    /// operations are addresses; a child's seq counts different things.
    pub fn logicalAddress(self: TraceInfo, k: u32) struct { after: ?Op, before: ?Op } {
        var after: ?Op = null;
        var before: ?Op = null;
        for (self.ops.items) |op| {
            if (!op.class.isKillPoint()) continue;
            if (self.primary_pid != null and op.pid != self.primary_pid.?) continue;
            if (op.seq == k) before = op;
            if (op.seq == k - 1) after = op;
        }
        return .{ .after = after, .before = before };
    }
};

/// The trace read's ceiling (#324). Sized against the largest exploration this
/// repository has measured — 119 worlds (Borg, `spike/cohort2/borg-r3/RUNLOG.md`) — at
/// the contract's worst-case record, `contract.max_record_len` = 8210 bytes (two
/// `max_path` components plus headers): 976,990 bytes, which this cap clears 68 times
/// over. Two things that comparison does NOT say: worlds are not records (a trace also
/// carries seq-0 lifecycle, boundary and marker records, which nothing here counts), and
/// at worst-case records the cap admits 8,174 of them — not the "million operations" an
/// earlier draft claimed by silently switching to typical path lengths mid-argument.
/// It shares its value with `max_state_file_bytes` and nothing else: the two bound
/// different things and may move apart.
pub const max_trace_bytes: usize = 64 * 1024 * 1024;

pub fn readTrace(gpa: Allocator, path: []const u8) SnapshotError!TraceInfo {
    return readTraceCapped(gpa, path, max_trace_bytes);
}

/// The capped form, parameterized for the reason `takeSnapshotCapped` is (#265): the
/// shipped cap cannot be reached by a fixture. The engine unlinks the trace before
/// every run — the recording path and the world path both — so no oversized file can be
/// planted, and the only writer is the shim. How many operations that takes depends on
/// path lengths and is not claimed here; what is measured is that no committed define
/// comes near it. Tests drive this with a small `max`.
pub fn readTraceCapped(gpa: Allocator, path: []const u8, max: usize) SnapshotError!TraceInfo {
    var info: TraceInfo = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .ops = .empty,
    };
    errdefer info.arena.deinit();
    const arena = info.arena.allocator();

    var path_buf: [contract.max_path]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.PathTooLong;

    // A missing trace file is not an error here: it is the observation that the shim
    // never ran, which the caller turns into `no_shim_marker`.
    //
    // Capped since #324, and the cap breaking is the one failure this read does NOT
    // collapse. #265 left the read uncapped precisely because collapsing it would
    // relabel an oversized trace as "the shim never initialised" — a refusal with the
    // wrong reason, worse than no cap. That reasoning stands; what changed is that the
    // cap now has a way to say what it is. Every OTHER failure still collapses, because
    // for those the empty TraceInfo is the honest observation.
    var too_large_size: ?u64 = null;
    const bytes = readWhole(arena, path_z.ptr, max, &too_large_size) catch |err| switch (err) {
        error.FileTooLarge => {
            info.too_large = true;
            info.too_large_size = too_large_size;
            return info;
        },
        else => return info,
    };
    if (bytes.len == 0) return info;

    var off: usize = contract.decodeHeader(bytes) catch |err| switch (err) {
        error.VersionMismatch => {
            info.saw_header = true;
            info.version_mismatch = true;
            return info;
        },
        else => {
            info.truncated = true;
            return info;
        },
    };
    info.saw_header = true;

    // The continuation window (#123): a subject exec is judged, not refused, when
    // the very next same-pid shim_ready carries exactly the operation count the
    // chain left off at. The window is open between those two records.
    var pending_exec = false;
    var pending_base: u32 = 0;

    while (off < bytes.len) {
        const dec = contract.decodeRecord(bytes[off..]) catch {
            info.truncated = true;
            break;
        };
        off += dec.consumed;
        const op: Op = .{
            .class = dec.rec.op,
            .seq = dec.rec.seq,
            .pid = dec.rec.pid,
            .path = try arena.dupe(u8, dec.rec.path),
            .aux = try arena.dupe(u8, dec.rec.aux),
        };
        switch (op.class) {
            .shim_ready => {
                info.saw_shim_ready = true;
                if (info.primary_pid == null) {
                    info.primary_pid = op.pid;
                } else if (pending_exec and op.pid == info.primary_pid.?) {
                    // The new image announcing itself. Its seq is the carried base
                    // (v10); anything else — a fresh 0 from a stripped environment
                    // or a non-interposed exec path — is a chain that broke.
                    if (op.seq == pending_base) {
                        info.exec_continuations += 1;
                    } else {
                        info.exec_chain_broken = true;
                        if (info.hard_boundary == null) info.hard_boundary = .exec;
                    }
                    pending_exec = false;
                } else if (op.pid == info.primary_pid.?) {
                    // No window is open, and the subject announced itself AGAIN. The
                    // constructor runs once per image, so a second announcement IS an
                    // image change — one that escaped interposition entirely (execl
                    // family, fexecve: no exec record, no carried count). Structural,
                    // and it needs no prior operations to fire: R1 measured an execl
                    // with zero in-scope ops before it slipping to a verdict because
                    // the numbering check's two sides were trivially equal.
                    info.exec_chain_broken = true;
                    if (info.hard_boundary == null) info.hard_boundary = .exec;
                }
            },
            .kill_landed => {
                info.kill_landed_seq = op.seq;
                info.kill_landed_pid = op.pid;
            },
            .unresolved => info.saw_unresolved = true,
            // The record's path field carries the syscall-and-flag spelling, not a
            // path (v12). First one wins: the refusal names one operation, the way
            // the oracle's `unsupported` does on Linux, and the slice borrows from
            // the trace buffer the caller keeps alive — the same lifetime `Op.path`
            // already lives with.
            .unsupported => {
                if (info.first_unsupported == null) info.first_unsupported = op.path;
            },
            else => {},
        }
        const is_primary = info.primary_pid != null and op.pid == info.primary_pid.?;
        if (!is_primary) {
            info.foreign_pid_seen = true;
            if (op.class.isKillPoint() or op.class == .kill_landed)
                info.foreign_kill_point = true;
        }
        if (op.class.isKillPoint() and is_primary) {
            info.kill_point_count = @max(info.kill_point_count, op.seq);
            info.primary_kill_records += 1;
            if (op.class.isMutation()) info.mutation_count += 1;
        }
        if (op.class.isBoundary()) {
            if (info.boundary == null) info.boundary = op.class;
            const hard = switch (op.class) {
                .detached => true,
                // A record written before the primary announced itself is attributed
                // to the primary: refusing is the safe misreading.
                .thread => is_primary or info.primary_pid == null,
                .exec => blk: {
                    // A subject exec opens the continuation window instead of
                    // refusing outright (#123). Before the subject is known, v9's
                    // safe misreading stands; a second exec while a window is
                    // still open means the intermediate image was never observed.
                    if (info.primary_pid == null) break :blk true;
                    if (!is_primary) break :blk false;
                    if (pending_exec) {
                        info.exec_chain_broken = true;
                        break :blk true;
                    }
                    pending_exec = true;
                    pending_base = info.kill_point_count;
                    break :blk false;
                },
                else => false,
            };
            if (hard and info.hard_boundary == null) info.hard_boundary = op.class;
        }
        try info.ops.append(arena, op);
    }
    // A window still open at the end of the trace is a chain that broke: the image
    // changed and nothing observed the far side.
    if (pending_exec) {
        info.exec_chain_broken = true;
        if (info.hard_boundary == null) info.hard_boundary = .exec;
    }
    return info;
}

// ---------------------------------------------------------------------------------

pub const Violation = union(enum) {
    /// A path present before and after the operation is gone from the crashed state.
    missing: []const u8,
    /// Present, but holding neither the old nor the new content.
    hybrid: []const u8,
    /// A history-form file (ADR 0004) whose crashed content no longer begins with its
    /// pre-operation content — or whose path no longer holds a file at all.
    rewritten: []const u8,
    /// The operation claimed success before the kill, and part of the new state did
    /// not survive (ADR 0008): a shared file still holds old content, a history file
    /// gained nothing, a created file is absent, or a deleted file is back.
    not_durable: []const u8,
};

/// Which invariant a shared file is judged by, decided once from the snapshots alone.
pub const FileForm = enum {
    /// The crashed content must equal the pre or the post content.
    standard,
    /// The crashed content must still begin with the pre content (ADR 0004). The
    /// appended tail is deliberately not judged — whether a torn tail is acceptable
    /// is the target's recovery semantics, which belongs to an L2 checker.
    history,
};

pub const PlannedFile = struct {
    /// All three slices borrow from the pre/post snapshots handed to `classify`;
    /// the plan must not outlive them.
    rel: []const u8,
    /// The judged identity is (kind, content) on EACH side, and the two sides may
    /// differ: stow's unfold turns a fold symlink into a real directory, and that
    /// pair is judged like any other — killed mid-swap, the path holds neither
    /// identity (#122, owner ruling). A symlink's "content" is its target string,
    /// so without the kind a same-named regular file holding those bytes would
    /// satisfy the content comparison while being a different thing.
    pre_kind: posix.Kind,
    post_kind: posix.Kind,
    form: FileForm,
    pre_content: []const u8,
    post_content: []const u8,
};

pub const L0Plan = struct {
    arena: std.heap.ArenaAllocator,
    files: std.ArrayList(PlannedFile),
    history_count: u32 = 0,

    pub fn deinit(self: *L0Plan) void {
        self.arena.deinit();
    }
};

/// The kinds the built-in invariants can compare: a (kind, content) pair is a whole
/// identity for each of these. Sockets and devices stay outside — their content is
/// unreadable here, and a comparison of nothing would be agreement about nothing.
fn isJudgedKind(k: posix.Kind) bool {
    return k == .file or k == .symlink or k == .dir;
}

/// Decide, once and from the snapshots alone, which invariant each shared file is
/// judged by. Both the judgement (`judgeL0`) and the report's `l0` note read from the
/// same plan — there is deliberately no second place where the classification is
/// computed, because two classifiers would drift.
///
/// A file enters the history form iff its pre content is non-empty and its post
/// content strictly extends it. Non-empty matters: `startsWith(anything, "")` is
/// vacuously true, so an empty "history" would constrain nothing — such files keep
/// the standard rule, where the atomic-write check still means something.
pub fn classify(gpa: Allocator, pre: Snapshot, post: Snapshot) error{OutOfMemory}!L0Plan {
    var plan: L0Plan = .{ .arena = std.heap.ArenaAllocator.init(gpa), .files = .empty };
    errdefer plan.arena.deinit();
    const arena = plan.arena.allocator();
    for (pre.entries.items) |pe| {
        if (!isJudgedKind(pe.kind)) continue;
        const po = post.find(pe.rel) orelse continue;
        if (!isJudgedKind(po.kind)) continue;
        // A dir-to-dir pair used to be skipped as carrying "nothing to compare" —
        // but its kind IS the comparison (#164): an empty directory replaced by a
        // file, or deleted outright, was invisible exactly because the pair never
        // entered the plan. A directory with children is reached through the
        // children's own pairs; an empty one has no other witness, so every judged
        // pair enters now — kind changes included (#122: stow's unfold, fold
        // symlink → real directory, is the window that define exists to explore).
        // The history form is a statement about appendable byte streams; a symlink's
        // target string is replaced whole or not at all, so only file→file pairs
        // qualify and everything else stays standard.
        const history = pe.kind == .file and po.kind == .file and pe.content.len > 0 and
            !std.mem.eql(u8, po.content, pe.content) and
            std.mem.startsWith(u8, po.content, pe.content);
        if (history) plan.history_count += 1;
        try plan.files.append(arena, .{
            .rel = pe.rel,
            .pre_kind = pe.kind,
            .post_kind = po.kind,
            .form = if (history) FileForm.history else FileForm.standard,
            .pre_content = pe.content,
            .post_content = po.content,
        });
    }
    return plan;
}

/// L0: the built-in atomicity invariant.
///
/// DESIGN §12 states it as "the state directory equals the pre-operation snapshot or
/// the post-operation result, never a hybrid". Implementing that literally fails a
/// *correct* target: the standard write-temp-then-rename idiom leaves `key.json.tmp`
/// behind at several crash points, so the directory equals neither snapshot.
///
/// The invariant that actually separates a correct target from a broken one is
/// narrower — it is about the paths the operation is *replacing*:
///
///   for every path present in both the pre and post snapshots,
///   the crashed state must contain it, holding either the pre or the post identity
///   (kind and content as a pair, #122) —
///   or, for a file whose clean run only ever extends it (the history form, ADR 0004),
///   content that still begins with everything the file held before the operation.
///
/// Paths in neither snapshot (temporaries) are ignored. Paths only in pre (deleted by
/// the operation) or only in post (created by it) may legitimately be absent mid-flight.
pub fn judgeL0(plan: L0Plan, crashed: Snapshot) ?Violation {
    for (plan.files.items) |f| {
        const ce = crashed.find(f.rel) orelse return .{ .missing = f.rel };
        switch (f.form) {
            .standard => {
                // The identity on each side is (kind, content) as a pair: a symlink's
                // content is its target string, so a same-named regular file holding
                // those bytes — or a directory beside an empty pre content — must not
                // read as preserved state (#122). A pair whose kind changed between
                // the clean runs (stow's unfold: symlink → directory) is judged by
                // the same two-sided rule; killed mid-swap, the path matches neither
                // side, and that is the violation.
                if (ce.kind == f.pre_kind and std.mem.eql(u8, ce.content, f.pre_content)) continue;
                if (ce.kind == f.post_kind and std.mem.eql(u8, ce.content, f.post_content)) continue;
                return .{ .hybrid = f.rel };
            },
            .history => {
                // Both arms check kind now (#122); this one keeps its own because its
                // violation is `rewritten`, not `hybrid`, and because an empty prefix
                // test would otherwise accept a directory's empty content.
                if (ce.kind != .file) return .{ .rewritten = f.rel };
                if (std.mem.startsWith(u8, ce.content, f.pre_content)) continue;
                return .{ .rewritten = f.rel };
            },
        }
    }
    return null;
}

/// The post-success invariant (ADR 0008), judged only in worlds where the operation's
/// own success marker reached stdout before the kill: the *new* state must survive.
/// Judged against the whole post snapshot, not just the files both snapshots share —
/// a created file that vanished or a deleted file that returned is exactly the loss a
/// success claim promised away. The one deliberate gap: a post-only file is required
/// to exist but its content is not judged (it may legitimately differ between runs),
/// and the report's `not tested` says so.
pub fn judgeL1(plan: L0Plan, pre: Snapshot, post: Snapshot, crashed: Snapshot) ?Violation {
    for (plan.files.items) |f| {
        const ce = crashed.find(f.rel) orelse return .{ .not_durable = f.rel };
        switch (f.form) {
            // The success claim promised the post state, kind and content both:
            // a directory's content is the empty string, so an empty post file
            // replaced by a same-named directory would compare equal on content
            // alone. The plan carries the post kind, so no second lookup (#122).
            .standard => if (ce.kind != f.post_kind or !std.mem.eql(u8, ce.content, f.post_content))
                return .{ .not_durable = f.rel },
            .history => {
                if (ce.kind != .file) return .{ .not_durable = f.rel };
                if (!std.mem.startsWith(u8, ce.content, f.pre_content))
                    return .{ .not_durable = f.rel };
                // Success claimed an append happened; a file exactly equal to its pre
                // content kept its history and lost the change.
                if (ce.content.len <= f.pre_content.len)
                    return .{ .not_durable = f.rel };
            },
        }
    }
    for (post.entries.items) |e| {
        if (pre.find(e.rel) != null) continue;
        const ce = crashed.find(e.rel) orelse return .{ .not_durable = e.rel };
        if (ce.kind != e.kind) return .{ .not_durable = e.rel };
        // A post-only FILE's content may legitimately differ between runs, which is
        // the deliberate gap the report's `not tested` names. That reasoning does not
        // transfer to a symlink: its target string is its whole identity and it is
        // written whole — a farm's new link pointing anywhere else is exactly the
        // loss a success claim promised away (#122, R1).
        if (e.kind == .symlink and !std.mem.eql(u8, ce.content, e.content))
            return .{ .not_durable = e.rel };
    }
    for (pre.entries.items) |e| {
        if (post.find(e.rel) != null) continue;
        if (crashed.find(e.rel) != null) return .{ .not_durable = e.rel };
    }
    return null;
}

// The #27 pins, one test per pin: the issue's named scenario, both ways
// around. Under a content-only comparison a directory's recorded-empty
// content reads as equal to an emptied (or not-yet-written) file, and the
// kind change slips through. The pair rule (#122) closed this; these hold it
// closed through the real path (classify + judgeL0), because "an emptied
// file classifies as the standard form" is part of the claim. Separate test
// fns on purpose — a shared fn masks every pin after the first failure, and
// a mutation round must report each red individually.
fn expectHybridAgainstCrashedKind(pre_content: []const u8, post_content: []const u8, crashed_kind: posix.Kind) !void {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "note", pre_content }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "note", post_content }});
    defer post.deinit();
    var crashed: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer crashed.deinit();
    try crashed.entries.append(crashed.arena.allocator(), .{ .rel = "note", .kind = crashed_kind, .content = "" });
    const v = (try testJudge(gpa, pre, post, crashed)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("note", v.hybrid);
}

test "#27 pin: a post-empty file pair rejects a crashed directory" {
    try expectHybridAgainstCrashedKind("x", "", .dir);
}

test "#27 pin: a pre-empty file pair rejects a crashed directory" {
    try expectHybridAgainstCrashedKind("", "x", .dir);
}

test "#27 pin: an .other crashed kind is not the emptied file" {
    // FIFO-shaped: recorded with empty content too. Unit-level property — in
    // real runs #5's adjudicated demotion will refuse `.other` at snapshot time.
    try expectHybridAgainstCrashedKind("x", "", .other);
}

test "#27 control: a non-empty pair rejects the same directory as always" {
    // Content alone already refuses this shape, so the kind-blind mutation
    // that reds the three pins above spares this one — it keeps rejecting.
    try expectHybridAgainstCrashedKind("x", "y", .dir);
}

// The #164 pins: an empty directory present in both clean runs has no witness
// but its own pair — with the old skip, a crash world could replace it with a
// file or delete it and the verdict never looked.

test "#164: a dir-to-dir pair enters the plan and an intact world judges clean" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(FileForm.standard, plan.files.items[0].form);
    var intact: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer intact.deinit();
    try intact.entries.append(intact.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, intact));
}

test "#164 pin: an empty directory replaced by an empty file is a violation" {
    // Content matches both sides; only the kind dissents — the exact shape
    // the skip used to hide.
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    var as_file: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_file.deinit();
    try as_file.entries.append(as_file.arena.allocator(), .{ .rel = "box", .kind = .file, .content = "" });
    try std.testing.expectEqualStrings("box", judgeL0(plan, as_file).?.hybrid);
}

test "#164 pin: an empty directory deleted outright is missing" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    var gone: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer gone.deinit();
    try std.testing.expectEqualStrings("box", judgeL0(plan, gone).?.missing);
}

test "#164 pin: restore goes loud when a directory cannot be created" {
    // The guard's own falsification: a parentless dir entry makes mkdir fail
    // with ENOENT, and restore must refuse — a silently absent directory
    // would let judgeL0 report a `missing` the tool itself manufactured.
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-loud-dir-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    // The resolved parent: `restore` requires a root that resolves to itself, which is
    // the spelling its call sites hand over. See the symlink test below for the same note.
    var dbuf: [contract.max_path]u8 = undefined;
    const parent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{parent}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a/b", .kind = .dir, .content = "" });
    try std.testing.expectError(error.CreateFailed, restore(snap, root));
}

/// Content written over every file when probing whether a checker actually looks at
/// the state. Distinctive enough to recognise in a report, and not valid content for
/// anything a target is likely to store.
pub const corruption_probe = "sideeye-corruption-probe\n";

/// Where every symlink is pointed during the falsification probe: a name that exists
/// nowhere, distinctive enough to recognise in a checker's error output. A symlink's
/// judged identity is its target string, so retargeting is the corruption that
/// preserves the structure — the link stays a link, the farm shape stays intact, and
/// only the thing a link-aware checker must verify has changed (#122).
pub const corruption_probe_target = "sideeye-corruption-probe-target";

/// Overwrite every file in the state directory — and retarget every symlink —
/// leaving the structure intact.
///
/// This exists for DESIGN §14-13: before exploring, a deliberately corrupted state must
/// make the checker fail, otherwise the checker is not testing what it claims and every
/// PASS it produces afterwards is meaningless.
///
/// Emptying the directory would be the obvious way to corrupt it and is the wrong one.
/// A checker that compares a diagnostic command against reality — the shape sideeye
/// exists to encourage — finds an empty state perfectly *consistent*: the diagnostic
/// says unhealthy, nothing loads, the two agree. Replacing contents while keeping the
/// files in place breaks the agreement instead of removing the subject.
pub fn corruptState(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    // Overwriting is destructive too: a root swapped since it was resolved sends every
    // write below outside the state directory. The single call site runs this immediately
    // after `restore`, which refuses the same way — but relying on the neighbour is how a
    // guard ends up covering one entry point and not the next.
    try assertRootResolvesToItself(root);
    // Through the same held descriptor as `restore`, for the same reason: writing by
    // pathname after the root has been vetted leaves the vet's window open, and this
    // function's own comment above says relying on the neighbour is how a guard ends up
    // covering one entry point and not the next.
    const fd = switch (try openRootDir(root)) {
        .absent => return error.CreateFailed,
        .fd => |f| f,
    };
    defer _ = posix.close(fd);
    for (snap.entries.items) |e| {
        // The corruptible kinds, named once and in the same terms `countCorruptible`
        // uses. They were two separate conditions here — `== .symlink` and then
        // `!= .file` — which is the same predicate said differently in two places, and
        // the falsification gate reads the other one to decide whether corrupting is
        // even possible.
        if (e.kind != .file and e.kind != .symlink) continue;
        var rel_buf: [contract.max_path]u8 = undefined;
        const rel_z = std.fmt.bufPrintZ(&rel_buf, "{s}", .{e.rel}) catch return error.PathTooLong;
        if (e.kind == .symlink) {
            // Replace, not follow: opening the link would corrupt whatever it points
            // at, which may be outside the state directory entirely. A checker that
            // never notices every link in the state pointing at a nonexistent probe
            // name is not checking the links — the same argument as overwriting file
            // contents, applied to the only content a symlink has.
            if (posix.unlinkat(fd, rel_z.ptr, 0) != 0) return error.CreateFailed;
            if (posix.symlinkat(corruption_probe_target, fd, rel_z.ptr) != 0) return error.CreateFailed;
            continue;
        }
        const wfd = posix.openat(fd, rel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC | posix.O_CLOEXEC, @as(c_uint, 0o644));
        // A file that could not be overwritten leaves the state intact, and an intact
        // state is one the checker is right to accept. The run would then report
        // `checker_not_falsified` — "the checker accepted a state whose every file had
        // been overwritten with junk" — about files this function failed to touch,
        // blaming the caller's checker for the engine's own failed write. The same
        // silence was fixed in `restore` and `deleteTree`; the scan that found those
        // looked at the two functions named in the finding and missed this one.
        if (wfd < 0) return error.CreateFailed;
        var off: usize = 0;
        while (off < corruption_probe.len) {
            const w = posix.write(wfd, corruption_probe[off..].ptr, corruption_probe.len - off);
            if (w <= 0) {
                _ = posix.close(wfd);
                return error.CreateFailed;
            }
            off += @intCast(w);
        }
        _ = posix.close(wfd);
    }
}

/// How many entries `corruptState` can actually corrupt. The falsification gate asks
/// this before trusting a checker; counting only files would send a symlink-farm state
/// (entries: directories and links, zero regular files) into "nothing to corrupt"
/// while corruptState has a real probe for its links (#122).
pub fn countCorruptible(snap: Snapshot) usize {
    var n: usize = 0;
    for (snap.entries.items) |e| {
        if (e.kind == .file or e.kind == .symlink) n += 1;
    }
    return n;
}

pub const WorldResult = struct {
    k: u32,
    term: posix.Term,
    landed: bool,
    violation: ?Violation,
};

test "freshDir refuses a root a mistake would produce, before any I/O" {
    // The behavioral half — an existing root comes back empty, a missing one is
    // created — is pinned at the call site by mcp-acceptance check 8 (explore, then
    // replay twice in one server session), which was seen red before the feature.
    // What must hold here is that the guard is wired in FRONT of the deletion.
    try std.testing.expectError(error.UnsafeRoot, freshDir("/tmp"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("/"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("relative/state"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("/tmp/x/"));
    // The guard is LEXICAL: this spelling passes it and resolves to /tmp. That is
    // why the call site hands freshDir the realpath'd state, never the case's raw
    // string — a refactor that undoes the resolution re-opens the hole this line
    // documents. (assertSafeRoot only; calling freshDir here would empty /tmp.)
    try assertSafeRoot("/tmp/../tmp");
}

test "assertSafeRoot rejects roots a mistake would produce" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("relative/path"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot(""));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp/x/"));
    try assertSafeRoot("/tmp/x/state");
    try assertSafeRoot("/work/state");
}

test "assertSafeRoot rejects the spellings production actually receives" {
    // Both call sites hand over the realpath'd root, and on macOS every path in the
    // three lines above arrives through /private. The cases above assert the depth rule
    // on inputs production never evaluates: `--state /tmp` reaches the guard as
    // "/private/tmp", which has two components and passed. This test is the reason the
    // exact-match list exists.
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/var/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/Users"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/home"));

    // Scratch under those roots is the ordinary case and must still pass — the entries
    // above are exact, not trees.
    try assertSafeRoot("/private/tmp/x/state");
    try assertSafeRoot("/Users/someone/scratch/state");

    // $TMPDIR on macOS. /var is absent from the tree list precisely so this passes; a
    // list that denied /var wholesale would refuse the platform's own scratch space.
    try assertSafeRoot("/private/var/folders/lm/abcdef/T/state");
}

test "assertSafeRoot rejects system trees, on component boundaries" {
    // The paths this guard exists for. /var/lib/myapp is what docs/ci-quickstart.md
    // suggested; it has three components, so a depth rule accepts it.
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/lib/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/var/lib/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/usr/local/share/x"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/etc/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/etc/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/Library/Application Support/x"));
    // The tree itself, not only what is under it.
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/lib"));

    // Component boundary: naming a denied prefix is not sitting inside it. A
    // `startsWith` test would refuse both of these.
    try assertSafeRoot("/var/library/state");
    try assertSafeRoot("/optimism/state");
}

test "assertSafeRoot covers what each platform resolves the shorthand to" {
    // Linux resolves /var/run to /run and /var/lock to /run/lock, so a list holding only
    // the /var spellings is inert there in exactly the way the pre-/private list was
    // inert on macOS. Measured in the CI container: /var/run -> /run.
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/run/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/run/lock/x"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/run/myapp"));

    // Site-local trees an operator populates are NOT denied, and that is a judgement
    // rather than a measurement — there is no override flag, so a wrong entry is a wall.
    // These two lines are the record of the decision, and they fail if someone adds
    // either tree back without revisiting it.
    try assertSafeRoot("/opt/myapp/state");
    try assertSafeRoot("/srv/myapp/state");
}

test "assertSafeNamingRoot drops the depth rule and refuses ancestors instead (#329)" {
    const t = std.testing;

    // The point of the change: a single-component mount, which the depth rule refused
    // and which the container this project recommends is shaped like.
    try assertSafeNamingRoot("/work");
    try assertSafeNamingRoot("/opt");
    try assertSafeNamingRoot("/repo");
    // Depth is not consulted at all, so the deep roots keep passing for the same reasons
    // they always did.
    try assertSafeNamingRoot("/opt/myapp/state");
    try assertSafeNamingRoot("/Users/someone/scratch");
    try assertSafeNamingRoot("/var/library/state");

    // The ancestor read, and this is the whole of its covered set — measured by
    // enumerating both lists, not chosen by example. `/private` and `/private/var` are
    // reachable only on macOS and `spike/mcp-acceptance.sh` runs only on Linux, so these
    // three lines are the only place the set is pinned on both platforms.
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/var"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private/var"));

    // Everything the shared checks refuse still refuses.
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot(""));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("relative/path"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/work/"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/tmp"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private/tmp"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/Users"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/var/lib/myapp"));

    // The predicates still differ in one direction, which is the point of the split: the
    // destructive side refuses a depth-1 root that the naming side accepts. They no
    // longer differ in the other — #358 gave the destructive side the outward read, so
    // the line below used to read `try assertSafeRoot("/private/var")` and was the hole
    // being tracked.
    try t.expectError(error.UnsafeRoot, assertSafeRoot("/work"));
    try t.expectError(error.UnsafeRoot, assertSafeRoot("/private/var"));
}

test "assertSafeRoot refuses the ancestor a typed /var resolves to (#358)" {
    const t = std.testing;

    // The composition, not the spelling. Every call site hands over the realpath'd root,
    // so on macOS a typed `/var` arrives here as `/private/var` — deep enough for the
    // depth rule, and an ancestor of `/private/var/lib`. A lexical assertion cannot carry
    // this claim: it is about what the resolver produces. #329's note in mcp-acceptance
    // describes the same shape one surface over — the naming vet's composition through the
    // MCP startup path — and that gap is still open; this test borrows its form, not its
    // coverage.
    //
    // On Linux `realpath("/var")` is `/var`, one component, refused by the depth rule
    // before and after this change — so a green here proves nothing on that platform and
    // is not counted. The assertion below is the macOS job's.
    var buf: [contract.max_path]u8 = undefined;
    const resolved_z = posix.realpath("/var", &buf) orelse {
        // A failure, not a skip: a host without /var would otherwise make this vacuous
        // and nobody would learn that the check stopped looking.
        return error.TestUnexpectedResult;
    };
    const resolved = std.mem.span(resolved_z);
    try t.expectError(error.UnsafeRoot, assertSafeRoot(resolved));

    // The refusal above is not enough on its own: on Linux the resolver returns `/var`,
    // which the depth rule refuses, so a green there says nothing about the outward read.
    // Count the components and assert which rule is doing the work. Two or more means the
    // depth rule passed it and something else refused it — on this repository's lists,
    // only the outward read can. One component means the platform never composes the
    // shape this test is about, and the assertion above is the depth rule's.
    var slashes: usize = 0;
    for (resolved) |ch| {
        if (ch == '/') slashes += 1;
    }
    if (slashes >= 2) {
        // The composition macOS produces: /var -> /private/var, deep enough to pass the
        // depth rule and an ancestor of /private/var/lib. Before #358 this was accepted.
        try t.expect(std.mem.eql(u8, resolved, "/private/var"));
    }
}

test "assertRootResolvesToItself refuses a root swapped for a symlink after resolution" {
    // The window this closes: assertSafeRoot and the resolution behind it run before
    // --setup, and setup (or the recorded operation) can leave a link where the state
    // directory was. deleteTree refuses symlinked ENTRIES but reaches the root through
    // opendir, which follows one.
    // Pid-unique parent (#28: zig build test runs test binaries concurrently), and the
    // base is taken back through realpath: on macOS /tmp is itself a link, so a literal
    // "/tmp/..." root never resolves to itself and every assertion below would be about
    // the wrong thing.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-rootswap-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var good_buf: [contract.max_path]u8 = undefined;
    const good = std.fmt.bufPrint(&good_buf, "{s}/state", .{base}) catch unreachable;
    var good_z: [contract.max_path]u8 = undefined;
    const good_zs = std.fmt.bufPrintZ(&good_z, "{s}", .{good}) catch unreachable;
    var other_buf: [contract.max_path]u8 = undefined;
    const other = std.fmt.bufPrint(&other_buf, "{s}/elsewhere", .{base}) catch unreachable;
    var other_z: [contract.max_path]u8 = undefined;
    const other_zs = std.fmt.bufPrintZ(&other_z, "{s}", .{other}) catch unreachable;
    defer {
        _ = posix.unlink(good_zs.ptr);
        _ = posix.rmdir(good_zs.ptr);
        _ = posix.rmdir(other_zs.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    try std.testing.expect(posix.mkdir(good_zs.ptr, 0o755) == 0);
    // Resolves to itself: accepted.
    try assertRootResolvesToItself(good);

    // Now the swap. The link points at a sibling, which is enough — what is refused is
    // "this root no longer resolves to itself", not "the target is dangerous".
    try std.testing.expect(posix.mkdir(other_zs.ptr, 0o755) == 0);
    try std.testing.expect(posix.rmdir(good_zs.ptr) == 0);
    try std.testing.expect(posix.symlink(other_zs.ptr, good_zs.ptr) == 0);

    try std.testing.expectError(error.UnsafeRoot, assertRootResolvesToItself(good));
    // Control: the sibling the link points at is itself fine, so the refusal above is
    // about the swap and not about anything in this directory.
    try assertRootResolvesToItself(other);

    // A root that is simply absent is not a swap: deleteTree already returns silently
    // for it, and refusing here would turn a tolerated state into a SETUP ERROR.
    try std.testing.expect(posix.unlink(good_zs.ptr) == 0);
    try assertRootResolvesToItself(good);
}

test "restore and freshDir refuse a swapped root — the guard is wired in front of the delete" {
    // The test above drives assertRootResolvesToItself directly, which says nothing about
    // whether the destructive path calls it. Deleting the call from `restore` left that
    // test green (measured), so this one aims at the call sites instead: a guard that
    // exists and never executes is the failure mode being ruled out here.
    const gpa = std.testing.allocator;

    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-wired-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{base}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    var obuf: [contract.max_path]u8 = undefined;
    const outside = std.fmt.bufPrint(&obuf, "{s}/outside", .{base}) catch unreachable;
    var ozbuf: [contract.max_path]u8 = undefined;
    const outside_z = std.fmt.bufPrintZ(&ozbuf, "{s}", .{outside}) catch unreachable;
    defer {
        _ = posix.unlink(root_z.ptr); // the symlink, if the swap below happened
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        deleteTree(outside) catch {};
        _ = posix.rmdir(outside_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(outside_z.ptr, 0o755) == 0);

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a", .kind = .file, .content = "x" });

    // Control: the unswapped root restores. Without this the refusal below could be
    // about anything in this directory rather than about the swap.
    try restore(snap, root);

    // A sentinel outside the state directory. If the guard is not wired in, the delete
    // follows the link and this file goes with it.
    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    const fd = posix.open(sentinel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);

    // The swap: what --setup or the recorded operation could leave behind.
    deleteTree(root) catch {};
    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    try std.testing.expect(posix.symlink(outside_z.ptr, root_z.ptr) == 0);

    try std.testing.expectError(error.UnsafeRoot, restore(snap, root));
    try std.testing.expectError(error.UnsafeRoot, freshDir(root));
    // corruptState writes rather than deletes, and its one call site sits directly after
    // `restore`. Covering it here rather than leaning on that neighbour: the ordering at
    // the call site is not a property of this function.
    try std.testing.expectError(error.UnsafeRoot, corruptState(snap, root));

    // The sentinel survived: the refusal happened before anything was removed.
    try std.testing.expectEqual(posix.Kind.file, try posix.kindOfPathNoFollow(sentinel_z.ptr));
}

test "the walk drains a directory past its collection bound, in one call (#327)" {
    // The reopen loop exists because names must be collected before anything is deleted,
    // and the collection buffers are finite: 256 entries or 4096 bytes of names, whichever
    // runs out first. Each pass must therefore start reading the directory from the
    // beginning — the pre-descriptor code got that from calling `opendir` fresh, a new
    // open file description with its own offset at zero.
    //
    // `dup` does NOT give that: a duplicate shares the file description, offset included,
    // and neither libc rewinds it in `fdopendir`. A walk built on `dup` resumes pass two
    // where pass one stopped, finds nothing after the tail, and reads that as "empty" —
    // returning success over a directory it did not drain. `removed < count` cannot see it:
    // every entry that was collected was removed, and the loss is in the collection.
    //
    // Residue is the failure this whole function is written against: world k judged
    // against world k-1's leftovers. 400 entries clears the 256 bound with room to spare.
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-drain-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(base_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var rb: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rb, "{s}/state", .{base}) catch unreachable;
    var rzb: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzb, "{s}", .{root}) catch unreachable;
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    var i: usize = 0;
    while (i < 400) : (i += 1) {
        var nb: [contract.max_path]u8 = undefined;
        const n_z = std.fmt.bufPrintZ(&nb, "{s}/entry-{d}", .{ root, i }) catch unreachable;
        const fd = posix.open(n_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(fd >= 0);
        _ = posix.close(fd);
    }

    try deleteTree(root);

    // Counted rather than sampled: "the first entry is gone" is true of a partial drain.
    var snap = try takeSnapshot(std.testing.allocator, root);
    defer snap.deinit();
    try std.testing.expectEqual(@as(usize, 0), snap.entries.items.len);
}

test "freshDir on a missing parent stays loud; the shared open has two meanings (#327)" {
    // One `open`, two readings of ENOENT. `deleteTree` reads it as "nothing to delete" and
    // returns; `freshDir` has already failed its `mkdir` by the time it looks, so the same
    // errno means a missing parent — and a --fresh-state that could not do its job and said
    // nothing is the silent no-op the flag exists to remove. An implementation that let the
    // walk's reading carry here is green everywhere else and wrong exactly here.
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-noparent-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.rmdir(base_z.ptr); // must not exist; a leftover from a crashed run would hide the case
    var rb: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rb, "{s}/gone/state", .{base_z}) catch unreachable;

    try std.testing.expectError(error.DeleteFailed, freshDir(root));

    // Control: with the parent there, the same call succeeds — so the refusal above is
    // about the missing parent and not about the path being rejected for some other reason.
    var gb: [contract.max_path]u8 = undefined;
    const gone_z = std.fmt.bufPrintZ(&gb, "{s}/gone", .{base_z}) catch unreachable;
    var rzb: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzb, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(gone_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    try std.testing.expect(posix.mkdir(base_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(gone_z.ptr, 0o755) == 0);
    try freshDir(root);
}

test "the walk on its own follows a swapped root; the descriptor is what stops it (#327)" {
    // The neighbour above proves the shipped entry points refuse a symlinked root, so it
    // says nothing about the walk itself. This one removes the guard from the picture and
    // asks what the walk supplies on its own — which is the only thing that answers a swap
    // landing AFTER the guard has already run. Red before #327: `opendir` follows the link
    // and the sentinel outside the tree is removed.
    //
    // Not a claim that the shipped entry points are vulnerable. They are guarded, and the
    // neighbour above measures that.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-isolated-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{base}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    var obuf: [contract.max_path]u8 = undefined;
    const outside = std.fmt.bufPrint(&obuf, "{s}/outside", .{base}) catch unreachable;
    var ozbuf: [contract.max_path]u8 = undefined;
    const outside_z = std.fmt.bufPrintZ(&ozbuf, "{s}", .{outside}) catch unreachable;
    defer {
        _ = posix.unlink(root_z.ptr); // the symlink planted below
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        deleteTree(outside) catch {};
        _ = posix.rmdir(outside_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(outside_z.ptr, 0o755) == 0);

    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    const fd = posix.open(sentinel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);

    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    try std.testing.expect(posix.symlink(outside_z.ptr, root_z.ptr) == 0);

    deleteTree(root) catch {};

    try std.testing.expectEqual(posix.Kind.file, try posix.kindOfPathNoFollow(sentinel_z.ptr));
}

/// A snapshot built from literal pairs, for tests.
///
/// Sorts, like `takeSnapshot` does. It did not, and that made the sorted order an
/// accident of one producer rather than a property every `Snapshot` has — which is
/// exactly what `find` now depends on. Ten of the call sites below pass their pairs in
/// an order that is not lexicographic, so a `find` that assumed sorting would have
/// returned wrong answers here rather than failing loudly (#262).
///
/// Sorting can change which violation a test observes: `classify` walks `pre.entries`
/// in order into `plan.files`, and both judges return on the first violation in that
/// list. Every fixture here arranges one violation at a time, so the reported answer
/// does not move — but a fixture with two would be decided by this sort.
fn testSnapshot(gpa: Allocator, pairs: []const [2][]const u8) !Snapshot {
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

/// classify + judgeL0 in one call, for tests whose interest is the verdict.
fn testJudge(gpa: Allocator, pre: Snapshot, post: Snapshot, crashed: Snapshot) !?Violation {
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    return judgeL0(plan, crashed);
}

test "L0 catches the delete-before-rename window" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    // The crashed state from the buggy toy at k=5: the key is gone, a temp remains.
    var crashed = try testSnapshot(gpa, &.{.{ "key.json.tmp", "key=2\n" }});
    defer crashed.deinit();

    const v = (try testJudge(gpa, pre, post, crashed)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.missing);
}

test "L0 accepts a leftover temporary file" {
    // This is the case a literal reading of DESIGN §12 gets wrong: the corrected toy
    // leaves key.json.tmp behind at several crash points and must still pass.
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    var mid = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" },
        .{ "key.json.tmp", "key=2\n" },
    });
    defer mid.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, mid));

    var done = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer done.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, done));
}

test "L0 catches content that is neither the old nor the new value" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();
    var torn = try testSnapshot(gpa, &.{.{ "key.json", "key=" }});
    defer torn.deinit();

    const v = (try testJudge(gpa, pre, post, torn)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.hybrid);
}

test "L0 ignores files the operation legitimately creates or deletes" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "old.json", "gone\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "new.json", "fresh\n" }});
    defer post.deinit();
    // Neither file present: mid-flight, and not a violation, since no path appears in
    // both snapshots.
    var empty = try testSnapshot(gpa, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, empty));
}

test "classify puts only a non-empty strict extension into the history form" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{
        .{ "grew.log", "born\n" }, // non-empty strict extension -> history
        .{ "key.json", "key=1\n" }, // diverged -> standard
        .{ "same.txt", "still\n" }, // unchanged -> standard
        .{ "fresh.log", "" }, // empty pre -> standard, however post grew
        .{ "shrunk.db", "abc\n" }, // post shorter -> standard
    });
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{
        .{ "grew.log", "born\nappended\n" },
        .{ "key.json", "key=2\n" },
        .{ "same.txt", "still\n" },
        .{ "fresh.log", "grown\n" },
        .{ "shrunk.db", "a" },
    });
    defer post.deinit();

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 1), plan.history_count);
    for (plan.files.items) |f| {
        const expected: FileForm = if (std.mem.eql(u8, f.rel, "grew.log")) .history else .standard;
        try std.testing.expectEqual(expected, f.form);
    }
}

test "the post-success invariant judges the whole post snapshot (ADR 0008)" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" }, // standard: must equal post in a marker world
        .{ "audit.log", "e1\n" }, // history: must have gained something
        .{ "old.tmp", "x\n" }, // pre-only: the operation deletes it
    });
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" }, // post-only: the operation creates it
    });
    defer post.deinit();
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();

    // The full new state survives: no violation.
    var durable = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2 different-tail\n" },
        .{ "receipt.txt", "different-content\n" }, // existence only; content not judged
    });
    defer durable.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, durable));

    // A shared file still on its old content is not durable.
    var stale = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" },
    });
    defer stale.deinit();
    try std.testing.expectEqualStrings("key.json", judgeL1(plan, pre, post, stale).?.not_durable);

    // A history file that gained nothing lost the claimed change.
    var ungrown = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\n" },
        .{ "receipt.txt", "ok\n" },
    });
    defer ungrown.deinit();
    try std.testing.expectEqualStrings("audit.log", judgeL1(plan, pre, post, ungrown).?.not_durable);

    // A created file that vanished, and a deleted file that returned.
    var uncreated = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
    });
    defer uncreated.deinit();
    try std.testing.expectEqualStrings("receipt.txt", judgeL1(plan, pre, post, uncreated).?.not_durable);
    var undeleted = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" },
        .{ "old.tmp", "x\n" },
    });
    defer undeleted.deinit();
    try std.testing.expectEqualStrings("old.tmp", judgeL1(plan, pre, post, undeleted).?.not_durable);

    // Kind is identity too: a created file that came back as a same-named directory
    // is not the promised state, even where content comparison would pass (a
    // directory's content is the empty string).
    var kind_swap = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "" },
    });
    defer kind_swap.deinit();
    // By name, not by index. This was `items[2]`, meaning "the third one written above" —
    // which stopped being the same thing the moment `testSnapshot` started sorting. It
    // still lands on `receipt.txt` in lexicographic order, so the index would have kept
    // passing; it would just have been passing by coincidence.
    for (kind_swap.entries.items) |*e| {
        if (std.mem.eql(u8, e.rel, "receipt.txt")) e.kind = .dir;
    }
    try std.testing.expectEqualStrings("receipt.txt", judgeL1(plan, pre, post, kind_swap).?.not_durable);
}

test "history form tolerates any tail and the loss of none of the history" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t=17\n" }});
    defer post.deinit();

    // Killed before the append: exactly the pre content.
    var untouched = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer untouched.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, untouched));

    // Killed mid-append: a torn tail. The bytes after pre are not judged.
    var torn = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t" }});
    defer torn.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, torn));

    // A re-run's tail differs from the recorded one entirely — still not judged.
    var other_tail = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t=99 and longer than recorded\n" }});
    defer other_tail.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, other_tail));
}

test "history form catches history that was rewritten, truncated or replaced" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2\n" }});
    defer post.deinit();

    // Emptied: the truncate-then-rewrite window.
    var emptied = try testSnapshot(gpa, &.{.{ "audit.log", "" }});
    defer emptied.deinit();
    const v1 = (try testJudge(gpa, pre, post, emptied)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v1.rewritten);

    // Cut mid-history: shorter than pre.
    var cut = try testSnapshot(gpa, &.{.{ "audit.log", "entry" }});
    defer cut.deinit();
    const v2 = (try testJudge(gpa, pre, post, cut)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v2.rewritten);

    // Same length, different bytes.
    var swapped = try testSnapshot(gpa, &.{.{ "audit.log", "Xntry-1\nentry-2\n" }});
    defer swapped.deinit();
    const v3 = (try testJudge(gpa, pre, post, swapped)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v3.rewritten);

    // Gone entirely stays `missing`, as for every form.
    var gone = try testSnapshot(gpa, &.{});
    defer gone.deinit();
    const v4 = (try testJudge(gpa, pre, post, gone)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v4.missing);

    // Replaced by a directory: content would be empty, and an empty prefix test
    // would accept it — the kind check exists for exactly this.
    var as_dir: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_dir.deinit();
    try as_dir.entries.append(as_dir.arena.allocator(), .{ .rel = "audit.log", .kind = .dir, .content = "" });
    const v5 = (try testJudge(gpa, pre, post, as_dir)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v5.rewritten);
}

test "a standard-form file does not inherit the history form's tolerance" {
    // Control for the classification: key.json's post diverges from its pre, so
    // crashed content that merely *extends* pre is a hybrid, not preserved history.
    // An implementation that applies the prefix rule to every changed file passes
    // the history tests above and fails here.
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();
    var extended = try testSnapshot(gpa, &.{.{ "key.json", "key=1\ngarbage" }});
    defer extended.deinit();

    const v = (try testJudge(gpa, pre, post, extended)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.hybrid);
}

test "an empty-pre file keeps the standard rule instead of a vacuous history" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "fresh.log", "" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "fresh.log", "first entry\n" }});
    defer post.deinit();

    // A partial write is caught — under a vacuous history form it would not be.
    var partial = try testSnapshot(gpa, &.{.{ "fresh.log", "first en" }});
    defer partial.deinit();
    const v = (try testJudge(gpa, pre, post, partial)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("fresh.log", v.hybrid);

    // The two legitimate states still pass.
    var empty = try testSnapshot(gpa, &.{.{ "fresh.log", "" }});
    defer empty.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, empty));
    var full = try testSnapshot(gpa, &.{.{ "fresh.log", "first entry\n" }});
    defer full.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, full));
}

test "a symlink pair is judged by kind and by target (#122)" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v1" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v2" });

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].pre_kind);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].post_kind);
    // A symlink is never the history form: its target is replaced whole.
    try std.testing.expectEqual(@as(u32, 0), plan.history_count);

    // Killed before or after the retarget: either target is a legitimate state.
    var old_t: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer old_t.deinit();
    try old_t.entries.append(old_t.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v1" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, old_t));

    // A third target is neither: the retarget was not atomic.
    var third: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer third.deinit();
    try third.entries.append(third.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions" });
    try std.testing.expectEqualStrings("current", judgeL0(plan, third).?.hybrid);

    // The kind check's own falsification: a regular FILE holding the pre target as
    // bytes satisfies the content comparison and is still a violation — without the
    // kind guard this case reads as preserved state.
    var as_file: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_file.deinit();
    try as_file.entries.append(as_file.arena.allocator(), .{ .rel = "current", .kind = .file, .content = "versions/v1" });
    try std.testing.expectEqualStrings("current", judgeL0(plan, as_file).?.hybrid);

    // Gone entirely stays missing, as for every judged pair.
    var gone: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer gone.deinit();
    try std.testing.expectEqualStrings("current", judgeL0(plan, gone).?.missing);
}

test "a pair whose kind changes between the clean runs is judged, not skipped (#122)" {
    // The stow unfold shape: pre has a fold SYMLINK, post has a real DIRECTORY at the
    // same path. The owner's ruling: judge it by the same two-sided rule instead of
    // silently skipping — the skip was invisible while the oracle refused every
    // symlink-touching target, and became an undisclosed hole once #122 removed that
    // refusal.
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "../stow/A/sub" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "target/sub", .kind = .dir, .content = "" });

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].pre_kind);
    try std.testing.expectEqual(posix.Kind.dir, plan.files.items[0].post_kind);

    // Killed before the swap: still the fold link. Legitimate.
    var before: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer before.deinit();
    try before.entries.append(before.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "../stow/A/sub" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, before));

    // Killed after: the real directory. Legitimate.
    var after: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer after.deinit();
    try after.entries.append(after.arena.allocator(), .{ .rel = "target/sub", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, after));

    // Killed mid-swap (link deleted, directory not yet made): the path is gone —
    // the non-atomic window this pair exists to expose.
    var mid: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer mid.deinit();
    try std.testing.expectEqualStrings("target/sub", judgeL0(plan, mid).?.missing);

    // A link retargeted to neither side matches neither identity.
    var wrong: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer wrong.deinit();
    try wrong.entries.append(wrong.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "/elsewhere" });
    try std.testing.expectEqualStrings("target/sub", judgeL0(plan, wrong).?.hybrid);

    // An unchanged directory pair used to stay out of the plan; since #164 it
    // enters (its kind is the comparison) and an intact world judges clean.
    var pre2: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre2.deinit();
    try pre2.entries.append(pre2.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    var post2: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post2.deinit();
    try post2.entries.append(post2.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    var plan2 = try classify(gpa, pre2, post2);
    defer plan2.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan2.files.items.len);
    var d_ok: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer d_ok.deinit();
    try d_ok.entries.append(d_ok.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan2, d_ok));
}

test "L1 judges a post-only symlink by its target, not existence alone (#122)" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "../pkg/real" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();

    // The promised link, target and all: durable.
    var ok: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer ok.deinit();
    try ok.entries.append(ok.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "../pkg/real" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, ok));

    // Present but pointing anywhere else: the loss the success claim promised away.
    var retargeted: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer retargeted.deinit();
    try retargeted.entries.append(retargeted.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "/elsewhere" });
    try std.testing.expectEqualStrings("farm/link", judgeL1(plan, pre, post, retargeted).?.not_durable);
}

test "readLinkTarget is fail-closed at its own boundary (#122)" {
    // A real link with a 10-byte target; the guard's own predicate is "a result that
    // fills the buffer is refused", so an 8-byte and an exactly-10-byte buffer must
    // both answer null, and only a roomier buffer answers the target.
    var dbuf: [contract.max_path]u8 = undefined;
    const dir_z = std.fmt.bufPrintZ(&dbuf, "/tmp/sideeye-readlink-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(dir_z.ptr, 0o755);
    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&lbuf, "{s}/l", .{dir_z}) catch unreachable;
    _ = posix.unlink(link_z.ptr);
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("0123456789", link_z.ptr));
    defer {
        _ = posix.unlink(link_z.ptr);
        _ = posix.rmdir(dir_z.ptr);
    }

    var small: [8]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(link_z.ptr, &small));
    var exact: [10]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(link_z.ptr, &exact));
    var roomy: [11]u8 = undefined;
    try std.testing.expectEqualStrings("0123456789", readLinkTarget(link_z.ptr, &roomy).?);
    // n < 0: not a link at all.
    var missing_buf: [contract.max_path]u8 = undefined;
    const missing_z = std.fmt.bufPrintZ(&missing_buf, "{s}/absent", .{dir_z}) catch unreachable;
    var big: [64]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(missing_z.ptr, &big));
}

test "snapshot, restore and corruptState carry symlinks as links (#122)" {
    const gpa = std.testing.allocator;

    // Pid-unique root (#28: zig build test runs test binaries concurrently), built from
    // the RESOLVED parent: `restore` requires the root to resolve to itself
    // (assertRootResolvesToItself), which is what the call sites hand it. A literal "/tmp/..."
    // root satisfies that on Linux and fails on macOS, where /tmp is itself a link.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-symlink-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var dbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&dbuf, "{s}/state", .{base}) catch unreachable;
    var rbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var fbuf: [contract.max_path]u8 = undefined;
    const file_z = try joinZ(&fbuf, root, "key.json");
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 4), posix.write(fd, "k=1\n", 4));
    _ = posix.close(fd);
    var lbuf: [contract.max_path]u8 = undefined;
    const rel_link_z = try joinZ(&lbuf, root, "rel-link");
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("key.json", rel_link_z.ptr));
    var gbuf: [contract.max_path]u8 = undefined;
    const dangling_z = try joinZ(&gbuf, root, "dangling");
    // A dangling link is a legitimate snapshot citizen: readlink works, follow fails.
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("/nowhere/dangling", dangling_z.ptr));

    var snap = try takeSnapshot(gpa, root);
    defer snap.deinit();
    try std.testing.expectEqual(@as(usize, 3), snap.entries.items.len);
    const rl = snap.find("rel-link") orelse return error.MissingEntry;
    try std.testing.expectEqual(posix.Kind.symlink, rl.kind);
    try std.testing.expectEqualStrings("key.json", rl.content);
    const dg = snap.find("dangling") orelse return error.MissingEntry;
    try std.testing.expectEqual(posix.Kind.symlink, dg.kind);
    try std.testing.expectEqualStrings("/nowhere/dangling", dg.content);
    try std.testing.expectEqual(@as(usize, 3), countCorruptible(snap));

    // Retarget one link and delete the other, then restore: both come back verbatim,
    // the dangling one restored dangling.
    try std.testing.expectEqual(@as(c_int, 0), posix.unlink(rel_link_z.ptr));
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("elsewhere", rel_link_z.ptr));
    try std.testing.expectEqual(@as(c_int, 0), posix.unlink(dangling_z.ptr));
    try restore(snap, root);
    var tbuf: [contract.max_path]u8 = undefined;
    var n = posix.readlink(rel_link_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("key.json", tbuf[0..@intCast(n)]);
    n = posix.readlink(dangling_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("/nowhere/dangling", tbuf[0..@intCast(n)]);

    // corruptState retargets every link at the probe name — a checker that resolves
    // or compares link targets has something it must fail on.
    try corruptState(snap, root);
    n = posix.readlink(rel_link_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings(corruption_probe_target, tbuf[0..@intCast(n)]);
    n = posix.readlink(dangling_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings(corruption_probe_target, tbuf[0..@intCast(n)]);
}

test "a links-only state is corruptible, so the falsification gate keeps meaning (#122)" {
    // The stow shape: a state directory of directories and symlinks, zero regular
    // files. countCorruptible must not send it into "nothing to corrupt".
    const gpa = std.testing.allocator;
    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "pkg", .kind = .dir, .content = "" });
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "pkg/bin", .kind = .symlink, .content = "../stow/pkg/bin" });
    try std.testing.expectEqual(@as(usize, 1), countCorruptible(snap));
}

test "ownership/permission writes change nothing a snapshot judges (#121's own predicate)" {
    // The exclusion's predicate, pinned directly instead of resting on inference
    // (R1): chmod on a state file must leave the snapshot byte-identical, because
    // the judged state is names, bytes and link targets. If Entry ever grows a mode
    // field, this test goes red and #121's report wording has to change with it.
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-chmod-inv-{d}", .{posix.getpid()}) catch unreachable;
    var dz_buf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&dz_buf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try joinZ(&fbuf, dir, "f.txt");
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 2), posix.write(fd, "x\n", 2));
    _ = posix.close(fd);
    defer {
        _ = posix.unlink(fz.ptr);
        _ = posix.rmdir(dz.ptr);
    }

    const gpa = std.testing.allocator;
    var before = try takeSnapshot(gpa, dir);
    defer before.deinit();
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(fz.ptr, 0o600));
    var after = try takeSnapshot(gpa, dir);
    defer after.deinit();

    try std.testing.expectEqual(before.entries.items.len, after.entries.items.len);
    for (before.entries.items, after.entries.items) |b, a| {
        try std.testing.expectEqualStrings(b.rel, a.rel);
        try std.testing.expectEqual(b.kind, a.kind);
        try std.testing.expectEqualStrings(b.content, a.content);
    }
}

test "deleteTree refuses a PARTIAL failure instead of leaving residue (#121, R1)" {
    // An unreadable directory is skipped silently by opendir, its rmdir then fails —
    // and a sibling that deletes fine used to make the pass count as success. The
    // residue would be judged as the next world's state.
    if (std.c.geteuid() == 0) return error.SkipZigTest; // root ignores modes
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-deltree-{d}/state", .{posix.getpid()}) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-deltree-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var rz_buf: [contract.max_path]u8 = undefined;
    const rz = std.fmt.bufPrintZ(&rz_buf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(rz.ptr, 0o755);
    var sb: [contract.max_path]u8 = undefined;
    const sub_z = try joinZ(&sb, dir, "locked");
    _ = posix.mkdir(sub_z.ptr, 0o755);
    var ib: [contract.max_path]u8 = undefined;
    const inner_z = try joinZ(&ib, dir, "locked/held.txt");
    const fd = posix.open(inner_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    var gb: [contract.max_path]u8 = undefined;
    const gone_z = try joinZ(&gb, dir, "goes.txt");
    const fd2 = posix.open(gone_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd2 >= 0);
    _ = posix.close(fd2);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(sub_z.ptr, 0o000));
    defer {
        _ = std.c.chmod(sub_z.ptr, 0o755);
        _ = posix.unlink(inner_z.ptr);
        _ = posix.rmdir(sub_z.ptr);
        _ = posix.unlink(gone_z.ptr);
        _ = posix.rmdir(rz.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    // The sibling deletes, the locked directory cannot — the pass must refuse.
    try std.testing.expectError(error.DeleteFailed, deleteTree(dir));
}

test "a trace written against another contract version is a mismatch, not a short trace" {
    // The third structural detector, and the only one that had never been seen firing.
    // It is what stops a stale shim paired with a fresh engine from being read as a
    // target that performed fewer operations than it did — sharing contract.zig at build
    // time says nothing about which binaries end up in the same run.
    var buf: [contract.header_len]u8 = undefined;
    _ = try contract.encodeHeader(&buf);
    std.mem.writeInt(u32, buf[contract.magic.len..][0..4], contract.contract_version + 1, .little);

    // Pid-unique path: engine tests run in more than one test binary, and
    // `zig build test` runs those binaries concurrently — a fixed name raced
    // between the write, the read and the unlink, failing a different assert
    // each time it lost (#28: measured at three distinct lines in one day).
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-version-test-{d}", .{posix.getpid()}) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pbuf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try joinZ(&fbuf, dir, "trace.bin");
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, buf.len), posix.write(fd, &buf, buf.len));
    _ = posix.close(fd);

    var info = try readTrace(std.testing.allocator, std.mem.span(fz.ptr));
    defer info.deinit();
    try std.testing.expect(info.version_mismatch);
    // Distinct from truncation: the two lead to different verdicts and different advice.
    try std.testing.expect(!info.truncated);
    try std.testing.expect(info.saw_header);

    // Control: the same header at the right version is not a mismatch.
    var ok_buf: [contract.header_len]u8 = undefined;
    _ = try contract.encodeHeader(&ok_buf);
    const fd2 = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd2 >= 0);
    try std.testing.expectEqual(@as(isize, ok_buf.len), posix.write(fd2, &ok_buf, ok_buf.len));
    _ = posix.close(fd2);
    var ok_info = try readTrace(std.testing.allocator, std.mem.span(fz.ptr));
    defer ok_info.deinit();
    try std.testing.expect(!ok_info.version_mismatch);

    _ = posix.unlink(fz.ptr);
    _ = posix.rmdir(dz.ptr);
}

fn writeTraceForTest(dir_tag: []const u8, records: []const contract.Record, fbuf: *[contract.max_path]u8) ![*:0]const u8 {
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-{s}-{d}", .{ dir_tag, posix.getpid() }) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pbuf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    const fz = try joinZ(fbuf, dir, "trace.bin");
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    var hbuf: [contract.header_len]u8 = undefined;
    const hn = try contract.encodeHeader(&hbuf);
    try std.testing.expectEqual(@as(isize, @intCast(hn)), posix.write(fd, &hbuf, hn));
    for (records) |rec| {
        var rbuf: [2 * contract.max_path]u8 = undefined;
        const rn = try contract.encodeRecord(&rbuf, rec);
        try std.testing.expectEqual(@as(isize, @intCast(rn)), posix.write(fd, &rbuf, rn));
    }
    _ = posix.close(fd);
    return fz.ptr;
}

test "a subject exec followed by a shim_ready carrying the count is a continuation (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-cont", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 2, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 3, .pid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var info = try readTrace(std.testing.allocator, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    try std.testing.expectEqual(@as(u32, 3), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 3), info.primary_kill_records);
    _ = posix.unlink(fz);
}

test "a subject exec whose shim_ready restarts at zero is a broken chain, and the renumbering is caught (#123)" {
    // The stale-shim shape contract v10 exists for: numbering restarted after the
    // image change. Two independent detectors must both see it — the continuation
    // predicate (wrong base) and the records-vs-max disagreement.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-restart", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var info = try readTrace(std.testing.allocator, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    // records = 3, max = 2: the duplicate seq 1 collapses under @max.
    try std.testing.expectEqual(@as(u32, 3), info.primary_kill_records);
    try std.testing.expectEqual(@as(u32, 2), info.kill_point_count);
    _ = posix.unlink(fz);
}

test "a subject exec with no shim_ready after it is a broken chain (#123)" {
    // The static-image / stripped-environment / execl-family shape: the far side of
    // the image change was never observed at all.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-dark", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
    }, &fbuf);
    var info = try readTrace(std.testing.allocator, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "a second announcement with no exec record is itself an image change (#123)" {
    // The execl-family shape with nothing recorded before it: no exec record, so
    // no window — but the constructor runs once per image, and a second same-pid
    // shim_ready is self-contained evidence the image changed. R1 measured this
    // slipping to a verdict when only the numbering check stood behind it (zero
    // prior ops make records == max trivially).
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("dup-announce", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var info = try readTrace(std.testing.allocator, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "a child's exec never opens a continuation window and stays tolerable (#123)" {
    // The pass shape: children exec and the subject keeps going. The exec itself is
    // not hard; the child's state-directory write is what refuses the run, through
    // foreign_kill_point — the boundary stays a spawn doing what spawns do.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-child", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 9, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 9, .path = "/tmp/s/c", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var info = try readTrace(std.testing.allocator, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expect(info.foreign_kill_point);
    _ = posix.unlink(fz);
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

test "the per-file cap refuses, names the file, and carries its size (#265)" {
    const gpa = std.testing.allocator;

    // Pid-unique root from the RESOLVED parent, the same way the symlink test above
    // builds one and for the same reason (#28; macOS /tmp is itself a link).
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-filecap-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var dbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&dbuf, "{s}/state", .{base}) catch unreachable;
    var rbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var fbuf: [contract.max_path]u8 = undefined;
    const file_z = try joinZ(&fbuf, root, "grown.log");
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 9), posix.write(fd, "123456789", 9));
    _ = posix.close(fd);

    // Against a cap the file exceeds: the refusal fires and the diag names the file
    // and its true size (from lseek, not from the truncated read).
    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.FileTooLarge,
        takeSnapshotCapped(gpa, root, onlyFileCap(8), &diag),
    );
    try std.testing.expectEqualStrings("grown.log", diag.file.rel());
    try std.testing.expectEqual(@as(?u64, 9), diag.file.size);

    // Positive control, same tree: at the cap exactly, the read is not a breach —
    // the boundary is "over", not "at" — and the snapshot succeeds.
    var ok = try takeSnapshotCapped(gpa, root, onlyFileCap(9), null);
    defer ok.deinit();
    try std.testing.expectEqual(@as(usize, 1), ok.entries.items.len);
    try std.testing.expectEqualStrings("123456789", ok.entries.items[0].content);
}

/// Caps for a test that is about ONE ceiling. The other is put out of reach, so a
/// refusal cannot be attributed to the ceiling the test is not about — and so the
/// per-file tests above keep meaning what they meant before there were two (#323).
fn onlyFileCap(n: usize) SnapshotCaps {
    return .{ .file = n, .tree = std.math.maxInt(usize) };
}

fn onlyTreeCap(n: usize) SnapshotCaps {
    return .{ .file = std.math.maxInt(usize), .tree = n };
}

/// A pid-unique `<parent>/state` built from the RESOLVED parent, plus the paths needed
/// to tear it down. Three tests below built this by hand; macOS `/tmp` is itself a link,
/// so the realpath step is load-bearing rather than tidiness (#28).
const TreeFixture = struct {
    parent_z: [contract.max_path]u8 = undefined,
    root_buf: [contract.max_path]u8 = undefined,
    root: []const u8 = &.{},

    fn init(self: *TreeFixture, tag: []const u8) ?[]const u8 {
        const parent_z = std.fmt.bufPrintZ(&self.parent_z, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
        _ = posix.mkdir(parent_z.ptr, 0o755);
        var base_buf: [contract.max_path]u8 = undefined;
        // Every caller does `init(...) orelse return error.SkipZigTest`, which is BEFORE
        // its `defer deinit()` — so a failure here has to take the parent back out itself
        // or leave a directory behind for the rest of the machine's life.
        const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse {
            _ = posix.rmdir(parent_z.ptr);
            return null;
        });
        self.root = std.fmt.bufPrint(&self.root_buf, "{s}/state", .{base}) catch unreachable;
        var rz: [contract.max_path]u8 = undefined;
        const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{self.root}) catch unreachable;
        _ = posix.mkdir(root_z.ptr, 0o755);
        return self.root;
    }

    fn deinit(self: *TreeFixture) void {
        deleteTree(self.root) catch {};
        var rz: [contract.max_path]u8 = undefined;
        const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{self.root}) catch unreachable;
        _ = posix.rmdir(root_z.ptr);
        var pz: [contract.max_path]u8 = undefined;
        const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{std.mem.sliceTo(&self.parent_z, 0)}) catch unreachable;
        _ = posix.rmdir(parent_z.ptr);
    }

    /// `n` empty directories. The shape that has no content and no file entries at all,
    /// which is the only way to reach the `.dir` branch's own charge.
    fn fillDirs(self: *TreeFixture, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var dbuf: [contract.max_path]u8 = undefined;
            var nbuf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&nbuf, "d{d:0>5}", .{i}) catch unreachable;
            const dz = try joinZ(&dbuf, self.root, name);
            if (posix.mkdir(dz.ptr, 0o755) != 0) return error.SkipZigTest;
        }
    }

    /// `n` files of `bytes` bytes each, named `f0000`, `f0001`, … — equal sizes on
    /// purpose where a test wants the break to be independent of `readdir` order.
    fn fill(self: *TreeFixture, n: usize, bytes: usize) !void {
        var chunk: [4096]u8 = @splat('x');
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var fbuf: [contract.max_path]u8 = undefined;
            var nbuf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&nbuf, "f{d:0>5}", .{i}) catch unreachable;
            const fz = try joinZ(&fbuf, self.root, name);
            const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) return error.SkipZigTest;
            defer _ = posix.close(fd);
            var left = bytes;
            while (left > 0) {
                const take = @min(left, chunk.len);
                if (posix.write(fd, &chunk, take) != @as(isize, @intCast(take))) return error.SkipZigTest;
                left -= take;
            }
        }
    }
};

test "the tree ceiling stops the walk where it breaks, rather than after reading everything (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-stop") orelse return error.SkipZigTest;
    defer fx.deinit();

    // 40 x 64 KiB = 2.5 MiB of content against a 256 KiB ceiling: ten times over, so a
    // walk that stops when it breaks and one that reads the tree and compares afterwards
    // are far apart in what they hold.
    const files = 40;
    const each = 64 * 1024;
    const cap = 256 * 1024;
    try fx.fill(files, each);

    // What reading the whole tree costs, measured on the same tree through the same
    // production function — this is the number the refusal must NOT reach. Taken first,
    // so it is an observation rather than a bound reasoned from the arena's growth rule.
    var full = try takeSnapshotCapped(gpa, fx.root, onlyTreeCap(std.math.maxInt(usize)), null);
    const full_capacity = full.arena.queryCapacity();
    try std.testing.expectEqual(@as(usize, files), full.entries.items.len);
    full.deinit();

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(cap), &diag),
    );

    // The ceiling was passed — otherwise the refusal is reporting something else.
    try std.testing.expect(diag.tree.reached > cap);

    // **This is the assertion the whole check exists for.** An implementation that sums
    // during the walk and compares once after it returns still refuses, still names the
    // reason, still emits the JSON — every acceptance leg stays green. What it cannot do
    // is hold less than the whole tree: `reached` equals `full_capacity` exactly. (It
    // reddens two more lines below as well, since its account is the whole tree rather
    // than a prefix; only this test fails, not three, and this is the line Zig stops at.)
    try std.testing.expect(diag.tree.reached < full_capacity);

    // The operator-visible half of the same fact: the account is a prefix.
    try std.testing.expect(diag.tree.entries < files);
    try std.testing.expect(diag.tree.entries > 0);

    // **The two counters pinned against each other, not just bounded.** Every file here
    // is the same size, so the product is exact — and a bound alone does not hold them:
    // review measured that deleting `charged = content.len` from the `.file` branch left
    // the whole suite green, because `0 < files * each` is true and the empty-tree test
    // below wants `content == 0` anyway. The operator-facing half of the refusal could
    // have been permanently zero with nothing noticing.
    try std.testing.expectEqual(diag.tree.entries * each, diag.tree.content);

    // Positive control on the same tree: above its footprint, the snapshot succeeds and
    // carries every entry. **It also pins "over, not at"** — the ceiling passed here is
    // `full_capacity` exactly, so tightening `charge`'s `reached <= caps.tree` to `<`
    // reddens this line. What no fixture can do is land `queryCapacity` on a *chosen*
    // value, because `ArenaAllocator` hands out whole nodes sized 1.5x their predecessor;
    // taking the boundary from the tree's own measured cost is the way around that, and
    // it is why this control is not the decoration it looks like.
    var ok = try takeSnapshotCapped(gpa, fx.root, onlyTreeCap(full_capacity), null);
    defer ok.deinit();
    try std.testing.expectEqual(@as(usize, files), ok.entries.items.len);
}

test "the tree ceiling charges directories too, which is the only entry kind with its own charge (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-dirs") orelse return error.SkipZigTest;
    defer fx.deinit();

    // Directories are charged inside the `.dir` branch, before it descends, rather than
    // by the shared charge at the end of the loop — the branch `continue`s past that one
    // so `seen` is not counted twice. **That makes the `.dir` charge the only one nothing
    // else can cover**, and first-look review measured that deleting it leaves every other
    // test in this file green while a tree of directories walks to completion holding
    // 174x the ceiling. A tree with no files at all is the shape that reaches it.
    try fx.fillDirs(500);

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(32 * 1024), &diag),
    );
    // No content anywhere, and it still refuses — as in the empty-files test below, but
    // through a different branch of `walk`.
    try std.testing.expectEqual(@as(u64, 0), diag.tree.content);
    // And it refused early rather than after walking the lot, which is what deleting the
    // charge would turn into.
    try std.testing.expect(diag.tree.entries < 500);
}

test "the tree ceiling counts what the snapshot holds, not the bytes it read (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-metric") orelse return error.SkipZigTest;
    defer fx.deinit();

    // Two thousand empty files: zero content bytes, and an arena carrying two thousand
    // `rel` strings, two thousand `Entry` values and the entry list's own growth.
    try fx.fill(2000, 0);

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(32 * 1024), &diag),
    );

    // **A ceiling that sums file content cannot produce this line.** Zero content read,
    // and the refusal fired anyway — which is the difference between capping the tree and
    // capping what holding the tree costs. Measured at scale on this shape: 50,000 empty
    // files hold 12,959,676 bytes against a content sum of zero.
    try std.testing.expectEqual(@as(u64, 0), diag.tree.content);
    try std.testing.expect(diag.tree.entries > 0);
    try std.testing.expect(diag.tree.reached > 32 * 1024);
}

/// A trace file of `n` bytes in a pid-unique directory, plus its cleanup. Built the
/// way the per-file cap's test builds its root (#28: the resolved parent, because
/// macOS `/tmp` is itself a link).
fn traceFixture(tag: []const u8, bytes: []const u8, path_out: []u8) ?[]const u8 {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return null);
    const path = std.fmt.bufPrint(path_out, "{s}/trace.bin", .{base}) catch unreachable;
    var fz: [contract.max_path]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return null;
    _ = posix.write(fd, bytes.ptr, bytes.len);
    _ = posix.close(fd);
    return path;
}

/// An allocator that refuses any single request over `ceiling` and passes the rest
/// through. `std.testing.FailingAllocator` cannot express this: its `alloc_index` only
/// advances on success, so a `fail_index` that catches the first request catches every
/// request after it too — which tests "nothing can be allocated", a different thing from
/// "this one large reservation could not be met".
const RefuseLargeAllocator = struct {
    backing: Allocator,
    ceiling: usize,

    fn allocator(self: *RefuseLargeAllocator) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(ctx: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (len > self.ceiling) return null;
        return self.backing.rawAlloc(len, a, ra);
    }
    fn resize(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (n > self.ceiling) return false;
        return self.backing.rawResize(m, a, n, ra);
    }
    fn remap(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (n > self.ceiling) return null;
        return self.backing.rawRemap(m, a, n, ra);
    }
    fn free(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(m, a, ra);
    }
};

test "a reservation that cannot be met does not relabel an oversized trace (#323)" {
    // #323 gave `readWhole` a reservation taken from the file's own length. This test is
    // about what happens when that reservation FAILS, and it is aimed at the call site
    // rather than the function: `readTraceCapped`'s catch collapses every error except
    // `FileTooLarge` into an empty `TraceInfo`, which the engine reads as
    // `no_shim_marker`. A reservation that returned `OutOfMemory` would therefore turn
    // "the trace is larger than this engine will read" into "the shim never initialised"
    // — the relabelling `max_trace_bytes`' own comment calls worse than having no cap.
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap-reserve", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-reserve-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }

    // Past a cap of 4 the reservation asks for `4 + one chunk`; the read loop's own
    // requests are a few hundred bytes. A ceiling between the two fails exactly the
    // reservation and nothing else, which is what separates "the reservation is a hint"
    // from "the reservation is load-bearing".
    var refuser: RefuseLargeAllocator = .{ .backing = std.testing.allocator, .ceiling = 16 * 1024 };
    var info = try readTraceCapped(refuser.allocator(), path, 4);
    defer info.deinit();

    // The answer is the cap's, not the empty read's — which is the whole point.
    try std.testing.expect(info.too_large);
    try std.testing.expect(!info.saw_shim_ready);

    // Positive control, same fixture and same allocator, under the cap: the read
    // completes. Without it, an allocator that broke every read would satisfy the line
    // above for the wrong reason — "nothing can be allocated at all" is a different
    // failure that would otherwise pass as correct here.
    var ok = try readTraceCapped(refuser.allocator(), path, 4096);
    defer ok.deinit();
    try std.testing.expect(!ok.too_large);
    try std.testing.expectEqual(@as(usize, 0), ok.ops.items.len);
}

test "an oversized trace says so, instead of collapsing into the empty read (#324)" {
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }

    // Over the cap: the flag is set and the size is the file's true length, read by
    // lseek rather than counted from the truncated read.
    var big = try readTraceCapped(gpa, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
    try std.testing.expectEqual(@as(?u64, 10), big.too_large_size);
    // What makes this a distinct answer rather than a relabelled one: the flag the
    // caller checks for "the shim never ran" is NOT set by a capped read. Were it the
    // only signal, this trace would refuse as `no_shim_marker`.
    try std.testing.expect(!big.saw_shim_ready);
    try std.testing.expect(!big.truncated);

    // At the cap exactly, no breach — the boundary is "over", not "at" (the per-file
    // cap's boundary, kept identical so the two caps cannot drift in that detail).
    var ok = try readTraceCapped(gpa, path, 10);
    defer ok.deinit();
    try std.testing.expect(!ok.too_large);
}

test "a cap breach and an unreadable trace are different observations (#324)" {
    const gpa = std.testing.allocator;

    // A trace that is not there at all: the empty TraceInfo, exactly as before this
    // change — the honest observation that the shim never wrote anything.
    var absent = try readTraceCapped(gpa, "/tmp/sideeye-no-such-trace-file-does-not-exist", 4);
    defer absent.deinit();
    try std.testing.expect(!absent.too_large);
    try std.testing.expect(absent.too_large_size == null);
    try std.testing.expect(!absent.saw_shim_ready);
    try std.testing.expectEqual(@as(usize, 0), absent.ops.items.len);

    // The contrast, from the same reader: a file that exists and breaks the cap does
    // set the flag. Without this leg the assertions above pass for an implementation
    // that never sets `too_large` at all.
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap-contrast", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-contrast-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }
    var big = try readTraceCapped(gpa, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
}

