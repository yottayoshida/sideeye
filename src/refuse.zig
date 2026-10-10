const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const boundary = @import("boundary.zig");
const defang = @import("defang.zig");
const report = @import("report.zig");
const files = @import("files.zig");
const image = @import("image.zig");
const textShown = defang.textShown;
const removeFile = files.removeFile;
const say = report.say;

pub var json_path: ?[]const u8 = null;
pub var json_arena: ?std.mem.Allocator = null;
fn readFailedStep(errno: ?c_int) contract.NextStep {
    const en = errno orelse return .environment;
    if (en == posix.EACCES or en == posix.EPERM) return .unreadable_entry_appeared;
    if (en == posix.ENOENT) return .quiesce;
    return .environment;
}

test "the step for an unreadable entry is chosen on the measured errno, and only a permission failure blames the user's access (#535)" {
    try std.testing.expectEqual(contract.NextStep.unreadable_entry_appeared, readFailedStep(posix.EACCES));
    try std.testing.expectEqual(contract.NextStep.unreadable_entry_appeared, readFailedStep(posix.EPERM));
    try std.testing.expectEqual(contract.NextStep.quiesce, readFailedStep(posix.ENOENT));
    try std.testing.expectEqual(contract.NextStep.environment, readFailedStep(posix.EIO));
    try std.testing.expectEqual(contract.NextStep.environment, readFailedStep(null));
}

/// `refuseUnsupportedEntry`, which defangs. A Unix name may hold newlines and escape
/// introducers; unlike the JSON side there is no second escaper behind the text.
pub fn snapshotOrRefuse(gpa: std.mem.Allocator, root: []const u8, what: []const u8) engine.Snapshot {
    var diag: engine.SnapshotDiag = .{};
    return engine.takeSnapshotCapped(gpa, root, engine.SnapshotCaps.shipped, &diag) catch |e| {
        // An allocation failure is an environment problem in either phase, the rule
        // `spawnFailure` already states. Routing it to UNKNOWN would leave a seam one
        // statement wide: this snapshot exiting 2 for OOM while the `classify` that
        // consumes it exits 3 for the same cause. The ruling on #351 listed it among the
        // errors to move; this is the deviation, taken deliberately and approved.
        if (e == error.OutOfMemory) setupError(.environment, what);

        // **Decided once, for every exit below.** Threading the reason through as a
        // parameter was the first design, and review counted what could then go wrong:
        // of the sites that refuse here, the no-measured-size branch and the no-arena
        // fallback (and, since #535, the empty-name fallbacks in `snapshotDetail`) are
        // reached by nothing, so any of them could have named the wrong reason with
        // every check in the tree still green. That is what #330
        // **Exhaustive over `SnapshotError` on purpose**, like `snapshotDetail` below and
        // for the same reason: an error member added later must not silently take a
        // neighbour's reason. The `if` this replaced would have handed `TreeTooLarge` the
        // catch-all with nothing to notice (#323).
        const answer: struct { reason: contract.UnknownReason, bare: []const u8, next: contract.NextStep, setup: contract.SetupErrorReason } = switch (e) {
            error.FileTooLarge => .{
                .reason = .state_file_too_large,
                .bare = "a state file is too large for byte-level judgment",
                .next = .narrow_state,
                .setup = .environment,
            },
            error.TreeTooLarge => .{
                .reason = .state_tree_too_large,
                .bare = "the state tree is too large to snapshot",
                .next = .narrow_state,
                .setup = .environment,
            },
            error.TooDeep,
            error.PathTooLong,
            => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
                .next = .narrow_state,
                .setup = .environment,
            },
            error.ReadFailed => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
                .next = readFailedStep(diag.entry.errno),
                .setup = .environment,
            },
            error.ClassifyFailed => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
                .next = .environment,
                .setup = .environment,
            },
            error.EntriesNotSortedUnique => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
                .next = .sideeye_defect,
                .setup = .internal,
            },
            error.OutOfMemory => unreachable, // refused above
        };
        const reason = answer.reason;

        if (json_arena) |ja| snapshotRefusal(reason, answer.setup, report.snapshotDetail(ja, e, what, &diag), answer.next);

        // Unreachable in practice: json_arena is assigned unconditionally before the
        // parse loop, ahead of every call site. Kept so this function's contract does
        // not depend on that ordering — but do not read it as a covered "no arena"
        // message path; nothing exercises it, including the split below. It is a split
        // rather than one string because the first draft let a `TooDeep` failure fall
        // through to the cap's wording here, which nothing would have caught.
        snapshotRefusal(reason, answer.setup, answer.bare, answer.next);
    };
}

test "a snapshot refusal for an unreadable entry names it, and the errno only when one was measured (#535)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var diag: engine.SnapshotDiag = .{};
    diag.entry.rel.set("m_inmail.6c3e.69");
    diag.entry.kind = .file;
    diag.entry.errno = posix.EACCES;
    const with = report.snapshotDetail(a, error.ReadFailed, "could not snapshot a crashed state", &diag);
    try std.testing.expect(std.mem.indexOf(u8, with, "m_inmail.6c3e.69 could not be read (file; errno ") != null);
    try std.testing.expect(std.mem.indexOf(u8, with, " EACCES)") != null);
    diag.entry.errno = null;
    diag.entry.kind = .symlink;
    const without = report.snapshotDetail(a, error.ReadFailed, "could not snapshot a crashed state", &diag);
    try std.testing.expect(std.mem.indexOf(u8, without, "m_inmail.6c3e.69 could not be read (symlink)") != null);
    try std.testing.expect(std.mem.indexOf(u8, without, "errno") == null);
    diag.entry.kind = .unclassified;
    const cls = report.snapshotDetail(a, error.ClassifyFailed, "could not snapshot a crashed state", &diag);
    try std.testing.expect(std.mem.indexOf(u8, cls, "m_inmail.6c3e.69 could not be classified") != null);
    try std.testing.expect(std.mem.indexOf(u8, cls, "errno") == null);
    var empty: engine.SnapshotDiag = .{};
    const bare = report.snapshotDetail(a, error.ReadFailed, "could not snapshot a crashed state", &empty);
    try std.testing.expectEqualStrings("could not snapshot a crashed state: a file or symlink inside the state tree could not be read", bare);
    try std.testing.expectEqualStrings(" EACCES", report.errnoName(posix.EACCES));
    try std.testing.expectEqualStrings("", report.errnoName(12345));
}

