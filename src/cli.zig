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
//! (`boundary.boundary_ev.witness`). Every refusal `parse` makes goes through
//! `refuse.setupError`; its one exit of its own is the unknown-mode banner — `usage()` then
//! exit 3 — which `main()` no longer reaches. Also here since #705: `answerEntry`, which
//! answers help, `version` and `--version`, a bare `sideeye` and a word that names no
//! command before anything is parsed, and each command's own help, cut out of the usage
//! text. Not here: the `mcp`, `evidence` and `demo` branches (they exit or self-exec and
//! are `main()`'s), and
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
const defang = @import("defang.zig");
const setupError = refuse.setupError;
const say = report.say;
const removeFile = files.removeFile;

/// Must match `.version` in `build.zig.zon`. They are two hand-written strings for the
/// same number, and they had already drifted: the package said 0.1.0 while `--help` said
/// 0.1.0-dev. A test below holds them together.
pub const version = "1.10.0";

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
    /// `--recovery` / `[recovery] command` and `--recovery-check` / `[recovery] check` (#606,
    /// ADR 0072): the target's own recovery and the checker that judges what it left, run
    /// against each saved FAIL world's crash state after the verdict is decided. String form
    /// only on both surfaces, so the replay line carries exactly the command the explore ran.
    /// Declared as a pair or not at all; the pair is held in `phaseDefine`, after the case or
    /// the config has been read, so a mode's own first refusal still comes first.
    recovery: ?[]const u8 = null,
    recovery_check: ?[]const u8 = null,
    allow_unverified: bool = false,
    /// Which observation path counts the operations (contract v14). The default is
    /// the only one that existed through v13, so an invocation that never names this
    /// flag behaves exactly as it did.
    observe: contract.ObserveMode = .wrappers,
    /// Whether `--observe` was on the command line, which `observe` alone cannot say: its
    /// default is a value. A replayed case that records its mode (#691, ADR 0100) takes that
    /// mode when the flag is absent, and refuses a flag that names another.
    observe_named: bool = false,
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
    \\  sideeye preflight --state <dir> --operation <cmd> [--shim <lib>] [--setup <cmd>] [--expect-status <n>] [--cwd <dir>] [--apparatus <entry>] [--scratch <path>] [--oracle <strace>] [--observe wrappers|syscalls|supervised] [--work <dir>] [--twice]
    \\  sideeye preflight --config <sideeye.toml> [--shim <lib>] [--oracle <strace>] [--observe wrappers|syscalls|supervised] [--work <dir>] [--twice]
    \\  sideeye explore --state <dir> --operation <cmd> [--setup <cmd>] [--check <cmd>] [--recovery <cmd> --recovery-check <cmd>] [--marker <bytes>] [--expect-status <n>] [--cwd <dir>] [--apparatus <entry>] [--scratch <path>] [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls|supervised] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye explore --config <sideeye.toml> [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls|supervised] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye replay <case.json> [--shim <lib>] [--recovery <cmd> --recovery-check <cmd>] [--fresh-state] [--state-under <dir>] [--oracle <strace> | --oracle-fs-usage] [--observe wrappers|syscalls|supervised] [--work <dir>] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
    \\  sideeye evidence <case.json>
    \\  sideeye mcp
    \\  sideeye help [<command>]
    \\  sideeye version
    \\  sideeye completions zsh|bash|fish
    \\
    \\demo compiles a small planted-bug tool on this machine (it needs a C compiler)
    \\and explores it, printing the same FAIL report a real finding produces. The
    \\expected exit code is 1 — the planted bug found — so the demo doubles as a
    \\smoke test of this binary and its shim.
    \\
    \\preflight answers "does the recording phase accept this target?" without
    \\exploring — from the define flags before a sideeye.toml exists, or from the
    \\toml itself with --config, read as explore reads it. It runs the operation
    \\under observation and either accepts the recording (exit 0) or refuses with
    \\the same named detector a real run would use (exit 2). A toml's marker must
    \\appear in the recording's output, and a check is refused if it cannot be
    \\started or the state holds nothing to corrupt; neither the check nor a
    \\recovery is run.
    \\With --twice it observes a second run and compares the two, adding one
    \\outcome: the runs left different state (exit 1, and no verdict — see
    \\--twice below). What only a real exploration can check — kill landing,
    \\world-side process boundaries, baseline behavior, checker falsification —
    \\is listed as not checked, never silently claimed.
    \\
    \\evidence renders the bundle a FAIL saved beside its case: the paths whose
    \\before, completed and crashed states differ, whether each existed before the
    \\operation and whether its old bytes survive elsewhere inside the judged state,
    \\the two operations around the crash point, the checker's result and its last
    \\output line, and the replay command. Markdown on stdout, for pasting into an
    \\upstream report. Every field is something the run measured or the word
    \\`unknown`; nothing is ranked. Takes the case's path or the bundle's own
    \\(docs/evidence.md).
    \\
    \\completions prints a completion script for zsh, bash or fish (docs/cli.md: how
    \\to load it).
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
    \\  --oracle     path to strace; the recording run is compared against it (Linux;
    \\               refused on macOS, whose witness is --oracle-fs-usage)
    \\  --oracle-fs-usage
    \\               macOS, as root: compare the recording run against fs_usage
    \\               instead. sudo must already hold credentials (`sudo -v` first, in
    \\               this terminal — the cache is per-terminal); the run refuses
    \\               rather than prompting. Narrower than strace: fs_usage prints
    \\               only a rename's old path and cuts long pathnames from the left,
    \\               so a rename it cannot match and a state directory deep enough to
    \\               be cut are both refusals rather than agreements; and it cannot
    \\               account for other processes, so a child, or the target
    \\               replacing its own image, is UNKNOWN under it.
    \\               Everything it cannot resolve refuses
    \\  --check      command run after each crash, in a fresh process; exit 0 = invariant holds
    \\  --recovery   the target's own recovery (with --recovery-check; the two come together).
    \\               After the exploration has decided its verdict, each saved FAIL world's
    \\               crash state — names, kinds and contents, not timestamps or permissions —
    \\               is rebuilt in --state, this runs, and the recovery checker judges what it
    \\               left. The result is reported beside the verdict and never changes it
    \\               or the exit code. An explore's replay line carries both flags, and
    \\               replay accepts them; with --config they come from [recovery] instead
    \\  --recovery-check
    \\               exit 0 = the recovery left a correct state. Trusted only after it
    \\               rejects a corrupted state and accepts what the recovery leaves on the
    \\               completed one; a checker that fails either makes every recovery result
    \\               unknown, not the run
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
    \\  --observe wrappers|syscalls|supervised
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
    \\               **Caution: do not use `syscalls` on a target that execs an image the
    \\               shim cannot be loaded into.** A filter is inherited across exec and
    \\               cannot be replaced, while exec resets the SIGSYS handler that makes it
    \\               survivable, so a statically linked helper dies at its first
    \\               state-changing call (measured: exit 0 under wrappers, killed by
    \\               SIGSYS under this). A child the shim IS loaded into is unaffected,
    \\               except the child glibc's posix_spawn runs file actions in before
    \\               its exec, with every signal blocked.
    \\               In this mode a target must leave SIGSYS alone. The shim guards
    \\               sigaction/signal/sigprocmask/pthread_sigmask against it, which a
    \\               target can notice, but not every way in: docs/report-schema.md
    \\               item (4) names the ways known
    \\               `supervised` (Linux 5.19+, aarch64/x86_64) counts from OUTSIDE
    \\               the target: the engine starts it through a seccomp
    \\               user-notification filter, no shim is loaded, and each
    \\               state-changing call waits for the engine, which counts it and
    \\               lets it run — or, at the crash point, kills the run before it
    \\               runs. The mode for a statically linked target, which the other
    \\               two refuse as no_shim_marker. It needs a cgroup v2 the engine
    \\               can create cgroups in. Its walls: a run whose writes come from
    \\               two threads refuses (the thread-order records are the shim's);
    \\               a target that installs its own seccomp filter can hide calls
    \\               from it; setuid children lose their privilege (no_new_privs).
    \\               Its case records the mode; replay takes it with no flag
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
    \\               and symlink targets in the state directory (--state, or a
    \\               toml's [world] state); modes, ownership, timestamps, inode
    \\               identity, a symlink's destination and everything outside
    \\               the state directory are not compared, the pre-state
    \\               run B starts from is rebuilt rather than byte-identical, and
    \\               two runs are not all runs. The two-second gap is what
    \\               epoch-second stamping needs to move — not a measured
    \\               sufficiency threshold for nondeterminism in general.
    \\               Caution: it also REWRITES the state directory: it is
    \\               restored from the pre-run snapshot before the second run,
    \\               so the first run's output is gone and file modes come back
    \\               as 0644/0755. A preflight without this flag leaves the
    \\               directory as the run left it.
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

// ---- #705: a mistake is named in one line, and each command has its own help -----------
//
// The first answer to a mistyped command or flag used to be the whole of `usage_fmt` —
// 218 lines, the longest 412 columns — with no line saying what was wrong, and the parse
// loop's arity guard answered an unknown flag typed last as "an option is missing its
// value". What follows names the token instead, offers the nearest spelling the command
// accepts, and cuts each command's own help out of the same text.
//
// Every name compared against comes out of `usage_fmt`: the synopsis lines for commands
// and their flags, the flag entries for what each flag is. `spike/acceptance.sh`'s #273
// block holds the synopsis against the parser in three directions, so reading it here
// adds no second list to drift — a flag the parser reads with no synopsis line is red
// there before it could be missing here.

const synopsis_prefix = "  sideeye ";

/// The command a synopsis line is for (`explore` for both of explore's), or null for a
/// line that is not one.
fn synopsisCommand(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, synopsis_prefix)) return null;
    const rest = line[synopsis_prefix.len..];
    return rest[0 .. std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len];
}

