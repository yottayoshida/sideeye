//! The argv surface: what `sideeye explore|replay|preflight …` accepts, and what the parser
//! says about the run while it reads.
//!
//! `src/cli.zig` owns `Args` — the flags and define-surface values a run starts from — the
//! usage text and `version`, and `parse`: the mode dispatch, the flag loop and the mode
//! refusals that used to open `main()`. Their statements moved as they were; what is new is
//! the function around them and its result, `Parsed`. Two things `parse` does are not
//! "argv → Args", and they are named here because #352's tests pin their order: as each flag
//! is read it tells the report what may already be said (`report.noteOracle`,
//! `report.checker_note`, `report.l1_note`, `report.expected_status_val`,
//! `report.settleDeclared`) and where the JSON goes (`refuse.json_path`, removing a previous
//! report at that path), and it records which witness was named
//! (`boundary.boundary_ev.witness`). Every refusal in here goes through
//! `refuse.setupError`; the one exit of its own is the unknown-mode banner — `usage()` then
//! exit 3 — which prints no verdict line. Not here: the `mcp`, `help`, `version` and `demo`
//! branches that run before any parsing (they exit or self-exec and are `main()`'s), and
//! `splitArgs`, `commandArgv` and the `resolve*` family, which the freeze audit's rung 1 reads
//! out of `src/main.zig` and which no code here calls — and, for the same reason, the digit
//! grammar of `--expect-status`, which is `config.parseExpectStatus` because the toml key
//! `expected_status` shares it and rung 1 reads surface 1 out of `config.zig`.
//!
//! Third seam of #572 (ADR 0062), second half. Moved byte for byte on 2026-09-13 with `pub`
//! where another file reads them, with three declared exceptions: `Mode` was a local `enum`
//! inside `main()` and is a top-level declaration here; `stop_when_orphaned` was a module
//! variable the loop wrote and the world loop read, and is a field of `Args` (the world loop
//! reads `args.stop_when_orphaned`); `parse` ends in a `return` the loop did not have. The
//! two tests that hold `version` and the help text moved with them; `build.zig` names this
//! file as a test root.
const std = @import("std");
const contract = @import("contract");
const config = @import("config.zig");
const posix = @import("posix.zig");
const boundary = @import("boundary.zig");
const report = @import("report.zig");
const refuse = @import("refuse.zig");
const files = @import("files.zig");
const setupError = refuse.setupError;
const say = report.say;
const removeFile = files.removeFile;

/// Must match `.version` in `build.zig.zon`. They are two hand-written strings for the
/// same number, and they had already drifted: the package said 0.1.0 while `--help` said
/// 0.1.0-dev. A test below holds them together.
pub const version = "1.3.0";

/// `--apparatus` is repeatable and the flag parser owns no allocator; a define with more
/// devices than this belongs in a toml. The entries live here and `Args.apparatus` is a
/// slice of them, the same slice type the toml's key yields.
const max_apparatus = 32;
var apparatus_flag_buf: [max_apparatus][]const u8 = undefined;

/// `--scratch` is repeatable for the same reason, with the same ceiling (ADR 0043).
const max_scratch = 32;
var scratch_flag_buf: [max_scratch][]const u8 = undefined;