fn snapshotRefusal(reason: contract.UnknownReason, setup: contract.SetupErrorReason, detail: []const u8, next: contract.NextStep) noreturn {
    switch (run_phase) {
        .before_exploration => setupError(setup, detail),
        .exploring => unknown(reason, detail, next),
    }
}

/// Read a trace, or refuse. Pairs with `answerForOversizedTrace`, which every caller
/// must reach: forgetting the cap check at one site is the defect this exists to fix
/// (#324) — the world loop's read has no shim-marker branch to catch the collapse, so a
/// missed check there refused with `kill_did_not_land`, a claim about the engine's own
/// kill drawn from a trace it declined to read.
pub fn readTraceOrRefuse(path: []const u8, cap: usize, setup_msg: []const u8) engine.TraceInfo {
    // Not `.?`: an ordering mistake should report itself rather than panic. It cannot
    // happen today — `main` installs the budget before any argument is parsed — and a
    // local budget could not stand in if it could, because the `TraceInfo` returned here
    // outlives this frame and frees through the budget's child.
    const b = trace_budget orelse setupError(.internal, "internal: a trace was read before the whole-trace ceiling was installed");
    return engine.readTraceCapped(b, path, cap) catch setupError(.environment, setup_msg);
}

/// The cost of the split, stated because it is the defect this issue is about: nothing
/// forces a caller to reach this. A read site can read and never answer, which is
/// exactly how the world loop came to refuse with `kill_did_not_land`. What holds it
/// instead is the acceptance leg, which drives the recording and world sites through
/// lowered-cap engines and fails on the reason rather than the exit code; a site added
/// without an answer has no leg and is caught in review, not by the compiler.
pub fn answerForOversizedTrace(t: engine.TraceInfo, where: []const u8, cap: usize) void {
    if (t.too_large) traceTooLarge(t.too_large_size, where, cap);
    // The whole-trace ceiling answers HERE, beside the per-read cap, rather than at the
    // read (#377). Both refusals are structural UNKNOWNs, and this is the point every
    // caller already reaches after classifying — refusing at the read instead cost the
    // recording site its L0 account, measured as `atomicity: not classified`, because
    // the final snapshot had not been taken yet.
    if (t.budget_refused) |want| {
        if (trace_budget) |b| traceBudgetExhausted(want, where, b.limit);
    }
}

/// counted the sites and found three.) The size appears only when
/// `lseek` measured it — a size nobody measured must not appear in the message, the
/// rule the per-file cap's refusal already follows.
fn traceTooLarge(size: ?u64, where: []const u8, cap: usize) noreturn {
    if (json_arena) |ja| {
        if (size) |sz|
            unknown(.trace_too_large, std.fmt.allocPrint(ja, "the trace from {s} is larger than this engine will read: {d} bytes against a {d}-byte cap; {s}'s account is complete, but the engine declined to hold it", .{ where, sz, cap, boundary.recorder() }) catch "the trace is larger than this engine will read", .narrow_state)
        else
            unknown(.trace_too_large, std.fmt.allocPrint(ja, "the trace from {s} is larger than this engine will read (over the {d}-byte cap); {s}'s account is complete, but the engine declined to hold it", .{ where, cap, boundary.recorder() }) catch "the trace is larger than this engine will read", .narrow_state);
    }
    // Unreachable in practice for the same reason snapshotOrRefuse's fallback is:
    // json_arena is assigned before the parse loop, ahead of every call site. Kept so
    // this function does not depend on that ordering; nothing exercises it.
    unknown(.trace_too_large, "the trace is larger than this engine will read", .narrow_state);
}

fn traceBudgetExhausted(wanted: usize, where: []const u8, limit: usize) noreturn {
    if (json_arena) |ja| {
        unknown(.trace_budget_exhausted, std.fmt.allocPrint(ja, "reading the trace from {s} would have taken this engine past the ceiling every trace it holds at once must fit under: a {d}-byte allocation against a {d}-byte ceiling. Each trace involved may be well under the per-read cap — what ran out is the sum", .{ where, wanted, limit }) catch "the engine's whole-trace ceiling was reached", .narrow_state);
    }
    unknown(.trace_budget_exhausted, "the engine's whole-trace ceiling was reached", .narrow_state);
}

/// A pointer rather than the object: the object lives as a local in `main`, which
/// outlives every `TraceInfo` built on it — a budget that died first would leave those
/// arenas holding a dangling child allocator to free through.
pub var trace_budget: ?*engine.TraceBudget = null;

const LiveSidecar = struct { pid: c_int, gpa: std.mem.Allocator };
pub var fsu_live: ?LiveSidecar = null;

/// The observer's capture file, from spawn until it has been read. A `defer` on the
/// block that stopped the observer removed it — at that block's closing brace, forty
/// lines before the comparison opened it, so the comparison read nothing and the run
/// refused with "could not be read". Measured on an otherwise green end-to-end run.
pub var fsu_capture: ?[]const u8 = null;

pub fn dropCapture() void {
    const c = fsu_capture orelse return;
    fsu_capture = null;
    removeFile(c);
}

pub fn stopLiveSidecar() posix.SidecarEnd {
    const live = fsu_live orelse return .had_exited;
    fsu_live = null;
    return posix.stopSidecar(live.gpa, live.pid, &.{ "/usr/bin/sudo", "-n" }, 5000);
}

