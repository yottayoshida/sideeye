const std = @import("std");
const posix = @import("posix.zig");

const read = @import("engine/read.zig");
const trace = @import("engine/trace.zig");
const snapshot = @import("engine/snapshot.zig");
const judge = @import("engine/judge.zig");
const state_fs = @import("engine/state_fs.zig");

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
pub const namedByMutation = snapshot.namedByMutation;
pub const scratchMatches = snapshot.scratchMatches;
pub const finalizeEntries = snapshot.finalizeEntries;
pub const testSnapshot = snapshot.testSnapshot;

pub const SnapshotError = state_fs.SnapshotError;
pub const max_depth = state_fs.max_depth;
pub const max_state_file_bytes = state_fs.max_state_file_bytes;
pub const max_state_tree_bytes = state_fs.max_state_tree_bytes;
pub const SnapshotCaps = state_fs.SnapshotCaps;
pub const FileTooLargeDiag = state_fs.FileTooLargeDiag;
pub const EntryRel = state_fs.EntryRel;
pub const EntryDiag = state_fs.EntryDiag;
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

pub const ReadWholeError = read.ReadWholeError;

pub const TraceReadError = trace.TraceReadError;

pub const Op = trace.Op;
pub const TraceInfo = trace.TraceInfo;
pub const max_trace_bytes = trace.max_trace_bytes;
pub const max_trace_bytes_total = trace.max_trace_bytes_total;
pub const TraceBudget = trace.TraceBudget;
pub const unboundedBudget = trace.unboundedBudget;
pub const readTrace = trace.readTrace;
pub const readTraceCapped = trace.readTraceCapped;

pub const Violation = judge.Violation;
pub const FileForm = judge.FileForm;
pub const PlannedFile = judge.PlannedFile;
pub const L0Plan = judge.L0Plan;
pub const classify = judge.classify;
pub const classifyWith = judge.classifyWith;
pub const judgeL0 = judge.judgeL0;
pub const judgeL1 = judge.judgeL1;
pub const WorldResult = struct {
    k: u32,
    term: posix.Term,
    landed: bool,
    violation: ?Violation,
};

test "the three read error sets hold what their readers can raise (#376)" {
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
    std.testing.refAllDecls(trace);
    std.testing.refAllDecls(read);
    std.testing.refAllDecls(snapshot);
    std.testing.refAllDecls(judge);
    std.testing.refAllDecls(state_fs);
}

fn facadeExports(comptime name: []const u8) bool {
    @setEvalBranchQuota(100_000);
    for (std.meta.declarations(@This())) |d| {
        if (std.mem.eql(u8, d.name, name)) return true;
    }
    return false;
}

test "the facade re-exports every public declaration of each part (#491)" {
    // Walked, not listed. A list of names written out here would go quiet the day one
    // more public declaration appeared in a part; this walks what each part declares.
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
