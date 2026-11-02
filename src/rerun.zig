const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const containment = @import("containment.zig");
const files = @import("files.zig");
const refuse = @import("refuse.zig");
const pinning = @import("pinning.zig");
const defang = @import("defang.zig");

const unknown = refuse.unknown;
const setupError = refuse.setupError;

pub const Context = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    op_argv: []const []const u8,
    state_abs: []const u8,
    state_alt: []const u8,
    out_path: []const u8,
    cwd: ?[]const u8,
    budget_ms: ?u64,
    scratch: []const []const u8,
    preload_var: []const u8,
};

pub const End = struct {
    term: posix.Term,
    snap: engine.Snapshot,
};

pub const References = struct {
    before: End,
    after: End,
};

pub const Declared = struct {
    ctx: Context,
    refs: References,
};

pub const observed = "the operation, run again from the crash state with no shim, ended as neither reference run";
pub const subject = "(named by the rerun invariant, not by path)";

pub const Verdict = struct {
    mismatch: ?[]const u8,
    leftovers: usize,
};

// The pin library alone, never the shim: what is asked is how the operation ends on its own, and
// the pin is apparatus the define declared, so a pinned operation is re-run pinned.
fn preload() []const u8 {
    const both = pinning.preload orelse return "";
    return both[0 .. std.mem.indexOfScalar(u8, both, ':') orelse both.len];
}

fn runFrom(ctx: Context, from: engine.Snapshot) End {
    engine.restore(from, ctx.state_abs) catch |e| refuse.restoreFailure(e, "could not restore a state to run the operation again from", ctx.state_abs);
    files.removeFile(ctx.out_path);
    var cg = containment.spawn(false);
    const cg_ptr: ?*posix.CgroupSpawn = if (cg) |*c| c else null;
    const term = posix.runChildCaptureWorld(ctx.gpa, ctx.op_argv, &.{
        .{ "TOY_STATE", ctx.state_abs },
        .{ contract.env.state_dir, ctx.state_abs },
        .{ contract.env.state_dir_alt, ctx.state_alt },
        .{ contract.env.trace_path, "" },
        .{ contract.env.kill_at, "" },
        .{ contract.env.kill_group, "" },
        .{ contract.env.run_cgroup, "" },
        .{ contract.env.kill_cgroup, "" },
        .{ contract.env.kill_aside, "" },
        .{ contract.env.pin_seed, pinning.seed_hex },
        .{ contract.env.pin_claims, pinning.claimsFor(ctx.arena) },
        .{ ctx.preload_var, preload() },
    }, .{ .path = ctx.out_path, .stderr_too = true, .exclusive = true }, ctx.budget_ms, ctx.cwd, cg_ptr) catch |e| switch (e) {
        error.TimedOut => unknown(.child_timed_out, "the operation, run again from a state for the rerun invariant, was still running after the --world-timeout budget expired; it was sent SIGKILL", .raise_world_timeout),
        else => |se| refuse.spawnFailure(se, refuse.run_phase, "could not run the operation again for the rerun invariant"),
    };
    if (cg) |c| if (c.joined and !c.stopped)
        unknown(.child_process_detected, "a process the operation started when run again for the rerun invariant could not be stopped, so the state it left may still be changing", .environment);
    const snap = refuse.snapshotOrRefuse(ctx.gpa, ctx.state_abs, "could not snapshot the state the operation left when run again");
    var again = refuse.snapshotOrRefuse(ctx.gpa, ctx.state_abs, "could not snapshot the state the operation left when run again");
    defer again.deinit();
    var one: [1]engine.Difference = undefined;
    if (!engine.diffSnapshots(snap, again, &one).equal())
        unknown(.state_not_quiescent, "the state changed between two samples taken after the operation was run again for the rerun invariant: something it started is still writing", .quiesce);
    return .{ .term = term, .snap = snap };
}

// The leftovers it returns are not compared, only counted: a temporary file a crash left and the
// next run never touched is what a correct program leaves too, and comparing it would fail every
// target that writes through a temporary name.
fn endsAs(ctx: Context, run: End, ref: End, crashed: ?engine.Snapshot, initial: engine.Snapshot) ?usize {
    if (!std.meta.eql(run.term, ref.term)) return null;
    const buf = ctx.gpa.alloc(engine.Difference, run.snap.entries.items.len + ref.snap.entries.items.len) catch setupError(.environment, "out of memory");
    defer ctx.gpa.free(buf);
    const count = engine.diffSnapshotsExcept(run.snap, ref.snap, buf, ctx.scratch);
    var left: usize = 0;
    for (buf[0..count.stored]) |d| {
        if (d.how != .only_in_first) return null;
        const e = run.snap.find(d.rel).?;
        const c = (crashed orelse return null).find(d.rel) orelse return null;
        if (initial.find(d.rel) != null or c.kind != e.kind or !std.mem.eql(u8, c.content, e.content)) return null;
        left += 1;
    }
    return left;
}

fn termText(arena: std.mem.Allocator, t: posix.Term) []const u8 {
    return switch (t) {
        .exited => |c| std.fmt.allocPrint(arena, "exited {d}", .{c}) catch "exited",
        .signaled => |s| std.fmt.allocPrint(arena, "was killed by signal {d}", .{s}) catch "was killed by a signal",
        .unknown => "did not exit normally",
    };
}

