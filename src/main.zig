//!     `sideeye` and a word that names no command before anything else (#705); the branches
//!     before parsing (`mcp`, `evidence`, `demo`) are still here, and so are `splitArgs`,
//!     `commandArgv` and the `resolve*` family,
//!     because the freeze audit's rung 1 reads surface 1 out of this file
//!     (`spike/freeze-audit/surface-drift.sh`) and nothing in `cli.zig` calls them; the
//!     digit grammar `expected_status` and `--expect-status` share is `config.parseExpectStatus`
//!     for the same reason.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const image = @import("image.zig");
const oracle = @import("oracle.zig");
const fsusage = @import("fsusage.zig");
const config = @import("config.zig");
const mcp = @import("mcp.zig");
const engine_build_options = @import("engine_build_options");
const boundary = @import("boundary.zig");
const defang = @import("defang.zig");
const capture = @import("capture.zig");
const files = @import("files.zig");
const report = @import("report.zig");
const refuse = @import("refuse.zig");
const workdir = @import("workdir.zig");
const prefix = @import("prefix.zig");
const cli = @import("cli.zig");
const case = @import("case.zig");
const evidence = @import("evidence.zig");
const recovery = @import("recovery.zig");
const controls_mod = @import("controls.zig");
const containment = @import("containment.zig");
const supervise = @import("supervise.zig");
const sanitizeForReport = defang.sanitizeForReport;
const textShown = defang.textShown;
const appendSanitized = defang.appendSanitized;
const removeFile = files.removeFile;
const writeWholeFile = files.writeWholeFile;
const say = report.say;
const setupError = refuse.setupError;
const setupErrorFmt = refuse.setupErrorFmt;
const unknown = refuse.unknown;
const spawnFailure = refuse.spawnFailure;

const trace_cap: usize = if (engine_build_options.trace_cap_override == 0)
    engine.max_trace_bytes
else
    engine_build_options.trace_cap_override;

const trace_cap_world: usize = if (engine_build_options.trace_cap_override_world == 0)
    engine.max_trace_bytes
else
    engine_build_options.trace_cap_override_world;

const trace_budget_limit: usize = if (engine_build_options.trace_budget_override == 0)
    engine.max_trace_bytes_total
else
    engine_build_options.trace_budget_override;

const preload_var = if (builtin.os.tag == .macos) "DYLD_INSERT_LIBRARIES" else "LD_PRELOAD";

const child_env_names = [_][]const u8{ "TOY_STATE", contract.env.state_dir, contract.env.state_dir_alt, contract.env.trace_path, contract.env.seq_base, contract.env.before_constructor, contract.env.observe, contract.env.kill_group, contract.env.run_cgroup, contract.env.kill_cgroup, contract.env.kill_aside, preload_var };

test "every variable the engine sets for a child is refused as apparatus" {
    for (child_env_names) |n| try std.testing.expect(config.engineOwnedEnv(n));
}

var startup_ppid: c_int = 0;
/// leaves the filesystem as it found it. Every vet between those mkdirs and the
/// first destructive step shares this one helper: a refusal branch that forgets
/// half of it would leave a 0755 directory at a path the run just refused to use.
fn undoSetupMkdirs(work_created: bool, work_z: [*:0]const u8, state_created: bool, state_z: [*:0]const u8) void {
    if (work_created) {
        // Do not remove a run.lock this run does not hold: another run that found the directory
        // this one made may be holding it, and a third would then lock a new file beside it.
        if (workdir.lock_fd >= 0) {
            var lock_buf: [contract.max_path]u8 = undefined;
            if (std.mem.printSentinel(&lock_buf, "{s}/run.lock", .{std.mem.span(work_z)}, 0)) |lock_z| _ = posix.unlink(lock_z.ptr) else |_| {}
        }
        _ = posix.rmdir(work_z);
    }
    if (state_created) _ = posix.rmdir(state_z);
}

test "undoing a work directory this run made removes run.lock only while this run holds the lock (#816)" {
    var db: [contract.max_path]u8 = undefined;
    const dir_z = std.mem.printSentinel(&db, "/tmp/sideeye-undo-lock-{d}", .{posix.getpid()}, 0) catch unreachable;
    var lb: [contract.max_path]u8 = undefined;
    const lock_z = std.mem.printSentinel(&lb, "{s}/run.lock", .{dir_z}, 0) catch unreachable;
    var nb: [contract.max_path]u8 = undefined;
    const none_z = std.mem.printSentinel(&nb, "/tmp/sideeye-undo-none-{d}", .{posix.getpid()}, 0) catch unreachable;
    defer {
        _ = posix.unlink(lock_z.ptr);
        _ = posix.rmdir(dir_z.ptr);
    }
    const saved = workdir.lock_fd;
    defer workdir.lock_fd = saved;

    _ = posix.mkdir(dir_z.ptr, 0o755);
    const fd = posix.open(lock_z.ptr, posix.O_WRONLY | posix.O_CREAT, @as(c_uint, 0o600));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    workdir.lock_fd = -1;
    undoSetupMkdirs(true, dir_z.ptr, false, none_z.ptr);
    try std.testing.expect(posix.access(lock_z.ptr, 0) == 0);

    workdir.lock_fd = 99;
    undoSetupMkdirs(true, dir_z.ptr, false, none_z.ptr);
    try std.testing.expect(posix.access(lock_z.ptr, 0) != 0);
    try std.testing.expect(posix.access(dir_z.ptr, 0) != 0);
}

// Not raised from `--world-timeout`: a replay line does not carry it, and it changes what worlds
// do. Not removed either: it is what stops a root fs_usage if the watch is gone too.
const fsusage_time_limit_s: u32 = 1800;

/// Everything that can fail about the observer fails *here*, before the first child of
/// the measured run exists: the credential check, the launch, and the proof that the
/// capture is live. That placement is not a preference — `docs/contract-freeze.md`
/// closes the `unknown_reason` set: a member added after the v1.0 tag is a breaking
/// change that needs its own ruling, so a new way to fail that arrives after the
/// recording has begun has no name to refuse under until a ruling gives it one, and
/// refusing here means it never needs one. (Two earlier revisions of this paragraph
fn startFsUsage(gpa: std.mem.Allocator, arena: std.mem.Allocator, capture_path: []const u8, sentinel: []const u8, limit_s: u32) c_int {
    // `sudo -n`: never prompt. A prompt here would block a run nobody is watching, and
    // the caller who *is* watching gets a message naming the one command to run first.
    // Not `exclusive`: `/dev/null` already exists, so `O_CREAT|O_EXCL` there refuses
    // every time. This capture is a discard, not evidence — there is nothing in the
    // work directory for a planted file to stand in front of.
    const probe = posix.runChildCapture(gpa, &.{ "/usr/bin/sudo", "-n", "/usr/bin/true" }, &.{}, .{ .path = "/dev/null" }, null) catch |e|
        spawnFailure(e, .before_exploration, "could not run sudo to start fs_usage");
    switch (probe) {
        .exited => |c| if (c != 0) setupError(.environment, "fs_usage needs root and sudo has no cached credentials; run `sudo -v` in this terminal first, then re-run. The credential cache is per-terminal, so a `sudo -v` elsewhere does not reach this process"),
        else => setupError(.environment, "the sudo credential check did not exit normally"),
    }

    const limit = std.fmt.allocPrint(arena, "{d}", .{limit_s}) catch setupError(.environment, "out of memory");
    // Unfiltered: `fs_usage`'s pid filter does not follow a fork, so filtering by the
    // subject leaves a raw-forked child invisible to this witness exactly where it is
    // already invisible to the shim (#405). Scope is the state root, decided in
    // `fsusage.read`. `-t` stays behind the watch: SIGPIPE cannot stop a root observer that
    // outlived its parent and holds kdebug, since a process that has stopped writing never
    // learns the reader is gone.
    // No class filter: `-f filesys` drops `dup` and `dup2`, and a write through a moved
    // descriptor is then a write on a number nothing opened (#796).
    const pid = posix.spawnSidecar(gpa, &.{ "/usr/bin/sudo", "-n", "/usr/bin/fs_usage", "-w", "-e", "-t", limit }, capture_path, fsusage.errPath(arena, capture_path) catch setupError(.environment, "out of memory")) catch |e|
        spawnFailure(e, .before_exploration, "could not start fs_usage");
    // Registered before anything below can refuse. From here on, every `setupError`
    // and `unknown` stops it; no call site has to.
    refuse.fsu_live = .{ .pid = pid, .gpa = gpa };
    refuse.fsu_capture = capture_path;
    // Not after the handshake: an engine that died during it would leave a root observer to run
    // out its whole `-t`, nothing else watching.
    if (!posix.watchSidecar(pid))
        setupError(.environment, "could not start the process that stops fs_usage if this run ends without stopping it; refusing rather than leaving a root observer running until its own time limit");

    var zb: [contract.max_path]u8 = undefined;
    const sz = std.mem.printSentinel(&zb, "{s}", .{sentinel}, 0) catch setupError(.define_invalid, "path too long");
    // Created ONCE, before the loop. Inside it, the second iteration's O_EXCL open
    // necessarily fails on the file the first one made — which is how the first
    // version of this refused every run that needed more than one poll, under a
    // message about the *closing* sentinel that named neither the file nor the loop
    // it came from. The O_EXCL that guards against clobbering a state file and the
    const fd = posix.open(sz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o600));
    if (fd < 0) setupError(.environment, "the fs_usage handshake could not create its sentinel inside the state directory; a file of that name is already there, or the directory is not writable");
    _ = posix.close(fd);

    var waited: u64 = 0;
    var seen: u64 = 0; // bytes of the capture already scanned
    while (waited < 10_000) {
        var st: c_int = 0;
        const w = posix.waitpid(pid, &st, posix.WNOHANG);
        if (w == pid or w < 0) {
            posix.releaseSidecarWatch();
            refuse.fsu_live = null;
            removeFile(sentinel);
            posix.noteSidecar(0);
            const said = capture.readFileAllocCapped(arena, fsusage.errPath(arena, capture_path) catch "", 4096, .{ .no_follow = true }) orelse "";
            const trimmed = std.mem.trim(u8, said, " \t\r\n");
            setupError(.environment, std.fmt.allocPrint(arena, "fs_usage exited before the handshake completed{s}{s}; its stderr is {s}, and if it says `ktrace_start: Resource busy`, another fs_usage still holds the kernel trace facility — wait for it, or stop it, and re-run", .{ if (trimmed.len > 0) ", saying: " else "", textShown(arena, trimmed), textShown(arena, fsusage.errPath(arena, capture_path) catch "") }) catch "fs_usage exited before the handshake completed");
        }

        // Flush pressure. fs_usage writes its capture through stdio, and a file is
        // block-buffered: on a quiet machine the sentinel's line can sit in that buffer
        // past the whole ten-second window. Two CI runs on the macOS runner timed out
        // here on different checks while the same script passed every check on a busy
        // laptop, whose neighbours kept the buffer moving. Sixty-four `access` calls on
        // the sentinel path from the engine are about 16 KB of capture — past a 4 KB
        // stdio buffer several times over — and the reader drops them as read-only.
        var pressure: u32 = 0;
        while (pressure < 64) : (pressure += 1) _ = posix.access(sz.ptr, posix.F_OK);

        // A fresh arena per poll: the capture grows while this loop runs, and reading
        // the whole of it ten times into the caller's arena keeps every copy.
        var poll_arena = std.heap.ArenaAllocator.init(gpa);
        defer poll_arena.deinit();
        if (capture.readFileFrom(poll_arena.allocator(), capture_path, seen, 64 * 1024 * 1024)) |a| {
            // The reader's predicate, not a substring search. A raw search matched a
            // system daemon's line about the sentinel and let a run proceed whose
            // capture the reader could then not scope at all (measured, first
            // end-to-end run): a gate looser than the check behind it is not a gate.
            if (fsusage.capturesPath(a.text, sentinel)) {
                removeFile(sentinel);
                return pid;
            }
            seen = a.end;
        }
        posix.sleepForMs(100);
        waited += 100;
    }
    removeFile(sentinel);
    setupError(.environment, "fs_usage started but its capture never showed the engine's own sentinel, so nothing proves the observer was recording; the run would have been judged against a capture of unknown coverage");
}

/// The trace and stdout paths are parameters because each observation needs its own: a
/// second run writing over the first's trace would leave a snapshot being compared
/// against an account that no longer describes it.
fn runOperationObserved(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    op_argv: []const []const u8,
    state_abs: []const u8,
    state_alt: []const u8,
    shim: []const u8,
    oracle_path: ?[]const u8,
    oracle_out: []const u8,
    trace_path: []const u8,
    stdout_path: []const u8,
    cwd: ?[]const u8,
    observe: contract.ObserveMode,
    cg: ?*posix.CgroupSpawn,
) posix.Term {
    const sup = supervise.Spawn.start(gpa, arena, observe, op_argv, trace_path, state_abs, state_alt, 0, containment.runName(cg), containment.killName(cg)) catch |e|
        setupError(.environment, supervise.startFailure(e));
    const argv = sup.argv;
    const env_trace = if (observe == .supervised) "" else trace_path;
    const preload = supervise.preloadFor(observe, shim);
    const term: posix.Term = run: {
        if (oracle_path) |strace_path| {
            // Environment goes to the target via strace's -E, not through our own
            // setenv: LD_PRELOAD applied here would load the shim into strace itself,
            // and strace's own file operations would land in the trace as if the
            // target had produced them.
            var list: std.ArrayList([]const u8) = .empty;
            list.append(arena, strace_path) catch setupError(.environment, "out of memory");
            // `-f` follows children and `%process` covers clone/fork/execve. Without
            // both, a target that creates a child through a raw clone is invisible to
            // the oracle as well as to the shim, and the child's work on the state
            // directory never appears anywhere. setsid/setpgid are named explicitly
            // because `%process` does not include them (measured), and an *unshimmed*
            // child detaching from the containment group is visible nowhere else.
            // `mprotect`, `pkey_mprotect` and `mremap` are not file calls either (#689, ADR
            // 0098): they are how a state file mapped shared and read-only becomes writable or
            // moves, and a store through it has no call of its own. `?` keeps an strace that
            // has no name for `pkey_mprotect` from refusing to start.
            for ([_][]const u8{ "-f", "-y", "-e", "trace=%file,%desc,%process,setsid,setpgid,mprotect,?pkey_mprotect,mremap", "-o", oracle_out }) |a|
                list.append(arena, a) catch setupError(.environment, "out of memory");
            const pairs = [_][2][]const u8{
                .{ "TOY_STATE", state_abs },
                .{ contract.env.state_dir, state_abs },
                .{ contract.env.state_dir_alt, state_alt },
                .{ contract.env.trace_path, env_trace },
                // Pinned empty so an ambient value in the operator's shell cannot
                // become the first image's numbering base (R1; parseU32("") is 0).
                .{ contract.env.seq_base, "" },
                // Pinned empty for the same reason (#753): a carried mark in the operator's shell
                // would refuse every run. Empty is how the shim reads "no mark".
                .{ contract.env.before_constructor, "" },
                .{ contract.env.observe, observe.name() },
                // Pinned empty when there is no cgroup, for the reason `seq_base` is above (v17).
                // The kill path is a world's alone, and pinned empty here for the same reason.
                .{ contract.env.run_cgroup, containment.runName(cg) },
                .{ contract.env.kill_cgroup, "" },
                .{ contract.env.kill_aside, "" },
                .{ preload_var, preload },
            };
            for (pairs) |kv| {
                list.append(arena, "-E") catch setupError(.environment, "out of memory");
                const joined = std.fmt.allocPrint(arena, "{s}={s}", .{ kv[0], kv[1] }) catch setupError(.environment, "out of memory");
                list.append(arena, joined) catch setupError(.environment, "out of memory");
            }
            for (argv) |a| list.append(arena, a) catch setupError(.environment, "out of memory");
            break :run posix.runChildCaptureContained(gpa, list.items, &.{}, recordingCapture(stdout_path), cwd, cg) catch |e| spawnFailure(e, .exploring, "could not run --operation under the oracle");
        }
        break :run posix.runChildCaptureContained(gpa, argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, env_trace },
            // Pinned empty: see the oracle-path pairs above.
            .{ contract.env.seq_base, "" },
            .{ contract.env.before_constructor, "" },
            .{ contract.env.observe, observe.name() },
            // Pinned empty where there is nothing to name: see the oracle-path pairs above.
            .{ contract.env.run_cgroup, containment.runName(cg) },
            .{ contract.env.kill_cgroup, "" },
            .{ contract.env.kill_aside, "" },
            .{ preload_var, preload },
        }, recordingCapture(stdout_path), cwd, cg) catch |e| spawnFailure(e, .exploring, "could not run --operation");
    };
    if (supervise.handoverFailure(sup.finish(), term, "the run")) |why| unknown(.recording_run_failed, why, .environment);
    return term;
}

/// `exclusive` because the caller unlinks the path immediately before this (#469):
/// `O_NOFOLLOW` refuses a *symlink* at the name and does nothing about a **hard link**,
/// which is the same file rather than a pointer to one — so without `O_EXCL` a work
/// directory someone else reached can still turn this capture into an arbitrary-file
/// truncation. Free here precisely because of that unlink, and its reach is bounded by
/// the same fact: what it covers is the window between the unlink and the open, and the
/// case where the unlink silently failed.
fn recordingCapture(stdout_path: []const u8) posix.Capture {
    return .{ .path = stdout_path, .exclusive = true };
}

/// detectors set them). The buffers are fields because the slices into them
/// (`define.state_abs`, `rec.rec_trace`, …) outlive the phase that filled them. Everything
/// below the four values `main()` places — the two allocators and `cli.parse`'s answer — is
/// `undefined` until its phase runs; the phases run in one order, from `main()`, and nowhere
/// else (#572, ADR 0062).
const Run = struct {
    const Define = struct {
        replay_case: ?case.ReplayCase,
        only_k: ?u32,
        state: []const u8,
        operation: config.Command,
        expect_status: u8,
        shim: []const u8,
        state_abs: []const u8,
        state_alt: []const u8,
        alt_differs: bool,
        real_buf: [contract.max_path]u8,
        alt_buf: [contract.max_path]u8,
        work_abs: []const u8,
        work_real_buf: [contract.max_path]u8,
        effective_cwd: ?[]const u8,
        config_dir: ?[]const u8,
    };
    const Recording = struct {
        rec_trace: []const u8,
        op_argv: []const []const u8,
        oracle_out: []const u8,
        rec_stdout: []const u8,
        fsu_sentinel_a: []const u8,
        fsu_sentinel_b: []const u8,
        rec_started_ms: u64,
        rec_capture: capture.CaptureObservation,
        trace: engine.TraceInfo,
        final: engine.Snapshot,
        l0_plan: engine.L0Plan,
        judgeable: refuse.Judgeable,
        cgroup: ?posix.CgroupSpawn,
        rec_trace_buf: [contract.max_path]u8,
        oracle_out_buf: [contract.max_path]u8,
        rec_stdout_buf: [contract.max_path]u8,
        fsu_sentinel_a_buf: [contract.max_path]u8,
        fsu_sentinel_b_buf: [contract.max_path]u8,
    };
    const Admission = struct {
        children_admitted: bool,
        crossed_boundary: bool,
    };
    const Firsts = struct {
        first_failure: ?engine.WorldResult,
        first_failure_l0: bool,
        first_failure_l1: bool,
        first_failure_l2: bool,
        first_failure_path: [contract.max_path]u8,
        first_failure_path_len: usize,
        first_checker: ?engine.WorldResult,
        first_checker_l0: bool,
        first_checker_l1: bool,
        first_checker_path: [contract.max_path]u8,
        first_checker_path_len: usize,
        first_failure_ev: ?evidence.Draft,
        first_checker_ev: ?evidence.Draft,
        marker_worlds: u32,
    };

    gpa: std.mem.Allocator,
    arena_state: *std.heap.ArenaAllocator,
    arena: std.mem.Allocator,
    parsed: cli.Parsed,
    define: Define = undefined,
    initial: engine.Snapshot = undefined,
    rec: Recording = undefined,
    admitted: Admission = undefined,
    n: u32 = undefined,
    check_argv: ?[]const []const u8 = undefined,
    firsts: Firsts = undefined,
};

pub fn main(init: std.process.Init.Minimal) !void {
    // Position matters more than it looks. Captured immediately before the world loop,
    // this would miss a launcher that died during `--setup` or the recording run — the
    // baseline would already be the reaper's pid, which never changes. Captured here, the
    // blind window shrinks to fork-to-exec: a launcher that dies before this line is not
    // seen, and the flag's own documentation says so.
    startup_ppid = posix.getppid();

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // The whole-trace ceiling, installed before anything in this process can read a
    // trace (#377, ADR 0033). A local in `main` on purpose: every `TraceInfo` built on
    // it is freed before `main` returns, and a budget that died first would leave those
    // arenas freeing through a dangling child allocator. Nothing moves it after
    // `readTraceOrRefuse` starts handing out its allocator.
    var budget: engine.TraceBudget = .{ .child = gpa, .limit = trace_budget_limit };
    refuse.trace_budget = &budget;

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const argv = try init.args.toSlice(arena_state.allocator());

    // `--observe supervised` (#217, ADR 0089): this binary started as the filter installer in
    // front of the operation. It installs the filter, hands the listener to the engine that
    // started it, and execs the operation — nothing else in `main` may run first, since every
    // call it made would be the subject's.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], supervise.exec_arg)) supervise.filterExec(argv);

    // Removed, not pinned empty on each spawn as `seq_base` is: the shim arms the group kill on
    // `kill_group`'s presence, so an empty value would still arm it.
    for (contract.env.removed_at_start) |name| _ = posix.unsetenv(name.ptr);

    // Help in every spelling and in the positions it is answered in, `version` and
    // `--version`, a bare `sideeye`, and a first word that names no command — answered and
    // exited in `cli.answerEntry` (#273, #296, #705), before `mcp` so that `mcp --help` is
    // answered too. What returns is a command word followed by anything else, for the
    cli.answerEntry(arena_state.allocator(), argv);

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "mcp")) {
        if (argv.len != 2) cli.refuseArgumentOf(arena_state.allocator(), "mcp", argv[2], "; operational settings come from SIDEEYE_MCP_* environment variables");
        mcp.runServer(gpa);
        return;
    }

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "evidence")) {
        const ea = arena_state.allocator();
        const one = "sideeye evidence takes one argument: the saved case, or the bundle beside it";
        const looks_like_option = argv.len == 3 and argv[2].len > 1 and argv[2][0] == '-' and
            std.c.access((ea.dupeSentinel(u8, argv[2], 0) catch argv[2]).ptr, std.c.F_OK) != 0;
        if (argv.len == 2) cli.refuseOnStderr(ea, one, .{});
        if (argv.len != 3 or looks_like_option) {
            const extra = if (argv.len == 3) argv[2] else for (argv[2..]) |a| {
                if (a.len > 1 and a[0] == '-') break a;
            } else argv[3];
            cli.refuseOnStderr(ea, one ++ "; got '{s}'{s} (sideeye help evidence)", .{
                defang.textShown(ea, extra), if (looks_like_option) ", which is no file here, and evidence takes no option" else " too",
            });
        }
        std.process.exit(evidence.runCommand(gpa, argv[2]));
    }

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "completions")) cli.runCompletions(arena_state.allocator(), argv);

    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "demo")) {
        runDemo(arena_state.allocator(), argv[2..]);
    }

    // Before the loop, so that a parse error occurring *after* `--json` was read still
    // reaches the report rather than leaving whatever was there before.
    refuse.json_arena = arena_state.allocator();
    var run: Run = .{ .gpa = gpa, .arena_state = &arena_state, .arena = arena_state.allocator(), .parsed = cli.parse(argv) };
    // Not before the parse: `--world-timeout` resets SIGCHLD there, and children must get that disposition.
    posix.installInterruptHandlers(refuse.stopForSignal);
    phaseDefine(&run);
    phaseSetup(&run);
    phaseApparatus(&run);
    defer run.initial.deinit();
    phaseRecording(&run);
    defer run.rec.trace.deinit();
    defer run.rec.final.deinit();
    defer run.rec.l0_plan.deinit();
    phaseStructural(&run);
    phaseOracle(&run);
    phasePreflight(&run);
    phaseChecker(&run);
    phaseExploration(&run);
    phaseReport(&run);
}

