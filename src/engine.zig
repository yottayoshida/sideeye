//! The exploration engine: snapshot the state, run the target under the shim, kill it
//! at each operation in turn, and judge what is left behind.
//!
//! Every verdict the engine produces has to survive one question: could it be wrong in
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
//!   - `engine/state_fs.zig` owns the snapshot walk with its caps and the destructive side
//!     — `restore`, `freshDir`, `corruptState` and the root vets they run first; this file
//!     re-exports every public declaration of that file and holds none of its bodies.
//!   - `engine/read.zig` holds `readWhole`, the one-file-into-an-arena read that the
//!     snapshot walk (following a link at the name) and the trace read (refusing one)
//!     share. It is beside both rather than inside either, because inside either it would
//!     be a cycle.
//!
//! A test near the end of this file walks the public declarations of each part and fails
//! if the facade drops one.
//!
//! What stays here: `WorldResult`, the orchestrator's account of one explored world, which
//! `main.zig`'s world loop produces and no part returns (ADR 0050); the test that pins the
//! three read error sets together, kept where all three are visible without importing
//! three parts; and the checks on the facade itself.

const std = @import("std");
const posix = @import("posix.zig");

const read = @import("engine/read.zig");
const trace = @import("engine/trace.zig");
const snapshot = @import("engine/snapshot.zig");
const judge = @import("engine/judge.zig");
const state_fs = @import("engine/state_fs.zig");

// ---------------------------------------------------------------------------------
// The snapshot lives in `engine/snapshot.zig` (#491, ADR 0048). What follows is its
// public surface, re-exported so `main.zig` reaches it as `engine.*`. The parts that use
// these names — the judges and the state tree — import `snapshot.zig` directly and take
// them by private alias, so nothing in this file spells them but this block and the module
// map above. The facade test near the end of this file walks `snapshot.zig`'s public
// declarations and fails if one is missing from this list.
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

// ---------------------------------------------------------------------------------
// The walk, the restore and the corruption probe live in `engine/state_fs.zig` (#491,
// ADR 0050). What follows is their public surface, re-exported so `main.zig` and
// `mcp.zig` reach them as `engine.*`. The facade test near the end of this file walks
// `state_fs.zig`'s public declarations and fails if one is missing from this list.
pub const SnapshotError = state_fs.SnapshotError;
pub const max_depth = state_fs.max_depth;
pub const max_state_file_bytes = state_fs.max_state_file_bytes;
pub const max_state_tree_bytes = state_fs.max_state_tree_bytes;
pub const SnapshotCaps = state_fs.SnapshotCaps;
pub const FileTooLargeDiag = state_fs.FileTooLargeDiag;
pub const TreeTooLargeDiag = state_fs.TreeTooLargeDiag;
pub const SnapshotDiag = state_fs.SnapshotDiag;
pub const takeSnapshot = state_fs.takeSnapshot;
pub const takeSnapshotCapped = state_fs.takeSnapshotCapped;
pub const RestoreError = state_fs.RestoreError;
pub const assertSafeRoot = state_fs.assertSafeRoot;
pub const assertSafeNamingRoot = state_fs.assertSafeNamingRoot;
pub const freshDir = state_fs.freshDir;
pub const restore = state_fs.restore;
pub const corruption_probe = state_fs.corruption_probe;
pub const corruption_probe_target = state_fs.corruption_probe_target;
pub const corruptState = state_fs.corruptState;
pub const countCorruptible = state_fs.countCorruptible;
// ---------------------------------------------------------------------------------

/// Moved to `engine/read.zig` (#491); re-exported so the pin test below and every
/// caller keep their spelling.
pub const ReadWholeError = read.ReadWholeError;

/// Moved to `engine/trace.zig` (#491); re-exported for the same reason.
pub const TraceReadError = trace.TraceReadError;

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
pub const WorldResult = struct {
    k: u32,
    term: posix.Term,
    landed: bool,
    violation: ?Violation,
};

test "the three read error sets hold what their readers can raise (#376)" {
    // The counts, held the way `RestoreError`'s are (`main.zig`): a test that says it
    // covered a whole set has to notice when the set grows. It also pins the split
    // itself — merging the sets back, or widening one to the other, reddens here rather
    // than nowhere. The membership is argued in each set's doc comment; this is the
    // arithmetic behind those arguments. Since #491 the three sets live in three files
    // (`SnapshotError` in `engine/state_fs.zig`, `ReadWholeError` in `engine/read.zig`,
    // `TraceReadError` in `engine/trace.zig`) and are reached through the re-exports
    // above; the split is still pinned in this one place, on purpose — the facade is the
    // one file where all three are visible without importing three parts.
    const t = std.testing;
    try t.expectEqual(@as(usize, 8), @typeInfo(SnapshotError).error_set.?.len);
    try t.expectEqual(@as(usize, 3), @typeInfo(ReadWholeError).error_set.?.len);
    try t.expectEqual(@as(usize, 2), @typeInfo(TraceReadError).error_set.?.len);
}

test {
    // The files under `engine/` cannot be named in build.zig's test_sources — as a root,
    // their `../posix.zig` falls outside the module path — so their tests reach this
    // root, and main's, only through references from tests that a root does collect.
    // After the last seam of #491 the two named tests left in this file reach little:
    // one pins three error sets, the other walks every part's declarations — so the parts
    // are still reached, by a test whose job is something else. `posix.zig`'s tests are
    // not: they were collected here because this file's own tests called `posix.*`, and
    // now nothing here does. This block is what reaches them, through the parts' bodies.
    // That is the point of it: the reach is unconditional rather than a property of which
    // test happens to mention what, and a seam that takes the last mention of a part with
    // it does not quietly stop collecting that part's tests. No precedent in this repo before #491;
    // the reason it is here is the one build.zig records for test_sources.
    std.testing.refAllDecls(trace);
    std.testing.refAllDecls(read);
    std.testing.refAllDecls(snapshot);
    std.testing.refAllDecls(judge);
    std.testing.refAllDecls(state_fs);
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
    // `unboundedBudget`, `Reconciled`, `OrderProblem`, `FileForm`, `corruption_probe_target`),
    // so forgetting a re-export would otherwise leave every build, every test and every
    // acceptance leg green with the module map at the top of this file false.
    //
    // The parts are listed here by hand, in two arrays kept in step so the compile error
    // can name the part: a further part is a new plan, and that plan adds an entry to each.
    inline for (
        .{ "trace", "snapshot", "judge", "state_fs" },
        .{ trace, snapshot, judge, state_fs },
    ) |name, part| {
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
