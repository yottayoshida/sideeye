const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const oracle = @import("oracle.zig");
const config = @import("config.zig");
const mcp = @import("mcp.zig");

/// Must match `.version` in `build.zig.zon`. They are two hand-written strings for the
/// same number, and they had already drifted: the package said 0.1.0 while `--help` said
/// 0.1.0-dev. A test below holds them together.
pub const version = "0.4.0";

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
    config: ?[]const u8 = null,
    marker: ?[]const u8 = null,
};

/// A saved counterexample (ADR 0009): the resolved define it was found against, the
/// crash point, and the landing context that decides whether a later replay still
/// addresses the same operation. Parsed strictly — an unknown field is a case from a
/// future schema, not something to skip.
const ReplayCase = struct {
    schema: []const u8,
    case_version: u32,
    sideeye_version: []const u8,
    contract_version: u32,
    define: struct {
        state: []const u8,
        setup: ?[]const u8 = null,
        operation: []const u8,
        check: ?[]const u8 = null,
        marker: ?[]const u8 = null,
    },
    k: u32,
    ops_total: u32,
    prefix_hash: []const u8,
    after_class: []const u8,
    after_path: []const u8,
    before_class: []const u8,
    before_path: []const u8,
    violation: []const u8,
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
/// The L1 story (ADR 0008): whether a success marker was declared, and in how many
/// crash worlds it was observed — the worlds where the post-success invariant was
/// enforced. Mirrors `checker_note`: one variable, read by text and JSON alike.
var l1_note: []const u8 = "no marker configured";
/// Whether a marker was configured at all; widens `not tested` (post-only file
/// contents are checked for existence, not content).
var l1_configured: bool = false;
/// Which L0 form judged which files (ADR 0004). Starts as an explicit "not yet", so
/// an UNKNOWN raised before the snapshots exist never carries an invented
/// classification; set from the L0Plan the moment it is built.
var l0_note: []const u8 = "not classified (the run was refused before L0 classification)";
/// Non-zero once any file is judged by the history form; widens `not tested`.
var l0_history_count: u32 = 0;
/// The case/replay story (ADR 0009), one variable each read by text and JSON alike
/// (the checker_note pattern). A FAIL sets them to the saved case and its replay
/// command; a replay sets the case to what it was asked to re-verify the moment the
/// file parses, so even a `case_no_longer_applies` refusal names which case it
/// refused — the JSON consumer is the §17 audience and must not need the text.
var case_note: []const u8 = "(none)";
var replay_note: []const u8 = "-";
/// What the run knows about process boundaries. "single process" until evidence says
/// otherwise; a tolerated boundary replaces it with what was observed and what that
/// limits — the reader of a FAIL must be able to see that the window is attributed to
/// the subject only.
var boundary_note: []const u8 = "single process";
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
        \\  sideeye replay <case.json> --shim <lib> [--oracle <strace>] [--work <dir>] [--json <path>]
        \\
        \\replay re-runs one saved counterexample: the same pipeline as explore — the
        \\oracle comparison, the structural detectors, checker falsification, landing
        \\evidence — restricted to the case's crash point plus the baseline (ADR 0009).
        \\When the recording no longer matches the case's landing context, the answer
        \\is "case no longer applies" (exit 2), never a verdict about a shifted point.
        \\
        \\  --config     path to a sideeye.toml carrying the define surface (ADR 0007);
        \\               mutually exclusive with --state/--setup/--operation/--check.
        \\               Relative paths in the file resolve against its own directory
        \\  --state      directory whose contents define the target's state
        \\  --setup      command that produces the initial state (run once)
        \\  --operation  command to explore; killed before each operation that can change state
        \\  --shim       path to libsideeye_shim.so
        \\  --work       scratch directory for traces (default /tmp/sideeye-work)
        \\  --oracle     path to strace; the recording run is compared against it
        \\  --check      command run after each crash, in a fresh process; exit 0 = invariant holds
        \\  --marker     success marker: a byte string the operation prints on stdout when
        \\               it has committed. In worlds where it appeared before the kill,
        \\               the post-success invariant is enforced: the new state must
        \\               survive (ADR 0008)
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
    // The classification lines appear here too: DESIGN §13 demands text and JSON
    // carry identical content, and the JSON below already does. Before the snapshots
    // exist this honestly reads "not classified".
    say(
        \\UNKNOWN  {s}
        \\         {s}
        \\
        \\atomicity   {s}
        \\l1          {s}
        \\case        {s}
        \\not tested  {s}
        \\
        \\Sideeye could not judge this run. That is not a pass: the exit code is 2 so a
        \\caller has to decide deliberately what to do with it.
        \\
    , .{ reason.name(), detail, l0_note, l1_note, case_note, notTestedText() });
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

    // `mcp` runs a stateless MCP stdio server and never returns to the explore/replay
    // pipeline below (that pipeline is entirely explore/replay-specific). It forwards
    // tool calls by self-exec'ing this same binary's `explore`/`replay`.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "mcp")) {
        // No further arguments: everything operational comes from SIDEEYE_MCP_*.
        // Silently ignoring extras would start a stdin-reading server where the user
        // expected a flag to have meant something.
        if (argv.len != 2) {
            const msg = "sideeye mcp takes no arguments; operational settings come from SIDEEYE_MCP_* environment variables\n";
            _ = posix.write(2, msg.ptr, msg.len);
            std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
        }
        mcp.runServer(gpa);
        return;
    }

    const Mode = enum { explore, replay };
    var mode: Mode = .explore;
    var case_arg: ?[]const u8 = null;
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "explore")) {
        mode = .explore;
    } else if (argv.len >= 3 and std.mem.eql(u8, argv[1], "replay") and argv[2].len > 0 and argv[2][0] != '-') {
        mode = .replay;
        case_arg = argv[2];
    } else {
        usage();
        std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
    }

    var args: Args = .{};
    // Before the loop, so that a parse error occurring *after* `--json` was read still
    // reaches the report rather than leaving whatever was there before.
    json_arena = arena_state.allocator();
    var i: usize = if (mode == .replay) 3 else 2;
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
        else if (std.mem.eql(u8, argv[i], "--marker")) args.marker = v
        else if (std.mem.eql(u8, argv[i], "--config")) args.config = v
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

    // A replay's define comes from the case file itself: the counterexample's
    // identity includes what was run, not just where it was killed (ADR 0009).
    var replay_case: ?ReplayCase = null;
    var only_k: ?u32 = null;
    if (mode == .replay) {
        if (args.state != null or args.setup != null or args.operation != null or
            args.check != null or args.marker != null or args.config != null)
            setupError("replay takes its define from the case file; the define-surface flags and --config do not apply");
        const rarena = arena_state.allocator();
        const ctext = readFileAllocCapped(rarena, case_arg.?, 1024 * 1024) orelse setupError(
            std.fmt.allocPrint(rarena, "the case file could not be read (missing, unreadable, or over 1 MiB): {s}", .{case_arg.?}) catch "the case file could not be read",
        );
        const parsed = std.json.parseFromSlice(ReplayCase, rarena, ctext, .{}) catch
            setupError("the case file could not be parsed as a sideeye case");
        const c = parsed.value;
        if (!std.mem.eql(u8, c.schema, "sideeye/case"))
            setupError("the file does not declare itself a sideeye case");
        if (c.case_version != 1)
            setupError("this binary understands case schema version 1 only");
        if (c.contract_version != contract.contract_version)
            unknown(.case_no_longer_applies, "the case was recorded under a different trace contract; the crash-point numbering does not carry over");
        args.state = c.define.state;
        args.setup = c.define.setup;
        args.operation = c.define.operation;
        args.check = c.define.check;
        args.marker = c.define.marker;
        replay_case = c;
        only_k = c.k;
        // From here on, every verdict — including a refusal — names the case it is
        // about, in text and JSON alike.
        case_note = case_arg.?;
    }

    // The define surface comes from exactly one place (ADR 0007): a config file or
    // the flags, never a merge — a precedence table would make the file unreadable
    // on its own, and which line was in effect would be invisible.
    if (args.config) |cfg_path| {
        if (args.state != null or args.setup != null or args.operation != null or args.check != null or args.marker != null)
            setupError("--config and the define-surface flags (--state, --setup, --operation, --check, --marker) are mutually exclusive: the define lives in one place or the other");
        const arena = arena_state.allocator();
        const text = readFileAlloc(arena, cfg_path) orelse setupError(
            std.fmt.allocPrint(arena, "--config could not be read: {s}", .{cfg_path}) catch "--config could not be read",
        );
        switch (config.parse(arena, text) catch setupError("out of memory")) {
            .ok => |d| {
                // The dirname is absolutized before anything resolves against it: the
                // resolved define is what a saved case stores as the counterexample's
                // identity, and a relative spelling would make the case mean a
                // different command from every other cwd.
                const dir_raw = std.fs.path.dirname(cfg_path) orelse ".";
                var dir_z: [contract.max_path]u8 = undefined;
                const dz = std.fmt.bufPrintZ(&dir_z, "{s}", .{dir_raw}) catch setupError("--config path is too long");
                var dir_real: [contract.max_path]u8 = undefined;
                const dir_abs = posix.realpath(dz.ptr, &dir_real) orelse setupError("--config's directory could not be resolved");
                const dir = arena.dupe(u8, std.mem.span(dir_abs)) catch setupError("out of memory");
                args.state = resolvePathAgainst(arena, dir, d.state);
                args.setup = if (d.setup) |s| resolveCommandAgainst(arena, dir, s) else null;
                args.operation = resolveCommandAgainst(arena, dir, d.operation);
                args.check = if (d.check) |c| resolveCommandAgainst(arena, dir, c) else null;
                args.marker = d.marker;
            },
            .fault => |f| {
                const msg = if (f.line == 0)
                    std.fmt.allocPrint(arena, "{s}: {s}", .{ cfg_path, f.what }) catch f.what
                else
                    std.fmt.allocPrint(arena, "{s} line {d}: {s}", .{ cfg_path, f.line, f.what }) catch f.what;
                setupError(msg);
            },
        }
    }

    const state = args.state orelse setupError("--state is required");
    const operation = args.operation orelse setupError("--operation is required");
    const shim = args.shim orelse setupError("--shim is required in v0.1");
    if (args.marker) |m| {
        if (m.len == 0) setupError("the marker is empty");
        if (m.len >= 4096) setupError("the marker is unreasonably long (>= 4 KiB)");
        l1_configured = true;
        l1_note = "marker configured; the recording run has not been scanned yet";
    }

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

    // The operation's stdout is evidence — the L1 marker is read from it (ADR 0008) —
    // so every operation run (recording, worlds, baseline) writes it to the work
    // directory. Every run gets the same shape whether or not a marker is configured:
    // an isatty branch in the target must not differ between the recording run and
    // the worlds, or the recorded operation sequence describes a different execution.
    var rec_stdout_buf: [contract.max_path]u8 = undefined;
    const rec_stdout = std.fmt.bufPrint(&rec_stdout_buf, "{s}/stdout-record.txt", .{args.work}) catch setupError("path too long");
    removeFile(rec_stdout);

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
            // directory never appears anywhere. setsid/setpgid are named explicitly
            // because `%process` does not include them (measured), and an *unshimmed*
            // child detaching from the containment group is visible nowhere else.
            for ([_][]const u8{ "-f", "-y", "-e", "trace=%file,%desc,%process,setsid,setpgid", "-o", oracle_out }) |a|
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
            break :blk posix.runChildCapture(gpa, list.items, &.{}, rec_stdout) catch setupError("could not run --operation under the oracle");
        }
        break :blk posix.runChildCapture(gpa, op_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, rec_trace },
            .{ preload_var, shim },
        }, rec_stdout) catch setupError("could not run --operation");
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

    // A marker the clean run cannot produce would make every post-success obligation
    // vacuous while the report still said PASS (ADR 0008). Checked against the
    // recording run — the run that completes normally, where even an unflushed stdio
    // buffer reaches the capture through the exit-time flush. A crash world killed
    // before the marker is not this: there the conditional simply does not apply.
    if (args.marker) |m| {
        const seen = fileContains(rec_stdout, m) catch
            setupError("the recording run's stdout capture could not be read back");
        if (!seen) {
            l1_note = "marker configured; never observed, even in the recording run";
            unknown(.marker_never_observed, "the success marker never appeared in the recording run's own stdout; check the marker string, and whether the target writes it to stdout at all");
        }
        l1_note = "marker observed in the recording run; crash worlds not explored yet";
    }

    var trace = engine.readTrace(gpa, rec_trace) catch setupError("could not read the trace");
    defer trace.deinit();

    var final = engine.takeSnapshot(gpa, state_abs) catch setupError("could not snapshot the final state");
    defer final.deinit();

    // Classified before the structural detectors, so every exit below — including the
    // UNKNOWNs — reports the classification that actually existed, not a placeholder.
    // The plan is the single source for both the judgement and the report (ADR 0004).
    var l0_plan = engine.classify(gpa, initial, final) catch setupError("out of memory");
    defer l0_plan.deinit();
    l0_history_count = l0_plan.history_count;
    l0_note = buildL0Note(arena, l0_plan);

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

    // The boundaries that stay refusals whatever an oracle says. exec replaces the
    // image the crash points were read from; a thread makes operation order
    // non-deterministic; a process that left the containment group is one the engine
    // cannot claim to have stopped. Read from `hard_boundary`, not `boundary`: the
    // first boundary in the trace can be a tolerable fork written *before* the record
    // that must refuse the run, and the refusal must not lose to it.
    if (trace.hard_boundary) |b| switch (b) {
        .exec => unknown(.child_process_detected, "the target replaced its own image (exec); the crash-point addresses do not survive an image change"),
        .thread => unknown(.multiple_threads_detected, "the target created a thread; operation order would not be deterministic"),
        .detached => unknown(.child_process_detected, "a process left the containment group (setsid/setpgid); the engine cannot claim to have stopped it"),
        else => {},
    };

    // The shim-side second witness, on the recording run. Crash points are numbered per
    // process; an operation by anyone else has no unique address and cannot be judged.
    //
    // Under an oracle this overlaps the oracle's own touch check for children the shim
    // can see — measured: disabling this line alone changes no toy's verdict — but the
    // overlap is not subsumption in either direction. The oracle reads paths textually
    // from strace output and misses a child's *relative* spelling of a state path, which
    // the shim resolves against the child's cwd; the shim misses any child that never
    // loaded it, which the oracle sees. Two witnesses with different blind spots, kept
    // deliberately.
    if (trace.foreign_kill_point)
        unknown(.child_touched_state_dir, "a process other than the subject performed a state-directory operation during the recording run");

    // A fork/spawn boundary — or any record from another pid — is tolerable only when
    // an oracle can account for what the other processes did. The shim only sees
    // processes that load it, and "was not seen" must never be read as "did nothing".
    // Mutable: the oracle can reveal children the shim never saw (a raw clone whose
    // child loads nothing), and every consequence of having crossed a boundary — the
    // quiescence sampling above all — must engage for those too.
    var crossed_boundary = trace.boundary != null or trace.foreign_pid_seen;
    if (crossed_boundary and args.oracle == null)
        unknown(.boundary_without_oracle, "the target crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; pass --oracle (Linux)");

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
        // The oracle resolves relative paths against the subject's cwd (ADR 0006). The
        // subject inherits the engine's cwd — `runChild` does not chdir — so that is the
        // starting value; the subject's own chdir/fchdir move it from there. The alt
        // spelling is passed only when it genuinely differs, so containment accepts both.
        var oracle_cwd_buf: [contract.max_path]u8 = undefined;
        const oracle_cwd = if (posix.getcwd(&oracle_cwd_buf, oracle_cwd_buf.len)) |p| std.mem.span(p) else "/";
        const parsed = oracle.parse(arena, text, state_abs, if (alt_differs) state_alt else "", oracle_cwd) catch setupError("out of memory");

        // An oracle that observed nothing agrees with a shim that observed nothing, and
        // the report says "agreed" either way. The acceptance suite asserts by hand that
        // more than ten lines were examined; the tool itself shipped without the check
        // its own suite considered necessary.
        if (parsed.lines_seen == 0)
            unknown(.oracle_saw_nothing, "the oracle produced no output, so nothing was compared against the shim's account");

        if (parsed.boundary) |name|
            unknown(.child_process_detected, name);

        // The tolerance condition, decided by the observer that sees children whether
        // or not they loaded the shim.
        if (parsed.child_touched)
            unknown(.child_touched_state_dir, "a process other than the subject touched the state directory; its operations have no crash-point address");

        if (parsed.unsupported) |name|
            unknown(.unsupported_syscall_observed, name);

        var shim_classes: std.ArrayList(contract.OpClass) = .empty;
        // Index-aligned with shim_classes, so a refusal can say what the shim's
        // account holds at the divergence instead of only that one exists (#41).
        var shim_ops: std.ArrayList(engine.Op) = .empty;
        for (trace.ops.items) |op| {
            if (op.class.isMarker() or op.class.isBoundary()) continue;
            // close stays in the trace but leaves the comparison (ADR 0003): the oracle
            // sees descriptors the shim never saw born, and pairing closes across the
            // two views has no honest fixpoint.
            if (op.class == .close) continue;
            // Only the subject's account is compared against the oracle's view of the
            // subject. A tolerated child's records (its own shim_ready arrives when it
            // execs something dynamically linked) are not operations to reconcile.
            if (trace.primary_pid != null and op.pid != trace.primary_pid.?) continue;
            shim_classes.append(arena, op.class) catch setupError("out of memory");
            shim_ops.append(arena, op) catch setupError("out of memory");
        }

        if (oracle.compare(shim_classes.items, parsed.classes.items)) |f| switch (f) {
            .missed => |m| unknown(.oracle_missed_operation, divergenceDetail(
                arena,
                "the oracle saw a state-directory operation the shim did not record",
                m.index,
                shim_ops.items,
                parsed.lines.items,
            )),
            .phantom => |p| unknown(.oracle_saw_phantom, divergenceDetail(
                arena,
                "the shim recorded an operation the oracle did not see",
                p.index,
                shim_ops.items,
                parsed.lines.items,
            )),
            .unsupported => |name| unknown(.unsupported_syscall_observed, name),
        };

        oracle_note = std.fmt.allocPrint(
            arena,
            "agreed on {d} operations ({d} syscall lines examined, {d} touching the state directory)",
            .{ parsed.classes.items.len, parsed.lines_seen, parsed.lines_in_scope },
        ) catch "agreed";

        if (parsed.children > 0) {
            crossed_boundary = true;
            boundary_note = std.fmt.allocPrint(
                arena,
                "{d} other process(es) observed; none touched the state directory. A FAIL's window is attributed to the subject only",
                .{parsed.children},
            ) catch "crossed, tolerated";
        }
    }

    // Quiescence, observed rather than proven. A tolerated child was killed with the
    // group, but a grandchild reparented away is nobody's child to wait for — so when a
    // boundary was crossed, the final state is sampled twice and any disagreement is a
    // writer still alive. Two equal samples do not prove a future writer cannot exist;
    // the report says "observed", never "proven".
    if (crossed_boundary) {
        var final_again = engine.takeSnapshot(gpa, state_abs) catch setupError("could not re-snapshot the final state");
        defer final_again.deinit();
        if (!snapshotsEqual(final, final_again))
            unknown(.state_not_quiescent, "the state directory changed between two samples taken after the recording run was contained: something is still writing");
    }

    if (!snapshotsEqual(initial, final) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed while zero mutating operations were recorded: operations were missed");

    const n = trace.kill_point_count;
    crash_points = n;

    // The landing context, before anything is explored — including before the
    // zero-crash-points PASS below, which would otherwise answer for a case whose
    // operations have all disappeared. Classes gate; paths only warn (pid-embedded
    // temp names legitimately differ between runs — the timewarrior shape).
    if (replay_case) |rc| {
        if (rc.ops_total != n)
            unknown(.case_no_longer_applies, std.fmt.allocPrint(arena, "the recording now counts {d} state-changing operation(s); the case was recorded over {d}", .{ n, rc.ops_total }) catch "the operation count changed");
        if (rc.k < 1 or rc.k > n)
            unknown(.case_no_longer_applies, "the case's crash point is out of range for this recording");
        var hh: [16]u8 = undefined;
        if (!prefixHash(trace, rc.k, &hh))
            unknown(.case_no_longer_applies, "the recording's operation numbering has a gap before the crash point; nothing can vouch that the recorded index still names the same operation");
        if (!std.mem.eql(u8, &hh, rc.prefix_hash))
            unknown(.case_no_longer_applies, "the class sequence leading to the crash point changed; killing at the recorded index would address a different operation");
        const addr = trace.logicalAddress(rc.k);
        const after_class = if (addr.after) |a| a.class.name() else "(start)";
        const before_class = if (addr.before) |b| b.class.name() else "(end)";
        if (!std.mem.eql(u8, after_class, rc.after_class) or !std.mem.eql(u8, before_class, rc.before_class))
            unknown(.case_no_longer_applies, "the operations around the crash point changed class; the case names a different window");
        const after_path = if (addr.after) |a| a.path else "";
        const before_path = if (addr.before) |b| b.path else "";
        if (!std.mem.eql(u8, after_path, rc.after_path) or !std.mem.eql(u8, before_path, rc.before_path))
            say("note: the paths at the crash point differ from the recorded case (often pid-embedded temp names); the class structure matches, so the replay proceeds\n", .{});
    }
    if (n == 0) {
        requireCompleteness(args.oracle != null, args.allow_unverified);
        say(
            \\PASS  the operation performed nothing that can change the state directory
            \\      explored 0 crash points; nothing to kill before
            \\      atomicity: {s}
            \\      l1: {s}
            \\      case: {s}
            \\      not tested: {s}
            \\
        , .{ l0_note, l1_note, case_note, notTestedText() });
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
    var first_failure_l0 = false;
    var first_failure_l1 = false;
    var first_failure_l2 = false;
    var first_failure_path: [contract.max_path]u8 = undefined;
    var first_failure_path_len: usize = 0;
    var marker_worlds: u32 = 0;
    var checks_run: u32 = 0;

    var world_stdout_buf: [contract.max_path]u8 = undefined;
    const world_stdout = std.fmt.bufPrint(&world_stdout_buf, "{s}/stdout-world.txt", .{args.work}) catch setupError("path too long");

    var k: u32 = 1;
    while (k <= n + 1) : (k += 1) {
        // A replay explores exactly the case's world plus the baseline; every trust
        // gate inside this loop still runs (ADR 0009) — a replay that skipped them
        // would blame the target for whatever the skipped gate existed to catch.
        if (only_k) |okk| {
            if (k != okk and k != n + 1) continue;
        }
        engine.restore(initial, state_abs) catch setupError("could not restore the state directory");

        var kbuf: [16]u8 = undefined;
        const kstr = std.fmt.bufPrint(&kbuf, "{d}", .{k}) catch unreachable;
        var wt_buf: [contract.max_path]u8 = undefined;
        const world_trace = std.fmt.bufPrint(&wt_buf, "{s}/trace-{d}.bin", .{ args.work, k }) catch setupError("path too long");
        removeFile(world_trace);
        removeFile(world_stdout);

        const term = posix.runChildCapture(gpa, op_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, world_trace },
            .{ contract.env.kill_at, kstr },
            .{ preload_var, shim },
        }, world_stdout) catch setupError("could not run --operation");

        var wtrace = engine.readTrace(gpa, world_trace) catch setupError("could not read a world trace");
        defer wtrace.deinit();

        // The second witness again, on every explored world and the baseline. A child's
        // behaviour is allowed to differ between worlds — the parent dying earlier
        // changes which path the child takes — so clearing the recording run clears
        // nothing else.
        if (wtrace.foreign_kill_point)
            unknown(.child_touched_state_dir, "a process other than the subject performed a state-directory operation in an explored world");
        if (wtrace.hard_boundary) |hb| switch (hb) {
            .detached => unknown(.child_process_detected, "a process left the containment group in an explored world"),
            .thread => unknown(.multiple_threads_detected, "the target created a thread in an explored world"),
            .exec => unknown(.child_process_detected, "the target replaced its own image in an explored world"),
            else => {},
        };

        // Landing evidence: the kill must have happened where it was asked for, *to the
        // subject*. seq alone is not enough — a spawned child inherits SIDEEYE_KILL_AT
        // and counts its own operations, and its k-th is a different address entirely.
        const landed = wtrace.kill_landed_seq != null and wtrace.kill_landed_seq.? == k and
            wtrace.kill_landed_pid != null and wtrace.primary_pid != null and
            wtrace.kill_landed_pid.? == wtrace.primary_pid.?;
        if (k <= n and !landed)
            unknown(.kill_did_not_land, "a world was asked to die before a given operation and did not");
        if (k <= n and !term.isSignal(posix.SIGKILL))
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

        // Same observation as after the recording run: when a boundary was crossed,
        // one sample is a moment and two agreeing samples are a state.
        if (crossed_boundary) {
            var crashed_again = engine.takeSnapshot(gpa, state_abs) catch setupError("could not re-snapshot a crashed state");
            defer crashed_again.deinit();
            if (!snapshotsEqual(crashed, crashed_again))
                unknown(.state_not_quiescent, "the crashed state changed between two samples: something the subject started is still writing");
        }

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
            checks_run += 1;
            l2_failed = switch (ct) {
                .exited => |code| code != 0,
                else => true,
            };
        }

        const l0 = engine.judgeL0(l0_plan, crashed);

        // The post-success invariant (ADR 0008), only in worlds where the operation's
        // own success claim reached stdout before the kill. In every other world the
        // conditional does not apply — which is the normal shape of a post-success
        // invariant, not a gap: L0 and the checker judged every world above.
        var marker_seen = false;
        if (args.marker) |m| marker_seen = fileContains(world_stdout, m) catch
            setupError("a world's stdout capture could not be read back");
        if (marker_seen and k <= n) marker_worlds += 1;
        const l1 = if (marker_seen) engine.judgeL1(l0_plan, initial, final, crashed) else null;

        // The baseline world was never killed. If the invariant fails there, it fails
        // without any help from sideeye — the checker rejects a state the operation
        // produces normally, or the operation is broken on its own — and neither is a
        // crash-consistency counterexample. Reporting it as "N of N crash worlds violated
        // an invariant" blames crashing for something that happens without it.
        //
        // Reachable two ways: a checker that rejects the operation's normal output, or
        // an operation whose re-run writes different bytes than the recorded final —
        // the baseline is a fresh execution, not the recorded snapshot. (An earlier
        // comment here claimed only the first path exists; the first real target
        // arrived through the second.) The history form (ADR 0004) removes the second
        // path for files that only grow; a non-reproducible *rewrite* still lands
        // here, and that refusal is the honest one: its crash worlds could not be
        // judged either.
        if (k > n and (l0 != null or l2_failed or l1 != null))
            unknown(.baseline_violates_invariant, "the invariant failed in the world that was never crashed, so nothing found here is a consequence of crashing; check the operation and the checker against each other first");

        if (l0 != null or l2_failed or l1 != null) {
            violations += 1;
            if (first_failure == null) {
                const v = l0 orelse l1;
                first_failure = .{ .k = k, .term = term, .landed = landed, .violation = v };
                first_failure_l0 = l0 != null;
                first_failure_l1 = l1 != null;
                first_failure_l2 = l2_failed;
                if (v) |vv| {
                    const p = switch (vv) {
                        .missing => |p| p,
                        .hybrid => |p| p,
                        .rewritten => |p| p,
                        .not_durable => |p| p,
                    };
                    @memcpy(first_failure_path[0..p.len], p);
                    first_failure_path_len = p.len;
                }
            }
        }
    }

    if (l1_configured) {
        l1_note = std.fmt.allocPrint(
            arena,
            "marker observed in {d} of {d} crash worlds; the post-success invariant was enforced there",
            .{ marker_worlds, n },
        ) catch "marker configured";
    }
    if (check_argv != null) {
        checker_note = std.fmt.allocPrint(
            arena,
            "{s}; ran in {d} world(s)",
            .{ checker_note, checks_run },
        ) catch checker_note;
    }

    // ---- report --------------------------------------------------------------------
    if (first_failure) |f| {
        const addr = trace.logicalAddress(f.k);
        const after = if (addr.after) |a| a.class.name() else "(start)";
        const after_path = if (addr.after) |a| a.path else "";
        const before = if (addr.before) |b| b.class.name() else "(end)";
        const before_path = if (addr.before) |b| b.path else "";
        const invariant = if (first_failure_l0 and first_failure_l2)
            "built-in atomicity, and the checker"
        else if (first_failure_l0)
            "built-in atomicity (L0)"
        else if (first_failure_l1 and first_failure_l2)
            "the post-success invariant, and the checker"
        else if (first_failure_l1)
            "the post-success invariant (L1)"
        else
            "the checker (L2)";
        const what = if (f.violation) |v| switch (v) {
            .missing => "present before and after the operation, but gone from the crashed state",
            .hybrid => "holding neither the old nor the new content",
            .rewritten => "present, but its recorded history is no longer a prefix of its content",
            .not_durable => "the operation claimed success before the kill, and this part of the new state did not survive",
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
        // The counterexample outlives the console (ADR 0009). Saved on explore only:
        // a replay re-verifies an existing case, it does not mint another.
        const saved_case: ?[]const u8 = if (only_k == null) blk: {
            // The stored state is the resolved spelling: a case must mean the same
            // state directory from any cwd, or the replay silently sets up elsewhere.
            var case_args = args;
            case_args.state = state_abs;
            break :blk writeCase(arena, args.work, case_args, f.k, n, trace, if (f.violation) |v| @tagName(v) else "checker");
        } else null;
        const case_shown = saved_case orelse (if (mode == .replay) case_arg.? else "(not saved)");
        const replay_cmd = if (saved_case) |sc|
            std.fmt.allocPrint(arena, "sideeye replay {s} --shim {s}", .{ sc, shim }) catch "-"
        else if (mode == .replay)
            "(this run is a replay; the case reproduced)"
        else
            "-";
        case_note = case_shown;
        replay_note = replay_cmd;
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
            \\atomicity   {s}
            \\oracle      {s}
            \\checker     {s}
            \\l1          {s}
            \\case        {s}
            \\replay      {s}
            \\processes   {s}
            \\not tested  {s}
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
            l0_note,
            oracle_note,
            checker_note,
            l1_note,
            case_shown,
            replay_cmd,
            boundary_note,
            notTestedText(),
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
        \\      atomicity: {s}
        \\      oracle: {s}
        \\      checker: {s}
        \\      l1: {s}
        \\      case: {s}
        \\      processes: {s}
        \\      not tested: {s}
        \\
    , .{ explored, explored, explored, n, l0_note, oracle_note, checker_note, l1_note, case_note, boundary_note, notTestedText() });
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

/// One sentence naming which form judged which files. Counts and names come from the
/// same L0Plan the judgement reads (ADR 0004), so the report cannot describe a
/// different classification than the one that ran. Names are bounded — the point is
/// "which files got the weaker claim", not an inventory.
fn buildL0Note(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
    const standard = plan.files.items.len - @as(usize, plan.history_count);
    if (plan.history_count == 0) {
        return std.fmt.allocPrint(arena, "{d} file(s) judged pre-or-post", .{standard}) catch "classified";
    }
    var names: std.ArrayList(u8) = .empty;
    var listed: u32 = 0;
    for (plan.files.items) |f| {
        if (f.form != .history) continue;
        if (listed == 3) break;
        if (listed > 0) names.appendSlice(arena, ", ") catch return "classified";
        appendSanitized(&names, arena, f.rel) catch return "classified";
        listed += 1;
    }
    if (plan.history_count > listed) {
        const more = std.fmt.allocPrint(arena, " (+{d} more)", .{plan.history_count - listed}) catch return "classified";
        names.appendSlice(arena, more) catch return "classified";
    }
    return std.fmt.allocPrint(
        arena,
        "{d} file(s) judged pre-or-post; {d} file(s) judged by the history form (appended tails not judged): {s}",
        .{ standard, plan.history_count, names.items },
    ) catch "classified";
}

/// Target-chosen file names go into the text report verbatim, and a Unix file name may
/// contain newlines and control bytes — enough to forge whole report lines. The JSON
/// side is escaped in `jsonString`; this is the text side's equivalent for the l0
/// note. (The FAIL block's path fields have carried the same exposure since v0.1 and
/// are tracked as their own issue — this guards the surface this change adds.)
fn appendSanitized(names: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}!void {
    for (s) |ch| {
        try names.append(arena, if (ch < 0x20 or ch == 0x7f) '?' else ch);
    }
}

/// The `not tested` list is not constant: whenever any file was judged by the history
/// form, its appended tail joined the untested set, and a PASS headline must not
/// stand without that narrowing beside it.
fn notTestedText() []const u8 {
    const history = l0_history_count > 0;
    if (history and l1_configured)
        return "power loss, torn writes, concurrent processes, appended tails (files under the history form), post-only file contents (L1 checks existence only)";
    if (history)
        return "power loss, torn writes, concurrent processes, appended tails (files under the history form)";
    if (l1_configured)
        return "power loss, torn writes, concurrent processes, post-only file contents (L1 checks existence only)";
    return "power loss, torn writes, concurrent processes";
}

fn notTestedJson() []const u8 {
    const history = l0_history_count > 0;
    if (history and l1_configured)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\", \"post-only file contents (L1 checks existence only)\"]";
    if (history)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\"]";
    if (l1_configured)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"post-only file contents (L1 checks existence only)\"]";
    return "[\"power loss\", \"torn writes\", \"concurrent processes\"]";
}

/// Whether the file at `path` contains `needle`, read in chunks with an overlap so a
/// marker straddling a chunk boundary is still found — without holding a chatty
/// target's whole stdout in memory across a few hundred worlds. An unreadable capture
/// is an error, never "absent": absence decides whether L1 applies to a world, and an
/// I/O failure silently read as absence would skip the invariant on the PASS side.
fn fileContains(path: []const u8, needle: []const u8) error{Unreadable}!bool {
    if (needle.len == 0) return false;
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return error.Unreadable;
    const fd = posix.open(z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return error.Unreadable;
    defer _ = posix.close(fd);
    var buf: [64 * 1024]u8 = undefined;
    if (needle.len >= buf.len) return error.Unreadable;
    var kept: usize = 0;
    while (true) {
        const nr = posix.read(fd, buf[kept..].ptr, buf.len - kept);
        if (nr < 0) {
            if (std.c._errno().* == posix.EINTR) continue;
            return error.Unreadable;
        }
        if (nr == 0) return false;
        const have = kept + @as(usize, @intCast(nr));
        if (std.mem.indexOf(u8, buf[0..have], needle) != null) return true;
        kept = @min(needle.len - 1, have);
        std.mem.copyForwards(u8, buf[0..kept], buf[have - kept .. have]);
    }
}

test "fileContains finds a marker straddling the chunk boundary" {
    // posix directly, like the engine itself: the std file API wants an `Io` instance
    // threaded through every call, and this test needs one file, not a runtime.
    const path = ".zig-cache/tmp-filecontains-test.txt";
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch unreachable;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    // 64 KiB of padding minus half the marker, so MARKER spans the read boundary.
    var pad: [64 * 1024 - 3]u8 = undefined;
    @memset(&pad, 'x');
    try std.testing.expect(posix.write(fd, &pad, pad.len) == pad.len);
    try std.testing.expect(posix.write(fd, "MARKER", 6) == 6);
    _ = posix.close(fd);
    defer removeFile(path);
    try std.testing.expect(try fileContains(path, "MARKER"));
    try std.testing.expect(!try fileContains(path, "ABSENT"));
    try std.testing.expectError(error.Unreadable, fileContains(".zig-cache/no-such-capture", "X"));
}

/// `readFileAlloc` with a ceiling: a case file is caller-supplied input, and reading
/// until EOF from something that never ends (a device, a fifo) would hang the run
/// before any refusal could fire. Over the cap answers like unreadable.
fn readFileAllocCapped(arena: std.mem.Allocator, path: []const u8, cap: usize) ?[]const u8 {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    const fd = posix.open(z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n < 0) return null;
        if (n == 0) break;
        list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
        if (list.items.len > cap) return null;
    }
    return list.items;
}

fn readFileAlloc(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    // A read error is not end of file (the shared loop returns null for it): treating
    // them alike once turned a truncated oracle file into a complete one, and the
    // comparison that followed was against however much happened to arrive.
    return readFileAllocCapped(arena, path, std.math.maxInt(usize));
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

    try w.appendSlice(arena, ",\n  \"l0\": ");
    try jsonString(w, arena, l0_note);
    try w.appendSlice(arena, ",\n  \"l1\": ");
    try jsonString(w, arena, l1_note);
    try w.appendSlice(arena, ",\n  \"case\": ");
    try jsonString(w, arena, case_note);
    try w.appendSlice(arena, ",\n  \"replay\": ");
    try jsonString(w, arena, replay_note);
    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    try w.appendSlice(arena, ",\n  \"checker\": ");
    try jsonString(w, arena, checker_note);
    try w.appendSlice(arena, ",\n  \"processes\": ");
    try jsonString(w, arena, boundary_note);
    // Stated in the report itself, not only in the documentation: a PASS that does not
    // say what it did not look at is the kind of reassurance this tool refuses to give.
    try w.appendSlice(arena, ",\n  \"not_tested\": ");
    try w.appendSlice(arena, notTestedJson());
    try w.appendSlice(arena, "\n}\n");
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

/// A relative path in a sideeye.toml means "relative to the toml", not to wherever
/// the process happens to run (ADR 0007) — the same file has to mean the same thing
/// from anywhere, or a replayed define quietly points at a different state.
fn resolvePathAgainst(arena: std.mem.Allocator, dir: []const u8, path: []const u8) []const u8 {
    if (path.len == 0 or path[0] == '/') return path;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, path }) catch setupError("out of memory");
}