pub fn unknown(reason: contract.UnknownReason, detail: []const u8, next: contract.NextStep) noreturn {
    _ = stopLiveSidecar();
    dropCapture();
    const next_step = next.render();
    if (json_path) |jp| if (json_arena) |ja|
        report.writeJsonReport(ja, jp, "UNKNOWN", @intFromEnum(contract.ExitCode.unknown), null, null, reason.name(), null, detail, next_step);
    // `next` sits AFTER the detail line: the acceptance suite reads the detail as the line
    // that follows `UNKNOWN  <reason>`, and that contract predates this line. `processes`
    // goes in the lower block for the same reason and joins the other verdicts there (#123):
    say(
        \\{s}  {s}
        \\         {s}
        \\next        {s}
        \\
    , .{ report.paint("UNKNOWN"), reason.name(), detail, next_step });
    // #337: the same value the JSON carries, on its own line, and only when there is one
    // — a `divergence` line reading empty would be a field pretending to an answer. After
    // `next`, before the classification block, so the two lines the acceptance suite
    // anchors on (the reason, and the detail beneath it) keep their positions.
    if (report.divergence_syscall.len > 0) say("divergence  {s}\n", .{report.divergence_syscall});
    report.sayAccount(json_arena orelse std.heap.page_allocator, .unknown, 0);
    say(
        \\
        \\Sideeye could not judge this run. That is not a pass: the exit code is 2 so a
        \\caller has to decide deliberately what to do with it.
        \\
    , .{});
    report.emitSeal();
    std.process.exit(@intFromEnum(contract.ExitCode.unknown));
}

pub fn requireCompleteness(arena: std.mem.Allocator, has_oracle: bool, allow_unverified: bool) void {
    if (has_oracle or allow_unverified) return;
    const base = if (boundary.observe_mode == .supervised)
        "no oracle was given, so the supervising engine's account of what happened was not checked against anything; pass --oracle, or --allow-unverified to accept the weaker claim"
    else if (builtin.os.tag == .macos)
        "no oracle was given, so the shim's account of what happened was not checked against anything; pass --oracle-fs-usage (run sudo -v first, in the same terminal), or --allow-unverified to accept the weaker claim"
    else
        "no oracle was given, so the shim's account of what happened was not checked against anything; pass --oracle, or --allow-unverified to accept the weaker claim";
    // A discovered strace is only ever NAMED here, never attached: a second witness
    // joining on its own would silently strengthen what a flagless verdict claims —
    // and flip every caller that measured the no-oracle behavior (#78).
    const msg = if (findStraceForHint(arena)) |s|
        std.fmt.allocPrint(arena, "{s} (strace is on this machine: pass --oracle {s})", .{ base, s }) catch base
    else
        base;
    unknown(.completeness_not_verified, msg, .pass_oracle);
}

pub fn findStraceForHint(arena: std.mem.Allocator) ?[]const u8 {
    if (builtin.os.tag != .linux) return null;
    const path_env = posix.getenv("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, std.mem.span(path_env), ':');
    while (it.next()) |dir| {
        if (dir.len == 0 or dir[0] != '/') continue;
        var zb: [contract.max_path]u8 = undefined;
        const z = std.fmt.bufPrintZ(&zb, "{s}/strace", .{dir}) catch continue;
        if (posix.access(z.ptr, posix.X_OK) == 0)
            return arena.dupe(u8, z) catch null;
    }
    return null;
}

/// Every path and name here came from the define, so each goes through `textShown`.
pub fn unstartable(arena: std.mem.Allocator, role: []const u8, argv: []const []const u8, cwd: ?[]const u8) ?[]const u8 {
    if (argv.len == 0) return null;
    const s = image.startable(arena, argv[0], cwd, if (std.c.getenv("PATH")) |p| std.mem.span(p) else null);
    const file = textShown(arena, s.file orelse "");
    const name = textShown(arena, s.name orelse "");
    if (s.interpreter) |raw| {
        const interp = textShown(arena, raw);
        return switch (s.fault) {
            .ok, .not_judged => return null,
            .missing => std.fmt.allocPrint(arena, "{s}: {s} names #! interpreter {s}, which does not exist", .{ role, file, interp }),
            .not_regular => std.fmt.allocPrint(arena, "{s}: {s} names #! interpreter {s}, which is not a regular file", .{ role, file, interp }),
            .no_exec_bit => std.fmt.allocPrint(arena, "{s}: {s} names #! interpreter {s}, which exists but this user may not execute", .{ role, file, interp }),
            .unreachable_path => |e| std.fmt.allocPrint(arena, "{s}: {s} names #! interpreter {s}, which could not be examined (errno {d}{s})", .{ role, file, interp, e, report.errnoName(e) }),
            .not_on_path => std.fmt.allocPrint(arena, "{s}: {s} names #! interpreter {s} {s}, and no executable file named {s} is on PATH", .{ role, file, interp, name, name }),
        } catch "a define command cannot be started";
    }
    return switch (s.fault) {
        .ok, .not_judged => return null,
        .missing => std.fmt.allocPrint(arena, "{s}: {s} does not exist", .{ role, file }),
        .not_regular => std.fmt.allocPrint(arena, "{s}: {s} is not a regular file, so it cannot be executed", .{ role, file }),
        .no_exec_bit => std.fmt.allocPrint(arena, "{s}: {s} exists but this user may not execute it (no execute bit, or a noexec mount or an ACL that denies it); Sideeye executes the file itself, as ./check.sh rather than sh check.sh", .{ role, file }),
        .unreachable_path => |e| std.fmt.allocPrint(arena, "{s}: {s} could not be examined (errno {d}{s}), so whether it exists is not known", .{ role, file, e, report.errnoName(e) }),
        .not_on_path => std.fmt.allocPrint(arena, "{s}: no executable file named {s} is on PATH", .{ role, name }),
    } catch "a define command cannot be started";
}

pub var toml_dir: ?[]const u8 = null;

pub fn cwdObservation(arena: std.mem.Allocator, argv: []const []const u8) ?[]const u8 {
    const dir = toml_dir orelse return null;
    if (report.command_cwd_declared) return null;
    const ran = report.command_cwd orelse return null;
    if (std.mem.eql(u8, dir, ran) or argv.len < 2) return null;
    for (argv[1..]) |word| {
        const v = if (word.len > 1 and word[0] == '-')
            (if (std.mem.indexOfScalar(u8, word, '=')) |eq| word[eq + 1 ..] else continue)
        else
            word;
        if (v.len == 0 or v[0] == '/') continue;
        var name: []const u8 = v;
        while (true) {
            if (existsUnder(arena, ran, name)) break;
            if (existsUnder(arena, dir, name))
                return std.fmt.allocPrint(arena, "{s} is under the toml's directory {s} and not under {s}, where the commands ran", .{ textShown(arena, name), textShown(arena, dir), textShown(arena, ran) }) catch null;
            const up = std.fs.path.dirname(name) orelse break;
            if (up.len == 0 or std.mem.eql(u8, up, ".") or std.mem.eql(u8, up, "..")) break;
            name = up;
        }
    }
    return null;
}

fn existsUnder(arena: std.mem.Allocator, dir: []const u8, rel: []const u8) bool {
    const p = std.fs.path.join(arena, &.{ dir, rel }) catch return false;
    const z = arena.dupeZ(u8, p) catch return false;
    return posix.access(z.ptr, posix.F_OK) == 0;
}

pub fn cwdStep(observation: ?[]const u8, step: contract.NextStep) contract.NextStep {
    if (observation == null) return step;
    return switch (step) {
        .fix_define, .run_then_expect_status, .run_by_hand_signalled => .declare_cwd,
        else => step,
    };
}

test "the cwd observation outranks the recording run's own steps, never the syscalls mode's (#710)" {
    try std.testing.expectEqual(contract.NextStep.declare_cwd, cwdStep("x", .run_then_expect_status));
    try std.testing.expectEqual(contract.NextStep.declare_cwd, cwdStep("x", .run_by_hand_signalled));
    try std.testing.expectEqual(contract.NextStep.run_then_expect_status, cwdStep(null, .run_then_expect_status));
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, cwdStep("x", .syscalls_may_have_killed));
    try std.testing.expectEqual(contract.NextStep.scratch_or_twice, cwdStep("x", .scratch_or_twice));
}