fn phaseDefine(run: *Run) void {
    const arena_state = run.arena_state;
    const mode = run.parsed.mode;
    const case_arg = run.parsed.case_arg;
    var args = run.parsed.args;

    var replay_case: ?case.ReplayCase = null;
    var only_k: ?u32 = null;
    if (mode == .replay) {
        if (args.state != null or args.setup != null or args.operation != null or
            args.check != null or args.marker != null or args.expect_status != null or
            args.cwd != null or args.config != null or args.apparatus.len != 0 or args.scratch.len != 0)
            setupError(.define_invalid, "replay takes its define from the case file; the define-surface flags (--apparatus and --scratch included) and --config do not apply");
        const rarena = arena_state.allocator();
        const ctext = capture.readFileAllocCapped(rarena, case_arg.?, 1024 * 1024, .{ .require_regular = true }) orelse setupError(
            .environment,
            std.fmt.allocPrint(rarena, "the case file could not be read (missing, not a regular file, unreadable, or over 1 MiB): {s}", .{case_arg.?}) catch "the case file could not be read",
        );
        const c = switch (case.read(rarena, ctext)) {
            .ok => |read_case| read_case,
            .invalid => |why| setupError(.define_invalid, why),
        };
        // The COMMANDS are deliberately not resolved here. `writeCase` stores those as
        // the CLI spelled them — only `state` is overwritten with its resolved form at
        // the save site, and the flag path never calls `resolveCommand` — so resolving
        // them on the way in would point a saved case's `./op.sh` at the case directory,
        // breaking the cases this engine writes. Making them absolute is the save site's
        const case_dir = blk: {
            const raw = std.fs.path.dirname(case_arg.?) orelse ".";
            var dz_buf: [contract.max_path]u8 = undefined;
            const dz = std.mem.printSentinel(&dz_buf, "{s}", .{raw}, 0) catch setupError(.define_invalid, "the case file's directory is too long to resolve against");
            var real_buf: [contract.max_path]u8 = undefined;
            const abs = posix.realpath(dz.ptr, &real_buf) orelse setupError(.environment, "the case file's directory could not be resolved");
            break :blk rarena.dupe(u8, std.mem.span(abs)) catch setupError(.environment, "out of memory");
        };
        args.state = resolvePathAgainst(rarena, case_dir, c.define.state);
        args.setup = c.define.setup;
        args.operation = c.define.operation;
        args.check = c.define.check;
        args.marker = c.define.marker;
        // The case is replay's last source of both (flags and --config were refused above),
        // so the accounts settle here — "configured" or "none configured" — and every exit
        // from here on, `case_no_longer_applies` included, reports what the case held (#352).
        report.settleDeclared(args.check != null, args.marker != null);
        args.expect_status = c.define.expected_status;
        args.cwd = if (c.define.cwd) |cd| resolvePathAgainst(rarena, case_dir, cd) else null;
        // the same question. Normalised again on the way in: an engine-written case is
        // already normalised and passes through unchanged, a hand-written `cache/` would
        // otherwise be accepted by the grammar and match nothing.
        if (c.define.scratch) |decl| {
            const norm = rarena.alloc([]const u8, decl.len) catch setupError(.environment, "out of memory");
            for (decl, 0..) |e, j| norm[j] = switch (config.parseScratchEntry(e)) {
                .ok => |p| p,
                .bad => |m| setupError(.define_invalid, m),
            };
            args.scratch = norm;
        }
        // Not from a flag: `--apparatus` was refused above, so a case saved before it carried the
        // declaration replays with none checked.
        if (c.define.apparatus) |decl| args.apparatus = decl;
        // Mirrored into the report before any refusal below can fire: a contract
        // mismatch on a status-3 case must not report expected_status 0 (R1 finding).
        report.expected_status_val = c.define.expected_status orelse 0;
        replay_case = c;
        only_k = c.k;
        // account block (a SETUP ERROR's text is its one sentence). Set before the contract
        // gate so the one refusal this block raises names it too.
        report.case_note = case_arg.?;
        boundary.replaying = true;
        // The mode the case was counted under (#691, ADR 0100), taken after `case_note` so the
        // refusal below carries the case in its JSON `case`, like every refusal from here on;
        // its sentence names the case too, since a SETUP ERROR's text prints no `case` line. Absent — every
        if (c.observe) |m| {
            const obs = contract.ObserveMode.parse(m).?; // vetted by the version gate above
            if (args.observe_named and args.observe != obs)
                setupErrorFmt(rarena, .define_invalid, "the case {s} was recorded under --observe {s} and its crash point is a number in that mode's count; replay it without --observe, or with --observe {s} (--observe {s} was given)", .{ textShown(rarena, case_arg.?), obs.name(), obs.name(), args.observe.name() });
            args.observe = obs;
            // Re-derived here rather than left to the recording phase: a refusal between this
            // line and that one (`--state-under`, the destruction vet) would otherwise name
            // the shim as the observer of a supervised case.
            report.noteObserver(obs == .supervised);
        }
        if (c.contract_version != contract.contract_version)
            unknown(.case_no_longer_applies, "the case was recorded under a different trace contract; the crash-point numbering does not carry over", .re_record);
        // --fresh-state (#69) is honoured further down, on state_abs — the guard in
        // front of the deletion is lexical, and only the realpath'd spelling makes
        // it mean anything. Nothing destructive happens in this block.
    }

    var config_dir: ?[]const u8 = null;
    if (args.config) |cfg_path| {
        if (args.state != null or args.setup != null or args.operation != null or args.check != null or args.marker != null or args.expect_status != null or args.cwd != null or args.apparatus.len != 0 or args.scratch.len != 0 or args.recovery != null or args.recovery_check != null)
            setupError(.define_invalid, "--config and the define-surface flags (" ++ cli.define_surface_list ++ ") are mutually exclusive: the define lives in one place or the other");
        const arena = arena_state.allocator();
        // Bounded, and the only reader that is. The path is operator-named and may
        // legitimately be a pipe — `--config /dev/stdin`, a process substitution — so it
        // cannot be refused by kind the way a case path is (#400), and it cannot be
        // waited on forever either. A ceiling comes with it: the largest config in this
        const text = capture.readFileAllocCapped(arena, cfg_path, 1024 * 1024, .{ .bounded = true }) orelse setupError(
            .environment,
            std.fmt.allocPrint(arena, "--config could not be read: {s}", .{cfg_path}) catch "--config could not be read",
        );
        switch (config.parse(arena, text) catch setupError(.environment, "out of memory")) {
            .ok => |d| {
                // The toml is the last source of a checker and a marker under --config (the
                // flags were refused), and it has been read: settle both accounts here, before
                // the two refusals below that can fire after a successful parse, so a toml
                // that declared them is never reported as "not established" (#352, review).
                report.settleDeclared(d.check != null, d.marker != null);
                // The dirname is absolutized before anything resolves against it: the
                // resolved define is what a saved case stores as the counterexample's
                // identity, and a relative spelling would make the case mean a
                // different command from every other cwd.
                const dir_raw = std.fs.path.dirname(cfg_path) orelse ".";
                var dir_z: [contract.max_path]u8 = undefined;
                const dz = std.mem.printSentinel(&dir_z, "{s}", .{dir_raw}, 0) catch setupError(.define_invalid, "--config path is too long");
                var dir_real: [contract.max_path]u8 = undefined;
                const dir_abs = posix.realpath(dz.ptr, &dir_real) orelse setupError(.environment, "--config's directory could not be resolved");
                const dir = arena.dupe(u8, std.mem.span(dir_abs)) catch setupError(.environment, "out of memory");
                config_dir = dir;
                // #700 (ADR 0093): the directory a failed command's relative arguments are
                // compared under, and only for a config that is a file — read from a pipe, its
                // "directory" is `/dev` or `/dev/fd`, and "add cwd" would point there.
                {
                    var cfg_z: [contract.max_path]u8 = undefined;
                    if (std.mem.printSentinel(&cfg_z, "{s}", .{cfg_path}, 0)) |cz| {
                        // Not followed through a link: `/dev/stdin` redirected from a file
                        // resolves to a regular file, and its directory is still `/dev`.
                        if ((posix.kindOfPathNoFollow(cz.ptr) catch .other) == .file) refuse.toml_dir = dir;
                    } else |_| {}
                }
                // #706 (ADR 0095): read as written, before argv[0] is resolved against `dir`; the
                // parser's own sentences (a value cut at an inner quote) first.
                const spelled = config.shellWarnings(arena, .toml, d.setup, d.operation, d.check, d.recovery, d.recovery_check);
                report.define_warnings = std.mem.concat(arena, []const u8, &.{ d.cut_at_comment, spelled }) catch spelled;
                args.state = resolvePathAgainst(arena, dir, d.state);
                args.setup = if (d.setup) |s| resolveCommand(arena, dir, s) else null;
                args.operation = resolveCommand(arena, dir, d.operation);
                args.check = if (d.check) |c| resolveCommand(arena, dir, c) else null;
                args.marker = d.marker;
                args.cwd = if (d.cwd) |c| resolvePathAgainst(arena, dir, c) else null;
                args.apparatus = d.apparatus orelse &.{};
                args.scratch = d.scratch orelse &.{};
                args.recovery = if (d.recovery) |r| resolveCommandAgainst(arena, dir, r) else null;
                args.recovery_check = if (d.recovery_check) |r| resolveCommandAgainst(arena, dir, r) else null;
                if (d.controls.len > 0) {
                    if (d.check == null)
                        setupError(.define_invalid, "[controls] needs [define] check: a control is read by the legs the checker reports on the state it broke");
                    const resolved = arena.alloc(config.Control, d.controls.len) catch setupError(.environment, "out of memory");
                    for (d.controls, resolved) |c, *r| {
                        r.* = .{ .leg = c.leg, .command = resolveCommandAgainst(arena, dir, c.command) };
                        refuseSpacedDir(arena, dir, "controls", "control", c.command, r.command);
                    }
                    args.controls = resolved;
                }
                // Not turned into argv as the define's commands are: a recovery is carried and printed on
                // the replay line as one string, which splits on spaces wherever it is read again.
                for ([_]?[]const u8{ d.recovery, d.recovery_check }, [_]?[]const u8{ args.recovery, args.recovery_check }) |written, resolved| {
                    if (written) |w| refuseSpacedDir(arena, dir, "recovery", "recovery", w, resolved.?);
                }
                if (d.expected_status) |es| {
                    args.expect_status = config.parseExpectStatus(es) orelse setupError(.define_invalid, "expected_status must be an integer in 0..255 (one double-quoted string, as every value here)");
                    // Same mirror as the flag: refusals between here and the
                    // canonical binding must report the declaration that was read.
                    report.expected_status_val = args.expect_status.?;
                }
            },
            .fault => |f| {
                const msg = if (f.line == 0)
                    std.fmt.allocPrint(arena, "{s}: {s}", .{ cfg_path, f.what }) catch f.what
                else
                    std.fmt.allocPrint(arena, "{s} line {d}: {s}", .{ cfg_path, f.line, f.what }) catch f.what;
                setupError(.define_invalid, msg);
            },
        }
    }
    if (args.config == null and replay_case == null)
        report.define_warnings = config.shellWarnings(arena_state.allocator(), .flags, args.setup, args.operation, args.check, args.recovery, args.recovery_check);

    const state = args.state orelse setupError(.define_invalid, "--state is required");
    const operation = args.operation orelse setupError(.define_invalid, "--operation is required");
    const expect_status: u8 = args.expect_status orelse 0;
    report.expected_status_val = expect_status;
    if (args.marker) |m| {
        if (m.len == 0) setupError(.define_invalid, "the marker is empty");
        if (m.len >= 4096) setupError(.define_invalid, "the marker is unreasonably long (>= 4 KiB)");
        report.l1_configured = true;
        report.l1_note = report.l1NoteFor(.named);
    }

    // The declared cwd is resolved and vetted here, ahead of the state directory's mkdir
    // below: a define naming a directory that is not there must refuse before anything on
    // disk has moved, and exit 3 is true of it — nothing of the define has run.
    if (args.cwd) |declared| {
        var cwd_z_buf: [contract.max_path]u8 = undefined;
        const cwd_z = std.mem.printSentinel(&cwd_z_buf, "{s}", .{declared}, 0) catch setupError(.define_invalid, "the declared cwd is too long");
        var cwd_real: [contract.max_path]u8 = undefined;
        // Both refusals print a string that arrived from a config or a case file, and
        // both are declared trust boundaries — so both go through `textShown`, the way
        // the `--state-under` refusal below already does for `define.state`. Same class,
        // same batch that found it (#266): a refusal firing *on* a hostile declaration is
        // exactly where a forged control sequence would reach the console.
        const cwd_abs = posix.realpath(cwd_z.ptr, &cwd_real) orelse setupError(
            .environment,
            std.fmt.allocPrint(arena_state.allocator(), "the declared cwd could not be resolved: {s}", .{textShown(arena_state.allocator(), declared)}) catch "the declared cwd could not be resolved",
        );
        const cwd_span = std.mem.span(cwd_abs);
        // A regular file resolves fine and then fails at `chdir` in the child, which
        // reads as the operation exiting 125 — a diagnosis about the target for what is
        // a fault in the declaration. Refused by name here instead.
        if (!posix.isDirPath(cwd_abs)) setupError(
            .environment,
            std.fmt.allocPrint(arena_state.allocator(), "the declared cwd is not a directory: {s}", .{textShown(arena_state.allocator(), cwd_span)}) catch "the declared cwd is not a directory",
        );
        args.cwd = arena_state.allocator().dupe(u8, cwd_span) catch setupError(.environment, "out of memory");
    }

    // Not only under a declared cwd: the target itself can chdir before it execs, and the image
    // it execs opens `SIDEEYE_TRACE_PATH`, and the loader the shim, against the directory it moved
    // to. Lexical, not realpath: `--work` may not exist yet.
    const cwd_declared = args.cwd != null;
    const shim_pins = if (args.shim) |sh| workdir.pinsName(sh, cwd_declared) else false;
    const oracle_pins = if (args.oracle) |o| workdir.pinsName(o, cwd_declared) else false;
    if (workdir.isRelativePath(args.work) or shim_pins or oracle_pins) {
        var pin_cwd_buf: [contract.max_path]u8 = undefined;
        // No fallback to `/`: a relative `--work` would then be made at the root.
        const pin_base = if (posix.getcwd(&pin_cwd_buf, pin_cwd_buf.len)) |p| std.mem.span(p) else setupError(.environment, "the directory Sideeye was started in could not be read, and a relative --work, --shim or --oracle is read against it; pass absolute paths");
        const pin_arena = arena_state.allocator();
        args.work = resolvePathAgainst(pin_arena, pin_base, args.work);
        if (shim_pins) {
            const pinned = resolvePathAgainst(pin_arena, pin_base, args.shim.?);
            // Not pinned into a name the preload variable splits — LD_PRELOAD on spaces and colons,
            // DYLD_INSERT_LIBRARIES on colons — unless a declared cwd already required it.
            if (cwd_declared or std.mem.indexOfAny(u8, pinned, " \t:") == null) args.shim = pinned;
        }
        if (oracle_pins) args.oracle = resolvePathAgainst(pin_arena, pin_base, args.oracle.?);
    }

    // #647: where the define's commands run, decided once, here — directly after the
    // declared `cwd` has been resolved and pinned, and before anything else in phase 0 can
    // refuse. A SETUP ERROR raised from this line on carries the directory in its JSON; one
    // raised above it (the config, the `cwd` vet) does not, because there is no directory
    const effective_cwd: ?[]const u8 = args.cwd orelse blk: {
        var own_cwd_buf: [contract.max_path]u8 = undefined;
        const own = posix.getcwd(&own_cwd_buf, own_cwd_buf.len) orelse break :blk null;
        break :blk arena_state.allocator().dupe(u8, std.mem.span(own)) catch null;
    };
    report.command_cwd = effective_cwd;
    report.command_cwd_declared = args.cwd != null;

    // Bound after the pin above, not before it: `findShim`'s own answer is already
    // absolute, but an explicit `--shim ./lib.dylib` is the caller's spelling, and the
    // loader resolves it in the child — after the chdir. Read too early, this const would
    // hold the unpinned string and the run would die in dyld naming the declared
    // directory, which is how the review found it.
    const shim = args.shim orelse findShim(arena_state.allocator());

    var state_z_buf: [contract.max_path]u8 = undefined;
    const state_z = std.mem.printSentinel(&state_z_buf, "{s}", .{state}, 0) catch setupError(.define_invalid, "--state is too long");
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
    const state_created = posix.mkdir(state_z.ptr, 0o755) == 0;
    const state_abs = blk: {
        if (posix.realpath(state_z.ptr, &run.define.real_buf)) |p| break :blk std.mem.span(p);
        // The errno is read first: the rmdir below issues its own syscall and would
        // overwrite it (#486).
        const why = std.c._errno().*;
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupErrorFmt(arena_state.allocator(), .environment, "--state {s}: {s}. Until it resolves, {s}", .{ textShown(arena_state.allocator(), state), refuse.resolveFailure(arena_state.allocator(), state, why), if (args.observe == .supervised) "the engine could not match the paths it reads from the target against it" else "the shim and the engine would filter on different spellings of it" });
    };
    if (posix.kindOfPathNoFollow(@ptrCast(state_abs.ptr))) |kind| {
        if (kind != .dir) setupErrorFmt(arena_state.allocator(), .define_invalid, "--state {s} is not a directory: the state is the one directory the target's state lives in, and a {s} there would be judged as an empty tree", .{ textShown(arena_state.allocator(), state), switch (kind) {
            .file => "regular file",
            .symlink => "symlink",
            else => "non-directory entry",
        } });
    } else |_| {}

    // A recovery is a pair (#606, ADR 0072), held here and only here: after the case or the
    // config has been read — so a flag and a toml key cannot each supply half — and after the
    // mode's own first refusals, so a probe that adds one of the two flags to a failing base
    // command still meets that command's failure first (the CLI self-description check reads a
    // refusal raised earlier as a flag the mode does not accept).
    if ((args.recovery == null) != (args.recovery_check == null)) {
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError(.define_invalid, "a recovery is declared as a pair: --recovery with --recovery-check, or `command` with `check` under [recovery]; one without the other would run a recovery nothing judges, or judge one nothing ran");
    }
    // A value of spaces passes the empty-string check at the flag and the key and splits into
    // no words, and a child handed no argv dies before exec — which the gate would read as a
    // recovery that ran and ended, and every exhibit `fail` (review). Refused like `--check`.
    if (args.recovery) |rc| {
        const words_cmd = if (commandArgv(arena_state.allocator(), .{ .str = rc })) |w| w.len else |_| 0;
        const words_chk = if (commandArgv(arena_state.allocator(), .{ .str = args.recovery_check.? })) |w| w.len else |_| 0;
        if (words_cmd == 0 or words_chk == 0) {
            if (state_created) _ = posix.rmdir(state_z.ptr);
            setupError(.define_invalid, if (words_cmd == 0) "--recovery is empty" else "--recovery-check is empty");
        }
    }
    // exploration replaces it once a recovery has run. Preflight saves no world at all, and a
    // recovery reaches it only from a toml (#704): said as what preflight does with it, so a
    // refusal does not read as though worlds had been explored. Never started either way —
    if (args.recovery != null) report.recovery_note = if (mode == .preflight)
        "declared; preflight runs no recovery"
    else
        "configured; not run (no world was saved as a FAIL)";
    if (args.leave_crash_state) {
        report.crash_state_left = false;
        report.crash_state_note = "not left: the run ended before a verdict";
    }

    // Still before setup runs, so the refusal is a configuration error; the state directory
    // this run made above is undone, as the recovery refusals above undo it. See the flag's
    // parse site for why this is not raised there (and why not before the state resolves:
    // the CLI self-description check pins the base command's first refusal, #406).
    if (args.oracle_fs_usage and builtin.os.tag != .macos) {
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError(.platform_unsupported, "--oracle-fs-usage is macOS only; on Linux the completeness oracle is --oracle <strace>, which needs no privilege");
    }
    if (args.oracle != null and builtin.os.tag == .macos) {
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError(.platform_unsupported, if (mode == .preflight)
            "--oracle runs strace, which is Linux only; preflight on macOS answers without a second witness, so drop --oracle. To ask with strace as the witness, run preflight on Linux; " ++ contract.ci_linux_run
        else
            "--oracle runs strace, which is Linux only; drop it. On macOS the second witness is --oracle-fs-usage (run sudo -v first, in the same terminal), or accept the weaker claim with --allow-unverified; under sideeye mcp, leave SIDEEYE_MCP_ORACLE unset. To run with strace as the witness, run on Linux; " ++ contract.ci_linux_run);
    }

    // This vet sits *before* --fresh-state's deletion below, and cleans up the one
    // side effect its own resolution needs (mkdir before realpath): a refusal must
    // leave the state directory exactly as it found it, and the first version of the
    // check emptied the state dir — or planted <state>/work — before refusing
    // (review finding). `isInsideDir` holds --work equal to the state directory, and
    var work_buf: [contract.max_path]u8 = undefined;
    const work_z = std.mem.printSentinel(&work_buf, "{s}", .{args.work}, 0) catch {
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError(.define_invalid, "--work is too long");
    };
    const work_created = mcp.mkdirWorkDir(args.work, 0o755) == 0;
    // #692 (ADR 0099): the cases saved here are commands a replay runs, and the default is a
    // fixed name in /tmp that `mkdir` adopts on EEXIST — so whoever made that name first,
    // or planted a link at it, chose where they go. Asked of the name as given, before
    // `realpath` below follows it and before anything is written under it — and only of a
    // directory this invocation did not just create, which is its own whatever owner a
    // filesystem reports for it (an NFS export squashing root, say).
    //
    // Two answers wait for that `realpath`. `missing` is the resolution failure that has
    // always reported an uncreatable --work. `unclassifiable` is also what `lstat` answers
    // when an EARLIER component is the trouble — `--work /etc/passwd/w` (ENOTDIR), a parent
    // the runner cannot search (EACCES) — and there the resolution failure names the errno,
    // where this check's sentence would blame a directory that is not there and offer a new
    // name as the way past (#692 review). Only a name that resolves and still cannot be read
    // is refused as unclassifiable, after the resolution below.
    const work_refusal: ?mcp.WorkDirRefused = if (work_created) null else switch (mcp.workDirVerdict(args.work)) {
        .ok, .missing => null,
        .refused => |r| r,
    };
    const work_refusal_msg: []const u8 = if (work_refusal) |r| blk: {
        const a = arena_state.allocator();
        break :blk mcp.workDirRefusalMessage(
            a,
            std.fmt.allocPrint(a, "--work {s}", .{textShown(a, args.work)}) catch "--work",
            r,
            "Pass --work a name that does not exist yet, and Sideeye creates it as yours, or a directory of your own",
        );
    } else "";
    if (work_refusal) |r| {
        if (r.why != .unclassifiable) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(mcp.workDirRefusalReason(r.why), work_refusal_msg);
        }
    }
    {
        const work_abs = blk: {
            if (posix.realpath(work_z.ptr, &run.define.work_real_buf)) |p| break :blk std.mem.span(p);
            // Before undoSetupMkdirs, which issues syscalls of its own (#486).
            const why = std.c._errno().*;
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupErrorFmt(arena_state.allocator(), .environment, "--work {s}: {s}", .{ textShown(arena_state.allocator(), args.work), refuse.resolveFailure(arena_state.allocator(), args.work, why) });
        };
        if (work_refusal != null) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.environment, work_refusal_msg);
        }
        if (contract.isInsideDir(work_abs, state_abs)) {
            // Remove only what this invocation just created: refusing while leaving
            // a fresh <state>/work behind would itself be the contamination the
            // check exists to prevent. (The state root too — `--state /opt/x --work
            // /opt/x/work` creates both, one directory up.)
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "--work must not be the state directory or inside it: the engine's own captures and traces there would be observed as the target's state operations");
        }
        run.define.work_abs = work_abs;
    }

    // The same shape, for the case file itself (#325 review). A replay empties the state
    // directory (`--fresh-state`) and rebuilds it once per world, so a case whose
    // `define.state` resolves to a directory *containing the case* deletes the case —
    // and, in the conventional `<work>/cases/` layout, every sibling case with it,
    // including the second exhibit a checker-red run saves.
    //
    // Reachable before this batch too (a relative `.` resolved against the invoker's
    // cwd), but resolving against the case file is what makes it land reliably: the case
    // is then always inside the directory being emptied. `--state-under` does not see it
    // — the state IS inside the declared range, which is the only thing that test asks —
    // so this is its own vet, beside `--work`'s, on the same resolved bytes the
    // destruction will use. Measured before the vet existed: `"state": "."` with the case
    if (mode == .replay) {
        var case_z_buf: [contract.max_path]u8 = undefined;
        const czb = std.mem.printSentinel(&case_z_buf, "{s}", .{case_arg.?}, 0) catch setupError(.define_invalid, "the case file's path is too long");
        var case_real: [contract.max_path]u8 = undefined;
        // Unresolvable here means it moved since the read a moment ago: refuse rather
        // than skip the vet.
        const case_abs = posix.realpath(czb.ptr, &case_real) orelse {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.environment, "the case file could not be resolved for the destruction vet");
        };
        if (contract.isInsideDir(std.mem.span(case_abs), state_abs)) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "the case file lies inside the state directory this replay empties, so replaying it would delete the case (and any sibling case beside it); point define.state at a directory that does not contain the case");
        }
    }

    // Refused when unresolvable rather than skipped: the report is written after the rewrite,
    // into a directory the crash state may hold although the define's state did not.
    if (args.leave_crash_state) if (args.json) |jp| {
        var jdir_z_buf: [contract.max_path]u8 = undefined;
        const jdir_z = std.mem.printSentinel(&jdir_z_buf, "{s}", .{std.fs.path.dirname(jp) orelse "."}, 0) catch {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "--json's directory is too long");
        };
        var jdir_real: [contract.max_path]u8 = undefined;
        const jdir_abs = posix.realpath(jdir_z.ptr, &jdir_real) orelse {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "with --leave-crash-state, --json's directory must already exist: it is checked against the state directory the crash state is written to");
        };
        if (contract.isInsideDir(std.mem.span(jdir_abs), state_abs)) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "--json lies inside the state directory --leave-crash-state rewrites to the crash state; the report would be an entry the crash never left");
        }
    };

    // Strict inside, not equal: a case naming the range itself would make the
    // operator's whole workspace the sacrificial directory. Both sides are compared
    // realpath'd — state_abs already is, and the flag resolves here — or the /tmp
    // and /private/tmp spellings of the same directory would split on macOS.
    if (args.state_under) |su| {
        var su_z_buf: [contract.max_path]u8 = undefined;
        const su_z = std.mem.printSentinel(&su_z_buf, "{s}", .{su}, 0) catch {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "--state-under is too long");
        };
        var su_real_buf: [contract.max_path]u8 = undefined;
        const su_abs = blk: {
            if (posix.realpath(su_z.ptr, &su_real_buf)) |p| break :blk std.mem.span(p);
            // Fail-closed: an unresolvable range must refuse the run, not skip the
            // confinement it was asked to apply. "Resolved" is all this checks — a
            // regular file resolves and passes here; everything under it then fails
            // strict-inside, so the outcome is refusal either way.
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.environment, "--state-under could not be resolved; refusing rather than running unconfined");
        };
        // "/" satisfies isInsideDir for every absolute path — a range that confines
        // nothing is a misconfiguration, not a wide range.
        if (su_abs.len <= 1) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.define_invalid, "--state-under / would confine nothing; name the directory the state may live under");
        }
        if (!contract.isStrictlyInsideDir(state_abs, su_abs)) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            const arena = arena_state.allocator();
            // `state_abs` comes from the case file's `define.state`, and a case is a
            // declared trust boundary — so this refusal, the one that fires *on* a hostile
            // case, was splicing a hostile string into the console verbatim. Same class as
            // `snapshotOrRefuse` above, same batch that introduced it (#266), found by the
            // review that followed the first fix rather than by the scan that accompanied
            // it. `su_abs` is operator-supplied and takes the same treatment for free.
            // #765: and explore. For a config the first way out is to move its state inside the
            // range — the refusal exists for an agent that wrote the state wrong, and telling it
            // to run the same config at the command line, where nothing confines it, would route
            // the mistake around the check. A replayed case's state is where the command that
            const way = if (mode == .replay)
                "replay it from the command line, where its state was made, or widen the range"
            else
                "move the state inside the range, or widen the range";
            setupError(.define_invalid, std.fmt.allocPrint(arena, "the state directory resolves outside the allowed range, or is the range itself: state {s}, --state-under {s}. To go on, {s} to a directory holding this state (SIDEEYE_MCP_STATE_ROOT on the MCP server, --state-under on the command line)", .{ textShown(arena, state_abs), textShown(arena, su_abs), way }) catch "the state directory resolves outside the allowed range (--state-under)");
        }
        // Not the spelling given: a relative one on a printed line refuses when pasted elsewhere.
        args.state_under = arena_state.allocator().dupe(u8, su_abs) catch setupError(.environment, "out of memory");
    }

    // Not left to `engine.restore`'s own `assertSafeRoot`: that runs once `--setup` has run
    // against the state, and refusing a system path after running the target's setup
    // against it is not a refusal.
    //
    // It sits *after* the --work containment vet on purpose. Both are ahead of every
    // destructive step, so the order does not change what is protected — but `--state /`
    // is refused by both, and the containment vet's acceptance leg uses exactly that
    // input to hold `isInsideDir`'s empty-prefix branch (the hand-rolled test it replaced
    // answered "outside" for `/`). Vetting the root first would take that input away and
    // leave the containment logic with no CLI-level case.
    engine.assertSafeRoot(state_abs) catch {
        undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
        setupError(.define_invalid, "--state names a location nothing sacrificial belongs in: exploration empties and rebuilds this directory once per world, hundreds of times. Point it at a scratch directory the run owns");
    };

    // Not earlier. The CLI self-description check (spike/acceptance.sh) pins the base
    // command's first refusal — its `--state` that does not resolve, above — and reads a flag
    // that changes the first line as one the mode does not accept; a refusal of a dummy
    // `--setup` raised ahead of that one would make `--setup` read as refused everywhere
    // (the shape `src/cli.zig` records for `--oracle-fs-usage`, #406). After `effective_cwd`
    // too, so the report names the directory the setup would have run in (#647).
    const setup_arena = arena_state.allocator();
    const setup_cwd = effective_cwd orelse args.cwd;
    const setup_argv: []const []const u8 = if (args.setup) |cmd| commandArgv(setup_arena, cmd) catch &[_][]const u8{} else &[_][]const u8{};
    if (refuse.unstartable(setup_arena, "setup", setup_argv, setup_cwd)) |m| {
        undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
        setupError(.environment, m);
    }
    // Not after the setup: a setup run without a declared variable writes wherever the tool
    // falls back to, which on a developer's machine is the real data.
    if (checkApparatus(setup_arena, args.apparatus, args.cwd, .before_setup)) |r| {
        // Not a directory the JSON report goes under: the report would have nowhere to land.
        // Compared through realpath, not by spelling: a /tmp on one side and /private/tmp on
        // the other is the same directory.
        var keep_work = false;
        var keep_state = false;
        if (refuse.json_path) |jp| {
            var jdir_buf: [contract.max_path]u8 = undefined;
            var jdir_real: [contract.max_path]u8 = undefined;
            var work_real: [contract.max_path]u8 = undefined;
            if (std.mem.printSentinel(&jdir_buf, "{s}", .{std.fs.path.dirname(jp) orelse "."}, 0)) |jdir_z| {
                if (posix.realpath(jdir_z.ptr, &jdir_real)) |jdir_abs| {
                    const jdir = std.mem.span(jdir_abs);
                    if (posix.realpath(work_z.ptr, &work_real)) |w| keep_work = contract.isInsideDir(jdir, std.mem.span(w));
                    keep_state = contract.isInsideDir(jdir, state_abs);
                }
            } else |_| {}
        }
        undoSetupMkdirs(work_created and !keep_work, work_z.ptr, state_created and !keep_state, state_z.ptr);
        setupError(r.reason, r.text);
    }

    // deleteTree the restore path uses). It runs on state_abs, never the case's raw
    // spelling: the guard is lexical, and "/tmp/../etc" spells safe while resolving
    // unsafe — the realpath above is the guard's other half. Sitting here also keeps
    // every earlier setup validation — the --work containment vet included — ahead of
    // the one destructive step, and the mkdir-then-resolve above already covers a
    // state dir that does not exist yet.
    // Not after `--fresh-state`: a second replay of one case would empty the state the first
    // is exploring before meeting the lock.
    if (workdir.lock(arena_state.allocator(), args.work)) |r| {
        undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
        setupError(r.reason, r.text);
    }

    if (args.fresh_state) {
        engine.freshDir(state_abs) catch |e| refuse.restoreFailure(e, "--fresh-state could not empty the case's state directory", state_abs);
        // Asked again after the emptying (#701 review): a setup that lived inside the state
        // directory passed the question above and is gone now, and would otherwise reach
        // `--setup exited 127` naming no file. Only here, where the directory is
        // sacrificial by contract and the replay was going to empty it anyway.
        if (refuse.unstartable(setup_arena, "setup", setup_argv, setup_cwd)) |m| {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError(.environment, m);
        }
    }

    // On macOS `--state /tmp/x` resolves to `/private/tmp/x`, and a target told its state
    // is at `/tmp/x` hands `/tmp/x/key.json` to `unlink` while `F_GETPATH` answers
    // `/private/tmp/x/key.json` for the same file. Exploration never saw this because the
    // engine hands the target the resolved path; the `reproduce` line did, because there
    // the target finds its state its own way — and the result was a printed command that
    // ran to completion and changed nothing.
    const state_alt = blk: {
        var cwd_buf: [contract.max_path]u8 = undefined;
        const cwd = if (posix.getcwd(&cwd_buf, cwd_buf.len)) |p| std.mem.span(p) else "/";
        const n = contract.normalizePath(&run.define.alt_buf, cwd, state) catch break :blk state_abs;
        break :blk n;
    };
    const alt_differs = !std.mem.eql(u8, state_alt, state_abs);

    run.parsed.args = args;
    run.define.replay_case = replay_case;
    run.define.only_k = only_k;
    run.define.state = state;
    run.define.operation = operation;
    run.define.expect_status = expect_status;
    run.define.shim = shim;
    run.define.state_abs = state_abs;
    run.define.state_alt = state_alt;
    run.define.alt_differs = alt_differs;
    run.define.effective_cwd = effective_cwd;
    run.define.config_dir = config_dir;
}

