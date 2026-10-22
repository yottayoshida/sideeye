//! **When.** After the exploration loop, once the verdict is decided, and only when the run has
//! a FAIL. Run inside the loop, a recovery's writes outside the state directory and any process
//! it leaves behind would reach every later world and the baseline — which the next world's
//! restore does not undo — and a FAIL could come out UNKNOWN. After the loop there is nothing
//! left for it to change.
//!
//! **Which state.** Each saved exhibit's `crashed` snapshot, kept past its world by the loop,
//! rebuilt in the state directory with `engine.restore` — the directory after the loop holds the
//! baseline's result with the world checker's work on top, not the crash state. A snapshot
//! holds names, kinds, contents and permission bits (ADR 0109) and nothing else, so
//! the rebuilt state carries the crash's permission bits but restore-time timestamps and the
//! engine's ownership: a recovery that decides by modification time sees every file as new. The
//! report says so rather than the result pretending otherwise.
//!
//! **What counts.** `pass` and `fail` are spent on one observation: the command ran and ended,
//! the state stopped changing, and the recovery checker accepted or rejected it. Everything else
//! is `unknown`, because reporting a recovery that never ran as `fail` would be a claim about the
//! tool this run did not measure. The checker is trusted only after both of the world checker's
//! controls: it rejects a corrupted state, and it accepts what the recovery leaves on the
//! completed, uncrashed state — the world loop's baseline, with the recovery run on it. Without
//! the second, a checker that rejects everything (a variable its environment lacks, a path that
//! does not resolve) reads every exhibit `fail`, which is the checker's verdict on itself.
//!
//! **What this file must never do** is end the process. The verdict is already decided when it
//! runs, and a recovery failure that reached `setupError`, `spawnFailure`, `unknown()`, a
//! `refuse.*` helper, `containment.afterRun` or `snapshotOrRefuse` would replace a FAIL with a
//! refusal about the recovery. Of the modules that hold them only `containment` is imported, for
//! `spawn` alone — its `afterRun`, `refuseDetach`, `killCameBack` and `pastCrashPoint` all end the
//! process — and the acceptance suite greps this file for every one of those names.

const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const forks_text = std.fmt.comptimePrint("{d}", .{posix.max_group_forks});
const capture = @import("capture.zig");
const files = @import("files.zig");
const report = @import("report.zig");
const containment = @import("containment.zig");

pub const Exhibit = struct {
    k: u32,
    crashed: engine.Snapshot,
};

pub const Leg = struct {
    k: u32,
    result: contract.RecoveryResult,
    ms: u64,
    command_exit: ?u8,
    why: []const u8,
    stopped: Stopped = .{},
    survivor: bool = false,
};

pub const Stopped = struct {
    count: u32 = 0,
    more: bool = false,
};

pub fn claimAfter(earliest: Leg) ?[]const u8 {
    if (earliest.survivor)
        return "the earliest exhibit's leg left a process its cgroup could not stop, and this leg would have run beside it";
    return null;
}

pub const Declared = struct {
    command: []const []const u8,
    check: []const []const u8,
};

pub const Context = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    state_abs: []const u8,
    work: []const u8,
    cwd: ?[]const u8,
    budget_ms: ?u64,
    stop_when_orphaned: bool,
    startup_ppid: c_int,
};

pub const Outcome = struct {
    earliest: ?Leg,
    checker: ?Leg,
    total_ms: u64,
    trusted: bool,
};

pub const probe_prefix = "sideeye-recovery-probe:";
pub const probe_link_target = "sideeye-recovery-probe-target";

/// path, and every symlink retargeted at `probe_link_target`. Directories are kept. Built as a
/// snapshot, and written through the public `engine.restore`, so the probe keeps every guard a
/// restore has — the vetted root, the held descriptor, no symlink followed on the way in —
/// without a second writer beside it.
pub fn probeSnapshot(gpa: std.mem.Allocator, from: engine.Snapshot) !engine.Snapshot {
    var snap: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    errdefer snap.arena.deinit();
    const a = snap.arena.allocator();
    for (from.entries.items) |e| {
        const content: []const u8 = switch (e.kind) {
            .file => try std.fmt.allocPrint(a, "{s}{s}\n", .{ probe_prefix, e.rel }),
            .symlink => probe_link_target,
            else => try a.dupe(u8, e.content),
        };
        // Never drop the mode: the baseline is rebuilt with it, and a checker that reads only a
        // mode would reject a probe without it and accept the baseline unread.
        try snap.entries.append(a, .{ .rel = try a.dupe(u8, e.rel), .kind = e.kind, .content = content, .mode = e.mode });
    }
    try engine.finalizeEntries(&snap);
    return snap;
}

