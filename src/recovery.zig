//! The recovery phase: what a target's own recovery does to a saved FAIL world's crash state
//! (#606, ADR 0072).
//!
//! A FAIL says the state a crash left violates an invariant. Some tools repair that state on
//! their next start — ninja rebuilds an output its log says is stale — and some make it worse,
//! deleting the last good copy on the way. Neither is visible in the crash-state verdict, and
//! it must not become visible *there*: the verdict is about the state the crash left, and a
//! recovery that succeeds does not make that state correct. So a declared recovery is a second
//! observation, reported beside the verdict and never folded into it.
//!
//! **When.** After the exploration loop, once the verdict is decided, and only when the run has
//! a FAIL. Run inside the loop, a recovery's writes outside the state directory and any process
//! it leaves behind would reach every later world and the baseline — which the next world's
//! restore does not undo — and a FAIL could come out UNKNOWN. After the loop there is nothing
//! left for it to change.
//!
//! **Which state.** Each saved exhibit's `crashed` snapshot, kept past its world by the loop,
//! rebuilt in the state directory with `engine.restore` — the directory after the loop holds the
//! baseline's result with the world checker's work on top, not the crash state. A snapshot
//! holds names, kinds and contents and nothing else, so the rebuilt state carries restore-time
//! timestamps and the engine's fixed modes: a recovery that decides by modification time or by
//! permission sees every file as new and every mode as 0644/0755. The report says so rather than
//! the result pretending otherwise.
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
const capture = @import("capture.zig");
const files = @import("files.zig");
const report = @import("report.zig");
const containment = @import("containment.zig");

/// One saved exhibit's world: its crash point and the crash state the loop kept for it.
pub const Exhibit = struct {
    k: u32,
    crashed: engine.Snapshot,
};

/// What one recovery leg established about one exhibit.
pub const Leg = struct {
    k: u32,
    result: contract.RecoveryResult,
    /// Wall clock for this leg: rebuilding the crash state, the command, the settle check and
    /// the checker. The two controls are counted once, in `Outcome.total_ms`.
    ms: u64,
    /// The recovery command's exit status when it exited; null when it was killed by a signal,
    /// timed out, or never started.
    command_exit: ?u8,
    /// Why the result is what it is, in one clause, for the account line.
    why: []const u8,
    /// Processes the recovery command left running when it exited, which its cgroup stopped.
    stopped: Stopped = .{},
    /// A process the command or the checker started outlived the kill of its cgroup: it is still
    /// running, and `claimAfter` keeps the next leg from running beside it.
    survivor: bool = false,
};

/// Processes a contained command left when it exited, stopped by its cgroup — a repair it had
/// handed to one of them was cut short, and the account says so. Zero where the leg was not
/// contained, where nothing was left, or where no command ran.
pub const Stopped = struct {
    count: u32 = 0,
    /// More were left than the engine counts one by one.
    more: bool = false,
};

/// Whether the claim exhibit's leg may run after the earliest's. Null when it may; otherwise why
/// it is `unknown` without running: a process the earliest's leg could not stop is still there,
/// and the claim leg would be judged with it (diff review, second round).
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
    /// `--world-timeout` in milliseconds, applied to the command, the checker and the probe
    /// alike. Null means no budget: a recovery that never ends holds the run, as a checker does.
    budget_ms: ?u64,
    stop_when_orphaned: bool,
    startup_ppid: c_int,
};

pub const Outcome = struct {
    earliest: ?Leg,
    /// The claim exhibit's leg. When both exhibits are one world it is the same leg, run once.
    checker: ?Leg,
    /// Both controls plus every leg, in milliseconds.
    total_ms: u64,
    /// Whether the recovery checker rejected the corrupted state and accepted what the recovery
    /// left on the completed one. When false, every leg is `unknown` with the reason.
    trusted: bool,
};

/// The file contents the probe writes: distinct per file, so a checker that compares two files
/// with each other (`cmp out.txt in.txt`, the shape a recovery check most often takes) is not
/// handed two equal files and passed. The engine's own `corruptState` writes one string to
/// every file, which is enough for the define's checker and not for this one.
pub const probe_prefix = "sideeye-recovery-probe:";
/// Where every symlink points during the probe: a name that exists nowhere.
pub const probe_link_target = "sideeye-recovery-probe-target";

/// A copy of `from` with every file's contents replaced by `probe_prefix` and its own relative
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
        try snap.entries.append(a, .{ .rel = try a.dupe(u8, e.rel), .kind = e.kind, .content = content });
    }
    try engine.finalizeEntries(&snap);
    return snap;
}

/// How a recovery command's end reads, before the checker runs: `null` means the command ran
/// and ended and the checker should decide; otherwise the leg is `unknown` for the reason given.
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

