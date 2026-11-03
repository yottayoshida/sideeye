const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const cli = @import("cli.zig");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const pinning = @import("pinning.zig");
const defang = @import("defang.zig");
const controls_run = @import("controls_run.zig");

pub const Refusal = struct { reason: contract.SetupErrorReason, text: []const u8 };

pub fn refusal(args: cli.Args) ?Refusal {
    if (builtin.os.tag != .linux)
        return .{ .reason = .platform_unsupported, .text = "--interleave runs on Linux only: it pauses the operation at a crash point with a stop at the calling thread, which this platform does not deliver there" };
    if (args.observe != .wrappers)
        return .{ .reason = .platform_unsupported, .text = "--interleave runs under the default observation mode only; drop --observe" };
    if (args.world_timeout_s == null)
        return .{ .reason = .define_invalid, .text = "--interleave needs --world-timeout: a second copy that never ends would otherwise hold the run forever" };
    if (args.interleave_wait_s >= args.world_timeout_s.?)
        return .{ .reason = .define_invalid, .text = "--interleave waits on the second copy before resuming the first, so --world-timeout, which bounds the whole world, must be longer than that wait" };
    if (args.recovery != null)
        return .{ .reason = .define_invalid, .text = "--interleave does not run a recovery: an interleaved world ends with both copies finished, not in a crash state a recovery would start from" };
    if (args.leave_crash_state)
        return .{ .reason = .define_invalid, .text = "--leave-crash-state has no crash state to leave in an interleaved world: both copies run to their end" };
    if (args.power_loss != null)
        return .{ .reason = .define_invalid, .text = "--interleave and --power-loss each name the run's crash model; run them separately" };
    if (args.rerun)
        return .{ .reason = .define_invalid, .text = "--interleave does not take --invariant rerun: an interleaved world already runs the operation again, beside the first copy" };
    if (args.marker != null)
        return .{ .reason = .define_invalid, .text = "--interleave does not take a success marker: a marker is about one run's output, and an interleaved world has two" };
    if (pinning.asked(args.apparatus))
        return .{ .reason = .define_invalid, .text = "--interleave does not take pin:random: the second copy would draw the first copy's numbers, or none of them" };
    if (pinning.askedClock(args.apparatus))
        return .{ .reason = .define_invalid, .text = "--interleave does not take pin:clock: both copies would read one instant, and names or ids made from the time would collide as no two real runs' do" };
    return null;
}

pub const SecondCopy = struct {
    argv: []const []const u8,
    env: []const [2][]const u8,
    stdout: []const u8,
    budget_ms: u64,
    cwd: ?[]const u8,
    wait_ms: u64,
    stopped: bool = false,
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),
    term: ?posix.Term = null,
    failed: ?(posix.ContainedSpawnError || error{TimedOut}) = null,
    past_wait: bool = false,

    fn body(self: *SecondCopy) void {
        posix.registers_second = true;
        if (posix.runChildCaptureWorld(std.heap.page_allocator, self.argv, self.env, .{ .path = self.stdout, .exclusive = true }, self.budget_ms, self.cwd, null)) |t| {
            self.term = t;
        } else |e| self.failed = e;
        self.done.store(true, .release);
    }

    pub fn onStop(ctx: *anyopaque, pid: c_int) void {
        const self: *SecondCopy = @ptrCast(@alignCast(ctx));
        posix.stop_hook = null;
        self.stopped = true;
        self.thread = std.Thread.spawn(.{}, body, .{self}) catch null;
        if (self.thread != null) {
            const t0 = posix.monotonicMs();
            while (!self.done.load(.acquire) and posix.monotonicMs() - t0 < self.wait_ms) {
                const ts: std.c.timespec = .{ .sec = 0, .nsec = 10_000_000 };
                _ = posix.nanosleep(&ts, null);
            }
            self.past_wait = !self.done.load(.acquire);
        }
        // Resumed whether or not the second copy ended: a copy blocked on the first's lock proceeds
        // only once the first releases it, and killing it would read waiting as failing.
        _ = posix.kill(pid, posix.SIGCONT);
    }
};

