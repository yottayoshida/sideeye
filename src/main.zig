const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");

pub const version = "0.1.0-dev";

var out_buf: [16 * 1024]u8 = undefined;

fn say(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&out_buf, fmt, args) catch return;
    var off: usize = 0;
    while (off < s.len) {
        const w = posix.write(1, s[off..].ptr, s.len - off);
        if (w <= 0) return;
        off += @intCast(w);
    }
}

const Args = struct {
    state: ?[]const u8 = null,
    setup: ?[]const u8 = null,
    operation: ?[]const u8 = null,
    shim: ?[]const u8 = null,
    work: []const u8 = "/tmp/sideeye-work",
};

fn usage() void {
    say(
        \\sideeye {s} (trace contract v{d})
        \\
        \\usage:
        \\  sideeye explore --state <dir> --operation <cmd> [--setup <cmd>] [--shim <lib>] [--work <dir>]
        \\
        \\  --state      directory whose contents define the target's state
        \\  --setup      command that produces the initial state (run once)
        \\  --operation  command to explore; killed before each of its file operations
        \\  --shim       path to libsideeye_shim.so
        \\  --work       scratch directory for traces (default /tmp/sideeye-work)
        \\
        \\exit codes: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR
        \\
    , .{ version, contract.contract_version });
}

fn unknown(reason: contract.UnknownReason, detail: []const u8) noreturn {
    say(
        \\UNKNOWN  {s}
        \\         {s}
        \\
        \\Sideeye could not judge this run. That is not a pass: the exit code is 2 so a
        \\caller has to decide deliberately what to do with it.
        \\
    , .{ reason.name(), detail });
    std.process.exit(@intFromEnum(contract.ExitCode.unknown));
}

fn setupError(detail: []const u8) noreturn {
    say("SETUP ERROR  {s}\n", .{detail});
    std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
}

