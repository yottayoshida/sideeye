const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const oracle = @import("oracle.zig");
const capture = @import("capture.zig");
const posix = @import("posix.zig");
const refuse = @import("refuse.zig");
const report = @import("report.zig");
const boundary = @import("boundary.zig");
const containment = @import("containment.zig");
const supervise = @import("supervise.zig");
const files = @import("files.zig");

const unknown = refuse.unknown;
const setupError = refuse.setupError;

// The engine's variables go to the target through `-E`, never through strace's own environment:
// the shim in LD_PRELOAD would load into strace and count strace's writes as the target's.
pub fn straceArgv(arena: std.mem.Allocator, strace_path: []const u8, out_path: []const u8, pairs: []const [2][]const u8, argv: []const []const u8) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    list.appendSlice(arena, &.{ strace_path, "-f", "-y", "-e", oracle.strace_trace_spec, "-o", out_path }) catch outOfMemory();
    for (pairs) |kv| {
        const joined = std.fmt.allocPrint(arena, "{s}={s}", .{ kv[0], kv[1] }) catch outOfMemory();
        list.appendSlice(arena, &.{ "-E", joined }) catch outOfMemory();
    }
    list.appendSlice(arena, argv) catch outOfMemory();
    return list.items;
}

fn outOfMemory() noreturn {
    setupError(.environment, "out of memory");
}

pub const World = struct {
    gpa: std.mem.Allocator,
    k: u32,
    n: u32,
    capture_path: []const u8,
    state_abs: []const u8,
    state_alt: []const u8,
    cwd: []const u8,
    children_admitted: bool,
    cg: ?*const posix.CgroupSpawn,
    observe: contract.ObserveMode,
    keep: std.mem.Allocator,
};

fn killedTid(trace: *const engine.TraceInfo) ?u64 {
    for (trace.ops.items) |op| if (op.class == .kill_landed) return op.tid;
    return null;
}

pub fn checkWorld(w: World, trace: *const engine.TraceInfo) ?[]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(w.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const where = std.fmt.allocPrint(arena, " in explored world {d}", .{w.k}) catch outOfMemory();

    const text = capture.readFileAlloc(arena, w.capture_path) orelse
        setupError(.environment, "an explored world's oracle capture could not be read");
    const own_files = [_][]const u8{ containment.killName(w.cg), containment.asideName(w.cg) };
    const parsed = oracle.parseWorld(arena, text, w.state_abs, w.state_alt, w.cwd, .{
        .killed_tid = killedTid(trace),
        .shim_cgroup_files = if (w.cg != null and own_files[0].len > 0) &own_files else &.{},
    }) catch outOfMemory();

    if (parsed.lines_seen == 0)
        unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the oracle produced no output{s}, so nothing was compared against {s}'s account", .{ where, boundary.recorder() }) catch "the oracle produced no output in an explored world", .environment);
    if (parsed.boundary) |name|
        unknown(.child_process_detected, std.fmt.allocPrint(arena, "{s}{s}", .{ name, where }) catch name, .unwrap_or_class_wall);
    if (parsed.detached != null and !containment.holds(w.cg, trace, w.k <= w.n))
        containment.refuseDetach(arena, w.cg, std.fmt.allocPrint(arena, ", seen by the oracle as a child's {s}{s}", .{ parsed.detached.?, where }) catch "");
    if (w.children_admitted) {
        if (boundary.worldWritersAgree(arena, trace.*, parsed)) |why|
            unknown(boundary.unattributedWriterReason(trace.*, parsed), boundary.withOracleCapture(arena, std.fmt.allocPrint(arena, "{s}{s}", .{ why.detail, where }) catch why.detail, w.capture_path, why.detail), boundary.staticParentNext(
                boundary.childTouchedNext(why.wall, w.observe, true),
                why.wall == .shimmed_writer_unnumbered and boundary.shimAnnouncedElsewhere(trace.primary_pid, parsed.primary_pid),
            ));
    } else if (parsed.childTouched())
        unknown(.child_touched_state_dir, boundary.withOracleCapture(arena, std.fmt.allocPrint(arena, "the oracle saw a process other than the subject change the state directory{s}, and the recording admitted no child whose operations are crash points", .{where}) catch "the oracle saw a process other than the subject change the state directory in an explored world", w.capture_path, "a process other than the subject changed the state directory in an explored world"), .class_wall);
    if (parsed.unsupported) |name|
        unknown(.unsupported_syscall_observed, name, .class_wall);

    compareOrRefuse(arena, trace, &parsed, w.observe, where);
    return if (parsed.cgroup_move) |what| std.fmt.allocPrint(w.keep, "{s}{s}", .{ what, where }) catch what else null;
}

pub fn compareOrRefuse(arena: std.mem.Allocator, trace: *const engine.TraceInfo, parsed: *const oracle.Parsed, observe: contract.ObserveMode, where: []const u8) void {
    var shim_classes: std.ArrayList(contract.OpClass) = .empty;
    var shim_ops: std.ArrayList(engine.Op) = .empty;
    for (trace.ops.items) |op| {
        if (op.class.isMarker() or op.class.isBoundary() or op.class.isThreadSync()) continue;
        if (op.class == .close) continue;
        if (trace.primary_pid != null and op.pid != trace.primary_pid.?) continue;
        shim_classes.append(arena, op.class) catch outOfMemory();
        shim_ops.append(arena, op) catch outOfMemory();
    }
    const mode_hint = if (observe == .syscalls)
        " — and under --observe syscalls each trapped call reaches the oracle twice, once refused and once re-issued, so this can also mean a refusal the capture did not carry (one operation too many) or a retraction that fired on an entry that had run (one too few)"
    else
        "";
    const observer = supervise.observerName(observe);
    if (oracle.compare(shim_classes.items, parsed.classes.items)) |f| switch (f) {
        .missed => |m| unknown(.oracle_missed_operation, report.divergenceDetail(
            arena,
            std.fmt.allocPrint(arena, "the oracle saw a state-directory operation the {s} did not record{s}{s}", .{ observer, where, mode_hint }) catch
                "the oracle saw a state-directory operation the observer did not record",
            m.index,
            shim_ops.items,
            parsed.lines.items,
            parsed.names.items,
        ), boundary.staticParentNext(
            boundary.missedOperationNext(observe, builtin.os.tag == .linux),
            boundary.shimAnnouncedElsewhere(trace.primary_pid, parsed.primary_pid),
        )),
        .phantom => |p| unknown(.oracle_saw_phantom, report.divergenceDetail(
            arena,
            std.fmt.allocPrint(arena, "the {s} recorded an operation the oracle did not see{s}{s}", .{ observer, where, mode_hint }) catch
                "the observer recorded an operation the oracle did not see",
            p.index,
            shim_ops.items,
            parsed.lines.items,
            parsed.names.items,
        ), .sideeye_defect),
        .unsupported => |name| unknown(.unsupported_syscall_observed, name, .class_wall),
    };
}