/// Whether `word` is a command some synopsis line is for.
pub fn isCommand(word: []const u8) bool {
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (it.next()) |line| {
        if (synopsisCommand(line)) |c| if (std.mem.eql(u8, c, word)) return true;
    }
    return false;
}

/// The `--flag` words of one line, at word boundaries: `--oracle` is never read out of
/// `--oracle-fs-usage`, nor a flag out of a `--` inside another word.
const FlagWords = struct {
    s: []const u8,
    i: usize = 0,
    fn next(self: *FlagWords) ?[]const u8 {
        while (std.mem.indexOfPos(u8, self.s, self.i, "--")) |at| {
            var end = at + 2;
            while (end < self.s.len and (std.ascii.isAlphanumeric(self.s[end]) or self.s[end] == '-')) end += 1;
            self.i = end;
            const starts_word = at == 0 or self.s[at - 1] == ' ' or self.s[at - 1] == '[';
            if (starts_word and end > at + 2) return self.s[at..end];
        }
        return null;
    }
};

/// The flags the synopsis lines of `cmd` name — of every command when `cmd` is null, which
/// is the set the parse loop reads (the help, version and mcp lines carry none) — each
/// once, in the order they first appear.
fn synopsisFlags(cmd: ?[]const u8, buf: [][]const u8) [][]const u8 {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (it.next()) |line| {
        const c = synopsisCommand(line) orelse continue;
        if (cmd) |want| if (!std.mem.eql(u8, c, want)) continue;
        var fw: FlagWords = .{ .s = line };
        next_flag: while (fw.next()) |f| {
            for (buf[0..n]) |seen| if (std.mem.eql(u8, seen, f)) continue :next_flag;
            if (n == buf.len) break;
            buf[n] = f;
            n += 1;
        }
    }
    return buf[0..n];
}

/// The commands, each once, in synopsis order.
fn synopsisCommands(buf: [][]const u8) [][]const u8 {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    next_line: while (it.next()) |line| {
        const c = synopsisCommand(line) orelse continue;
        for (buf[0..n]) |seen| if (std.mem.eql(u8, seen, c)) continue :next_line;
        if (n == buf.len) break;
        buf[n] = c;
        n += 1;
    }
    return buf[0..n];
}

/// Room for every flag or command the synopsis names; a count past it is cut off rather
/// than written out of bounds, and the unit test below fails first.
const max_names = 64;

/// Whether some command's synopsis line names `flag`: the parse loop's test for "a flag",
/// asked before its arity guard so that an unknown one is named rather than taken for a
/// known one missing its value. Every command's, not the running one's — `spike/
/// acceptance.sh` measures arity by putting each parser flag last under `explore`, and a
/// flag explore refuses by name (`--state-under`, `--twice`) has to reach that refusal.
pub fn isKnownFlag(flag: []const u8) bool {
    var buf: [max_names][]const u8 = undefined;
    for (synopsisFlags(null, &buf)) |f| if (std.mem.eql(u8, f, flag)) return true;
    return false;
}

/// Levenshtein distance, or null past the longest name worth comparing — a token that
/// long is not a misspelling of anything here.
fn editDistance(a: []const u8, b: []const u8) ?usize {
    const cap = 64;
    if (a.len > cap or b.len > cap) return null;
    var row: [cap + 1]usize = undefined;
    for (0..b.len + 1) |j| row[j] = j;
    for (a, 0..) |ca, i| {
        var diag = row[0];
        row[0] = i + 1;
        for (b, 0..) |cb, j| {
            const up = row[j + 1];
            row[j + 1] = @min(@min(up + 1, row[j] + 1), diag + @intFromBool(ca != cb));
            diag = up;
        }
    }
    return row[b.len];
}

/// The one name a mistyped `token` most plausibly meant. A token that is the start of
/// exactly one name (three characters at least past the dashes) is read as that start.
/// Otherwise the closest name within
/// one edit for a stem of four characters or fewer, two for a longer one — two edits reach
/// too far in a short word (`--ora` is two from `--work`; unit test below). Two names as
/// close as each other answer nothing: a guess between two is not a correction. `names`
/// are distinct, which `synopsisFlags` and `synopsisCommands` guarantee.
fn nearest(token: []const u8, names: []const []const u8) ?[]const u8 {
    const stem = std.mem.trimStart(u8, token, "-");
    var prefix: ?[]const u8 = null;
    var prefixes: usize = 0;
    var best: ?[]const u8 = null;
    var best_d: usize = (if (stem.len <= 4) @as(usize, 1) else 2) + 1;
    var tied = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, token)) return null;
        if (stem.len >= 3 and std.mem.startsWith(u8, name, token)) {
            prefix = name;
            prefixes += 1;
        }
        if (editDistance(token, name)) |d| {
            if (d < best_d) {
                best = name;
                best_d = d;
                tied = false;
            } else if (d == best_d and best != null) tied = true;
        }
    }
    // The start of exactly one name is that name. The start of several falls to the edit
    // distance among all of them (review of #705): `--recover` starts both `--recovery` and
    // `--recovery-check` and is one edit from the first, which it plainly meant.
    if (prefixes == 1) return prefix;
    if (best != null and !tied) return best;
    return null;
}

/// The nearest flag `cmd` itself takes — never one only another command takes, which
/// would be a spelling the command refuses.
fn nearestFlagOf(cmd: []const u8, token: []const u8) ?[]const u8 {
    var buf: [max_names][]const u8 = undefined;
    return nearest(token, synopsisFlags(cmd, &buf));
}

fn didYouMean(arena: std.mem.Allocator, near: ?[]const u8) []const u8 {
    const n = near orelse return "";
    return std.fmt.allocPrint(arena, " — did you mean '{s}'?", .{n}) catch "";
}

/// Write `fmt` to stderr as one line and exit 3: the shape the argument refusals of `mcp`,
/// `help`, `version` and `evidence` have always had, which print no verdict line because
/// no run has started.
pub fn refuseOnStderr(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) noreturn {
    const msg = std.fmt.allocPrint(arena, fmt ++ "\n", args) catch fmt ++ "\n";
    _ = posix.write(2, msg.ptr, msg.len);
    std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
}

/// A word that names no command: in the command position (`top`), or after `help`. An
/// option where the command goes is told the order, which is the likelier mistake.
fn refuseUnknownCommand(arena: std.mem.Allocator, top: bool, token: []const u8) noreturn {
    var buf: [max_names][]const u8 = undefined;
    const order = if (top and token.len > 0 and token[0] == '-') " — the command comes first: sideeye <command> [options]" else "";
    refuseOnStderr(arena, "{s}unknown command '{s}'{s}{s} (sideeye help lists the commands)", .{
        if (top) "sideeye: " else "sideeye help: ", defang.textShown(arena, token), didYouMean(arena, nearest(token, synopsisCommands(&buf))), order,
    });
}

/// `sideeye <command>` refusing an argument it does not take — `mcp` and `version`, which
/// take none. "takes no arguments" is what `spike/acceptance.sh` #273 reads for them.
pub fn refuseArgumentOf(arena: std.mem.Allocator, cmd: []const u8, token: []const u8, tail: []const u8) noreturn {
    refuseOnStderr(arena, "sideeye {s} takes no arguments; got '{s}'{s}", .{ cmd, defang.textShown(arena, token), tail });
}

/// `demo`'s refusal of anything but `--shim <lib>`, naming what it was given. Through
/// `setupError`, as it always was, and still beginning "demo takes only", which is what
/// `spike/acceptance.sh` #273 reads for a flag demo refuses.
pub fn refuseDemoArgument(arena: std.mem.Allocator, token: []const u8) noreturn {
    refuse.setupErrorFmt(arena, .define_invalid, "demo takes only --shim <lib>; got '{s}'{s} — everything else it arranges itself", .{
        defang.textShown(arena, token), didYouMean(arena, nearestFlagOf("demo", token)),
    });
}