fn phaseSetup(run: *Run) void {
    const gpa = run.gpa;
    const arena_state = run.arena_state;
    const args = run.parsed.args;
    const state_abs = run.define.state_abs;

    if (args.setup) |cmd| {
        const a = arena_state.allocator();
        const setup_argv = commandArgv(a, cmd) catch setupError(.define_invalid, "--setup is empty");
        if (setup_argv.len == 0) setupError(.define_invalid, "--setup is empty");
        // Do not drop the pid from the name: on a filesystem without locks `workdir.lock` lets a
        // second run in, and this capture's contents reach `message`.
        var setup_out_buf: [contract.max_path]u8 = undefined;
        const setup_out = std.fmt.bufPrint(
            &setup_out_buf,
            "{s}/setup-output-{d}.txt",
            .{ args.work, posix.getpid() },
        ) catch setupError(.define_invalid, "path too long");
        // `exclusive` needs it, and `Capture.exclusive`'s doc asks for both halves by
        // name: without the unlink a second run refuses on its own leftover, and without
        // `O_EXCL` a FIFO planted at the name blocks the parent's `O_WRONLY` before any
        // budget exists to time it out.
        removeFile(setup_out);
        const term = posix.runChildCapture(gpa, setup_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
        }, .{
            .path = setup_out,
            // #483 names stderr, which is where a setup writes its diagnosis. Capturing
            // stdout alone would leave the file empty for the ordinary failure and the
            // refusal would say "wrote nothing" about a command that wrote a paragraph.
            // Not folded into `recordingCapture`: that one deliberately leaves stderr
            // alone, and sharing the constructor would widen the recording run's capture
            // as a side effect of this change.
            .stderr_too = true,
            .exclusive = true,
        }, args.cwd) catch |e| spawnFailure(e, .before_exploration, "could not run --setup");
        report.setup_status = term;
        switch (term) {
            // refusal's own name (#483). The number alone is what #483 asks for, and it
            // is all this can honestly carry: a first draft annotated 127 as "command
            // not found", and `exec /no/such/binary` under /bin/sh measured 126 here —
            // the mapping from a failed exec to a status is the shell's, not ours.
            .exited => |code| if (code != 0) setupErrorFmt(a, .setup_failed, "--setup exited {d}{s}{s}{s}", .{ code, report.setupOutputDetail(a, setup_out), report.exit126Note(code), refuse.withObservation(a, "", refuse.cwdObservation(a, setup_argv), null) }),
            .signaled => |sig| setupErrorFmt(a, .setup_failed, "--setup was killed by signal {d}{s}", .{ sig, report.setupOutputDetail(a, setup_out) }),
            .unknown => |st| setupErrorFmt(a, .setup_failed, "--setup ended in a way waitpid reported as status {d}{s}", .{ st, report.setupOutputDetail(a, setup_out) }),
        }
        // The setup succeeded and nothing in the report names this file — but it is now
        // the only place its output exists at all, because capturing it took it off the
        // terminal where it used to appear. A setup that prints `warning: using a stale
        // fixture` on a run that succeeds would otherwise be unobservable to anyone, which
        // is a loss this change would have introduced while fixing the same shape (#483).
        // A short-lived arena: `arena_state` lives to the end of the process, and a
        // successful setup that talked (a `make`, a `git clone`) would otherwise keep its
        // whole output resident through every world that follows.
        var probe = std.heap.ArenaAllocator.init(gpa);
        defer probe.deinit();
        if (capture.readSetupCapture(probe.allocator(), setup_out) == .empty) removeFile(setup_out);
    }
}

fn phaseApparatus(run: *Run) void {
    const gpa = run.gpa;
    const arena_state = run.arena_state;
    const args = run.parsed.args;
    const state_abs = run.define.state_abs;

    // After setup, not before it: a setup that builds the operation or writes the checker is
    // a define this must not refuse. Before the first snapshot and before either command
    // runs, so a name that is not there is a SETUP ERROR naming the file — not a recording
    // that "exited 127", and not a checker that "rejected the state" without ever starting.
    {
        const a = arena_state.allocator();
        const cwd = run.define.effective_cwd orelse args.cwd;
        const none = &[_][]const u8{};
        if (refuse.unstartable(a, "operation", commandArgv(a, run.define.operation) catch none, cwd)) |m| setupError(.environment, m);
        if (args.check) |c| if (refuse.unstartable(a, "check", commandArgv(a, c) catch none, cwd)) |m| setupError(.environment, m);
    }

    if (checkApparatus(arena_state.allocator(), args.apparatus, args.cwd, .after_setup)) |r| setupError(r.reason, r.text);
    // The scratch declaration is published here too (ADR 0043), at the same point as the
    // apparatus: the define is final, and every report from here on — a refusal raised
    // by the recording run included — carries it under the same presence rule.
    report.scratch_declared = args.scratch;

    const initial = refuse.snapshotOrRefuse(gpa, state_abs, "could not snapshot the initial state");
    // #5, checked before anything runs: an unreproducible entry the setup left (or
    // that predates the run) fails fast — no recording, no worlds. Nothing competes
    // with this refusal here.
    refuse.refuseUnsupportedEntry(arena_state.allocator(), initial, "present before the recording run");

    run.initial = initial;
}

fn phaseRecording(run: *Run) void {
    const gpa = run.gpa;
    const arena_state = run.arena_state;
    const args = run.parsed.args;
    const operation = run.define.operation;
    const expect_status = run.define.expect_status;
    const shim = run.define.shim;
    const state_abs = run.define.state_abs;
    const state_alt = run.define.state_alt;
    const initial = run.initial;

    // This and `rec_stdout` resolved, not `--work` as spelled: fs_usage prints a path reached
    // through macOS's `/tmp` link as `/private/tmp/…`, which no match against `/tmp/…` meets.
    const rec_trace = std.fmt.bufPrint(&run.rec.rec_trace_buf, "{s}/trace-record.bin", .{run.define.work_abs}) catch setupError(.define_invalid, "path too long");
    removeFile(rec_trace);

    const op_argv = commandArgv(arena_state.allocator(), operation) catch setupError(.define_invalid, "--operation is empty");
    if (op_argv.len == 0) setupError(.define_invalid, "--operation is empty");

    const oracle_out = std.fmt.bufPrint(&run.rec.oracle_out_buf, "{s}/oracle.txt", .{args.work}) catch setupError(.define_invalid, "path too long");
    removeFile(oracle_out);
    // Not left for the next run in this work directory: the sidecar opens it exclusively.
    removeFile(fsusage.errPath(arena_state.allocator(), oracle_out) catch setupError(.environment, "out of memory"));

    // directory. Every run gets the same shape whether or not a marker is configured:
    // an isatty branch in the target must not differ between the recording run and
    // the worlds, or the recorded operation sequence describes a different execution.
    const rec_stdout = std.fmt.bufPrint(&run.rec.rec_stdout_buf, "{s}/stdout-record.txt", .{run.define.work_abs}) catch setupError(.define_invalid, "path too long");
    removeFile(rec_stdout);

    const arena = arena_state.allocator();

    // Checked before the run, so that "the operation failed" and "the oracle could not be
    // started" stay distinguishable. Without this, a missing strace makes the child exit
    // 127 and the report says `recording_run_failed / the operation exited non-zero` —
    // blaming a target that never ran. It also made the acceptance check for that verdict
    // pass identically on a machine with no strace, so the check discriminated nothing.
    if (args.oracle) |oracle_path| {
        var ob: [contract.max_path]u8 = undefined;
        const oz = std.mem.printSentinel(&ob, "{s}", .{oracle_path}, 0) catch setupError(.define_invalid, "--oracle path is too long");
        if (posix.access(oz.ptr, posix.X_OK) != 0) {
            const bare = if (std.mem.indexOfScalar(u8, oracle_path, '/') == null) " — it is checked as a path from the directory Sideeye was started in, not looked up on PATH, so pass strace's full path" else "";
            const found = if (refuse.findStraceForHint(arena)) |s| std.fmt.allocPrint(arena, "; strace is on this machine: {s}", .{s}) catch "" else "";
            setupError(.environment, std.fmt.allocPrint(arena, "--oracle (SIDEEYE_MCP_ORACLE under sideeye mcp) names {s}, which is not an executable file{s}{s}; the completeness check cannot run", .{ textShown(arena, oracle_path), bare, found }) catch "--oracle is not an executable file; the completeness check cannot run");
        }
    }

    // Checked here for the reason the line above is: before the operation runs, so that
    // "this kernel cannot do it" and "the target misbehaved" stay distinguishable, and so
    // that the OPERATION has not run when the refusal arrives. Not "the state directory is
    // untouched" — `--setup` runs above this line and is allowed to write there, which is
    // what it is for (review, P2). What this placement buys is that the target's own
    // operation, the thing whose crash points the run is about, has not started.
    boundary.observe_mode = args.observe;
    report.noteObserver(args.observe == .supervised);
    oracle.fold_restarted = args.observe == .supervised;
    const mode_from = if (!args.observe_named and run.define.replay_case != null and run.define.replay_case.?.observe != null)
        "the case being replayed records the mode it was counted under: "
    else
        "";
    if (args.observe == .supervised) {
        if (builtin.os.tag == .macos)
            setupErrorFmt(arena_state.allocator(), .platform_unsupported, "{s}--observe supervised is Linux only, on aarch64 and x86_64: it counts through a seccomp user-notification filter, which macOS has no equivalent of. On Linux 5.19 or later, with a cgroup v2 the engine can create cgroups in, the same command takes it; " ++ contract.macos_table, .{mode_from});
        if (!supervise.available)
            setupErrorFmt(arena_state.allocator(), .platform_unsupported, "{s}--observe supervised is Linux only, on aarch64 and x86_64: it counts through a seccomp user-notification filter, which this platform has no equivalent of", .{mode_from});
        if (!supervise.kernelSupports())
            setupErrorFmt(arena_state.allocator(), .platform_unsupported, "{s}--observe supervised needs a kernel that accepts a seccomp user-notification listener with SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV (Linux 5.19 or later), and this one does not", .{mode_from});
        // Required, not preferred (#217, review): the crash point's kill reaches a process that
        // left the process group only through a cgroup, and without the shim there is nothing
        // inside the process to notice that it left.
        if (containment.spawn(false) == null)
            setupErrorFmt(arena_state.allocator(), .environment, "{s}--observe supervised needs a cgroup v2 the engine can create cgroups in (delegated to its user, or root): the crash point's kill reaches every process of the run through it, however one left the process group", .{mode_from});
    }
    if (args.observe == .syscalls) {
        if (builtin.os.tag != .linux)
            setupErrorFmt(arena_state.allocator(), .platform_unsupported, "{s}--observe syscalls is Linux only: it installs a seccomp filter, which this platform has no equivalent of. macOS observes at the libc entry points (--observe wrappers, the default). To count at the kernel boundary, run on Linux; " ++ contract.ci_linux_run ++ ", with the flag added, and " ++ contract.macos_table, .{mode_from});
        if (!posix.seccompTrapAvailable())
            setupErrorFmt(arena_state.allocator(), .platform_unsupported, "{s}--observe syscalls needs a kernel that accepts SECCOMP_RET_TRAP and this one does not (CONFIG_SECCOMP_FILTER); the default --observe wrappers works everywhere", .{mode_from});
    }

    // The macOS observer runs beside the recording rather than wrapping it, so it is
    // started here and stopped after — and both sentinels live inside the state root,
    // where `fsusage.read` can scope them, and are removed before the snapshot that
    // judges anything sees them.
    var fsu_pid: ?c_int = null;
    // Not a fixed name, and not without O_EXCL: it would truncate a state file that carried
    // it, and a failed handshake exits with no restore after it. Not the engine's pid: two
    // explores over one state would collide, and a child derives it with `getppid`. Not
    // built outside the flag's branch: the suffix would push a state root near
    // `contract.max_path` over the limit on runs that never asked for this observer.
    var fsu_sentinel_a: []const u8 = "";
    var fsu_sentinel_b: []const u8 = "";
    if (args.oracle_fs_usage) {
        // The display cap cuts a pathname from the LEFT (measured: 144, 153 and 156 on
        // two machines), so a state root long enough to be cut takes its own prefix off
        // every line and nothing in the capture can be scoped to it. Checked before the
        // observer starts, so the refusal is a setup error rather than a silent hole.
        // The bound counts what fs_usage prints, not what the caller typed: the data
        // volume's firmlink prefix and the sentinel's own name ride on every line.
        if (state_abs.len > fsu_sentinel_max_root)
            setupError(.define_invalid, "--oracle-fs-usage cannot scope a state directory this deep: fs_usage prints pathnames with the data volume's firmlink prefix (20 bytes) and cuts long ones from the left at a display cap measured at 144, 153 and 156 bytes, and the sentinel's own name takes 40, so the state root must be 96 bytes or fewer (under a smaller cap a root over 84 passes here and is refused at the handshake or as missing_sentinel instead, never judged). Use a shorter --state path");
        const pair = fsUsageSentinels(state_abs, &run.rec.fsu_sentinel_a_buf, &run.rec.fsu_sentinel_b_buf) orelse
            setupError(.environment, "could not name the fs_usage sentinels: either getentropy refused to supply the eight bytes each name is drawn from, or the state path plus 40 bytes did not fit the path buffer; refusing to start an observer whose sentinel a target could name");
        fsu_sentinel_a = pair.a;
        fsu_sentinel_b = pair.b;
    }

    // Not before the checks above: a mistake they refuse must leave the state as the setup left it.
    engine.restore(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the state directory before the recording run", state_abs);

    // Not above the rebuild: a rebuild that fails before the operation has run is a SETUP
    // ERROR, and the rewrite disposition and the snapshot cap read this line to tell it from
    // one past the recording.
    refuse.run_phase = .exploring;

    // Not after the spawn: the name may then resolve to another file than the one executed.
    // Not between the mark and the spawn: an unbounded reading there eats the two seconds
    // `--twice` promises between its runs' starts. Not per world: it is not an observer.
    boundary.rec_image = image.observe(arena, op_argv[0], args.cwd, if (std.c.getenv("PATH")) |p| std.mem.span(p) else null);

    const fsu_started_ms = posix.monotonicMs();
    if (args.oracle_fs_usage) fsu_pid = startFsUsage(gpa, arena, oracle_out, fsu_sentinel_a, fsusage_time_limit_s);

    // The recording run's cgroup (contract v17, #559), made before the mark for the reason the
    // image reading above gives: nothing whose cost this engine does not bound sits between the
    // mark and the spawn. The probe behind it runs once per engine.
    run.rec.cgroup = containment.spawn(false);

    // Before the spawn, where the comment on this mark says it belongs, so `--twice`
    // measures the interval between the two runs it compares. Its placement used to carry
    const rec_started_ms = posix.monotonicMs();

    const rec_term = runOperationObserved(
        gpa,
        arena,
        op_argv,
        state_abs,
        state_alt,
        shim,
        args.oracle,
        oracle_out,
        rec_trace,
        rec_stdout,
        args.cwd,
        args.observe,
        if (run.rec.cgroup) |*cg| cg else null,
    );

    if (fsu_pid) |pid| {
        var zb: [contract.max_path]u8 = undefined;
        const sz = std.mem.printSentinel(&zb, "{s}", .{fsu_sentinel_b}, 0) catch setupError(.define_invalid, "path too long");
        const fd = posix.open(sz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o600));
        if (fd < 0) unknown(.oracle_saw_nothing, "the closing sentinel could not be created inside the state directory, so nothing can establish that the capture covered the end of the recording", .environment);
        _ = posix.close(fd);
        // Stopped, not left to `-t`: the answer to "was it still running?" is what
        // separates a capture of the whole window from one that closed early, and it
        // can only be asked before the signal.
        _ = pid;
        const end = refuse.stopLiveSidecar();
        // Removed before the final snapshot, which is what judges the state: a file the
        // engine created for its own bookkeeping must not appear as an unexplained
        // entry in the tree the verdict is about. Unconditional, so the refusals below
        // do not leave it behind either.
        removeFile(fsu_sentinel_b);
        switch (end) {
            .was_running => {},
            .had_exited => {
                const ended = fsusage.ended(arena, posix.monotonicMs() - fsu_started_ms, fsusage_time_limit_s);
                unknown(.oracle_saw_nothing, ended.detail, ended.next);
            },
            .would_not_die => unknown(.oracle_saw_nothing, "fs_usage did not stop when asked, so nothing bounds what its capture covers", .environment),
        }
    }
    const op_obs = refuse.cwdObservation(arena, op_argv);
    const op_step = refuse.cwdStep(op_obs, boundary.fixDefineUnder(args.observe));
    const exit_step = refuse.cwdStep(op_obs, boundary.recordingEndedStep(args.observe, true));
    const sig_step = refuse.cwdStep(op_obs, boundary.recordingEndedStep(args.observe, false));
    // Not refused here when the image names a platform and the run died: refusing before the
    // trace is read would blame the target for a library that never loaded in it.
    const end_deferred = boundary.defersRecordingEnd(rec_term, boundary.rec_image);
    if (end_deferred) boundary.rec_end_deferred = rec_term else refuse.recordingEnd(arena, rec_term, expect_status, op_obs, exit_step, sig_step);

    // A marker the clean run cannot produce would make every post-success obligation
    // vacuous while the report still said PASS (ADR 0008). Checked against the
    // recording run — the run that completes normally, where even an unflushed stdio
    // buffer reaches the capture through the exit-time flush. A crash world killed
    // before the marker is not this: there the conditional simply does not apply.
    const rec_capture = capture.observeCapture(rec_stdout, args.marker) catch
        setupError(.environment, "the recording run's stdout capture could not be read back");
    if (args.marker != null and !end_deferred) {
        if (!rec_capture.marker_seen) {
            report.l1_note = "marker configured; never observed, even in the recording run";
            unknown(.marker_never_observed, refuse.withObservation(arena, "the success marker never appeared in the recording run's own stdout; check the marker string, and whether the target writes it to stdout at all", op_obs, op_step), op_step);
        }
        report.l1_note = "marker observed in the recording run; crash worlds not explored yet";
    }

    const trace = refuse.readTraceOrRefuse(rec_trace, trace_cap, .{ .root = state_abs, .alt = state_alt, .scratch = args.scratch, .initial = &initial }, "could not read the trace");
    if (end_deferred and boundary.heldEndStands(trace)) refuse.recordingEnd(arena, rec_term, expect_status, op_obs, exit_step, sig_step);

    const final = refuse.snapshotOrRefuse(gpa, state_abs, "could not snapshot the final state");

    // Classified before the structural detectors, so every exit below — including the
    // UNKNOWNs — reports the classification that actually existed, not a placeholder.
    const l0_plan = engine.classifyWith(gpa, initial, final, report.scratch_declared) catch setupError(.environment, "out of memory");
    report.l0_history_count = l0_plan.history_count;
    report.l0_note = report.buildL0Note(arena, l0_plan);
    // #638, ADR 0079: the same plan, as data. Published here rather than at the report's
    // own build so that every exit below — the UNKNOWNs included — carries the set that
    // actually existed, for the reason the paragraph above gives about the note.
    report.publishJudgedPaths(arena, l0_plan);

    // Now that the classification exists, not at the read: see the pairing above. Ahead
    // of the version check below, and the two cannot both apply: a capped read returns
    // before `decodeHeader`, so `version_mismatch` is always false when `too_large` is set.
    refuse.answerForOversizedTrace(trace, "the recording run", trace_cap);

    run.rec.rec_trace = rec_trace;
    run.rec.op_argv = op_argv;
    run.rec.oracle_out = oracle_out;
    run.rec.rec_stdout = rec_stdout;
    run.rec.fsu_sentinel_a = fsu_sentinel_a;
    run.rec.fsu_sentinel_b = fsu_sentinel_b;
    run.rec.rec_started_ms = rec_started_ms;
    run.rec.rec_capture = rec_capture;
    run.rec.trace = trace;
    run.rec.final = final;
    run.rec.l0_plan = l0_plan;
}

fn phaseStructural(run: *Run) void {
    const args = run.parsed.args;
    const arena = run.arena;
    const trace = run.rec.trace;

    // These run first on purpose. Exploring N worlds on top of a recording run that
    // cannot be trusted only multiplies the untrustworthiness — and every one of those
    // worlds would produce a verdict that looks just as confident.

    boundary.boundary_ev.trace_read = true;

    if (trace.version_mismatch)
        unknown(.contract_version_mismatch, "the shim was built against a different trace contract than this engine", .rebuild_pair);

    if (!trace.saw_shim_ready)
        unknown(.no_shim_marker, boundary.noShimDetail(arena), boundary.noShimNext());

    // Without this the mode is a request and not a fact: a shim that could not install
    // its filter records the write family through the wrappers instead, and the report
    // would carry a verdict for flush granularity while the invocation said syscalls.
    // The kernel check before the run catches the ordinary cause; this catches the rest
    // — a target that drops privileges, a process spawned into a context of its own, a
    // shim built for a platform that has no filter to install.
    //
    // **Placed here, after the three checks that explain an empty announcement**, and not
    // where it was first written — between the trace read and the oversized-trace answer.
    // From there it intercepted a run whose shim never loaded at all (a wrong `--shim`, a
    // static or setuid target, a mismatched architecture), a v13 shim, and a capped read,
    // and told all three that "the trace was written by a shim that did not read the
    // request". For the first of those no shim wrote the trace, and the sentence made
    // `no_shim_marker` — which `docs/report-schema.md` documents for exactly that input —
    // unreachable in this mode, turning the most ordinary environment failure there is
    // from UNKNOWN into a SETUP ERROR (review, P0).
    //
    // A SETUP ERROR rather than an UNKNOWN because `docs/report-schema.md`'s
    // `unknown_reason` set is closed by name and `docs/contract-freeze.md` surface 2
    // calls gaining a member a breaking change — and because this is what a setup error
    // is: the run could not be arranged the way the invocation declared, which is the
    // same reading the `apparatus` check uses for a device that was not there.
    if (args.observe == .supervised and !std.mem.eql(u8, trace.observe_aux, contract.observe_aux.supervised))
        setupError(.environment, "--observe supervised: the recording run's account was not written by the supervising engine, so its observation path cannot be claimed");
    if (args.observe == .syscalls and !std.mem.eql(u8, trace.observe_aux, contract.observe_aux.armed)) {
        if (std.mem.eql(u8, trace.observe_aux, contract.observe_aux.unsupported))
            setupError(.platform_unsupported, "--observe syscalls was asked for and the shim reports it cannot install a filter at all: this shim was built for a platform or an architecture whose trap frame it does not know. Rebuild the pair, or use --observe wrappers");
        if (std.mem.eql(u8, trace.observe_aux, contract.observe_aux.failed))
            setupError(.environment, "--observe syscalls was asked for and the shim's filter installation was refused inside the target's own process, although this kernel accepts SECCOMP_RET_TRAP. A target that drops privileges or clears PR_SET_NO_NEW_PRIVS reaches this; --observe wrappers does not need a filter");
        setupError(.environment, "--observe syscalls was asked for and the subject's announcement does not say the filter was installed: the trace was written by a shim that did not read the request. Rebuild the engine and the shim from the same tree");
    }

    // The shim's half of the boundary evidence, recorded the moment the trace is known
    // to be the shim's — before every refusal below, because each of them writes a
    // report and the account has to say what had been observed by then. The order is the
    // rule `metadata_note` states and this field used to break: publish what was seen,
    // never a default standing in for it.
    boundary.boundary_ev.shim_reported = true;
    boundary.boundary_ev.shim_boundary = trace.crossedBoundary();
    boundary.boundary_ev.shim_process_boundary = trace.crossedProcessBoundary();
    boundary.boundary_ev.shim_foreign_touch = trace.foreign_kill_point;
    boundary.boundary_ev.exec_continuations = trace.exec_continuations;
    boundary.boundary_ev.exec_chain_broken = trace.exec_chain_broken;
    if (trace.hard_boundary) |b| boundary.boundary_ev.shim_hard = switch (b) {
        // The engine says of the other .exec shape "refusing is the safe misreading"
        // (below), so the account must not assert breakage it did not establish. The
        // two wordings split on the same field the refusal splits on.
        .exec => if (trace.exec_chain_broken)
            "an image replacement whose chain of observation broke"
        else
            "an image replacement before the subject announced itself",
        else => null,
    };
    const rec_cg: ?*const posix.CgroupSpawn = if (run.rec.cgroup) |*cg| cg else null;
    const detach_refused = trace.detached != null and !containment.holds(rec_cg, &trace, false);
    if (boundary.boundary_ev.shim_hard == null and detach_refused)
        boundary.boundary_ev.shim_hard = "a process leaving the containment group";
    // The larger of the two counts (v18): a creator's `.thread` is dropped when the shim is
    // re-entered, the child's own start is not, and either is the shim having seen it.
    boundary.boundary_ev.threads = @max(trace.thread_records, trace.thread_start_records);
    boundary.boundary_ev.unrecorded_writer_thread = trace.unrecorded_writer_thread;
    boundary.boundary_ev.writer_threads = trace.subject_writer_tids;
    boundary.boundary_ev.thread_turns = trace.thread_turns;
    boundary.boundary_ev.thread_joins = trace.thread_joins;
    boundary.boundary_ev.thread_detaches = trace.thread_detaches;
    boundary.boundary_ev.shim_thread_only = trace.boundary == .thread and !trace.crossedProcessBoundary() and trace.exec_continuations == 0;
    boundary.boundary_ev.shim_subject_detached = trace.subject_detached and !trace.crossedProcessBoundary();

    if (trace.truncated)
        unknown(.trace_truncated, "the trace ends mid-record; how many operations there were is unknown", .retry_then_report);

    // Keyed on the record that refuses, not on the first unplaceable one: an
    // `unlinked-fd close` is exempt (ADR 0003 §2 — close is neither a kill point nor a
    // mutation, so no crash point was going to be computed from it), and it can arrive
    // ahead of one that is not. The message names the refusing record for the same
    // reason #485 exists: a refusal that names a different operation than the one it is
    // about sends the reader looking in the wrong place.
    if (trace.unresolved_refusing != null)
        unknown(.unresolvable_path, boundary.unresolvedDetail(arena, trace.unresolved_refusing, "", "an operation was observed whose path could not be determined, so it cannot be placed among the crash points"), boundary.traceClosedNext(trace.unresolved_refusing));

    if (trace.first_unsupported) |name|
        unknown(.unsupported_syscall_observed, name, .class_wall);

    // asked about below it since #559's second half. Read from `hard_boundary`, not
    // `boundary`: the first boundary in the trace can be a tolerable fork written
    // *before* the record that must refuse the run, and the refusal must not lose to it.
    if (trace.hard_boundary) |b| switch (b) {
        .exec => if (trace.exec_chain_broken) {
            const broke = "the target replaced its own image and the chain of observation broke: no continuation record carrying the operation count followed, or the subject announced itself again without an exec record (an execl-family call, a static image, or a stripped environment cannot carry the count). An unbroken self-exec chain is judged; a separate process is not (#123)";
            const sx = boundary.selfExecStep(arena);
            unknown(.child_process_detected, std.fmt.allocPrint(arena, "{s}{s}", .{ broke, sx.detail }) catch broke, sx.next);
        } else unknown(.child_process_detected, "an image replacement was recorded before the subject announced itself; refusing is the safe misreading", .unwrap_or_class_wall),
        else => {},
    };
    // After the image-change refusal above, which a detach recorded first no longer hides.
    if (detach_refused) containment.refuseDetach(arena, rec_cg, "");
    // own traces below. In front of the numbering check on purpose: the same race trips
    // that one too, and this is the refusal that says why.
    if (trace.second_writer_thread) |op|
        unknown(.multiple_threads_detected, boundary.threadDetail(arena, trace.first_writer_thread, op, trace.first_writer_thread_detached, ""), boundary.threadsStep(args.observe, boundary.oneThreadSwitchSet(&envValue)));

    const children_admitted = false;

    // from the oracle block below). The two witnesses have different blind spots — the
    // oracle reads paths textually and misses a child's relative spelling of a state
    // path, which the shim resolves against the child's own cwd; the shim misses any
    // child that never loaded it, which the oracle sees — and a slice that admits a run
    // has to hear from both. Refusing here, before the oracle has been read, could only
    // ever answer "no".

    // **This answers before the child decision, and the message is what carries the
    // difference.** The refusal that used to sit above this line is gone — deciding
    // whether a run's children may be judged needs the oracle, which is parsed further
    // down — so a run whose operations interleave across processes reaches this check
    // first, and two processes taking one number is exactly what interleaving produces.
    // Rather than move the check (it must run for a run with no oracle at all, which
    // never reaches the later site), the sentence names the cause when more than one
    // process wrote. An earlier version of this comment claimed the opposite order and
    if (trace.kill_records != trace.kill_point_count)
        unknown(.sequence_numbering_broken, if (trace.foreign_kill_point)
            "two processes took the same number: the run's kill-point records and its highest sequence number disagree, which is what happens when their operations run at the same time — each reads the highest number the trace holds and both take the next one. No crash-point address can be trusted"
        else
            "the run's kill-point records and its highest sequence number disagree; the numbering has gaps or duplicates and no crash-point address can be trusted", .class_wall);

    const crossed_boundary = boundary.boundary_ev.shim_boundary;
    // `needsOracle`, not `crossed_boundary`, for the two requirements (v16): a thread
    // on its own arms the quiescence sampling below like any boundary, and needs no
    // second witness — its writes reach the shim, which shares its process. The
    // sampling keeps `crossed_boundary`, which keeps every class.
    if (trace.needsOracle() and !args.has_oracle)
        unknown(.boundary_without_oracle, if (builtin.os.tag == .macos) "the target crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; on macOS no witness this engine reads can (#702)" else "the target crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; pass --oracle (Linux)", .account_boundary_or_unwrap);
    // The fs_usage oracle cannot account for other processes the way strace does, so a
    // boundary the shim saw is not tolerated under it. fs_usage excludes processes by
    // name — the man page lists Terminal, sshd and the shells, and `-e` does not lift
    // that (measured: a `/bin/sh` child produced zero lines under its own name) — so a
    // child that execs one of them mutates the judged directory in nobody's account.
    if (trace.needsOracle() and args.oracle_fs_usage)
        unknown(.boundary_without_oracle, "the target crossed a process boundary and the fs_usage oracle cannot account for other processes: fs_usage excludes some by name (the shells among them) and -e does not lift that, so what a child did in the state directory may be in nobody's account; on macOS the oracle verifies single-process runs", .account_boundary);

    run.admitted.children_admitted = children_admitted;
    run.admitted.crossed_boundary = crossed_boundary;
}

