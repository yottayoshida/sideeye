const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const oracle = @import("oracle.zig");

/// Must match `.version` in `build.zig.zon`. They are two hand-written strings for the
/// same number, and they had already drifted: the package said 0.1.0 while `--help` said
/// 0.1.0-dev. A test below holds them together.
pub const version = "0.1.0";

/// How the loader is told to inject the shim. Same idea, different spelling.
const preload_var = if (builtin.os.tag == .macos) "DYLD_INSERT_LIBRARIES" else "LD_PRELOAD";

var out_buf: [16 * 1024]u8 = undefined;

/// The report is the product. Losing it silently is not an option.
///
/// This used to `catch return` on overflow, so a FAIL whose paths pushed the text past
/// 16 KB exited 1 having printed nothing at all — the caller would see a bare exit code
/// and no counterexample. Formatting into a fixed buffer is still right for a tool that
/// must work when the heap is uninteresting, so the failure is reported instead of
/// swallowed.
fn say(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&out_buf, fmt, args) catch {
        const msg = "sideeye: the report did not fit in the output buffer; paths are unusually long\n";
        _ = posix.write(2, msg.ptr, msg.len);
        return;
    };
    var off: usize = 0;
    while (off < s.len) {
        const w = posix.write(1, s[off..].ptr, s.len - off);
        // A truncated report reads as a complete one — the reader has no way to know a
        // line was cut. Nothing can be said about it on stdout, which is the stream that
        // just failed, so it goes to stderr. Found by the same-class scan that this
        // function's own overflow fix started.
        if (w <= 0) {
            const msg = "sideeye: the report was cut short; stdout stopped accepting output\n";
            _ = posix.write(2, msg.ptr, msg.len);
            return;
        }
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
    json: ?[]const u8 = null,
};

/// What the report says so far.
///
/// These are module-level because `unknown()` and `setupError()` exit from deep inside
/// the run and still have to emit the machine-readable half of the report: DESIGN §13
/// requires both forms to carry identical content, and UNKNOWN is the verdict a caller
/// is most likely to be branching on.
///
/// There used to be two variables per note — a local the text report read, and a global
/// the JSON read, copied across on the success path only. An UNKNOWN then printed
/// `unknown_reason: checker_not_falsified` beside `checker: none configured`: the report
/// contradicted itself about whether a checker existed. One variable each removes the
/// possibility rather than fixing the two sites where it showed.
var json_path: ?[]const u8 = null;
var json_arena: ?std.mem.Allocator = null;
var oracle_note: []const u8 = "not run (no --oracle given)";
var checker_note: []const u8 = "none configured";
/// Progress, so an UNKNOWN raised mid-exploration reports what had been explored rather
/// than zero. A caller aggregating coverage reads these.
var crash_points: u32 = 0;
var explored: u32 = 0;
var violations: u32 = 0;

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
        \\  --json       write the machine-readable report to this path
        \\  --allow-unverified
        \\               accept PASS with no completeness check. Needed on macOS, which
        \\               has no usable oracle: dtruss is blocked by SIP. The report says
        \\               so, and the claim it makes is weaker.
        \\
        \\exit codes: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR
        \\
        \\--operation must exit 0 when it is not being killed. The crash points are read
        \\off that run, so a target that fails partway through would be explored against
        \\a sequence it never performs; v0.1 reports UNKNOWN rather than guess.
        \\
    , .{ version, contract.contract_version });
}