/// Commands resolve their argv[0] only when it names a place (`./check.sh`), never a
/// program (`mytool` stays a PATH lookup). The rest of the string is untouched — the
/// split-on-spaces rule is the flags' rule, written into ADR 0007. argv[0] is found
/// the way the executor finds it — after skipping leading spaces — or a value like
/// `" ./check.sh"` would slip past resolution and run cwd-relative, quietly breaking
/// the "same file means the same thing from anywhere" rule.
fn resolveCommandAgainst(arena: std.mem.Allocator, dir: []const u8, cmd: []const u8) []const u8 {
    var start: usize = 0;
    while (start < cmd.len and cmd[start] == ' ') start += 1;
    const rest = cmd[start..];
    const sp = std.mem.indexOfScalar(u8, rest, ' ');
    const head = if (sp) |p| rest[0..p] else rest;
    const tail = if (sp) |p| rest[p..] else "";
    if (head.len == 0 or head[0] == '/' or std.mem.indexOfScalar(u8, head, '/') == null) return cmd;
    return std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ dir, head, tail }) catch setupError("out of memory");
}

test "toml paths resolve against the toml's directory, commands only when they name a place" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    try std.testing.expectEqualStrings("/cfg/./state", resolvePathAgainst(a, "/cfg", "./state"));
    try std.testing.expectEqualStrings("/abs", resolvePathAgainst(a, "/cfg", "/abs"));
    try std.testing.expectEqualStrings("/cfg/./check.sh --strict", resolveCommandAgainst(a, "/cfg", "./check.sh --strict"));
    try std.testing.expectEqualStrings("mytool rotate-key", resolveCommandAgainst(a, "/cfg", "mytool rotate-key"));
    try std.testing.expectEqualStrings("/usr/bin/tool x", resolveCommandAgainst(a, "/cfg", "/usr/bin/tool x"));
    // argv[0] is found the way the executor finds it: leading spaces must not let a
    // place-naming command slip past resolution and run cwd-relative.
    try std.testing.expectEqualStrings("/cfg/./check.sh", resolveCommandAgainst(a, "/cfg", " ./check.sh"));
}