/// One constant for both forms of the `metadata` line: two copies of a sentence drift. `docs/cli.md`
/// quotes it.
const restore_carries = "Restore reproduces permission bits (read, write and execute; a directory's owner bits are added) but not ownership, set-id or sticky bits, or timestamps: crash worlds start from the recorded permission bits, with timestamps assigned during restore";

fn phaseOracle(run: *Run) void {
    const gpa = run.gpa;
    const args = run.parsed.args;
    const replay_case = run.define.replay_case;
    const state_abs = run.define.state_abs;
    const state_alt = run.define.state_alt;
    const alt_differs = run.define.alt_differs;
    const initial = run.initial;
    const rec_trace = run.rec.rec_trace;
    const oracle_out = run.rec.oracle_out;
    const rec_stdout = run.rec.rec_stdout;
    const arena = run.arena;
    const fsu_sentinel_a = run.rec.fsu_sentinel_a;
    const fsu_sentinel_b = run.rec.fsu_sentinel_b;
    const rec_capture = run.rec.rec_capture;
    const trace = run.rec.trace;
    const final = run.rec.final;

    var oracle_cgroup_move: ?[]const u8 = null;

    // The wording matters: a PASS carrying this line is making a weaker claim than one
    // that says the two views agreed, and a reader should be able to see which is which
    // without knowing how the run was invoked.
    if (args.allow_unverified)
        report.oracle_note = if (args.observe == .supervised)
            "NOT VERIFIED (--allow-unverified) — nothing checked what the supervising engine counted from outside the target, with no shim loaded"
        else
            "NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported";
    if (args.has_oracle) {
        // Set before the exits below, not after them. Every `unknown()` in this block is
        // raised by the oracle having run and disagreed; a report saying "not run" beside
        // `unknown_reason: oracle_missed_operation` contradicts itself.
        report.oracle_note = if (args.observe == .supervised)
            "ran; the comparison did not complete — the account compared was the supervising engine's, counted from outside the target with no shim loaded"
        else
            "ran; the comparison did not complete";
        // "could not be read", not "produced no output": an oracle that ran and
        // recorded nothing leaves a readable empty file, which the lines-seen check
        // below answers with oracle_saw_nothing. This site fires when the capture
        const text = if (args.oracle_fs_usage)
            capture.readFileAllocCapped(arena, oracle_out, fsusage.capture_cap, .{ .no_follow = true }) orelse {
                const unread = fsusage.unread(arena, fsusage.sizeNoFollow(oracle_out), fsusage.capture_cap);
                unknown(.oracle_saw_nothing, unread.detail, unread.next);
            }
        else
            capture.readFileAlloc(arena, oracle_out) orelse setupError(.environment, "the oracle's capture file could not be read");
        refuse.dropCapture();
        // This line is the whole reason `cwd` is not a one-line feature. The shim reads
        // the cwd inside the child, so it follows the chdir on its own; the oracle reads
        // a trace after the fact and has to be told. Left at the engine's cwd, the two
        // observers would resolve the same relative path to two different files — and the
        // completeness check that compares them reports that as the shim having missed an
        // operation, or as a containment decision about a file nothing touched. A verdict
        // drawn from that is wrong in a way neither observer can see.
        const oracle_cwd = run.define.effective_cwd orelse "/";
        // The strace reader is not handed "/" when the engine's own cwd could not be read: a
        // relative path resolved against the wrong directory reads as outside the state,
        // where an unknown cwd refuses.
        const parsed = if (args.oracle_fs_usage) blk: {
            const err_text = capture.readFileAllocCapped(arena, fsusage.errPath(arena, oracle_out) catch setupError(.environment, "out of memory"), 64 * 1024, .{ .no_follow = true }) orelse
                unknown(.oracle_saw_nothing, "fs_usage's stderr could not be read back, or grew past what this engine reads, so whether it dropped events is unknown", .environment);
            if (std.mem.indexOf(u8, err_text, "buffer overrun") != null)
                unknown(.oracle_saw_nothing, "fs_usage reported a buffer overrun: the machine produced events faster than it read them and it dropped some, so the capture can be missing an operation", .environment);
            const std_scope = fsusage.standardFdScope(state_abs, if (alt_differs) state_alt else "", rec_stdout);
            const r = fsusage.readWithStd(arena, text, state_abs, if (alt_differs) state_alt else "", rec_trace, fsu_sentinel_a, fsu_sentinel_b, oracle_cwd, trace.subject_writer_tid_list.items, trace.subject_started_tid_list.items, std_scope) catch setupError(.environment, "out of memory");
            if (r.defect) |d| switch (d) {
                .unparsed => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "a line of the fs_usage capture did not match the grammar, so the account has a hole: {s}", .{textShown(arena, l)}) catch "a line of the fs_usage capture did not match the grammar", .sideeye_defect),
                .truncated => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "fs_usage cut a pathname at its display width, so the line cannot be scoped to the state directory either way: {s}", .{textShown(arena, l)}) catch "fs_usage cut a pathname at its display width", .narrow_state),
                .unresolved_fd => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the capture carries an operation on a descriptor it never saw opened, so where it points is unknown: {s}", .{textShown(arena, l)}) catch "the capture carries an operation on a descriptor it never saw opened", .strace_on_linux),
                .unresolvable_path => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the capture carries an operation whose path this reader could not read or place, so where it points is unknown: {s}", .{textShown(arena, l)}) catch "the capture carries an operation whose path could not be read or placed", .sideeye_defect),
                .unknown_call => |l| unknown(.unsupported_syscall_observed, std.fmt.allocPrint(arena, "fs_usage reported a call on the state directory that this version does not model: {s}", .{textShown(arena, l)}) catch "fs_usage reported a call this version does not model", .strace_on_linux),
                .no_subject => unknown(.oracle_saw_nothing, "no thread in the fs_usage capture wrote to the shim's trace file, so the capture cannot say which lines are the subject's", .strace_on_linux),
                .missing_sentinel => |sp| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the fs_usage capture is missing a sentinel the engine placed ({s}), so nothing establishes that the observer covered the whole recording", .{textShown(arena, sp)}) catch "the fs_usage capture is missing a sentinel the engine placed", .environment),
            };
            break :blk r.parsed;
        } else oracle.parse(arena, text, state_abs, if (alt_differs) state_alt else "", run.define.effective_cwd orelse "") catch setupError(.environment, "out of memory");

        // The witness has now looked, and what it saw is part of the account from here
        // on — including on the refusals immediately below, which are exactly the runs
        // where a stale "single process" used to be published.
        boundary.boundary_ev.witness = .{ .read = .{
            .kind = if (args.oracle_fs_usage) .fs_usage else .strace,
            .children = parsed.children,
            .lines = parsed.lines_seen,
        } };
        boundary.boundary_ev.oracle_child_touched = parsed.childTouched();
        // A child's detach is the oracle's boundary in the account only where it refuses: in a
        // run the engine held it is a child like any other (#559), and naming it here would
        // hide the sentence the account gives every other child.
        const rec_cg: ?*const posix.CgroupSpawn = if (run.rec.cgroup) |*cg| cg else null;
        const detach_refused = parsed.detached != null and !containment.holds(rec_cg, &trace, false);
        boundary.boundary_ev.oracle_boundary = parsed.boundary orelse if (detach_refused) parsed.detached else null;

        // Set before any exit below, like oracle_note: an UNKNOWN raised by this
        // block must still carry what the oracle saw being excluded (#121).
        report.metadata_note = blk: {
            const items = parsed.metadata_observed.items;
            if (items.len == 0) break :blk "none observed. " ++ restore_carries;
            var names: std.ArrayList(u8) = .empty;
            var listed: std.ArrayList([]const u8) = .empty;
            for (items) |n| {
                var dup = false;
                for (listed.items) |s| {
                    if (std.mem.eql(u8, s, n)) {
                        dup = true;
                        break;
                    }
                }
                if (dup) continue;
                listed.append(arena, n) catch break :blk "observed (detail unavailable)";
                var count: usize = 0;
                for (items) |m| {
                    if (std.mem.eql(u8, m, n)) count += 1;
                }
                if (names.items.len > 0) names.appendSlice(arena, ", ") catch break :blk "observed (detail unavailable)";
                const piece = std.fmt.allocPrint(arena, "{s} x{d}", .{ n, count }) catch break :blk "observed (detail unavailable)";
                names.appendSlice(arena, piece) catch break :blk "observed (detail unavailable)";
            }
            break :blk std.fmt.allocPrint(
                arena,
                "{d} ownership/permission/timestamp write(s) observed and excluded from judgement — outside the judged state (#121, #190): {s}. " ++ restore_carries,
                .{ items.len, names.items },
            ) catch "observed (detail unavailable)";
        };

        // An oracle that observed nothing agrees with a shim that observed nothing, and
        // the report says "agreed" either way. The acceptance suite asserts by hand that
        if (parsed.lines_seen == 0)
            unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the oracle produced no output, so nothing was compared against {s}'s account — the program given as the oracle wrote nothing to its output file: check that it is strace, and that it writes its account where -o names", .{boundary.recorder()}) catch "the oracle produced no output, so nothing was compared", .environment);

        if (parsed.boundary) |name|
            unknown(.child_process_detected, name, .unwrap_or_class_wall);
        if (detach_refused)
            containment.refuseDetach(arena, rec_cg, std.fmt.allocPrint(arena, ", seen by the oracle as a child's {s}", .{parsed.detached.?}) catch "");
        oracle_cgroup_move = parsed.cgroup_move;

        // The tolerance condition, now decided by both witnesses at once (v15). Either
        // one seeing a writing child brings the question up; the answer needs the two of
        // them, which is why this is the site — the shim's own view is in `trace` and the
        // oracle's has just been parsed.
        if (trace.foreign_kill_point or parsed.childTouched()) {
            if (boundary.childrenMayBeJudged(arena, trace, parsed)) |why| {
                // one. The rule and the evidence it reads live in
                // `unattributedWriterReason`, as a function so that a test can reach it —
                // written inline here it had no check at all, and switching it off left
                // every unit test green while only the message branch was pinned.
                const reason = boundary.unattributedWriterReason(trace, parsed);
                unknown(reason, boundary.withOracleCapture(arena, why.detail, if (args.oracle != null) oracle_out else null, why.detail), boundary.staticParentNext(
                    boundary.childTouchedNext(why.wall, args.observe, builtin.os.tag == .linux),
                    why.wall == .shimmed_writer_unnumbered and boundary.shimAnnouncedElsewhere(trace.primary_pid, parsed.primary_pid),
                ));
            }
            run.admitted.children_admitted = true;
            boundary.boundary_ev.children_judged = true;
        }

        if (parsed.unsupported) |name|
            unknown(.unsupported_syscall_observed, name, .class_wall);

        var shim_classes: std.ArrayList(contract.OpClass) = .empty;
        // Index-aligned with shim_classes, so a refusal can say what the shim's
        // account holds at the divergence instead of only that one exists (#41).
        var shim_ops: std.ArrayList(engine.Op) = .empty;
        for (trace.ops.items) |op| {
            if (op.class.isMarker() or op.class.isBoundary() or op.class.isThreadSync()) continue;
            // close stays in the trace but leaves the comparison (ADR 0003): the oracle
            // sees descriptors the shim never saw born, and pairing closes across the
            // two views has no honest fixpoint.
            if (op.class == .close) continue;
            if (trace.primary_pid != null and op.pid != trace.primary_pid.?) continue;
            shim_classes.append(arena, op.class) catch setupError(.environment, "out of memory");
            shim_ops.append(arena, op) catch setupError(.environment, "out of memory");
        }

        const mode_hint = if (args.observe == .syscalls)
            " — and under --observe syscalls each trapped call reaches the oracle twice, once refused and once re-issued, so this can also mean a refusal the capture did not carry (one operation too many) or a retraction that fired on an entry that had run (one too few)"
        else
            "";
        if (oracle.compare(shim_classes.items, parsed.classes.items)) |f| switch (f) {
            .missed => |m| unknown(.oracle_missed_operation, report.divergenceDetail(
                arena,
                std.fmt.allocPrint(arena, "the oracle saw a state-directory operation the {s} did not record{s}", .{ supervise.observerName(args.observe), mode_hint }) catch
                    "the oracle saw a state-directory operation the observer did not record",
                m.index,
                shim_ops.items,
                parsed.lines.items,
                parsed.names.items,
            ), boundary.staticParentNext(
                boundary.missedOperationNext(args.observe, builtin.os.tag == .linux),
                boundary.shimAnnouncedElsewhere(trace.primary_pid, parsed.primary_pid),
            )),
            .phantom => |p| unknown(.oracle_saw_phantom, report.divergenceDetail(
                arena,
                std.fmt.allocPrint(arena, "the {s} recorded an operation the oracle did not see{s}", .{ supervise.observerName(args.observe), mode_hint }) catch
                    "the observer recorded an operation the oracle did not see",
                p.index,
                shim_ops.items,
                parsed.lines.items,
                parsed.names.items,
            ), .sideeye_defect),
            .unsupported => |name| unknown(.unsupported_syscall_observed, name, .class_wall),
        };

        // **Not `oracle_verified` when the run's crash points include operations this
        // comparison did not cover** (v15). The comparison is the subject's account
        // against the oracle's view of the subject; a run with admitted children has
        // crash points the oracle testified to the existence and the ORDER of, and not
        // the content of. `pass mv` is the shape that makes it visible: the subject is a
        // shell that writes nothing itself, so "agreed on 0 operations" sits beside a
        // PASS over five crash points, all of them children's.
        //
        // The pattern is the one v14 set for `--observe syscalls` and for the same stated
        // reason: a weaker claim gets a name rather than the stronger field's, because
        // `docs/contract-freeze.md` surface 2 says a machine field changes name before it
        // changes meaning. So the `verdict == "PASS" && oracle_verified` gate keeps
        // treating this class as unverified, which is the conservative reading.
        if (run.admitted.children_admitted)
            report.oracle_verified_subject_only = true
        else
            report.oracle_verified = true;
        // The witness and its narrowing go at the END of the line. Two acceptance checks
        // match `agreed on N operations` as a substring (two legs in spike/acceptance.sh;
        // the line numbers that stood here, 703 and 2835, no longer point at them);
        // a prefix would break them, and "surface 2 permits improving the prose" is a
        // licence about the freeze, not about the checks that hold the code to it.
        const agreed = std.fmt.allocPrint(
            arena,
            // "syscall lines examined" verbatim: a leg in spike/acceptance.sh extracts
            // the count with `grep -o '[0-9]* syscall lines examined'`, and dropping the word
            // made the oracle-agreement check read scanned=0 (CI, first run of #406).
            "agreed on {d} operations ({d} syscall lines examined, {d} in scope of the judged state)",
            .{ parsed.classes.items.len, parsed.lines_seen, parsed.lines_in_scope },
        ) catch "agreed";
        report.oracle_operations_agreed = parsed.classes.items.len;
        report.oracle_note = if (args.oracle_fs_usage)
            std.fmt.allocPrint(
                arena,
                "{s}, witness fs_usage. Narrower than strace, each toward refusal: a rename is checked at " ++
                    "its old path only (fs_usage prints no destination); a process boundary is not tolerated " ++
                    "(fs_usage excludes some processes by name); a chdir by the subject leaves relative " ++
                    "operands unplaceable; a pathname cut by the display width refuses. Two things it cannot " ++
                    "see at all: a process leaving the containment group, and a neighbour's descriptor into " ++
                    "the state directory opened before the capture began",
                .{agreed},
            ) catch agreed
        else blk: {
            // strace. Two disclosures can apply to one run — a syscalls-mode run whose
            // writing children were admitted is exactly the shape this release opened —
            // so they are appended in turn rather than chosen between. Both go AFTER
            // "witness strace" because two acceptance legs match `agreed on N operations`
            // as a substring, and a prefix would break them.
            var note = std.fmt.allocPrint(arena, "{s}, witness strace", .{agreed}) catch agreed;
            if (args.observe == .syscalls)
                note = std.fmt.allocPrint(
                    arena,
                    "{s} of THIS run — the kernel refuses each trapped call and the handler re-issues it, " ++
                        "so the capture carries the refused entry beside the one that ran; each refused entry " ++
                        "is retracted when its `--- SIGSYS ... si_code=SYS_SECCOMP ---` is read",
                    .{note},
                ) catch note;
            if (args.observe == .supervised)
                note = std.fmt.allocPrint(
                    arena,
                    "{s} of THIS run — the operations were counted from outside the target by the supervising " ++
                        "engine through a seccomp user-notification filter, no shim loaded; in this mode the oracle " ++
                        "does not count an entry strace ended `= ? ERESTART...` (a signal took the call back before it completed)",
                    .{note},
                ) catch note;
            if (run.admitted.children_admitted)
                // Without this the line reads as full agreement — and on a target whose
                // own process writes nothing it reads "agreed on 0 operations" beside a
                // PASS over five crash points, which is exactly the shape a reader would
                // take for "verified".
                note = std.fmt.allocPrint(
                    arena,
                    "{s} — the SUBJECT's operations only. This run's crash points include " ++
                        "operations performed by an awaited child, and those the oracle placed and ordered " ++
                        "rather than compared one by one: this is `oracle_verified_subject_only`, and " ++
                        "`oracle_verified` stays false. What accounts for a write neither observer placed is " ++
                        "the per-path reconciliation, not this comparison",
                    .{note},
                ) catch note;
            break :blk note;
        };

        // The oracle can reveal children the shim never saw (a raw clone whose child
        // loads nothing), and every consequence of having crossed a boundary — the
        // quiescence sampling below above all — must engage for those too. The account
        if (parsed.children > 0) run.admitted.crossed_boundary = true;
    }

    // writer still alive. Two equal samples do not prove a future writer cannot exist;
    // the report says "observed", never "proven".
    if (run.admitted.crossed_boundary) {
        var final_again = refuse.snapshotOrRefuse(gpa, state_abs, "could not re-snapshot the final state");
        defer final_again.deinit();
        if (!snapshotsEqual(final, final_again))
            unknown(.state_not_quiescent, "the state directory changed between two samples taken after the recording run was contained: something is still writing", .quiesce);
        // The capture is L1 evidence and gets the same observation (#46). Its first
        // sample was the marker scan above; the oracle-output parse sits between the
        // two, so the observed window is wide without costing an extra wait.
        const rec_capture_again = capture.observeCapture(rec_stdout, null) catch
            setupError(.environment, "the recording run's stdout capture could not be read back");
        if (rec_capture.sawTruncation() or rec_capture_again.sawTruncation() or
            !rec_capture.fingerprintEql(rec_capture_again))
            unknown(.state_not_quiescent, "the stdout capture changed between two samples taken after the recording run was contained: something is still writing to the inherited stdout", .quiesce);
    }

    if (!snapshotsEqual(initial, final) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed while zero mutating operations were recorded: operations were missed", boundary.unrecordedWriteNext(builtin.os.tag == .linux));

    // #5, after every trust detector above has had its say: under an oracle a mid-run
    // mknod already refused as unsupported_syscall_observed (#121's defined list keeps
    // precedence), and quiescence judged the samples themselves — this catches what
    // reaches here with no syscall witness at all, the no-oracle path being the one
    // place an unreproducible entry could otherwise slip into the worlds.
    refuse.refuseUnsupportedEntry(arena, final, "appeared during the recording run");

    // Placed after `refuseUnsupportedEntry` on purpose. A `mknod`'d FIFO is a change no
    // operation names — the shim interposes no `mknod` anywhere — so running first would
    // take three acceptance legs' refusals and answer them under this name instead of
    // the one that says what is actually wrong with the entry.
    //
    // After the oracle comparison too: where an oracle ran, `oracle_missed_operation`
    // names the specific syscall that went unseen, which is strictly more than "this
    // path is unexplained". This is the detector for the runs that have no second
    // witness at all, which is every macOS run that does not pay root.
    refuse.reconcileOrRefuse(gpa, arena, initial, final, trace.ops.items, state_abs, if (alt_differs) state_alt else "", report.scratch_declared);
    const n = trace.kill_point_count;
    report.crash_points = n;

    // The landing context, before anything is explored — including before the
    // zero-crash-points refusal below, which would otherwise answer for a case whose
    // operations have all disappeared. Classes gate; paths only warn (pid-embedded
    // temp names legitimately differ between runs — the timewarrior shape).
    if (replay_case) |rc| {
        if (rc.ops_total != n)
            unknown(.case_no_longer_applies, std.fmt.allocPrint(arena, "the recording now counts {d} state-changing operation(s); the case was recorded over {d}", .{ n, rc.ops_total }) catch "the operation count changed", .re_record);
        if (rc.k < 1 or rc.k > n)
            unknown(.case_no_longer_applies, "the case's crash point is out of range for this recording", .re_record);
        var hh: [16]u8 = undefined;
        if (!case.prefixHash(trace, rc.k, &hh))
            unknown(.case_no_longer_applies, "the recording's operation numbering has a gap before the crash point; nothing can vouch that the recorded index still names the same operation", .re_record);
        if (!std.mem.eql(u8, &hh, rc.prefix_hash))
            unknown(.case_no_longer_applies, "the class sequence leading to the crash point changed; killing at the recorded index would address a different operation", .re_record);
        const addr = trace.logicalAddress(rc.k);
        const after_class = if (addr.after) |a| a.class.name() else "(start)";
        const before_class = if (addr.before) |b| b.class.name() else "(end)";
        if (!std.mem.eql(u8, after_class, rc.after_class) or !std.mem.eql(u8, before_class, rc.before_class))
            unknown(.case_no_longer_applies, "the operations around the crash point changed class; the case names a different window", .re_record);
        const after_path = if (addr.after) |a| a.path else "";
        const before_path = if (addr.before) |b| b.path else "";
        if (!std.mem.eql(u8, after_path, rc.after_path) or !std.mem.eql(u8, before_path, rc.before_path))
            say("note: the paths at the crash point differ from the recorded case (often pid-embedded temp names); the class structure matches, so the replay proceeds\n", .{});
    }

    // The watch on a contained recording run (contract v17, #559), after every refusal this
    // run already had, so none of them changes name: a process the oracle saw move between
    // cgroups or be created into one, then the cgroup's own account — it stopped, no shim
    // reported itself outside it, no writer was cut short, nothing the trace names outlived
    // it. A run that was not contained is asked none of this.
    if (run.rec.cgroup) |*cg| {
        if (oracle_cgroup_move) |what| unknown(.child_process_detected, what, .class_wall);
        containment.afterRun(arena, cg, &trace, "", true);
    }

    // #683, ADR 0091: measured once every check on the recording's trace has held — the last of
    // them is the contained run's account just above — so a refusal raised on a trace that was cut
    // short, too large, of another contract or not finished carries no count read from it (R1 and
    // R2 of the diff). From the same plan and records, so the count the report carries and the one
    run.rec.judgeable = refuse.measureJudgeable(gpa, arena, initial, final, run.rec.l0_plan, trace.ops.items, state_abs, if (alt_differs) state_alt else "");
    report.l0_judged_paths_touched = run.rec.judgeable.touched;
    // The same point, for the same reason, for the process account's figures (#711, ADR 0096).
    report.processes_measured = true;

    run.n = n;
}