fn unknown(reason: contract.UnknownReason, detail: []const u8) noreturn {
    if (json_path) |jp| if (json_arena) |ja|
        writeJsonReport(ja, jp, "UNKNOWN", @intFromEnum(contract.ExitCode.unknown), null, reason.name(), detail);
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

/// A setup error is a verdict too, and it has to reach the JSON.
///
/// It did not, and the file was neither written nor removed: a caller running twice into
/// the same `--json` path read the *previous* run's document as this run's result. Since
/// several of these fire mid-run — after the trace is read, after a world is restored —
/// that stale verdict could be a PASS for a run that never explored anything.
fn setupError(detail: []const u8) noreturn {
    if (json_path) |jp| if (json_arena) |ja|
        writeJsonReport(ja, jp, "SETUP_ERROR", @intFromEnum(contract.ExitCode.setup_error), null, null, detail);
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
    // Before the loop, so that a parse error occurring *after* `--json` was read still
    // reaches the report rather than leaving whatever was there before.
    json_arena = arena_state.allocator();
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
        else if (std.mem.eql(u8, argv[i], "--json")) {
            args.json = v;
            json_path = v;
            // Any document at this path describes some earlier run. Removing it now means
            // an exit that never reaches a writer leaves *no* report rather than a stale
            // one: absence is unambiguous, a previous verdict is not.
            removeFile(v);
        }
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
    // Create the directory before resolving it, and refuse to continue if resolution
    // still fails.
    //
    // The fallback used to be "use the argument as given", which is silently wrong on
    // macOS: /tmp is a symlink to /private/tmp, so the engine would filter on
    // /tmp/run/state while the shim — which asks the descriptor via F_GETPATH — sees
    // /private/tmp/run/state. Every operation falls outside the state directory, the
    // trace comes back empty, and the oracle cannot help because it is handed the same
    // wrong spelling and also finds nothing. Two views agreeing on nothing looks exactly
    // like two views agreeing.
    _ = posix.mkdir(state_z.ptr, 0o755);
    const state_abs = blk: {
        if (posix.realpath(state_z.ptr, &real_buf)) |p| break :blk std.mem.span(p);
        setupError("--state could not be resolved to an absolute path; the shim and the engine would filter on different spellings of it");
    };

    // The spelling the caller used, absolute but with symlinks left alone.
    //
    // On macOS `--state /tmp/x` resolves to `/private/tmp/x`, and a target told its state
    // is at `/tmp/x` hands `/tmp/x/key.json` to `unlink` while `F_GETPATH` answers
    // `/private/tmp/x/key.json` for the same file. Exploration never saw this because the
    // engine hands the target the resolved path; the `reproduce` line did, because there
    // the target finds its state its own way — and the result was a printed command that
    // ran to completion and changed nothing.
    var alt_buf: [contract.max_path]u8 = undefined;
    const state_alt = blk: {
        var cwd_buf: [contract.max_path]u8 = undefined;
        const cwd = if (posix.getcwd(&cwd_buf, cwd_buf.len)) |p| std.mem.span(p) else "/";
        const n = contract.normalizePath(&alt_buf, cwd, state) catch break :blk state_abs;
        break :blk n;
    };
    const alt_differs = !std.mem.eql(u8, state_alt, state_abs);

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

    // Checked before the run, so that "the operation failed" and "the oracle could not be
    // started" stay distinguishable. Without this, a missing strace makes the child exit
    // 127 and the report says `recording_run_failed / the operation exited non-zero` —
    // blaming a target that never ran. It also made the acceptance check for that verdict
    // pass identically on a machine with no strace, so the check discriminated nothing.
    if (args.oracle) |oracle_path| {
        var ob: [contract.max_path]u8 = undefined;
        const oz = std.fmt.bufPrintZ(&ob, "{s}", .{oracle_path}) catch setupError("--oracle path is too long");
        if (posix.access(oz.ptr, posix.X_OK) != 0)
            setupError("--oracle is not an executable file; the completeness check cannot run");
    }

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
                .{ contract.env.state_dir_alt, state_alt },
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
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, rec_trace },
            .{ preload_var, shim },
        }) catch setupError("could not run --operation");
    };
    // The recording run's outcome decides whether its trace means anything.
    //
    // This used to be discarded. An operation that failed immediately — a bad argument,
    // a missing input, EACCES — wrote its shim_ready marker, recorded no operations, and
    // left the state untouched, so every structural detector stayed quiet and the run
    // reported PASS over zero crash points. A partial failure was worse: five operations
    // become two, and the exploration is confidently complete over a sequence the target
    // never finishes. `--setup` was already checked here; the operation is the one whose
    // result the entire trace depends on.
    switch (rec_term) {
        .exited => |code| if (code != 0)
            unknown(.recording_run_failed, "the operation exited non-zero during the recording run, so the crash points derived from it describe an execution that did not happen"),
        else => unknown(.recording_run_failed, "the operation did not exit normally during the recording run"),
    }

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
    if (args.allow_unverified)
        oracle_note = "NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported";
    if (args.oracle != null) {
        // Set before the exits below, not after them. Every `unknown()` in this block is
        // raised by the oracle having run and disagreed; a report saying "not run" beside
        // `unknown_reason: oracle_missed_operation` contradicts itself.
        oracle_note = "ran; the comparison did not complete";
        const text = readFileAlloc(arena, oracle_out) orelse setupError("the oracle produced no output");
        const parsed = oracle.parse(arena, text, state_abs) catch setupError("out of memory");

        // An oracle that observed nothing agrees with a shim that observed nothing, and
        // the report says "agreed" either way. The acceptance suite asserts by hand that
        // more than ten lines were examined; the tool itself shipped without the check
        // its own suite considered necessary.
        if (parsed.lines_seen == 0)
            unknown(.oracle_saw_nothing, "the oracle produced no output, so nothing was compared against the shim's account");

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
    crash_points = n;
    if (n == 0) {
        requireCompleteness(args.oracle != null, args.allow_unverified);
        say(
            \\PASS  the operation performed no state-directory operations
            \\      explored 0 crash points; nothing to kill before
            \\      not tested: power loss, torn writes, concurrent processes
            \\
        , .{});
        if (args.json) |jp| writeJsonReport(arena, jp, "PASS", @intFromEnum(contract.ExitCode.pass), null, null, null);
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // ---- checker falsification (DESIGN §14-13) -------------------------------------
    //
    // Run before exploring, not after: a checker that cannot tell a corrupted state
    // from a good one will report every world as fine, and the resulting PASS would be
    // a statement about nothing. Better to refuse than to produce a confident answer
    // derived from an instrument that was never shown to respond.
    var check_argv: ?[]const []const u8 = null;
    if (args.check) |check_cmd| {
        const cargv = splitArgs(arena, check_cmd) catch setupError("--check is empty");
        if (cargv.len == 0) setupError("--check is empty");
        check_argv = cargv;
        // Before the falsification exits, for the same reason as the oracle note above:
        // `checker_not_falsified` next to `checker: none configured` is a report arguing
        // with itself about whether a checker was given.
        checker_note = "configured; falsification did not complete";

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
            .{ contract.env.state_dir_alt, state_alt },
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
        // The baseline world is not killed, so nothing above inspects it — which is
        // exactly the discarded-exit-status defect that was just fixed for the recording
        // run. It is the same command over the same state, and the recording run was
        // required to exit 0; a different outcome here means the restored state is not
        // the state that was recorded, and every other world started from it too.
        if (k > n) switch (term) {
            .exited => |code| if (code != 0)
                unknown(.baseline_run_failed, "the un-killed baseline world exited non-zero although the recording run of the same command succeeded: the restored state differs from the recorded one"),
            else => unknown(.baseline_run_failed, "the un-killed baseline world did not exit normally"),
        };

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

        // The baseline world was never killed. If the invariant fails there, it fails
        // without any help from sideeye — the checker rejects a state the operation
        // produces normally, or the operation is broken on its own — and neither is a
        // crash-consistency counterexample. Reporting it as "N of N crash worlds violated
        // an invariant" blames crashing for something that happens without it.
        //
        // Only reachable through a checker: for the baseline, `crashed` *is* `final`, and
        // judgeL0 compares every shared file against pre or post, so post always matches.
        if (k > n and (l0 != null or l2_failed))
            unknown(.baseline_violates_invariant, "the invariant failed in the world that was never crashed, so nothing found here is a consequence of crashing; check the operation and the checker against each other first");

        if (l0 != null or l2_failed) {
            violations += 1;
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
        // The shim arms itself only when it has somewhere to write, so a reproduce line
        // without a trace path is inert: `init()` returns before setting `active`, no
        // operation is counted, the kill never fires, and the command runs to completion
        // leaving an intact state — the opposite of what the report above describes. The
        // first version of this line omitted `SIDEEYE_STATE_DIR`; fixing that and not
        // running the result left this one. Acceptance now executes what is printed.
        var repro_buf: [contract.max_path]u8 = undefined;
        const repro_trace = std.fmt.bufPrint(&repro_buf, "{s}/trace-repro.bin", .{args.work}) catch
            setupError("path too long");
        // Only when the two spellings differ. Printing `A=x B=x` invites the reader to
        // wonder which one matters, and the answer would be "neither, they are the same".
        var alt_env_buf: [contract.max_path + 64]u8 = undefined;
        const alt_env = if (alt_differs)
            std.fmt.bufPrint(&alt_env_buf, " {s}={s}", .{ contract.env.state_dir_alt, state_alt }) catch
                setupError("path too long")
        else
            "";
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
            \\reproduce   SIDEEYE_STATE_DIR={s}{s} SIDEEYE_TRACE_PATH={s} {s}={s} SIDEEYE_KILL_AT={d} <operation>
            \\
        , .{
            violations, explored,
            invariant,
            f.k,        n,
            after,      after_path,
            before,     before_path,
            path_shown,
            what,
            explored,   n,
            oracle_note,
            checker_note,
            state_abs,  alt_env,     repro_trace, preload_var, shim, f.k,
        });
        if (args.json) |jp| writeJsonReport(arena, jp, "FAIL", @intFromEnum(contract.ExitCode.fail), .{
            .k = f.k,
            .after = after,
            .after_path = after_path,
            .before = before,
            .before_path = before_path,
            .subject = path_shown,
            .observed = what,
            .invariant = invariant,
        }, null, null);
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
    if (args.json) |jp| writeJsonReport(arena, jp, "PASS", @intFromEnum(contract.ExitCode.pass), null, null, null);
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
        // A read error is not end of file. Treating them alike turned a truncated oracle
        // file into a complete one, and the comparison that followed was against however
        // much happened to arrive before the error.
        if (n < 0) return null;
        if (n == 0) break;
        list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
    }
    return list.items;
}

/// JSON for the caller, text for the reader, with identical content (DESIGN §13).
///
/// Hand-written rather than derived from a type: the schema is explicitly experimental
/// until v1.0, and generating it would suggest a stability this release does not offer.
///
/// `std.json.Stringify.encodeJsonString` was the obvious alternative and does not fit.
/// Its default options pass bytes 0x80–0xFF through unchanged — the same defect this
/// function had — and `escape_unicode` decodes them with `catch unreachable`, so invalid
/// UTF-8 is a panic rather than a bad document.
fn jsonString(w: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) !void {
    try w.append(arena, '"');
    var i: usize = 0;
    while (i < s.len) {
        const ch = s[i];
        switch (ch) {
            '"' => {
                try w.appendSlice(arena, "\\\"");
                i += 1;
            },
            '\\' => {
                try w.appendSlice(arena, "\\\\");
                i += 1;
            },
            '\n' => {
                try w.appendSlice(arena, "\\n");
                i += 1;
            },
            '\r' => {
                try w.appendSlice(arena, "\\r");
                i += 1;
            },
            '\t' => {
                try w.appendSlice(arena, "\\t");
                i += 1;
            },
            else => {
                if (ch < 0x20) {
                    var esc: [6]u8 = undefined;
                    try w.appendSlice(arena, try std.fmt.bufPrint(&esc, "\\u{x:0>4}", .{ch}));
                    i += 1;
                } else if (ch < 0x80) {
                    try w.append(arena, ch);
                    i += 1;
                } else {
                    // A path on Linux is an arbitrary byte string; a JSON document must be
                    // valid UTF-8. Passing these through raw produced a file that jq,
                    // Python and Go all refuse — the caller loses the counterexample
                    // entirely, which is worse than losing one character of a filename.
                    // Valid sequences go through untouched; an invalid byte becomes
                    // U+FFFD and the document still parses.
                    const len = std.unicode.utf8ByteSequenceLength(ch) catch {
                        try w.appendSlice(arena, "\\ufffd");
                        i += 1;
                        continue;
                    };
                    if (i + len > s.len or !std.unicode.utf8ValidateSlice(s[i..][0..len])) {
                        try w.appendSlice(arena, "\\ufffd");
                        i += 1;
                        continue;
                    }
                    try w.appendSlice(arena, s[i..][0..len]);
                    i += len;
                }
            },
        }
    }
    try w.append(arena, '"');
}

const Earliest = struct {
    k: u32,
    after: []const u8,
    after_path: []const u8,
    before: []const u8,
    before_path: []const u8,
    subject: []const u8,
    observed: []const u8,
    invariant: []const u8,
};

fn buildJson(
    arena: std.mem.Allocator,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    unknown_reason: ?[]const u8,
    message: ?[]const u8,
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = &buf;
    var nb: [16]u8 = undefined;

    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"experimental\",\n");
    try w.appendSlice(arena, "  \"contract_version\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}));
    try w.appendSlice(arena, ",\n  \"verdict\": ");
    try jsonString(w, arena, verdict);
    try w.appendSlice(arena, ",\n  \"exit_code\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{exit_code}));
    // Read from the run's own counters rather than passed in as zeroes. An UNKNOWN raised
    // at world 4 of 6 used to report `"explored": 0`, so a caller aggregating coverage
    // from the JSON recorded nothing for every run that ended early.
    try w.appendSlice(arena, ",\n  \"crash_points\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{crash_points}));
    try w.appendSlice(arena, ",\n  \"explored\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{explored}));
    try w.appendSlice(arena, ",\n  \"violations\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{violations}));

    if (unknown_reason) |r| {
        try w.appendSlice(arena, ",\n  \"unknown_reason\": ");
        try jsonString(w, arena, r);
    }
    if (message) |m| {
        try w.appendSlice(arena, ",\n  \"message\": ");
        try jsonString(w, arena, m);
    }

    if (detail) |d| {
        try w.appendSlice(arena, ",\n  \"earliest\": {\n    \"crash_point\": ");
        try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{d.k}));
        try w.appendSlice(arena, ",\n    \"invariant\": ");
        try jsonString(w, arena, d.invariant);
        try w.appendSlice(arena, ",\n    \"after\": {\"op\": ");
        try jsonString(w, arena, d.after);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, d.after_path);
        try w.appendSlice(arena, "},\n    \"before\": {\"op\": ");
        try jsonString(w, arena, d.before);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, d.before_path);
        try w.appendSlice(arena, "},\n    \"subject\": ");
        try jsonString(w, arena, d.subject);
        try w.appendSlice(arena, ",\n    \"observed\": ");
        try jsonString(w, arena, d.observed);
        try w.appendSlice(arena, "\n  }");
    }

    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    try w.appendSlice(arena, ",\n  \"checker\": ");
    try jsonString(w, arena, checker_note);
    // Stated in the report itself, not only in the documentation: a PASS that does not
    // say what it did not look at is the kind of reassurance this tool refuses to give.
    try w.appendSlice(arena, ",\n  \"not_tested\": [\"power loss\", \"torn writes\", \"concurrent processes\"]\n}\n");
    return buf.items;
}

/// On stderr, not stdout: the text report is the process's output, and a diagnostic
/// mixed into it would be read as part of the verdict.
fn jsonFailed(detail: []const u8) void {
    const prefix = "sideeye: the JSON report was not written: ";
    _ = posix.write(2, prefix.ptr, prefix.len);
    _ = posix.write(2, detail.ptr, detail.len);
    _ = posix.write(2, "\n", 1);
}

/// Written whole or not at all.
///
/// Every step here used to fail silently: a failed open, a short write, a formatting
/// error mid-document. The result was a truncated file — `{"schema": "sideeye/report",`
/// with no closing brace — beside an exit code claiming a clean verdict, and the caller
/// could not tell a broken write from a broken tool. Building the document first and
/// moving it into place with `rename` is the same discipline sideeye exists to check for
/// in other programs; applying it here is not decoration.
fn writeJsonReport(
    arena: std.mem.Allocator,
    path: []const u8,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    unknown_reason: ?[]const u8,
    message: ?[]const u8,
) void {
    const doc = buildJson(arena, verdict, exit_code, detail, unknown_reason, message) catch
        return jsonFailed("the document could not be built");

    var pbuf: [contract.max_path]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&pbuf, "{s}", .{path}) catch
        return jsonFailed("--json path is too long");
    var tbuf: [contract.max_path]u8 = undefined;
    const tz = std.fmt.bufPrintZ(&tbuf, "{s}.tmp", .{path}) catch
        return jsonFailed("--json path is too long");

    const fd = posix.open(tz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return jsonFailed("the file could not be opened for writing");
    var off: usize = 0;
    while (off < doc.len) {
        const written = posix.write(fd, doc[off..].ptr, doc.len - off);
        if (written <= 0) {
            _ = posix.close(fd);
            _ = posix.unlink(tz.ptr);
            return jsonFailed("the write did not complete");
        }
        off += @intCast(written);
    }
    _ = posix.close(fd);

    if (posix.rename(tz.ptr, pz.ptr) != 0) {
        _ = posix.unlink(tz.ptr);
        return jsonFailed("the finished document could not be moved into place");
    }
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

test "the version in build.zig.zon and the one the CLI prints are the same string" {
    // Two hand-written copies of one number, and they had already drifted before anyone
    // looked: the package manifest said 0.1.0 while `--help` said 0.1.0-dev. A release
    // would have shipped a tag that disagreed with the binary it tagged.
    const zon = @embedFile("build_zon");
    const needle = ".version = \"";
    const start = (std.mem.indexOf(u8, zon, needle) orelse return error.NoVersionField) + needle.len;
    const end = std.mem.indexOfScalarPos(u8, zon, start, '"') orelse return error.Unterminated;
    try std.testing.expectEqualStrings(zon[start..end], version);
}