pub const Args = struct {
    state: ?[]const u8 = null,
    // The three commands carry either spelling (config.Command): the flags always
    // bind the string form; the argv form arrives only through a sideeye.toml or a
    // case_version 3 case file (ADR 0019).
    setup: ?config.Command = null,
    operation: ?config.Command = null,
    shim: ?[]const u8 = null,
    work: []const u8 = "/tmp/sideeye-work",
    oracle: ?[]const u8 = null,
    /// macOS: use `fs_usage` as the completeness oracle for the recording run.
    ///
    /// A flag with no value, unlike `--oracle`: there is one `fs_usage` and it is at a
    /// fixed path, so a path parameter would be a knob whose only correct setting is
    /// the default. It is not a spelling of `--oracle` either — that one names a
    /// program to wrap the target with, and this one starts an observer beside it
    /// (`src/fsusage.zig`), so the two cannot be reduced to one parameter without the
    /// value silently meaning two different things.
    oracle_fs_usage: bool = false,
    /// Whether this run named a completeness oracle at all — the one question six
    /// sites used to ask by spelling the disjunction themselves.
    ///
    /// Derived once, immediately after the parser has ruled the two flags mutually
    /// exclusive, so no reader has to re-establish that they cannot both be set. The
    /// review that found `requireCompleteness` still reading `args.oracle != null` —
    /// a comparison that ran, agreed, and left the PASS gate demanding
    /// `--allow-unverified` — found a defect this shape produces: a second backend
    /// arrives and every site that asked the old question keeps answering it.
    has_oracle: bool = false,
    check: ?config.Command = null,
    allow_unverified: bool = false,
    /// Which observation path counts the operations (contract v14). The default is
    /// the only one that existed through v13, so an invocation that never names this
    /// flag behaves exactly as it did.
    observe: contract.ObserveMode = .wrappers,
    fresh_state: bool = false,
    /// Preflight only (#199): observe the operation a second time from the restored
    /// pre-state and compare the two post-snapshots. Opt-in, because it doubles the
    /// wall time and adds the inter-run gap — a caller who did not ask for a second
    /// observation keeps the single-run answer this command has always given.
    ///
    /// What it can conclude is bounded by the Snapshot model, not by the word
    /// "deterministic": `Entry` carries `rel`, `kind` and `content`, so modes,
    /// ownership, timestamps, inode identity, a symlink's target and everything
    /// outside the declared root are all outside the comparison. `engine.restore`
    /// rebuilds the pre-state at fixed modes, so run B does not even start from a
    /// byte-identical directory — it starts from the same *snapshot*. The help text
    /// states both limits rather than leaving them to be discovered.
    twice: bool = false,
    /// The per-world wall-clock budget in seconds (#263). Null — the default — means
    /// no budget anywhere: the flag is opt-in, and turning it on is the operator's
    /// explicit choice, never a shipped default that could move a verdict.
    world_timeout_s: ?u32 = null,
    /// Replay only (#266): the directory the case's state must resolve strictly
    /// inside. The MCP server passes its destruction range here; the case path being
    /// vetted says nothing about where the case's OWN define points the deletion.
    state_under: ?[]const u8 = null,
    json: ?[]const u8 = null,
    config: ?[]const u8 = null,
    marker: ?[]const u8 = null,
    /// The exit status that means the operation completed (ADR 0014). Null means
    /// "not declared", which behaves as 0 — kept apart from an explicit 0 so the
    /// preflight hint and the saved case can carry exactly what the caller said.
    expect_status: ?u8 = null,
    /// Where the define's commands run. It arrives from a toml or a saved case and has
    /// no flag: a caller at a terminal can `cd`, and the caller that cannot — the MCP
    /// server's, handed a config path and starting the engine itself — has no other way
    /// to say it. Absolute by the time anything reads it.
    cwd: ?[]const u8 = null,
    /// The define's apparatus entries, as spelled (ADR 0041): the toml key's list, or the
    /// repeated `--apparatus` flags collected in `apparatus_flag_buf`. Empty when nothing
    /// was declared, which is what every define written before the key existed says.
    apparatus: []const []const u8 = &.{},
    /// The define's scratch paths (ADR 0043), normalised: the toml key's list, the
    /// repeated `--scratch` flags collected in `scratch_flag_buf`, or a version-5 case's
    /// declaration. Empty when nothing was declared. Every path here, and everything
    /// beneath it, is judged by neither built-in invariant.
    scratch: []const []const u8 = &.{},
    /// #269, `--stop-when-orphaned`: refuse to start another world once `getppid()` stops
    /// answering what it answered at process start. A module variable of `main.zig` until
    /// #572 seam 3b; the loop below sets it and the world loop reads it, and nothing else.
    stop_when_orphaned: bool = false,
};