fn phasePreflight(run: *Run) void {
    const gpa = run.gpa;
    const mode = run.parsed.mode;
    const args = run.parsed.args;
    const state = run.define.state;
    const operation = run.define.operation;
    const expect_status = run.define.expect_status;
    const shim = run.define.shim;
    const state_abs = run.define.state_abs;
    const state_alt = run.define.state_alt;
    const initial = run.initial;
    const op_argv = run.rec.op_argv;
    const arena = run.arena;
    const rec_started_ms = run.rec.rec_started_ms;
    const final = run.rec.final;
    const children_admitted = run.admitted.children_admitted;
    const n = run.n;

    // Deliberately *before* the exploration's own zero-crash-point refusal and its loop: preflight
    // makes no PASS claim (so the completeness gate does not apply), and everything a
    // preflight can honestly say is known once the recording-phase gates above have all
    // held their fire. The exploration-only refusals — kill landing, world-side process
    // boundaries, baseline behavior, checker falsification — have not run, and the
    // report says so by name. This exit is unconditional; no explore/replay code below
    // is reachable in preflight mode.
    if (mode == .preflight) {
        // names the toml, and an argv-form define needs no spelling. From the flags the define
        // always carries the string form, so the unwraps below are structurally satisfied;
        // they are refusals rather than unreachables so that another route feeding preflight
        // an argv-form define fails closed with the constraint named instead of printing a
        // hint that cannot be spelled.
        const hint: PreflightHint = if (args.config) |cfg| .{ .config = .{ .path = cfg, .dir = run.define.config_dir.? } } else blk: {
            const pf_msg = "preflight's flags carry the string form of a define; the argv form lives in a sideeye.toml, which `sideeye preflight --config` reads";
            const pf_setup: ?[]const u8 = if (args.setup) |s| switch (s) {
                .str => |x| x,
                .argv => setupError(.define_invalid, pf_msg),
            } else null;
            const pf_op: []const u8 = switch (operation) {
                .str => |x| x,
                .argv => setupError(.define_invalid, pf_msg),
            };
            break :blk .{ .flags = .{ .state = state, .setup = pf_setup, .cwd = args.cwd, .operation = pf_op, .expect_status = args.expect_status, .apparatus = args.apparatus, .scratch = args.scratch } };
        };
        // #682, ADR 0091: the README promises a preflight refusal names the detector a real
        // run would use, and an exploration with no crash point is refused. Ahead of the
        // second run, which would only measure the repeatability of nothing.
        if (n == 0) refuse.refuseNoCrashPoint(arena, args.has_oracle, refuse.cwdObservation(arena, op_argv));
        // #704: a checker reaches preflight only from a toml, and with a crash point the
        // exploration's first refusals for it are these two, in `phaseChecker` and in this
        // order — a command with no words, then nothing to corrupt in the initial snapshot —
        // both before any world. After the zero-crash-point refusal, as there: with none,
        // explore answers that and never reaches the checker. Ahead of the second run, which
        // would rewrite the state.
        if (args.check) |c| {
            _ = refuse.checkerArgv(commandArgv(arena, c));
            refuse.refuseNothingToCorrupt(initial);
        }
        const repeat: ?Repeat = if (args.twice)
            observeAgain(gpa, arena, initial, final, state_abs, state_alt, .{ .root = state_abs, .alt = state_alt, .scratch = args.scratch, .initial = &initial }, op_argv, shim, args.oracle, args.work, expect_status, rec_started_ms, args.cwd, args.observe, children_admitted)
        else
            null;
        // Not after two runs that split: they leave no one state for a control to break.
        const ran_controls: ?report.PreflightControls = if (args.controls.len > 0 and (if (repeat) |r| r.count.equal() else true))
            runControls(gpa, arena, args, state_abs, final)
        else
            null;
        preflightReport(arena, n, hint, .{ .work = if (args.work_named) args.work else null, .state_under = args.state_under, .shim = args.shim, .oracle = args.oracle }, .{
            .check = args.check != null,
            .marker = args.marker != null,
            .recovery = args.recovery != null,
        }, repeat, ran_controls);
    }

    if (n == 0) {
        refuse.requireCompleteness(arena, args.has_oracle, args.allow_unverified);
        refuse.refuseNoCrashPoint(arena, args.has_oracle, refuse.cwdObservation(arena, op_argv));
    }
}

fn refuseSpacedDir(arena: std.mem.Allocator, dir: []const u8, section: []const u8, noun: []const u8, written: []const u8, resolved: []const u8) void {
    if (resolved.ptr != written.ptr and std.mem.indexOfScalar(u8, dir, ' ') != null)
        setupErrorFmt(arena, .define_invalid, "[{s}] takes the string form only, split on spaces, and {s}, the directory its relative command resolves against, holds a space: move the sideeye.toml to a path without one, or name the {s} by an absolute path without one", .{ section, textShown(arena, dir), noun });
}

const LegRun = struct { term: posix.Term, legs: ?[]const controls_mod.Leg };

var unread_legs_buf: [contract.max_path]u8 = undefined;

// Not `/dev/null`: a checker that replaces or removes the file it is handed (`mv`, `rm -f`)
// would, run as root, replace or remove the system's.
fn unreadLegs(work: []const u8) []const u8 {
    const p = std.fmt.bufPrint(&unread_legs_buf, "{s}/legs.unread.txt", .{work}) catch setupError(.define_invalid, "path too long");
    clearLegs(p);
    return p;
}

// An empty directory a checker made at the path is removed too, or every later run would read it;
// one with something in it is left, and reads as unreadable.
fn clearLegs(p: []const u8) void {
    removeFile(p);
    var z: [contract.max_path]u8 = undefined;
    const pz = std.mem.printSentinel(&z, "{s}", .{p}, 0) catch return;
    _ = posix.rmdir(pz.ptr);
}

fn checkerEnv(state_abs: []const u8, legs_path: []const u8) [3][2][]const u8 {
    return .{ .{ "TOY_STATE", state_abs }, .{ contract.env.state_dir, state_abs }, .{ contract.env.legs, legs_path } };
}

fn termWords(arena: std.mem.Allocator, term: posix.Term) []const u8 {
    return switch (term) {
        .exited => |c| std.fmt.allocPrint(arena, "exit {d}", .{c}) catch "exited",
        .signaled => |sig| std.fmt.allocPrint(arena, "signal {d}", .{sig}) catch "signaled",
        .unknown => "ended in a way the engine could not read",
    };
}

fn termPassed(term: posix.Term) bool {
    return switch (term) {
        .exited => |c| c == 0,
        else => false,
    };
}

fn runLabelled(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, argv: []const []const u8, state_abs: []const u8, legs_path: []const u8, capture_name: []const u8, name: []const u8) posix.Term {
    const out = std.fmt.allocPrint(arena, "{s}/{s}", .{ args.work, capture_name }) catch setupError(.environment, "out of memory");
    removeFile(out);
    const term = posix.runChildCapture(gpa, argv, &checkerEnv(state_abs, legs_path), .{ .path = out, .stderr_too = true, .exclusive = true }, args.cwd) catch |e|
        spawnFailure(e, .exploring, "could not run a [controls] command or the checker after it");
    // Labelled on every line: unlabelled, a control's output would read as a world's.
    if (capture.readFileAllocCapped(arena, out, 1024 * 1024, .{ .no_follow = true })) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| if (line.len > 0) say("{s}: {s}\n", .{ name, textShown(arena, line) });
    }
    return term;
}

// `stem` is `baseline` or `control.<leg>`: a leg name holds no `.`, so no leg's files are the baseline's.
fn checkWithLegs(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, cargv: []const []const u8, state_abs: []const u8, stem: []const u8, name: []const u8) LegRun {
    const legs_path = std.fmt.allocPrint(arena, "{s}/{s}.legs.txt", .{ args.work, stem }) catch setupError(.environment, "out of memory");
    // Not a file left from the run before: its lines would be read as this run's.
    clearLegs(legs_path);
    const label = std.fmt.allocPrint(arena, "{s} checker", .{name}) catch setupError(.environment, "out of memory");
    const capture_name = std.fmt.allocPrint(arena, "{s}.check.txt", .{stem}) catch setupError(.environment, "out of memory");
    const term = runLabelled(gpa, arena, args, cargv, state_abs, legs_path, capture_name, label);
    return .{ .term = term, .legs = readLegs(arena, legs_path) };
}

fn readLegs(arena: std.mem.Allocator, legs_path: []const u8) ?[]const controls_mod.Leg {
    var z: [contract.max_path]u8 = undefined;
    const pz = std.mem.printSentinel(&z, "{s}", .{legs_path}, 0) catch return null;
    if ((posix.kindOfPathNoFollow(pz.ptr) catch return null) == .missing) return &.{};
    // `require_regular`, not the kind above: a FIFO put there after it was looked at would hold
    // a plain open forever.
    const text = capture.readFileAllocCapped(arena, legs_path, 64 * 1024, .{ .no_follow = true, .require_regular = true }) orelse return null;
    return controls_mod.parseLegs(arena, text) catch setupError(.environment, "out of memory");
}

fn redNames(arena: std.mem.Allocator, legs: ?[]const controls_mod.Leg) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (legs orelse &.{}) |l| if (l.red) out.append(arena, l.name) catch setupError(.environment, "out of memory");
    return out.items;
}