/// How a recovery checker's end reads: the result, and why when it is `unknown`.
pub fn checkerEnd(term: posix.Term) struct { result: contract.RecoveryResult, why: []const u8 } {
    return switch (term) {
        .exited => |c| switch (c) {
            0 => .{ .result = .pass, .why = "the recovery checker accepted the recovered state" },
            125 => .{ .result = .unknown, .why = "the recovery checker could not enter the declared cwd, or exited 125 (indistinguishable here)" },
            126 => .{ .result = .unknown, .why = "the recovery checker could not be arranged before exec (exit 126)" },
            127 => .{ .result = .unknown, .why = "the recovery checker could not be executed (exit 127)" },
            else => .{ .result = .fail, .why = "the recovery checker rejected the recovered state" },
        },
        // As the world checker is read: a checker that did not exit normally did not accept.
        .signaled => .{ .result = .fail, .why = "the recovery checker was killed by a signal" },
        .unknown => .{ .result = .unknown, .why = "the recovery checker ended in a status the engine does not decode" },
    };
}

fn orphaned(ctx: Context) bool {
    return ctx.stop_when_orphaned and posix.getppid() != ctx.startup_ppid;
}

/// Run a child the way a recovery leg does: captured (both streams, re-emitted with `label` on
/// every line), under the run's world budget, with the state directory in its environment.
/// `error.TimedOut`, `error.LeftRunning` and every spawn error come back to the caller to become
/// `unknown`.
///
/// Contained where the engine can make cgroups, as each world is (#559, ADR 0065): everything the
/// child started — a daemon that left its process group included — is stopped when the child
/// exits, so what one leg starts cannot answer for the next (review: a `pg_ctl start` left by
/// the baseline control would make the next leg's start fail, and read `fail`). Elsewhere only
/// the child's process group is stopped, and `docs/cli.md` names that limit.
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
    // Held and not emptied by its kill: something the child started is still running, and what it
    // does from here is not this leg's to report.
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

/// One exhibit's leg: its crash state rebuilt, then `on`.
fn leg(ctx: Context, d: Declared, ex: Exhibit) Leg {
    const tag = std.fmt.allocPrint(ctx.arena, "{d}", .{ex.k}) catch
        return unknownLeg(ex.k, posix.monotonicMs(), null, "out of memory");
    return on(ctx, d, ex.k, ex.crashed, tag, "");
}

/// Rebuild `state`, run the recovery command, see the state stop changing, run the checker.
/// `tag` names the capture files (`recovery-<tag>.txt`) and `label` goes between `recovery` and
/// the colon on every re-emitted line, so the baseline control's output is never read as a
/// crash leg's.
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

/// The accept-side control, the world loop's baseline carried over: the completed, uncrashed
/// state, the recovery run on it, and the checker must accept what it left. Null when it did;
/// otherwise why no exhibit's result can be trusted.
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

/// Every recovery leg this run owes: the two controls once, then the earliest exhibit, then the
/// claim exhibit unless it is the same world. `earliest` is null when the run has no FAIL, and
/// then nothing runs.
pub fn run(ctx: Context, d: Declared, final: engine.Snapshot, earliest: ?Exhibit, claim: ?Exhibit) Outcome {
    const started = posix.monotonicMs();
    const first = earliest orelse return .{ .earliest = null, .checker = null, .total_ms = 0, .trusted = false };

    if (falsify(ctx, d, final) orelse baseline(ctx, d, final)) |why| {
        // No leg ran, so no exhibit carries time: the controls' time is the account's.
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

/// The report's `recovery` account: what ran, against which saved worlds, how long it took, and
/// what the result rests on. One sentence built once, read by the text line and the JSON field
/// alike. `failing_worlds` is the run's violation count, so the account says how many failing
/// worlds were not saved and so were not recovered — a saved world does not stand for the
/// others (the exploration-cost record measured failing worlds as distinct from each other).
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
        "configured; the recovery checker was trusted after two controls (corrupted state -> recovery check failed; completed state, recovery run on it -> recovery check passed); crash point {s}{s}; ran against {d} of {d} failing world(s), the saved ones, in {d}.{d:0>3}s; the crash states were rebuilt from snapshots, so contents are as the crash left them and timestamps and permissions are not",
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
    // The defect this exists for: `corruptState` writes one string to every file, so two files
    // that were equal before stay equal after, and `cmp in out` exits 0 on the corrupted state.
    try t.expect(!std.mem.eql(u8, in.content, out.content));
    try t.expect(std.mem.startsWith(u8, in.content, probe_prefix));
    try t.expect(!std.mem.eql(u8, in.content, "same"));
    try t.expectEqual(from.entries.items.len, probe.entries.items.len);
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
    // A non-zero exit is still a recovery that ran: the checker decides what it left.
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
