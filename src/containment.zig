const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine_build_options = @import("engine_build_options");
const posix = @import("posix.zig");
const engine = @import("engine.zig");
const refuse = @import("refuse.zig");

pub fn spawn(world: bool) ?posix.CgroupSpawn {
    if (engine_build_options.no_cgroup) return null;
    const home = posix.cgroupHome() orelse return null;
    return posix.CgroupSpawn.init(home, world);
}

/// empty. Empty rather than unset for the reason `seq_base` is pinned: a value left in the
/// operator's shell must not tell a shim it was contained.
pub fn runName(cg: ?*const posix.CgroupSpawn) []const u8 {
    return if (cg) |c| c.relPath() else "";
}

pub fn killName(cg: ?*const posix.CgroupSpawn) []const u8 {
    const c = cg orelse return "";
    return if (c.world) c.killPath() else "";
}

pub fn asideName(cg: ?*const posix.CgroupSpawn) []const u8 {
    const c = cg orelse return "";
    return if (c.world) c.asidePath() else "";
}

/// world armed to die at its crash point). A world's `cgroup.kill` is not asked for: an image
/// that reaches the crash point without it cannot kill, records that, and `killCameBack` refuses
/// the world — asking here too added only the race `cut_by_kill` is about (review). A run the
/// watch finds anything in is refused by the watch, later.
pub fn holds(cg: ?*const posix.CgroupSpawn, trace: *const engine.TraceInfo, cut_by_kill: bool) bool {
    const c = cg orelse return false;
    return c.joined and trace.cgroupAnswered(cut_by_kill);
}

pub fn refuseDetach(arena: std.mem.Allocator, cg: ?*const posix.CgroupSpawn, where: []const u8) noreturn {
    const can_contain = !engine_build_options.no_cgroup and posix.cgroupHome() != null;
    const f = detachFinding(arena, cg, where, builtin.os.tag == .linux, can_contain);
    refuse.unknown(f.reason, f.detail, f.next);
}

pub fn detachFinding(arena: std.mem.Allocator, cg: ?*const posix.CgroupSpawn, where: []const u8, linux: bool, can_contain: bool) Finding {
    const lead = "a process left the containment group (setsid/setpgid)";
    if (!linux) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "{s}{s}; this platform gives the engine no cgroup to stop it with, so the engine cannot claim to have stopped it", .{ lead, where }) catch lead,
        .next = .class_wall,
    };
    const joined = if (cg) |c| c.joined else false;
    if (!joined and !can_contain) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "{s}{s}, and the engine could not give this run a cgroup of its own, so it cannot claim to have stopped it. Run the engine where it can make cgroups under its own and move processes into them — a writable cgroup v2 delegated to its user, or root over a writable cgroup v2 (a default container mounts it read-only) — and a process that leaves the group is stopped with the run's cgroup and judged", .{ lead, where }) catch lead,
        .next = .environment,
    };
    if (!joined) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "{s}{s}, and this run did not get a cgroup although the engine can make them here, so the engine cannot claim to have stopped it", .{ lead, where }) catch lead,
        .next = .retry_then_report,
    };
    return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "{s}{s}, and not every process that announced itself said it was inside the run's cgroup before it went on, so the engine cannot claim to have stopped it", .{ lead, where }) catch lead,
        .next = .class_wall,
    };
}

pub const Finding = struct {
    reason: contract.UnknownReason,
    detail: []const u8,
    next: contract.NextStep,
};

/// Refuse a contained run whose cgroup did not hold it. Called once the run's trace has been
/// read and every refusal the run already had has been asked.
pub fn afterRun(arena: std.mem.Allocator, cg: *const posix.CgroupSpawn, trace: *const engine.TraceInfo, where: []const u8, lingering_counts: bool) void {
    if (runFinding(arena, cg, trace, where, lingering_counts, posix.processState)) |f|
        refuse.unknown(f.reason, f.detail, f.next);
}