fn runControls(gpa: std.mem.Allocator, arena: std.mem.Allocator, args: cli.Args, state_abs: []const u8, final: engine.Snapshot) report.PreflightControls {
    const cargv = refuse.checkerArgv(commandArgv(arena, args.check.?));
    engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state before the [controls] baseline", state_abs);
    const base = checkWithLegs(gpa, arena, args, cargv, state_abs, "baseline", "control baseline");
    const base_word = controls_mod.baseline(termPassed(base.term), base.legs);
    const out = arena.alloc(report.PreflightControl, args.controls.len) catch setupError(.environment, "out of memory");
    for (args.controls, out) |c, *o| {
        o.* = .{ .leg = c.leg, .word = @tagName(controls_mod.Word.baseline_red), .control_exit = null, .checker_exit = null, .red = &.{} };
        // Not run under a red baseline: no control can be told apart from it.
        if (base_word != .none) continue;
        engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state before a control", state_abs);
        const cargv_ctl = commandArgv(arena, .{ .str = c.command }) catch setupError(.environment, "out of memory");
        const name = std.fmt.allocPrint(arena, "control({s})", .{c.leg}) catch setupError(.environment, "out of memory");
        const stem = std.fmt.allocPrint(arena, "control.{s}", .{c.leg}) catch setupError(.environment, "out of memory");
        const ctl_capture = std.fmt.allocPrint(arena, "{s}.txt", .{stem}) catch setupError(.environment, "out of memory");
        const ctl_term = runLabelled(gpa, arena, args, cargv_ctl, state_abs, unreadLegs(args.work), ctl_capture, name);
        o.control_exit = termWords(arena, ctl_term);
        if (!termPassed(ctl_term)) {
            o.word = @tagName(controls_mod.Word.control_failed);
            continue;
        }
        const chk = checkWithLegs(gpa, arena, args, cargv, state_abs, stem, name);
        o.word = @tagName(controls_mod.control(base.legs orelse &.{}, c.leg, termPassed(chk.term), chk.legs));
        o.checker_exit = termWords(arena, chk.term);
        o.red = redNames(arena, chk.legs);
    }
    engine.restore(final, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the recorded state after the [controls]", state_abs);
    return .{
        .baseline = .{ .word = @tagName(base_word), .checker_exit = termWords(arena, base.term), .red = redNames(arena, base.legs) },
        .controls = out,
    };
}

fn phaseChecker(run: *Run) void {
    const gpa = run.gpa;
    const args = run.parsed.args;
    const state_abs = run.define.state_abs;
    const initial = run.initial;
    const arena = run.arena;

    // Run before exploring, not after: a checker that cannot tell a corrupted state
    // from a good one will report every world as fine, and the resulting PASS would be
    // a statement about nothing. Better to refuse than to produce a confident answer
    // derived from an instrument that was never shown to respond.
    var check_argv: ?[]const []const u8 = null;
    if (args.check) |check_cmd| {
        const cargv = refuse.checkerArgv(commandArgv(arena, check_cmd));
        check_argv = cargv;
        // Before the falsification exits, for the same reason as the oracle note above:
        // `checker_not_falsified` next to `checker: none configured` is a report arguing
        // with itself about whether a checker was given.
        report.checker_note = "configured; falsification did not complete";

        refuse.refuseNothingToCorrupt(initial);

        engine.restore(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not restore before falsifying the checker", state_abs);
        // Through the same disposition as the restore one line up, not setupError:
        // corruption is the other rewrite of the recorded tree, its errors are the
        // same RestoreError set (UnsafeRoot included — engine/state_fs.zig's own comment on
        // corruptState says why it re-checks the root rather than trusting its
        // neighbour), and by this line the define has run, so exit 3 would claim
        // it never did (#363).
        engine.corruptState(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not corrupt the state for the falsification probe", state_abs);

        // The gate's child output is captured and re-emitted with a per-line
        // `falsify: ` marker (#134). By design this step produces exactly the output
        // a real finding would produce — a target failing over a broken store — and
        // a single line harvested from an unlabeled transcript once became "world
        // evidence" (the buku correction, PR #133). A fence would not travel with an
        // excerpt; a per-line prefix does.
        var fal_buf: [contract.max_path]u8 = undefined;
        const fal_out = std.fmt.bufPrint(&fal_buf, "{s}/falsify-check.txt", .{args.work}) catch setupError(.define_invalid, "path too long");
        removeFile(fal_out);
        // `exclusive` for the same reason as the recording run's, and free for the same reason —
        // `removeFile` is one line up.
        const probe = posix.runChildCapture(gpa, cargv, &checkerEnv(state_abs, unreadLegs(args.work)), .{ .path = fal_out, .stderr_too = true, .exclusive = true }, args.cwd) catch |e| spawnFailure(e, .exploring, "could not run --check");

        // Re-emitted before the verdict on the probe: unknown() exits the process,
        // and the gate's output is evidence in the refusal case too.
        report.sayCaptureMarked(arena, fal_out, "falsify");

        switch (probe) {
            .exited => |code| {
                // switch, before any child exists. What still reaches 126 is a `dup2`
                // that failed in the child — which says so on the engine's
                // stderr — and a checker that genuinely exits 126,
                // which is indistinguishable from it and gets the fail-closed reading.
                if (code == 126)
                    unknown(.checker_not_falsified, "the checker probe exited 126: either the engine's fork stub could not arrange the child before exec (a line on the engine's stderr names the call and the errno) or the checker itself exited 126 — indistinguishable from here, so the gate refuses rather than counting it as red", .environment);
                if (code == 0) {
                    const obs = refuse.cwdObservation(arena, cargv);
                    const step = refuse.cwdStep(obs, .fix_define);
                    unknown(.checker_not_falsified, refuse.withObservation(arena, "the checker accepted a state whose every file had been overwritten with junk and every symlink retargeted at a nonexistent name", obs, step), step);
                }
            },
            else => unknown(.checker_not_falsified, "the checker did not exit normally when given a corrupted state", .run_checker_by_hand),
        }
        report.checker_note = "falsified before the run (corrupted state -> check failed)";

        // After the falsification and after `checker_note`, on purpose: every refusal the gate
        // had keeps its place and its output, and a refusal here leaves the note true — the
        // falsification did complete. The note itself is unchanged: README's demo block and
        // docs/cli.md's real output carry it, and `spike/check-readme-demo.py` compares them with
        // the demo line by line. A checker that passes prints nothing here, so a transcript of a
        // define that was already fine does not change.
        engine.restore(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not restore before showing the checker the starting state", state_abs);
        var start_buf: [contract.max_path]u8 = undefined;
        const start_out = std.fmt.bufPrint(&start_buf, "{s}/start-check.txt", .{args.work}) catch setupError(.define_invalid, "path too long");
        removeFile(start_out);
        const start = posix.runChildCapture(gpa, cargv, &checkerEnv(state_abs, unreadLegs(args.work)), .{ .path = start_out, .stderr_too = true, .exclusive = true }, args.cwd) catch |e| spawnFailure(e, .exploring, "could not run --check on the starting state");
        switch (start) {
            .exited => |code| if (code != 0) {
                // Marked `start: ` for the reason the falsification's lines are marked: this is
                // exactly the output a real finding would produce.
                report.sayCaptureMarked(arena, start_out, "start");
                // 126 as the falsification reads it: the fork stub's own exit code or the
                // checker's, and nothing here tells them apart.
                if (code == 126)
                    unknown(.checker_rejects_initial_state, "the checker probe on the starting state exited 126: either the engine's fork stub could not arrange the child before exec (a line on the engine's stderr names the call and the errno) or the checker itself exited 126 — indistinguishable from here, so the run is refused rather than judged by it", .environment);
                // #700 (ADR 0093): a checker with a relative argument read under the wrong
                // directory rejects every state, this one first. Then the step is the cwd line,
                // and the detail carries no instruction of its own to contradict it.
                const obs = refuse.cwdObservation(arena, cargv);
                const step = refuse.cwdStep(obs, .fix_define);
                // "As Sideeye restores it": the probe sees the state every world starts from, which
                // is the restore's copy, not what setup left — what a restore does not carry is
                // docs/cli.md's to say (#678 is changing it), so the sentence points there rather
                // than naming what is lost.
                const seen = std.fmt.allocPrint(arena, "the checker exited {d} on the state the define starts from, as Sideeye restores it before every world, before the operation ran: nothing the target did is in it", .{code}) catch "the checker rejected the state the define starts from, before the operation ran";
                const what = if (obs != null) seen else std.fmt.allocPrint(arena, "{s}, so a world the checker fails there says nothing about the target — make the checker accept that state (" ++ contract.docUrl("docs/cli.md#example") ++ " says what a restore does not carry)", .{seen}) catch seen;
                unknown(.checker_rejects_initial_state, refuse.withObservation(arena, what, obs, step), step);
            },
            else => {
                report.sayCaptureMarked(arena, start_out, "start");
                unknown(.checker_rejects_initial_state, "the checker did not exit normally on the state the define starts from, as Sideeye restores it before every world, before the operation ran", .run_checker_by_hand);
            },
        }
    }

    run.check_argv = check_argv;
}

fn phaseExploration(run: *Run) void {
    const gpa = run.gpa;
    const args = run.parsed.args;
    const only_k = run.define.only_k;
    const expect_status = run.define.expect_status;
    const shim = run.define.shim;
    const state_abs = run.define.state_abs;
    const state_alt = run.define.state_alt;
    const initial = run.initial;
    const op_argv = run.rec.op_argv;
    const oracle_out = run.rec.oracle_out;
    const arena = run.arena;
    const trace = run.rec.trace;
    const final = run.rec.final;
    const l0_plan = run.rec.l0_plan;
    const children_admitted = run.admitted.children_admitted;
    const crossed_boundary = run.admitted.crossed_boundary;
    const n = run.n;
    const check_argv = run.check_argv;
    const first_failure_path = &run.firsts.first_failure_path;
    const first_checker_path = &run.firsts.first_checker_path;

    var first_failure: ?engine.WorldResult = null;
    var first_failure_l0 = false;
    var first_failure_l1 = false;
    var first_failure_l2 = false;
    var first_failure_path_len: usize = 0;
    var first_checker: ?engine.WorldResult = null;
    var first_checker_l0 = false;
    var first_checker_l1 = false;
    var first_checker_path_len: usize = 0;
    var first_failure_ev: ?evidence.Draft = null;
    // Each exhibit's crash state, kept past its world when a recovery was declared (#606): the
    // world's own `defer` frees it otherwise, and the recovery after the loop is its only reader.
    // `first_checker_snap` stays null when the claim exhibit is the earliest's own world — one
    // world, one snapshot. Not freed: the process ends with the report, as the drafts beside it do.
    var first_failure_snap: ?engine.Snapshot = null;
    var first_checker_snap: ?engine.Snapshot = null;
    var first_checker_ev: ?evidence.Draft = null;
    var marker_worlds: u32 = 0;
    var checks_run: u32 = 0;

    // Beside `world_stdout_buf` and not inside the checker block, although only that block
    // spells it: `co` escapes into `checker_out`, which the exhibit branches read after the
    // block has closed. A buffer declared inside would have ended its life at the closing
    // brace and the read would be of a slot the compiler is free to reuse.
    var checker_out_buf: [contract.max_path]u8 = undefined;
    var world_stdout_buf: [contract.max_path]u8 = undefined;
    const world_stdout = std.fmt.bufPrint(&world_stdout_buf, "{s}/stdout-world.txt", .{args.work}) catch setupError(.define_invalid, "path too long");

    const order = prefix.plan(arena, trace, n, initial, final, state_abs, state_alt, args.scratch) catch setupError(.environment, "out of memory");
    var leave_snap: ?engine.Snapshot = null;
    var k: u32 = 1;
    while (k <= n + 1) : (k += 1) {
        // A replay explores exactly the case's world plus the baseline; every trust
        // gate inside this loop still runs (ADR 0009) — a replay that skipped them
        // would blame the target for whatever the skipped gate existed to catch.
        if (only_k) |okk| {
            if (k != okk and k != n + 1) continue;
        }
        // and rewriting the state directory with nobody left to report to. Checked before
        // `restore`, so what happens instead of the deletion is the refusal rather than
        // the deletion followed by one.
        //
        // The claim is narrow and the reason's own documentation says so: the next world
        // boundary **that is reached**. A setup, recording or checker run that hangs
        // never reaches one, and the process-group teardown that would help there runs at
        // the end of a world, not the start.
        if (args.stop_when_orphaned and posix.getppid() != startup_ppid)
            unknown(.parent_exited, "the process that launched this exploration is gone; stopping at a world boundary rather than continuing to kill processes and rewrite the state directory with nobody to report to", .relaunch);
        engine.restore(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the state directory", state_abs);

        var kbuf: [16]u8 = undefined;
        const kstr = std.fmt.bufPrint(&kbuf, "{d}", .{k}) catch unreachable;
        var wt_buf: [contract.max_path]u8 = undefined;
        const world_trace = std.fmt.bufPrint(&wt_buf, "{s}/trace-{d}.bin", .{ args.work, k }) catch setupError(.define_invalid, "path too long");
        removeFile(world_trace);
        removeFile(world_stdout);

        var wcg = containment.spawn(true);
        const wcg_ptr: ?*posix.CgroupSpawn = if (wcg) |*c| c else null;
        const wsup = supervise.Spawn.start(gpa, arena, args.observe, op_argv, world_trace, state_abs, state_alt, @intCast(k), containment.runName(wcg_ptr), containment.killName(wcg_ptr)) catch |e|
            setupError(.environment, supervise.startFailure(e));
        const wterm = posix.runChildCaptureWorld(gpa, wsup.argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, if (args.observe == .supervised) "" else world_trace },
            .{ contract.env.kill_at, kstr },
            // The engine has put this child in its own process group (`runChildImpl`),
            // so the shim may take the group down rather than one process. Set here and
            // nowhere else: the recording run is not armed, and the `reproduce` line an
            // operator types has no engine behind it to have made the group.
            .{ contract.env.kill_group, "1" },
            // Pinned empty: see the recording pairs.
            .{ contract.env.seq_base, "" },
            .{ contract.env.before_constructor, "" },
            // The same observation path the recording used, necessarily: `kill_at` is an
            // index into the sequence the recording produced, and a world counting
            // through the other path would number differently and stop somewhere else.
            .{ contract.env.observe, args.observe.name() },
            // in place of signalling the group (v17). Pinned empty when this world is not
            // contained, for the reason on the recording pairs.
            .{ contract.env.run_cgroup, containment.runName(wcg_ptr) },
            .{ contract.env.kill_cgroup, containment.killName(wcg_ptr) },
            .{ contract.env.kill_aside, containment.asideName(wcg_ptr) },
            .{ preload_var, supervise.preloadFor(args.observe, shim) },
            // `exclusive` for the reason on `recordingCapture`, and free for the same
            // reason: `removeFile(world_stdout)` is two lines up and runs on every pass
            // of this loop, so a re-run over one work directory never meets its own
            // leftover here.
        }, .{ .path = world_stdout, .exclusive = true }, if (args.world_timeout_s) |s| @as(u64, s) * 1000 else null, args.cwd, wcg_ptr) catch |e| switch (e) {
            error.TimedOut => {
                // The format below is a fixed string plus at most five digits
                // (parseWorldTimeout caps the value at 86400), so 320 bytes holds it
                // with margin — measured, after the first sizing of this buffer read
                // as provable and panicked on the very first firing. `catch
                // unreachable` on a bound someone eyeballed is just a deferred crash;
                // it stays only because the bound is now arithmetic.
                var tbuf: [320]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &tbuf,
                    "a world's operation was still running after the --world-timeout budget of {d} second(s) expired; it was sent SIGKILL, and the remaining worlds cannot be judged. Raise the budget, or investigate what the operation waits on",
                    .{args.world_timeout_s.?},
                ) catch unreachable;
                unknown(.child_timed_out, detail, .raise_world_timeout);
            },
            error.ForkFailed, error.OutOfMemory, error.WaitFailed, error.StdinUnavailable, error.CaptureUnavailable, error.CgroupJoinFailed, error.ChildGroupRefused => |se| spawnFailure(se, .exploring, "could not run --operation"),
        };
        // Every process of the world is dead by now; the supervising thread's account is
        // complete once it has been joined (#217).
        if (supervise.handoverFailure(wsup.finish(), wterm, "a world's run")) |why| setupError(.environment, why);
        const term = wterm;

        var wtrace = refuse.readTraceOrRefuse(world_trace, trace_cap_world, .{ .root = state_abs, .alt = state_alt, .scratch = args.scratch, .initial = &initial }, "could not read a world trace");
        refuse.answerForOversizedTrace(wtrace, "an explored world", trace_cap_world);
        defer wtrace.deinit();

        // The same question the recording's announcement answers, asked of the run that
        // actually produces the verdict (review, P1). `SIDEEYE_KILL_AT` is an index into
        // the sequence the RECORDING counted, and in syscalls mode that sequence is at
        // syscall granularity; a world whose filter did not install counts the write
        // family through the wrappers instead, so its k-th operation is a different
        // operation and the kill lands somewhere nobody chose. Everything above about
        // "the mode is a fact and not a request" applies here more sharply than to the
        // recording, because a wrong answer here is a verdict rather than a refusal.
        if (args.observe == .supervised and !std.mem.eql(u8, wtrace.observe_aux, contract.observe_aux.supervised))
            setupError(.environment, "--observe supervised: a world's account was not written by the supervising engine");
        if (args.observe == .syscalls and !std.mem.eql(u8, wtrace.observe_aux, contract.observe_aux.armed))
            setupError(.environment, "--observe syscalls was asked for and an explored world's shim does not report the filter installed, although the recording run's did: the crash point this world was told to stop at is an index into a sequence it did not count. Re-run, and if it repeats the environment is refusing the filter for some processes and not others");

        // The world's own boundary evidence, before the refusals that read it. Without
        // this the account for a world-side refusal is the *recording's* clause, which
        // review measured saying "no boundary was recorded" on a run refused because a
        // world's child wrote into the judged directory. The world-only site further
        boundary.boundary_ev.world_boundary = boundary.boundary_ev.world_boundary or
            wtrace.crossedBoundary();
        boundary.boundary_ev.world_process_boundary = boundary.boundary_ev.world_process_boundary or
            wtrace.crossedProcessBoundary();
        boundary.boundary_ev.world_thread_only = boundary.boundary_ev.world_thread_only or
            (wtrace.boundary == .thread and !wtrace.crossedProcessBoundary() and wtrace.exec_continuations == 0);
        boundary.boundary_ev.world_subject_detached = boundary.boundary_ev.world_subject_detached or
            (wtrace.subject_detached and !wtrace.crossedProcessBoundary());
        boundary.boundary_ev.world_foreign_touch = boundary.boundary_ev.world_foreign_touch or wtrace.foreign_kill_point;

        // The second witness again, on every explored world and the baseline. A child's
        // behaviour is allowed to differ between worlds — the parent dying earlier
        // changes which path the child takes — so clearing the recording run clears
        // nothing else.
        // A world runs without an oracle, so it cannot ask the three conditions itself;
        // it inherits the recording's answer (v15). What a world does NOT inherit is
        // permission for a child it did not have: a boundary that appears only in an
        // explored world refuses above (#169), and a recording with no writing child
        // leaves `children_admitted` false, so the first one to appear here still stops
        // the run. The residual — a run whose admitted children behave differently in a
        // world — is the window ADR 0002 already records, narrowed by the prefix check
        // below, and named in the report rather than left to be discovered.
        if (wtrace.foreign_kill_point and !children_admitted)
            unknown(.child_touched_state_dir, boundary.foreignTouchDetail(arena, wtrace.first_foreign, "in an explored world", if (args.oracle != null) oracle_out else null, "a process other than the subject performed a state-directory operation in an explored world"), .class_wall);
        // A world may take a branch the recording run did not (the kill changes what the
        // target sees), so an unmodellable in-scope operation can first appear here.
        if (wtrace.first_unsupported) |name|
            unknown(.unsupported_syscall_observed, name, .class_wall);
        // The same sentence, for the same reason, about an operation the shim could not
        // place. **This closes #522**, which is exactly this gap and was filed before the
        // `close` exemption existed: an unplaceable operation refused during recording and
        // was dropped silently in an explored world, towards a false PASS. An earlier
        if (wtrace.unresolved_refusing != null)
            unknown(.unresolvable_path, boundary.unresolvedDetail(arena, wtrace.unresolved_refusing, " in an explored world", "an operation was observed in an explored world whose path could not be determined, so it cannot be placed among the crash points"), .class_wall);
        if (wtrace.hard_boundary) |hb| switch (hb) {
            .exec => unknown(.child_process_detected, "the target replaced its own image in an explored world without an unbroken chain of observation", .class_wall),
            else => {},
        };
        // And a process that left the process group, held or not by this world's own cgroup
        // (#559's second half): a world takes branches the recording did not. A world armed to
        // die can have its kill cut an image off between announcing itself and answering, and
        // that is the kill, not an escape.
        if (wtrace.detached != null and !containment.holds(wcg_ptr, &wtrace, k <= n))
            containment.refuseDetach(arena, wcg_ptr, " in an explored world");
        // The thread rule, asked of this world's own trace (v16): a world takes branches
        // the recording did not, and a second thread writing here is as unordered as one
        // in the recording. Nothing is inherited — the record names its thread.
        if (wtrace.second_writer_thread) |op|
            unknown(.multiple_threads_detected, boundary.threadDetail(arena, wtrace.first_writer_thread, op, wtrace.first_writer_thread_detached, " in an explored world"), boundary.threadsStep(args.observe, boundary.oneThreadSwitchSet(&envValue)));
        if (wtrace.kill_records != wtrace.kill_point_count)
            unknown(.sequence_numbering_broken, "the run's kill-point numbering has gaps or duplicates in an explored world; the world's crash-point address cannot be trusted", .class_wall);

        // address entirely". A number is a position in the run now, so a child's k IS
        // the k the engine asked about — and requiring the subject would mean a world
        // armed at an awaited child's operation could never report a landing at all.
        const landed = wtrace.kill_landed_seq != null and wtrace.kill_landed_seq.? == k;
        if (k <= n and !landed)
            unknown(.kill_did_not_land, "a world was asked to die before a given operation and did not", .kill_not_landed);

        // Not by class alone: two writes of one class to two names swap without changing it.
        if (k <= n) if (prefix.firstDivergence(&order, wtrace, k)) |d|
            unknown(.kill_did_not_land, prefix.detail(arena, d, &order), .not_repeating);
        // A contained world's shim that could not kill it exits and says why (v17, #559) — the
        // one watch that answers ahead of an existing refusal, because this refusal would
        // otherwise file an environment's failure as sideeye's defect.
        if (wcg_ptr != null and k <= n and !term.isSignal(posix.SIGKILL))
            containment.killCameBack(arena, &wtrace, k);
        if (k <= n and !term.isSignal(posix.SIGKILL))
            unknown(.kill_did_not_land, "a world that should have been killed exited on its own", .sideeye_defect);
        if (k > n) switch (term) {
            // 126 first, because it is not evidence about the state: it is the code the
            // engine's own fork stub keeps for a child it could not arrange before exec
            // (`posix.childArrangeFailed` — its stderr line names the call and the errno),
            // and a target that itself exits 126 is indistinguishable from that here. The
            // checker gate reads the same code the same way.
            .exited => |code| if (code == 126 and code != expect_status)
                unknown(.baseline_run_failed, "the un-killed baseline world exited 126: either the engine's fork stub could not arrange the child before exec (a line on the engine's stderr names the call and the errno) or the operation itself exited 126 — indistinguishable from here, and not a statement about the restored state", .environment)
            else if (code != expect_status)
                unknown(.baseline_run_failed, std.fmt.allocPrint(arena, "the un-killed baseline world exited {d} where {d} was expected although the recording run of the same command succeeded: the restored state differs from the recorded one", .{ code, expect_status }) catch "the un-killed baseline world exited with an unexpected status", .second_run_diverged),
            .signaled => |sig| unknown(.baseline_run_failed, std.fmt.allocPrint(arena, "the un-killed baseline world was killed by signal {d}", .{sig}) catch "the un-killed baseline world was killed by a signal", .run_by_hand_signalled),
            else => unknown(.baseline_run_failed, "the un-killed baseline world did not exit normally", .run_by_hand_signalled),
        };

        var crashed = refuse.snapshotOrRefuse(gpa, state_abs, "could not snapshot a crashed state");
        // Kept past this world when it becomes a saved exhibit and a recovery was declared (#606),
        // or when it is the case's world under --leave-crash-state; this is the only copy.
        var crashed_kept = false;
        defer if (!crashed_kept) crashed.deinit();

        // one sample is a moment and two agreeing samples are a state. Boundary
        // evidence is per-world as well as recording-global (#46): a recording that
        // never forked says nothing about a world where the parent dying earlier sent
        // the child down a forking path — the same reason the per-world witness above
        // re-checks what the recording already cleared.
        const world_armed = crossed_boundary or wtrace.crossedBoundary();
        // token — the message is what distinguishes them. The account is written
        // BEFORE the refusal so the report's processes field tells the world's
        // story, never the recording's "single process".
        // `needsOracle` and not `world_armed` (v16): a world whose only boundary is a
        // thread has nothing an oracle would account for, and refusing it here would
        // undo the thread rule for every target whose thread is created inside the
        // operation. The sampling below still arms on it.
        if (!crossed_boundary and wtrace.needsOracle()) {
            boundary.boundary_ev.world_only = true;
            unknown(.boundary_without_oracle, if (wtrace.crossedProcessBoundary())
                "a process boundary appeared in an explored world that the recording never crossed; explored worlds run without an oracle, so nothing accounts for what the other process did"
            else if (wtrace.subject_detached)
                "the subject left its process group in an explored world that the recording never did; explored worlds run without an oracle, so nothing accounts for what followed"
            else
                "the subject replaced its own image in an explored world that the recording never did; explored worlds run without an oracle, so nothing accounts for the chain across that change", .class_wall);
        }
        var world_capture_first: ?capture.CaptureObservation = null;
        if (world_armed) {
            var crashed_again = refuse.snapshotOrRefuse(gpa, state_abs, "could not re-snapshot a crashed state");
            defer crashed_again.deinit();
            if (!snapshotsEqual(crashed, crashed_again))
                unknown(.state_not_quiescent, "the crashed state changed between two samples: something the subject started is still writing", .quiesce);
            // The capture's first sample (#46). The second rides the marker scan below,
            // so the observed window brackets the checker and the scan itself.
            world_capture_first = capture.observeCapture(world_stdout, null) catch
                setupError(.environment, "a world's stdout capture could not be read back");
        }

        report.explored += 1;

        var l2_failed = false;
        var checker_out: ?[]const u8 = null;
        if (check_argv) |cargv| {
            var capture_opened = true;
            const co = std.fmt.bufPrint(&checker_out_buf, "{s}/checker-output.txt", .{args.work}) catch
                setupError(.define_invalid, "path too long");
            // `exclusive` needs the removal, and without `O_EXCL` a FIFO planted at the name
            // would block the parent's open — the pair `Capture.exclusive` asks for by name.
            files.removeFile(co);
            // stderr too, for the reason #483 gives on the setup capture: a checker reports
            // through either stream, and capturing stdout alone would leave the file empty for
            // the ordinary failure.
            const ct = posix.runChildCapture(gpa, cargv, &checkerEnv(state_abs, unreadLegs(args.work)), .{ .path = co, .stderr_too = true, .exclusive = true }, args.cwd) catch |e| switch (e) {
                // The one failure that is about the capture and not about the child: since
                // #469 the parent opens the file, so this arrives before any child exists.
                // The checker still has to run — the verdict rests on its exit status — so
                // it runs uncaptured and the bundle's diagnostic stays unknown. Refusing
                // here would turn a FAIL into an UNKNOWN over an attachment.
                error.CaptureUnavailable => blk_cap: {
                    // Left null on this path deliberately, rather than relying on the
                    // removal above to make the read come back empty: "there is no capture"
                    // and "the capture is empty" are different answers, and only the first
                    // is true here.
                    capture_opened = false;
                    break :blk_cap posix.runChild(gpa, cargv, &checkerEnv(state_abs, unreadLegs(args.work)), args.cwd) catch |e2| spawnFailure(e2, .exploring, "could not run --check");
                },
                else => spawnFailure(e, .exploring, "could not run --check"),
            };
            // Set whichever way the child ended: a checker killed by a signal has often
            // written the line that says why, and the capture is what holds it.
            if (capture_opened) {
                checker_out = co;
                // tells them apart as well, and says which world. `spike/acceptance.sh` counts
                // gate lines, world lines and unmarked checker lines, which must be none.
                if (capture.readFileAllocCapped(arena, co, 1024 * 1024, .{ .no_follow = true })) |text| {
                    var lines = std.mem.splitScalar(u8, text, '\n');
                    while (lines.next()) |line| {
                        if (line.len == 0) continue;
                        if (k > n) say("baseline: {s}\n", .{line}) else say("world {s}: {s}\n", .{ kstr, line });
                    }
                }
            }
            checks_run += 1;
            l2_failed = switch (ct) {
                .exited => |code| code != 0,
                else => true,
            };
        }

        const l0 = engine.judgeL0(l0_plan, crashed);

        var marker_seen = false;
        if (args.marker != null or world_capture_first != null) {
            const world_capture = capture.observeCapture(world_stdout, args.marker) catch
                setupError(.environment, "a world's stdout capture could not be read back");
            // The refusal comes before the marker bit is used anywhere: a scan raced
            // by a live writer must not decide whether L1 applies (#46). Two equal
            // samples are an observation, never a proof of future quiet.
            if (world_capture_first) |first| {
                if (first.sawTruncation() or world_capture.sawTruncation() or
                    !first.fingerprintEql(world_capture))
                    unknown(.state_not_quiescent, "the stdout capture of a crashed world changed between two samples: something the subject started is still writing to the inherited stdout", .quiesce);
            }
            if (args.marker != null) marker_seen = world_capture.marker_seen;
        }

        // #5, after every observation of this world has fired — the armed double
        // sample above and the capture's bracketing second sample just now — so a
        // still-writing world refuses as itself (state_not_quiescent), never as
        // this (R1). A special file reaches this snapshot whether or not any
        // syscall witness saw it born; on macOS with no oracle, none did. The
        // baseline is the one un-killed world, and an entry only IT leaves gets
        // its own attribution instead of a fictitious crash (R1).
        refuse.refuseUnsupportedEntry(arena, crashed, if (k <= n) "left in a crashed world" else "left by the baseline re-run");

        if (marker_seen and k <= n) marker_worlds += 1;
        const l1 = if (marker_seen) engine.judgeL1(l0_plan, initial, final, crashed) else null;

        // The baseline world was never killed. If the invariant fails there, it fails
        // without any help from sideeye — the checker rejects a state the operation
        // produces normally, or the operation is broken on its own — and neither is a
        // crash-consistency counterexample. Reporting it as "N of N explored worlds violated
        // an invariant" blames crashing for something that happens without it.
        // Three layers reach this refusal and the message names which (#199). The byte
        // layer first: the engine knows the path the re-run left holding neither
        // recorded content, and saying "check the checker" about it cost the first real
        // target three measurements. It cannot tell a clock or a random id from a cache
        // keyed on an inode the restore moved (git's index), so the message reports the
        // observation and the path, never a cause; the limit itself — byte-repeatable
        // writes — is the README's, beside `preflight --twice`; since #710 the step names
        // that and `scratch` (ADR 0097). The marker and the checker are the define's own
        if (k > n and (l0 != null or l1 != null or l2_failed)) {
            const step: contract.NextStep = if (l0 != null) .scratch_or_twice else if (l1 != null) .fix_define else boundary.fixDefineUnder(args.observe);
            // #700 (ADR 0093): the checker layer alone, where a checker with a relative argument
            // read under the wrong directory rejects every state. The line above is pinned by
            // spike/acceptance.sh, so the step is replaced here rather than there.
            const base_obs: ?[]const u8 = if (l0 == null and l1 == null) (if (check_argv) |c| refuse.cwdObservation(arena, c) else null) else null;
            const base_step = refuse.cwdStep(base_obs, step);
            const what: []const u8 = if (l0) |v|
                std.fmt.allocPrint(arena, "{s}{s}{s}", .{ report.baselineObserved(arena, v), report.baselineDiffers(arena, l0_plan, crashed, v), report.baselineAlsoFailed(l1 != null, l2_failed) }) catch "the re-run from the restored state did not leave the recorded bytes"
            else if (l1) |v|
                std.fmt.allocPrint(arena, "the operation printed its success marker, and {s} did not hold the new state that marker promised{s}; check the marker and the operation against each other first", .{ textShown(arena, report.violationPath(v)), report.baselineAlsoFailed(false, l2_failed) }) catch "the success marker's promise did not hold in the un-killed re-run; check the marker and the operation against each other first"
            else
                refuse.withObservation(arena, "the checker rejected the state the operation leaves on its own; check the operation and the checker against each other first", base_obs, base_step);
            unknown(.baseline_violates_invariant, std.fmt.allocPrint(arena, "{s}: {s}", .{ report.baseline_refusal_lead, what }) catch what, base_step);
        }

        // The watch on a contained world (contract v17, #559), after every refusal this world
        // already had, so none of them changes name. What was still in the cgroup when the
        // direct child exited counts only in the baseline: a killed world's crash point is what
        // ended it. And nothing ran at or past the crash point.
        if (wcg_ptr) |cg| {
            containment.afterRun(arena, cg, &wtrace, " in an explored world", k > n);
            if (k <= n) containment.pastCrashPoint(arena, &wtrace, k);
        }

        if (l0 != null or l2_failed or l1 != null) {
            report.violations += 1;
            if (first_failure == null) {
                const v = l0 orelse l1;
                first_failure = .{ .k = k, .term = term, .landed = landed, .violation = v };
                first_failure_l0 = l0 != null;
                first_failure_l1 = l1 != null;
                first_failure_l2 = l2_failed;
                if (v) |vv| {
                    const p = report.violationPath(vv);
                    @memcpy(first_failure_path[0..p.len], p);
                    first_failure_path_len = p.len;
                }
                // #607. The only point at which the crashed state still exists: this
                // iteration's own `defer` frees it and the next world restores the
                // directory. Everything the bundle says about the three states is read
                // here, into arena-owned bytes; `phaseReport` adds what is only final after
                // the loop. Failing to measure loses the bundle, never the verdict.
                first_failure_ev = evidence.measure(arena, initial, final, crashed, l0_plan, .{
                    .configured = check_argv != null,
                    .failed = l2_failed,
                    .output_path = checker_out,
                }) catch null;
                if (args.recovery != null) {
                    first_failure_snap = crashed;
                    crashed_kept = true;
                }
            }
            if (l2_failed and first_checker == null) {
                const v = l0 orelse l1;
                first_checker = .{ .k = k, .term = term, .landed = landed, .violation = v };
                first_checker_l0 = l0 != null;
                first_checker_l1 = l1 != null;
                if (v) |vv| {
                    const p = report.violationPath(vv);
                    @memcpy(first_checker_path[0..p.len], p);
                    first_checker_path_len = p.len;
                }
                first_checker_ev = evidence.measure(arena, initial, final, crashed, l0_plan, .{
                    .configured = check_argv != null,
                    .failed = l2_failed,
                    .output_path = checker_out,
                }) catch null;
                // Kept only when this world was not already kept as the earliest: one snapshot,
                // one owner, and the recovery runs once for a world that is both exhibits.
                if (args.recovery != null and !crashed_kept) {
                    first_checker_snap = crashed;
                    crashed_kept = true;
                }
            }
        }
        // Here, after every refusal this world can raise: kept earlier, a world refused for a
        // FIFO or a still-running writer would leave a state the run never judged.
        if (args.leave_crash_state and only_k != null and k == only_k.?) {
            leave_snap = crashed;
            crashed_kept = true;
        }
    }

    if (report.l1_configured) {
        report.l1_note = std.fmt.allocPrint(
            arena,
            "marker observed in {d} of {d} crash worlds; the post-success invariant was enforced there",
            .{ marker_worlds, n },
        ) catch "marker configured";
    }
    if (check_argv != null) {
        report.checker_note = std.fmt.allocPrint(
            arena,
            "{s}; ran in {d} world(s)",
            .{ report.checker_note, checks_run },
        ) catch report.checker_note;
        report.checker_worlds = checks_run;
    }

    run.firsts.first_failure = first_failure;
    run.firsts.first_failure_l0 = first_failure_l0;
    run.firsts.first_failure_l1 = first_failure_l1;
    run.firsts.first_failure_l2 = first_failure_l2;
    run.firsts.first_failure_path_len = first_failure_path_len;
    run.firsts.first_checker = first_checker;
    run.firsts.first_checker_l0 = first_checker_l0;
    run.firsts.first_checker_l1 = first_checker_l1;
    run.firsts.first_checker_path_len = first_checker_path_len;
    run.firsts.first_failure_ev = first_failure_ev;
    run.firsts.first_checker_ev = first_checker_ev;
    run.firsts.marker_worlds = marker_worlds;

    // The recovery phase (#606, ADR 0072), after every world including the baseline: the
    // verdict is decided and nothing the recovery does can reach a world. `recovery.run` cannot
    // end the process — a recovery that fails, hangs past the budget or never starts is an
    // `unknown` result beside the FAIL, never a refusal in its place.
    if (args.recovery) |rcmd| if (first_failure) |ff| if (first_failure_snap) |fsnap| rec: {
        const declared: recovery.Declared = .{
            .command = commandArgv(arena, .{ .str = rcmd }) catch break :rec,
            .check = commandArgv(arena, .{ .str = args.recovery_check.? }) catch break :rec,
        };
        const claim: ?recovery.Exhibit = if (first_checker) |fc|
            .{ .k = fc.k, .crashed = first_checker_snap orelse fsnap }
        else
            null;
        const outcome = recovery.run(.{
            .gpa = gpa,
            .arena = arena,
            .state_abs = state_abs,
            .work = args.work,
            .cwd = args.cwd,
            .budget_ms = if (args.world_timeout_s) |ws| @as(u64, ws) * 1000 else null,
            .stop_when_orphaned = args.stop_when_orphaned,
            .startup_ppid = startup_ppid,
        }, declared, final, .{ .k = ff.k, .crashed = fsnap }, claim);
        if (outcome.earliest) |l| report.recovery_earliest = .{ .result = l.result, .ms = l.ms, .command_exit = l.command_exit };
        if (outcome.checker) |l| report.recovery_checker_earliest = .{ .result = l.result, .ms = l.ms, .command_exit = l.command_exit };
        report.recovery_note = recovery.note(arena, outcome, report.violations);
    };

    // Not before the recovery: it rebuilds crash states of its own in this directory and runs
    // a command over them, and the directory left would be what the recovery made.
    // Not through `refuse.restoreFailure`: a FAIL must not become an UNKNOWN over this.
    if (leave_snap) |snap| leave: {
        if (args.stop_when_orphaned and posix.getppid() != startup_ppid) {
            report.crash_state_note = "not left: the process that launched this replay is gone";
            break :leave;
        }
        engine.restore(snap, state_abs) catch |e| {
            report.crash_state_note = std.fmt.allocPrint(arena, "not left: rewriting the state directory to the crash state failed ({s}); it may hold part of each", .{@errorName(e)}) catch "not left: rewriting the state directory to the crash state failed";
            break :leave;
        };
        report.crash_state_left = true;
        report.crash_state_note = "left in the state directory: the kill's state, before the checker ran, whatever the verdict";
    }
}

fn phaseReport(run: *Run) void {
    const mode = run.parsed.mode;
    const case_arg = run.parsed.case_arg;
    const args = run.parsed.args;
    const only_k = run.define.only_k;
    const shim = run.define.shim;
    const state_abs = run.define.state_abs;
    const state_alt = run.define.state_alt;
    const alt_differs = run.define.alt_differs;
    const arena = run.arena;
    const trace = run.rec.trace;
    const n = run.n;
    const first_failure = run.firsts.first_failure;
    const first_failure_l0 = run.firsts.first_failure_l0;
    const first_failure_l1 = run.firsts.first_failure_l1;
    const first_failure_l2 = run.firsts.first_failure_l2;
    const first_failure_path = &run.firsts.first_failure_path;
    const first_failure_path_len = run.firsts.first_failure_path_len;
    const first_checker = run.firsts.first_checker;
    const first_checker_l0 = run.firsts.first_checker_l0;
    const first_checker_l1 = run.firsts.first_checker_l1;
    const first_checker_path = &run.firsts.first_checker_path;
    const first_checker_path_len = run.firsts.first_checker_path_len;

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
        const what = report.violationObserved(f.violation);
        const path_shown = if (first_failure_path_len > 0)
            first_failure_path[0..first_failure_path_len]
        else
            "(named by the checker, not by path)";
        var repro_buf: [contract.max_path]u8 = undefined;
        const repro_trace = std.fmt.bufPrint(&repro_buf, "{s}/trace-repro.bin", .{args.work}) catch
            setupError(.define_invalid, "path too long");
        const saved_case: ?[]const u8 = if (only_k == null) blk: {
            // The stored state is the resolved spelling: a case must mean the same
            // state directory from any cwd, or the replay silently sets up elsewhere.
            var case_args = args;
            case_args.state = state_abs;
            break :blk case.writeCase(arena, args.work, case_args, f.k, n, trace, if (f.violation) |v| @tagName(v) else "checker");
        } else null;
        const case_shown = saved_case orelse (if (mode == .replay) case_arg.? else "(not saved)");
        const replay_cmd = if (saved_case) |sc|
            report.replayLine(arena, sc, args)
        else if (mode == .replay)
            "(this run is a replay; the case reproduced)"
        else
            "-";
        report.case_note = case_shown;
        report.replay_note = replay_cmd;
        const saved_evidence: ?[]const u8 = if (saved_case) |sc| ev_blk: {
            const d = run.firsts.first_failure_ev orelse break :ev_blk null;
            const op_line = evidence.joinArgv(arena, run.rec.op_argv) catch break :ev_blk null;
            break :ev_blk evidence.save(arena, sc, op_line, state_abs, n, .{
                .exhibit = .earliest,
                .crash_point = f.k,
                .boundary = .{
                    .after_op = after,
                    .after_path = after_path,
                    .before_op = before,
                    .before_path = before_path,
                },
                .invariant = invariant,
                .subject = path_shown,
                .observed = what,
                .replay = replay_cmd,
                .case_path = case_shown,
                .draft = d,
                .recovery = if (report.recovery_earliest) |r| r.result else null,
            });
        } else null;
        report.evidence_note = saved_evidence orelse "-";
        // shares the earliest's case file — no duplicate is written. Different
        // world: its case is written strictly AFTER the earliest's, so in a
        // fresh work directory 000001 always belongs to the overall earliest;
        // and when the earliest's case could not be written at all, the checker
        // case is not written either, keeping that ownership an invariant even
        // under write failure. The second write sits inside the same
        // explore-only condition as the first: a replay does not mint (ADR 0009).
        const checker_detail: ?report.CheckerEarliest = if (first_checker) |fc| blk: {
            const caddr = trace.logicalAddress(fc.k);
            const cinvariant = if (first_checker_l0)
                "built-in atomicity, and the checker"
            else if (first_checker_l1)
                "the post-success invariant, and the checker"
            else
                "the checker (L2)";
            const same_world = fc.k == f.k;
            const csaved: ?[]const u8 = if (same_world)
                saved_case
            else if (only_k == null and saved_case != null) blk2: {
                var case_args = args;
                case_args.state = state_abs;
                break :blk2 case.writeCase(arena, args.work, case_args, fc.k, n, trace, if (fc.violation) |v| @tagName(v) else "checker");
            } else null;
            const ccase = if (same_world) case_shown else (csaved orelse "(not saved)");
            const creplay = if (same_world)
                replay_cmd
            else if (csaved) |cc|
                report.replayLine(arena, cc, args)
            else
                "-";
            const cevidence: []const u8 = if (same_world)
                (saved_evidence orelse "-")
            else if (csaved) |cc| cev_blk: {
                const d = run.firsts.first_checker_ev orelse break :cev_blk "-";
                const op_line = evidence.joinArgv(arena, run.rec.op_argv) catch break :cev_blk "-";
                break :cev_blk evidence.save(arena, cc, op_line, state_abs, n, .{
                    .exhibit = .checker,
                    .crash_point = fc.k,
                    .boundary = .{
                        .after_op = if (caddr.after) |a| a.class.name() else "(start)",
                        .after_path = if (caddr.after) |a| a.path else "",
                        .before_op = if (caddr.before) |b| b.class.name() else "(end)",
                        .before_path = if (caddr.before) |b| b.path else "",
                    },
                    .invariant = cinvariant,
                    .subject = if (first_checker_path_len > 0)
                        first_checker_path[0..first_checker_path_len]
                    else
                        "(named by the checker, not by path)",
                    .observed = report.violationObserved(fc.violation),
                    .replay = creplay,
                    .case_path = ccase,
                    .draft = d,
                    .recovery = if (report.recovery_checker_earliest) |r| r.result else null,
                }) orelse "-";
            } else "-";
            break :blk .{
                .e = .{
                    .k = fc.k,
                    .after = if (caddr.after) |a| a.class.name() else "(start)",
                    .after_path = if (caddr.after) |a| a.path else "",
                    .before = if (caddr.before) |b| b.class.name() else "(end)",
                    .before_path = if (caddr.before) |b| b.path else "",
                    .subject = if (first_checker_path_len > 0)
                        first_checker_path[0..first_checker_path_len]
                    else
                        "(named by the checker, not by path)",
                    .observed = report.violationObserved(fc.violation),
                    .invariant = cinvariant,
                },
                .case = ccase,
                .replay = creplay,
                .evidence = cevidence,
            };
        } else null;
        say("{s}", .{report.paint("FAIL")});
        say(
            \\  {d} of {d} explored worlds violated an invariant
            \\
            \\invariant   {s}
            \\earliest    crash point {d} of {d}
            \\            after  {s}({s})
            \\            before {s}({s})
            \\path        {s}
            \\observed    {s}
            \\
        , .{
            report.violations,             report.explored,
            invariant,                     f.k,
            n,
            // The three target-chosen operands go to the text defanged; the
            // JSON block below reads the raw variables (#26).
                                        after,
            textShown(arena, after_path),  before,
            textShown(arena, before_path), textShown(arena, path_shown),
            what,
        });
        if (checker_detail) |cd| {
            if (cd.e.k != f.k) say(
                \\checker red crash point {d} of {d} ({s})
                \\            case     {s}
                \\            replay   {s}
                \\            evidence {s}
                \\
            , .{ cd.e.k, n, cd.e.invariant, cd.case, cd.replay, report.evidenceCommand(arena, cd.evidence) });
        }
        report.sayAccount(arena, .fail, n);
        // **`SIDEEYE_KILL_GROUP` is deliberately not set by this line** (v15) — the line unsets
        // it (#711). A world gets it because the engine put the target in its own process group
        // first; a shell an operator types this into has done no such thing, and the kill would
        // take that shell down with the target. Measured twice: an earlier draft group-killed
        // unconditionally and the acceptance suite's own shell died at the leg that runs this
        // line (SIGKILL, exit 137); and #711's first version pinned the variable empty, which
        // the shim reads as set (it looks at presence, not value), with the same result. So the
        // line unsets it, which also keeps one left in the reader's shell from arming it.
        //
        // What that costs is honest and small: the line dies in front of the same
        // operation, in the process that reaches it. Where that process is an awaited
        // child, the rest of the tree keeps running afterwards, so the line reproduces the
        // crash point rather than the whole world. Replacing the `unset` with the variable
        // by hand reproduces the world exactly — from a shell you are willing to lose.
        say("\n", .{});
        if (args.observe == .supervised)
            say("reproduce   {s}  (the crash point is the engine's, from outside the operation; there is no shim to preload)\n", .{if (saved_case != null) replay_cmd else "this run again, with --observe supervised"})
        else
            say("reproduce   {s}\n", .{report.reproduceLine(arena, .{
                .cwd = report.command_cwd,
                .state = state_abs,
                .state_alt = if (alt_differs) state_alt else null,
                .trace = repro_trace,
                .preload_var = preload_var,
                .shim = shim,
                .kill_at = f.k,
                .observe = args.observe.name(),
                .argv = run.rec.op_argv,
            }) catch "(the line could not be built: out of memory)"});
        if (args.json) |jp| report.writeJsonReport(arena, jp, "FAIL", @backingInt(contract.ExitCode.fail), .{
            .k = f.k,
            .after = after,
            .after_path = after_path,
            .before = before,
            .before_path = before_path,
            .subject = path_shown,
            .observed = what,
            .invariant = invariant,
        }, checker_detail, null, null, null, null);
        report.emitSeal();
        std.process.exit(@backingInt(contract.ExitCode.fail));
    }

    refuse.requireCompleteness(arena, args.has_oracle, args.allow_unverified);
    // #683, ADR 0091: after every world — a FAIL has already exited above — and not for a
    // replay, whose one world answers a different question.
    if (only_k == null) refuse.requireSomethingCouldFail(arena, run.rec.judgeable, run.check_argv != null, args.marker != null, run.firsts.marker_worlds);

    say("{s}  {d}/{d} explored worlds satisfied the built-in atomicity invariant under a process kill{s}{s}\n", .{ report.paint("PASS"), report.explored, report.explored, report.singleCrashPointClause(n), report.untouchedClause(arena, run.rec.judgeable.touched, run.rec.judgeable.judged) });
    report.sayAccount(arena, .pass, n);
    if (args.json) |jp| report.writeJsonReport(arena, jp, "PASS", @backingInt(contract.ExitCode.pass), null, null, null, null, null, null);
    report.emitSeal();
    std.process.exit(@backingInt(contract.ExitCode.pass));
}

fn splitArgs(arena: std.mem.Allocator, cmd: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, cmd, ' ');
    while (it.next()) |tok| try list.append(arena, tok);
    return list.items;
}