pub fn commandEnd(term: posix.Term) ?[]const u8 {
    return switch (term) {
        // 125 is the child's when it could not enter the declared cwd, 126 the fork stub's own
        // status and 127 the child's after a failed exec: in all three the recovery may never
        // have started, and a checker run now would judge the crash state itself. A command
        // that genuinely exits one of them is `unknown` too — the conservative side.
        .exited => |c| if (c == 125)
            "the recovery command could not enter the declared cwd, or exited 125 (indistinguishable here)"
        else if (c == 126)
            "the recovery command could not be arranged before exec (exit 126)"
        else if (c == 127)
            "the recovery command could not be executed (exit 127)"
        else
            null,
        // Read as a command that ran. The one pre-exec death that is a signal — `adoptStdin`'s abort
        // on a `dup2` that failed other than by EINTR — cannot be told from a recovery that
        // aborted; the engine treats that `dup2` as unreachable, and reading every SIGABRT as
        // `unknown` would lose the tools whose recovery really crashes.
        .signaled => null,
        .unknown => "the recovery command ended in a status the engine does not decode",
    };
}

pub fn checkerEnd(term: posix.Term) struct { result: contract.RecoveryResult, why: []const u8 } {
    return switch (term) {
        .exited => |c| switch (c) {
            0 => .{ .result = .pass, .why = "the recovery checker accepted the recovered state" },
            125 => .{ .result = .unknown, .why = "the recovery checker could not enter the declared cwd, or exited 125 (indistinguishable here)" },
            126 => .{ .result = .unknown, .why = "the recovery checker could not be arranged before exec (exit 126)" },
            127 => .{ .result = .unknown, .why = "the recovery checker could not be executed (exit 127)" },
            else => .{ .result = .fail, .why = "the recovery checker rejected the recovered state" },
        },
        .signaled => .{ .result = .fail, .why = "the recovery checker was killed by a signal" },
        .unknown => .{ .result = .unknown, .why = "the recovery checker ended in a status the engine does not decode" },
    };
}

fn orphaned(ctx: Context) bool {
    return ctx.stop_when_orphaned and posix.getppid() != ctx.startup_ppid;
}

fn runCaptured(ctx: Context, argv: []const []const u8, capture_name: []const u8, label: []const u8, stopped: ?*Stopped) !posix.Term {
    const path = try std.fmt.allocPrint(ctx.arena, "{s}/{s}", .{ ctx.work, capture_name });
    // `exclusive` needs the removal first, and a FIFO planted at the name would otherwise block
    // the parent's open (`Capture.exclusive`).
    files.removeFile(path);
    var cg = containment.spawn(false);
    const cg_ptr: ?*posix.CgroupSpawn = if (cg) |*c| c else null;
    const term = try posix.runChildCaptureWorld(ctx.gpa, argv, &.{
        .{ "TOY_STATE", ctx.state_abs },
        .{ contract.env.state_dir, ctx.state_abs },
    }, .{ .path = path, .stderr_too = true, .exclusive = true }, ctx.budget_ms, ctx.cwd, cg_ptr);
    // Re-emitted with a label on every line, for #134's reason: output that reaches the
    // transcript unlabeled can be harvested as the world's, and this is not the world's.
    if (capture.readFileAllocCapped(ctx.arena, path, 1024 * 1024, .{ .no_follow = true })) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            report.say("{s}{s}\n", .{ label, line });
        }
    }
    if (cg) |c| {
        if (c.joined and !c.stopped) return error.LeftRunning;
        if (stopped) |st| st.* = .{ .count = @intCast(c.lingering_len), .more = c.lingering_more };
    }
    return term;
}

fn unknownLeg(k: u32, started: u64, command_exit: ?u8, why: []const u8) Leg {
    return .{ .k = k, .result = .unknown, .ms = posix.monotonicMs() -| started, .command_exit = command_exit, .why = why };
}

/// Two snapshots of the state, back to back: equal is an observation that nothing was still
/// writing when the checker was about to run, never a proof of future quiet. A writer the
/// recovery left behind — a daemonising restart, a `setsid` child — that is still changing the
/// state makes the leg `unknown` instead of letting the checker judge a moving target. A writer
/// that is quiet at that moment is not seen here: where the leg was contained its cgroup has
/// already stopped it, and where it was not it can reach the next leg (`docs/cli.md`).
fn settled(ctx: Context) ?[]const u8 {
    var first = engine.takeSnapshotCapped(ctx.gpa, ctx.state_abs, engine.SnapshotCaps.shipped, null) catch
        return "the state after the recovery command could not be snapshotted";
    defer first.deinit();
    var second = engine.takeSnapshotCapped(ctx.gpa, ctx.state_abs, engine.SnapshotCaps.shipped, null) catch
        return "the state after the recovery command could not be snapshotted";
    defer second.deinit();
    var one: [1]engine.Difference = undefined;
    if (!engine.diffSnapshots(first, second, &one).equal())
        return "the state was still changing after the recovery command ended";
    return null;
}