/// A token in a flag's position that the parse loop cannot take. Three shapes, each said
/// for what it is: help asked for after the command, which is answered only right after
/// it (`main()`'s note on late-position help says why the loop does not answer it); a word
/// that is not a flag at all; and an unknown flag, with the nearest one the command takes.
/// The comparison with the help spellings is made here on `token`, not in the loop on
/// `argv[i]` — `spike/acceptance.sh` check 15 holds the loop to having none.
fn refuseFlagPosition(mode: Mode, token: []const u8) noreturn {
    const arena = argArena();
    const m = @tagName(mode);
    const shown = defang.textShown(arena, token);
    if (std.mem.eql(u8, token, "--help") or std.mem.eql(u8, token, "-h"))
        refuse.setupErrorFmt(arena, .define_invalid, "'{s}' is answered only on its own: sideeye help {s}, or sideeye {s} {s} with nothing after it", .{ shown, m, m, shown });
    if (token.len == 0 or token[0] != '-')
        refuse.setupErrorFmt(arena, .define_invalid, "{s} takes no positional argument here: '{s}' (sideeye help {s})", .{ m, shown, m });
    refuse.setupErrorFmt(arena, .define_invalid, "unknown option '{s}'{s} (sideeye help {s} lists the options {s} takes)", .{
        shown, didYouMean(arena, nearestFlagOf(m, token)), m, m,
    });
}

/// The column a flag's summary starts at in a command's help, past the longest flag name
/// that fits; a longer one pushes its own first line two columns further.
const summary_col = 22;
const help_width = 80;

/// Append `text`, split on single spaces, starting at column `col` and breaking before a
/// word that would carry a line past `help_width`; each further line starts at `indent`.
fn appendWrapped(out: *std.ArrayList(u8), arena: std.mem.Allocator, words: []const []const u8, start_col: usize, indent: usize) error{OutOfMemory}!void {
    var col = start_col;
    var line_empty = true;
    for (words) |w| {
        if (!line_empty and col + 1 + w.len > help_width) {
            try out.append(arena, '\n');
            try out.appendNTimes(arena, ' ', indent);
            col = indent;
            line_empty = true;
        }
        if (!line_empty) {
            try out.append(arena, ' ');
            col += 1;
        }
        try out.appendSlice(arena, w);
        col += w.len;
        line_empty = false;
    }
}

/// A synopsis line cut into the units it may break between: words outside brackets, a
/// bracketed group whole, and a flag together with the `<value>` after it.
fn synopsisUnits(arena: std.mem.Allocator, line: []const u8) error{OutOfMemory}![]const []const u8 {
    var units: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= line.len) : (i += 1) {
        const at_end = i == line.len;
        if (!at_end) switch (line[i]) {
            '[' => depth += 1,
            ']' => depth -|= 1,
            else => {},
        };
        if (at_end or (line[i] == ' ' and depth == 0)) {
            if (i > start) {
                const unit = line[start..i];
                const n = units.items.len;
                if (unit[0] == '<' and n > 0 and std.mem.startsWith(u8, units.items[n - 1], "--")) {
                    const prev = units.items[n - 1];
                    const prev_start = @intFromPtr(prev.ptr) - @intFromPtr(line.ptr);
                    units.items[n - 1] = line[prev_start..i];
                } else try units.append(arena, unit);
            }
            start = i + 1;
        }
    }
    return units.items;
}

/// One flag's summary for a command's help: the first sentence of its entry in the flag
/// list, or the whole description when it has no sentence end (`--state`'s is one clause),
/// joined onto one line. The entry is the line beginning `  --flag` and the continuation
/// lines indented under it; its heading runs to the first two-space gap, and a heading with
/// none (`--observe wrappers|syscalls|supervised`, `--world-timeout <s>`) leaves the whole
/// description to the lines below. Null when the list has no entry for the flag, which the
/// unit test below keeps from happening.
fn flagSummary(arena: std.mem.Allocator, flag: []const u8) error{OutOfMemory}!?[]const u8 {
    var text: std.ArrayList(u8) = .empty;
    var found = false;
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (it.next()) |line| {
        if (found) {
            if (!std.mem.startsWith(u8, line, "    ")) break;
            if (text.items.len > 0) try text.append(arena, ' ');
            try text.appendSlice(arena, std.mem.trim(u8, line, " "));
            continue;
        }
        if (!std.mem.startsWith(u8, line, "  --")) continue;
        var fw: FlagWords = .{ .s = line };
        const name = fw.next() orelse continue;
        if (!std.mem.eql(u8, name, flag)) continue;
        found = true;
        if (std.mem.indexOfPos(u8, line, 2, "  ")) |gap| try text.appendSlice(arena, std.mem.trim(u8, line[gap..], " "));
    }
    if (!found) return null;
    const s = text.items;
    // Every sentence of the entry that begins `Caution:` rides along after the first (review
    // of #705): the short help is where `<command> --help` now sends a reader, and the first
    // sentence alone dropped `--twice` rewriting --state and `syscalls` killing a static
    // helper — both visible there while `<command> --help` printed the whole reference. A
    // caution added to an entry later is carried by being spelled the same way.
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, s[0..sentenceEnd(s, 0)]);
    var k = out.items.len;
    while (std.mem.indexOfPos(u8, s, k, "Caution:")) |at| {
        const begin = if (at >= 2 and std.mem.eql(u8, s[at - 2 .. at], "**")) at - 2 else at;
        const end = sentenceEnd(s, at);
        try out.append(arena, ' ');
        try out.appendSlice(arena, s[begin..end]);
        k = end;
    }
    return out.items;
}

/// Where the sentence that contains `from` ends: just past a `.` followed by a space or the
/// end, or past a `.**` that closes an emphasised sentence. The whole text when it has none.
fn sentenceEnd(s: []const u8, from: usize) usize {
    var k = from;
    while (std.mem.indexOfScalarPos(u8, s, k, '.')) |dot| {
        if (dot + 1 == s.len or s[dot + 1] == ' ') return dot + 1;
        if (std.mem.startsWith(u8, s[dot + 1 ..], "**") and (dot + 3 == s.len or s[dot + 3] == ' ')) return dot + 3;
        k = dot + 1;
    }
    return s.len;
}

/// The paragraph of `usage_fmt` that begins at column 0 with `lead` and a space — `demo`'s,
/// `preflight`'s, `evidence`'s, `replay`'s, and `exit codes:` — up to the next blank line.
fn paragraph(lead: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    var prev_blank = false;
    while (it.next()) |line| {
        defer prev_blank = line.len == 0;
        if (!prev_blank or !std.mem.startsWith(u8, line, lead) or line.len <= lead.len or line[lead.len] != ' ') continue;
        const begin = @intFromPtr(line.ptr) - @intFromPtr(usage_fmt.ptr);
        const end = std.mem.indexOfPos(u8, usage_fmt, begin, "\n\n") orelse usage_fmt.len;
        return usage_fmt[begin..end];
    }
    return null;
}

/// `sideeye help <command>` and `sideeye <command> --help`: the version line, the command's
/// synopsis lines broken to fit, its paragraph, one line per flag its synopsis names, and
/// the exit codes — the codes' first line for a command that reaches a run, with the
/// preflight parenthesis only under preflight, which produces no verdict.
pub fn renderCommandHelp(arena: std.mem.Allocator, cmd: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "sideeye {s} (trace contract v{d})\n\nusage:\n", .{ version, contract.contract_version });
    var it = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (it.next()) |line| {
        const c = synopsisCommand(line) orelse continue;
        if (!std.mem.eql(u8, c, cmd)) continue;
        try out.appendSlice(arena, "  ");
        try appendWrapped(&out, arena, try synopsisUnits(arena, line[2..]), 2, 6);
        try out.append(arena, '\n');
    }
    if (paragraph(cmd)) |p| try out.print(arena, "\n{s}\n", .{p});
    var buf: [max_names][]const u8 = undefined;
    const flags = synopsisFlags(cmd, &buf);
    if (flags.len > 0) {
        try out.appendSlice(arena, "\noptions:\n");
        for (flags) |f| {
            try out.print(arena, "  {s}", .{f});
            const col = 2 + f.len;
            const start = if (col + 2 <= summary_col) summary_col else col + 2;
            try out.appendNTimes(arena, ' ', start - col);
            var words: std.ArrayList([]const u8) = .empty;
            var ws = std.mem.splitScalar(u8, (try flagSummary(arena, f)) orelse "", ' ');
            while (ws.next()) |w| if (w.len > 0) try words.append(arena, w);
            try appendWrapped(&out, arena, words.items, start, summary_col);
            try out.append(arena, '\n');
        }
        if (paragraph("exit codes:")) |codes| {
            var lines = std.mem.splitScalar(u8, codes, '\n');
            try out.print(arena, "\n{s}\n", .{lines.first()});
            const own = try std.fmt.allocPrint(arena, "({s} ", .{cmd});
            if (lines.peek()) |second| if (std.mem.startsWith(u8, std.mem.trimStart(u8, second, " "), own)) {
                while (lines.next()) |l| try out.print(arena, "{s}\n", .{l});
            };
        }
    }
    try out.appendSlice(arena, "\nEvery flag in full, and the other commands: sideeye help\n");
    return out.items;
}