pub fn runFinding(
    arena: std.mem.Allocator,
    cg: *const posix.CgroupSpawn,
    trace: *const engine.TraceInfo,
    where: []const u8,
    lingering_counts: bool,
    stateOf: *const fn (u32) ?u8,
) ?Finding {
    if (!cg.joined) return null;

    if (!cg.stopped) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "the run's cgroup could not be stopped{s}: {d} ms after its cgroup.kill was written it still held a live process, so what touches the state from here is unaccounted for", .{ where, posix.world_kill_grace_ms }) catch "the run's cgroup could not be stopped",
        .next = .environment,
    };

    if (trace.cgroup_outside) |op| return outsideFinding(arena, op, where);

    // Every process the trace names, and whether it wrote a kill point. Derived from the
    // records rather than kept beside them in the reader, where a count and a list answering
    // one question could disagree.
    var named: std.AutoHashMapUnmanaged(u32, bool) = .empty;
    for (trace.ops.items) |op| {
        const slot = named.getOrPut(arena, op.pid) catch return outOfMemory();
        if (!slot.found_existing) slot.value_ptr.* = false;
        if (op.class.isKillPoint()) slot.value_ptr.* = true;
    }

    if (lingering_counts) {
        for (cg.lingering[0..cg.lingering_len]) |pid| {
            if (named.get(pid) orelse false) return .{
                .reason = .child_process_detected,
                .detail = std.fmt.allocPrint(arena, "a process that wrote the state directory (pid {d}) was still running when the run's direct child exited{s}; stopping the run's cgroup cut it short, so the state it left is not one the run finished", .{ pid, where }) catch "a process that wrote the state directory was still running when the run's direct child exited",
                .next = .class_wall,
            };
        }
        if (cg.lingering_more) return .{
            .reason = .child_process_detected,
            .detail = std.fmt.allocPrint(arena, "more processes than the engine reads ({d}) were still in the run's cgroup when its direct child exited{s}, so whether one of them had written the state directory is unknown", .{ cg.lingering.len, where }) catch "more processes than the engine reads were still in the run's cgroup when its direct child exited",
            .next = .class_wall,
        };
    }

    var pids = named.keyIterator();
    while (pids.next()) |pid| {
        if (survivor(arena, pid.*, where, stateOf)) |f| return f;
    }
    for (cg.lingering[0..cg.lingering_len]) |pid| {
        if (survivor(arena, pid, where, stateOf)) |f| return f;
    }
    return null;
}

fn outsideFinding(arena: std.mem.Allocator, op: engine.Op, where: []const u8) Finding {
    if (std.mem.eql(u8, op.aux, contract.cgroup_aux.unreadable)) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "a process of the run (pid {d}) could not read where it stands against the run's cgroup{s} (/proc/self/cgroup would not open, or held no cgroup v2 line), so nothing says the kills that end a run reach it", .{ op.pid, where }) catch "a process of the run could not read where it stands against the run's cgroup",
        .next = .environment,
    };
    return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "a process of the run (pid {d}) reported itself outside the run's cgroup{s}: it was moved out of it or born outside it, and neither the crash-point kill nor the engine's cleanup reaches a process there", .{ op.pid, where }) catch "a process of the run reported itself outside the run's cgroup",
        .next = .class_wall,
    };
}

fn survivor(arena: std.mem.Allocator, pid: u32, where: []const u8, stateOf: *const fn (u32) ?u8) ?Finding {
    const state = stateOf(pid) orelse return null;
    if (state == 'Z' or state == 'X') return null;
    return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "a process of the run (pid {d}, state {c}) was still alive after the run's cgroup was stopped{s}: it had left the cgroup, so the kills that end a run did not reach it", .{ pid, state, where }) catch "a process of the run was still alive after the run's cgroup was stopped",
        .next = .class_wall,
    };
}

fn outOfMemory() Finding {
    return .{ .reason = .child_process_detected, .detail = "out of memory while checking the run's cgroup; the run is refused rather than left unchecked", .next = .retry_then_report };
}

/// **The exception to "after every refusal"**, and it has to be: the shim that writes
/// `cgroup:kill-returned` or `cgroup:outside` at the crash point then exits rather than fall
/// back to a group kill, so the world ends with an exit status and the loop's next refusal is
/// "a world that should have been killed exited on its own", filed as sideeye's defect. The
/// record says what actually happened, and only a contained world can carry it, so answering
/// first renames nothing an uncontained world would have met. Called in front of that refusal
/// and only where it would fire.
pub fn killCameBack(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) void {
    if (killFinding(arena, trace, k)) |f| refuse.unknown(f.reason, f.detail, f.next);
}

pub fn killFinding(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) ?Finding {
    if (trace.cgroup_kill_returned) |op| return .{
        .reason = .kill_did_not_land,
        .detail = std.fmt.allocPrint(arena, "the crash point's write to the run's cgroup.kill came back (pid {d}, before operation {d}): the kill did not take the run, so the world did not die where it was asked to", .{ op.pid, k }) catch "the crash point's write to the run's cgroup.kill came back",
        .next = .environment,
    };
    if (trace.cgroup_outside) |op|
        return outsideFinding(arena, op, std.fmt.allocPrint(arena, " in an explored world that exited instead of dying before operation {d}", .{k}) catch " in an explored world");
    return null;
}

