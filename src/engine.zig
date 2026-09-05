//! The exploration engine: snapshot the state, run the target under the shim, kill it
//! at each operation in turn, and judge what is left behind.
//!
//! Every verdict this file produces has to survive one question: could it be wrong in
//! the direction of saying PASS when something was missed? The structural detectors
//! exist because of that question, and they run before any world is explored — if the
//! recording run is not trustworthy, exploring five hundred worlds built on it only
//! multiplies the untrustworthiness.
//!
//! Since #491 this file is the facade over its parts, which live beside it:
//!
//!   - `engine/trace.zig` owns trace reading, decoding, budgeting and process accounting;
//!     this file re-exports every public declaration of that file and holds none of its
//!     bodies.
//!   - `engine/snapshot.zig` owns `Entry` and `Snapshot`, their diff, their reconciliation
//!     against the trace, and the sorted-unique invariant the producers finalize through;
//!     this file re-exports every public declaration of that file and holds none of its
//!     bodies.
//!   - `engine/judge.zig` owns the classification (`classify`, `classifyWith`, `L0Plan`
//!     with its `PlannedFile` and `FileForm`) and the L0/L1 judges (`judgeL0`, `judgeL1`,
//!     `Violation`); this file re-exports every public declaration of that file and holds
//!     none of its bodies.
//!   - `engine/read.zig` holds `readWhole`, the one-file-into-an-arena read that the
//!     snapshot walk (following a link at the name) and the trace read (refusing one)
//!     share. It is beside both rather than inside either, because inside either it would
//!     be a cycle.
//!
//! A test near the end of this file walks the public declarations of each part and fails
//! if the facade drops one.
//!
//! What stays here: the walk that takes a snapshot and the caps on it (with the error set
//! and diagnostics the walk can fail with), the destructive restore and its root vets, the
//! corruption probe, and `WorldResult`. The first three are the last seam — one per change
//! (ADR 0047, 0048, 0049); where `WorldResult` belongs is that seam's call.

const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");
/// Read for the ancestor-probe entry below (#358); zero effect on a shipped build.
const build_options = @import("engine_build_options");

const Allocator = std.mem.Allocator;

const read = @import("engine/read.zig");
const trace = @import("engine/trace.zig");
const snapshot = @import("engine/snapshot.zig");
const judge = @import("engine/judge.zig");

// ---------------------------------------------------------------------------------
// The snapshot lives in `engine/snapshot.zig` (#491, ADR 0048). What follows is its
// public surface, re-exported so `main.zig` reaches it as `engine.*` and the walk and the
// restore below keep spelling `Snapshot`, `Entry` and `finalizeEntries` the way they always
// have (the judges take the four names they use from `snapshot.zig` directly, by private
// alias, since #491's third seam). The facade test near the end of this file
// walks `snapshot.zig`'s public declarations and fails if one is missing from this list.
pub const Entry = snapshot.Entry;
pub const OrderProblem = snapshot.OrderProblem;
pub const validateSortedUnique = snapshot.validateSortedUnique;
pub const Snapshot = snapshot.Snapshot;
pub const firstUnsupportedEntry = snapshot.firstUnsupportedEntry;
pub const Difference = snapshot.Difference;
pub const DiffCount = snapshot.DiffCount;
pub const diffSnapshots = snapshot.diffSnapshots;
pub const diffSnapshotsExcept = snapshot.diffSnapshotsExcept;
pub const Unaccounted = snapshot.Unaccounted;
pub const Reconciled = snapshot.Reconciled;
pub const Link = snapshot.Link;
pub const reconcile = snapshot.reconcile;
pub const collectLinks = snapshot.collectLinks;
pub const scratchMatches = snapshot.scratchMatches;
pub const finalizeEntries = snapshot.finalizeEntries;
pub const testSnapshot = snapshot.testSnapshot;
// ---------------------------------------------------------------------------------

/// `EntriesNotSortedUnique` means the snapshot came out of `walk` in a shape `find` cannot
/// search: out of order, or holding the same `rel` twice. Neither should be reachable — the
/// sort in `finalizeEntries` (`engine/snapshot.zig`) guarantees the first and a directory
/// traversal cannot produce the second — so
/// this is the check refusing rather than letting a binary search answer from a list that
/// does not satisfy its precondition (#262).
pub const SnapshotError = error{ OutOfMemory, ReadFailed, TooDeep, PathTooLong, ClassifyFailed, EntriesNotSortedUnique, FileTooLarge, TreeTooLarge };

/// Moved to `engine/read.zig` (#491); re-exported so the pin test below and every
/// caller keep their spelling.
pub const ReadWholeError = read.ReadWholeError;

/// Moved to `engine/trace.zig` (#491); re-exported for the same reason.
pub const TraceReadError = trace.TraceReadError;

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
/// **What the arena costs above the content, measured.** With `read.readWhole` reserving from
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
/// by four times this, plus `max_trace_bytes_total`. That last term said "the two trace
/// arenas" until #377 found three read sites and gave them a ceiling of their own — the
/// point of which is that this sentence no longer has to count them. The run that
/// refuses may hold more, for
/// the node-growth reason above, and then exits. Raising this value is not the safe
/// direction: here a refusal is the good outcome, and the alternative to refusing is the
/// unreported death above.
pub const max_state_tree_bytes: usize = 256 * 1024 * 1024;