fn commandArgv(arena: std.mem.Allocator, cmd: config.Command) ![]const []const u8 {
    return switch (cmd) {
        .str => |s| splitArgs(arena, s),
        .argv => |a| a,
    };
}

/// Two seconds is what epoch-second stamping needs to move, and it is the interval one
/// unpinned `borg create` split at — it is **not** a measured sufficiency threshold for
/// nondeterminism in general, and the help text says so rather than implying a target
/// that survives it is repeatable.
const repeat_gap_ms: u64 = 2000;

const repeat_diff_byte_budget: usize = 1024;

const repeat_diff_slots: usize = 64;

const Repeat = struct {
    gap_ms: u64,
    count: engine.DiffCount,
    diffs: []const engine.Difference,
    spans: []const ?[]const u8,
    /// The same lines in their `.shape` form — where, how long, what kind, no byte of either
    /// run — for `--json` (#717). Made here beside `spans` because the second snapshot is
    /// freed when `observeAgain` returns, so no later step could make them.
    shapes: []const ?[]const u8,
};

const repeat_span_paths: usize = 8;

/// Order is the cohort harness's, not the obvious one: **sleep, then restore**. The
/// protocol defines the gap between the two runs' starts, and restoring before the wait
/// would leave the freshly rebuilt pre-state exposed for the whole gap to anything the
/// first run left running.
///
/// Run B is gated explicitly here rather than by reusing the recording path wholesale:
/// that path writes the report globals as it goes, so a second pass through it would
/// overwrite what the first run reported.
/// What run B does NOT get, listed because an earlier draft of this comment claimed it
/// got everything (review): `unresolvable_path`, `unsupported_syscall_observed`,
/// `sequence_numbering_broken`, the oracle comparison, and stdout quiescence. The first
/// three walk the trace's records — a second copy of that analysis is the wholesale
/// reuse this function exists to avoid — and the oracle comparison is disclosed in the
/// report's `scope` line. Stdout quiescence guards the capture the marker is read from,
/// which run B has no claim resting on.
fn observeAgain(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    initial: engine.Snapshot,
    first: engine.Snapshot,
    state_abs: []const u8,
    state_alt: []const u8,
    gate: engine.GateExempt,
    op_argv: []const []const u8,
    shim: []const u8,
    oracle_path: ?[]const u8,
    work: []const u8,
    expect_status: u8,
    first_started_ms: u64,
    /// The define's declared directory, carried through so the second observation runs
    /// where the first did — a repeatability comparison between two different working
    /// directories would be measuring the directories.
    cwd: ?[]const u8,
    /// The same observation path the first run used. A repeatability comparison between
    /// two runs counted by different observers would be measuring the observers.
    observe: contract.ObserveMode,
    /// Whether run A's writing children were admitted (v15). This function cannot decide
    /// it: `oracle-2.txt` is written and not parsed, and reading it is a promise this
    /// flag deliberately does not make on its own.
    children_admitted: bool,
) Repeat {
    // The floor is enforced against the clock, not assumed from one sleep, while `--help`,
    // docs/cli.md and the CHANGELOG all promise "at least two seconds". Without this
    // loop the command could print `two runs 47 ms apart left equal state` and
    // contradict its own help (review, P2). The clock is monotonic, so each pass
    // shortens the remainder and the loop terminates.
    while (true) {
        const elapsed = posix.monotonicMs() -| first_started_ms;
        if (elapsed >= repeat_gap_ms) break;
        posix.sleepForMs(repeat_gap_ms - elapsed);
    }

    // `oracle_path` answers "did the caller name an oracle?", which is what the refusals
    // below are about — telling someone who passed `--oracle` to pass `--oracle` is the
    // defect review found once this function started nulling it. `attached` answers "does
    // run B carry it?". The two were separated because they used to have different
    // answers: run B carried no oracle in syscalls mode, for the reason the recording run
    // did not either — strace saw a trapped write twice. Nulling the parameter at the call
    // site collapsed them and made the refusal message and the report's own disclosure lie
    // in opposite directions (review, P1).
    //
    // **They have the same answer now** (ADR 0054): the recording run carries an oracle in
    // that mode, so the reason for the asymmetry is gone, and leaving it would have made
    // `--twice` measure run A under strace and run B without it — two runs compared for
    // equal state after being observed differently. The distinction is kept rather than
    // collapsed back into one variable, because the refusals below still ask the other
    // question and that is what made them lie the first time.
    const attached: ?[]const u8 = oracle_path;
    engine.restore(initial, state_abs) catch |e| refuse.restoreFailure(e, "could not restore the state directory before the second observed run", state_abs);

    var trace_buf: [contract.max_path]u8 = undefined;
    const trace_b = std.fmt.bufPrint(&trace_buf, "{s}/trace-record-2.bin", .{work}) catch setupError(.define_invalid, "path too long");
    var stdout_buf: [contract.max_path]u8 = undefined;
    const stdout_b = std.fmt.bufPrint(&stdout_buf, "{s}/stdout-record-2.txt", .{work}) catch setupError(.define_invalid, "path too long");
    var oracle_buf: [contract.max_path]u8 = undefined;
    const oracle_out_b = std.fmt.bufPrint(&oracle_buf, "{s}/oracle-2.txt", .{work}) catch setupError(.define_invalid, "path too long");
    removeFile(trace_b);
    removeFile(stdout_b);
    removeFile(oracle_out_b);

    const started = posix.monotonicMs();
    var cg_b = containment.spawn(false);
    const cg_b_ptr: ?*posix.CgroupSpawn = if (cg_b) |*c| c else null;
    const term = runOperationObserved(gpa, arena, op_argv, state_abs, state_alt, shim, attached, oracle_out_b, trace_b, stdout_b, cwd, observe, cg_b_ptr);

    // split. `recording_run_failed` is the existing member for "the run this account
    // rests on did not complete" — no new closed-set name, which after the v1.0 tag
    // would be a breaking change (`docs/contract-freeze.md`, surface 2).
    switch (term) {
        // 126 first, for the reason the recording run's own check gives: the stub's code.
        .exited => |code| if (code == 126 and code != expect_status)
            unknown(.recording_run_failed, "the second observed run exited 126: either the engine's fork stub could not arrange the child before exec (a line on the engine's stderr names the call and the errno) or the operation itself exited 126 — indistinguishable from here, and not a statement about repeatability", .environment)
        else if (code != expect_status)
            unknown(.recording_run_failed, std.fmt.allocPrint(arena, "the second observed run exited {d} where {d} was expected, although the first run of the same command succeeded: the two runs cannot be compared", .{ code, expect_status }) catch "the second observed run exited with an unexpected status", .second_run_diverged),
        else => unknown(.recording_run_failed, "the second observed run did not exit normally, although the first run of the same command succeeded", .second_run_diverged),
    }

    var trace = refuse.readTraceOrRefuse(trace_b, trace_cap, gate, "could not read the second observed run's trace");
    defer trace.deinit();
    // #324's pairing: every site that reads with a cap must answer for it. Forgetting
    // this at one site is the defect that issue exists to fix, and its own doc warns
    // that a third read site would have no acceptance leg holding it — **this is that
    // third site**, and it has no leg: the `-Dtest-trace-cap` engines cap the shared
    // constant, so run A's read fires first and run B is never reached. What holds it
    // is this comment and review. Without the answer the cap would return an empty
    // `TraceInfo` and every gate below would go vacuously green.
    refuse.answerForOversizedTrace(trace, "the second observed run", trace_cap);
    // Recorded here, above every refusal below, for the same reason run A's evidence is
    // recorded above its own: each of them writes a report, and the account has to name
    // the run it is about. An earlier revision of this said "before the refusals" while
    // sitting after four of them (`no_shim_marker`, `trace_truncated`,
    // `child_touched_state_dir`, `contract_version_mismatch`) — harmless at the time,
    // because preflight refused `--json` (until #717) and the UNKNOWN text block carried no `processes`
    // line, and wrong for whoever built on the claim next. Caught by review. **The second
    // half of that excuse is gone as of #123**: the UNKNOWN block prints the account,
    // and each of those four refusals goes through it, so this assignment sitting above them
    // is what makes it name run B. (A refusal that exits through `setupError` still prints
    // one line and no account — `restoreFailure` above and the snapshot OOM paths below take
    // that route — so the claim is about this block, not about every exit from here.)
    const b_detach_refused = trace.detached != null and !containment.holds(cg_b_ptr, &trace, false);
    boundary.boundary_ev.second_run = boundary.secondRunLabel(trace, b_detach_refused);
    // The property says "the two runs OBSERVED in this invocation". A run whose shim
    // never initialised was not observed, and reporting it as one half of a comparison
    // would make that word false — the flag exists for targets that take a different
    // path the second time, so a second run that loads nothing is not hypothetical.
    if (!trace.saw_shim_ready)
        unknown(.no_shim_marker, boundary.noShimDetailSecondRun(arena), .check_shim);
    if (trace.truncated)
        unknown(.trace_truncated, "the second observed run's trace ends mid-record; how many operations there were is unknown", .retry_then_report);
    // Inherited from run A, for the reason the parameter's doc gives, and refusing a
    // child run A was admitted for would make `--twice` unusable on exactly the targets
    // this version exists to judge.
    if (trace.foreign_kill_point and !children_admitted)
        unknown(.child_touched_state_dir, boundary.foreignTouchDetail(arena, trace.first_foreign, "during the second observed run", if (attached != null) oracle_out_b else null, "a process other than the subject performed a state-directory operation during the second observed run"), .class_wall);

    // cost nothing — a second process could not reach this point. It can now: run B
    // inherits run A's admission, so two of its processes taking one number is a state
    // nothing else in this function would notice. `--twice` compares post-state bytes and
    // says so; it does not compare accounts.
    if (trace.kill_records != trace.kill_point_count)
        unknown(.sequence_numbering_broken, if (trace.foreign_kill_point)
            "two processes took the same number in the second observed run: its kill-point records and its highest sequence number disagree, which is what happens when their operations run at the same time"
        else
            "the second observed run's kill-point records and its highest sequence number disagree; the numbering has gaps or duplicates", .class_wall);
    if (trace.version_mismatch)
        unknown(.contract_version_mismatch, "the shim and engine disagree on the trace contract version in the second observed run", .rebuild_pair);
    // run exactly as run A applies them. Read from `hard_boundary` for the same reason
    // run A does: the first boundary in a trace can be a tolerable fork written before
    // the record that must refuse.
    if (trace.hard_boundary) |b| switch (b) {
        .exec => unknown(.child_process_detected, "the second observed run replaced its own image, so the two runs did not execute the same program to completion and cannot be compared", .class_wall),
        else => {},
    };
    if (b_detach_refused)
        containment.refuseDetach(arena, cg_b_ptr, " during the second observed run");
    if (trace.second_writer_thread) |op|
        unknown(.multiple_threads_detected, boundary.threadDetail(arena, trace.first_writer_thread, op, trace.first_writer_thread_detached, " in the second observed run"), boundary.threadsStep(observe, boundary.oneThreadSwitchSet(&envValue)));
    // A soft boundary in run B and not run A is still a boundary: the shim only sees
    // what loads it, and "was not seen" must not read as "did nothing" here either.
    //
    // What this does NOT do is compare run B's oracle capture against its shim account.
    // `oracle-2.txt` is written — run B executes under the same wrapper run A did, so
    // that the two runs differ in nothing the caller controls — and it is not parsed.
    // witness. The report's `scope` line says so, and widening it is a separate promise.
    if (trace.needsOracle() and oracle_path == null)
        unknown(.boundary_without_oracle, if (builtin.os.tag == .macos) "the second observed run crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; on macOS no witness this engine reads can (#702)" else "the second observed run crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; pass --oracle (Linux)", .account_boundary_or_unwrap);

    // The third trace read's share of the same rule. Run A's copy is above (and it is
    // what a refusing record in the recording run trips), but run B is a second
    // execution: `--twice` exists because the two can differ, and the difference is
    // exactly what an unplaceable operation here would be about.
    //
    // **Below `boundary_ev.second_run`, not above it.** A first draft sat between the
    // comment that documents that assignment and the assignment itself, so a run B that
    // both crossed a boundary and held a refusing record printed an account with no
    // run-B boundary evidence — the same defect the world loop's own comment records
    // review catching once. Caught in review again, here.
    if (trace.unresolved_refusing != null)
        unknown(.unresolvable_path, boundary.unresolvedDetail(arena, trace.unresolved_refusing, " in the second observed run", "an operation was observed in the second observed run whose path could not be determined, so it cannot be placed among the crash points"), .class_wall);

    var second = refuse.snapshotOrRefuse(gpa, state_abs, "could not snapshot the state after the second observed run");
    defer second.deinit();
    // Quiescence, the same way the exploration path asks it: two samples back to back.
    // A tree still being written would otherwise be compared at a moment nobody chose,
    // and the difference reported as the target's nondeterminism.
    var again = refuse.snapshotOrRefuse(gpa, state_abs, "could not re-sample the state after the second observed run");
    defer again.deinit();
    var quiesce_buf: [1]engine.Difference = undefined;
    if (!engine.diffSnapshots(second, again, &quiesce_buf).equal())
        unknown(.state_not_quiescent, "two samples of the state directory taken back to back after the second observed run disagreed: something was still writing, so the comparison would describe a moment nobody chose", .quiesce);

    if (!snapshotsEqual(initial, second) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed during the second observed run while zero mutating operations were recorded: operations were missed", boundary.unrecordedWriteNext(builtin.os.tag == .linux));

    // The watch on run B (v17, #559), after every refusal run B already had, as run A's is. The
    // oracle's half is not asked: run B's capture is written and not parsed, which the report's
    // `scope` line already says.
    if (cg_b_ptr) |cg| containment.afterRun(arena, cg, &trace, " in the second observed run", true);

    const diffs = arena.alloc(engine.Difference, repeat_diff_slots) catch setupError(.environment, "out of memory");
    // A declared scratch path is left out of the comparison (ADR 0043), the way the
    // exploration leaves it out of the judgement: README points at --twice as the
    // byte-repeatability wall's measurement, and a wall the exploration no longer hits on
    // a declared path must not still be reported by the preflight. Left out before it is
    // counted, so the total the report prints is the total of what was compared.
    const count = engine.diffSnapshotsExcept(first, second, diffs, report.scratch_declared);
    // `Difference.rel` borrows from whichever snapshot holds the entry, and `second` is
    // freed by this function's own `defer`. An `only_in_second` row therefore points
    // into a released arena the moment this returns — read-after-free in
    // `preflightReport`, measured as a segfault in review. The other three kinds borrow
    // from `first`, which outlives this call, which is why every run measured before
    // review survived: all of them were `content_differs`.
    //
    // Copying into `arena` — the caller's, which outlives both snapshots — is the fix
    // rather than lifting `second` out, because the borrow rule belongs to the value:
    // a `Difference` that escapes its snapshots has to own its bytes.
    //
    // #688: the byte line for a path whose content differs is built here too, while both
    // snapshots are alive — `byteSpan` copies what it quotes into `arena`.
    const spans = arena.alloc(?[]const u8, count.stored) catch setupError(.environment, "out of memory");
    @memset(spans, null);
    const shapes = arena.alloc(?[]const u8, count.stored) catch setupError(.environment, "out of memory");
    @memset(shapes, null);
    var with_bytes: usize = 0;
    for (diffs[0..count.stored], spans, shapes) |*d, *sp, *sh| {
        if (d.how == .content_differs and with_bytes < repeat_span_paths) {
            if (first.find(d.rel)) |fe| if (second.find(d.rel)) |se| {
                sp.* = report.byteSpan(arena, "first run", fe.content, "second run", se.content, .bytes);
                sh.* = report.byteSpan(arena, "first run", fe.content, "second run", se.content, .shape);
                with_bytes += 1;
            };
        }
        d.rel = arena.dupe(u8, d.rel) catch setupError(.environment, "out of memory");
    }
    return .{
        .gap_ms = started -| first_started_ms,
        .count = count,
        .diffs = diffs[0..count.stored],
        .spans = spans,
        .shapes = shapes,
    };
}

const PreflightHint = union(enum) {
    flags: report.NextDefine,
    config: struct { path: []const u8, dir: []const u8 },
};

const PreflightDeclared = struct { check: bool, marker: bool, recovery: bool };

fn preflightReport(arena: std.mem.Allocator, n: u32, hint: PreflightHint, next_run: report.NextRun, declared: PreflightDeclared, repeat: ?Repeat, ran_controls: ?report.PreflightControls) noreturn {
    const oracle_path = next_run.oracle;
    // Where the comparison and the rewrite of `--twice` happen, named the way the define named
    // it: byte for byte the old wording from the flags, which acceptance pins.
    const state_named: []const u8 = if (hint == .config) "[world] state" else "--state";
    // "not accepted", not "accepted but split". `docs/contract-freeze.md` says a
    // preflight that ACCEPTS the recording exits 0; under `--twice` the caller asked a
    // second question, so acceptance means the recording held *and* the two runs
    // agreed. Calling a split "accepted" and returning a non-zero code would contradict
    // the frozen sentence; narrowing what acceptance means under this flag does not.
    const split = if (repeat) |r| !r.count.equal() else false;
    const pf_doc: ?report.PreflightDoc = if (refuse.json_path != null) blk: {
        const rep: ?report.PreflightRepeat = if (repeat) |r| rb: {
            const out = arena.alloc(report.PreflightDiff, r.diffs.len) catch setupError(.environment, "out of memory");
            for (r.diffs, r.shapes, out) |d, sh, *o| o.* = .{ .path = d.rel, .how = @tagName(d.how), .shape = sh };
            break :rb .{ .gap_ms = r.gap_ms, .total = r.count.total, .diffs = out };
        } else null;
        break :blk .{ .runs_differ = split, .operations = n, .marker_declared = declared.marker, .repeat = rep, .controls = ran_controls };
    } else null;
    if (split) {
        say("PREFLIGHT  not accepted — the two observed runs left different state\n\n", .{});
    } else {
        say("PREFLIGHT  recording accepted — {d} state-changing operation(s) observed\n\n", .{n});
    }
    if (repeat) |r| {
        if (split) {
            // Paths are target-chosen: a file name may hold a newline, and unescaped it
            // would let a target forge report lines. Same neutralisation the l0 note
            // uses, and the budget is bytes rather than a path count because one `rel`
            // can approach max_path on its own.
            var used: usize = 0;
            var shown: usize = 0;
            for (r.diffs, 0..) |d, i| {
                const rel = textShown(arena, d.rel);
                // The FIRST path is always named, whatever it costs: `--help`,
                // docs/cli.md and the headline all say the differing paths are named, and a
                // single path over the budget — `contract.max_path` is 4096 — would
                // otherwise print nothing but "… and 1 more" (review, P3). Truncating
                // it instead would risk cutting a UTF-8 sequence mid-character, so the
                // budget yields here rather than the promise.
                if (i > 0 and used + rel.len > repeat_diff_byte_budget) break;
                used += rel.len;
                shown += 1;
                const how = switch (d.how) {
                    .only_in_first => "only after the first run",
                    .only_in_second => "only after the second run",
                    .kind_differs => "kind differs",
                    .content_differs => "content differs",
                };
                say("difference   {s} ({s})\n", .{ rel, how });
                if (r.spans[i]) |sp| say("             bytes {s}\n", .{sp});
            }
            if (r.count.total > shown)
                say("             … and {d} more\n", .{r.count.total - shown});
            say("\n", .{});
        }
    }
    report.sayCwd(arena, "cwd          {s}{s}\n");
    say(
        \\atomicity    {s}
        \\oracle       {s}
        \\processes    {s}
        \\
    , .{ report.l0_note, report.oracle_note, boundary.boundaryAccount() });
    // #704: what a toml declared, and what preflight did with each. The marker was found in the
    // recording run's output — a marker that never appears is refused in `phaseRecording`, so
    // reaching here means it was seen; `l1_note` says "crash worlds not explored yet", which reads
    // as though an exploration followed. The checker was not refused by `unstartable` — which leaves some
    // files unjudged (an execute-only one; the script an interpreter is handed), so the line says
    // what was not refused rather than that it will start — had something in the state to
    // corrupt, and was not run. A recovery is never started
    if (declared.marker) say("marker       observed in the recording run's output; preflight explores no crash world\n", .{});
    if (ran_controls) |c| {
        say("checker      run on the state the recording left, and after each [controls] command broke it\n", .{});
        say("controls     baseline {s} ({s}{s}{s})\n", .{ c.baseline.word, c.baseline.checker_exit, if (c.baseline.red.len > 0) "; red " else "", std.mem.join(arena, ", ", c.baseline.red) catch "" });
        for (c.controls) |k| {
            const ctl_exit = k.control_exit orelse {
                say("             {s}: {s} (not run)\n", .{ k.leg, k.word });
                continue;
            };
            const red = std.mem.join(arena, ", ", k.red) catch "";
            say("             {s}: {s} (control {s}{s}{s}{s}{s})\n", .{
                k.leg,
                k.word,
                ctl_exit,
                if (k.checker_exit != null) ", checker " else "",
                k.checker_exit orelse "",
                if (red.len > 0) "; red " else "",
                red,
            });
        }
    } else if (declared.check) say(
        \\checker      declared, not run: not refused as a command that cannot be
        \\             started, and the state holds something to corrupt
        \\
    , .{});
    if (declared.recovery) report.sayRecovery("recovery     {s}\n");
    // The parenthesis is #682's: with no check and no marker, explore can refuse an operation
    // that only creates files `nothing_could_fail`, which one recording cannot rule out. A toml
    // that declares either has said what makes a world fail, and the sentence would not apply.
    const nc = report.preflight_not_checked;
    comptime std.debug.assert(nc.len == 5);
    if (declared.check or declared.marker) say(
        \\
        \\not checked  {s}, {s}, {s},
        \\             {s}, {s} — only a real
        \\             exploration runs these
        \\
        \\
    , .{ nc[0], nc[1], nc[2], nc[3], nc[4] }) else say(
        \\
        \\not checked  {s}, {s}, {s},
        \\             {s}, {s} (with no
        \\             check or marker, an operation that only creates files is refused
        \\             nothing_could_fail) — only a real exploration runs these
        \\
        \\
    , .{ nc[0], nc[1], nc[2], nc[3], nc[4] });
    if (repeat) |r| {
        // Reported whether the runs agreed or split, and worded as an observation
        // rather than a property: two samples cannot establish that a target is
        // deterministic, and `not checked` above still carries determinism for exactly
        // that reason. The interval is the measured one — a gap printed from the sleep
        // that was requested would be the measurement describing its own intent.
        const verdict = if (split) "differed" else "left equal state";
        say(
            \\repeatability  two runs {d} ms apart {s} under {s}
            \\scope          file bytes, entry kinds and symlink targets only; modes,
            \\               ownership, timestamps, and anything outside {s} are
            \\               not compared, and two runs are not all runs
            \\
        , .{ r.gap_ms, verdict, state_named, state_named });
        // Stated only when run B actually carried the oracle, because otherwise it
        // describes a file that does not exist. Run B carries it in every mode since
        if (oracle_path != null)
            say(
                \\               the second run's oracle capture is written but not
                \\               compared; only the first run's account was checked
                \\
            , .{});
        if (report.scratch_declared.len > 0)
            say("scratch        declared scratch, not compared: {s}\n", .{report.scratchNote(arena)});
        say("\n", .{});
    }
    if (oracle_path == null) {
        if (builtin.os.tag == .macos) say(
            \\note         no oracle checked the shim's account against a second witness;
            \\             explore's PASS will require --oracle-fs-usage (after sudo -v)
            \\             or --allow-unverified
            \\
            \\
        , .{}) else say(
            \\note         no oracle checked the shim's account against a second witness;
            \\             explore's PASS will require --oracle <strace> (Linux) or
            \\             --allow-unverified (macOS)
            \\
            \\
        , .{});
    }
    if (split) {
        say(
            \\next         pin or relocate what differs, then re-run this command;
            \\             explore would reach the same divergence in its baseline
            \\             world, after a full define had been written
            \\
        , .{});
        if (refuse.json_path) |jp| report.writePreflightJson(arena, jp, pf_doc.?);
        report.emitSeal();
        std.process.exit(@backingInt(contract.ExitCode.fail));
    }
    // Under `--observe supervised` the next command names the mode, not a shim: there is no shim
    // in that mode, and an explore without the flag counts through one the target cannot load.
    // A shim the run found itself is left out rather than named: found beside the binary's real
    // path, it is one installed version's, and a later upgrade deletes it.
    var run = next_run;
    run.observe = boundary.observe_mode;
    if (run.oracle == null and builtin.os.tag != .macos) run.oracle_found = refuse.findStraceForHint(arena);
    const tail = report.nextRunWords(arena, run) catch setupError(.environment, "out of memory");
    switch (hint) {
        // Every word through `shellWord`, not double quotes: a `$` or a backquote in a path or a
        // command would be expanded by the shell the line is pasted into, and explore would read
        // another define than the one preflight accepted.
        .flags => |f| say(
            \\next         sideeye explore{s} \
            \\               --check <your-invariant.sh>{s}
            \\
        , .{ report.nextDefineWords(arena, f) catch setupError(.environment, "out of memory"), tail }),
        .config => |c| {
            // spelling it out. Named as the toml's resolved directory joined with its own name:
            // that directory is what `phaseDefine` resolved every relative path against, and what
            // explore will resolve them against when the line is pasted — so a toml that is a
            // symlink keeps its own side rather than its target's, whose relative paths would mean
            // a different define (review of #704). Single-quoted for /bin/sh, as the replay line
            // quotes a recovery. A toml read from a pipe, a process substitution or `/dev/stdin`
            // (which `phaseDefine` reads on purpose) cannot be read again by the pasted command, and
            // a name `textShown` would rewrite cannot be pasted as printed; both get the line that
            // says to save the define, rather than one that would read nothing or another file.
            const Sys = struct {
                fn under(p: []const u8) bool {
                    for ([_][]const u8{ "/dev", "/proc" }) |sys| {
                        if (std.mem.eql(u8, p, sys) or (std.mem.startsWith(u8, p, sys) and p[sys.len] == '/')) return true;
                    }
                    return false;
                }
            };
            const sys_why = "which a second command may not read the same way";
            var file_buf: [contract.max_path]u8 = undefined;
            var hop_buf: [contract.max_path]u8 = undefined;
            var why: []const u8 = "which is not a regular file a second command can read again";
            var then: []const u8 = "save it to a file, then";
            const pastable: ?[]const u8 = blk: {
                if (Sys.under(c.dir)) {
                    why = sys_why;
                    break :blk null;
                }
                const named = std.fs.path.join(arena, &.{ c.dir, std.fs.path.basename(c.path) }) catch break :blk null;
                // Each link the name goes through is read, not resolved: Linux's realpath follows
                // `/proc/self/fd/0` to the file stdin was redirected from, so a toml that is a link
                // to `/dev/stdin` would resolve to a regular file the pasted command never reads
                // (the change's second review). Bounded as the kernel bounds a chain.
                var cur: []const u8 = named;
                var hops: usize = 0;
                while (hops < 40) : (hops += 1) {
                    const cz = arena.dupeSentinel(u8, cur, 0) catch break :blk null;
                    const len = posix.readlink(cz.ptr, &hop_buf, hop_buf.len);
                    if (len < 0) break;
                    const target = hop_buf[0..@intCast(len)];
                    cur = std.fs.path.resolvePosix(arena, &.{ std.fs.path.dirname(cur) orelse "/", target }) catch break :blk null;
                    if (Sys.under(cur)) {
                        why = sys_why;
                        break :blk null;
                    }
                }
                const nz = arena.dupeSentinel(u8, named, 0) catch break :blk null;
                const real = std.mem.span(posix.realpath(nz.ptr, &file_buf) orelse break :blk null);
                const rz = arena.dupeSentinel(u8, real, 0) catch break :blk null;
                if ((posix.kindOfPathNoFollow(rz.ptr) catch .other) != .file) break :blk null;
                if (!std.mem.eql(u8, textShown(arena, named), named)) {
                    why = "whose name cannot be printed here as a line to paste";
                    then = "copy it to a file with a plain name, then";
                    break :blk null;
                }
                break :blk named;
            };
            if (pastable) |p| say(
                \\next         sideeye explore --config {s}{s}
                \\
            , .{ shellSingleQuote(arena, p), tail }) else say(
                \\next         the define was read from {s},
                \\             {s}: {s}
                \\             sideeye explore --config <that file>{s}
                \\
            , .{ textShown(arena, c.path), why, then, tail });
        },
    }
    if (refuse.json_path) |jp| report.writePreflightJson(arena, jp, pf_doc.?);
    report.emitSeal();
    std.process.exit(@backingInt(contract.ExitCode.pass));
}

const demo_toy = @embedFile("demo_toy");
const demo_check_sh = @embedFile("check_sh");

const shim_basename = mcp.shim_basename;

test "demo shim candidates: tarball sibling first, zig-out lib layout second" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const c = try mcp.shimCandidates(arena, "/opt/sideeye/bin/sideeye");
    const first = std.fmt.allocPrint(arena, "/opt/sideeye/bin/{s}", .{shim_basename}) catch unreachable;
    const second = std.fmt.allocPrint(arena, "/opt/sideeye/bin/../lib/{s}", .{shim_basename}) catch unreachable;
    try std.testing.expectEqualStrings(first, c[0]);
    try std.testing.expectEqualStrings(second, c[1]);
}