pub fn pastCrashPoint(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) void {
    if (pastFinding(arena, trace, k)) |f| refuse.unknown(f.reason, f.detail, f.next);
}

pub fn pastFinding(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) ?Finding {
    if (trace.cgroup_kill_alone) |op| return .{
        .reason = .kill_did_not_land,
        .detail = std.fmt.allocPrint(arena, "the crash point before operation {d} could not step aside out of the cgroup it was killing (pid {d}), so the kill was the cgroup's alone: a process that had left the run's cgroup without leaving its process group was not stopped there", .{ k, op.pid }) catch "a crash point killed with the run's cgroup alone",
        .next = .environment,
    };
    if (trace.kill_point_count < k) return null;
    return .{
        .reason = .kill_did_not_land,
        .detail = std.fmt.allocPrint(arena, "a world asked to die before operation {d} holds a record numbered {d}: an operation ran at or past the crash point, so the crashed state is not the one the crash point stands for", .{ k, trace.kill_point_count }) catch "a world holds a record numbered at or past its crash point",
        .next = .class_wall,
    };
}

const t = std.testing;

fn fakeState(comptime answer: ?u8) *const fn (u32) ?u8 {
    return &struct {
        fn f(_: u32) ?u8 {
            return answer;
        }
    }.f;
}

fn testTrace(arena: std.mem.Allocator, ops: []const engine.Op) !engine.TraceInfo {
    var info: engine.TraceInfo = .{ .arena = std.heap.ArenaAllocator.init(t.allocator), .ops = .empty };
    try info.ops.appendSlice(arena, ops);
    return info;
}

fn record(class: contract.OpClass, seq: u32, pid: u32) engine.Op {
    return .{ .class = class, .seq = seq, .pid = pid, .tid = pid, .path = "/tmp/s/a", .aux = "" };
}

fn joinedCgroup() posix.CgroupSpawn {
    var cg = posix.CgroupSpawn.init(.{ .dir = "/nonexistent-cgroup-home", .rel = "/" }, true) orelse unreachable;
    cg.joined = true;
    cg.stopped = true;
    return cg;
}

test "a contained run that emptied, where nothing it named survived, is let through — and each way it can fail is named (v17, #559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    var trace = try testTrace(a, &.{ record(.shim_ready, 0, 40), record(.write, 1, 41), record(.rename, 2, 40) });
    defer trace.deinit();

    var cg = joinedCgroup();
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState(null)) == null);
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('Z')) == null);
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('X')) == null);

    const alive = runFinding(a, &cg, &trace, " in an explored world", true, fakeState('S')) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.child_process_detected, alive.reason);
    try t.expect(std.mem.indexOf(u8, alive.detail, "still alive after the run's cgroup was stopped in an explored world") != null);
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('?')) != null);

    cg.stopped = false;
    const stuck = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.NextStep.environment, stuck.next);
    cg.stopped = true;

    cg.joined = false;
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('S')) == null);
}

test "a writer still in the cgroup when the direct child exited refuses, a silent helper does not, and a killed world's teardown is not evidence (v17, #559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    var trace = try testTrace(a, &.{ record(.shim_ready, 0, 40), record(.shim_ready, 0, 41), record(.write, 1, 41), record(.shim_ready, 0, 42) });
    defer trace.deinit();
    var cg = joinedCgroup();

    cg.lingering[0] = 41;
    cg.lingering_len = 1;
    const cut = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, cut.detail, "pid 41") != null);
    try t.expect(std.mem.indexOf(u8, cut.detail, "cut it short") != null);
    try t.expect(runFinding(a, &cg, &trace, "", false, fakeState(null)) == null);

    cg.lingering[0] = 42;
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState(null)) == null);

    cg.lingering_more = true;
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState(null)) != null);
}

test "a shim outside the run's cgroup refuses the run, and at the crash point it is named before the world's exit is (v17, #559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    var trace = try testTrace(a, &.{record(.shim_ready, 0, 40)});
    defer trace.deinit();
    var cg = joinedCgroup();

    try t.expect(killFinding(a, &trace, 3) == null);
    trace.cgroup_outside = record(.cgroup, 3, 43);
    const outside = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, outside.detail, "pid 43") != null);
    const at_kill = killFinding(a, &trace, 3) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.child_process_detected, at_kill.reason);
    try t.expectEqual(contract.NextStep.class_wall, at_kill.next);

    var unreadable = record(.cgroup, 0, 44);
    unreadable.aux = contract.cgroup_aux.unreadable;
    trace.cgroup_outside = unreadable;
    const unread = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.NextStep.environment, unread.next);
    try t.expect(std.mem.indexOf(u8, unread.detail, "could not read") != null);
    try t.expect(std.mem.indexOf(u8, unread.detail, "moved out") == null);
    try t.expectEqual(contract.NextStep.environment, (killFinding(a, &trace, 3) orelse return error.TestUnexpectedResult).next);

    trace.cgroup_kill_returned = record(.cgroup, 3, 40);
    const returned = killFinding(a, &trace, 3) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.kill_did_not_land, returned.reason);
}

