//! The watch on a run the engine contained in a cgroup of its own (contract v17, #559).
//!
//! Where the engine can move processes within its own cgroup on Linux — a cgroup v2 delegated
//! to it, or root — each observed run — the recording run, every explored world and the
//! baseline, preflight's second run — gets a cgroup made for it (`posix.CgroupSpawn`). The
//! engine's cleanup writes that cgroup's `cgroup.kill` (`posix.runChildImplWithOps`); a world's
//! crash point steps aside out of the cgroup below it that the run's processes are in, writes
//! that one's `cgroup.kill`, and then signals its process group (`shim/src/common.zig`). A cgroup reaches a process however it left the process group,
//! which is what it is for. It also has exits a process group did not have: a process can
//! write its pid into another cgroup's `cgroup.procs`, be moved there by someone else, or be
//! created in one through `clone3(CLONE_INTO_CGROUP)`, and none of that is a `setsid` the
//! shim sees.
//!
//! This file is the engine's half of watching those exits. The shim's half is the `cgroup`
//! record (`contract.cgroup_aux`); the oracle's is `oracle.Parsed.cgroup_move`. Every check
//! here refuses and none admits: nothing in this file lifts a refusal.
//!
//! **The checks run after the refusals of the phase their run is judged in**, at the call sites
//! in `main.zig`, so none of those changes name. Two things are asked later still. For the
//! recording run, `phaseChecker`'s falsification of the declared checker, before any world: a
//! contained run whose watch finds something reports that finding instead of
//! `checker_not_falsified`, and one whose checker probe could not be started is refused with the
//! finding (exit 2) before that setup error (exit 3) is reached. And `requireCompleteness`,
//! which answers a would-be PASS without an oracle in `phasePreflight` and `phaseReport`: a
//! contained run with neither `--oracle` nor `--allow-unverified` reports the finding instead of
//! `completeness_not_verified`. One check answers ahead of a refusal on purpose, named at
//! `killCameBack`. A run the engine did
//! not contain meets none of this. What containment changes besides is which runs get this far
//! — a detach the shim did not record, missed by the process group, is stopped by the cgroup
//! instead of being caught still writing — and BUILDLOG's #559 entry names that case.
//!
//! Each check is a function returning what it found, beside a thin one that refuses on it:
//! `refuse.unknown` ends the process, so the finding is what a test can reach.

const std = @import("std");
const contract = @import("contract");
const engine_build_options = @import("engine_build_options");
const posix = @import("posix.zig");
const engine = @import("engine.zig");
const refuse = @import("refuse.zig");

/// A cgroup for one observed run, or null where the run is not contained: anywhere but
/// Linux, where the engine cannot move processes within its own cgroup, in the `-Dtest-no-cgroup` engine, and when the kernel
/// refused the entropy its name is drawn from. `world` says whether the shim is also handed
/// the cgroup's `cgroup.kill`.
pub fn spawn(world: bool) ?posix.CgroupSpawn {
    if (engine_build_options.no_cgroup) return null;
    const home = posix.cgroupHome() orelse return null;
    return posix.CgroupSpawn.init(home, world);
}

/// `contract.env.run_cgroup` for a spawn: the cgroup as the shim will find itself in it, or
/// empty. Empty rather than unset for the reason `seq_base` is pinned: a value left in the
/// operator's shell must not tell a shim it was contained.
pub fn runName(cg: ?*const posix.CgroupSpawn) []const u8 {
    return if (cg) |c| c.relPath() else "";
}

/// `contract.env.kill_cgroup`: a contained world's `cgroup.kill`, or empty — the recording run
/// and preflight's second run are not killed at a crash point.
pub fn killName(cg: ?*const posix.CgroupSpawn) []const u8 {
    const c = cg orelse return "";
    return if (c.world) c.killPath() else "";
}

/// `contract.env.kill_aside`: where a contained world's crash point steps aside to, or empty.
pub fn asideName(cg: ?*const posix.CgroupSpawn) []const u8 {
    const c = cg orelse return "";
    return if (c.world) c.asidePath() else "";
}

/// What a check found, in the shape `refuse.unknown` takes.
pub const Finding = struct {
    reason: contract.UnknownReason,
    detail: []const u8,
    next: contract.NextStep,
};