pub fn withObservation(arena: std.mem.Allocator, detail: []const u8, observation: ?[]const u8, step: ?contract.NextStep) []const u8 {
    const o = observation orelse return detail;
    if (step) |st| if (st == .declare_cwd) return std.fmt.allocPrint(arena, "{s}; {s}", .{ detail, o }) catch detail;
    return std.fmt.allocPrint(arena, "{s}; {s}: add cwd = \".\" under [define] to run the commands from the toml's directory", .{ detail, o }) catch detail;
}

test "cwdObservation names an argument found only under the toml's directory (#700)" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    var tb: [128]u8 = undefined;
    var rb: [128]u8 = undefined;
    const toml_z = try std.fmt.bufPrintZ(&tb, "/tmp/sideeye-cwdobs-toml-{d}", .{posix.getpid()});
    const ran_z = try std.fmt.bufPrintZ(&rb, "/tmp/sideeye-cwdobs-ran-{d}", .{posix.getpid()});
    _ = posix.mkdir(toml_z.ptr, 0o755);
    _ = posix.mkdir(ran_z.ptr, 0o755);
    var sb: [192]u8 = undefined;
    var bb: [192]u8 = undefined;
    var cb: [192]u8 = undefined;
    const seed = try std.fmt.bufPrintZ(&sb, "{s}/seed", .{toml_z});
    const both_t = try std.fmt.bufPrintZ(&bb, "{s}/both", .{toml_z});
    const both_r = try std.fmt.bufPrintZ(&cb, "{s}/both", .{ran_z});
    for ([_][:0]const u8{ seed, both_t, both_r }) |p| {
        const fd = posix.open(p.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        if (fd < 0) return error.SkipZigTest;
        _ = posix.close(fd);
    }
    defer {
        for ([_][:0]const u8{ seed, both_t, both_r }) |p| _ = posix.unlink(p.ptr);
        _ = posix.rmdir(toml_z.ptr);
        _ = posix.rmdir(ran_z.ptr);
    }
    const saved = .{ toml_dir, report.command_cwd, report.command_cwd_declared };
    defer {
        toml_dir = saved[0];
        report.command_cwd = saved[1];
        report.command_cwd_declared = saved[2];
    }
    toml_dir = toml_z;
    report.command_cwd = ran_z;
    report.command_cwd_declared = false;

    var db: [192]u8 = undefined;
    const state_t = try std.fmt.bufPrintZ(&db, "{s}/state", .{toml_z});
    _ = posix.mkdir(state_t.ptr, 0o755);
    defer _ = posix.rmdir(state_t.ptr);
    const nested = cwdObservation(a, &.{ "./cfgset", "./state/config.json", "theme" }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, nested, "./state is under the toml's directory "));
    const o = cwdObservation(a, &.{ "/bin/cp", "./seed", "out" }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, o, "./seed is under the toml's directory "));
    try std.testing.expect(cwdObservation(a, &.{ "tool", "--in=seed" }) != null);
    try std.testing.expectEqual(contract.NextStep.declare_cwd, cwdStep(o, .fix_define));
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, cwdStep(o, .syscalls_may_have_killed));
    try std.testing.expect(cwdObservation(a, &.{ "tool", "both", "nothing", "/abs/seed", "-v" }) == null);
    try std.testing.expect(cwdObservation(a, &.{"seed"}) == null);
    try std.testing.expectEqual(contract.NextStep.fix_define, cwdStep(null, .fix_define));
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, .declare_cwd), "add cwd") == null);
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, .syscalls_may_have_killed), "add cwd = \".\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, null), "add cwd = \".\"") != null);
    try std.testing.expectEqualStrings("d", withObservation(a, "d", null, null));
    report.command_cwd_declared = true;
    try std.testing.expect(cwdObservation(a, &.{ "tool", "./seed" }) == null);
    report.command_cwd_declared = false;
    report.command_cwd = toml_z;
    try std.testing.expect(cwdObservation(a, &.{ "tool", "./seed" }) == null);
    report.command_cwd = ran_z;
    toml_dir = null;
    try std.testing.expect(cwdObservation(a, &.{ "tool", "./seed" }) == null);
}