/// FNV-1a over the class names of the subject's counted operations 1..k, hex-encoded.
/// Classes only, deliberately: paths may legitimately differ between runs
/// (pid-embedded temp names), and the replay treats a path difference as a warning,
/// never as identity (ADR 0009).
/// Returns false when any of seq 1..k is missing from the trace: a numbering gap
/// means the recording itself is not a sequence this hash can vouch for, and hashing
/// only what happens to be present would let two differently-broken traces agree.
fn prefixHash(trace: engine.TraceInfo, k: u32, out: *[16]u8) bool {
    var h: u64 = 0xcbf29ce484222325;
    var seq: u32 = 1;
    while (seq <= k) : (seq += 1) {
        var found = false;
        for (trace.ops.items) |op| {
            if (!op.class.isKillPoint()) continue;
            if (trace.primary_pid != null and op.pid != trace.primary_pid.?) continue;
            if (op.seq != seq) continue;
            for (op.class.name()) |ch| {
                h ^= ch;
                h *%= 0x100000001b3;
            }
            h ^= 0x1f; // separator, so ["ab","c"] and ["a","bc"] hash apart
            h *%= 0x100000001b3;
            found = true;
            break;
        }
        if (!found) return false;
    }
    _ = std.fmt.bufPrint(out, "{x:0>16}", .{h}) catch unreachable;
    return true;
}