/// Both ceilings, together, so a call site cannot supply one without the other.
///
/// **A tree can break both, and which one is reported depends on `readdir` order.** The
/// per-file cap wins for whatever entry the walk reaches first, because `read.readWhole` returns
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
                const content = read.readWhole(arena, full.ptr, ctx.caps.file, &size, .follow) catch |e| {
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
    "/usr",         "/etc",             "/bin",            "/sbin",              "/lib",             "/lib64",
    "/boot",        "/dev",             "/proc",           "/sys",               "/var/lib",         "/var/db",
    "/var/spool",
    // Linux resolves /var/run to /run and /var/lock to /run/lock, so the /var spellings
    // never arrive here; both are listed because a distribution that keeps them real
    // would send the other one. Same reason the /private entries below exist.
      "/var/run",         "/run",            "/System",            "/Library",         "/Applications",
    "/private/etc", "/private/var/lib", "/private/var/db", "/private/var/spool", "/private/var/run",
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
    "/tmp",         "/private/tmp",         "/var/tmp", "/private/var/tmp",
    "/var/folders", "/private/var/folders", "/home",    "/Users",
    "/Volumes",     "/mnt",                 "/media",   "/root",
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
/// captured at resolution time covers a replacement that happens **after** this look and
/// leaves a different pair behind, and since #338 that pair is threaded from here to the
/// open. Two things it still does not see: a mount that was already in place when this
/// function ran, because that is what this function approved; and a replacement that
/// inherits the vetted inode number after the original's last link is gone
/// (`posix.Identity`'s doc carries that one).
///
/// **The check-to-open window is closed now (#338, ADR 0037), and this function is half
/// of how.** It still resolves a name and compares strings, which is two syscalls away
/// from the open that follows. What it adds is the identity of the object it approved, and
/// `openRootDir` refuses any descriptor that is not that object. Not a second reading of
/// the name at open time — that was tried, and measured accepting the swap, because after
/// a rename-and-replace the descriptor and the name reach the same new directory.
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
/// now an open descriptor. **Done for the check-to-open half in #338 (ADR 0037),
/// in `openRootDir`.** The bind-mount half stays open and is not closable this way: a
/// mount established before the open is pinned wrong by a descriptor and agrees with
/// itself by device and inode, so both comparisons pass on it.
///
/// What the vet saw, and — when it saw something — which object that was.
///
/// The identity is the whole point (#338). "Vetted" can only mean "the object this
/// function looked at", so the object has to be named in a way that survives the pathname
/// being repointed afterwards. A device and inode pair does; a pathname does not.
///
/// `absent` is not a failure. A root that is simply gone is a state two callers below
/// recover from by creating it, and one of them then has to know that nothing was there.
const RootVet = union(enum) { identified: posix.Identity, absent };

fn assertRootResolvesToItself(root: []const u8) RestoreError!RootVet {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    // No separate symlink test. An earlier version asked `isSymlink` first, justified as
    // keeping two failures distinguishable — measured, deleting it left every test green,
    // because the comparison below already refuses a linked root by the only thing that
    // matters: it resolves somewhere else. The one case it could have added, a dangling
    // link, never reaches here — `main.zig` cannot resolve such a `--state` at all.
    var real_buf: [contract.max_path]u8 = undefined;
    const resolved = posix.realpath(root_z.ptr, &real_buf) orelse {
        if (std.c._errno().* == posix.ENOENT) return .absent; // nothing there to delete
        return error.UnsafeRoot; // cannot look: refuse rather than delete blind
    };
    if (!std.mem.eql(u8, std.mem.span(resolved), root)) return error.UnsafeRoot;
    // Which object was approved, not merely that the name approves of itself. `openRootDir`
    // compares the descriptor it ends up holding against this, and that comparison is what
    // closes the window between here and there.
    return .{ .identified = posix.identityOfPath(root_z.ptr) catch return error.UnsafeRoot };
}

/// What opening the destructive root found.
///
/// `absent` is a variant rather than an error because the two callers disagree about it:
/// `deleteTree` has nothing to delete and is done, while `freshDir` has already failed its
/// `mkdir`, so an absent root there means a missing parent — the silent no-op that flag
/// exists to remove. One `open`, two meanings, and neither may be assumed by the other.
const RootOpen = union(enum) { fd: c_int, absent };

/// Open a directory for the destructive walk, pinned by descriptor (#327), and refuse it
/// unless the descriptor and the pathname still reach the same object (#338).
///
/// Holding the descriptor is what closes the swap window: every delete below is relative
/// to the inode opened here, so replacing the *pathname* afterwards redirects nothing.
/// `O_NOFOLLOW` additionally refuses a root that is itself a link. `vet` closes the other
/// end — the window between the caller's vet and this open — by carrying the identity that
/// vet approved, so the descriptor has to be that object and not merely something wearing
/// that name.
///
/// The parameter is not optional on purpose. Every caller has to produce a `RootVet`, and
/// the only things that produce one are `assertRootResolvesToItself` and a `stat` taken
/// by a caller that has just created the root itself. Nobody can quietly opt out of the
/// comparison by passing nothing, which is the shape a fourth destructive entry point
/// would otherwise take — and the reason this function exists at all is that `opendir`
/// used to be called from several places with several different amounts of care.
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
fn openRootDir(root: []const u8, vet: RootVet) RestoreError!RootOpen {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    const fd = posix.open(
        root_z.ptr,
        posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC,
        @as(c_uint, 0),
    );
    if (fd >= 0) {
        // **The vet-to-open window (#338, ADR 0037).** The descriptor pins an inode for
        // its whole life; the pathname between the vet and here does not. So the caller
        // hands over the identity its vet approved, and the descriptor has to be that same
        // object or nothing happens.
        //
        // **Comparing the descriptor against what the name resolves to *now* does not
        // work, and was measured not working before this shape was written.** Move the
        // vetted directory aside inside the window and put another in its place: the open
        // reaches the new one and the name resolves to the new one, the two agree, and the
        // walk empties a tree nobody vetted. That comparison can only see a swap landing
        // in the sliver between the open and the stat — a window this function would be
        // creating itself.
        //
        // What stays open is a swap that happened *before* the vet, including a bind mount
        // established before it. The vet approves whatever was there when it looked, and
        // no comparison anchored to the vet can question the vet. `#338` says so in the
        // same words; ADR 0024's Alternatives claimed the device/inode pair would cover
        // it, and ADR 0037 records that correction.
        //
        // Both arms live here rather than at the three call sites. They were written there
        // first, one conditional each, which is the shape where the fourth caller forgets
        // one: the whole reason this function exists is that `opendir` used to be called
        // from several places with several different amounts of care.
        switch (vet) {
            .identified => |want| {
                const held = posix.identityOfFd(fd) catch {
                    _ = posix.close(fd);
                    return error.UnsafeRoot;
                };
                if (!held.eql(want)) {
                    _ = posix.close(fd);
                    return error.UnsafeRoot;
                }
            },
            // The vet found nothing and yet something is here, so it arrived after the vet
            // looked and nobody approved it. `freshDir` reaches this when its `mkdir` has
            // already failed; `corruptState` when the tree `restore` just built has gone.
            // `restore` is the one caller that legitimately creates the root, and it takes
            // a fresh identity after its `mkdir` rather than passing this stale `.absent`.
            .absent => {
                _ = posix.close(fd);
                return error.UnsafeRoot;
            },
        }
        return .{ .fd = fd };
    }
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
    // Reached only from tests — every production path goes through `restore`, `freshDir`
    // or `corruptState`, each of which runs the full vet. This one takes an identity of
    // its own instead. The name-resolution half of the vet demands the realpath'd spelling
    // and these callers pass `/tmp/...` literals; the identity half needs no such thing,
    // and it is the half `openRootDir` compares against. So the swap window is closed here
    // too and the name checks are not, which is the accurate statement and the reason this
    // is not a fourth production entry point.
    var vet_buf: [contract.max_path]u8 = undefined;
    const vet_z = std.fmt.bufPrintZ(&vet_buf, "{s}", .{root}) catch return error.PathTooLong;
    const vet: RootVet = if (posix.identityOfPath(vet_z.ptr)) |id| .{ .identified = id } else |_| .absent;
    switch (try openRootDir(root, vet)) {
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
    // The `mkdir` above is this function's only legitimate creator, and it has already
    // failed. So if the vet finds nothing here, nothing that appears afterwards can be
    // legitimate -- see the `.fd` arm below (#338).
    const vet = try assertRootResolvesToItself(root);
    switch (try openRootDir(root, vet)) {
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

/// `restore`'s root creation, and the identity the descriptor will be held to (#338).
///
/// Separated from `restore` so the state it refuses can be reached by a test. That state
/// lives between two calls `restore` makes back to back — the vet, then this `mkdir` — and
/// no input to `restore` can place anything in between. Handed the vet's verdict directly,
/// it is three ordinary cases.
///
/// Unlike `freshDir`, `restore` *is* the legitimate creator when the root is gone: the
/// first run of every world arrives with nothing there, so a vet that saw nothing is
/// ordinary and the `mkdir` that follows must succeed. `EEXIST` on that path says a
/// directory arrived between the two calls. It is someone else's, and `O_NOFOLLOW` will
/// not refuse it, because it is a perfectly real directory.
///
/// Every other `mkdir` failure is left alone and falls through to `openRootDir`'s `.absent`
/// arm, which still answers `CreateFailed`. A missing parent keeps the diagnosis it has
/// always had rather than being reported as a swap.
///
/// The identity comes *after* the `mkdir` for the same reason: on a first run the `mkdir`
/// is what put the directory there, and the vet above has nothing to name. One `stat`
/// rather than a second full vet — the name's resolution was judged above, and a swap to a
/// symlink since then is refused by `O_NOFOLLOW` in the open, not here.
fn createRoot(root_z: [*:0]const u8, vet: RootVet) RestoreError!RootVet {
    switch (vet) {
        // The vet saw the root and approved it, so the identity to hold the descriptor to
        // is **that** one. Re-reading the name here would undo the whole change: a swap
        // between the vet and this point makes `mkdir` say `EEXIST` exactly as it would
        // have anyway, and a fresh reading then returns the intruder, which then agrees
        // with the intruder at the open. That shape was in the tree until review found it,
        // and it passed every test, because the swap test drove `openRootDir` directly and
        // never came through here.
        .identified => {
            _ = posix.mkdir(root_z, 0o755); // EEXIST is the expected answer and says nothing
            return vet;
        },
        // Nothing was there, so this call is the legitimate creator and the identity can
        // only be read afterwards.
        .absent => {
            if (posix.mkdir(root_z, 0o755) != 0) {
                // Something is there that was not there a moment ago. It is not ours, and
                // `O_NOFOLLOW` will not refuse it for being real.
                if (std.c._errno().* == posix.EEXIST) return error.UnsafeRoot;
                // Any other failure keeps the diagnosis it has always had: `openRootDir`
                // finds nothing and the caller answers `CreateFailed`, which is what a
                // missing parent has always produced.
                return .absent;
            }
            return if (posix.identityOfPath(root_z)) |id| .{ .identified = id } else |_| .absent;
        },
    }
}

/// Write one recorded file into the tree, relative to the held root descriptor. The
/// single write path `restore` and `corruptState` share.
///
/// `O_NOFOLLOW` because the two halves of this file used to answer a planted symlink
/// differently (#446): `deleteTreeAt` descends with the flag and refuses a link where a
/// directory was, while the write opened without it and agreed to write *through* one —
/// sending the recorded bytes to whatever it pointed at, outside the state directory.
/// Measured on a directory descriptor with a link at the entry name: without the flag the
/// write succeeds through the link, with it the open is refused and the file outside is
/// unchanged byte for byte.
///
/// **Final component only.** The interior of a multi-component `e.rel` is still resolved
/// by name and is left open rather than argued safe — the reasoning, and why closing it
/// needs resolution the kernel enforces, is in CHANGELOG and BUILDLOG under #446.
///
/// A partial write is a failure, not a short success: returning here would start the next
/// world from a truncated file, and judgeL0 would then report a hybrid — a counterexample
/// manufactured by the tool rather than found in the target. read.readWhole distinguishes
/// these cases; the loop this replaced did not.
fn writeFileEntryAt(dirfd: c_int, rel_z: [*:0]const u8, bytes: []const u8) RestoreError!void {
    const wfd = posix.openat(dirfd, rel_z, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0o644));
    if (wfd < 0) return error.CreateFailed;
    defer _ = posix.close(wfd);
    var off: usize = 0;
    while (off < bytes.len) {
        const w = posix.write(wfd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return error.CreateFailed;
        off += @intCast(w);
    }
}

pub fn restore(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    const vet = try assertRootResolvesToItself(root);

    // Created *before* the descriptor is taken, not after the delete where it used to sit.
    // Once the root is held open, a `mkdir` on the pathname makes a different directory
    // than the one the walk and every creation below are pinned to, and each `mkdirat`
    // would then run against an unlinked inode. Before the open there is nothing to
    // disagree with: a root that is simply gone is recreated here, as it always was.
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    const after = try createRoot(root_z.ptr, vet);

    // One descriptor for the whole call: the delete and the rebuild are pinned to the same
    // inode, so a swap between them redirects neither. What it does not pin is the interior
    // — `e.rel` is a multi-component path, and its intermediate components are still
    // resolved by name below. Those directories were made by this loop moments earlier.
    const fd = switch (try openRootDir(root, after)) {
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
            .file => try writeFileEntryAt(fd, rel_z.ptr, e.content),
            // Unreachable from any explored path since #5's refusal fires on every
            // snapshot before restore runs — kept loud, not silent: an `.other` that
            // somehow arrives here would otherwise become a tool-manufactured
            // `missing` in the next world's judgement, the exact shape #5 demoted.
            .other, .missing => return error.CreateFailed,
        }
    }
}

// ---------------------------------------------------------------------------------
// The trace reader lives in `engine/trace.zig` (#491, ADR 0047). What follows is its
// public surface, re-exported so `main.zig` reaches it as `engine.*` (the reconcile tests
// that spell `Op` moved to `engine/snapshot.zig` with `reconcile`, and take it from
// `trace.zig` directly). A test near the end of this file walks `trace.zig`'s public
// declarations and fails if one is missing from this list, so adding one there without
// adding it here does not stay quiet.
pub const Op = trace.Op;
pub const TraceInfo = trace.TraceInfo;
pub const max_trace_bytes = trace.max_trace_bytes;
pub const max_trace_bytes_total = trace.max_trace_bytes_total;
pub const TraceBudget = trace.TraceBudget;
pub const unboundedBudget = trace.unboundedBudget;
pub const readTrace = trace.readTrace;
pub const readTraceCapped = trace.readTraceCapped;
// ---------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------
// The judges live in `engine/judge.zig` (#491, ADR 0049). What follows is their public
// surface, re-exported so `main.zig` reaches them as `engine.*` and `WorldResult` below
// keeps naming `Violation` the way it always has. The facade test near the end of this
// file walks `judge.zig`'s public declarations and fails if one is missing from this list.
pub const Violation = judge.Violation;
pub const FileForm = judge.FileForm;
pub const PlannedFile = judge.PlannedFile;
pub const L0Plan = judge.L0Plan;
pub const classify = judge.classify;
pub const classifyWith = judge.classifyWith;
pub const judgeL0 = judge.judgeL0;
pub const judgeL1 = judge.judgeL1;
// ---------------------------------------------------------------------------------
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
    const vet = try assertRootResolvesToItself(root);
    // Through the same held descriptor as `restore`, for the same reason: writing by
    // pathname after the root has been vetted leaves the vet's window open, and this
    // function's own comment above says relying on the neighbour is how a guard ends up
    // covering one entry point and not the next.
    const fd = switch (try openRootDir(root, vet)) {
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
        // Loud on failure, per `writeFileEntryAt`: a file that could not be overwritten
        // leaves the state intact, and the run would then report `checker_not_falsified`
        // — "the checker accepted a state whose every file had been overwritten with
        // junk" — about a file this function never touched, blaming the caller's checker
        // for the engine's own failed write.
        try writeFileEntryAt(fd, rel_z.ptr, corruption_probe);
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

/// The roots the relation below is held over (#359).
///
/// Written as a corpus rather than as a list of asserts because the relation is what is
/// being pinned, not the individual answers: a root added here is checked in both
/// directions and against both predicates without anyone remembering to write four lines.
/// Twenty-two of the thirty-nine also appear in the hand-written vet tests above, three
/// more only in the denylist definitions themselves — being on a list is not being
/// tested — and the remaining fourteen appear nowhere in this file. The two mutations that motivate
/// this test — the outward read on one side only, the depth rule on one side only — are
/// both already killed by those hand-written asserts, so a corpus built only from their
/// roots would have added nothing. What it adds is the fourteen nobody thought to list,
/// one of which (a `~` in a component) is what the attribution mutation uses.
const root_relation_corpus = [_][]const u8{
    // Depth-1 paths in neither list: the cell where the two predicates legitimately differ.
    "/work",                        "/opt",               "/repo",                                  "/srv",             "/nix",               "/cores",
    "/data",                        "/scratch",
    // Denied outright, by tree or exactly.
              "/usr",                                   "/etc/myapp",       "/tmp",               "/private/tmp",
    "/Users",                       "/home",              "/var/lib/x",                             "/run/lock/x",      "/root",              "/Volumes",
    // Ancestors of denied entries — the outward read's own cell.
    "/var",                         "/private",           "/private/var",
    // Accepted by both: the ordinary case, in several shapes.
                              "/opt/myapp/state", "/srv/myapp/state",   "/work/state",
    "/Users/someone/scratch/state", "/var/library/state", "/private/var/folders/lm/abcdef/T/state", "/optimism/state",
    // Unusual bytes in a component, and depth beyond anything else here.
     "/work/~cache/state", "/opt/a.b/c-d/state",
    "/srv/x y/state",               "/a/b/c/d/e/f/g/h",
    // Refused by the shape checks rather than by either list.
      "/work/state/",                           "relative/path",    "",                   "/",
    // Accepted by both, and the reason both vets say the caller hands over the resolved
    // spelling: the checks are lexical, so these pass here and mean something else on disk.
    "//var",                        "/opt/../var",        "/work/.",
};

fn namingAccepts(root: []const u8) bool {
    assertSafeNamingRoot(root) catch return false;
    return true;
}

fn destructiveAccepts(root: []const u8) bool {
    assertSafeRoot(root) catch return false;
    return true;
}

// The relation between the two vets, held over the corpus (#359, ADR 0046).
//
// The denylists live in this file, next to the destructive path, and #359 asked whether
// they should move somewhere neither consumer owns. ADR 0046 declines the move: the drift
// the address argument protects against did happen once (#329 gave the outward read to
// the naming side alone) and what closed it was extraction into a shared helper, not
// relocation — and a new file would let the same asymmetry be written inside it. So what
// is pinned here is the relation, which nothing pinned before.
//
// Three assertions, and the third is what keeps the first two from being vacuous. A
// mutation that adds a check to the naming side alone would satisfy the implication by
// emptying its antecedent; requiring every cell of the corpus to be populated means the
// corpus has to keep separating the predicates for the test to pass at all.
test "the three read error sets hold what their readers can raise (#376)" {
    // The counts, held the way `RestoreError`'s are (`main.zig`): a test that says it
    // covered a whole set has to notice when the set grows. It also pins the split
    // itself — merging the sets back, or widening one to the other, reddens here rather
    // than nowhere. The membership is argued in each set's doc comment; this is the
    // arithmetic behind those arguments. Since #491 the three sets live in three files
    // (`SnapshotError` here, `ReadWholeError` in `engine/read.zig`, `TraceReadError` in
    // `engine/trace.zig`) and are reached through the re-exports above; the split is
    // still pinned in this one place, on purpose.
    const t = std.testing;
    try t.expectEqual(@as(usize, 8), @typeInfo(SnapshotError).error_set.?.len);
    try t.expectEqual(@as(usize, 3), @typeInfo(ReadWholeError).error_set.?.len);
    try t.expectEqual(@as(usize, 2), @typeInfo(TraceReadError).error_set.?.len);
}

test "the naming vet refuses a subset of what the destructive vet refuses (#359)" {
    const t = std.testing;

    var naming_only_accepts: usize = 0; // naming yes, destructive no — the depth rule's cell
    var both_accept: usize = 0;
    var both_refuse: usize = 0;

    for (root_relation_corpus) |root| {
        const naming = namingAccepts(root);
        const destructive = destructiveAccepts(root);
        var slashes: usize = 0;
        for (root) |ch| {
            if (ch == '/') slashes += 1;
        }

        // 0. The relation as an equality, which is what the property sentence says: the
        //    destructive vet accepts exactly what the naming vet accepts and is deep
        //    enough. Assertions 1 and 2 decompose it into the two directions and name
        //    which one broke; this line is what makes them an equality rather than a
        //    containment. Without it a destructive-side-only check confined to depth-1
        //    roots passes everything, because the cell it empties is still filled by the
        //    other seven.
        if (destructive != (naming and slashes >= 2)) {
            std.debug.print(
                "#359: {s} — naming {}, destructive {}, slashes {d}: the vets differ by something other than depth\n",
                .{ root, naming, destructive, slashes },
            );
            return error.VetsDifferBySomethingOtherThanDepth;
        }

        // 1. Containment: everything the naming vet refuses, the destructive vet refuses.
        //    A check added to the naming side that the destructive side does not get
        //    lands here.
        if (!naming and destructive) {
            std.debug.print("#359: naming refuses {s} but the destructive vet accepts it\n", .{root});
            return error.NamingRefusalNotCoveredByDestructive;
        }

        // 2. The one direction they may differ in is the depth rule, and nothing else.
        //    A check added to the destructive side alone lands here.
        if (naming and !destructive) {
            if (slashes >= 2) {
                std.debug.print("#359: the destructive vet refuses {s} for a reason that is not depth\n", .{root});
                return error.DestructiveRefusalIsNotTheDepthRule;
            }
            naming_only_accepts += 1;
        } else if (naming and destructive) {
            both_accept += 1;
        } else {
            both_refuse += 1;
        }
    }

    // 3. The corpus separates them. Without this, a mutation can satisfy 1 and 2 by
    //    making one of the cells unreachable — which is exactly what adding the depth
    //    rule to the naming side does.
    try t.expect(naming_only_accepts > 0);
    try t.expect(both_accept > 0);
    try t.expect(both_refuse > 0);
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
    // Resolves to itself: accepted, and it names what it approved. The verdict is not
    // discarded here because every destructive caller now branches on it (#338): a vet
    // that answered `.absent` for a root plainly present would let `restore` read its own
    // legitimate `mkdir` as a swap and refuse every first run.
    try std.testing.expect((try assertRootResolvesToItself(good)) == .identified);

    // Now the swap. The link points at a sibling, which is enough — what is refused is
    // "this root no longer resolves to itself", not "the target is dangerous".
    try std.testing.expect(posix.mkdir(other_zs.ptr, 0o755) == 0);
    try std.testing.expect(posix.rmdir(good_zs.ptr) == 0);
    try std.testing.expect(posix.symlink(other_zs.ptr, good_zs.ptr) == 0);

    try std.testing.expectError(error.UnsafeRoot, assertRootResolvesToItself(good));
    // Control: the sibling the link points at is itself fine, so the refusal above is
    // about the swap and not about anything in this directory.
    try std.testing.expect((try assertRootResolvesToItself(other)) == .identified);

    // A root that is simply absent is not a swap: deleteTree already returns silently
    // for it, and refusing here would turn a tolerated state into a SETUP ERROR.
    try std.testing.expect(posix.unlink(good_zs.ptr) == 0);
    try std.testing.expect((try assertRootResolvesToItself(good)) == .absent);
}

test "openRootDir refuses a root swapped between the vet and the open (#338)" {
    // The window #338 named: `assertRootResolvesToItself` looks at a name, `openRootDir`
    // opens that name, and the two are separate syscalls. Deterministic, no threads — the
    // swap is performed between two calls this test makes itself, which is the whole
    // reason the comparison is anchored to the vet rather than to a second look at the name.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vetwin-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    // The base goes back through realpath: on macOS /tmp is itself a link, and the vet
    // compares spellings.
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    var bb: [contract.max_path]u8 = undefined;
    const moved_z = std.fmt.bufPrintZ(&bb, "{s}/moved", .{rparent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(moved_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    const vet = try assertRootResolvesToItself(root);
    try std.testing.expect(vet == .identified);

    // Control first: nothing swapped, the open is accepted. Without this the refusal below
    // is satisfied by a guard that refuses everything.
    switch (try openRootDir(root, vet)) {
        .fd => |fd| _ = posix.close(fd),
        .absent => return error.TestUnexpectedResult,
    }

    // Now the swap, inside the window: the vetted directory is moved aside and another put
    // at the same name.
    try std.testing.expect(posix.rename(root_z.ptr, moved_z.ptr) == 0);
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    try std.testing.expectError(error.UnsafeRoot, openRootDir(root, vet));

    // And why the baseline has to come from the vet. The design this replaced compared the
    // descriptor against whatever the *name* resolved to at open time; after the swap those
    // two are the same new directory, so that comparison agrees and the walk would empty a
    // tree nobody vetted. Asserted rather than argued, because it is the only thing that
    // distinguishes the shipped shape from the one that was measured accepting this.
    const fd2 = posix.open(root_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fd2 >= 0);
    defer _ = posix.close(fd2);
    const held = try posix.identityOfFd(fd2);
    const named = try posix.identityOfPath(root_z.ptr);
    try std.testing.expect(held.eql(named)); // the rejected comparison passes here
    try std.testing.expect(!held.eql(vet.identified)); // the shipped one does not
}

test "openRootDir refuses a root that appeared after the vet found nothing (#338)" {
    // `freshDir` reaches this with its `mkdir` already failed, and `corruptState` when the
    // tree `restore` built has gone: in both, nothing between the vet and the open is
    // entitled to create the root, so something being there means someone else made it.
    // `restore` is the exception and takes a fresh identity after its own `mkdir`.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vetabs-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    // The vet looks at a root that is not there.
    try std.testing.expect((try assertRootResolvesToItself(root)) == .absent);
    // Inside the window, one appears.
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    try std.testing.expectError(error.UnsafeRoot, openRootDir(root, .absent));

    // Control: the same directory, opened against a vet that did see it, is accepted — so
    // the refusal above is about the `.absent` verdict and not about this directory.
    const seen = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };
    switch (try openRootDir(root, seen)) {
        .fd => |fd| _ = posix.close(fd),
        .absent => return error.TestUnexpectedResult,
    }
}

test "createRoot keeps the vetted identity across a swap, rather than re-reading the name (#338)" {
    // The hole review found, and the reason it survived: the swap test above drives
    // `openRootDir` directly, so it never came through here. Inside `restore` the order is
    // vet, `createRoot`, open — and if `createRoot` re-reads the name, a swap landing
    // before it makes `mkdir` answer the `EEXIST` it would have answered anyway, the fresh
    // reading returns the intruder, and the open then agrees with the intruder.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-keepid-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var ab: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&ab, "{s}/state", .{parent}) catch unreachable;
    var bb: [contract.max_path]u8 = undefined;
    const moved_z = std.fmt.bufPrintZ(&bb, "{s}/moved", .{parent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(moved_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    const approved = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };

    // Control: no swap, and the identity comes back unchanged — so the assertion below is
    // about what `createRoot` does with the name, not about it returning a constant.
    const quiet = try createRoot(root_z.ptr, approved);
    try std.testing.expect(quiet.identified.eql(approved.identified));

    // The swap, before `createRoot` runs.
    try std.testing.expect(posix.rename(root_z.ptr, moved_z.ptr) == 0);
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    const kept = try createRoot(root_z.ptr, approved);
    // It must still name what the vet approved, not what the name reaches now.
    try std.testing.expect(kept.identified.eql(approved.identified));
    const intruder = try posix.identityOfPath(root_z.ptr);
    try std.testing.expect(!intruder.eql(approved.identified)); // the swap really happened
    // ...and the open then refuses, which is the outcome `restore` depends on.
    try std.testing.expectError(error.UnsafeRoot, openRootDir(std.mem.span(root_z.ptr), kept));
}

test "a vetted root that vanishes leaves createRoot's own directory unvetted (#338)" {
    // The third state, which neither swap test reaches: the vet identified a directory and
    // then it was removed rather than replaced, so `createRoot`'s `mkdir` succeeds and makes
    // one of its own. What holds everywhere is that the vetted identity is kept rather than
    // refreshed. Whether the open then refuses does not, and finding that out is what this
    // test is really for -- an earlier version asserted the refusal unconditionally, passed
    // here, and went red on Linux in CI.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vanish-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    const approved = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };

    // It goes away, and `createRoot` makes a new one.
    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    const kept = try createRoot(root_z.ptr, approved);
    try std.testing.expect(kept.identified.eql(approved.identified)); // still the vetted one
    try std.testing.expect((try posix.kindOfPathNoFollow(root_z.ptr)) == .dir); // and it did create

    // Whether the open refuses depends on the one thing the pair cannot see. Measured
    // 2026-09-01: overlayfs under Linux hands the new directory the number the old one had,
    // on the very next `mkdir`, three runs of three; APFS does not, three of three. So the
    // reuse case is not exotic on Linux -- it is what remove-then-recreate does by default.
    //
    // What it lets through is narrow, and worth writing beside the test rather than only in
    // the ADR. `O_NOFOLLOW` means the walk always reaches a real directory *at the vetted
    // path*, so a swap cannot redirect it elsewhere; the harm of one is that something worth
    // keeping ends up at that path. A directory *moved* there brings its own inode and is
    // refused. Only an object the filesystem created after the vetted one was unlinked can
    // inherit the number, and that object is a new, empty directory.
    //
    // Asserting the refusal where it is deliverable, and naming the world otherwise, rather
    // than asserting a portable refusal that is not.
    const now = try posix.identityOfPath(root_z.ptr);
    if (!now.eql(approved.identified)) {
        try std.testing.expectError(error.UnsafeRoot, openRootDir(root, kept));
    }
}

test "createRoot refuses a root that arrived after the vet found nothing (#338)" {
    // The one rule in this change that no input to `restore` can exercise: it sits between
    // the vet and the `mkdir`, two calls `restore` makes back to back. Driving `createRoot`
    // directly is what makes the three states reachable, and the mutation survey said so —
    // with the rule inline, deleting it left every test green.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-mkwin-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var ab: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&ab, "{s}/state", .{parent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    // First run: the vet saw nothing and nothing is there. The `mkdir` succeeds and names
    // what it made. This is the ordinary path, asserted first so the refusal below cannot
    // be satisfied by a rule that refuses whenever the vet was empty.
    const first = try createRoot(root_z.ptr, .absent);
    try std.testing.expect(first == .identified);
    try std.testing.expect((try posix.kindOfPathNoFollow(root_z.ptr)) == .dir);

    // The hostile case: the vet still says it saw nothing, but a directory is there now, so
    // it arrived in between and nobody approved it. `O_NOFOLLOW` would not refuse it —
    // it is a real directory — and without this rule the identity taken afterwards would
    // be the intruder's, agreeing with itself all the way down.
    try std.testing.expectError(error.UnsafeRoot, createRoot(root_z.ptr, .absent));

    // Ordinary second run: the vet identified the root, so `EEXIST` is expected and the
    // identity comes back unchanged.
    const seen = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };
    const again = try createRoot(root_z.ptr, seen);
    try std.testing.expect(again == .identified);
    try std.testing.expect(again.identified.eql(seen.identified));
}

test "restore still creates a root that is not there yet (#338)" {
    // The over-strictness detector. #338 makes three destructive paths refuse a root they
    // did not vet, and the first run of every world arrives here with no root at all: the
    // vet answers `.absent`, `restore`'s own `mkdir` puts the directory there, and the
    // identity it holds the descriptor to has to be taken after that `mkdir` rather than
    // before it. An implementation that refuses whenever the vet found nothing passes
    // every swap test above and breaks every ordinary run.
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-firstrun-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a", .kind = .file, .content = "x" });

    // Nothing there at all: the state the vet reports as `.absent`.
    try std.testing.expect((try assertRootResolvesToItself(root)) == .absent);
    try restore(snap, root);

    // And it did the work rather than merely not refusing.
    var eb: [contract.max_path]u8 = undefined;
    const entry_z = try joinZ(&eb, root, "a");
    try std.testing.expect((try posix.kindOfPathNoFollow(entry_z.ptr)) == .file);
    _ = posix.unlink(entry_z.ptr);

    // The second run is the other half: the root now exists, the vet identifies it, and
    // the `mkdir` fails with EEXIST as it always has.
    try std.testing.expect((try assertRootResolvesToItself(root)) == .identified);
    try restore(snap, root);
    try std.testing.expect((try posix.kindOfPathNoFollow(entry_z.ptr)) == .file);
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

test "the rebuild refuses to write through a symlink at an entry name (#446)" {
    // The asymmetry this closes: `deleteTreeAt` descends with `O_NOFOLLOW` and refuses a
    // symlink where a directory was; the write side opened without it and agreed to write
    // through one. Same file, same threat model, opposite answers.
    //
    // Aimed at `writeFileEntryAt` rather than at `restore`, because `restore` empties the
    // tree immediately above its rebuild: a link planted before the call is deleted by the
    // walk, and one planted *between* the delete and the write is a race this test cannot
    // stage. What is measured here is the flag's effect on the write, which is what the
    // change is. The `corruptState` leg below sits one level higher — that is a `pub fn`
    // and the production entry point `main.zig` calls — but it is still called directly
    // rather than reached through its own call site, which runs it after `restore` and so
    // cannot be driven into a planted link either.
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    const root = fx.init("writeentry") orelse return error.SkipZigTest;
    defer fx.deinit();
    const outside = try fx.sibling("outside");

    // A sentinel outside the state directory, with content — not just existence. A test
    // that only asked whether the file was still there would pass against a write that
    // followed the link and truncated it.
    const keep = "keep-me-intact\n";
    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    try TreeFixture.writeAt(sentinel_z.ptr, keep);

    var rz: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{root}) catch unreachable;
    const fd = posix.open(root_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fd >= 0);
    defer _ = posix.close(fd);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Control first: a real entry name is written, so the refusal below is about the link
    // and not about this directory, these flags, or these bytes.
    try writeFileEntryAt(fd, "real", "recorded bytes");
    var real_buf: [contract.max_path]u8 = undefined;
    const real_z = try joinZ(&real_buf, root, "real");
    try std.testing.expectEqualStrings("recorded bytes", try read.readWhole(arena, real_z.ptr, 4096, null, .follow));

    // The link: what a resident racer could leave at an entry name.
    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = try joinZ(&lbuf, root, "planted");
    try std.testing.expect(posix.symlink(sentinel_z.ptr, link_z.ptr) == 0);

    try std.testing.expectError(error.CreateFailed, writeFileEntryAt(fd, "planted", "recorded bytes"));

    // The bytes outside are untouched — the whole point. `expectEqualStrings` rather than
    // a length or an existence check: a followed write truncates first and would leave an
    // empty file that still exists.
    try std.testing.expectEqualStrings(keep, try read.readWhole(arena, sentinel_z.ptr, 4096, null, .follow));
    // And the link is still a link: the refusal did not replace it with a regular file.
    try std.testing.expectEqual(posix.Kind.symlink, try posix.kindOfPathNoFollow(link_z.ptr));
}

test "corruptState refuses a planted symlink rather than corrupting what it points at (#446)" {
    // The same write path, reached through the other of its two callers. Called directly
    // for the reason the test above records: `corruptState`'s one call site runs it
    // immediately after `restore`, which empties the tree, so no link planted from outside
    // survives to be met there.
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    const root = fx.init("corrupt-nofollow") orelse return error.SkipZigTest;
    defer fx.deinit();
    const outside = try fx.sibling("outside");

    const keep = "not-a-probe\n";
    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    try TreeFixture.writeAt(sentinel_z.ptr, keep);

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    // A real entry before the planted one, as the positive control: without it, the two
    // assertions below are also satisfied by a `corruptState` that refused before reaching
    // any write at all — `openRootDir` answering `.absent`, say. The probe landing in this
    // file is what says the write path was entered.
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "real", .kind = .file, .content = "recorded" });
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "planted", .kind = .file, .content = "recorded" });
    // Created rather than left to `O_CREAT`, so the control overwrites a file the way the
    // production path does: `restore` has always put the recorded tree back by this point.
    var real_buf: [contract.max_path]u8 = undefined;
    const real_z = try joinZ(&real_buf, root, "real");
    try TreeFixture.writeAt(real_z.ptr, "recorded");

    // The snapshot says `planted` is a file; the tree holds a link pointing outside. That
    // is exactly the disagreement a racer creates between the recording and the rewrite.
    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = try joinZ(&lbuf, root, "planted");
    try std.testing.expect(posix.symlink(sentinel_z.ptr, link_z.ptr) == 0);

    try std.testing.expectError(error.CreateFailed, corruptState(snap, root));

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The control: the entry that is a real file was corrupted, so the refusal above is
    // the write path saying no to the link, not this function stopping short of it.
    try std.testing.expectEqualStrings(corruption_probe, try read.readWhole(arena, real_z.ptr, 4096, null, .follow));
    try std.testing.expectEqualStrings(keep, try read.readWhole(arena, sentinel_z.ptr, 4096, null, .follow));
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
    outside_buf: [contract.max_path]u8 = undefined,
    outside: []const u8 = &.{},

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

    /// A directory beside `root`, under the same parent — where a test puts something the
    /// tree under test must not be able to reach. Torn down with the rest, and before the
    /// parent, which would otherwise refuse to go and leave the whole fixture behind.
    ///
    /// **One per fixture.** There is a single slot, so a second call would overwrite the
    /// first and leave that directory behind for the rest of the machine's life; the
    /// assert makes that a test failure rather than a slow leak.
    fn sibling(self: *TreeFixture, name: []const u8) ![]const u8 {
        std.debug.assert(self.outside.len == 0);
        const base = std.fs.path.dirname(self.root) orelse return error.SkipZigTest;
        self.outside = std.fmt.bufPrint(&self.outside_buf, "{s}/{s}", .{ base, name }) catch unreachable;
        var oz: [contract.max_path]u8 = undefined;
        const outside_z = std.fmt.bufPrintZ(&oz, "{s}", .{self.outside}) catch unreachable;
        if (posix.mkdir(outside_z.ptr, 0o755) != 0) return error.SkipZigTest;
        return self.outside;
    }

    fn deinit(self: *TreeFixture) void {
        deleteTree(self.root) catch {};
        var rz: [contract.max_path]u8 = undefined;
        const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{self.root}) catch unreachable;
        _ = posix.rmdir(root_z.ptr);
        if (self.outside.len != 0) {
            deleteTree(self.outside) catch {};
            var oz: [contract.max_path]u8 = undefined;
            const outside_z = std.fmt.bufPrintZ(&oz, "{s}", .{self.outside}) catch unreachable;
            _ = posix.rmdir(outside_z.ptr);
        }
        var pz: [contract.max_path]u8 = undefined;
        const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{std.mem.sliceTo(&self.parent_z, 0)}) catch unreachable;
        _ = posix.rmdir(parent_z.ptr);
    }

    /// Put `bytes` at `path_z`. Extracted at the third copy inside the two `#446` tests,
    /// not across the file — a dozen or so hand-rolled open/write/close sequences remain
    /// in older tests here and were left alone. `fill` cannot serve either way, because
    /// its names and contents are fixed for the size tests it exists for.
    ///
    /// A short write fails the test rather than skipping it. `fill` and `fillDirs` skip on
    /// everything, which is right for bulk setup, and wrong here: callers use this to
    /// place the bytes an assertion is about — a positive control that quietly turned into
    /// a skip would leave the guard unmeasured and the suite green. The open keeps
    /// `SkipZigTest`, because that one is about whether the environment can host the test
    /// at all, which is the same question `init` and `sibling` answer.
    fn writeAt(path_z: [*:0]const u8, bytes: []const u8) !void {
        const fd = posix.open(path_z, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        if (fd < 0) return error.SkipZigTest;
        defer _ = posix.close(fd);
        try std.testing.expectEqual(@as(isize, @intCast(bytes.len)), posix.write(fd, bytes.ptr, bytes.len));
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

test {
    // The files under `engine/` cannot be named in build.zig's test_sources — as a root,
    // their `../posix.zig` falls outside the module path — so their tests reach this
    // root, and main's, only through references from tests that a root does collect.
    // Some such references still exist (main's own tests reach the trace surface), and
    // some have gone: the tests that used to build snapshots through `testSnapshot` left
    // with the judges, and no test remaining in this file calls it. That is the point of
    // this block — the reach is unconditional rather than a property of which test happens
    // to mention what (#491), and a seam that takes the last mention of a part with it
    // does not quietly stop collecting that part's tests. No precedent in this repo before
    // #491; the reason it is here is the one build.zig records for test_sources.
    std.testing.refAllDecls(trace);
    std.testing.refAllDecls(read);
    std.testing.refAllDecls(snapshot);
    std.testing.refAllDecls(judge);
}

/// Whether this file declares `name` publicly. Test-only: the facade walk below is the one
/// caller, and it needs the public list rather than `@hasDecl` (see there).
fn facadeExports(comptime name: []const u8) bool {
    // A linear scan of this file's public declarations, byte-comparing each name, is more
    // than the default comptime budget of 1000 backward branches (measured: it stopped
    // there). The bound is generous; the scan is test-only and runs once per part name.
    @setEvalBranchQuota(100_000);
    for (std.meta.declarations(@This())) |d| {
        if (std.mem.eql(u8, d.name, name)) return true;
    }
    return false;
}

test "the facade re-exports every public declaration of each part (#491)" {
    // Walked, not listed. A list of names written out here would go quiet the day one
    // more public declaration appeared in a part; this walks what each part declares.
    // Some of those names are referenced by nothing outside this file (`readTrace`,
    // `unboundedBudget`, `Reconciled`, `OrderProblem`), so forgetting a re-export would
    // otherwise leave every build, every test and every acceptance leg green with the
    // module map at the top of this file false.
    //
    // The parts are listed here by hand, in two arrays kept in step so the compile error
    // can name the part: a further part is a new plan, and that plan adds an entry to each.
    inline for (.{ "trace", "snapshot", "judge" }, .{ trace, snapshot, judge }) |name, part| {
        inline for (comptime std.meta.declarations(part)) |d| {
            // `std.meta.declarations(@This())` rather than `@hasDecl`: from inside this
            // file `@hasDecl` is true for a private declaration too, so a
            // `const Reconciled = snapshot.Reconciled;` without `pub` would pass it and the
            // identity check both, while `main.zig` could not spell `engine.Reconciled`.
            // The public declaration list is what the module map promises.
            if (!comptime facadeExports(d.name)) {
                @compileError("engine.zig does not re-export " ++ name ++ "." ++ d.name);
            }
            // Identity for types and functions; for a `usize` ceiling or an error set this
            // is a comparison of value or structure, and a hand-copied
            // `pub const max_trace_bytes = 64 * 1024 * 1024;` would pass it. The walk above
            // is what holds the list complete; this line holds what it can.
            try std.testing.expect(@field(@This(), d.name) == @field(part, d.name));
        }
    }
}