/// Refuse a contained run whose cgroup did not hold it. Called once the run's trace has been
/// read and every refusal the run already had has been asked.
///
/// `where` ends each detail (`""` for the recording run, `" in an explored world"`, …).
/// `lingering_counts` says whether a process still in the cgroup when the direct child exited
/// is evidence. It is not in a world killed at its crash point: the shim's write to
/// `cgroup.kill` is what ended that run, and the processes it was still taking down when the
/// direct child's exit reached the engine are that kill at work.
pub fn afterRun(arena: std.mem.Allocator, cg: *const posix.CgroupSpawn, trace: *const engine.TraceInfo, where: []const u8, lingering_counts: bool) void {
    if (runFinding(arena, cg, trace, where, lingering_counts, posix.processState)) |f|
        refuse.unknown(f.reason, f.detail, f.next);
}

/// `afterRun`'s decision. `stateOf` is `posix.processState` outside tests.
pub fn runFinding(
    arena: std.mem.Allocator,
    cg: *const posix.CgroupSpawn,
    trace: *const engine.TraceInfo,
    where: []const u8,
    lingering_counts: bool,
    stateOf: *const fn (u32) ?u8,
) ?Finding {
    if (!cg.joined) return null;

    // The cgroup did not empty after `cgroup.kill`: something the kill could not take is still
    // running, and what touches the state from here is unaccounted for.
    if (!cg.stopped) return .{
        .reason = .child_process_detected,
        .detail = std.fmt.allocPrint(arena, "the run's cgroup could not be stopped{s}: {d} ms after its cgroup.kill was written it still held a live process, so what touches the state from here is unaccounted for", .{ where, posix.world_kill_grace_ms }) catch "the run's cgroup could not be stopped",
        .next = .environment,
    };

    // A shim that found its own process outside the run's cgroup, or could not tell — at its
    // announcement, at a process boundary, or at a crash point whose kill came back.
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
        // A writer still in the run's cgroup when the direct child exited — in `work` or the
        // run's own, not in a cgroup the target made below them (`posix.cgroupStopReal`) — was
        // stopped by the cleanup's `cgroup.kill`, part way through whatever it was writing. An uncontained engine's
        // group kill ends such a writer the same way and says nothing (plan review, M-c); a
        // contained run refuses it, and only it: a process the trace never names writing
        // anything is killed as the group kill has always killed a lingering helper.
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

    // Nothing the trace names, and nothing that was still in the cgroup, outlived the stop. A
    // process inside the cgroup cannot have — `stopped` says it emptied — so one that is alive
    // left it. A zombie (`Z`) and a process being torn down (`X`) are dead. A state that could
    // not be read counts as alive, and so does a pid the kernel handed to someone else in the
    // meantime: both are the side to be wrong on.
    var pids = named.keyIterator();
    while (pids.next()) |pid| {
        if (survivor(arena, pid.*, where, stateOf)) |f| return f;
    }
    for (cg.lingering[0..cg.lingering_len]) |pid| {
        if (survivor(arena, pid, where, stateOf)) |f| return f;
    }
    return null;
}

/// A `cgroup:outside` or `cgroup:unreadable` record, worded for which it is: a process the
/// shim saw outside the cgroup is the target's doing, one whose standing could not be read is
/// the environment's, and neither is said to be the other.
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

/// Refuse a contained world killed at crash point `k` that exited instead of dying, when its
/// shim said why.
///
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
    // The write came back while the process was inside the cgroup: the kill itself failed. A
    // cgroup made threaded refuses `cgroup.kill`, and so does one the engine cannot write.
    if (trace.cgroup_kill_returned) |op| return .{
        .reason = .kill_did_not_land,
        .detail = std.fmt.allocPrint(arena, "the crash point's write to the run's cgroup.kill came back (pid {d}, before operation {d}): the kill did not take the run, so the world did not die where it was asked to", .{ op.pid, k }) catch "the crash point's write to the run's cgroup.kill came back",
        .next = .environment,
    };
    if (trace.cgroup_outside) |op|
        return outsideFinding(arena, op, std.fmt.allocPrint(arena, " in an explored world that exited instead of dying before operation {d}", .{k}) catch " in an explored world");
    return null;
}

/// Refuse a contained world at crash point `k` whose trace holds an operation at or past it.
///
/// The shim writes an operation's record only after the crash-point test lets the operation
/// through, so in a world that died before operation `k` the highest kill point is `k - 1`
/// however many processes it had. A record numbered `k` or more is an operation performed
/// after the kill was issued, by a process it had not reached — whichever exit that process
/// took, and whether or not it is still alive. Sound for any world; asked of contained ones,
/// where the kill is meant to reach every process, and not added to every target.
pub fn pastCrashPoint(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) void {
    if (pastFinding(arena, trace, k)) |f| refuse.unknown(f.reason, f.detail, f.next);
}