/// Write the counterexample to `<work>/cases/NNNNNN.json` and return its path. The id
/// is claimed with O_EXCL, so two runs over one work directory cannot silently share a
/// case file. Returns null when nothing could be written — the FAIL report is the
/// product and must not die for the sake of its attachment.
fn writeCase(
    arena: std.mem.Allocator,
    work: []const u8,
    args: Args,
    k: u32,
    ops_total: u32,
    trace: engine.TraceInfo,
    violation_name: []const u8,
) ?[]const u8 {
    var dbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&dbuf, "{s}/cases", .{work}) catch return null;
    _ = posix.mkdir(dz.ptr, 0o755); // EEXIST is fine; open below decides
    const addr = trace.logicalAddress(k);
    var hh: [16]u8 = undefined;
    if (!prefixHash(trace, k, &hh)) return null;

    var doc: std.ArrayList(u8) = .empty;
    const w = &doc;
    var nb: [16]u8 = undefined;
    w.appendSlice(arena, "{\n  \"schema\": \"sideeye/case\",\n  \"case_version\": 1,\n  \"sideeye_version\": ") catch return null;
    jsonString(w, arena, version) catch return null;
    w.appendSlice(arena, ",\n  \"contract_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"define\": {\n    \"state\": ") catch return null;
    jsonString(w, arena, args.state.?) catch return null;
    if (args.setup) |s| {
        w.appendSlice(arena, ",\n    \"setup\": ") catch return null;
        jsonString(w, arena, s) catch return null;
    }
    w.appendSlice(arena, ",\n    \"operation\": ") catch return null;
    jsonString(w, arena, args.operation.?) catch return null;
    if (args.check) |c| {
        w.appendSlice(arena, ",\n    \"check\": ") catch return null;
        jsonString(w, arena, c) catch return null;
    }
    if (args.marker) |m| {
        w.appendSlice(arena, ",\n    \"marker\": ") catch return null;
        jsonString(w, arena, m) catch return null;
    }
    w.appendSlice(arena, "\n  },\n  \"k\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{k}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"ops_total\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{ops_total}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"prefix_hash\": ") catch return null;
    jsonString(w, arena, &hh) catch return null;
    w.appendSlice(arena, ",\n  \"after_class\": ") catch return null;
    jsonString(w, arena, if (addr.after) |a| a.class.name() else "(start)") catch return null;
    w.appendSlice(arena, ",\n  \"after_path\": ") catch return null;
    jsonString(w, arena, if (addr.after) |a| a.path else "") catch return null;
    w.appendSlice(arena, ",\n  \"before_class\": ") catch return null;
    jsonString(w, arena, if (addr.before) |b| b.class.name() else "(end)") catch return null;
    w.appendSlice(arena, ",\n  \"before_path\": ") catch return null;
    jsonString(w, arena, if (addr.before) |b| b.path else "") catch return null;
    w.appendSlice(arena, ",\n  \"violation\": ") catch return null;
    jsonString(w, arena, violation_name) catch return null;
    w.appendSlice(arena, "\n}\n") catch return null;

    const EEXIST: c_int = 17; // same value on Linux and Darwin
    var id: u32 = 1;
    while (id <= 999999) : (id += 1) {
        var pbuf: [contract.max_path]u8 = undefined;
        const pz = std.fmt.bufPrintZ(&pbuf, "{s}/cases/{d:0>6}.json", .{ work, id }) catch return null;
        const fd = posix.open(pz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o644));
        if (fd < 0) {
            // Only a taken id is worth trying past. An unwritable directory would
            // otherwise spin through a million opens on its way to "(not saved)".
            if (std.c._errno().* == EEXIST) continue;
            return null;
        }
        var off: usize = 0;
        while (off < doc.items.len) {
            const wn = posix.write(fd, doc.items[off..].ptr, doc.items.len - off);
            if (wn <= 0) {
                // A half-written case must not survive: it would both mislead a later
                // replay and permanently consume this id.
                _ = posix.close(fd);
                _ = posix.unlink(pz.ptr);
                return null;
            }
            off += @intCast(wn);
        }
        _ = posix.close(fd);
        return arena.dupe(u8, std.mem.span(pz.ptr)) catch null;
    }
    return null;
}