/// A setup error is a verdict too, and it has to reach the JSON.
///
/// It did not, and the file was neither written nor removed: a caller running twice into
/// the same `--json` path read the *previous* run's document as this run's result. Since
/// several of these fire mid-run — after the trace is read, after a world is restored —
/// that stale verdict could be a PASS for a run that never explored anything.
/// `restoreFailure`). The reason reaches the JSON as `setup_error_reason`; the text line
/// is unchanged, because its sentence already says what happened and the acceptance suite
/// reads the rest of that line as the detail.
pub fn setupError(reason: contract.SetupErrorReason, detail: []const u8) noreturn {
    _ = stopLiveSidecar();
    dropCapture();
    if (json_path) |jp| if (json_arena) |ja|
        report.writeJsonReport(ja, jp, "SETUP_ERROR", @intFromEnum(contract.ExitCode.setup_error), null, null, null, reason, detail, null);
    say("{s}  {s}\n", .{ report.paint("SETUP ERROR"), detail });
    report.emitSeal();
    std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
}

/// `phase` decides the verdict for `WaitFailed`, not just its wording. A child *ran* and
/// its status was never read, which is a statement about the target's execution, so while
/// worlds are being explored it has to be UNKNOWN — the distinction `recording_run_failed`
/// and `baseline_run_failed` already draw for the same phase. A first version of #264's
/// fix sent every call site to `setupError` and would have published
/// `verdict: "SETUP_ERROR"` for a mid-exploration wait failure: honest about the failure,
/// wrong about what it was about, and a silent change to the serialized shape.
const SpawnPhase = enum {
    before_exploration,
    exploring,
};

/// The phase the snapshot cap reads (#330). A *variable* rather than an argument
/// threaded through `snapshotOrRefuse`, and the difference is what can be verified:
/// `snapshotOrRefuse` has one call site before the recording run and the rest at or
/// past it, and an acceptance leg can only reach one of the later ones. Passed as an
/// argument, the others could name the wrong phase and every check in the tree would
/// stay green. Assigned once, immediately before the recording run, a per-site mistake is not
/// representable at all — what remains is where the single assignment sits, and the two
/// legs bound that from both sides: move it above the initial snapshot and check 2fc goes
/// red, delete it and check 2fd does. **They bound an interval, not a point** — measured,
/// by moving the assignment down to just above the final snapshot, where both legs stay
/// green because nothing between reads the variable. What is pinned is that the
/// assignment lies after the initial snapshot and at or before the final one.
///
/// Another call site added above this assignment would be misread, and no check would
/// say so — the same gap `answerForOversizedTrace` states for its own sites: caught in
/// review, not by the compiler.
pub var run_phase: SpawnPhase = .before_exploration;

pub fn spawnFailure(e: posix.ContainedSpawnError, phase: SpawnPhase, doing: []const u8) noreturn {
    // The SETUP_ERROR class, decided once for the whole error set (#518): every member is
    // the engine needing something of the machine — a fork, memory, a descriptor, a capture,
    // a wait, a cgroup — so every arm is `environment`, and the switch is exhaustive so a
    // member added to `ContainedSpawnError` has to be given a class here rather than inherit one.
    const reason: contract.SetupErrorReason = switch (e) {
        error.ForkFailed, error.OutOfMemory, error.WaitFailed, error.StdinUnavailable, error.CaptureUnavailable, error.CgroupJoinFailed => .environment,
    };
    if (e == error.WaitFailed) {
        const detail = "a child process ran, but its exit status could never be read: the wait was interrupted repeatedly, or failed permanently. Every verdict here rests on how that child ended, so the run refuses instead of deriving one from a status that was never written";
        switch (phase) {
            .before_exploration => setupError(reason, detail),
            .exploring => unknown(.child_wait_failed, detail, .retry_then_report),
        }
    }
    if (e == error.StdinUnavailable) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: /dev/null could not be opened, so the command could not be started with its stdin at end-of-file", .{doing}) catch doing);
    }
    // **This arm is not enforced by the compiler.** The chain above is a run of `if`s
    // ending in a bare `setupError(doing)`, so a member of `SpawnError` with no arm here
    // is not a build error — it silently becomes "could not run --operation" with no
    // reason. Adding a member to that error set means adding a line here, and the only
    // thing that says so is this paragraph and the acceptance leg that reads the text.
    if (e == error.CaptureUnavailable) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: the command's stdout capture in the work directory could not be opened. The engine refuses a capture path that is a symlink, or that already holds a file or directory the engine did not just create — check --work, and what is at the capture path inside it", .{doing}) catch doing);
    }
    if (e == error.CgroupJoinFailed) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: the engine could not arrange the run's cgroup — make it, open the pipe its child waits on, or move the child into it — so nothing of the command ran (a child already forked was killed first). Its own cgroup took a move and a new child cgroup when it was probed, so look at what changed since: permissions or limits on the cgroup, or the descriptors the engine may still open", .{doing}) catch doing);
    }
    setupError(reason, doing);
}