/// Absence stays loud, both looked-at paths named; argv[0] is never consulted
/// (a PATH name or a wrapper must not decide which library gets injected).
fn findShim(arena: std.mem.Allocator) []const u8 {
    const self = mcp.canonicalSelf() orelse setupError(.environment, "could not resolve the canonical path of this binary to look beside it for the shim; pass --shim <path>");
    const self_owned = arena.dupe(u8, self) catch setupError(.environment, "out of memory");
    switch (mcp.findShimBeside(arena, self_owned)) {
        .found => |f| return f,
        // A refused candidate is fatal here rather than absent: falling through to the
        // message below would say nothing was found at a place where something was, and
        // the operator would go looking for a missing file instead of a planted one.
        .refused => |r| setupError(.environment, mcp.refusalMessage(arena, r)),
        .absent => |cands| setupError(.environment, mcp.absentMessage(arena, cands, std.fmt.allocPrint(arena, "Pass --shim <path to {s}>", .{shim_basename}) catch "Pass --shim <path>")),
        .unsearchable => setupError(.environment, "out of memory while looking for the shim"),
    }
    unreachable;
}

/// The deepest state root `--oracle-fs-usage` accepts, in bytes of the caller's path.
/// fs_usage prints a pathname with the data volume's firmlink prefix
/// (`/System/Volumes/Data`, 20 bytes — the shape `capturesPath`'s measured line has)
/// and cuts long ones from the left at a display cap measured at 144, 153 and 156 on
/// two machines; the sentinel's own name below is `/.sideeye-fsusage-close.` (24) plus
/// sixteen hex digits. 156 − 20 − 40 = 96: the bound fits the largest measured cap, and
/// has since it was set (the arithmetic was not written down then; it is now). Under a
/// smaller cap a root over 84 passes this check and is refused later, at the handshake
/// (the cut opening name never matches) or as `missing_sentinel` (the closing name a
/// byte longer than the opening one is the one cut) — never judged. Kept at the largest
/// cap by owner ruling (2026-09-09): under that cap every root up to 96 works, and the
/// smaller caps refuse rather than misjudge. With the pid gone the name grew from about
/// thirty bytes to forty, so the root a smaller cap tolerates shrank by about ten. A
/// root the caller already spelled with the prefix is charged for it twice; whether a
/// root on another volume (`/Volumes/...`) is printed with a prefix at all is not
/// measured — it is charged the twenty either way, which refuses rather than misjudges.
const fsu_sentinel_max_root: usize = 156 - 20 - 40;

const SentinelPair = struct { a: []const u8, b: []const u8 };

/// Two draws, not one shared: the opening name is readable from the capture once the
/// handshake has passed (the capture is the engine's own file, `0600`, and the target
/// runs as the same user), so a name derived from it would hand the closing name over
/// too. The closing name is born after the target has exited and is never in a place
/// the target or its children can read, which is what makes a forged capture line for
/// it impossible rather than merely hard. Null when the kernel refuses entropy or a
fn fsUsageSentinels(state_abs: []const u8, a_buf: *[contract.max_path]u8, b_buf: *[contract.max_path]u8) ?SentinelPair {
    var hex_a: [16]u8 = undefined;
    var hex_b: [16]u8 = undefined;
    const ha = posix.randomHex(&hex_a) orelse return null;
    const hb = posix.randomHex(&hex_b) orelse return null;
    const a = std.fmt.bufPrint(a_buf, "{s}/.sideeye-fsusage-open.{s}", .{ state_abs, ha }) catch return null;
    const b = std.fmt.bufPrint(b_buf, "{s}/.sideeye-fsusage-close.{s}", .{ state_abs, hb }) catch return null;
    return .{ .a = a, .b = b };
}

fn isHex16(s: []const u8) bool {
    if (s.len != 16) return false;
    for (s) |c| if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'))) return false;
    return true;
}

test "fs_usage sentinels: the shape, two names per run that differ from each other, and a next run that differs from both (#549)" {
    var a1: [contract.max_path]u8 = undefined;
    var b1: [contract.max_path]u8 = undefined;
    var a2: [contract.max_path]u8 = undefined;
    var b2: [contract.max_path]u8 = undefined;
    const p1 = fsUsageSentinels("/tmp/st", &a1, &b1) orelse return error.TestUnexpectedResult;
    const p2 = fsUsageSentinels("/tmp/st", &a2, &b2) orelse return error.TestUnexpectedResult;
    const open_prefix = "/tmp/st/.sideeye-fsusage-open.";
    const close_prefix = "/tmp/st/.sideeye-fsusage-close.";
    try std.testing.expect(std.mem.startsWith(u8, p1.a, open_prefix));
    try std.testing.expect(std.mem.startsWith(u8, p1.b, close_prefix));
    const ha = p1.a[open_prefix.len..];
    const hb = p1.b[close_prefix.len..];
    try std.testing.expect(isHex16(ha));
    try std.testing.expect(isHex16(hb));
    // Independence inside one run: the opening name is readable from the capture, so
    // the closing name must not be derivable from it. One draw shared by both would
    // pass every other assertion here.
    try std.testing.expect(!std.mem.eql(u8, ha, hb));
    try std.testing.expect(!std.mem.eql(u8, p1.a, p2.a));
    try std.testing.expect(!std.mem.eql(u8, p1.b, p2.b));
    // The printed-length arithmetic the bound above rests on: the opening name is
    // root + 39, the closing one root + 40 (a byte longer — the one a cap cuts first).
    try std.testing.expectEqual("/tmp/st".len + 39, p1.a.len);
    try std.testing.expectEqual("/tmp/st".len + 40, p1.b.len);
}

test "every flag preflight takes is on its next line, or is preflight's own" {
    const preflight_only = comptime blk: {
        var own: []const []const u8 = &.{};
        for (std.enums.values(std.meta.FieldEnum(cli.Args))) |field| {
            if (cli.carried(field).next == .left_off) own = own ++ .{cli.flagOf(field)};
        }
        break :blk own;
    };
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const line = try std.mem.concat(a, u8, &.{
        " --config t",
        try report.nextDefineWords(a, .{ .state = "s", .setup = "u", .cwd = "c", .operation = "o", .expect_status = 3, .apparatus = &.{"note:x"}, .scratch = &.{"k"} }),
        try report.nextRunWords(a, .{ .work = "w", .state_under = "b", .observe = .syscalls, .shim = "l", .oracle = "t" }),
        " ",
    });
    var buf: [64][]const u8 = undefined;
    const flags = cli.synopsisFlags("preflight", &buf);
    var carried_count: usize = 0;
    for (flags) |flag| {
        var own = false;
        for (preflight_only) |o| own = own or std.mem.eql(u8, o, flag);
        const on_line = std.mem.indexOf(u8, line, try std.fmt.allocPrint(a, " {s} ", .{flag})) != null;
        if (on_line) carried_count += 1;
        std.testing.expect(own != on_line) catch |e| {
            std.debug.print("preflight's flag {s}: on the next line {}, preflight's own {}\n", .{ flag, on_line, own });
            return e;
        };
    }
    try std.testing.expect(carried_count > 0);
}

fn shellSingleQuote(arena: std.mem.Allocator, s: []const u8) []const u8 {
    return report.shellQuote(arena, s) catch setupError(.environment, "out of memory");
}

test "shellSingleQuote neutralizes metacharacters and embedded quotes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("'plain'", shellSingleQuote(arena, "plain"));
    try std.testing.expectEqualStrings("'a'\\''b; $(x) `y`'", shellSingleQuote(arena, "a'b; $(x) `y`"));
}

/// Self-exec rather than an in-process call for the same reason the MCP adapter
/// self-execs (ADR 0010): every verdict path in this file ends in `std.process.exit`.
fn runDemo(arena: std.mem.Allocator, rest: []const []const u8) noreturn {
    var shim_flag: ?[]const u8 = null;
    var i: usize = 0;
    while (i < rest.len) {
        if (std.mem.eql(u8, rest[i], "--shim")) {
            if (i + 1 >= rest.len) setupError(.define_invalid, "--shim is missing its value");
            shim_flag = rest[i + 1];
            i += 2;
            continue;
        }
        cli.refuseDemoArgument(arena, rest[i]);
    }

    const self = mcp.canonicalSelf() orelse setupError(.environment, "could not resolve the canonical path of this binary; refusing to guess what to self-exec");
    // canonicalSelf answers from a static buffer; copy before anything else reuses it.
    const self_owned = arena.dupe(u8, self) catch setupError(.environment, "out of memory");

    const shim = shim_flag orelse findShim(arena);

    // Scratch space: $TMPDIR when usable. explore splits command strings on spaces
    // (ADR 0007), so a TMPDIR containing one would shear "<tool> init" apart — /tmp then.
    const troot: []const u8 = blk: {
        if (posix.getenv("TMPDIR")) |t| {
            const s = std.mem.span(t);
            if (s.len > 0 and std.mem.indexOfScalar(u8, s, ' ') == null)
                break :blk if (s[s.len - 1] == '/') s[0 .. s.len - 1] else s;
        }
        break :blk "/tmp";
    };
    var templ_buf: [contract.max_path]u8 = undefined;
    const templ = std.mem.printSentinel(&templ_buf, "{s}/sideeye-demo-XXXXXX", .{troot}, 0) catch setupError(.environment, "TMPDIR is unreasonably long");
    const tmp_raw = posix.mkdtemp(templ.ptr) orelse setupError(.environment, "could not create the demo's scratch directory");
    const tmp = arena.dupe(u8, std.mem.span(tmp_raw)) catch setupError(.environment, "out of memory");

    const tool = std.fmt.allocPrint(arena, "{s}/demo-tool", .{tmp}) catch setupError(.environment, "out of memory");
    const check_path = std.fmt.allocPrint(arena, "{s}/check.sh", .{tmp}) catch setupError(.environment, "out of memory");
    if (!files.writeNewExecutable(tool, demo_toy))
        setupError(.environment, "could not write the demo's planted-bug tool into the scratch directory");
    // lost to a change in how those layers pass environments around. Single-quoted —
    // the path contains whatever $TMPDIR contained, and an unquoted value would hand
    // its metacharacters to the shell (R1 finding). The embedded script's shebang
    if (!writeWholeFile(check_path, &.{ "TOY=", shellSingleQuote(arena, tool), "\nexport TOY\n", demo_check_sh }))
        setupError(.environment, "could not write the demo's checker into the scratch directory");

    say(
        \\demo  wrote the planted-bug tool into {s}
        \\demo  the tool deletes its key before renaming the replacement in; a crash
        \\demo  between those two operations leaves no key at all. exploring:
        \\
        \\
    , .{tmp});

    const state_dir = std.fmt.allocPrint(arena, "{s}/state", .{tmp}) catch setupError(.environment, "out of memory");
    const work_dir = std.fmt.allocPrint(arena, "{s}/work", .{tmp}) catch setupError(.environment, "out of memory");
    const setup_cmd = std.fmt.allocPrint(arena, "{s} init", .{tool}) catch setupError(.environment, "out of memory");
    const op_cmd = std.fmt.allocPrint(arena, "{s} rotate", .{tool}) catch setupError(.environment, "out of memory");
    const check_cmd = std.fmt.allocPrint(arena, "/bin/sh {s}", .{check_path}) catch setupError(.environment, "out of memory");

    const exec_argv = [_][]const u8{
        self_owned,    "explore",
        "--state",     state_dir,
        "--setup",     setup_cmd,
        "--operation", op_cmd,
        "--check",     check_cmd,
        "--work",      work_dir,
        "--shim",      shim,
    };
    // `--shim` only when the demo was given one: one it found itself would ride into the
    // report's replay line as one installed version's path.
    const passed = if (shim_flag != null) exec_argv.len else exec_argv.len - 2;
    var argv_z: [exec_argv.len + 1]?[*:0]const u8 = undefined;
    for (exec_argv[0..passed], 0..) |a, j| argv_z[j] = (arena.dupeSentinel(u8, a, 0) catch setupError(.environment, "out of memory")).ptr;
    argv_z[passed] = null;
    _ = posix.execvp(argv_z[0].?, &argv_z);
    setupError(.environment, "could not self-exec the exploration");
}

/// as unchecked. `preload:` reads `/etc/ld.so.preload` and never `LD_PRELOAD`: the engine
/// replaces that variable with its own shim for every child, so a library there is a
/// device that does not arrive, and the refusal says so when that is where it was found.
///
/// `apparatus_declared` is set at the end of the after-setup pass, and only when every entry
/// passed: a SETUP ERROR raised from a refusal this returns carries no apparatus field, so a
/// report that carries one is a run whose declared devices were present when the engine
/// looked (the schema page's promise). `cwd` is the define's, for a relative PYTHONPATH entry — the operation
/// resolves it from there, so the check must too.
fn checkApparatus(arena: std.mem.Allocator, entries: []const []const u8, cwd: ?[]const u8, phase: enum { before_setup, after_setup }) ?workdir.Refusal {
    var preload_file: ?[]const u8 = null;
    for (entries) |e| {
        const parsed = switch (config.parseApparatusEntry(e)) {
            .ok => |p| p,
            .bad => |msg| return .{ .reason = .define_invalid, .text = msg },
        };
        // Only env: before the setup: the setup may make what the other kinds look for (a
        // pythonpath: file, a preload line), and a define relying on that would be refused for
        // a device it was about to make.
        if ((parsed == .env) != (phase == .before_setup)) continue;
        switch (parsed) {
            .env => |v| {
                const got = envValue(v.name) orelse return workdir.Refusal.print(arena, .environment, "apparatus {s}: the environment the operation inherits has no {s} (under sideeye mcp, a variable of the server's reaches it only when SIDEEYE_MCP_CHILD_ENV names it)", .{ e, v.name });
                if (v.value) |want| if (!std.mem.eql(u8, got, want))
                    return workdir.Refusal.print(arena, .environment, "apparatus {s}: {s} is set, but to a different value ({s})", .{ e, v.name, textShown(arena, got) });
            },
            .preload => |lib| {
                if (builtin.os.tag == .macos)
                    return workdir.Refusal.print(arena, .platform_unsupported, "apparatus {s}: cannot be satisfied on macOS — there is no global preload file, and the engine owns DYLD_INSERT_LIBRARIES for every child; on Linux the entry names a line of /etc/ld.so.preload, and " ++ contract.macos_table, .{e});
                if (preload_file == null) preload_file = capture.readFileAllocCapped(arena, "/etc/ld.so.preload", 64 * 1024, .{ .require_regular = true }) orelse blk: {
                    // Absent is the common case and means "no preload"; present but unreadable
                    // is a different fact and must not be reported as "no line names it".
                    if (posix.access("/etc/ld.so.preload", posix.F_OK) == 0)
                        return workdir.Refusal.print(arena, .environment, "apparatus {s}: /etc/ld.so.preload exists but could not be read (not a regular file, unreadable, or over 64 KiB)", .{e});
                    break :blk "";
                };
                if (!preloadNamed(preload_file.?, lib)) {
                    if (envValue("LD_PRELOAD")) |lp| if (namesLib(lp, lib))
                        return workdir.Refusal.print(arena, .environment, "apparatus {s}: {s} is in LD_PRELOAD, which the engine replaces with its own shim for every child, so it does not reach the operation; a global preload goes in /etc/ld.so.preload", .{ e, lib });
                    return workdir.Refusal.print(arena, .environment, "apparatus {s}: no line of /etc/ld.so.preload names {s}", .{ e, lib });
                }
            },
            .pythonpath => |file| {
                const pp = envValue("PYTHONPATH") orelse return workdir.Refusal.print(arena, .environment, "apparatus {s}: PYTHONPATH is not set in the environment the operation inherits (under sideeye mcp, a variable of the server's reaches it only when SIDEEYE_MCP_CHILD_ENV names it)", .{e});
                if (!pythonpathHas(arena, pp, file, cwd))
                    return workdir.Refusal.print(arena, .environment, "apparatus {s}: no entry of PYTHONPATH ({s}) has {s} directly under it", .{ e, textShown(arena, pp), file });
            },
            .note => {},
        }
    }
    if (phase == .after_setup) report.apparatus_declared = entries;
    return null;
}

fn envValue(name: []const u8) ?[]const u8 {
    var zbuf: [256]u8 = undefined;
    const z = std.mem.printSentinel(&zbuf, "{s}", .{name}, 0) catch return null;
    const v = posix.getenv(z.ptr) orelse return null;
    return std.mem.span(v);
}

fn namesLib(list: []const u8, lib: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, list, " \t:");
    while (it.next()) |entry| if (std.mem.startsWith(u8, std.fs.path.basename(entry), lib)) return true;
    return false;
}

fn preloadNamed(contents: []const u8, lib: []const u8) bool {
    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (namesLib(line, lib)) return true;
    }
    return false;
}

fn pythonpathHas(arena: std.mem.Allocator, pythonpath: []const u8, file: []const u8, cwd: ?[]const u8) bool {
    var it = std.mem.tokenizeScalar(u8, pythonpath, ':');
    while (it.next()) |dir| {
        const base = if (cwd) |c| resolvePathAgainst(arena, c, dir) else dir;
        var zbuf: [contract.max_path]u8 = undefined;
        const z = std.mem.printSentinel(&zbuf, "{s}/{s}", .{ base, file }, 0) catch continue;
        if (posix.access(z.ptr, posix.F_OK) == 0) return true;
    }
    return false;
}

test "preloadNamed: /etc/ld.so.preload lines, by basename prefix, comments and blanks ignored" {
    try std.testing.expect(preloadNamed("/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1\n", "libfaketime"));
    try std.testing.expect(preloadNamed("# comment\n\n  /opt/pin/no-accel-copy.so  \n", "no-accel-copy"));
    try std.testing.expect(preloadNamed("/a/libone.so /b/libtwo.so\n", "libtwo"));
    try std.testing.expect(!preloadNamed("", "libfaketime"));
    try std.testing.expect(!preloadNamed("# /usr/lib/libfaketime.so.1\n", "libfaketime"));
    try std.testing.expect(!preloadNamed("/usr/lib/libfake.so\n", "libfaketime"));
    try std.testing.expect(!preloadNamed("/usr/lib/libfaketime/other.so\n", "libfaketime"));
}

test "namesLib: an LD_PRELOAD value or a preload line, colon- or space-separated, by basename prefix" {
    try std.testing.expect(namesLib("/x/libsideeye_shim.so:/y/libfaketime.so.1", "libfaketime"));
    try std.testing.expect(namesLib("/y/libfaketime.so.1 /x/other.so", "libfaketime"));
    try std.testing.expect(!namesLib("/x/libsideeye_shim.so", "libfaketime"));
    try std.testing.expect(!namesLib("", "libfaketime"));
}

fn resolvePathAgainst(arena: std.mem.Allocator, dir: []const u8, path: []const u8) []const u8 {
    if (path.len == 0 or path[0] == '/') return path;
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, path }) catch setupError(.environment, "out of memory");
}

fn resolveCommandAgainst(arena: std.mem.Allocator, dir: []const u8, cmd: []const u8) []const u8 {
    var start: usize = 0;
    while (start < cmd.len and cmd[start] == ' ') start += 1;
    const rest = cmd[start..];
    const sp = std.mem.indexOfScalar(u8, rest, ' ');
    const head = if (sp) |p| rest[0..p] else rest;
    const tail = if (sp) |p| rest[p..] else "";
    if (head.len == 0 or head[0] == '/' or std.mem.indexOfScalar(u8, head, '/') == null) return cmd;
    return std.fmt.allocPrint(arena, "{s}/{s}{s}", .{ dir, head, tail }) catch setupError(.environment, "out of memory");
}

fn resolveCommand(arena: std.mem.Allocator, dir: []const u8, cmd: config.Command) config.Command {
    switch (cmd) {
        .str => |s| {
            const resolved = resolveCommandAgainst(arena, dir, s);
            // Not left as a string when `dir` holds a space: a string command is split on spaces
            // when it runs, and that would split the directory joined to its head.
            if (resolved.ptr == s.ptr or std.mem.indexOfScalar(u8, dir, ' ') == null) return .{ .str = resolved };
            return resolveCommand(arena, dir, .{ .argv = splitArgs(arena, s) catch setupError(.environment, "out of memory") });
        },
        .argv => |a| {
            if (a.len == 0) return .{ .argv = a };
            const head = a[0];
            if (head.len == 0 or head[0] == '/' or head[0] == ' ' or std.mem.indexOfScalar(u8, head, '/') == null)
                return .{ .argv = a };
            const out = arena.alloc([]const u8, a.len) catch setupError(.environment, "out of memory");
            out[0] = std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, head }) catch setupError(.environment, "out of memory");
            for (a[1..], 1..) |e, idx| out[idx] = e;
            return .{ .argv = out };
        },
    }
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
    try std.testing.expectEqualStrings("/cfg/./check.sh", resolveCommandAgainst(a, "/cfg", " ./check.sh"));
    const rel = resolveCommand(a, "/cfg", .{ .argv = &.{ "./check.sh", "--strict", "a b" } });
    try std.testing.expectEqualStrings("/cfg/./check.sh", rel.argv[0]);
    try std.testing.expectEqualStrings("--strict", rel.argv[1]);
    try std.testing.expectEqualStrings("a b", rel.argv[2]);
    const in_space_dir = resolveCommand(a, "/My Project", .{ .str = "./w rotate --n 3" });
    try std.testing.expectEqual(@as(usize, 4), in_space_dir.argv.len);
    try std.testing.expectEqualStrings("/My Project/./w", in_space_dir.argv[0]);
    try std.testing.expectEqualStrings("3", in_space_dir.argv[3]);
    try std.testing.expectEqualStrings("mytool x", resolveCommand(a, "/My Project", .{ .str = "mytool x" }).str);
    try std.testing.expectEqualStrings("/usr/bin/tool x", resolveCommand(a, "/My Project", .{ .str = "/usr/bin/tool x" }).str);
    try std.testing.expectEqualStrings("/MyProject/./w rotate", resolveCommand(a, "/MyProject", .{ .str = "./w rotate" }).str);
    const bare = resolveCommand(a, "/cfg", .{ .argv = &.{ "mytool", "x/y" } });
    try std.testing.expectEqualStrings("mytool", bare.argv[0]);
    try std.testing.expectEqualStrings("x/y", bare.argv[1]);
    const abs = resolveCommand(a, "/cfg", .{ .argv = &.{"/usr/bin/tool"} });
    try std.testing.expectEqualStrings("/usr/bin/tool", abs.argv[0]);
    const spaced = resolveCommand(a, "/cfg", .{ .argv = &.{" ./check.sh"} });
    try std.testing.expectEqualStrings(" ./check.sh", spaced.argv[0]);
}

fn snapshotsEqual(a: engine.Snapshot, b: engine.Snapshot) bool {
    var one: [1]engine.Difference = undefined;
    return engine.diffSnapshots(a, b, &one).equal();
}

test "the shipped engine options carry the shipped values (#365)" {
    // A loud edit is caught elsewhere: at 64 bytes every acceptance leg that drives the
    // SHIPPED binary refuses on a trace that size, and most of the suite does drive it —
    // not all, since four apparatus binaries are driven by their own names. A quiet one
    // is caught nowhere: 128 MiB passes acceptance (no toy trace comes near it), passes
    // the sha step, and ships an engine whose ceiling disagrees with engine.max_trace_bytes.
    // That quiet mutation is what these tests exist for, and it is the half that was
    // measured; the loud half is read off spike/acceptance.sh rather than run.
    try std.testing.expectEqual(@as(usize, 0), engine_build_options.trace_cap_override);
    try std.testing.expectEqual(@as(usize, 0), engine_build_options.trace_cap_override_world);
    // The whole-trace ceiling's override (#377) is the same promise one level up: a
    // quiet edit here ships an engine whose ceiling disagrees with
    // `engine.max_trace_bytes_total`, and no acceptance leg would notice because no toy
    // run comes near either value.
    try std.testing.expectEqual(@as(usize, 0), engine_build_options.trace_budget_override);
    try std.testing.expect(!engine_build_options.ancestor_probe);
    // A shipped engine that never contained a run would be the comparison engine under the
    // shipped name (#559): every containment leg would compare it with itself and stay green.
    try std.testing.expect(!engine_build_options.no_cgroup);
    // A shipped engine that delayed every supervised answer (#217) would be the test engine
    // under the shipped name: slower, and the one measurement of WAIT_KILLABLE_RECV would
    // compare it with itself.
    try std.testing.expectEqual(@as(u32, 0), engine_build_options.supervise_reply_delay_ms);
    // Not true in the shipped engine: an environment variable would then make its supervised
    // hand-over fail.
    try std.testing.expect(!engine_build_options.supervise_handover_fault);
}

test "the shipped trace caps fall back to the engine's constant (#365)" {
    // The raw options are the promise; these two are the wiring that carries it to the
    // read sites, and they fail differently. A non-zero override breaks the test above.
    // A rewrite of the conditional at the top of this file breaks only this one.
    // Asserting the derived values alone would be a step removed from the promise: with
    // `trace_cap_override` set to engine.max_trace_bytes itself, the override IS present
    // and the comparisons below still hold.
    try std.testing.expectEqual(engine.max_trace_bytes, trace_cap);
    try std.testing.expectEqual(engine.max_trace_bytes, trace_cap_world);
    try std.testing.expectEqual(engine.max_trace_bytes_total, trace_budget_limit);
}

test "no eighth engine build option arrives unchecked (#365)" {
    // The ratchet. Asserting five values says nothing about a SIXTH option arriving, and
    // the promise is universal: a `-Dtest-…` added later with no assertion above would
    // leave it false while CI stayed green. Pinning the count makes the next option fail
    // here until someone writes its line. Same instrument as the RestoreError arity pin
    const decls = @typeInfo(engine_build_options).@"struct".decl_names;
    try std.testing.expectEqual(@as(usize, 7), decls.len);
}