test "a record at or past the crash point refuses the world, and the operations before it do not (v17, #559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    var trace = try testTrace(a, &.{});
    defer trace.deinit();

    trace.kill_point_count = 2;
    try t.expect(pastFinding(a, &trace, 3) == null);
    trace.kill_point_count = 3;
    const at = pastFinding(a, &trace, 3) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.kill_did_not_land, at.reason);
    trace.kill_point_count = 9;
    try t.expect(pastFinding(a, &trace, 3) != null);

    trace.kill_point_count = 2;
    trace.cgroup_kill_alone = record(.cgroup, 3, 40);
    const alone = pastFinding(a, &trace, 3) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.kill_did_not_land, alone.reason);
    try t.expectEqual(contract.NextStep.environment, alone.next);
}

test "an uncontained spawn tells its shim nothing, pinned empty; a contained world is told both names (v17, #559)" {
    try t.expectEqualStrings("", runName(null));
    try t.expectEqualStrings("", killName(null));
    try t.expectEqualStrings("", asideName(null));
    const world = posix.CgroupSpawn.init(.{ .dir = "/sys/fs/cgroup/e", .rel = "/e" }, true) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.startsWith(u8, runName(&world), "/e/sideeye-"));
    try t.expect(std.mem.endsWith(u8, killName(&world), "/work/cgroup.kill"));
    try t.expect(std.mem.endsWith(u8, asideName(&world), "/cgroup.procs"));
    const recording = posix.CgroupSpawn.init(.{ .dir = "/sys/fs/cgroup/e", .rel = "/e" }, false) orelse return error.TestUnexpectedResult;
    try t.expect(runName(&recording).len > 0);
    try t.expectEqualStrings("", killName(&recording));
    try t.expectEqualStrings("", asideName(&recording));
}

test "a run is held for a detach only when every image answered, and a killed world forgives only an answer its kill cut off (#559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    var trace = try testTrace(a, &.{});
    defer trace.deinit();
    trace.shim_ready_records = 2;
    trace.cgroup_held_records = 2;
    var cg = joinedCgroup();
    try t.expect(holds(&cg, &trace, false));
    try t.expect(!holds(null, &trace, false));
    trace.cgroup_held_records = 1;
    trace.cgroup_unanswered_tail = 1;
    try t.expect(!holds(&cg, &trace, false));
    try t.expect(holds(&cg, &trace, true));
    trace.cgroup_unanswered_live = 1;
    try t.expect(!holds(&cg, &trace, true));
    trace.cgroup_unanswered_live = 0;
    trace.cgroup_held_records = 2;
    trace.cgroup_unanswered_tail = 0;
    trace.cgroup_kill_records = 0;
    try t.expect(holds(&cg, &trace, true));
    cg.joined = false;
    try t.expect(!holds(&cg, &trace, true));
}

test "a detach the engine did not hold is refused with the reason, and the step is the environment's only where the engine cannot make cgroups (#559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const no_cgroup = detachFinding(a, null, " in an explored world", true, false);
    try t.expectEqual(contract.NextStep.environment, no_cgroup.next);
    try t.expect(std.mem.indexOf(u8, no_cgroup.detail, "left the containment group") != null);
    try t.expect(std.mem.indexOf(u8, no_cgroup.detail, "writable cgroup v2 delegated") != null);
    try t.expect(std.mem.indexOf(u8, no_cgroup.detail, " in an explored world") != null);
    const mac = detachFinding(a, null, "", false, false);
    try t.expectEqual(contract.NextStep.class_wall, mac.next);
    const missed = detachFinding(a, null, "", true, true);
    try t.expectEqual(contract.NextStep.retry_then_report, missed.next);
    try t.expect(std.mem.indexOf(u8, missed.detail, "can make them here") != null);
    var cg = joinedCgroup();
    const unanswered = detachFinding(a, &cg, "", true, true);
    try t.expectEqual(contract.NextStep.class_wall, unanswered.next);
    try t.expect(std.mem.indexOf(u8, unanswered.detail, "said it was inside") != null);
}