/// Name the point where the two accounts split: the divergence index (1-based), the
/// raw strace line the oracle holds there, and what the shim's account holds at the
/// same position — or that either account simply ends. The detail travels through
/// `unknown` into the text and the JSON alike (DESIGN §13), so nobody has to decode
/// a binary trace by hand to learn which operation a refusal refused on (#41). On
/// allocation failure the lead sentence alone is returned: the refusal is the point,
/// the naming is the courtesy, and the courtesy must never cost the refusal.
fn divergenceDetail(
    arena: std.mem.Allocator,
    lead: []const u8,
    index: usize,
    shim_ops: []const engine.Op,
    oracle_lines: []const []const u8,
) []const u8 {
    const oracle_part = if (index < oracle_lines.len)
        std.fmt.allocPrint(arena, "the oracle saw: {s}", .{oracle_lines[index]}) catch return lead
    else
        std.fmt.allocPrint(arena, "the oracle's account ends after {d} operation(s)", .{index}) catch return lead;
    const shim_part = if (index < shim_ops.len) blk: {
        const op = shim_ops[index];
        break :blk if (op.aux.len > 0)
            std.fmt.allocPrint(arena, "the shim recorded: {s}(\"{s}\" -> \"{s}\")", .{ @tagName(op.class), op.path, op.aux }) catch return lead
        else
            std.fmt.allocPrint(arena, "the shim recorded: {s}(\"{s}\")", .{ @tagName(op.class), op.path }) catch return lead;
    } else std.fmt.allocPrint(arena, "the shim's account ends after {d} operation(s)", .{index}) catch return lead;
    const composed = std.fmt.allocPrint(arena, "{s}; divergence at operation {d}: {s}; {s}", .{
        lead, index + 1, oracle_part, shim_part,
    }) catch return lead;
    // Shim paths are raw bytes the target chose, and even strace's own escaping is
    // not a contract this report should lean on: a filename carrying a newline or an
    // escape sequence must not be able to forge report lines (the class of #26). One
    // choke point, applied to the whole composed detail, keeps the text and the JSON
    // carrying the same bytes.
    return sanitizeForReport(arena, composed) catch lead;
}