fn against(ctx: Context, a: engine.Snapshot, b: engine.Snapshot, which: []const u8) []const u8 {
    var one: [1]engine.Difference = undefined;
    const count = engine.diffSnapshotsExcept(a, b, &one, ctx.scratch);
    if (count.equal()) return std.fmt.allocPrint(ctx.arena, "the same state as the run {s}", .{which}) catch "the same state";
    const how = switch (one[0].how) {
        .only_in_first => "which that run did not leave",
        .only_in_second => "missing, which that run left",
        .kind_differs => "a different kind of entry",
        .content_differs => "different bytes",
    };
    return std.fmt.allocPrint(ctx.arena, "a state that differs from the run {s} at {s} ({s})", .{ which, defang.textShown(ctx.arena, one[0].rel), how }) catch "a different state";
}

pub fn prepare(ctx: Context, initial: engine.Snapshot) References {
    const before = runFrom(ctx, initial);
    // Before the restore that follows: a special file there would fail it as a rewrite, not as the entry it is.
    refuse.refuseUnsupportedEntry(ctx.arena, before.snap, "left by the operation run with no shim for the rerun invariant");
    var again = runFrom(ctx, initial);
    defer again.snap.deinit();
    if (endsAs(ctx, again, before, null, initial) == null)
        unknown(.baseline_run_failed, std.fmt.allocPrint(
            ctx.arena,
            "the rerun invariant needs the operation to end the same way twice from the state the define starts from, run with no shim, and it did not: the first run {s}, the second {s} and left {s}",
            .{ termText(ctx.arena, before.term), termText(ctx.arena, again.term), against(ctx, again.snap, before.snap, "before it") },
        ) catch "the operation, run twice from the starting state with no shim, ended differently", .second_run_diverged);
    return .{ .before = before, .after = runFrom(ctx, before.snap) };
}

pub fn judge(d: Declared, crashed: engine.Snapshot, initial: engine.Snapshot) Verdict {
    var run = runFrom(d.ctx, crashed);
    defer run.snap.deinit();
    if (endsAs(d.ctx, run, d.refs.before, crashed, initial) orelse endsAs(d.ctx, run, d.refs.after, crashed, initial)) |left|
        return .{ .mismatch = null, .leftovers = left };
    return .{
        .mismatch = std.fmt.allocPrint(
            d.ctx.arena,
            "the operation, run again from this crash state with no shim, {s} and left {s} and {s}; the run from the state before {s}, and the run after it {s}",
            .{ termText(d.ctx.arena, run.term), against(d.ctx, run.snap, d.refs.before.snap, "from the state before"), against(d.ctx, run.snap, d.refs.after.snap, "after it"), termText(d.ctx.arena, d.refs.before.term), termText(d.ctx.arena, d.refs.after.term) },
        ) catch "the operation, run again from this crash state, ended as neither reference run",
        .leftovers = 0,
    };
}

pub fn note(arena: std.mem.Allocator, worlds: u32, failed: u32, leftovers: usize) []const u8 {
    return std.fmt.allocPrint(arena, "the operation run again with no shim in {d} world(s); {d} of them ended as neither the run from the state before nor the run after it; {d} path(s) a crash left and the run did not touch were counted, not compared", .{ worlds, failed, leftovers }) catch "the operation run again in each world";
}

test "a run ends as a reference when only paths the crash left and it did not touch differ, and not otherwise" {
    const gpa = std.testing.allocator;
    const ctx: Context = .{ .gpa = gpa, .arena = undefined, .op_argv = &.{}, .state_abs = "", .state_alt = "", .out_path = "", .cwd = null, .budget_ms = null, .scratch = &.{"cache"}, .preload_var = "" };
    var initial = try engine.testSnapshot(gpa, &.{.{ "key", "v1" }});
    defer initial.deinit();
    var crashed = try engine.testSnapshot(gpa, &.{ .{ "key", "v1" }, .{ "key.Xa1", "v2" } });
    defer crashed.deinit();
    var ref = try engine.testSnapshot(gpa, &.{.{ "key", "v2" }});
    defer ref.deinit();
    const done: posix.Term = .{ .exited = 0 };
    const reference: End = .{ .term = done, .snap = ref };

    var left_alone = try engine.testSnapshot(gpa, &.{ .{ "cache", "x" }, .{ "key", "v2" }, .{ "key.Xa1", "v2" } });
    defer left_alone.deinit();
    try std.testing.expectEqual(@as(?usize, 1), endsAs(ctx, .{ .term = done, .snap = left_alone }, reference, crashed, initial));
    try std.testing.expectEqual(@as(?usize, null), endsAs(ctx, .{ .term = .{ .exited = 1 }, .snap = left_alone }, reference, crashed, initial));

    var rewritten = try engine.testSnapshot(gpa, &.{ .{ "key", "v2" }, .{ "key.Xa1", "v3" } });
    defer rewritten.deinit();
    try std.testing.expectEqual(@as(?usize, null), endsAs(ctx, .{ .term = done, .snap = rewritten }, reference, crashed, initial));

    var other = try engine.testSnapshot(gpa, &.{.{ "key", "v1" }});
    defer other.deinit();
    try std.testing.expectEqual(@as(?usize, null), endsAs(ctx, .{ .term = done, .snap = other }, reference, crashed, initial));
    try std.testing.expectEqual(@as(?usize, null), endsAs(ctx, .{ .term = done, .snap = left_alone }, reference, null, initial));
}