/// #5's demotion, shared by the three snapshot sites: a state tree holding an entry
/// `restore` cannot recreate must not be explored — every world would run against a
/// tree the recording run never had, and the crash points were derived from the
/// recording run. Ordering is deliberate at every call site: snapshot-trust
/// detectors (the oracle's defined-list scrutiny, quiescence) come first, this
/// demotion second, judgement last — so an existing refusal's reason is never
/// overtaken. The entry name reaches the text through the same non-bloating
/// defang as every other target-chosen string (#26/#167); `phase` says which
/// snapshot saw it. Returns only when the snapshot is clean.
pub fn refuseUnsupportedEntry(arena: std.mem.Allocator, snap: engine.Snapshot, phase: []const u8) void {
    if (engine.firstUnsupportedEntry(snap)) |rel| {
        const detail = std.fmt.allocPrint(
            arena,
            "the state directory holds an entry that is neither a regular file, a directory nor a symlink ({s}: {s}) — restore cannot recreate it, so every explored world would run against a tree the recording run never had",
            .{ phase, textShown(arena, rel) },
        ) catch "the state directory holds an entry that restore cannot recreate (a FIFO, socket or device)";
        unknown(.unsupported_state_entry, detail, .class_wall);
    }
}

/// The count itself is never truncated — a caller reading three names must still be
/// told the run had thirty.
const unaccounted_shown = 4;

/// Returns only when every difference is accounted for, or is inside a subtree a
/// recorded `rename` moved in. That second clause is a window, not a proof, and the
/// report says how wide it is rather than leaving it to a comment: the source of such a
/// rename was never snapshotted (for `papis add` it lives outside the judged root
/// entirely), so which descendants arrived with the move cannot be recovered from
/// anything this run holds.
pub fn reconcileOrRefuse(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    initial: engine.Snapshot,
    final: engine.Snapshot,
    ops: []const engine.Op,
    root: []const u8,
    alt: []const u8,
) void {
    // The differences are walked a second time here — `snapshotsEqual` above already
    // asked whether there were any — and that duplication is deliberate. Folding the two
    // would mean the zero-ops detector and this one shared a computation, and the first
    // is a frozen member whose firing condition must not move because the second wanted
    // a value. The cost is one linear merge over a tree whose largest committed instance
    // holds twenty-nine entries.
    const cap = initial.entries.items.len + final.entries.items.len + 1;
    const diffs = gpa.alloc(engine.Difference, cap) catch setupError(.environment, "out of memory");
    defer gpa.free(diffs);
    const dc = engine.diffSnapshots(initial, final, diffs);
    if (dc.equal()) return;

    const found = gpa.alloc(engine.Unaccounted, dc.stored + 1) catch setupError(.environment, "out of memory");
    defer gpa.free(found);

    // Reading the live tree instead would answer about the tree after the run, not the
    // one the operation crossed.
    var links: std.ArrayList(engine.Link) = .empty;
    engine.collectLinks(arena, initial, final, &links) catch setupError(.environment, "out of memory");
    const scratch = gpa.alloc(u8, 2 * contract.max_path) catch setupError(.environment, "out of memory");
    defer gpa.free(scratch);

    const r = engine.reconcile(diffs[0..dc.stored], ops, links.items, root, alt, scratch, found);

    report.attributed_to_rename = r.by_rename_prefix;
    if (r.by_rename_prefix > 0)
        report.l0_note = std.fmt.allocPrint(
            arena,
            "{s}; {d} path(s) attributed to a directory a recorded rename moved in from outside the judged root, and not individually accounted for — that source subtree was never snapshotted, so what arrived with the move and what an unrecorded writer added afterwards cannot be told apart",
            .{ report.l0_note, r.by_rename_prefix },
        ) catch report.l0_note;

    if (r.clean()) return;

    // `written` rather than `shown`: an allocation failure mid-list leaves a shorter one,
    // and a count computed from what was *intended* would then describe a list that was
    // never printed — the detail would read "incomplete: a and 3 more" with two names
    // missing and nothing saying so.
    var names: std.ArrayList(u8) = .empty;
    var written: usize = 0;
    for (found[0..@min(r.stored, unaccounted_shown)]) |u| {
        if (written > 0) names.appendSlice(arena, ", ") catch break;
        names.appendSlice(arena, textShown(arena, u.rel)) catch break;
        written += 1;
    }
    if (written == 0) names.appendSlice(arena, "(the names could not be rendered)") catch {};
    const more = if (r.total > written)
        std.fmt.allocPrint(arena, " and {d} more", .{r.total - written}) catch ""
    else
        "";
    const detail = std.fmt.allocPrint(
        arena,
        "the judged state changed at {d} path(s) that no recorded operation names, so the account of this run is incomplete: {s}{s}. {s}",
        .{ r.total, names.items, more, if (boundary.observe_mode == .supervised)
            "The supervising engine records the calls its filter watches, in the target and the processes it starts; a change made another way — through a mapped file, say, or by a process the target did not start — leaves no record at all"
        else
            "The shim records what crosses libc; a raw syscall, or a process that never loaded it, leaves no record at all" },
    ) catch "the judged state changed at a path that no recorded operation names";
    unknown(.state_changed_unaccounted, detail, .class_wall);
}

pub const Judgeable = struct {
    touched: u32,
    one_sided: bool,
    judged: usize,
};

pub fn measureJudgeable(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    initial: engine.Snapshot,
    final: engine.Snapshot,
    plan: engine.L0Plan,
    ops: []const engine.Op,
    root: []const u8,
    alt: []const u8,
) Judgeable {
    var links: std.ArrayList(engine.Link) = .empty;
    engine.collectLinks(arena, initial, final, &links) catch setupError(.environment, "out of memory");
    const scratch = gpa.alloc(u8, 2 * contract.max_path) catch setupError(.environment, "out of memory");
    defer gpa.free(scratch);
    return .{
        .touched = countTouched(plan, ops, links.items, root, alt, scratch),
        .one_sided = hasOneSidedEntry(plan, initial, final),
        .judged = plan.files.items.len,
    };
}

fn countTouched(plan: engine.L0Plan, ops: []const engine.Op, links: []const engine.Link, root: []const u8, alt: []const u8, scratch: []u8) u32 {
    var n: u32 = 0;
    for (plan.files.items) |f| {
        const changed = f.pre_kind != f.post_kind or !std.mem.eql(u8, f.pre_content, f.post_content);
        if (changed or engine.namedByMutation(f.rel, ops, links, root, alt, scratch)) n +|= 1;
    }
    return n;
}