/// Zig 0.16 passes the process's arguments and environment in; `std.process.argsAlloc`
/// no longer exists. The shape of `Init.Minimal` comes from `std.start.callMain`.
pub fn main(init: std.process.Init.Minimal) !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const argv = try init.args.toSlice(arena_state.allocator());

    if (argv.len < 2 or !std.mem.eql(u8, argv[1], "explore")) {
        usage();
        std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
    }

    var args: Args = .{};
    var i: usize = 2;
    while (i < argv.len) : (i += 2) {
        if (i + 1 >= argv.len) setupError("an option is missing its value");
        const v = argv[i + 1];
        if (std.mem.eql(u8, argv[i], "--state")) args.state = v
        else if (std.mem.eql(u8, argv[i], "--setup")) args.setup = v
        else if (std.mem.eql(u8, argv[i], "--operation")) args.operation = v
        else if (std.mem.eql(u8, argv[i], "--shim")) args.shim = v
        else if (std.mem.eql(u8, argv[i], "--work")) args.work = v
        else setupError("unknown option");
    }

    const state = args.state orelse setupError("--state is required");
    const operation = args.operation orelse setupError("--operation is required");
    const shim = args.shim orelse setupError("--shim is required in v0.1");

    // Resolve the state directory once, so every later comparison is against one
    // spelling of the path. The shim resolves what it sees the same way.
    var real_buf: [contract.max_path]u8 = undefined;
    var state_z_buf: [contract.max_path]u8 = undefined;
    const state_z = std.fmt.bufPrintZ(&state_z_buf, "{s}", .{state}) catch setupError("--state is too long");
    const state_abs = blk: {
        if (posix.realpath(state_z.ptr, &real_buf)) |p| break :blk std.mem.span(p);
        break :blk state;
    };

    var work_buf: [contract.max_path]u8 = undefined;
    const work_z = std.fmt.bufPrintZ(&work_buf, "{s}", .{args.work}) catch setupError("--work is too long");
    _ = posix.mkdir(work_z.ptr, 0o755);

    // ---- setup -------------------------------------------------------------------
    if (args.setup) |cmd| {
        const setup_argv = splitArgs(arena_state.allocator(), cmd) catch setupError("--setup is empty");
        if (setup_argv.len == 0) setupError("--setup is empty");
        const term = posix.runChild(gpa, setup_argv, &.{
            .{ "TOY_STATE", state_abs },
        }) catch setupError("could not run --setup");
        switch (term) {
            .exited => |code| if (code != 0) setupError("--setup exited non-zero"),
            else => setupError("--setup did not exit normally"),
        }
    }

    var initial = engine.takeSnapshot(gpa, state_abs) catch setupError("could not snapshot the initial state");
    defer initial.deinit();

    // ---- recording run -----------------------------------------------------------
    var rec_trace_buf: [contract.max_path]u8 = undefined;
    const rec_trace = std.fmt.bufPrint(&rec_trace_buf, "{s}/trace-record.bin", .{args.work}) catch setupError("path too long");
    removeFile(rec_trace);

    const op_argv = splitArgs(arena_state.allocator(), operation) catch setupError("--operation is empty");
    if (op_argv.len == 0) setupError("--operation is empty");

    const rec_term = posix.runChild(gpa, op_argv, &.{
        .{ "TOY_STATE", state_abs },
        .{ contract.env.state_dir, state_abs },
        .{ contract.env.trace_path, rec_trace },
        .{ "LD_PRELOAD", shim },
    }) catch setupError("could not run --operation");
    _ = rec_term;

    var trace = engine.readTrace(gpa, rec_trace) catch setupError("could not read the trace");
    defer trace.deinit();

    var final = engine.takeSnapshot(gpa, state_abs) catch setupError("could not snapshot the final state");
    defer final.deinit();

    // ---- structural detectors, before exploring anything --------------------------
    //
    // These run first on purpose. Exploring N worlds on top of a recording run that
    // cannot be trusted only multiplies the untrustworthiness — and every one of those
    // worlds would produce a verdict that looks just as confident.

    if (trace.version_mismatch)
        unknown(.contract_version_mismatch, "the shim was built against a different trace contract than this engine");

    if (!trace.saw_shim_ready)
        unknown(.no_shim_marker, "the shim never initialised: statically linked, hardened, or not injected at all");

    if (trace.boundary) |b| switch (b) {
        .fork, .exec => unknown(.child_process_detected, "the target created a child process; v0.1 explores single-process targets"),
        .thread => unknown(.multiple_threads_detected, "the target created a thread; operation order would not be deterministic"),
        else => {},
    };

    if (!snapshotsEqual(initial, final) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed while zero mutating operations were recorded: operations were missed");

    const n = trace.kill_point_count;
    if (n == 0) {
        say(
            \\PASS  the operation performed no state-directory operations
            \\      explored 0 crash points; nothing to kill before
            \\      not tested: power loss, torn writes, concurrent processes
            \\
        , .{});
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // ---- exploration --------------------------------------------------------------
    var explored: u32 = 0;
    var failures: u32 = 0;
    var first_failure: ?engine.WorldResult = null;
    var first_failure_path: [contract.max_path]u8 = undefined;
    var first_failure_path_len: usize = 0;

    var k: u32 = 1;
    while (k <= n + 1) : (k += 1) {
        engine.restore(initial, state_abs) catch setupError("could not restore the state directory");

        var kbuf: [16]u8 = undefined;
        const kstr = std.fmt.bufPrint(&kbuf, "{d}", .{k}) catch unreachable;
        var wt_buf: [contract.max_path]u8 = undefined;
        const world_trace = std.fmt.bufPrint(&wt_buf, "{s}/trace-{d}.bin", .{ args.work, k }) catch setupError("path too long");
        removeFile(world_trace);

        const term = posix.runChild(gpa, op_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.trace_path, world_trace },
            .{ contract.env.kill_at, kstr },
            .{ "LD_PRELOAD", shim },
        }) catch setupError("could not run --operation");

        var wtrace = engine.readTrace(gpa, world_trace) catch setupError("could not read a world trace");
        defer wtrace.deinit();

        // Landing evidence: the kill must have happened where it was asked for. Without
        // this check "killed before operation k" would rest on having set a variable.
        const landed = wtrace.kill_landed_seq != null and wtrace.kill_landed_seq.? == k;
        if (k <= n and !landed)
            unknown(.kill_did_not_land, "a world was asked to die before a given operation and did not");
        if (k <= n and !term.isSignal(9))
            unknown(.kill_did_not_land, "a world that should have been killed exited on its own");

        var crashed = engine.takeSnapshot(gpa, state_abs) catch setupError("could not snapshot a crashed state");
        defer crashed.deinit();

        explored += 1;
        if (engine.judgeL0(initial, final, crashed)) |v| {
            failures += 1;
            if (first_failure == null) {
                first_failure = .{ .k = k, .term = term, .landed = landed, .violation = v };
                const p = switch (v) {
                    .missing => |p| p,
                    .hybrid => |p| p,
                };
                @memcpy(first_failure_path[0..p.len], p);
                first_failure_path_len = p.len;
            }
        }
    }

    // ---- report --------------------------------------------------------------------
    if (first_failure) |f| {
        const addr = trace.logicalAddress(f.k);
        const after = if (addr.after) |a| a.class.name() else "(start)";
        const after_path = if (addr.after) |a| a.path else "";
        const before = if (addr.before) |b| b.class.name() else "(end)";
        const before_path = if (addr.before) |b| b.path else "";
        const what = switch (f.violation.?) {
            .missing => "present before and after the operation, but gone from the crashed state",
            .hybrid => "holding neither the old nor the new content",
        };
        say(
            \\FAIL  {d} of {d} crash worlds violated the built-in atomicity invariant
            \\
            \\earliest    crash point {d} of {d}
            \\            after  {s}({s})
            \\            before {s}({s})
            \\path        {s}
            \\observed    {s}
            \\explored    {d} worlds (crash points {d} + 1 baseline)
            \\not tested  power loss, torn writes, concurrent processes
            \\
            \\reproduce   SIDEEYE_KILL_AT={d} LD_PRELOAD={s} <operation>
            \\
        , .{
            failures,   explored,
            f.k,        n,
            after,      after_path,
            before,     before_path,
            first_failure_path[0..first_failure_path_len],
            what,
            explored,   n,
            f.k,        shim,
        });
        std.process.exit(@intFromEnum(contract.ExitCode.fail));
    }

    say(
        \\PASS  {d}/{d} crash worlds satisfied the built-in atomicity invariant
        \\      explored {d} worlds (crash points {d} + 1 baseline)
        \\      not tested: power loss, torn writes, concurrent processes
        \\
    , .{ explored, explored, explored, n });
    std.process.exit(@intFromEnum(contract.ExitCode.pass));
}

/// Split a command line on whitespace.
///
/// The first version of this ran commands through `/bin/sh -c`, which was wrong in a
/// way worth remembering: the shell forks to start the program, LD_PRELOAD applies to
/// the shell too, and every single run therefore reported `child_process_detected`.
/// Using `sh -c "exec …"` only trades the fork for an exec, which the same detector
/// catches. The target has to be executed directly.
///
/// The cost is that arguments cannot contain spaces. v0.1 accepts that limit rather
/// than growing a quoting parser; a proper argv-taking interface is the real fix.
fn splitArgs(arena: std.mem.Allocator, cmd: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, cmd, ' ');
    while (it.next()) |tok| try list.append(arena, tok);
    return list.items;
}

fn removeFile(path: []const u8) void {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = posix.unlink(z.ptr);
}

fn snapshotsEqual(a: engine.Snapshot, b: engine.Snapshot) bool {
    if (a.entries.items.len != b.entries.items.len) return false;
    for (a.entries.items) |ae| {
        const be = b.find(ae.rel) orelse return false;
        if (ae.kind != be.kind) return false;
        if (!std.mem.eql(u8, ae.content, be.content)) return false;
    }
    return true;
}