/// The help text, as a format string with two holes (version, contract version). A
/// constant rather than a literal inside `usage()` so a test can read it: every `--flag`
/// a `NextStep` sentence names has to exist here (#274), and a sentence that named a flag
/// this binary does not accept would be advice nobody can follow.
const usage_fmt =
    \\sideeye {s} (trace contract v{d})
    \\
    \\usage:
    \\  sideeye demo [--shim <lib>]
    \\  sideeye preflight --state <dir> --operation <cmd> [--shim <lib>] [--setup <cmd>] [--expect-status <n>] [--cwd <dir>] [--apparatus <entry>] [--scratch <path>] [--oracle <strace>] [--observe wrappers|syscalls] [--work <dir>] [--twice]
    \\  sideeye explore --state <dir> --operation <cmd> [--setup <cmd>] [--check <cmd>] [--marker <bytes>] [--expect-status <n>] [--cwd <dir>] [--apparatus <entry>] [--scratch <path>] [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye explore --config <sideeye.toml> [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye replay <case.json> [--shim <lib>] [--fresh-state] [--state-under <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls] [--work <dir>] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye mcp
    \\  sideeye help
    \\  sideeye version
    \\
    \\demo compiles a small planted-bug tool on this machine (it needs a C compiler)
    \\and explores it, printing the same FAIL report a real finding produces. The
    \\expected exit code is 1 — the planted bug found — so the demo doubles as a
    \\smoke test of this binary and its shim.
    \\
    \\preflight answers "does the recording phase accept this target?" before a
    \\define exists: it runs the operation under observation and either accepts
    \\the recording (exit 0) or refuses with the same named detector a real run
    \\would use (exit 2). With --twice it observes a second run and compares the
    \\two, adding one outcome: the runs left different state (exit 1, and no
    \\verdict — see --twice below). What only a real exploration can check — kill
    \\landing, world-side process boundaries, baseline behavior, checker
    \\falsification — is listed as not checked, never silently claimed.
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
    \\  --cwd        directory the define's commands run in (default: this process's).
    \\               The engine's own cwd does not move: --work, --json and --state
    \\               are still read against it
    \\  --apparatus  a device the operation's environment must carry, kind:value, repeatable:
    \\               env:NAME, env:NAME=VALUE, preload:LIB (a line of /etc/ld.so.preload),
    \\               pythonpath:FILE, note:TEXT. Checked after setup, before anything is
    \\               recorded; a missing one is a SETUP ERROR naming it. The report carries
    \\               the list as declared (docs/apparatus.md). The engine applies nothing
    \\  --scratch    a path under --state the built-in invariants leave alone, repeatable:
    \\               the path itself and everything beneath it, judged in no world — not
    \\               its bytes, not its presence. The report carries the declaration and
    \\               counts what it matched; the saved case carries it too (ADR 0043)
    \\  stdin        not a flag: every command sideeye runs (setup, operation, checker)
    \\               starts with its standard input at end-of-file, on the CLI and MCP
    \\               paths alike. A target that reads stdin sees EOF, never the
    \\               terminal or pipe sideeye itself was started from
    \\  --setup      command that produces the initial state (run once)
    \\  --operation  command to explore; killed before each operation that can change state
    \\  --expect-status  the exit status that means the operation completed (0..255,
    \\               default 0). Governs the recording run and the un-killed baseline
    \\               world alike; killed worlds still require the kill signal itself
    \\  --shim       path to libsideeye_shim.so; when omitted it is looked for
    \\               beside this binary (its sibling, then ../lib — the tarball
    \\               and zig-out layouts). Absence is a loud error naming both
    \\               places it looks, and so is a candidate the search will not
    \\               attribute: a symlink, or one owned by neither you, nor
    \\               root, nor the owner of this binary. A path given here is
    \\               used as named and not checked
    \\  --work       scratch directory for traces (default /tmp/sideeye-work)
    \\  --oracle     path to strace; the recording run is compared against it
    \\  --oracle-fs-usage
    \\               macOS: compare the recording run against fs_usage instead. Needs
    \\               root, so sudo must already hold credentials (`sudo -v` first, in
    \\               this terminal — the cache is per-terminal); the run refuses
    \\               rather than prompting. Narrower than strace by two measured
    \\               limits: fs_usage prints only a rename's old path, and it cuts
    \\               long pathnames from the left, so a rename it cannot match and a
    \\               state directory deep enough to be cut are both refusals rather
    \\               than agreements. Everything it cannot resolve refuses
    \\  --check      command run after each crash, in a fresh process; exit 0 = invariant holds
    \\  --marker     success marker: a byte string the operation prints on stdout when
    \\               it has committed. In worlds where it appeared before the kill,
    \\               the post-success invariant is enforced: the new state must
    \\               survive (ADR 0008)
    \\  --json       write the machine-readable report to this path
    \\  --fresh-state
    \\               (replay only) empty and recreate the case's state directory
    \\               before setup runs — for callers that cannot hand over a
    \\               pristine directory themselves. The MCP server passes it on
    \\               every replay: it lives for the whole client session, and the
    \\               second replay used to die in the leftovers of the first
    \\  --state-under
    \\               (replay only) the directory the case's state must resolve
    \\               strictly inside; anything else is refused before setup runs.
    \\               The case file names its own state directory, and this flag is
    \\               how a caller that only vetted the case's PATH bounds where the
    \\               case may point the deletion. The MCP server passes its
    \\               SIDEEYE_MCP_STATE_ROOT (default: the server root) on every
    \\               replay
    \\  --observe wrappers|syscalls
    \\               where operations are counted. Default `wrappers`: the
    \\               interposed libc entry points, with buffered stdio observed at
    \\               flush granularity (ADR 0005). `syscalls` (Linux) counts at the
    \\               kernel boundary instead, through a seccomp filter and a SIGSYS
    \\               handler in the target's own process, which is the only way to
    \\               see an operation libc issues from inside itself — an `fwrite`
    \\               past the buffer — or one that never reaches libc at all: a raw
    \\               `syscall(SYS_write, ...)`, or a runtime like Go's that issues
    \\               every file call directly. Its trap set is every operation that
    \\               can be a crash point: open, write, rename, unlink, fsync,
    \\               truncate, mkdir, rmdir, link, symlink. Two stay outside —
    \\               `copy_file_range` and `pwritev2` take six arguments, leaving the
    \\               filter no register for its re-issue marker. An oracle watches
    \\               this mode's own run, as it does every other mode's: a trapped
    \\               call reaches strace twice, once refused and once re-issued, and
    \\               the refused entry is retracted on the SIGSYS that refused it. So
    \\               the claim is `oracle_verified`, and the report's oracle line says
    \\               how the capture was read.
    \\               **Do not use it on a target that execs an image the shim cannot be
    \\               loaded into.** A filter is inherited across exec and cannot be
    \\               replaced, while exec resets the SIGSYS handler that makes it
    \\               survivable, so a statically linked helper dies at its first
    \\               state-changing call (measured: exit 0 under wrappers, killed by
    \\               SIGSYS under this). A child the shim IS loaded into is unaffected.
    \\               In this mode the shim also keeps SIGSYS deliverable, interposing
    \\               sigaction/signal/sigprocmask/pthread_sigmask so a target cannot
    \\               take the handler away; one that reaches those as raw syscalls
    \\               still dies
    \\  --allow-unverified
    \\               accept PASS with no completeness check. On macOS this is the
    \\               answer when no privilege is available: SIP leaves DTrace's
    \\               syscall provider with no probes even as root (#181), and the
    \\               one candidate measured oracle-shaped, fs_usage, requires it —
    \\               which is what --oracle-fs-usage pays for. The report says which
    \\               claim was made, and this one is weaker.
    \\  --stop-when-orphaned
    \\               stop at the next world boundary if the process that launched
    \\               this run exits (UNKNOWN, parent_exited). The MCP server passes
    \\               it on every explore and replay: agent hosts restart MCP servers
    \\               routinely, and an orphaned exploration otherwise keeps killing
    \\               processes and rewriting its state directory with nobody left to
    \\               report to. A run that hangs before a boundary is out of reach.
    \\  --world-timeout <s>
    \\               wall-clock budget per explored world, in seconds (1..86400,
    \\               off by default). A world's operation still running when the
    \\               budget expires is sent SIGKILL and refused UNKNOWN
    \\               child_timed_out, with the budget in the message. Worlds only: a
    \\               recording run, setup command or checker that hangs still hangs —
    \\               this flag is not a promise of a hang-free run. Setting it also
    \\               resets SIGCHLD to its default disposition for the whole run.
    \\               Not settable over MCP today.
    \\  --twice
    \\               (preflight only) observe the operation a SECOND time from the
    \\               restored pre-state, at least two seconds after the first start,
    \\               and compare the two post-states. Byte repeatability is a
    \\               property of two runs, so one observation structurally cannot
    \\               see it. Equal: exit 0. Different: the differing paths are named
    \\               and the command exits 1 — not a FAIL verdict, which preflight
    \\               never produces, but the negative answer to the question --twice
    \\               asked. A second run that ends abnormally refuses by name
    \\               instead, the way the first one would.
    \\               What this does NOT establish: that the target is
    \\               deterministic. The comparison covers file bytes, entry kinds
    \\               and symlink targets under --state; modes, ownership,
    \\               timestamps, inode identity, a symlink's destination and
    \\               everything outside --state are not compared, the pre-state
    \\               run B starts from is rebuilt rather than byte-identical, and
    \\               two runs are not all runs. The two-second gap is what
    \\               epoch-second stamping needs to move — not a measured
    \\               sufficiency threshold for nondeterminism in general.
    \\               It also REWRITES --state: the directory is restored from the
    \\               pre-run snapshot before the second run, so the first run's
    \\               output is gone and file modes come back as 0644/0755. A
    \\               preflight without this flag leaves the directory as the run
    \\               left it.
    \\
    \\exit codes: 0 PASS, 1 FAIL, 2 UNKNOWN, 3 SETUP ERROR
    \\            (preflight produces no verdict: it exits 0 when it accepts, 1 when
    \\             --twice found a split, 2 when a detector refused, 3 on setup)
    \\
    \\--operation must exit its declared success status when it is not being killed
    \\(--expect-status, default 0). The crash points are read off the recording run,
    \\so a target that fails partway through would be explored against a sequence it
    \\never performs; v0.1 reports UNKNOWN rather than guess.
    \\
;

pub fn usage() void {
    say(usage_fmt, .{ version, contract.contract_version });
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
/// `--world-timeout` in seconds: 1..86400, digits only (#263). Zero is refused rather
/// than read as "no budget" — an operator who typed a number meant a bound, and the
/// spelling for "no bound" is omitting the flag. The ceiling is a day: any larger value
/// is more plausibly a unit mistake than an intent, and the bound is what keeps the
/// millisecond conversion trivially inside u64.
fn parseWorldTimeout(s: []const u8) u32 {
    const msg = "--world-timeout must be a whole number of seconds, 1..86400";
    if (s.len == 0 or s.len > 5) setupError(.define_invalid, msg);
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') setupError(.define_invalid, msg);
        v = v * 10 + (ch - '0');
    }
    if (v == 0 or v > 86400) setupError(.define_invalid, msg);
    return v;
}

/// `--apparatus ENTRY`: the same grammar the toml key uses, refused with the same words.
fn appendApparatusFlag(args: *Args, v: []const u8) void {
    if (config.apparatusFault(v)) |m| setupError(.define_invalid, m);
    const n = args.apparatus.len;
    if (n == max_apparatus) setupError(.define_invalid, "--apparatus: more than 32 entries; a define this large belongs in a toml");
    apparatus_flag_buf[n] = v;
    args.apparatus = apparatus_flag_buf[0 .. n + 1];
}

/// `--scratch PATH`: the same grammar the toml key uses, refused with the same words, and
/// stored normalised the way the parser stores it (ADR 0043).
fn appendScratchFlag(args: *Args, v: []const u8) void {
    const norm = switch (config.parseScratchEntry(v)) {
        .ok => |p| p,
        .bad => |m| setupError(.define_invalid, m),
    };
    const n = args.scratch.len;
    if (n == max_scratch) setupError(.define_invalid, "--scratch: more than 32 entries; a define this large belongs in a toml");
    scratch_flag_buf[n] = norm;
    args.scratch = scratch_flag_buf[0 .. n + 1];
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

// Three tests rather than one, because a failing assertion aborts its test and the ones
// after it never run. Written as a single test, the mutation that breaks the recording
// override stopped at the first line, and the record of what had been seen red was
// written as if the whole body had fired — five assertions instead of eight. Split by
// role, a mutation names which role it broke.

test "every NextStep renders one sentence whose flags the help text accepts (#274)" {
    // Advice that names a flag this binary does not take is advice nobody can follow —
    // and a sentence is what the schema promises, so it ends in a full stop. Held here
    // against `usage_fmt`, the same text `sideeye help` prints, rather than against a
    // second list of flags that could drift from it.
    inline for (@typeInfo(contract.NextStep).@"enum".fields) |f| {
        const member: contract.NextStep = @enumFromInt(f.value);
        const s = member.render();
        try std.testing.expect(s.len > 0);
        try std.testing.expect(s[s.len - 1] == '.');
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, s, i, "--")) |at| {
            var end = at + 2;
            while (end < s.len and (std.ascii.isAlphabetic(s[end]) or s[end] == '-')) end += 1;
            const flag = s[at..end];
            // Every flag a sentence names appears in the help, as a flag (followed by
            // a space, a newline or a bracket — not as a prefix of a longer flag).
            var found = false;
            var k: usize = 0;
            while (std.mem.indexOfPos(u8, usage_fmt, k, flag)) |hit| {
                const after = hit + flag.len;
                if (after >= usage_fmt.len or usage_fmt[after] == ' ' or usage_fmt[after] == '\n' or usage_fmt[after] == ']' or usage_fmt[after] == ',') {
                    found = true;
                    break;
                }
                k = hit + 1;
            }
            if (!found) {
                std.debug.print("NextStep.{s} names {s}, which the help text does not list\n", .{ f.name, flag });
                return error.TestUnexpectedResult;
            }
            i = end;
        }
    }
}

/// Which subcommand `main()` is running. A local `enum` of `main()` until #572 seam 3b.
pub const Mode = enum { explore, replay, preflight };

/// What `main()` starts from: the mode, replay's case path, and the flags.
pub const Parsed = struct { mode: Mode, case_arg: ?[]const u8, args: Args };

/// The mode dispatch, the flag loop and the mode refusals, as they ran at the top of
/// `main()` (#572 seam 3b). Refuses through `setupError`; the unknown-mode banner exits 3.
pub fn parse(argv: []const []const u8) Parsed {
    var mode: Mode = .explore;
    var case_arg: ?[]const u8 = null;
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "explore")) {
        mode = .explore;
    } else if (argv.len >= 2 and std.mem.eql(u8, argv[1], "preflight")) {
        mode = .preflight;
    } else if (argv.len >= 3 and std.mem.eql(u8, argv[1], "replay") and argv[2].len > 0 and argv[2][0] != '-') {
        mode = .replay;
        case_arg = argv[2];
    } else {
        usage();
        std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
    }

    var args: Args = .{};
    var i: usize = if (mode == .replay) 3 else 2;
    while (i < argv.len) {
        // Flags without a value are handled first; everything else consumes a pair.
        if (std.mem.eql(u8, argv[i], "--allow-unverified")) {
            args.allow_unverified = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--oracle-fs-usage")) {
            // Parsed on every platform; refused on Linux further down, after the state
            // path has been resolved. spike/acceptance.sh's CLI self-description check
            // requires every flag the parser knows to be accepted by some synopsis line
            // on the machine running the check, and it decides "accepted" by whether the
            // flag changes the base command's first line of output — so a parse-time
            // refusal on Linux read as a flag no mode accepts (CI, #406, twice).
            args.oracle_fs_usage = true;
            // Said the moment the flag is read, so an exit anywhere after this line —
            // a later parse error included — reports the oracle as named (#352).
            report.noteOracle(.{ .named = .fs_usage });
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--fresh-state")) {
            if (mode != .replay) setupError(.define_invalid, "--fresh-state applies to replay only (explore's state may be legitimately pre-populated)");
            args.fresh_state = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--stop-when-orphaned")) {
            // #269. A flag and not an environment variable, for reasons measured and
            // recorded in ADR 0010 (argv is per-invocation and is not inherited).
            if (mode == .preflight) setupError(.define_invalid, "preflight explores no worlds; --stop-when-orphaned belongs to explore and replay");
            args.stop_when_orphaned = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--twice")) {
            // #199. The refusal runs the other way from the flags above: this one is
            // preflight's alone, because explore and replay already observe the
            // operation a second time — the un-killed baseline world is that run, and
            // `baseline_run_failed` is what they say when the re-run disagrees. What
            // preflight lacks is any second observation at all.
            if (mode != .preflight) setupError(.define_invalid, "--twice belongs to preflight; explore and replay already re-run the operation in the un-killed baseline world, and a divergent re-run refuses there: as baseline_run_failed when it does not end the way the recording did, as baseline_violates_invariant when its bytes differ");
            args.twice = true;
            i += 1;
            continue;
        }
        if (i + 1 >= argv.len) setupError(.define_invalid, "an option is missing its value");
        const v = argv[i + 1];
        if (std.mem.eql(u8, argv[i], "--observe")) {
            args.observe = contract.ObserveMode.parse(v) orelse
                setupError(.define_invalid, "--observe takes `wrappers` (the default) or `syscalls`");
        } else if (std.mem.eql(u8, argv[i], "--state")) args.state = v else if (std.mem.eql(u8, argv[i], "--setup")) args.setup = .{ .str = v } else if (std.mem.eql(u8, argv[i], "--operation")) args.operation = .{ .str = v } else if (std.mem.eql(u8, argv[i], "--shim")) args.shim = v else if (std.mem.eql(u8, argv[i], "--work")) args.work = v else if (std.mem.eql(u8, argv[i], "--oracle")) {
            args.oracle = v;
            // As for --oracle-fs-usage above: named from this line on (#352).
            report.noteOracle(.{ .named = .strace });
        } else if (std.mem.eql(u8, argv[i], "--check")) {
            args.check = .{ .str = v };
            report.checker_note = report.checkerNoteFor(.named);
        } else if (std.mem.eql(u8, argv[i], "--marker")) {
            args.marker = v;
            report.l1_note = report.l1NoteFor(.named);
        }
        // Taken as spelled, unlike the toml's, which resolves against the file's own
        // directory: a flag is typed at a cwd, so a relative one already means what the
        // caller meant. It is absolutized with the rest of them further down.
        else if (std.mem.eql(u8, argv[i], "--cwd")) args.cwd = v else if (std.mem.eql(u8, argv[i], "--apparatus")) appendApparatusFlag(&args, v) else if (std.mem.eql(u8, argv[i], "--scratch")) appendScratchFlag(&args, v) else if (std.mem.eql(u8, argv[i], "--expect-status")) {
            args.expect_status = config.parseExpectStatus(v) orelse setupError(.define_invalid, "--expect-status must be an integer in 0..255");
            // Mirrored immediately: a refusal between here and the canonical binding
            // below must not report the declaration as 0 (R1 finding).
            report.expected_status_val = args.expect_status.?;
        } else if (std.mem.eql(u8, argv[i], "--world-timeout")) {
            // #263. Worlds only — the recording run, setup and checkers have no
            // budget, and the help text says so: the flag must not read as a promise
            // of a hang-free run.
            if (mode == .preflight) setupError(.define_invalid, "preflight explores no worlds; --world-timeout belongs to explore and replay");
            args.world_timeout_s = parseWorldTimeout(v);
            // The budget's kill-safety and its bounded teardown both stand on
            // unreaped children staying zombies, so SIGCHLD goes to its default
            // disposition here — once, for the whole run, before any fork. An
            // inherited SIG_IGN survives exec and would let the kernel auto-reap;
            // resetting per-world instead would hand the first world a different
            // signal environment than every later one, and leave a window between
            // its fork and the reset. Every child of the run — recording, worlds,
            // checkers — now inherits the same default. Idempotent, so a repeated
            // flag is harmless. Documented in the flag's help text.
            _ = posix.signal(posix.SIGCHLD, posix.SIG_DFL);
        } else if (std.mem.eql(u8, argv[i], "--state-under")) {
            // #266. Replay only: an explore's config is the trust boundary and its
            // state is part of what the operator vets (#96); accepting the flag there
            // would be a second confinement feature nobody asked for, and preflight
            // destroys nothing.
            if (mode != .replay) setupError(.define_invalid, "--state-under applies to replay only: a config's state is part of what the operator vets, and preflight never destroys");
            // A confinement flag must not be last-wins: two spellings in one argv is
            // a caller bug, and silently taking the second would let a widened range
            // ride behind a narrow-looking one.
            if (args.state_under != null) setupError(.define_invalid, "--state-under was given twice; refusing rather than letting the second spelling win");
            args.state_under = v;
        } else if (std.mem.eql(u8, argv[i], "--config")) args.config = v else if (std.mem.eql(u8, argv[i], "--json")) {
            // Rejected before the removeFile below: a rejection that had already deleted
            // the caller's previous report would be a refusal with a side effect.
            if (mode == .preflight) setupError(.define_invalid, "preflight has no machine-readable form; sideeye explore --config answers strictly more, and --json lives there");
            args.json = v;
            refuse.json_path = v;
            // Any document at this path describes some earlier run. Removing it now means
            // an exit that never reaches a writer leaves *no* report rather than a stale
            // one: absence is unambiguous, a previous verdict is not.
            removeFile(v);
        } else setupError(.define_invalid, "unknown option");
        i += 2;
    }

    // preflight answers one question — "does the recording phase accept this target?" —
    // before a define exists. The define-shaped flags are refused by name rather than
    // ignored: an accepted-but-inert flag would be a declared intention that silently
    // never fires, the exact shape the config parser refuses too (ADR 0007).
    // Two observers cannot both be the completeness oracle: they produce different
    // accounts of the same run, and a caller who named both has not said which one the
    // verdict rests on. Refused by name rather than resolved by precedence — the
    // accepted-but-inert shape this parser refuses everywhere else (ADR 0007).
    if (args.oracle != null and args.oracle_fs_usage)
        setupError(.define_invalid, "--oracle and --oracle-fs-usage both name a completeness oracle; pass one");
    args.has_oracle = args.oracle != null or args.oracle_fs_usage;
    // Only now can "no --oracle given" be said: the whole argv has been read and no flag
    // named one. Before this line the account says nothing was established (#352).
    if (!args.has_oracle) report.noteOracle(.none);
    // The flags are the only source of a checker and a marker unless a replayed case or a
    // toml follows; those two blocks settle their own accounts once they have read theirs
    // (#352). Settled here and not at the marker vet: `--state is required` and its
    // siblings refuse between the two, and a flags-only run refused there with nothing
    // declared has read every source it will ever have.
    if (mode != .replay and args.config == null) report.settleDeclared(args.check != null, args.marker != null);
    // Named, not yet read. The account distinguishes the two: an oracle whose capture
    // never parsed establishes nothing about other processes, and a run refused before
    // the comparison must not report as though it had one.
    if (args.oracle_fs_usage)
        boundary.boundary_ev.witness = .{ .unread = .fs_usage }
    else if (args.oracle != null)
        boundary.boundary_ev.witness = .{ .unread = .strace };

    if (mode == .preflight) {
        if (args.oracle_fs_usage) setupError(.define_invalid, "--oracle-fs-usage belongs to explore and replay; preflight asks whether the recording phase accepts this target, and answers that without a second witness");
        if (args.check != null) setupError(.define_invalid, "preflight runs before an invariant exists; --check belongs to explore, which also falsifies it before trusting it");
        if (args.marker != null) setupError(.define_invalid, "--marker belongs to explore; preflight makes no claim a marker could strengthen");
        if (args.config != null) setupError(.define_invalid, "preflight takes the define-surface flags directly; once a sideeye.toml exists, `sideeye explore --config` answers strictly more");
        if (args.allow_unverified) setupError(.define_invalid, "preflight never claims PASS, so there is nothing --allow-unverified could weaken");
    }
    return .{ .mode = mode, .case_arg = case_arg, .args = args };
}