fn hasOneSidedEntry(plan: engine.L0Plan, pre: engine.Snapshot, post: engine.Snapshot) bool {
    for (post.entries.items) |e| if (pre.find(e.rel) == null and !plan.isScratch(e.rel)) return true;
    for (pre.entries.items) |e| if (post.find(e.rel) == null and !plan.isScratch(e.rel)) return true;
    return false;
}

pub fn checkerArgv(split: anyerror![]const []const u8) []const []const u8 {
    const cargv = split catch setupError(.define_invalid, "--check is empty");
    if (cargv.len == 0) setupError(.define_invalid, "--check is empty");
    return cargv;
}

pub fn refuseNothingToCorrupt(initial: engine.Snapshot) void {
    if (engine.countCorruptible(initial) == 0)
        unknown(.checker_not_falsified, "the state directory holds no files or symlinks, so there was nothing to corrupt and the checker could not be tested", .fix_define);
}

pub fn refuseNoCrashPoint(arena: std.mem.Allocator, has_oracle: bool, observation: ?[]const u8) noreturn {
    const who = boundary.recorder();
    const detail = if (has_oracle)
        "the operation performed no state-changing operation inside the state directory, so there was no crash point and no world in which anything could fail"
    else
        std.fmt.allocPrint(arena, "{s} recorded no state-changing operation inside the state directory, so there was no crash point and no world in which anything could fail; no oracle ran, so an operation {s} did not see is not ruled out", .{ who, who }) catch
            "no state-changing operation was recorded inside the state directory, so there was no crash point and no world in which anything could fail; no oracle ran, so an operation that was not seen is not ruled out";
    const step: contract.NextStep = if (observation != null) .declare_cwd else .nothing_in_state;
    unknown(.nothing_could_fail, withObservation(arena, detail, observation, step), step);
}

/// Called after every world has run and before the PASS is printed — a world may take a branch
/// the recording did not, and a FAIL there exits before this; moved ahead of the worlds, it
/// would refuse a run that had a counterexample to show. Not called for a replay: its one world
/// answers whether that world still fails, and a fix that moves the marker after the last
/// operation leaves the replayed world with nothing to judge and a true answer (R1 of the plan, M4).
pub fn requireSomethingCouldFail(arena: std.mem.Allocator, j: Judgeable, checker: bool, marker_declared: bool, marker_worlds: u32) void {
    if (checker or j.touched > 0) return;
    if (marker_worlds > 0 and j.one_sided) return;
    const detail = std.fmt.allocPrint(
        arena,
        "no world could have failed: no checker was declared, {s}, and none of the {d} path(s) the built-in atomicity invariant judges was changed or named by a crash point",
        .{ if (!marker_declared) "no marker was declared" else if (marker_worlds == 0) "the marker printed in no crash world" else "the marker's invariant had no created or removed path to judge", j.judged },
    ) catch "no world could have failed: no checker, no marker world with anything to judge, and no judged path any crash point could change";
    unknown(.nothing_could_fail, detail, couldFailStep(j, marker_declared));
}

fn couldFailStep(j: Judgeable, marker_declared: bool) contract.NextStep {
    return if (marker_declared or !j.one_sided) .declare_check else .declare_check_or_marker;
}

test "a marker is offered only where one could judge something and none is declared (#683)" {
    try std.testing.expectEqual(contract.NextStep.declare_check_or_marker, couldFailStep(.{ .touched = 0, .one_sided = true, .judged = 1 }, false));
    try std.testing.expectEqual(contract.NextStep.declare_check, couldFailStep(.{ .touched = 0, .one_sided = false, .judged = 1 }, false));
    try std.testing.expectEqual(contract.NextStep.declare_check, couldFailStep(.{ .touched = 0, .one_sided = true, .judged = 1 }, true));
}

fn testPlanned(rel: []const u8, pre: []const u8, post: []const u8) engine.PlannedFile {
    return .{ .rel = rel, .pre_kind = .file, .post_kind = .file, .form = .standard, .pre_content = pre, .post_content = post };
}

test "a judged path counts as touched when it changed or a crash point named it, and not otherwise (#683)" {
    var plan: engine.L0Plan = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .files = .empty };
    defer plan.deinit();
    const a = plan.arena.allocator();
    try plan.files.append(a, testPlanned("keep.txt", "k", "k"));
    try plan.files.append(a, testPlanned("grown.txt", "g", "g2"));
    try plan.files.append(a, testPlanned("same.txt", "s", "s"));
    var scratch: [2048]u8 = undefined;
    const ops = [_]engine.Op{
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/same.txt.tmp", .aux = "/tmp/s/same.txt" },
        .{ .class = .fsync, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/keep.txt", .aux = "" },
        .{ .class = .mkdir, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
    };
    try std.testing.expectEqual(@as(u32, 2), countTouched(plan, &ops, &.{}, "/tmp/s", "", &scratch));
    var still: engine.L0Plan = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .files = .empty };
    defer still.deinit();
    try still.files.append(still.arena.allocator(), testPlanned("keep.txt", "k", "k"));
    try std.testing.expectEqual(@as(u32, 0), countTouched(still, &ops, &.{}, "/tmp/s", "", &scratch));
}

test "an entry only one snapshot holds is something the marker's invariant can judge, unless it is scratch (#683)" {
    const gpa = std.testing.allocator;
    var pre = try engine.testSnapshot(gpa, &.{.{ "keep.txt", "k" }});
    defer pre.deinit();
    var post = try engine.testSnapshot(gpa, &.{ .{ "keep.txt", "k" }, .{ "new.txt", "n" } });
    defer post.deinit();
    var plan: engine.L0Plan = .{ .arena = std.heap.ArenaAllocator.init(gpa), .files = .empty };
    defer plan.deinit();
    try std.testing.expect(hasOneSidedEntry(plan, pre, post));
    try std.testing.expect(!hasOneSidedEntry(plan, pre, pre));
    plan.scratch = &.{"new.txt"};
    try std.testing.expect(!hasOneSidedEntry(plan, pre, post));
}