fn printCommandHelp(arena: std.mem.Allocator, cmd: []const u8) noreturn {
    const text = renderCommandHelp(arena, cmd) catch refuseOnStderr(arena, "sideeye: out of memory rendering the help for {s}", .{cmd});
    say("{s}", .{text});
    std.process.exit(@intFromEnum(contract.ExitCode.pass));
}

/// A bare `sideeye`: the version line, the commands, and where help is. Exit 3, as the bare
/// invocation always has (`spike/acceptance.sh` #273 holds both that and the first line).
fn printOverview(arena: std.mem.Allocator) noreturn {
    var buf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&buf);
    const list = std.mem.join(arena, ", ", cmds) catch "";
    say("sideeye {s} (trace contract v{d})\n\nusage: sideeye <command> [options]\ncommands: {s}\n\nsideeye help <command> describes one command; sideeye help is the whole reference.\n", .{ version, contract.contract_version, list });
    std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
}

fn isHelpSpelling(s: []const u8) bool {
    return std.mem.eql(u8, s, "--help") or std.mem.eql(u8, s, "-h");
}

/// The answers no define is needed for, given before anything is parsed: help in every
/// spelling and position it is answered in, `version` and `--version`, a bare `sideeye`,
/// and a first word that names no command. Each exits. A command word followed by
/// anything else returns, to the branch in `main()` that owns that command.
///
/// Called after the `__filter-exec` branch, which must run before anything else in `main`
/// (every call it made would be the subject's), and before `mcp`'s, so `mcp --help` is
/// answered like every other command's.
///
/// `<command> --help` is still the exact three-element shape #296 made it, and for its
/// reason: `explore --marker --help` keeps `--help` as the marker's bytes, `explore --help
/// extra` reaches the parser's refusal, and help in a late position is not answered here
/// because the parse loop's `--json` has already removed a file by then.
pub fn answerEntry(arena: std.mem.Allocator, argv: []const []const u8) void {
    if (argv.len < 2) printOverview(arena);
    // `--help -h` and `-h --help` are help asking about itself, as `help -h` is.
    if (argv.len == 3 and isHelpSpelling(argv[2]) and (isCommand(argv[1]) or isHelpSpelling(argv[1])))
        printCommandHelp(arena, if (isHelpSpelling(argv[1])) "help" else argv[1]);
    // `--help`, `-h` and `help` print the whole reference and exit 0 (#273): asking how to use
    // the tool is not a failure, and exit 0 is the success of what was asked, not PASS
    // (docs/contract-freeze.md §3). `help <command>` prints that command's own.
    if (std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h") or std.mem.eql(u8, argv[1], "help")) {
        if (argv.len == 2) {
            usage();
            std.process.exit(@intFromEnum(contract.ExitCode.pass));
        }
        if (argv.len == 3 and isCommand(argv[2])) printCommandHelp(arena, argv[2]);
        if (argv.len == 3) refuseUnknownCommand(arena, false, argv[2]);
        refuseOnStderr(arena, "sideeye help takes one command at most; got '{s}' after '{s}'", .{ defang.textShown(arena, argv[3]), defang.textShown(arena, argv[2]) });
    }
    // `version` prints the one line a release workflow holds a tag against, and exits 0. The
    // usage banner carries the same string but exits 3 — an assert built on that would have
    // to treat failure as success. `--version` is the spelling people try first.
    if (std.mem.eql(u8, argv[1], "version") or std.mem.eql(u8, argv[1], "--version")) {
        if (argv.len != 2) refuseArgumentOf(arena, "version", argv[2], "");
        say("sideeye {s} (trace contract v{d})\n", .{ version, contract.contract_version });
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }
    if (!isCommand(argv[1])) refuseUnknownCommand(arena, true, argv[1]);
}

// --------------------------------------------------------------- completions (#712)
//
// `sideeye completions zsh|bash|fish` prints a completion script for that shell. Its words are
// the usage lines' own: the commands and each command's flags come from `synopsisCommands` and
// `synopsisFlags` above, so the script cannot offer a flag the help does not list, and the
// #273 block in `spike/acceptance.sh` already holds the help to the parser. What is read here
// besides is what a completion needs and the help already says: what follows a flag (`<dir>`
// is a path, `a|b|c` its words, anything else a value with nothing to offer) and what follows
// the command word (`<case.json>`, `[<command>]`, `zsh|bash|fish`).

/// What a word in a synopsis line asks for when it is a value or a positional argument.
const Want = union(enum) {
    none,
    file,
    words: []const u8,
    commands,
    opaque_value,
};

/// The value tags that name a path. `<strace>` is one: its flag summary says "path to strace".
/// `spike/check-completions.py` keeps its own copy beside the tags that name no path, and stops
/// on a tag in neither, so a new path tag cannot be read as opaque on both sides at once.
const file_tags = [_][]const u8{ "<dir>", "<path>", "<lib>", "<case.json>", "<sideeye.toml>", "<strace>" };

fn wantOf(token: []const u8) Want {
    const t = std.mem.trim(u8, token, "[]");
    if (std.mem.eql(u8, t, "<command>")) return .commands;
    for (file_tags) |f| if (std.mem.eql(u8, t, f)) return .file;
    if (t.len > 0 and t[0] == '<') return .opaque_value;
    if (std.mem.indexOfScalar(u8, t, '|') != null and t.len > 1) return .{ .words = t };
    return .none;
}

/// What the flag `flag` of `cmd` takes, read off the word after it on `cmd`'s synopsis lines.
fn flagWant(cmd: []const u8, flag: []const u8) Want {
    var lines = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (lines.next()) |line| {
        const c = synopsisCommand(line) orelse continue;
        if (!std.mem.eql(u8, c, cmd)) continue;
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        while (words.next()) |w| {
            if (!std.mem.eql(u8, std.mem.trim(u8, w, "[]"), flag)) continue;
            const after = words.peek() orelse return .none;
            if (std.mem.eql(u8, after, "|") or std.mem.startsWith(u8, std.mem.trimStart(u8, after, "["), "--")) return .none;
            return wantOf(after);
        }
    }
    return .none;
}

/// What follows `cmd`'s command word on its first synopsis line, when that is not a flag.
fn positionalWant(cmd: []const u8) Want {
    var lines = std.mem.splitScalar(u8, usage_fmt, '\n');
    while (lines.next()) |line| {
        const c = synopsisCommand(line) orelse continue;
        if (!std.mem.eql(u8, c, cmd)) continue;
        var words = std.mem.tokenizeScalar(u8, line[synopsis_prefix.len + c.len ..], ' ');
        const first = words.next() orelse return .none;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, first, "["), "--")) return .none;
        return wantOf(first);
    }
    return .none;
}

/// The shells `completions` takes, as its own usage line spells them.
fn shellNames(buf: [][]const u8) [][]const u8 {
    const words = switch (positionalWant("completions")) {
        .words => |w| w,
        else => return buf[0..0],
    };
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, words, '|');
    while (it.next()) |s| {
        if (n == buf.len) break;
        buf[n] = s;
        n += 1;
    }
    return buf[0..n];
}

fn appendJoined(out: *std.ArrayList(u8), arena: std.mem.Allocator, items: []const []const u8, sep: []const u8) !void {
    for (items, 0..) |it, i| {
        if (i > 0) try out.appendSlice(arena, sep);
        try out.appendSlice(arena, it);
    }
}

fn appendWords(out: *std.ArrayList(u8), arena: std.mem.Allocator, words: []const u8) !void {
    var it = std.mem.splitScalar(u8, words, '|');
    var first = true;
    while (it.next()) |w| {
        if (!first) try out.append(arena, ' ');
        first = false;
        try out.appendSlice(arena, w);
    }
}