fn leg(ctx: Context, d: Declared, ex: Exhibit) Leg {
    const tag = std.fmt.allocPrint(ctx.arena, "{d}", .{ex.k}) catch
        return unknownLeg(ex.k, posix.monotonicMs(), null, "out of memory");
    const label = std.fmt.allocPrint(ctx.arena, " world {d}", .{ex.k}) catch
        return unknownLeg(ex.k, posix.monotonicMs(), null, "out of memory");
    return on(ctx, d, ex.k, ex.crashed, tag, label);
}

fn on(ctx: Context, d: Declared, k: u32, state: engine.Snapshot, tag: []const u8, label: []const u8) Leg {
    const started = posix.monotonicMs();
    if (orphaned(ctx)) return unknownLeg(k, started, null, "the process that launched this run is gone");
    engine.restore(state, ctx.state_abs) catch
        return unknownLeg(k, started, null, "the state could not be rebuilt in the state directory from its snapshot");

    const cmd_name = std.fmt.allocPrint(ctx.arena, "recovery-{s}.txt", .{tag}) catch
        return unknownLeg(k, started, null, "out of memory");
    const cmd_label = std.fmt.allocPrint(ctx.arena, "recovery{s}: ", .{label}) catch
        return unknownLeg(k, started, null, "out of memory");
    var stopped: Stopped = .{};
    const cterm = runCaptured(ctx, d.command, cmd_name, cmd_label, &stopped) catch |e| return switch (e) {
        error.LeftRunning => survivorLeg(k, started, null, "the recovery command left a process its cgroup could not stop"),
        error.TimedOut => unknownLeg(k, started, null, "the recovery command did not end within --world-timeout"),
        error.ChildGroupRefused => unknownLeg(k, started, null, "the recovery command could not be started: the kernel refused it a process group of its own in each of " ++ forks_text ++ " forks"),
        else => unknownLeg(k, started, null, "the recovery command could not be started"),
    };
    const command_exit: ?u8 = switch (cterm) {
        .exited => |c| c,
        else => null,
    };
    if (commandEnd(cterm)) |why| return withStopped(unknownLeg(k, started, command_exit, why), stopped);
    if (settled(ctx)) |why| return withStopped(unknownLeg(k, started, command_exit, why), stopped);

    const chk_name = std.fmt.allocPrint(ctx.arena, "recovery-check-{s}.txt", .{tag}) catch
        return unknownLeg(k, started, command_exit, "out of memory");
    const chk_label = std.fmt.allocPrint(ctx.arena, "recovery{s} check: ", .{label}) catch
        return unknownLeg(k, started, command_exit, "out of memory");
    const kterm = runCaptured(ctx, d.check, chk_name, chk_label, null) catch |e| return withStopped(switch (e) {
        error.LeftRunning => survivorLeg(k, started, command_exit, "the recovery checker left a process its cgroup could not stop"),
        error.TimedOut => unknownLeg(k, started, command_exit, "the recovery checker did not end within --world-timeout"),
        error.ChildGroupRefused => unknownLeg(k, started, command_exit, "the recovery checker could not be started: the kernel refused it a process group of its own in each of " ++ forks_text ++ " forks"),
        else => unknownLeg(k, started, command_exit, "the recovery checker could not be started"),
    }, stopped);
    const end = checkerEnd(kterm);
    return withStopped(.{ .k = k, .result = end.result, .ms = posix.monotonicMs() -| started, .command_exit = command_exit, .why = end.why }, stopped);
}

fn withStopped(l: Leg, stopped: Stopped) Leg {
    var out = l;
    out.stopped = stopped;
    return out;
}

fn survivorLeg(k: u32, started: u64, command_exit: ?u8, why: []const u8) Leg {
    var out = unknownLeg(k, started, command_exit, why);
    out.survivor = true;
    return out;
}

fn baseline(ctx: Context, d: Declared, final: engine.Snapshot) ?[]const u8 {
    const b = on(ctx, d, 0, final, "baseline", " baseline");
    return switch (b.result) {
        .pass => null,
        .fail => "the recovery checker rejected what the recovery left on the completed, uncrashed state",
        .unknown => std.fmt.allocPrint(ctx.arena, "on the completed, uncrashed state, {s}", .{b.why}) catch b.why,
    };
}