pub fn pastFinding(arena: std.mem.Allocator, trace: *const engine.TraceInfo, k: u32) ?Finding {
    // A crash point that could not step aside out of the cgroup it was killing (second review,
    // #559 PR A): its kill was the cgroup's alone, and a process that had left the cgroup without
    // leaving the process group was not stopped there, as an uncontained world's group kill would
    // have stopped it. Whatever the numbers below say, the kill was short.
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

// ---- tests -------------------------------------------------------------------------------

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

    // Control: everything the trace names is gone, nothing lingered.
    var cg = joinedCgroup();
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState(null)) == null);
    // Zombies and processes being torn down are dead.
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('Z')) == null);
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('X')) == null);

    // A named process still running after the stop.
    const alive = runFinding(a, &cg, &trace, " in an explored world", true, fakeState('S')) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.child_process_detected, alive.reason);
    try t.expect(std.mem.indexOf(u8, alive.detail, "still alive after the run's cgroup was stopped in an explored world") != null);
    // A state that could not be read is not taken for dead.
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('?')) != null);

    // The cgroup did not empty.
    cg.stopped = false;
    const stuck = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.NextStep.environment, stuck.next);
    cg.stopped = true;

    // A spawn that never joined is not watched at all.
    cg.joined = false;
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState('S')) == null);
}

test "a writer still in the cgroup when the direct child exited refuses, a silent helper does not, and a killed world's teardown is not evidence (v17, #559)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    // pid 41 wrote a kill point; pid 42 only announced itself.
    var trace = try testTrace(a, &.{ record(.shim_ready, 0, 40), record(.shim_ready, 0, 41), record(.write, 1, 41), record(.shim_ready, 0, 42) });
    defer trace.deinit();
    var cg = joinedCgroup();

    cg.lingering[0] = 41;
    cg.lingering_len = 1;
    const cut = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, cut.detail, "pid 41") != null);
    try t.expect(std.mem.indexOf(u8, cut.detail, "cut it short") != null);
    // The same lingering writer, in a world its crash point killed: not evidence.
    try t.expect(runFinding(a, &cg, &trace, "", false, fakeState(null)) == null);

    // A lingering process that wrote nothing is killed, not refused.
    cg.lingering[0] = 42;
    try t.expect(runFinding(a, &cg, &trace, "", true, fakeState(null)) == null);

    // More than the engine read cannot be vouched for.
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

    // A standing that could not be read is the environment's, and is not called a move.
    var unreadable = record(.cgroup, 0, 44);
    unreadable.aux = contract.cgroup_aux.unreadable;
    trace.cgroup_outside = unreadable;
    const unread = runFinding(a, &cg, &trace, "", true, fakeState(null)) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.NextStep.environment, unread.next);
    try t.expect(std.mem.indexOf(u8, unread.detail, "could not read") != null);
    try t.expect(std.mem.indexOf(u8, unread.detail, "moved out") == null);
    try t.expectEqual(contract.NextStep.environment, (killFinding(a, &trace, 3) orelse return error.TestUnexpectedResult).next);

    // The write came back from inside: the kill failed, and it is named before `outside` is.
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

    // Died before operation 3: the highest kill point is 2.
    trace.kill_point_count = 2;
    try t.expect(pastFinding(a, &trace, 3) == null);
    // Operation 3 itself was recorded: something performed it after the kill was issued.
    trace.kill_point_count = 3;
    const at = pastFinding(a, &trace, 3) orelse return error.TestUnexpectedResult;
    try t.expectEqual(contract.UnknownReason.kill_did_not_land, at.reason);
    trace.kill_point_count = 9;
    try t.expect(pastFinding(a, &trace, 3) != null);

    // A crash point that killed with the cgroup alone is refused whatever the numbers say.
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
    // The recording run is contained and never killed at a crash point.
    const recording = posix.CgroupSpawn.init(.{ .dir = "/sys/fs/cgroup/e", .rel = "/e" }, false) orelse return error.TestUnexpectedResult;
    try t.expect(runName(&recording).len > 0);
    try t.expectEqualStrings("", killName(&recording));
    try t.expectEqualStrings("", asideName(&recording));
}
