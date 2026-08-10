const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const oracle = @import("oracle.zig");

pub const version = "0.1.0-dev";

/// How the loader is told to inject the shim. Same idea, different spelling.
const preload_var = if (builtin.os.tag == .macos) "DYLD_INSERT_LIBRARIES" else "LD_PRELOAD";

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
    oracle: ?[]const u8 = null,
    check: ?[]const u8 = null,
    allow_unverified: bool = false,
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
        \\  --oracle     path to strace; the recording run is compared against it
        \\  --check      command run after each crash, in a fresh process; exit 0 = invariant holds
        \\  --allow-unverified
        \\               accept PASS with no completeness check. Needed on macOS, which
        \\               has no usable oracle: dtruss is blocked by SIP. The report says
        \\               so, and the claim it makes is weaker.
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

/// Guards every path that ends in PASS.
///
/// FAIL does not need this — a counterexample is real whether or not the account of the
/// run was complete. "No counterexample found" is only worth something if what was
/// looked at is known. Both PASS exits call this, including the one for a target that
/// appeared to perform no operations at all: that is the case where the shim saw
/// nothing, which is precisely when the question of whether it *could* see matters most.
///
/// `allow_unverified` exists because macOS has no oracle sideeye can use. `dtruss` is
/// DTrace-based and refuses to run under System Integrity Protection, and the
/// alternatives need an entitlement that a single distributed binary cannot carry.
/// Rather than branch on the platform — which would break the claim that both operating
/// systems produce the same verdict for the same scenario — the caller states the
/// weaker claim deliberately, and the report says which claim was made.
fn requireCompleteness(has_oracle: bool, allow_unverified: bool) void {
    if (has_oracle or allow_unverified) return;
    unknown(.completeness_not_verified, "no oracle was given, so the shim's account of what happened was not checked against anything; pass --oracle, or --allow-unverified to accept the weaker claim");
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
    while (i < argv.len) {
        // Flags without a value are handled first; everything else consumes a pair.
        if (std.mem.eql(u8, argv[i], "--allow-unverified")) {
            args.allow_unverified = true;
            i += 1;
            continue;
        }
        if (i + 1 >= argv.len) setupError("an option is missing its value");
        const v = argv[i + 1];
        if (std.mem.eql(u8, argv[i], "--state")) args.state = v
        else if (std.mem.eql(u8, argv[i], "--setup")) args.setup = v
        else if (std.mem.eql(u8, argv[i], "--operation")) args.operation = v
        else if (std.mem.eql(u8, argv[i], "--shim")) args.shim = v
        else if (std.mem.eql(u8, argv[i], "--work")) args.work = v
        else if (std.mem.eql(u8, argv[i], "--oracle")) args.oracle = v
        else if (std.mem.eql(u8, argv[i], "--check")) args.check = v
        else setupError("unknown option");
        i += 2;
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

    var oracle_out_buf: [contract.max_path]u8 = undefined;
    const oracle_out = std.fmt.bufPrint(&oracle_out_buf, "{s}/oracle.txt", .{args.work}) catch setupError("path too long");
    removeFile(oracle_out);

    const arena = arena_state.allocator();
    const rec_term = blk: {
        if (args.oracle) |strace_path| {
            // Environment goes to the target via strace's -E, not through our own
            // setenv: LD_PRELOAD applied here would load the shim into strace itself,
            // and strace's own file operations would land in the trace as if the
            // target had produced them.
            var list: std.ArrayList([]const u8) = .empty;
            list.append(arena, strace_path) catch setupError("out of memory");
            // `-f` follows children and `%process` covers clone/fork/execve. Without
            // both, a target that creates a child through a raw clone is invisible to
            // the oracle as well as to the shim, and the child's work on the state
            // directory never appears anywhere.
            for ([_][]const u8{ "-f", "-y", "-e", "trace=%file,%desc,%process", "-o", oracle_out }) |a|
                list.append(arena, a) catch setupError("out of memory");
            const pairs = [_][2][]const u8{
                .{ "TOY_STATE", state_abs },
                .{ contract.env.state_dir, state_abs },
                .{ contract.env.trace_path, rec_trace },
                .{ preload_var, shim },
            };
            for (pairs) |kv| {
                list.append(arena, "-E") catch setupError("out of memory");
                const joined = std.fmt.allocPrint(arena, "{s}={s}", .{ kv[0], kv[1] }) catch setupError("out of memory");
                list.append(arena, joined) catch setupError("out of memory");
            }
            for (op_argv) |a| list.append(arena, a) catch setupError("out of memory");
            break :blk posix.runChild(gpa, list.items, &.{}) catch setupError("could not run --operation under the oracle");
        }
        break :blk posix.runChild(gpa, op_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.trace_path, rec_trace },
            .{ preload_var, shim },
        }) catch setupError("could not run --operation");
    };
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

    if (trace.truncated)
        unknown(.trace_truncated, "the trace ends mid-record; how many operations there were is unknown");

    if (trace.saw_unresolved)
        unknown(.unresolvable_path, "an operation was observed whose path could not be determined, so it cannot be placed among the crash points");

    if (trace.boundary) |b| switch (b) {
        .fork, .exec => unknown(.child_process_detected, "the target created a child process; v0.1 explores single-process targets"),
        .thread => unknown(.multiple_threads_detected, "the target created a thread; operation order would not be deterministic"),
        else => {},
    };

    // ---- oracle comparison ---------------------------------------------------------
    // The wording matters: a PASS carrying this line is making a weaker claim than one
    // that says the two views agreed, and a reader should be able to see which is which
    // without knowing how the run was invoked.
    var oracle_note: []const u8 = if (args.allow_unverified)
        "NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported"
    else
        "not run (no --oracle given)";
    if (args.oracle != null) {
        const text = readFileAlloc(arena, oracle_out) orelse setupError("the oracle produced no output");
        const parsed = oracle.parse(arena, text, state_abs) catch setupError("out of memory");

        if (parsed.boundary) |name|
            unknown(.child_process_detected, name);

        if (parsed.unsupported) |name|
            unknown(.unsupported_syscall_observed, name);

        var shim_classes: std.ArrayList(contract.OpClass) = .empty;
        for (trace.ops.items) |op| {
            if (op.class.isMarker() or op.class.isBoundary()) continue;
            shim_classes.append(arena, op.class) catch setupError("out of memory");
        }

        if (oracle.compare(shim_classes.items, parsed.classes.items)) |f| switch (f) {
            .missed => unknown(.oracle_missed_operation, "the oracle saw a state-directory operation the shim did not record"),
            .phantom => unknown(.oracle_saw_phantom, "the shim recorded an operation the oracle did not see"),
            .unsupported => |name| unknown(.unsupported_syscall_observed, name),
        };

        oracle_note = std.fmt.allocPrint(
            arena,
            "agreed on {d} operations ({d} syscall lines examined, {d} touching the state directory)",
            .{ parsed.classes.items.len, parsed.lines_seen, parsed.lines_in_scope },
        ) catch "agreed";
    }

    if (!snapshotsEqual(initial, final) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed while zero mutating operations were recorded: operations were missed");

    const n = trace.kill_point_count;
    if (n == 0) {
        requireCompleteness(args.oracle != null, args.allow_unverified);
        say(
            \\PASS  the operation performed no state-directory operations
            \\      explored 0 crash points; nothing to kill before
            \\      not tested: power loss, torn writes, concurrent processes
            \\
        , .{});
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // ---- checker falsification (DESIGN §14-13) -------------------------------------
    //
    // Run before exploring, not after: a checker that cannot tell a corrupted state
    // from a good one will report every world as fine, and the resulting PASS would be
    // a statement about nothing. Better to refuse than to produce a confident answer
    // derived from an instrument that was never shown to respond.
    var check_argv: ?[]const []const u8 = null;
    var checker_note: []const u8 = "none configured";
    if (args.check) |check_cmd| {
        const cargv = splitArgs(arena, check_cmd) catch setupError("--check is empty");
        if (cargv.len == 0) setupError("--check is empty");
        check_argv = cargv;

        if (engine.countFiles(initial) == 0)
            unknown(.checker_not_falsified, "the state directory holds no files, so there was nothing to corrupt and the checker could not be tested");

        engine.restore(initial, state_abs) catch setupError("could not restore before falsifying the checker");
        engine.corruptState(initial, state_abs) catch setupError("could not corrupt the state for the falsification probe");

        const probe = posix.runChild(gpa, cargv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
        }) catch setupError("could not run --check");

        switch (probe) {
            .exited => |code| if (code == 0)
                unknown(.checker_not_falsified, "the checker accepted a state whose every file had been overwritten with junk"),
            else => unknown(.checker_not_falsified, "the checker did not exit normally when given a corrupted state"),
        }
        checker_note = "falsified before the run (corrupted state -> check failed)";
    }

    // ---- exploration --------------------------------------------------------------
    var explored: u32 = 0;
    var failures: u32 = 0;
    var first_failure: ?engine.WorldResult = null;
    var first_failure_l2 = false;
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
            .{ preload_var, shim },
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

        // The checker runs in a fresh process, after the crash, exactly as DESIGN §12
        // requires: in-memory state hides corruption, so nothing is evaluated inside
        // the lifetime of the process that died.
        var l2_failed = false;
        if (check_argv) |cargv| {
            const ct = posix.runChild(gpa, cargv, &.{
                .{ "TOY_STATE", state_abs },
                .{ contract.env.state_dir, state_abs },
            }) catch setupError("could not run --check");
            l2_failed = switch (ct) {
                .exited => |code| code != 0,
                else => true,
            };
        }

        const l0 = engine.judgeL0(initial, final, crashed);
        if (l0 != null or l2_failed) {
            failures += 1;
            if (first_failure == null) {
                first_failure = .{ .k = k, .term = term, .landed = landed, .violation = l0 };
                first_failure_l2 = l2_failed;
                if (l0) |v| {
                    const p = switch (v) {
                        .missing => |p| p,
                        .hybrid => |p| p,
                    };
                    @memcpy(first_failure_path[0..p.len], p);
                    first_failure_path_len = p.len;
                }
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
        const invariant = if (f.violation != null and first_failure_l2)
            "built-in atomicity, and the checker"
        else if (f.violation != null)
            "built-in atomicity (L0)"
        else
            "the checker (L2)";
        const what = if (f.violation) |v| switch (v) {
            .missing => "present before and after the operation, but gone from the crashed state",
            .hybrid => "holding neither the old nor the new content",
        } else "the checker exited non-zero after restart";
        const path_shown = if (first_failure_path_len > 0)
            first_failure_path[0..first_failure_path_len]
        else
            "(named by the checker, not by path)";
        say(
            \\FAIL  {d} of {d} crash worlds violated an invariant
            \\
            \\invariant   {s}
            \\earliest    crash point {d} of {d}
            \\            after  {s}({s})
            \\            before {s}({s})
            \\path        {s}
            \\observed    {s}
            \\explored    {d} worlds (crash points {d} + 1 baseline)
            \\oracle      {s}
            \\checker     {s}
            \\not tested  power loss, torn writes, concurrent processes
            \\
            \\reproduce   SIDEEYE_KILL_AT={d} {s}={s} <operation>
            \\
        , .{
            failures,   explored,
            invariant,
            f.k,        n,
            after,      after_path,
            before,     before_path,
            path_shown,
            what,
            explored,   n,
            oracle_note,
            checker_note,
            f.k,        preload_var, shim,
        });
        std.process.exit(@intFromEnum(contract.ExitCode.fail));
    }

    requireCompleteness(args.oracle != null, args.allow_unverified);

    say(
        \\PASS  {d}/{d} crash worlds satisfied the built-in atomicity invariant
        \\      explored {d} worlds (crash points {d} + 1 baseline)
        \\      oracle: {s}
        \\      checker: {s}
        \\      not tested: power loss, torn writes, concurrent processes
        \\
    , .{ explored, explored, explored, n, oracle_note, checker_note });
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

fn readFileAlloc(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    const fd = posix.open(z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n <= 0) break;
        list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
    }
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