/// The falsification probe: the recovery checker must reject a state it has every reason to
/// reject before any result of its is trusted. Built from `final`, the state the operation
/// leaves when it completes — not from a crash state, where a missing file alone would make an
/// existence-only checker exit non-zero and pass the probe without reading a byte.
fn falsify(ctx: Context, d: Declared, final: engine.Snapshot) ?[]const u8 {
    if (orphaned(ctx)) return "the process that launched this run is gone";
    var probe = probeSnapshot(ctx.gpa, final) catch return "the corrupted state for the probe could not be built";
    defer probe.deinit();
    engine.restore(probe, ctx.state_abs) catch return "the corrupted state for the probe could not be written";
    const term = runCaptured(ctx, d.check, "recovery-falsify-check.txt", "recovery falsify: ", null) catch |e| return switch (e) {
        error.TimedOut => "the recovery checker did not end within --world-timeout on the corrupted state",
        error.LeftRunning => "the recovery checker left a process its cgroup could not stop on the corrupted state",
        error.ChildGroupRefused => "the recovery checker could not be started against the corrupted state: the kernel refused it a process group of its own in each of " ++ forks_text ++ " forks",
        else => "the recovery checker could not be started against the corrupted state",
    };
    return switch (term) {
        .exited => |c| switch (c) {
            0 => "the recovery checker accepted a state whose every file had been overwritten with distinct junk",
            125, 126, 127 => "the recovery checker could not be executed against the corrupted state (exit 125, 126 or 127)",
            else => null,
        },
        else => "the recovery checker did not exit normally when given a corrupted state",
    };
}

pub fn run(ctx: Context, d: Declared, final: engine.Snapshot, earliest: ?Exhibit, claim: ?Exhibit) Outcome {
    const started = posix.monotonicMs();
    const first = earliest orelse return .{ .earliest = null, .checker = null, .total_ms = 0, .trusted = false };

    if (falsify(ctx, d, final) orelse baseline(ctx, d, final)) |why| {
        const e: Leg = .{ .k = first.k, .result = .unknown, .ms = 0, .command_exit = null, .why = why };
        const c: ?Leg = if (claim) |cl| .{ .k = cl.k, .result = .unknown, .ms = 0, .command_exit = null, .why = why } else null;
        return .{ .earliest = e, .checker = c, .total_ms = posix.monotonicMs() -| started, .trusted = false };
    }

    const e = leg(ctx, d, first);
    const c: ?Leg = if (claim) |cl|
        (if (cl.k == first.k) e else if (claimAfter(e)) |why| .{ .k = cl.k, .result = .unknown, .ms = 0, .command_exit = null, .why = why } else leg(ctx, d, cl))
    else
        null;
    return .{ .earliest = e, .checker = c, .total_ms = posix.monotonicMs() -| started, .trusted = true };
}

pub fn note(arena: std.mem.Allocator, o: Outcome, failing_worlds: u32) []const u8 {
    const e = o.earliest orelse return "configured; not run (no world was saved as a FAIL)";
    if (!o.trusted) return std.fmt.allocPrint(
        arena,
        "configured; no recovery result was recorded: {s}; ran against 0 of {d} failing world(s), the controls taking {d}.{d:0>3}s",
        .{ e.why, failing_worlds, o.total_ms / 1000, o.total_ms % 1000 },
    ) catch "configured; no recovery result was recorded";
    const legs: usize = if (o.checker) |c| (if (c.k == e.k) 1 else 2) else 1;
    const first = legLine(arena, e);
    const second: []const u8 = if (legs == 2) (std.fmt.allocPrint(arena, "; crash point {s}", .{legLine(arena, o.checker.?)}) catch "") else "";
    return std.fmt.allocPrint(
        arena,
        "configured; the recovery checker was trusted after two controls (corrupted state -> recovery check failed; completed state, recovery run on it -> recovery check passed); crash point {s}{s}; ran against {d} of {d} failing world(s), the saved ones, in {d}.{d:0>3}s; the crash states were rebuilt from snapshots, so contents and permission bits are as the crash left them (a directory with its owner's bits added) and timestamps and owners are not",
        .{ first, second, legs, failing_worlds, o.total_ms / 1000, o.total_ms % 1000 },
    ) catch "configured; ran (the account could not be formatted)";
}