pub fn setupErrorFmt(arena: std.mem.Allocator, reason: contract.SetupErrorReason, comptime fmt: []const u8, args: anytype) noreturn {
    setupError(reason, std.fmt.allocPrint(arena, fmt, args) catch fmt);
}

test "resolveFailure names the shallowest missing directory, and the errno otherwise (#486)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const deep = resolveFailure(arena, "/nope-for-test/a/b/leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, deep, "/nope-for-test does not exist") != null);
    try std.testing.expect(std.mem.indexOf(u8, deep, "the directory / does not exist") == null);

    const bare = resolveFailure(arena, "leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, bare, "no directory above it") != null);
    try std.testing.expect(std.mem.indexOf(u8, bare, "the directory . ") == null);

    const denied = resolveFailure(arena, "/x/y", @intFromEnum(std.posix.E.ACCES));
    try std.testing.expect(std.mem.indexOf(u8, denied, "ACCES") != null);
    const io = resolveFailure(arena, "/x/y", @intFromEnum(std.posix.E.IO));
    try std.testing.expect(std.mem.indexOf(u8, io, "IO") != null);

    const forged = resolveFailure(arena, "/nope-for-test\x1b[1m/leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, forged, "\x1b") == null);
}

/// Read the errno BEFORE any cleanup call — `rmdir`/`undoSetupMkdirs` overwrite it.
pub fn resolveFailure(arena: std.mem.Allocator, path: []const u8, err: c_int) []const u8 {
    if (err == posix.ENOENT) {
        const parent = std.fs.path.dirname(path) orelse
            return "it could not be resolved: ENOENT, and the name has no directory above it";
        var probe = parent;
        var walk = parent;
        while (true) {
            var zbuf: [contract.max_path]u8 = undefined;
            const z = std.fmt.bufPrintZ(&zbuf, "{s}", .{walk}) catch break;
            if (posix.isDirPath(z.ptr)) break;
            probe = walk;
            const up = std.fs.path.dirname(walk) orelse break;
            if (up.len == 0 or std.mem.eql(u8, up, walk)) break;
            walk = up;
        }
        // Target- and case-file-influenced (a replayed case supplies `define.state`),
        // so it goes through the same choke point the neighbouring refusals use (#266).
        return std.fmt.allocPrint(arena, "the directory {s} does not exist (the leaf is created, the parent is not)", .{textShown(arena, probe)}) catch
            "a directory above the leaf does not exist (the leaf is created, the parent is not)";
    }
    if (std.enums.tagName(std.posix.E, @as(std.posix.E, @enumFromInt(err)))) |tag|
        return std.fmt.allocPrint(arena, "it could not be resolved: {s} (errno {d})", .{ tag, err }) catch "it could not be resolved";
    return std.fmt.allocPrint(arena, "it could not be resolved (errno {d})", .{err}) catch "it could not be resolved";
}

/// Typed and exhaustive on purpose: a new member of `engine.RestoreError` must stop
/// compilation here rather than inherit `state_rewrite_failed` unexamined — the same
/// containment the snapshot's spawn-error switch keeps.
const RewriteDisposition = struct { exit: enum { setup, unknown }, detail: []const u8, next: contract.NextStep, setup_reason: contract.SetupErrorReason };

fn rewriteFailureDisposition(
    phase: SpawnPhase,
    e: engine.RestoreError,
    doing: []const u8,
) RewriteDisposition {
    const ends: struct { next: contract.NextStep, setup: contract.SetupErrorReason } = switch (e) {
        error.PathTooLong => .{ .next = .narrow_state, .setup = .define_invalid },
        error.UnsafeRoot, error.DeleteFailed, error.CreateFailed => .{ .next = .environment, .setup = .environment },
    };
    const detail: []const u8 = switch (e) {
        error.UnsafeRoot => "the state directory could not be confirmed as the one this run resolved: it now resolves elsewhere (a symlink or a moved parent), it is not a directory, it could not be read at all, or the path names a directory this run neither vetted nor created (one appeared, or replaced another, between the check and the open). Refusing destructive access to it",
        error.DeleteFailed, error.CreateFailed, error.PathTooLong => doing,
    };
    return .{
        .exit = switch (phase) {
            .before_exploration => .setup,
            .exploring => .unknown,
        },
        .detail = detail,
        .next = ends.next,
        .setup_reason = ends.setup,
    };
}

pub fn restoreFailure(e: engine.RestoreError, doing: []const u8) noreturn {
    const d = rewriteFailureDisposition(run_phase, e, doing);
    switch (d.exit) {
        .setup => setupError(d.setup_reason, d.detail),
        .unknown => unknown(.state_rewrite_failed, d.detail, d.next),
    }
}

test "a failed rewrite is SETUP_ERROR before exploration and UNKNOWN after, UnsafeRoot keeping its safety wording in both (#363)" {
    const doing = "could not restore the state directory";
    const errs = [_]engine.RestoreError{
        error.UnsafeRoot, error.DeleteFailed, error.CreateFailed, error.PathTooLong,
    };
    try std.testing.expectEqual(@as(usize, 4), @typeInfo(engine.RestoreError).error_set.?.len);
    for (errs) |e| {
        for ([_]SpawnPhase{ .before_exploration, .exploring }) |phase| {
            const d = rewriteFailureDisposition(phase, e, doing);
            try std.testing.expectEqual(phase == .exploring, d.exit == .unknown);
            if (e == error.UnsafeRoot) {
                try std.testing.expect(
                    std.mem.indexOf(u8, d.detail, "Refusing destructive access") != null,
                );
            } else {
                try std.testing.expectEqualStrings(doing, d.detail);
            }
            try std.testing.expectEqual(
                if (e == error.PathTooLong) contract.SetupErrorReason.define_invalid else contract.SetupErrorReason.environment,
                d.setup_reason,
            );
        }
    }
}