/// Replace bytes below 0x20 (and 0x7f) with a visible `\xNN` spelling. The JSON side
/// escapes controls already; the text side printed them raw, which let target-chosen
/// names inject report lines. Printable bytes pass through untouched.
fn sanitizeForReport(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var clean = true;
    for (s) |ch| {
        if (ch < 0x20 or ch == 0x7f) {
            clean = false;
            break;
        }
    }
    if (clean) return s;
    var out: std.ArrayList(u8) = .empty;
    for (s) |ch| {
        if (ch < 0x20 or ch == 0x7f) {
            var nb: [4]u8 = undefined;
            try out.appendSlice(arena, std.fmt.bufPrint(&nb, "\\x{x:0>2}", .{ch}) catch unreachable);
        } else {
            try out.append(arena, ch);
        }
    }
    return out.items;
}

test "divergence detail escapes a control byte a target put in a path" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const ops = [_]engine.Op{.{
        .class = .open,
        .seq = 1,
        .pid = 1,
        .path = "/tmp/s/evil\nUNKNOWN  forged_reason",
        .aux = "",
    }};
    const lines = [_][]const u8{"openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3"};
    const detail = divergenceDetail(arena_state.allocator(), "lead", 0, &ops, &lines);
    // The newline must arrive spelled out, never as a line break the report obeys.
    try std.testing.expect(std.mem.indexOf(u8, detail, "\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\\x0a") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "divergence at operation 1") != null);
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

test "the l0 note neutralises control bytes in target-chosen file names" {
    // A Unix file name may contain a newline; unescaped it would let a target forge
    // report lines ("log\nnot tested  nothing" reads as two lines of verdict). The
    // note must carry the name defanged. Control: the printable part survives.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var plan: engine.L0Plan = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .files = .empty,
        .history_count = 1,
    };
    defer plan.deinit();
    try plan.files.append(plan.arena.allocator(), .{
        .rel = "evil\nname\x1b.log",
        .form = .history,
        .pre_content = "a",
        .post_content = "ab",
    });

    const note = buildL0Note(arena_state.allocator(), plan);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, '\n') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, note, "evil?name?.log") != null);
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