fn renderBash(arena: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    try out.appendSlice(arena,
        \\# sideeye completions for bash, built from this binary's usage lines (sideeye help).
        \\# Load it: eval "$(sideeye completions bash)". Written for bash 3.2 and later.
        \\#
        \\# File names one per line and whole: a name with a space stays one word, and none is
        \\# expanded as a pattern. readline quotes them and gives a directory its slash through
        \\# -o filenames -- set here on bash 4 and later, at registration on 3.2, which has no
        \\# compopt (there it also applies to command and flag names, which matters only when a
        \\# directory of that name sits where you are).
        \\_sideeye_files() {
        \\    local f
        \\    COMPREPLY=()
        \\    # The backslashes typed before a space or `:` come off first: compgen takes them
        \\    # off itself inside a completion, but not when the function is called directly.
        \\    while IFS= read -r f; do
        \\        [ -n "$f" ] && COMPREPLY+=("$f")
        \\    done < <(compgen -f -- "${cur//\\/}")
        \\    compopt -o filenames 2>/dev/null
        \\    return 0
        \\}
        \\_sideeye_offer() {
        \\    if [ "$cword" -eq 1 ]; then
        \\        COMPREPLY=( $(compgen -W "
    );
    try appendJoined(&out, arena, cmds, " ");
    try out.appendSlice(arena,
        \\" -- "$cur") )
        \\        return 0
        \\    fi
        \\    case "$cmd" in
        \\
    );
    for (cmds) |cmd| {
        try out.print(arena, "    {s})\n", .{cmd});
        const pos = positionalWant(cmd);
        if (pos != .none) {
            try out.appendSlice(arena, "        if [ \"$cword\" -eq 2 ]; then\n");
            switch (pos) {
                .file => try out.appendSlice(arena, "            _sideeye_files\n"),
                .commands => {
                    try out.appendSlice(arena, "            COMPREPLY=( $(compgen -W \"");
                    try appendJoined(&out, arena, cmds, " ");
                    try out.appendSlice(arena, "\" -- \"$cur\") )\n");
                },
                .words => |w| {
                    try out.appendSlice(arena, "            COMPREPLY=( $(compgen -W \"");
                    try appendWords(&out, arena, w);
                    try out.appendSlice(arena, "\" -- \"$cur\") )\n");
                },
                else => {},
            }
            try out.appendSlice(arena, "            return 0\n        fi\n");
        }
        var fbuf: [max_names][]const u8 = undefined;
        const flags = synopsisFlags(cmd, &fbuf);
        if (flags.len == 0) {
            try out.appendSlice(arena, "        ;;\n");
            continue;
        }
        try out.appendSlice(arena, "        case \"$prev\" in\n");
        for (flags) |f| {
            switch (flagWant(cmd, f)) {
                .none => {},
                .file => try out.print(arena, "            {s}) _sideeye_files; return 0 ;;\n", .{f}),
                .words => |w| {
                    try out.print(arena, "            {s}) COMPREPLY=( $(compgen -W \"", .{f});
                    try appendWords(&out, arena, w);
                    try out.appendSlice(arena, "\" -- \"$cur\") ); return 0 ;;\n");
                },
                .commands, .opaque_value => try out.print(arena, "            {s}) return 0 ;;\n", .{f}),
            }
        }
        try out.appendSlice(arena, "        esac\n        COMPREPLY=( $(compgen -W \"");
        try appendJoined(&out, arena, flags, " ");
        try out.appendSlice(arena, "\" -- \"$cur\") )\n        ;;\n");
    }
    try out.appendSlice(arena,
        \\    esac
        \\    return 0
        \\}
        \\# readline replaces only the part of a word past its last unquoted COMP_WORDBREAKS
        \\# character -- past a `:` or `=`, from an `@` on -- so a reply is cut back to that part:
        \\# `x:` completes to `x:y.json`, not `x:x:y.json`. bash 4 and later also cut COMP_WORDS
        \\# there (`--state a:b` arrives as `a`, `:`, `b`); the words are joined back where the line
        \\# has no blank between them, which leaves 3.2's uncut words as they were. Only the line up
        \\# to the cursor is read, so a Tab pressed mid-line completes what is before it; COMP_POINT
        \\# counts bytes, so the line is cut in the C locale.
        \\_sideeye() {
        \\    local cur prev cword cmd line i w lead tail cut
        \\    local -a words
        \\    line=$(LC_ALL=C; printf '%s.' "${COMP_LINE:0:COMP_POINT}")
        \\    line=${line%.}
        \\    for (( i = 0; i < COMP_CWORD; i++ )); do
        \\        w=${COMP_WORDS[i]}
        \\        lead=${line%%[![:space:]]*}
        \\        if [ ${#words[@]} -eq 0 ] || [ -n "$lead" ]; then
        \\            words[${#words[@]}]=$w
        \\        else
        \\            words[${#words[@]}-1]=${words[${#words[@]}-1]}$w
        \\        fi
        \\        line=${line#"$lead"}
        \\        line=${line#"$w"}
        \\    done
        \\    lead=${line%%[![:space:]]*}
        \\    line=${line#"$lead"}
        \\    if [ ${#words[@]} -eq 0 ] || [ -n "$lead" ]; then
        \\        words[${#words[@]}]=$line
        \\    else
        \\        words[${#words[@]}-1]=${words[${#words[@]}-1]}$line
        \\    fi
        \\    cword=$(( ${#words[@]} - 1 ))
        \\    cur=${words[cword]}
        \\    prev=
        \\    [ "$cword" -gt 0 ] && prev=${words[cword-1]}
        \\    cmd=${words[1]}
        \\    COMPREPLY=()
        \\    _sideeye_offer
        \\    # Inside quotes, and at an escaped break character, readline replaces the whole word.
        \\    case "$cur" in \'*|\"*) return 0 ;; esac
        \\    tail=$cur
        \\    case "$COMP_WORDBREAKS" in *:*) tail=${tail##*:} ;; esac
        \\    case "$COMP_WORDBREAKS" in *=*) tail=${tail##*=} ;; esac
        \\    case "$COMP_WORDBREAKS" in *@*) case "$tail" in *@*) tail=@${tail##*@} ;; esac ;; esac
        \\    cut=${cur%"$tail"}
        \\    case "$cut" in *\\|*\\[:=]) return 0 ;; esac
        \\    # The replies are names as compgen gives them, without the backslashes typed before them.
        \\    cut=${cut//\\/}
        \\    if [ -n "$cut" ]; then
        \\        for (( i = 0; i < ${#COMPREPLY[@]}; i++ )); do
        \\            COMPREPLY[i]=${COMPREPLY[i]#"$cut"}
        \\        done
        \\    fi
        \\    return 0
        \\}
        \\if type compopt >/dev/null 2>&1; then
        \\    complete -F _sideeye sideeye
        \\else
        \\    complete -o filenames -F _sideeye sideeye
        \\fi
        \\
    );
    return out.items;
}

fn renderZsh(arena: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    try out.appendSlice(arena,
        \\#compdef sideeye
        \\# sideeye completions for zsh, built from this binary's usage lines (sideeye help).
        \\# Load it after compinit: eval "$(sideeye completions zsh)" -- or save it as _sideeye
        \\# in a directory on $fpath.
        \\_sideeye() {
        \\    local cmd=${words[2]} prev=${words[CURRENT-1]}
        \\    if (( CURRENT == 2 )); then
        \\        compadd --
    );
    // The space after `--` outside the literal: a multiline literal does not keep a
    // trailing space, and `compadd --demo` is an option, not the word demo.
    try out.append(arena, ' ');
    try appendJoined(&out, arena, cmds, " ");
    try out.appendSlice(arena,
        \\
        \\        return
        \\    fi
        \\    case $cmd in
        \\
    );
    for (cmds) |cmd| {
        try out.print(arena, "    ({s})\n", .{cmd});
        const pos = positionalWant(cmd);
        if (pos != .none) {
            try out.appendSlice(arena, "        if (( CURRENT == 3 )); then\n");
            switch (pos) {
                .file => try out.appendSlice(arena, "            _files\n"),
                .commands => {
                    try out.appendSlice(arena, "            compadd -- ");
                    try appendJoined(&out, arena, cmds, " ");
                    try out.append(arena, '\n');
                },
                .words => |w| {
                    try out.appendSlice(arena, "            compadd -- ");
                    try appendWords(&out, arena, w);
                    try out.append(arena, '\n');
                },
                else => {},
            }
            try out.appendSlice(arena, "            return\n        fi\n");
        }
        var fbuf: [max_names][]const u8 = undefined;
        const flags = synopsisFlags(cmd, &fbuf);
        if (flags.len == 0) {
            try out.appendSlice(arena, "        ;;\n");
            continue;
        }
        try out.appendSlice(arena, "        case $prev in\n");
        for (flags) |f| {
            switch (flagWant(cmd, f)) {
                .none => {},
                .file => try out.print(arena, "        ({s}) _files; return ;;\n", .{f}),
                .words => |w| {
                    try out.print(arena, "        ({s}) compadd -- ", .{f});
                    try appendWords(&out, arena, w);
                    try out.appendSlice(arena, "; return ;;\n");
                },
                .commands, .opaque_value => try out.print(arena, "        ({s}) return ;;\n", .{f}),
            }
        }
        try out.appendSlice(arena, "        esac\n        compadd -- ");
        try appendJoined(&out, arena, flags, " ");
        try out.appendSlice(arena, "\n        ;;\n");
    }
    try out.appendSlice(arena,
        \\    esac
        \\}
        \\if [[ ${funcstack[1]} == _sideeye ]]; then _sideeye "$@"; else compdef _sideeye sideeye; fi
        \\
    );
    return out.items;
}

fn renderFish(arena: std.mem.Allocator) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    try out.appendSlice(arena,
        \\# sideeye completions for fish, built from this binary's usage lines (sideeye help).
        \\# Load it: sideeye completions fish > ~/.config/fish/completions/sideeye.fish
        \\# The command is the first word, wherever another command's name appears later.
        \\function __sideeye_at --description 'sideeye <command> with exactly N words typed'
        \\    set -l w (commandline -opc)
        \\    test (count $w) -eq $argv[2]; and test "$w[2]" = $argv[1]
        \\end
        \\function __sideeye_in --description 'sideeye <command> with at least N words typed'
        \\    set -l w (commandline -opc)
        \\    test (count $w) -ge $argv[2]; and test "$w[2]" = $argv[1]
        \\end
        \\complete -c sideeye -f
        \\complete -c sideeye -n 'test (count (commandline -opc)) -eq 1' -a '
    );
    try appendJoined(&out, arena, cmds, " ");
    try out.appendSlice(arena, "'\n");
    for (cmds) |cmd| {
        const pos = positionalWant(cmd);
        switch (pos) {
            .none, .opaque_value => {},
            .file => try out.print(arena, "complete -c sideeye -n '__sideeye_at {s} 2' -F\n", .{cmd}),
            .commands => {
                try out.print(arena, "complete -c sideeye -n '__sideeye_at {s} 2' -a '", .{cmd});
                try appendJoined(&out, arena, cmds, " ");
                try out.appendSlice(arena, "'\n");
            },
            .words => |w| {
                try out.print(arena, "complete -c sideeye -n '__sideeye_at {s} 2' -a '", .{cmd});
                try appendWords(&out, arena, w);
                try out.appendSlice(arena, "'\n");
            },
        }
        const min: usize = if (pos == .none) 2 else 3;
        var fbuf: [max_names][]const u8 = undefined;
        for (synopsisFlags(cmd, &fbuf)) |f| {
            try out.print(arena, "complete -c sideeye -n '__sideeye_in {s} {d}' -l {s}", .{ cmd, min, f[2..] });
            switch (flagWant(cmd, f)) {
                .none => {},
                .file => try out.appendSlice(arena, " -r -F"),
                .words => |w| {
                    try out.appendSlice(arena, " -x -a '");
                    try appendWords(&out, arena, w);
                    try out.append(arena, '\'');
                },
                .commands, .opaque_value => try out.appendSlice(arena, " -x"),
            }
            try out.append(arena, '\n');
        }
    }
    return out.items;
}

/// `sideeye completions <shell>`: the script on stdout and exit 0, or one line naming the
/// mistake on stderr and exit 3 — a missing shell, one it does not know (with the nearest
/// it does, when there is exactly one), or a word after the shell. Written straight to
/// stdout, not through `say`, whose buffer is sized for a report.
pub fn runCompletions(arena: std.mem.Allocator, argv: []const []const u8) noreturn {
    var sbuf: [8][]const u8 = undefined;
    const shells = shellNames(&sbuf);
    const list = "zsh, bash or fish";
    if (argv.len == 2) refuseOnStderr(arena, "sideeye completions takes one shell: " ++ list ++ " (sideeye help completions)", .{});
    if (argv.len > 3) refuseOnStderr(arena, "sideeye completions takes one shell; got '{s}' after '{s}'", .{ defang.textShown(arena, argv[3]), defang.textShown(arena, argv[2]) });
    const shell = argv[2];
    const text = blk: {
        if (std.mem.eql(u8, shell, "bash")) break :blk renderBash(arena);
        if (std.mem.eql(u8, shell, "zsh")) break :blk renderZsh(arena);
        if (std.mem.eql(u8, shell, "fish")) break :blk renderFish(arena);
        refuseOnStderr(arena, "sideeye completions: unknown shell '{s}'{s} (it takes " ++ list ++ ")", .{
            defang.textShown(arena, shell), didYouMean(arena, nearest(shell, shells)),
        });
    } catch refuseOnStderr(arena, "sideeye: out of memory rendering the {s} completions", .{shell});
    var off: usize = 0;
    while (off < text.len) {
        const w = posix.write(1, text[off..].ptr, text.len - off);
        if (w <= 0) refuseOnStderr(arena, "sideeye completions: could not write the {s} script to standard output", .{shell});
        off += @intCast(w);
    }
    std.process.exit(@intFromEnum(contract.ExitCode.pass));
}

test "completions read what follows a flag and a command off the usage lines (#712)" {
    const T = std.testing;
    try T.expect(flagWant("explore", "--state") == .file);
    try T.expect(flagWant("explore", "--oracle") == .file);
    try T.expect(flagWant("explore", "--oracle-fs-usage") == .none);
    try T.expect(flagWant("explore", "--allow-unverified") == .none);
    try T.expect(flagWant("explore", "--recovery-check") == .opaque_value);
    try T.expect(flagWant("explore", "--marker") == .opaque_value);
    try T.expectEqualStrings("wrappers|syscalls|supervised", flagWant("explore", "--observe").words);
    try T.expect(positionalWant("replay") == .file);
    try T.expect(positionalWant("evidence") == .file);
    try T.expect(positionalWant("help") == .commands);
    try T.expectEqualStrings("zsh|bash|fish", positionalWant("completions").words);
    try T.expect(positionalWant("explore") == .none);
    try T.expect(positionalWant("demo") == .none);
    try T.expect(positionalWant("mcp") == .none);
    var sbuf: [8][]const u8 = undefined;
    const shells = shellNames(&sbuf);
    try T.expectEqual(@as(usize, 3), shells.len);
    // #705's nearest over the three: a start is that name, two equally near answer nothing.
    try T.expectEqualStrings("bash", nearest("bas", shells).?);
    try T.expectEqualStrings("zsh", nearest("sh", shells).?);
    try T.expect(nearest("bsh", shells) == null);
    try T.expect(nearest("tcsh", shells) == null);
}

/// The text of one command's branch in a bash or zsh script: from its head line to the
/// branch's closing `;;` at eight spaces.
fn branchOf(script: []const u8, head: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, script, head) orelse return null;
    const end = std.mem.indexOfPos(u8, script, at, "\n        ;;\n") orelse return null;
    return script[at..end];
}

/// `flag` as a whole word of `text`: not the start of a longer flag (`--oracle` is not found
/// in `--oracle-fs-usage`).
fn hasFlagWord(text: []const u8, flag: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, flag)) |at| {
        const end = at + flag.len;
        if (end == text.len or text[end] == ' ' or text[end] == ')' or text[end] == '"' or text[end] == ';' or text[end] == '\n') return true;
        from = end;
    }
    return false;
}

test "each completion script gives every command its own branch holding its own flags (#712)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const bash = try renderBash(arena);
    const zsh = try renderZsh(arena);
    const fish = try renderFish(arena);
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    try std.testing.expect(cmds.len >= 9);
    var all_buf: [max_names][]const u8 = undefined;
    const all = synopsisFlags(null, &all_buf);
    for (cmds) |cmd| {
        const b = branchOf(bash, try std.fmt.allocPrint(arena, "\n    {s})\n", .{cmd})) orelse return error.NoBashBranch;
        const z = branchOf(zsh, try std.fmt.allocPrint(arena, "\n    ({s})\n", .{cmd})) orelse return error.NoZshBranch;
        var fbuf: [max_names][]const u8 = undefined;
        const own = synopsisFlags(cmd, &fbuf);
        // Every flag of the command is in its branch, and no flag only another command takes.
        for (all) |f| {
            const mine = for (own) |o| {
                if (std.mem.eql(u8, o, f)) break true;
            } else false;
            try std.testing.expectEqual(mine, hasFlagWord(b, f));
            try std.testing.expectEqual(mine, hasFlagWord(z, f));
            const fish_line = try std.fmt.allocPrint(arena, "'__sideeye_in {s} ", .{cmd});
            const fish_flag = try std.fmt.allocPrint(arena, " -l {s}", .{f[2..]});
            var in_fish = false;
            var lines = std.mem.splitScalar(u8, fish, '\n');
            while (lines.next()) |line| {
                if (std.mem.indexOf(u8, line, fish_line) == null) continue;
                const at = std.mem.indexOf(u8, line, fish_flag) orelse continue;
                const end = at + fish_flag.len;
                if (end == line.len or line[end] == ' ') in_fish = true;
            }
            try std.testing.expectEqual(mine, in_fish);
        }
    }
}

test "the whole help fits what one say can print (#712)" {
    // `usage()` prints the help through `say`, which prints nothing on stdout past its
    // buffer. The help is near it; a line added without room would empty `sideeye help`.
    // The number is `report.say_capacity`, which a test in report.zig holds to it; read
    // here as a number so this test root does not pull in report.zig's own tests.
    const capacity = 16 * 1024;
    var buf: [capacity]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, usage_fmt, .{ version, contract.contract_version });
    try std.testing.expect(text.len + 64 < capacity);
}

fn displayWidth(line: []const u8) usize {
    return std.unicode.utf8CountCodepoints(line) catch line.len;
}

/// Does `help` carry a summary line for `flag` — a line that begins `  <flag>` and then a
/// space, so `--oracle` is not found in `--oracle-fs-usage`'s line?
fn hasSummaryLine(help: []const u8, flag: []const u8) bool {
    var it = std.mem.splitScalar(u8, help, '\n');
    while (it.next()) |line| {
        if (line.len > 2 + flag.len and std.mem.startsWith(u8, line, "  ") and
            std.mem.eql(u8, line[2 .. 2 + flag.len], flag) and line[2 + flag.len] == ' ') return true;
    }
    return false;
}

test "each command's help is its own: every flag it takes has a summary line, no other's does, and it fits (#705)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    // The eight the synopsis lists today. A count, not a list of names: a ninth command is
    // added to `usage_fmt` and this loop covers it without being edited.
    try std.testing.expect(cmds.len >= 8);
    var all_buf: [max_names][]const u8 = undefined;
    const all = synopsisFlags(null, &all_buf);
    try std.testing.expect(all.len >= 20);
    for (cmds) |cmd| {
        const help = try renderCommandHelp(arena, cmd);
        // The first line is the version line `spike/check-evidence-bundle.sh` reads for
        // `evidence --help`, built with its holes filled rather than cut out of `usage_fmt`.
        try std.testing.expect(std.mem.startsWith(u8, help, "sideeye "));
        try std.testing.expect(std.mem.indexOf(u8, help, "{s}") == null and std.mem.indexOf(u8, help, "{d}") == null);
        var lines: usize = 0;
        var it = std.mem.splitScalar(u8, help, '\n');
        while (it.next()) |line| {
            lines += 1;
            if (displayWidth(line) > help_width) {
                std.debug.print("help {s}: a line of {d} columns: {s}\n", .{ cmd, displayWidth(line), line });
                return error.TestUnexpectedResult;
            }
        }
        // 68, not the 60 first planned: the cautions the first diff review asked to carry
        // (`--twice`, `--observe`) put explore's at 61, and #704's `preflight --config` synopsis
        // line put preflight's at 65. The full reference is 226.
        try std.testing.expect(lines <= 68);
        // Shorter than the whole reference, which is the point of having one per command.
        try std.testing.expect(help.len * 2 < usage_fmt.len);
        var own_buf: [max_names][]const u8 = undefined;
        const own = synopsisFlags(cmd, &own_buf);
        for (all) |f| {
            const takes = for (own) |o| {
                if (std.mem.eql(u8, o, f)) break true;
            } else false;
            if (hasSummaryLine(help, f) != takes) {
                std.debug.print("help {s}: {s} {s}\n", .{ cmd, f, if (takes) "has no summary line" else "has a summary line it does not take" });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "a flag's summary is a whole sentence, or the whole description when it has no sentence end (#705)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var buf: [max_names][]const u8 = undefined;
    for (synopsisFlags(null, &buf)) |f| {
        const s = (try flagSummary(arena, f)) orelse {
            std.debug.print("{s} has no entry in the flag list\n", .{f});
            return error.TestUnexpectedResult;
        };
        try std.testing.expect(s.len > 0);
        const ends = s[s.len - 1] == '.' or s[s.len - 1] == ')' or std.mem.endsWith(u8, s, ".**");
        // Not ending in either is allowed only when nothing was cut: no sentence end inside.
        if (!ends and std.mem.indexOf(u8, s, ". ") != null) {
            std.debug.print("{s}'s summary stops mid-sentence: {s}\n", .{ f, s });
            return error.TestUnexpectedResult;
        }
    }
    // The two heading shapes with no two-space gap, whose description starts a line below.
    try std.testing.expect(std.mem.startsWith(u8, (try flagSummary(arena, "--observe")).?, "where operations are counted. "));
    try std.testing.expect(std.mem.startsWith(u8, (try flagSummary(arena, "--world-timeout")).?, "wall-clock budget"));
    // A one-clause description comes back whole.
    try std.testing.expectEqualStrings("directory whose contents define the target's state", (try flagSummary(arena, "--state")).?);
    // The cautions ride along: what `--twice` does to --state, what `syscalls` does to a
    // static helper, and that fs_usage needs root, which is in its first sentence.
    try std.testing.expect(std.mem.indexOf(u8, (try flagSummary(arena, "--twice")).?, "Caution: it also REWRITES the state directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, (try flagSummary(arena, "--observe")).?, "**Caution: do not use `syscalls`") != null);
    try std.testing.expect(std.mem.startsWith(u8, (try flagSummary(arena, "--oracle-fs-usage")).?, "macOS, as root:"));
    // Every caution the flag list states reaches a summary: counted across all of them, so
    // a caution added to any entry later is held here without this test being edited.
    var in_list: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, usage_fmt, at, "Caution:")) |hit| : (at = hit + 1) in_list += 1;
    var in_summaries: usize = 0;
    for (synopsisFlags(null, &buf)) |f| {
        const s = (try flagSummary(arena, f)).?;
        var k: usize = 0;
        while (std.mem.indexOfPos(u8, s, k, "Caution:")) |hit| : (k = hit + 1) in_summaries += 1;
    }
    try std.testing.expect(in_list >= 2);
    try std.testing.expectEqual(in_list, in_summaries);
}

test "a flag is known by its whole word, whichever command takes it (#705)" {
    try std.testing.expect(isKnownFlag("--oracle"));
    try std.testing.expect(isKnownFlag("--oracle-fs-usage"));
    try std.testing.expect(isKnownFlag("--state-under")); // replay's; explore refuses it by name
    try std.testing.expect(isKnownFlag("--twice")); // preflight's
    try std.testing.expect(!isKnownFlag("--orac"));
    try std.testing.expect(!isKnownFlag("--help"));
    try std.testing.expect(!isKnownFlag("--version"));
    try std.testing.expect(!isKnownFlag("-h"));
    try std.testing.expect(isCommand("explore") and isCommand("evidence") and isCommand("version"));
    try std.testing.expect(!isCommand("explor") and !isCommand("--version"));
}

test "the nearest spelling is the command's own, and two equally near answer nothing (#705)" {
    var cbuf: [max_names][]const u8 = undefined;
    const cmds = synopsisCommands(&cbuf);
    try std.testing.expectEqualStrings("explore", nearest("explor", cmds).?);
    try std.testing.expectEqualStrings("version", nearest("versoin", cmds).?);
    try std.testing.expect(nearest("init", cmds) == null);
    try std.testing.expectEqualStrings("--state", nearestFlagOf("explore", "--stat").?);
    try std.testing.expectEqualStrings("--shim", nearestFlagOf("demo", "--sim").?);
    try std.testing.expectEqualStrings("--observe", nearestFlagOf("explore", "--obs").?);
    // Near a flag only another command takes: explore refuses `--twice` and `--state-under`,
    // preflight refuses `--json`, so none of them is offered.
    try std.testing.expect(nearestFlagOf("explore", "--twic") == null);
    try std.testing.expect(nearestFlagOf("explore", "--state-undr") == null);
    try std.testing.expect(nearestFlagOf("preflight", "--jsn") == null);
    // A prefix of two flags (`--oracle`, `--oracle-fs-usage`) is no single answer — and not
    // `--work`, two edits away, which a two-edit reach on a short word used to offer.
    try std.testing.expect(nearestFlagOf("explore", "--ora") == null);
    // The start of several names falls to the edit distance among them: `--wor` starts both
    // `--work` and `--world-timeout` and is one edit from `--work`; `--recover` starts both
    // recovery flags and is one from `--recovery`.
    try std.testing.expectEqualStrings("--work", nearestFlagOf("explore", "--wor").?);
    try std.testing.expectEqualStrings("--world-timeout", nearestFlagOf("explore", "--worl").?);
    try std.testing.expectEqualStrings("--recovery", nearestFlagOf("explore", "--recover").?);
    try std.testing.expectEqualStrings("--oracle", nearestFlagOf("explore", "--oracl").?);
    // One edit is the reach for a short stem: `--jsn` is one from `--json`, which explore takes.
    try std.testing.expectEqualStrings("--json", nearestFlagOf("explore", "--jsn").?);
    try std.testing.expect(nearestFlagOf("explore", "--jxsn") == null);
    // Two names at the same distance: neither is offered.
    try std.testing.expect(nearest("ab", &.{ "ac", "ad" }) == null);
    try std.testing.expectEqual(@as(?usize, 3), editDistance("kitten", "sitting"));
}

test "a synopsis line breaks between bracket groups and keeps a flag with its value (#705)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const units = try synopsisUnits(arena_state.allocator(), "sideeye x --state <dir> [--oracle <strace> | --oracle-fs-usage] [--twice]");
    try std.testing.expectEqual(@as(usize, 5), units.len);
    try std.testing.expectEqualStrings("--state <dir>", units[2]);
    try std.testing.expectEqualStrings("[--oracle <strace> | --oracle-fs-usage]", units[3]);
    var fw: FlagWords = .{ .s = units[3] };
    try std.testing.expectEqualStrings("--oracle", fw.next().?);
    try std.testing.expectEqualStrings("--oracle-fs-usage", fw.next().?);
    try std.testing.expect(fw.next() == null);
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
    if (s.len == 0 or s.len > 5) badValue(null, "--world-timeout must be a whole number of seconds, 1..86400", s, null);
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') badValue(null, "--world-timeout must be a whole number of seconds, 1..86400", s, null);
        v = v * 10 + (ch - '0');
    }
    if (v == 0 or v > 86400) badValue(null, "--world-timeout must be a whole number of seconds, 1..86400", s, null);
    return v;
}

/// The allocator a refusal raised while parsing builds its sentence in: the arena `main()`
/// places before `parse` runs, or the page allocator for a caller that placed none.
fn argArena() std.mem.Allocator {
    return refuse.json_arena orelse std.heap.page_allocator;
}

/// A flag's value refused, in one shape for every flag (#705 — "names what was typed"
/// covers a value as much as a flag): why, then the value as typed, then the nearest
/// accepted value when there is one. `flag` prefixes a `why` that does not name it — the
/// config parser's sentences, shared with the toml, do not.
fn badValue(flag: ?[]const u8, why: []const u8, value: []const u8, near: ?[]const u8) noreturn {
    const arena = argArena();
    refuse.setupErrorFmt(arena, .define_invalid, "{s}{s}{s}; got '{s}'{s}", .{
        flag orelse "", if (flag != null) ": " else "", why, defang.textShown(arena, value), didYouMean(arena, near),
    });
}

/// `--apparatus ENTRY`: the same grammar the toml key uses, refused with the same words.
fn appendApparatusFlag(args: *Args, v: []const u8) void {
    if (config.apparatusFault(v)) |m| badValue("--apparatus", m, v, null);
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
        .bad => |m| badValue("--scratch", m, v, null),
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
    } else if (argv.len >= 2 and std.mem.eql(u8, argv[1], "replay")) {
        // A case's path is replay's first argument. This used to fall into the branch below
        // and print the whole help (#705); the refusal names what stood where the path goes.
        const arena = argArena();
        if (argv.len < 3) refuse.setupErrorFmt(arena, .define_invalid, "replay takes the saved case's path first: sideeye replay <case.json> [options] (sideeye help replay)", .{});
        refuse.setupErrorFmt(arena, .define_invalid, "replay takes the saved case's path first; got '{s}' (sideeye help replay)", .{defang.textShown(arena, argv[2])});
    } else {
        // Not reached from `main()`, whose `answerEntry` refuses a word that names no command
        // before this runs; kept so a new caller cannot fall through to a mode it never chose.
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
        // Asked before the arity guard (#705): an unknown flag typed last used to reach that
        // guard and be told it was missing its value. Every flag some synopsis line names
        // passes, whichever command it belongs to, so a known flag the mode refuses by name
        // still reaches that refusal below, and `spike/acceptance.sh`'s arity probe — each
        // parser flag placed last under `explore` — still meets the guard.
        if (!isKnownFlag(argv[i])) refuseFlagPosition(mode, argv[i]);
        // The guard's opening words are what that probe reads; the flag is named after them.
        if (i + 1 >= argv.len) refuse.setupErrorFmt(argArena(), .define_invalid, "an option is missing its value: {s} takes one", .{argv[i]});
        const v = argv[i + 1];
        if (std.mem.eql(u8, argv[i], "--observe")) {
            args.observe_named = true;
            args.observe = contract.ObserveMode.parse(v) orelse {
                // The modes the near value is chosen from are the enum's own names.
                var modes: [@typeInfo(contract.ObserveMode).@"enum".fields.len][]const u8 = undefined;
                inline for (@typeInfo(contract.ObserveMode).@"enum".fields, 0..) |f, k| modes[k] = f.name;
                badValue(null, "--observe takes `wrappers` (the default), `syscalls` or `supervised`", v, nearest(v, &modes));
            };
        } else if (std.mem.eql(u8, argv[i], "--state")) args.state = v else if (std.mem.eql(u8, argv[i], "--setup")) args.setup = .{ .str = v } else if (std.mem.eql(u8, argv[i], "--operation")) args.operation = .{ .str = v } else if (std.mem.eql(u8, argv[i], "--shim")) args.shim = v else if (std.mem.eql(u8, argv[i], "--work")) args.work = v else if (std.mem.eql(u8, argv[i], "--oracle")) {
            args.oracle = v;
            // As for --oracle-fs-usage above: named from this line on (#352).
            report.noteOracle(.{ .named = .strace });
        } else if (std.mem.eql(u8, argv[i], "--check")) {
            args.check = .{ .str = v };
            report.checker_note = report.checkerNoteFor(.named);
            report.checker_declared = true;
        } else if (std.mem.eql(u8, argv[i], "--marker")) {
            args.marker = v;
            report.l1_note = report.l1NoteFor(.named);
        } else if (std.mem.eql(u8, argv[i], "--recovery") or std.mem.eql(u8, argv[i], "--recovery-check")) {
            // The value travels into the replay line this run prints, so it is held to the
            // byte discipline a toml value is (#26): a control byte could forge that line,
            // and a backslash would promise an escape nothing processes.
            if (config.badBytes(v)) |msg| badValue(argv[i], msg, v, null);
            if (v.len == 0) badValue(argv[i], "a recovery command is empty", v, null);
            if (argv[i].len == "--recovery".len) args.recovery = v else args.recovery_check = v;
        }
        // Taken as spelled, unlike the toml's, which resolves against the file's own
        // directory: a flag is typed at a cwd, so a relative one already means what the
        // caller meant. It is absolutized with the rest of them further down.
        else if (std.mem.eql(u8, argv[i], "--cwd")) args.cwd = v else if (std.mem.eql(u8, argv[i], "--apparatus")) appendApparatusFlag(&args, v) else if (std.mem.eql(u8, argv[i], "--scratch")) appendScratchFlag(&args, v) else if (std.mem.eql(u8, argv[i], "--expect-status")) {
            args.expect_status = config.parseExpectStatus(v) orelse badValue(null, "--expect-status must be an integer in 0..255", v, null);
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
        } else refuseFlagPosition(mode, argv[i]); // a synopsis flag no branch above reads: #273 is red for it first
        i += 2;
    }

    // preflight answers one question — "does the recording phase accept this target?" —
    // without exploring, from the flags or from a toml (#704, ADR 0094). The flags that only
    // an exploration acts on are refused by name rather than ignored: an accepted-but-inert
    // flag would be a declared intention that silently never fires, the exact shape the
    // config parser refuses too (ADR 0007).
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
    // The oracle account names its observer (#217): known here once the whole argv is read,
    // so a run refused before the recording does not carry the shim's name under supervised.
    // `phaseRecording` re-derives it again for a mode a toml or a replayed case set later.
    report.noteObserver(args.observe == .supervised);
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
        // Under --config these three are define-surface flags beside a config, and the
        // refusal for that is explore's own, in `phaseDefine` (#704): checked here first, a
        // flag given beside a toml would be told something about preflight instead of that
        // the define lives in one place. Only the flags' preflight refuses them by name.
        if (args.config == null) {
            if (args.check != null) setupError(.define_invalid, "--check belongs to explore, which falsifies it before trusting it; a check declared in a sideeye.toml is read by preflight --config, which refuses it if it cannot be started or the state holds nothing to corrupt, and does not run it");
            if (args.marker != null) setupError(.define_invalid, "--marker belongs to explore; a marker declared in a sideeye.toml is read by preflight --config, which confirms the recording run printed it");
            if (args.recovery != null or args.recovery_check != null) setupError(.define_invalid, "--recovery and --recovery-check belong to explore and replay; preflight saves no FAIL for a recovery to be run against, and a recovery declared in a sideeye.toml is read by preflight --config without being run");
        }
        if (args.allow_unverified) setupError(.define_invalid, "preflight never claims PASS, so there is nothing --allow-unverified could weaken");
    }
    return .{ .mode = mode, .case_arg = case_arg, .args = args };
}