pub const Checker = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    argv: ?[]const []const u8,
    state_abs: []const u8,
    work: []const u8,
    cwd: ?[]const u8,

    pub fn run(self: Checker, label: []const u8, out_buf: *[contract.max_path]u8) controls_run.WorldChecker {
        const cargv = self.argv orelse return .{ .failed = false, .out = null };
        return controls_run.runWorldChecker(self.gpa, self.arena, cargv, self.state_abs, self.work, self.cwd, out_buf, label);
    }
};

pub fn exitedWith(term: posix.Term, status: u8) bool {
    return switch (term) {
        .exited => |code| code == status,
        else => false,
    };
}

pub fn termShown(arena: std.mem.Allocator, term: posix.Term) []const u8 {
    return switch (term) {
        .exited => |code| std.fmt.allocPrint(arena, "exited {d}", .{code}) catch "exited",
        .signaled => |sig| std.fmt.allocPrint(arena, "was killed by signal {d}", .{sig}) catch "was killed by a signal",
        else => "did not exit normally",
    };
}

pub fn firstDifference(arena: std.mem.Allocator, expected: engine.Snapshot, got: engine.Snapshot, scratch: []const []const u8) ?[]const u8 {
    var one: [1]engine.Difference = undefined;
    const d = engine.diffSnapshotsExcept(expected, got, &one, scratch);
    if (d.equal()) return null;
    if (d.stored == 0) return "the state";
    const how = switch (one[0].how) {
        .only_in_first => "missing",
        .only_in_second => "present but not expected",
        .kind_differs => "of another kind",
        .content_differs => "holding other bytes",
    };
    return std.fmt.allocPrint(arena, "{s} ({s})", .{ defang.textShown(arena, one[0].rel), how }) catch one[0].rel;
}

test "an interleaved run is refused where its pause or its yardstick cannot hold" {
    const base: cli.Args = .{ .interleave = true, .world_timeout_s = 60 };
    if (builtin.os.tag != .linux) {
        try std.testing.expectEqual(contract.SetupErrorReason.platform_unsupported, refusal(base).?.reason);
        return;
    }
    try std.testing.expect(refusal(base) == null);
    const Case = struct { args: cli.Args, reason: contract.SetupErrorReason };
    var syscalls = base;
    syscalls.observe = .syscalls;
    var no_budget = base;
    no_budget.world_timeout_s = null;
    var wait_not_shorter = base;
    wait_not_shorter.world_timeout_s = contract.interleave_wait_default_s;
    var with_recovery = base;
    with_recovery.recovery = "fix";
    var leave = base;
    leave.leave_crash_state = true;
    var pinned = base;
    pinned.apparatus = &.{"pin:random"};
    var marked = base;
    marked.marker = "done";
    var power = base;
    power.power_loss = .rename_before_data;
    var rerun = base;
    rerun.rerun = true;
    for ([_]Case{
        .{ .args = syscalls, .reason = .platform_unsupported },
        .{ .args = no_budget, .reason = .define_invalid },
        .{ .args = wait_not_shorter, .reason = .define_invalid },
        .{ .args = with_recovery, .reason = .define_invalid },
        .{ .args = leave, .reason = .define_invalid },
        .{ .args = pinned, .reason = .define_invalid },
        .{ .args = marked, .reason = .define_invalid },
        .{ .args = power, .reason = .define_invalid },
        .{ .args = rerun, .reason = .define_invalid },
    }) |c| try std.testing.expectEqual(c.reason, refusal(c.args).?.reason);
}

test "a copy succeeded only when it exited with the expected status, and its end is shown as it happened" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("exited 3", termShown(arena, .{ .exited = 3 }));
    try std.testing.expect(exitedWith(.{ .exited = 0 }, 0));
    try std.testing.expect(!exitedWith(.{ .exited = 1 }, 0));
    try std.testing.expect(!exitedWith(.{ .signaled = 9 }, 0));
}