fn legLine(arena: std.mem.Allocator, l: Leg) []const u8 {
    const exit: []const u8 = if (l.command_exit) |c| (std.fmt.allocPrint(arena, ", recovery command exit {d}", .{c}) catch "") else "";
    const stopped: []const u8 = if (l.stopped.count > 0 or l.stopped.more)
        (std.fmt.allocPrint(arena, ", {d}{s} process(es) it left stopped when it exited", .{ l.stopped.count, if (l.stopped.more) "+" else "" }) catch "")
    else
        "";
    return std.fmt.allocPrint(arena, "{d}: {s} ({s}{s}{s}, {d}.{d:0>3}s)", .{ l.k, l.result.name(), l.why, exit, stopped, l.ms / 1000, l.ms % 1000 }) catch "(unformatted)";
}

const t = std.testing;

test "the probe gives every file distinct contents, so an equality checker cannot pass it" {
    var from = try engine.testSnapshot(t.allocator, &.{ .{ "in.txt", "same" }, .{ "out.txt", "same" } });
    defer from.deinit();
    var probe = try probeSnapshot(t.allocator, from);
    defer probe.deinit();
    const in = probe.find("in.txt").?;
    const out = probe.find("out.txt").?;
    try t.expect(!std.mem.eql(u8, in.content, out.content));
    try t.expect(std.mem.startsWith(u8, in.content, probe_prefix));
    try t.expect(!std.mem.eql(u8, in.content, "same"));
    try t.expectEqual(from.entries.items.len, probe.entries.items.len);
}

test "the probe carries each entry's recorded mode, as the rebuilt baseline does (#678)" {
    var from = try engine.testSnapshot(t.allocator, &.{.{ "key", "k" }});
    defer from.deinit();
    from.entries.items[0].mode = 0o600;
    var probe = try probeSnapshot(t.allocator, from);
    defer probe.deinit();
    try t.expectEqual(@as(?u16, 0o600), probe.find("key").?.mode);
}

test "claimAfter: a survivor of the earliest leg makes the claim leg unknown, and nothing else does" {
    const survivor = survivorLeg(2, 0, null, "the recovery checker left a process its cgroup could not stop");
    try t.expect(claimAfter(survivor) != null);
    try t.expect(claimAfter(unknownLeg(2, 0, null, "the recovery command did not end within --world-timeout")) == null);
    const judged: Leg = .{ .k = 2, .result = .fail, .ms = 1, .command_exit = 0, .why = "the recovery checker rejected the recovered state" };
    try t.expect(claimAfter(judged) == null);
}

test "legLine names the processes a contained command left, and only when there were some" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var l: Leg = .{ .k = 3, .result = .fail, .ms = 12, .command_exit = 0, .why = "the recovery checker rejected the recovered state" };
    try t.expect(std.mem.indexOf(u8, legLine(a, l), "stopped when it exited") == null);
    l.stopped.count = 2;
    try t.expect(std.mem.indexOf(u8, legLine(a, l), ", 2 process(es) it left stopped when it exited") != null);
    l.stopped.more = true;
    try t.expect(std.mem.indexOf(u8, legLine(a, l), ", 2+ process(es)") != null);
}

test "commandEnd: only a command that ran and ended goes on to the checker" {
    try t.expect(commandEnd(.{ .exited = 0 }) == null);
    try t.expect(commandEnd(.{ .exited = 1 }) == null);
    try t.expect(commandEnd(.{ .signaled = 9 }) == null);
    try t.expect(commandEnd(.{ .exited = 125 }) != null);
    try t.expect(commandEnd(.{ .exited = 126 }) != null);
    try t.expect(commandEnd(.{ .exited = 127 }) != null);
    try t.expect(commandEnd(.{ .unknown = 12345 }) != null);
}

test "checkerEnd: fail only when the checker ran and rejected; never for a checker that did not start" {
    try t.expectEqual(contract.RecoveryResult.pass, checkerEnd(.{ .exited = 0 }).result);
    try t.expectEqual(contract.RecoveryResult.fail, checkerEnd(.{ .exited = 1 }).result);
    try t.expectEqual(contract.RecoveryResult.fail, checkerEnd(.{ .signaled = 9 }).result);
    try t.expectEqual(contract.RecoveryResult.unknown, checkerEnd(.{ .exited = 125 }).result);
    try t.expectEqual(contract.RecoveryResult.unknown, checkerEnd(.{ .exited = 126 }).result);
    try t.expectEqual(contract.RecoveryResult.unknown, checkerEnd(.{ .exited = 127 }).result);
    try t.expectEqual(contract.RecoveryResult.unknown, checkerEnd(.{ .unknown = 12345 }).result);
}

test {
    // Zig analyses a function only when something reaches it, and the tests above reach the
    // pure helpers alone: without this, `run`, `leg` and `falsify` would first be type-checked
    // by whichever build first calls them.
    std.testing.refAllDecls(@This());
}
