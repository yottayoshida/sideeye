//! What a run says: the report's state and its two renderings.
//!
//! `src/report.zig` owns the account of a run — the module-level facts the orchestrator's
//! phases establish (`oracle_note`, `checker_note`, `l1_note`, `l0_note`, `case_note`,
//! `explored`, `violations`, `setup_status`, `scratch_declared`, …) and the two renderings
//! that read them: the text report, line by line through `say`, and the JSON document
//! through `buildJson`, written whole or not at all by `writeJsonReport`. A value both
//! renderings carry has one definition here (#280), and a fact no phase has established
//! yet keeps its initialiser's "not established" wording (#352). Nothing here exits the
//! process or decides a verdict: `src/main.zig` sets the facts and chooses when each
//! rendering runs, and `src/refuse.zig` renders its two verdicts through the same `say` and
//! `writeJsonReport`.
//!
//! Who writes the facts: `main.zig`, directly or through the helpers here it calls
//! (`noteOracle`, `settleDeclared`), with three exceptions named so a reader does not have
//! to find them — `divergenceDetail` here sets `divergence_syscall` as it builds the
//! detail, and `refuse.reconcileOrRefuse` sets `l0_note` and `attributed_to_rename` as it
//! classifies. What is public is the orchestrator's interface to the report — the facts it
//! writes and the renderers it calls — which is why this surface is wider than the other
//! seams': it is the measured coupling between `main()` and the report, and the seam that
//! cuts `main()` into phases will consume it.
//!
//! Third seam of #572 (ADR 0062), first half. Bodies moved from `main.zig` byte for byte on
//! 2026-09-13, with `pub` added where another file reads or writes them; the aliases for
//! `defang.zig`'s three primitives and `files.zig`'s two operations are declared here as in
//! `main.zig`, so the moved bodies read as they did. Thirteen tests moved with the behaviour
//! they hold, and `build.zig` names this file as a test root.
const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const config = @import("config.zig");
const mcp = @import("mcp.zig");
const boundary = @import("boundary.zig");
const defang = @import("defang.zig");
const capture = @import("capture.zig");
const files = @import("files.zig");
const sanitizeForReport = defang.sanitizeForReport;
const textShown = defang.textShown;
const appendSanitized = defang.appendSanitized;
const removeFile = files.removeFile;
const writeWholeFile = files.writeWholeFile;

/// 32 KiB since #717: 16 held the whole help with 27 bytes to spare, and `preflight --json` was
/// the next flag. The help is printed by one `say`, so its size and this buffer move together.
var out_buf: [32 * 1024]u8 = undefined;
/// What one `say` can print; past it the report goes to stderr as an error instead.
pub const say_capacity = out_buf.len;

/// Whether the verdict word is coloured (#712, docs/cli.md): only when standard output is a
/// terminal, `NO_COLOR` is unset or empty (no-color.org), and `TERM` is not `dumb`. Pure, so
/// the cases are tested without touching the environment. Only fd 1 is asked: a report
/// redirected into a file from a terminal carries no escape sequence of Sideeye's.
fn colourFor(stdout_is_tty: bool, no_color: ?[]const u8, term: ?[]const u8) bool {
    if (!stdout_is_tty) return false;
    if (no_color) |v| if (v.len > 0) return false;
    if (term) |t| if (std.mem.eql(u8, t, "dumb")) return false;
    return true;
}

/// Decided at the first verdict word, not at startup: a SETUP ERROR can be printed while
/// the flags are still being read. The answer cannot change within one run.
var colour_decided: ?bool = null;

fn colourOn() bool {
    if (colour_decided) |c| return c;
    const no_color: ?[]const u8 = if (posix.getenv("NO_COLOR")) |z| std.mem.span(z) else null;
    const term: ?[]const u8 = if (posix.getenv("TERM")) |z| std.mem.span(z) else null;
    const c = colourFor(posix.isatty(1) == 1, no_color, term);
    colour_decided = c;
    return c;
}

/// The verdict word, coloured where `colourFor` allows it and as written everywhere else.
/// The word stays at the call site (`paint("FAIL")`) so a search for the verdict finds the
/// line that prints it; only the four verdicts are accepted.
pub fn paint(comptime word: []const u8) []const u8 {
    const code = comptime if (std.mem.eql(u8, word, "PASS"))
        "32"
    else if (std.mem.eql(u8, word, "FAIL"))
        "31"
    else if (std.mem.eql(u8, word, "UNKNOWN"))
        "33"
    else if (std.mem.eql(u8, word, "SETUP ERROR"))
        "35"
    else
        @compileError("paint takes a verdict word: PASS, FAIL, UNKNOWN or SETUP ERROR");
    return if (colourOn()) "\x1b[1;" ++ code ++ "m" ++ word ++ "\x1b[0m" else word;
}

test "say's capacity is the 32 KiB the whole help is held under in cli.zig (#712, #717)" {
    try std.testing.expectEqual(@as(usize, 32 * 1024), say_capacity);
}

test "the verdict is coloured only on a terminal, without NO_COLOR, and not for TERM=dumb (#712)" {
    const T = std.testing;
    for ([_]?[]const u8{ null, "xterm", "dumb" }) |term| {
        for ([_]?[]const u8{ null, "", "1" }) |nc| {
            const want_on = (nc == null or nc.?.len == 0) and !(term != null and std.mem.eql(u8, term.?, "dumb"));
            try T.expectEqual(want_on, colourFor(true, nc, term));
            try T.expectEqual(false, colourFor(false, nc, term));
        }
    }
}

/// Re-emits a gate child's captured output, every non-empty line behind `marker` (#134). A
/// gate's child produces exactly the output a real finding would — a checker failing over a
/// broken store, or refusing a state — and a single line harvested from an unlabeled transcript
/// once became "world evidence" (the buku correction, PR #133). A fence would not travel with
/// an excerpt; a per-line prefix does. Blank lines are dropped: a bare marker is noise. A
/// capture that cannot be read back is said out loud rather than silently swallowed.
pub fn sayCaptureMarked(arena: std.mem.Allocator, path: []const u8, comptime marker: []const u8) void {
    if (capture.readFileAllocCapped(arena, path, 1024 * 1024, .{ .no_follow = true })) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            say(marker ++ ": {s}\n", .{line});
        }
    } else {
        say(marker ++ ": (the gate's child output could not be read back from {s} — missing, unreadable, or over the 1 MiB re-emission cap; the capture file, if present, still holds it)\n", .{path});
    }
}

/// The report is the product. Losing it silently is not an option.
///
/// This used to `catch return` on overflow, so a FAIL whose paths pushed the text past
/// 16 KB exited 1 having printed nothing at all — the caller would see a bare exit code
/// and no counterexample. Formatting into a fixed buffer is still right for a tool that
/// must work when the heap is uninteresting, so the failure is reported instead of
/// swallowed.
pub fn say(comptime fmt: []const u8, args: anytype) void {
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

/// The prose half of the oracle account. Assigned from `OracleAsked` at three points —
/// here, the moment an oracle flag is consumed, and the end of the parse loop — and
/// rewritten only inside the comparison block. See `noteOracle` (#352).
pub var oracle_note: []const u8 = initialOracleNote(.unparsed);

/// The machine-readable half of the oracle account (#94). Set true at exactly one
/// point — beside the "agreed on N operations" note, after the comparison completed
/// and agreed. Every other outcome keeps the initial false: no --oracle given,
/// --allow-unverified without an oracle, or a comparison cut short by any refusal
/// above it (the two flags are not exclusive: an oracle that ran and agreed sets
/// true even beside an inert --allow-unverified). A fact
/// about the run, never about the verdict — a FAIL stands without an oracle.
pub var oracle_verified: bool = false;
/// The same fact for a comparison that covered the subject's operations and not the
/// children's (contract v15).
///
/// Set instead of `oracle_verified`, never beside it, and only where a run's writing
/// children were admitted as crash points: the completeness comparison is the subject's
/// account against the oracle's view of the subject, so a crash point performed by a child
/// is one the oracle placed and ordered but did not compare operation by operation. "Both
/// witnesses agreed about every operation the verdict rests on" and "both agreed about the
/// subject's, and the children's were seen but not compared" are different claims, and
/// `docs/contract-freeze.md` surface 2 says a machine field changes name before it changes
/// meaning — so the weaker claim gets a name rather than the stronger field's. A new
/// optional field, which surface 2 keeps open (#320).
pub var oracle_verified_subject_only: bool = false;
/// Ownership/permission writes on the state directory (#121, option b): observed by
/// the oracle alone — the shim does not interpose them — and excluded from every
/// verdict input. The default says why absence of a note is not absence of writes:
/// without an oracle nothing can see a chown, and "was not seen" must not read as
/// "did not happen" here any more than anywhere else in this tool.
pub var metadata_note: []const u8 = initialMetadataNote(.unparsed, false);
/// What the parser established about the oracle, kept so the metadata account can be
/// re-derived once the observation mode is known (#217, `noteObserver`).
var oracle_asked: OracleAsked = .unparsed;

/// What the parser has established about the completeness oracle so far (#352). Both
/// account strings above are assigned from this — at their initialisers, the moment either
/// oracle flag is consumed, and once the parse loop has read the whole argv — so "no
/// --oracle given" is written only after every argument was read and none named one.
/// Every exit before the comparison block writes the report through the same
/// `writeJsonReport` (`unknown()` and `setupError()` alike, parse errors included), and
/// used to publish the no-oracle wording on runs that were given an oracle: the initialiser
/// asserted a fact the parser had not yet established. Now it asserts nothing until it can.
const OracleAsked = union(enum) {
    /// The arguments have not been read to the end.
    unparsed,
    /// A flag naming an oracle was consumed; the comparison has not run.
    named: boundary.BoundaryEvidence.Kind,
    /// The arguments were read to the end and named none.
    none,
};

fn initialOracleNote(asked: OracleAsked) []const u8 {
    return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read",
        // The flag is named so a reader can tell which observer was asked for; the two
        // phrases are matched whole by spike/acceptance.sh (2fc, 2fd, 2fi), not by the
        // `--oracle` prefix they share.
        .named => |kind| switch (kind) {
            .strace => "not compared: --oracle was named, and this run stopped before the comparison",
            .fs_usage => "not compared: --oracle-fs-usage was named, and this run stopped before the comparison",
        },
        // Byte for byte what every run that named no oracle published before #352.
        .none => "not run (no --oracle given)",
    };
}

fn initialMetadataNote(asked: OracleAsked, supervised: bool) []const u8 {
    // Who does not see these calls is the observer's name (#217): under `--observe
    // supervised` no shim is loaded, and the engine's filter is not told of them either.
    if (supervised) return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read; the supervising engine is not notified of ownership/permission/timestamp calls, so only a completed oracle account could show them",
        .named => |kind| switch (kind) {
            .strace => "not established: --oracle was named, and this run stopped before its metadata account was completed; the supervising engine is not notified of ownership/permission/timestamp calls",
            .fs_usage => "not established: --oracle-fs-usage was named, and this run stopped before its metadata account was completed; the supervising engine is not notified of ownership/permission/timestamp calls",
        },
        .none => "not observable (no oracle ran; the supervising engine is not notified of ownership/permission/timestamp calls)",
    };
    return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read; the shim does not interpose ownership/permission/timestamp calls, so only a completed oracle account could show them",
        // "before its metadata account was completed", not "before its capture was read":
        // the comparison block reads the capture and can refuse on it before
        // `metadata_note` is assigned, and this wording has to stay true there too.
        .named => |kind| switch (kind) {
            .strace => "not established: --oracle was named, and this run stopped before its metadata account was completed; the shim does not interpose ownership/permission/timestamp calls",
            .fs_usage => "not established: --oracle-fs-usage was named, and this run stopped before its metadata account was completed; the shim does not interpose ownership/permission/timestamp calls",
        },
        .none => "not observable (no oracle ran; the shim does not interpose ownership/permission/timestamp calls)",
    };
}

/// Assign both accounts from what the parser has established.
pub fn noteOracle(asked: OracleAsked) void {
    oracle_note = initialOracleNote(asked);
    oracle_asked = asked;
    metadata_note = initialMetadataNote(asked, false);
}
/// Re-derive the metadata account once the observation mode is known (#217). The parser
/// records the oracle before the mode is read, so the account it wrote names the shim;
/// called before any run, so no comparison's account is overwritten.
pub fn noteObserver(supervised: bool) void {
    metadata_note = initialMetadataNote(oracle_asked, supervised);
}
/// The declared invariant's account. Same rule as `oracle_note` (#352): "none configured"
/// is written only once every source of a checker — the flag, a replayed case, the toml —
/// has been read and none supplied one; a source that did supply one says so from that
/// line on, and the initialiser establishes nothing. Rewritten inside the checker block.
pub var checker_note: []const u8 = checkerNoteFor(.unparsed);
/// The L1 story (ADR 0008): whether a success marker was declared, and in how many
/// crash worlds it was observed — the worlds where the post-success invariant was
/// enforced. Mirrors `checker_note`: one variable, read by text and JSON alike, and the
/// same three-state rule for what it says before the recording run (#352).
pub var l1_note: []const u8 = l1NoteFor(.unparsed);

/// The figures the `oracle` and `checker` sentences state, kept as data for the JSON report's
/// optional fields (#711, ADR 0096). Each is set on the line that writes the number into its
/// sentence, from the same value, and stays `null` — the field absent — until then: a run that
/// never reached the comparison, or never declared a checker, says nothing rather than zero.
pub var oracle_operations_agreed: ?usize = null;
/// Whether a checker was named, once that is known: set where `checker_note` becomes
/// "configured" or "none configured" — the line that reads `--check`, or `settleDeclared` once
/// every source has been read.
pub var checker_declared: ?bool = null;
/// How many worlds the checker ran in, set where the `checker` sentence says so.
pub var checker_worlds: ?usize = null;
/// Whether the recording run's process account is a measurement (#711): set once every check on
/// the recording's trace has held, at the line `l0_judged_paths_touched` is set on, for that
/// field's reason. A refusal on a trace cut short, renumbered or never announced carries counts
/// read from part of it, so the `processes_*` fields are absent there rather than partial.
pub var processes_measured: bool = false;

/// What the parser and the define sources have established about a declared checker or
/// marker (#352). Like `OracleAsked` but with no kind: the account names no source.
const Declared = enum {
    /// The arguments and the define sources have not all been read.
    unparsed,
    /// A flag, a replayed case or the toml supplied one.
    named,
    /// Every source has been read and none supplied one.
    none,
};

pub fn checkerNoteFor(d: Declared) []const u8 {
    return switch (d) {
        // "or define": a replayed case or a toml is read after the argv, and a run that
        // stops while reading either is in this state too.
        .unparsed => "not established: this run stopped while its arguments or define were still being read",
        .named => "configured; this run stopped before the checker ran",
        // Byte for byte the pre-#352 wording; docs/report-schema.md and acceptance pin it.
        .none => "none configured",
    };
}

pub fn l1NoteFor(d: Declared) []const u8 {
    return switch (d) {
        .unparsed => "not established: this run stopped while its arguments or define were still being read",
        // True from the moment a marker is known until the recording run's stdout is
        // scanned, which is where the next assignment sits.
        .named => "marker configured; the recording run has not been scanned yet",
        // Byte for byte the pre-#352 wording; docs/cli.md and docs/report-schema.md show it.
        .none => "no marker configured",
    };
}

/// Every source of a checker and a marker that this mode reads has been read: say
/// "configured" where one came and "none configured" where none did (#352). Called at the
/// line each mode's last source has been read by — right after the parse loop when neither
/// a replayed case nor a toml follows, after the case in replay, after the toml under
/// `--config`. Not later: the required-flag refusals and the marker vet sit after all three,
/// and a run refused there with nothing declared must say "none", not "not established".
pub fn settleDeclared(has_check: bool, has_marker: bool) void {
    checker_declared = has_check;
    checker_note = checkerNoteFor(if (has_check) .named else .none);
    l1_note = l1NoteFor(if (has_marker) .named else .none);
}
/// Whether a marker was configured at all; widens `not tested` (post-only file
/// contents are checked for existence, not content).
pub var l1_configured: bool = false;
/// Which L0 form judged which files (ADR 0004). Starts as an explicit "not yet", so
/// an UNKNOWN raised before the snapshots exist never carries an invented
/// classification; set from the L0Plan the moment it is built.
pub var l0_note: []const u8 = "not classified (the run was refused before L0 classification)";

/// How many differences were attributed wholesale to a directory a recorded rename moved
/// in from outside the judged root (#405, ADR 0032). Zero means the run has no such
/// window — which is the point of carrying it as a number: "no window" is then something
/// a caller reads, not something it infers from the absence of a sentence.
pub var attributed_to_rename: usize = 0;
/// Non-zero once any file is judged by the history form; widens `not tested`.
pub var l0_history_count: u32 = 0;
/// The case/replay story (ADR 0009), one variable each read by text and JSON alike
/// (the checker_note pattern). A FAIL sets them to the saved case and its replay
/// command; a replay sets the case to what it was asked to re-verify the moment the
/// file parses, so even a `case_no_longer_applies` refusal names which case it
/// refused — the JSON consumer is the §17 audience and must not need the text.
pub var case_note: []const u8 = "(none)";

/// The syscall the oracle saw at a divergence, for the report's `divergence_syscall`
/// (#337). Empty until a divergence refusal builds its detail, which is the only writer
/// — and it writes only where the oracle HAS a line at the diverging index, so
/// `oracle_saw_phantom` (where the shim's account runs past the oracle's, and the index
/// is exactly `oracle.len`) leaves it empty and the field stays absent.
///
/// The quoted line stays in `message`: a refusal that cannot name the operation it
/// refused on is not a diagnostic (ADR 0010), and #326 marks those bytes rather than
/// removing them. This is the same fact in a form a reader does not have to parse.
///
/// **It is the observer's vocabulary, never the target's** — which matters because the
/// text report prints this value without passing it through `sanitizeForReport`, unlike
/// every path-shaped string beside it. Two producers hold that line, and neither is
/// visible from here: `src/oracle.zig`'s `syscallName` returns only `[A-Za-z0-9_]+`
/// (its loop rejects anything else), and `src/fsusage.zig` appends `ln.call`, which by
/// then has been matched against `classOf`'s table — a member of that table or its
/// `_nocancel` variant, never free text from the capture. A third producer would have to
/// keep that property; the alignment tests on both sides are where a new one would be
/// noticed, not here.
pub var divergence_syscall: []const u8 = "";
/// How the `--setup` run ended (#518), set once from the value the refusal switches on and
/// read by `buildJson` under `setup_failed` only — so a run whose setup succeeded leaves a
/// status here that no report can reach. Carried the way `divergence_syscall` is, a global
/// the one site with the value sets, rather than threaded through `setupError`, whose 190
/// other sites have no status to hand over.
pub var setup_status: ?posix.Term = null;
pub var replay_note: []const u8 = "-";
/// The evidence bundle saved beside the earliest exhibit's case (#607, ADR 0071), or
/// `"-"` when none was written. A path rather than a derivation rule: the name is
/// `<work>/evidence/NNNNNN.json` for the case of that id today, and a consumer that had to know
/// that would be holding a second copy of a rule only this file should own.
pub var evidence_note: []const u8 = "-";
/// Progress, so an UNKNOWN raised mid-exploration reports what had been explored rather
/// than zero. A caller aggregating coverage reads these.
pub var crash_points: u32 = 0;
pub var explored: u32 = 0;
pub var violations: u32 = 0;
/// The declared success status in effect (default 0), mirrored into every report so a
/// PASS over a non-zero convention is machine-auditable (ADR 0014).
pub var expected_status_val: u8 = 0;
/// The directory the define's setup, operation and checker ran in (#647): the declared
/// `cwd`, resolved, or Sideeye's own when none was declared. Set once, in phase 0, right
/// after the declared `cwd` is resolved and pinned — the same value the oracle is handed to
/// resolve the subject's relative paths against, so the report and the oracle cannot name
/// two different directories for one run.
///
/// Null until then, and null for good on a SETUP ERROR raised by the config or by the `cwd`
/// vet itself: the report then carries neither field, because it has no directory to name.
/// Also null if Sideeye's own `getcwd` failed — a value it does not have is not written.
///
/// Why it exists: the refusal an adopter meets first when an operation needs its own
/// directory is `recording_run_failed`, which (ADR 0030) reports what was observed — an exit
/// status — and no cause. Where the commands ran is also an observation, the engine already
/// holds it, and it is the one that names the line to add.
pub var command_cwd: ?[]const u8 = null;
/// Whether `command_cwd` came from a declaration or is Sideeye's own default. The distinction
/// is the useful half: the failure #647 recorded was a `cwd` that was never declared.
pub var command_cwd_declared: bool = false;
/// The define's apparatus as declared (ADR 0041), set by `checkApparatus` once every entry
/// passed. Empty when nothing was declared, and the report then carries neither field: an
/// empty array would read as "declared nothing" on a SETUP ERROR raised before any define
/// was read. The unchecked subset is not stored: both renderings derive it through
/// `config.apparatusUnchecked`, so they cannot disagree about it.
pub var apparatus_declared: []const []const u8 = &.{};

/// The define's scratch declaration (ADR 0043), set beside the L0 classification — the
/// same slice the plan matches on, so the report's `scratch` field, the `atomicity`
/// line's parenthesis and the `not tested` item cannot describe a declaration the judge
/// did not read. Empty until the define was read, so a SETUP ERROR raised before that
/// carries no field.
pub var scratch_declared: []const []const u8 = &.{};

/// How many judged paths the report lists before it starts counting instead (#638, ADR 0079).
/// The state tree has no entry ceiling — `max_state_tree_bytes` bounds held memory, which a
/// tree of many small files reaches at a count in the millions — so an unbounded array would
/// be the one field that scales with the target's tree. The largest judged set measured while
/// authoring real defines was fourteen (`spike/authoring-cost/RESULTS.md`, `genisoimage`);
/// this is seventy times that, and a run that reaches it is telling its author to narrow the
/// state directory rather than to read the list.
pub const max_judged_paths_listed: usize = 1000;

/// The second ceiling, and the one that bounds the document: how many bytes of path names the
/// array carries before it starts counting instead.
///
/// The entry ceiling alone does not bound the report. `contract.max_path` is 4096, so a
/// thousand entries is four megabytes of names before escaping, and `jsonString` expands a
/// control byte to `\uXXXX` and an invalid UTF-8 byte to `\ufffd` — six bytes each. **The MCP
/// server reads the report with a 4 MiB cap** (`mcp.zig`) and answers a larger one with a tool
/// error, so without this a wide enough state tree would turn a real verdict into "sideeye
/// produced no report". Before this field existed nothing in the report grew with the target's
/// tree and that ceiling was unreachable; this keeps it that way.
///
/// 64 KiB of names is ~1000 paths at 64 bytes each, so it does not bind before the entry
/// ceiling on anything shaped like a define a person wrote, and 384 KiB after the worst-case
/// escaping leaves the MCP cap an order of magnitude of room.
pub const max_judged_paths_bytes: usize = 64 * 1024;

/// The L0 judged set as data (#638, ADR 0079): every path the built-in atomicity form judged,
/// read from the same plan the judgement reads (ADR 0004). `l0` says how many and in which
/// two forms; this says which. Set together with `l0_classified` by `publishJudgedPaths`, so
/// a refusal raised before the classification existed carries neither field — the presence
/// rule `apparatus` and `scratch` follow, keyed on a different fact.
pub var l0_judged_paths: []const []const u8 = &.{};

/// How many judged paths `l0_judged_paths` does NOT list. Zero is the common case and says
/// the array is the whole set; non-zero is the reading that matters, because the promise the
/// page makes is "the whole set, or a PREFIX of it and a count of the rest", never "the whole
/// set". A prefix rather than a fixed count: either ceiling can bind first, and an allocation
/// failure leaves no names at all with every path counted here.
pub var l0_judged_paths_omitted: u32 = 0;

/// Whether the run reached L0 classification. Not derivable from the two above: a run whose
/// judged set is legitimately empty — a define that declared everything scratch — publishes an
/// empty array with nothing omitted, and that is a different fact from never having classified.
pub var l0_classified: bool = false;

/// How many of the judged paths a crash world could have shown changed (#683, ADR 0091): those
/// that ended other than they began, or that a crash point named. Null until measured, which
/// happens once every check on the recording's trace has held (the last is a contained run's
/// cgroup account), so a refusal on an untrustworthy trace carries none. Zero beside a
/// non-empty `l0_judged_paths` is the reading this exists for — the atomicity invariant held
/// over paths the operation never touched, and on an exploration's PASS it is the checker or the
/// marker that judged the run (a replay's PASS is not gated, and can carry zero with neither).
pub var l0_judged_paths_touched: ?u32 = null;

/// The recovery account (#606, ADR 0072): what the run did about a declared recovery, as a
/// sentence. Null until the define was read and found to declare one, so a report from a
/// define without `[recovery]` — and a refusal raised before the define was read — carries no
/// recovery field and no recovery line. Two refusal messages name the recovery flags or
/// section whatever the define declares (`--config` exclusivity, an unknown config section).
pub var recovery_note: ?[]const u8 = null;

/// One saved exhibit's recovery result, for the JSON exhibit objects.
pub const RecoveryResultJson = struct {
    result: contract.RecoveryResult,
    ms: u64,
    command_exit: ?u8,
};

/// Set after the exploration when a recovery ran against the exhibit; null otherwise, which is
/// every run without a declared recovery and every run with one and no FAIL.
pub var recovery_earliest: ?RecoveryResultJson = null;
pub var recovery_checker_earliest: ?RecoveryResultJson = null;

fn apparatusHasUnchecked() bool {
    for (apparatus_declared) |e| if (config.apparatusUnchecked(e)) return true;
    return false;
}

/// The few errno values a snapshot refusal is likely to carry, spelled the way `man 2
/// open` spells them, so the operator does not have to look the number up; anything
/// else stays a number. Not `@errorName`: that would tie a message to a Zig identifier.
pub fn errnoName(en: c_int) []const u8 {
    if (en == posix.EACCES) return " EACCES";
    if (en == posix.EPERM) return " EPERM";
    if (en == posix.ENOENT) return " ENOENT";
    if (en == posix.EIO) return " EIO";
    if (en == posix.ELOOP) return " ELOOP";
    return "";
}

/// What the operator is told, beyond which snapshot failed.
///
/// Sentences rather than error names: `@errorName` appears nowhere in this codebase, and
/// `ClassifyFailed` tells an operator nothing. It would also tie an acceptance leg's text
/// to a Zig identifier, so a rename would redden the suite for no behavioural reason.
///
/// The two failures with a limit behind them report it, because a limit is something the
/// operator can act on — the same reason the cap names its own. The rest do not have one.
///
/// **Typed to `SnapshotError`, with no `else`, on purpose.** Taking `anyerror` and
/// defaulting to `what` would compile cleanly when a member is added to that error set,
/// and the new member would then produce the bare call-site wording — the pre-#351
/// behaviour this function exists to remove — while still being classified
/// `state_unsnapshotable` whether or not that is the right reason for it. Exhaustiveness
/// turns that silent regression into a build failure — measured: deleting the `TooDeep`
/// arm now fails to compile, where before it left every check green and the message bare.
///
/// `OutOfMemory` is `unreachable` here rather than absent, which states the carve-out at
/// the point a reader meets the switch. **It does not enforce it**: deleting the guard
/// above still builds, and the arm would then be reached at run time on a real allocation
/// failure. Nothing in the tree can produce that, so the carve-out is unfalsified — said
/// here rather than left for someone to assume the type checked it.
pub fn snapshotDetail(ja: std.mem.Allocator, e: engine.SnapshotError, what: []const u8, diag: *engine.SnapshotDiag) []const u8 {
    return switch (e) {
        error.FileTooLarge => if (diag.file.size) |sz|
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} ({d} bytes, cap {d}); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel.get()), sz, engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment"
        else
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} (over the {d}-byte cap); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel.get()), engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment",
        // Says which of two things the numbers describe, because they are the prefix the
        // walk had read when the ceiling broke and not the tree — `TreeTooLargeDiag`
        // records why the honest answer is to point at `du`/`find` rather than to keep
        // walking for the real figures. No entry name appears: the walk stops at whatever
        // `readdir` happened to reach, so a "largest so far" would be a different name on
        // a different filesystem.
        error.TreeTooLarge => std.fmt.allocPrint(ja, "the state tree is too large to snapshot: holding it reached {d} bytes of memory against a {d}-byte ceiling, after reading {d} bytes of content across {d} entries; the walk stopped there, so those count what was read and not the tree — `du -sb <state>` and `find <state> -mindepth 1 | wc -l` show the whole of it", .{ diag.tree.reached, engine.max_state_tree_bytes, diag.tree.content, diag.tree.entries }) catch "the state tree is too large to snapshot",
        // "deeper than", not "cap": the walk compares with a strict `>`, so a tree of
        // exactly this many levels passes and the next one does not.
        error.TooDeep => std.fmt.allocPrint(ja, "{s}: the state tree is nested deeper than the {d} levels the snapshot walks", .{ what, engine.max_depth }) catch what,
        // The buffer holds the state root, a separator and the entry's relative path, so
        // a long `--state` prefix reaches this with a short name inside the tree — saying
        // "a path inside the state tree" would send the operator to look at the wrong
        // half. And the bound is on the whole spelling INCLUDING its terminator, so a
        // path of exactly this many bytes already fails: "at least", not "longer than",
        // for the same reason `max_depth`'s message says "deeper than" and not "cap".
        error.PathTooLong => std.fmt.allocPrint(ja, "{s}: the state root and an entry inside it spell a path of at least {d} bytes, which is the limit the snapshot can hold", .{ what, contract.max_path }) catch what,
        // The entry is named when the walk recorded it (#535) — always, on the paths that
        // reach here — and the errno only when a call actually failed with one:
        // `readWholeDiag` leaves it null for a descriptor that was not a regular file.
        error.ReadFailed => blk: {
            const rel = diag.entry.rel.get();
            if (rel.len == 0) break :blk std.fmt.allocPrint(ja, "{s}: a file or symlink inside the state tree could not be read", .{what}) catch what;
            const kind: []const u8 = if (diag.entry.kind == .symlink) "symlink" else "file";
            if (diag.entry.errno) |en| {
                break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be read ({s}; errno {d}{s})", .{ what, textShown(ja, rel), kind, en, errnoName(en) }) catch what;
            }
            break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be read ({s})", .{ what, textShown(ja, rel), kind }) catch what;
        },
        error.ClassifyFailed => blk: {
            const rel = diag.entry.rel.get();
            if (rel.len == 0) break :blk std.fmt.allocPrint(ja, "{s}: an entry inside the state tree could not be classified as a file, directory or symlink", .{what}) catch what;
            break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be classified as a file, directory or symlink", .{ what, textShown(ja, rel) }) catch what;
        },
        // Not the operator's tree. Say so, or they go looking through their own files for
        // a broken invariant of ours.
        error.EntriesNotSortedUnique => std.fmt.allocPrint(ja, "{s}: the snapshot's own entry list came out unsorted or holding duplicates — that is a defect in sideeye, not in the state tree", .{what}) catch what,
        // Refused above, before this function is called. If that guard goes, this stops
        // being unreachable and the compiler says so.
        error.OutOfMemory => unreachable,
    };
}

/// A clause for a status of 126 from any child the engine forked: since 2026-09-08 that
/// is also the code `posix.childArrangeFailed` exits with when `setpgid` or a `dup2`
/// failed in the child before `exec`, and the child says which on the engine's stderr.
/// Empty for every other status, so the sentence a caller already prints is unchanged.
pub fn exit126Note(code: anytype) []const u8 {
    return if (code == 126) "; 126 is also the code the engine's own fork stub uses for a child it could not arrange before exec — if that was it, a line on the engine's stderr names the call and the errno" else "";
}

test "exit126Note speaks only for 126" {
    try std.testing.expectEqualStrings("", exit126Note(@as(u8, 1)));
    try std.testing.expectEqualStrings("", exit126Note(@as(u8, 127)));
    try std.testing.expect(std.mem.startsWith(u8, exit126Note(@as(u8, 126)), "; 126 is also the code"));
}

/// The longest run of a target's own bytes that reaches `message`: a setup writing one
/// 8 KiB line must not push the status and the path it is quoted beside out of view.
///
/// **Counted before defanging, not after.** The whole sentence goes through
/// `sanitizeForReport`, which spells a defanged byte `\xNN` — four characters for one —
/// so a line of 200 control bytes reaches the report as 800. That is bounded and it is
/// arena-allocated rather than written into a fixed buffer, so nothing overflows; it is
/// only not the same number, and saying "clipped to 200 bytes" of the *output* would be
/// wrong. `textShown`'s one-`?`-per-unit spelling does hold that stronger property, and
/// it is the right choice where a fixed buffer is downstream — here the single choke
/// point at the end matters more (two spellings of a defanged byte in one sentence is
/// what per-field sanitising produced).
const setup_line_max: usize = 200;

/// Backing store for the out-of-memory sentence in `setupOutputDetail`, at file scope
/// because that sentence outlives the call that builds it.
var setup_oom_buf: [contract.max_path + 64]u8 = undefined;

/// The clause a SETUP_ERROR adds about what the failing `--setup` wrote (#483).
///
/// Three answers, never two. The issue's complaint is that the observation "is not merely
/// unreported; it is gone", and collapsing "could not read it back" into "wrote nothing"
/// would put a second, quieter version of that same loss into the fix: the run would
/// assert something about a file it failed to open. `snapshotRefusal`'s neighbour at the
/// falsification gate says a capture it cannot read back out loud for the same reason.
///
/// Sanitised once at the end, like `unresolvedDetail` and `withOracleCapture` in
/// `boundary.zig`, rather than per field — and it is needed here more than there, because
/// `setupError` prints its detail through `say` with no defang of its own, and every byte of the line
/// is the target's. One choke point also means one spelling: `textShown` per field and
/// `sanitizeForReport` at the end defang differently, so mixing them put two renderings of
/// a control byte in the same sentence.
///
/// The ellipsis is derived from what the cut returned rather than from a second comparison
/// against `setup_line_max`, so the mark cannot disagree with the cut.
pub fn setupOutputDetail(arena: std.mem.Allocator, path: []const u8) []const u8 {
    // Every `catch` below lands here rather than on `""`. An exhausted arena would
    // otherwise turn the refusal back into the bare `--setup exited 7` this issue is
    // about, and it would do it silently — the one failure mode where saying less looks
    // exactly like a version that was never fixed. `unresolvedDetail` takes a fallback
    // sentence for the same reason.
    // Names the file even here: "the refusal names that file" is the half of the promise
    // an exhausted arena cannot take away, since the path is the caller's and this only
    // has to copy it.
    //
    // The buffer is at file scope, and that is the whole point of it being there. A first
    // version declared it here, which returns a slice of this function's frame to a caller
    // that reads it after the frame is gone — the exact shape `unresolved_kind.withFd`'s
    // doc warns about two files away, written the same day. Safe as a global because every
    // reader of the result is on the way to `setupError`, which is `noreturn`: there is no
    // second refusal to overwrite it, and no thread that could be composing another.
    const oom = std.fmt.bufPrint(
        &setup_oom_buf,
        "; what it wrote could not be described (out of memory); the capture is at {s}",
        .{path},
    ) catch "; what it wrote could not be described (out of memory)";
    const composed = switch (capture.readSetupCapture(arena, path)) {
        .unreadable => std.fmt.allocPrint(arena, "; its output could not be read back from {s}", .{path}) catch return oom,
        .empty => blk: {
            // Nothing was written, so there is nothing for the file to hold and no reason
            // for the sentence to name it. Removed here because this is the only place
            // that knows: `setupErrorFmt` never returns, so the failing path has no line
            // after this one, and the MCP adapter hands every call the same `--work` —
            // zero-byte pid-named files would accumulate there without bound.
            removeFile(path);
            break :blk "; it wrote nothing";
        },
        .line => |l| blk: {
            const cut = mcp.cutOnBoundary(l, setup_line_max);
            break :blk std.fmt.allocPrint(
                arena,
                "; its last output line was: {s}{s} (all of it is in {s})",
                .{ cut, if (cut.len < l.len) "..." else "", path },
            ) catch return oom;
        },
    };
    return sanitizeForReport(arena, composed) catch oom;
}

test "setupOutputDetail separates read failure, empty output, and a line — and defangs it (#483)" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var pb: [contract.max_path]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-setupout-{d}.txt", .{posix.getpid()}) catch unreachable;
    defer removeFile(path);

    // A file that is not there is not an empty file. Saying "wrote nothing" here would
    // repeat #483's own defect inside its fix.
    removeFile(path);
    const missing = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, missing, "could not be read back") != null);
    try t.expect(std.mem.indexOf(u8, missing, "wrote nothing") == null);

    try t.expect(writeWholeFile(path, &.{""}));
    const empty = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, empty, "wrote nothing") != null);
    try t.expect(std.mem.indexOf(u8, empty, "could not be read back") == null);
    // An empty capture is removed rather than named: nothing to hold, nothing to point at.
    try t.expect(capture.readSetupCapture(arena, path) == .unreadable);

    // The line the operator needs, and the file for the rest of it.
    try t.expect(writeWholeFile(path, &.{"opening\nthe setup could not find its input\n"}));
    const line = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, line, "the setup could not find its input") != null);
    try t.expect(std.mem.indexOf(u8, line, "all of it is in") != null);

    // A target that tries to forge a report line is the reason the sentence goes through
    // `sanitizeForReport`: `setupError` hands its detail straight to `say`.
    //
    // The control bytes are asserted, not the newline. A first version of this test wrote
    // `"x\nUNKNOWN  kill_did_not_land\n"` and checked that `"\nUNKNOWN"` was absent — but
    // `lastNonEmptyLine` splits on `'\n'`, so no return value of it can ever contain one.
    // That assertion held with `textShown` deleted outright (measured), which makes it a
    // check on the splitter rather than on the defang. ESC and CR survive the split, so
    // they are what proves the defang ran; the `foreignTouchDetail` test (in `boundary.zig`
    // since #572) has used ESC for the same reason since #484.
    try t.expect(writeWholeFile(path, &.{"safe\n\x1b[1mUNKNOWN  kill_did_not_land\rmore\n"}));
    const forged = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOfScalar(u8, forged, 0x1b) == null);
    try t.expect(std.mem.indexOfScalar(u8, forged, '\r') == null);
    try t.expect(std.mem.indexOf(u8, forged, "\nUNKNOWN") == null);
    // The line is still quoted — defanging must not silently drop the observation, which
    // is the whole point of #483.
    try t.expect(std.mem.indexOf(u8, forged, "kill_did_not_land") != null);

    // The clamp counts the target's bytes, and defanging spells each removed one `\xNN`.
    // A line of control bytes therefore reaches the report longer than the cap -- bounded
    // and arena-allocated, but not the same number, which is why the constant's doc says
    // "before defanging". Pinned so that swapping the choke point back to a one-`?`
    // spelling cannot silently change what the constant means.
    const ctrl = "\x01" ** (setup_line_max + 20);
    try t.expect(writeWholeFile(path, &.{ctrl}));
    const defanged = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOfScalar(u8, defanged, 0x01) == null);
    try t.expect(std.mem.indexOf(u8, defanged, "\\x01") != null);
    try t.expect(defanged.len > setup_line_max);

    // Longer than the cap: clamped, marked, and the file still named.
    const long = "E" ** (setup_line_max + 50);
    try t.expect(writeWholeFile(path, &.{long}));
    const clamped = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, clamped, "...") != null);
    // Not `clamped.len < long.len`: the sentence carries a prefix and the file's path as
    // well, so its total length says nothing about whether the line was cut. What the
    // clamp promises is that the whole line is not in there.
    try t.expect(std.mem.indexOf(u8, clamped, long) == null);
    try t.expect(std.mem.indexOf(u8, clamped, "E" ** setup_line_max) != null);

    // The same reader the success path deletes on. It has to agree with the sentences
    // above about what "nothing" means, or a setup would be told it wrote nothing while
    // its file was kept (or the reverse).
    try t.expect(writeWholeFile(path, &.{""}));
    try t.expect(capture.readSetupCapture(arena, path) == .empty);
    try t.expect(writeWholeFile(path, &.{"\n \n"}));
    try t.expect(capture.readSetupCapture(arena, path) == .empty);
    try t.expect(writeWholeFile(path, &.{"using a stale fixture\n"}));
    try t.expectEqualStrings("using a stale fixture", capture.readSetupCapture(arena, path).line);
    // A capture that cannot be read is not an empty one: deleting it would destroy the
    // only copy of an output the engine failed to see.
    removeFile(path);
    try t.expect(capture.readSetupCapture(arena, path) == .unreadable);

    // The out-of-memory sentence, through an allocator that refuses. It still names the
    // file, and — the reason the buffer moved to file scope — the bytes are still there
    // to read after the call that built them has returned. A stack-local buffer makes
    // this a read of a dead frame, which no assertion can be relied on to catch: the
    // check that matters is that the sentence survives the return at all.
    try t.expect(writeWholeFile(path, &.{"something"}));
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const starved = setupOutputDetail(failing.allocator(), path);
    try t.expect(std.mem.indexOf(u8, starved, "out of memory") != null);
    try t.expect(std.mem.indexOf(u8, starved, path) != null);
    // Read again after another call has had the chance to reuse the frame.
    var failing2 = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    _ = setupOutputDetail(failing2.allocator(), path);
    try t.expect(std.mem.indexOf(u8, starved, "out of memory") != null);
    // Naming the buffer is the assertion. Moving it back into `setupOutputDetail` — the
    // defect this test exists for — stops compiling here rather than failing at run time,
    // which matters because the run-time failure is undefined behaviour: restoring the
    // stack-local version and running the suite was measured green. A test that can only
    // observe the bug by luck is not what pins it; the reference is.
    try t.expect(std.mem.indexOf(u8, &setup_oom_buf, "out of memory") != null);
    try t.expect(std.mem.indexOf(u8, &setup_oom_buf, path) != null);

    // A capture that is a directory is not a capture. `require_regular` is what makes
    // this the read-failure branch rather than a read that returns nothing.
    removeFile(path);
    var db: [contract.max_path]u8 = undefined;
    const dz = try std.fmt.bufPrintZ(&db, "{s}", .{path});
    try t.expect(posix.mkdir(dz.ptr, @as(c_uint, 0o755)) == 0);
    defer _ = posix.rmdir(dz.ptr);
    const dir = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, dir, "could not be read back") != null);
}

/// One sentence naming which form judged which files. Counts and names come from the
/// same L0Plan the judgement reads (ADR 0004), so the report cannot describe a
/// different classification than the one that ran. Names are bounded — the point is
/// "which files got the weaker claim", not an inventory.
pub fn buildL0Note(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
    const base = buildL0NoteBase(arena, plan);
    if (plan.scratch.len == 0) return base;
    // ADR 0043: the declaration and its reach, read from the same plan the judge read.
    // The count is recorded paths the declaration matched (before or after), so a reader
    // can tell a declaration that reached something from one that named nothing the
    // recording had; the names are the declaration itself, bounded like the history names.
    var names: std.ArrayList(u8) = .empty;
    var listed: u32 = 0;
    for (plan.scratch) |p| {
        if (listed == 3) break;
        if (listed > 0) names.appendSlice(arena, ", ") catch return base;
        appendSanitized(&names, arena, p) catch return base;
        listed += 1;
    }
    if (plan.scratch.len > listed) {
        const more = std.fmt.allocPrint(arena, " (+{d} more)", .{plan.scratch.len - listed}) catch return base;
        names.appendSlice(arena, more) catch return base;
    }
    return std.fmt.allocPrint(arena, "{s}; {d} path(s) matched by scratch, not judged (declared: {s})", .{ base, plan.scratch_matched, names.items }) catch base;
}

/// Publish the judged set as data (#638, ADR 0079), from the same plan `buildL0Note` counts
/// and `judgeL0` walks.
///
/// **The plan is the only argument, and that is the design.** The set is not "the post
/// snapshot minus scratch": `classifyWith` keeps a path only where pre and post BOTH hold it
/// and both kinds are ones the built-in invariants compare. A projection handed a snapshot
/// could quietly answer the wrong question; one handed the plan cannot reach a snapshot to
/// get it wrong (`rules/memory` calls this preferring impossible over detected).
///
/// The paths are duped into the caller's arena rather than borrowed. `PlannedFile.rel`
/// borrows from the pre snapshot, which `main` frees on a defer of its own; the report is
/// built before that today, and this removes the coupling rather than relying on it.
pub fn publishJudgedPaths(arena: std.mem.Allocator, plan: engine.L0Plan) void {
    l0_classified = true;
    const total = plan.files.items.len;
    // Both ceilings, whichever binds first, decided before anything is allocated so the
    // array's length and the omitted count are two readings of one number.
    var listed: usize = 0;
    var bytes: usize = 0;
    while (listed < total and listed < max_judged_paths_listed) : (listed += 1) {
        const next = bytes + plan.files.items[listed].rel.len;
        if (next > max_judged_paths_bytes) break;
        bytes = next;
    }
    // An allocation failure must not turn into a silent lie. The count stays true and every
    // path reads as one this report did not name, which is exactly what happened.
    const out = arena.alloc([]const u8, listed) catch return omitAll(total);
    for (out, plan.files.items[0..listed]) |*slot, f| {
        slot.* = arena.dupe(u8, f.rel) catch return omitAll(total);
    }
    l0_judged_paths = out;
    l0_judged_paths_omitted = countedOmitted(total - listed);
}

fn omitAll(total: usize) void {
    l0_judged_paths = &.{};
    l0_judged_paths_omitted = countedOmitted(total);
}

/// Saturating rather than `@intCast`: the field is a count a reader compares against zero,
/// and a tree wide enough to overflow it would take the report down with a panic instead.
fn countedOmitted(n: usize) u32 {
    return if (n > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(n);
}

fn buildL0NoteBase(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
    const standard = plan.files.items.len - @as(usize, plan.history_count);
    if (plan.history_count == 0) {
        // "path(s)", not "file(s)": since #122 the judged pairs include symlinks and
        // kind-changed pairs, and a stow-shaped PASS would otherwise claim to have
        // judged N files over a directory holding none.
        return std.fmt.allocPrint(arena, "{d} path(s) judged pre-or-post", .{standard}) catch "classified";
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
        "{d} path(s) judged pre-or-post; {d} file(s) judged by the history form (appended tails not judged): {s}",
        .{ standard, plan.history_count, names.items },
    ) catch "classified";
}

/// The `not tested` list is not constant: whenever any file was judged by the history
/// form, its appended tail joined the untested set, and a PASS headline must not
/// stand without that narrowing beside it.
///
/// **One definition, two renderings** (#280). Both reports carry this list, and
/// `DESIGN.md` §13's binding rule is that a value both forms carry has one definition.
/// This one had two: hand-written functions holding the same four cases twice, with the
/// JSON side escaping its quotes by hand, and nothing holding them together. Both are
/// built at comptime from the items below now, so adding one puts it in both renderings
/// and there is no way to edit one side alone.
///
/// Comptime rather than a runtime join, deliberately: the old functions returned static
/// strings and allocate nothing, and **four of the five** call sites are inside format
/// strings where an allocation failure has nowhere to go. The tables cost nothing at
/// runtime and keep the output the same bytes it was.
const not_tested_always = [_][]const u8{ "power loss", "torn writes", "concurrent processes" };
const not_tested_history = "appended tails (files under the history form)";
const not_tested_l1 = "post-only file contents (L1 checks existence only; post-only link targets are judged)";
const not_tested_scratch = "declared scratch paths (neither bytes nor presence judged)";

/// The conditions that widen the list, in bit order: bit i of the variant is condition i.
/// One list binds the three tables AND `notTestedVariant` below, which derives its bits
/// from this length — the comment that used to sit on `not_tested_bits` said binding the
/// variant too was "one condition away from being worth it", and `scratch` (ADR 0043) is
/// that condition. Adding an item here without a predicate in `notTestedCondition` is a
/// compile error, not an out-of-range read.
const not_tested_conditions = [_][]const u8{ not_tested_history, not_tested_l1, not_tested_scratch };
const not_tested_variants = 1 << not_tested_conditions.len;

/// Whether a list item could not be placed into JSON by quoting it and nothing else.
/// Separated from the guard below so it can be tested: `@compileError` cannot be
/// exercised from a test, but the predicate that decides it can.
///
/// Invalid UTF-8 counts, and that clause came from review: `jsonString` rewrites it to
/// U+FFFD, with a comment recording that the raw bytes give "a file that jq, Python and
/// Go all refuse". A `\xNN` escape in a Zig literal reaches this directly, so without
/// this clause an item could build clean and ship a JSON document no parser accepts --
/// measured, before the clause existed.
fn notTestedNeedsEscaping(s: []const u8) bool {
    for (s) |c| if (c == '"' or c == '\\' or c < 0x20) return true;
    return !std.unicode.utf8ValidateSlice(s);
}

// The JSON rendering quotes each item and does nothing else, which is correct only while
// no item contains a quote, a backslash or a control byte. Rather than carry a second
// escaper beside `jsonString` -- one that could drift from it in silence -- an item that
// would need one fails the build, and "escaping" here includes invalid UTF-8, which
// `jsonString` also rewrites. Seen red by giving an item a quote and reading
// the failure: "not-tested item needs JSON escaping: appended \"tails\" ...".
comptime {
    for (not_tested_always) |item| {
        if (notTestedNeedsEscaping(item)) @compileError("not-tested item needs JSON escaping: " ++ item);
    }
    for (not_tested_conditions) |item| {
        if (notTestedNeedsEscaping(item)) @compileError("not-tested item needs JSON escaping: " ++ item);
    }
}

/// The list for one variant, indexed the way `notTestedVariant` indexes them: bit i of
/// the variant appends condition i, in list order.
fn notTestedList(comptime variant: usize) []const []const u8 {
    comptime {
        var out: []const []const u8 = &not_tested_always;
        for (not_tested_conditions, 0..) |item, i| {
            if (variant & (@as(usize, 1) << i) != 0) out = out ++ [_][]const u8{item};
        }
        return out;
    }
}

/// Both renderings, from one walk of one list: `", "` between items either way, and the
/// JSON form adds the brackets and the quotes. The separator is written once here rather
/// than in two functions, which is the whole point.
fn notTestedJoined(comptime variant: usize, comptime quoted: bool) []const u8 {
    comptime {
        var out: []const u8 = if (quoted) "[" else "";
        for (notTestedList(variant), 0..) |item, i| {
            if (i != 0) out = out ++ ", ";
            out = out ++ if (quoted) "\"" ++ item ++ "\"" else item;
        }
        return out ++ if (quoted) "]" else "";
    }
}

// The three tables, one row per variant, every row built from the one list above: the
// width is derived from the conditions' count, so a condition added there widens all
// three here and there is no second constant to keep in step.
const not_tested_items_by_variant = blk: {
    var t: [not_tested_variants][]const []const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedList(v);
    break :blk t;
};
const not_tested_text_by_variant = blk: {
    var t: [not_tested_variants][]const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedJoined(v, false);
    break :blk t;
};
const not_tested_json_by_variant = blk: {
    var t: [not_tested_variants][]const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedJoined(v, true);
    break :blk t;
};

/// The run-time predicate for condition i of `not_tested_conditions`, by index. `i` is
/// comptime (the caller unrolls over the list), so a condition without a predicate here
/// is a compile error — the binding the table's old comment said was one condition away.
fn notTestedCondition(comptime i: usize) bool {
    return switch (i) {
        0 => l0_history_count > 0,
        1 => l1_configured,
        2 => scratch_declared.len > 0,
        else => @compileError("a not-tested condition was added to the list without a predicate here"),
    };
}

/// Bit i is condition i -- read once, so the two renderings cannot disagree about which
/// list this run is even describing.
fn notTestedVariant() usize {
    var v: usize = 0;
    inline for (0..not_tested_conditions.len) |i| {
        if (notTestedCondition(i)) v |= @as(usize, 1) << i;
    }
    return v;
}

pub fn notTestedText() []const u8 {
    return not_tested_text_by_variant[notTestedVariant()];
}

fn notTestedJson() []const u8 {
    return not_tested_json_by_variant[notTestedVariant()];
}

/// The text form of the declaration (ADR 0043): the entries as declared, comma-separated,
/// neutralised the way every target-chosen path in the text report is.
pub fn scratchNote(arena: std.mem.Allocator) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (scratch_declared, 0..) |e, i| {
        if (i > 0) out.appendSlice(arena, ", ") catch return "(allocation failed)";
        out.appendSlice(arena, textShown(arena, e)) catch return "(allocation failed)";
    }
    return out.items;
}

test "the report names where the define's commands ran, and whether that was declared, only once it is known (#647)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const saved_cwd = command_cwd;
    const saved_decl = command_cwd_declared;
    defer {
        command_cwd = saved_cwd;
        command_cwd_declared = saved_decl;
    }

    // Before phase 0 has resolved the `cwd` — a config or `cwd`-vet refusal — neither field.
    command_cwd = null;
    const before = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .define_invalid, "m", null);
    try std.testing.expect(std.mem.indexOf(u8, before, "command_cwd") == null);

    // Declared: the resolved path, and `true`.
    command_cwd = "/tmp/proj";
    command_cwd_declared = true;
    const decl = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, decl, "\n  \"command_cwd\": \"/tmp/proj\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, decl, "\n  \"command_cwd_declared\": true") != null);

    // Undeclared: Sideeye's own directory is still a directory the commands ran in, so the
    // path is there — `false` is what says it was nobody's choice.
    command_cwd = "/home/runner/work";
    command_cwd_declared = false;
    const own = try buildJson(a, "UNKNOWN", 2, null, null, "recording_run_failed", null, "m", "Do this.");
    try std.testing.expect(std.mem.indexOf(u8, own, "\n  \"command_cwd\": \"/home/runner/work\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, own, "\n  \"command_cwd_declared\": false") != null);

    // A SETUP ERROR raised after the `cwd` was resolved carries it: its text is one line by
    // design, and the JSON is where the directory still has to be.
    const after = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "m", null);
    try std.testing.expect(std.mem.indexOf(u8, after, "\"command_cwd\"") != null);

    // Escaped through the JSON writer, not written raw: a control byte in a directory name
    // must not reach the report as itself.
    command_cwd = "/tmp/a\nb";
    const esc = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, esc, "/tmp/a\\nb") != null);
    try std.testing.expect(std.mem.indexOf(u8, esc, "/tmp/a\nb") == null);
}

test "a SETUP_ERROR report carries its class, and the setup's status only under setup_failed and only as measured (#518)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const saved = setup_status;
    defer setup_status = saved;

    setup_status = .{ .exited = 7 };
    const exited = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup exited 7", null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "\n  \"setup_error_reason\": \"setup_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "\n  \"setup_exit_code\": 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "setup_signal") == null);
    // The class comes right after the other closed set's slot and before the message.
    try std.testing.expect(std.mem.indexOf(u8, exited, "\"setup_error_reason\"").? < std.mem.indexOf(u8, exited, "\"message\"").?);

    setup_status = .{ .signaled = 9 };
    const killed = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup was killed by signal 9", null);
    try std.testing.expect(std.mem.indexOf(u8, killed, "\n  \"setup_signal\": 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, killed, "setup_exit_code") == null);

    // A status waitpid did not decode: the class, and no number nobody decoded.
    setup_status = .{ .unknown = 0x1234 };
    const undecoded = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup ended in a way waitpid reported as status 4660", null);
    try std.testing.expect(std.mem.indexOf(u8, undecoded, "\"setup_error_reason\": \"setup_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, undecoded, "setup_exit_code") == null and std.mem.indexOf(u8, undecoded, "setup_signal") == null);

    // A status left behind by an earlier arm never reaches another class, nor a verdict
    // that carries no class at all.
    setup_status = .{ .exited = 7 };
    const env = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .environment, "out of memory", null);
    try std.testing.expect(std.mem.indexOf(u8, env, "\"setup_error_reason\": \"environment\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, env, "setup_exit_code") == null);
    const unk = try buildJson(a, "UNKNOWN", 2, null, null, "no_shim_marker", null, "m", "Do this.");
    try std.testing.expect(std.mem.indexOf(u8, unk, "setup_error_reason") == null and std.mem.indexOf(u8, unk, "setup_exit_code") == null);
    const pass = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, pass, "setup_") == null);
}

/// The text report's apparatus line, in the calling block's own style, only when
/// something was declared.
pub fn sayApparatus(arena: std.mem.Allocator, comptime fmt: []const u8) void {
    if (apparatus_declared.len > 0) say(fmt, .{apparatusNote(arena)});
}

/// #706 (ADR 0095): a sentence per string-form command the define spelled for a shell, set by
/// `phaseDefine` from `config.shellWarnings`; empty for a replay. Carried by the verdict blocks'
/// `warning` lines, JSON `define_warnings` and MCP's summary, and written to stderr once at the
/// end (`emitWarnings`) so a run that ends in a SETUP ERROR or a preflight report shows it too.
pub var define_warnings: []const []const u8 = &.{};
var warnings_emitted = false;

/// The text report's warning lines, one per warning, in the calling block's own style.
pub fn sayWarnings(comptime fmt: []const u8) void {
    for (define_warnings) |w| say(fmt, .{w});
}

/// Each warning once, on stderr, as `sideeye: warning: …`. At the end and not when the define is
/// read, for the seal's reason (below): a reader of merged output who takes its first line must
/// still find the verdict there (`docs/cli.md`). Called by `emitSeal`, which every exit after a
/// report reaches — preflight's two own exits included since #717, which seal only under
/// `--json`.
pub fn emitWarnings() void {
    if (warnings_emitted) return;
    warnings_emitted = true;
    const prefix = "sideeye: warning: ";
    for (define_warnings) |w| {
        _ = posix.write(2, prefix.ptr, prefix.len);
        _ = posix.write(2, w.ptr, w.len);
        _ = posix.write(2, "\n", 1);
    }
}

/// The text report's recovery line, in the calling block's own style, only when a recovery was
/// declared, read from the variable the JSON field reads. Printed where the apparatus line is —
/// the verdict blocks and UNKNOWN's — and, like it, not on SETUP ERROR's text, whose JSON still
/// carries the field.
pub fn sayRecovery(comptime fmt: []const u8) void {
    if (recovery_note) |rn| say(fmt, .{rn});
}

/// The text report's `cwd` line (#647), in the calling block's own style, read from the
/// variable the JSON field reads. Printed in every block that prints `expected` — UNKNOWN,
/// FAIL and PASS — and in `preflight`'s report; like `sayRecovery`,
/// not on SETUP ERROR's one-line text, whose JSON still carries the field. Nothing is printed
/// while `command_cwd` is unset, which is every report raised before the `cwd` is resolved.
///
/// In the UNKNOWN block it sits under `next` — below `divergence` when there is one: that is
/// where a reader of `recording_run_failed` already is. Placed with `expected` further down, the line
/// would exist and not be read — the detail sends the reader to `--expect-status` and `next`
/// sends them back to the detail before either reaches it.
///
/// The label is `cwd`, the key the reader would add to the toml, and an undeclared one says
/// so. Defanged: a declared `cwd` arrives from a config or a case file, outside the trust
/// boundary, and a control byte in a directory name would otherwise forge a report line.
pub fn sayCwd(arena: std.mem.Allocator, comptime fmt: []const u8) void {
    if (command_cwd) |c| say(fmt, .{ defang.textShown(arena, c), if (command_cwd_declared) "" else "  (none declared: Sideeye's own)" });
}

/// A value single-quoted for a POSIX shell, the whole escape: every byte stands for itself
/// inside `'…'`, and a `'` closes the quote, is written escaped, and reopens it.
pub fn shellQuote(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '\'');
    for (s) |ch| {
        if (ch == '\'') try out.appendSlice(arena, "'\\''") else try out.append(arena, ch);
    }
    try out.append(arena, '\'');
    return out.items;
}

/// One word of a command line a reader pastes (#711): the value as it is when every byte is one
/// a shell reads literally in an unquoted word, `shellQuote`d otherwise — so an ordinary path
/// prints exactly as it always did, and one holding a space, a quote or a `$` still pastes as one
/// argument. The set leaves out `=`, which would make a first word an assignment and which zsh
/// (macOS's shell) expands at the start of a word, `~`, `*`, `?` and the brackets, which a shell
/// expands, and everything a shell splits or redirects on; an empty value is `''`, which a bare
/// word cannot spell.
pub fn shellWord(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    if (s.len == 0) return shellQuote(arena, s);
    for (s) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and std.mem.indexOfScalar(u8, "_./:@%+,-", ch) == null)
            return shellQuote(arena, s);
    }
    return s;
}

test "a shell word is the value itself unless a shell would read it otherwise (#711)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("/tmp/se/work/cases/000001.json", try shellWord(a, "/tmp/se/work/cases/000001.json"));
    try std.testing.expectEqualStrings("'/tmp/a b/c'", try shellWord(a, "/tmp/a b/c"));
    try std.testing.expectEqualStrings("''", try shellWord(a, ""));
    try std.testing.expectEqualStrings("'NAME=x'", try shellWord(a, "NAME=x"));
    try std.testing.expectEqualStrings("'it'\\''s'", try shellWord(a, "it's"));
    try std.testing.expectEqualStrings("'$HOME'", try shellWord(a, "$HOME"));
    try std.testing.expectEqualStrings("'~/x'", try shellWord(a, "~/x"));
}

/// The text report's `evidence` value (#709): the command that renders the bundle, which a
/// reader pastes, rather than the bundle's path alone — the JSON field keeps the path
/// (`docs/report-schema.md`), and the path is the command's argument, so nothing the text said
/// is lost. `-` stays `-`: a bundle that was not written names no command.
pub fn evidenceCommand(arena: std.mem.Allocator, bundle: []const u8) []const u8 {
    if (std.mem.eql(u8, bundle, "-")) return bundle;
    const word = shellWord(arena, bundle) catch return bundle;
    return std.fmt.allocPrint(arena, "sideeye evidence {s}", .{word}) catch bundle;
}

/// What a FAIL's `reproduce` line is made of (#711): the values the engine hands a world, so a
/// pasted line runs the operation the way a world did — except two kinds, which belong to a
/// world's own process group and cgroup and which a pasted line runs in neither of. The cgroup
/// ones are pinned empty, as the engine pins them for a recording: the shim reads empty as none,
/// and a value left in the reader's shell from an earlier run would otherwise be read.
/// `SIDEEYE_KILL_GROUP` is **unset** in the line's subshell, not pinned: the shim reads its
/// presence, not its value, and with it the kill takes the reader's own shell down with the target
/// (measured twice — see the FAIL block in `main.zig`; the second time was this line's first
/// version, which pinned it empty and killed the acceptance suite's own shell). `TOY_STATE` is not
/// carried: it is the demo toy's own name for the state directory, which the toy reads
/// `SIDEEYE_STATE_DIR` for when it is unset, and printing it would hide whether the line's
/// `SIDEEYE_STATE_DIR_ALT` reaches the shim (acceptance check 2m spells the state its own way).
pub const Reproduce = struct {
    cwd: ?[]const u8,
    state: []const u8,
    /// Only when it is a different spelling from `state`; pinned empty otherwise.
    state_alt: ?[]const u8,
    trace: []const u8,
    preload_var: []const u8,
    shim: []const u8,
    kill_at: usize,
    /// The observation mode's name: without `SIDEEYE_OBSERVE=syscalls` the shim counts the
    /// default way, and under that mode the kill lands on another operation (measured).
    observe: []const u8,
    argv: []const []const u8,
};

/// A FAIL's `reproduce` line (#711): a command that runs as printed in a POSIX shell once the
/// define's setup has left the state it starts from. In a subshell, so the reader's own shell
/// stays where it was: `cd` to the directory the commands ran in, the world's variables, the
/// operation's own argv — each word through `shellWord`, and a bare first word quoted too, so an
/// alias of the same name in an interactive shell is not what runs — and standard input from
/// `/dev/null`, which is where every command Sideeye runs reads it (`docs/cli.md`).
///
/// It used to end in the placeholder `<operation>`, and still does, with no `cd`, when the line
/// cannot be printed as a command that means the same run: the argv or the directory holds a
/// byte the report defangs (printed raw it would let a define's bytes forge report lines,
/// printed defanged it would name another program or directory), Sideeye could not name the
/// directory, or the line would not fit the text report's output buffer, which drops a write
/// that overruns it.
pub fn reproduceLine(arena: std.mem.Allocator, r: Reproduce) error{OutOfMemory}![]const u8 {
    var env: std.ArrayList(u8) = .empty;
    try env.print(arena, "{s}={s} {s}={s}", .{
        contract.env.state_dir,     try shellWord(arena, r.state),
        contract.env.state_dir_alt, if (r.state_alt) |alt| try shellWord(arena, alt) else "",
    });
    try env.print(arena, " {s}={s} {s}={s} {s}={d} {s}= {s}={s} {s}= {s}= {s}=", .{
        contract.env.trace_path,  try shellWord(arena, r.trace),
        r.preload_var,            try shellWord(arena, r.shim),
        contract.env.kill_at,     r.kill_at,
        contract.env.seq_base,    contract.env.observe,
        r.observe,                contract.env.run_cgroup,
        contract.env.kill_cgroup, contract.env.kill_aside,
    });
    const as_command = blk: {
        const c = r.cwd orelse break :blk false;
        if (r.argv.len == 0 or !std.mem.eql(u8, defang.textShown(arena, c), c)) break :blk false;
        for (r.argv) |a| if (!std.mem.eql(u8, defang.textShown(arena, a), a)) break :blk false;
        break :blk true;
    };
    const placeholder = try std.fmt.allocPrint(arena, "{s} <operation>", .{env.items});
    if (!as_command) return placeholder;
    var out: std.ArrayList(u8) = .empty;
    // The trace emptied first: the shim numbers each operation from the highest number already in
    // it (v15), so a second paste into the same file would count from where the first stopped and
    // never reach k — the line ran to completion and said nothing (measured, #711's review).
    try out.print(arena, "(cd {s} && unset {s} && : > {s} && {s}", .{
        try shellWord(arena, r.cwd.?), contract.env.kill_group, try shellWord(arena, r.trace), env.items,
    });
    for (r.argv, 0..) |a, i| {
        const bare_name = i == 0 and std.mem.indexOfScalar(u8, a, '/') == null;
        try out.print(arena, " {s}", .{if (bare_name) try shellQuote(arena, a) else try shellWord(arena, a)});
    }
    try out.appendSlice(arena, " </dev/null)");
    // "reproduce   " and the newline beside it, inside the one write `say` makes of the line.
    if (out.items.len + 16 > say_capacity) return placeholder;
    return out.items;
}

test "the reproduce line is a command in a subshell, or keeps the placeholder when it cannot mean the same run (#711)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const pins = " SIDEEYE_RUN_CGROUP= SIDEEYE_KILL_CGROUP= SIDEEYE_KILL_ASIDE=";
    const base: Reproduce = .{
        .cwd = "/w d",
        .state = "/s",
        .state_alt = null,
        .trace = "/t/trace-repro.bin",
        .preload_var = "LD_PRELOAD",
        .shim = "/l/libsideeye_shim.so",
        .kill_at = 5,
        .observe = "wrappers",
        .argv = &.{ "/bin/toy", "rotate", "a b" },
    };
    try std.testing.expectEqualStrings(
        "(cd '/w d' && unset SIDEEYE_KILL_GROUP && : > /t/trace-repro.bin && SIDEEYE_STATE_DIR=/s SIDEEYE_STATE_DIR_ALT= SIDEEYE_TRACE_PATH=/t/trace-repro.bin LD_PRELOAD=/l/libsideeye_shim.so SIDEEYE_KILL_AT=5 SIDEEYE_SEQ_BASE= SIDEEYE_OBSERVE=wrappers" ++ pins ++ " /bin/toy rotate 'a b' </dev/null)",
        try reproduceLine(a, base),
    );
    var sys = base;
    sys.observe = "syscalls";
    sys.state_alt = "/link/s";
    sys.argv = &.{ "toy", "rotate" };
    try std.testing.expectEqualStrings(
        "(cd '/w d' && unset SIDEEYE_KILL_GROUP && : > /t/trace-repro.bin && SIDEEYE_STATE_DIR=/s SIDEEYE_STATE_DIR_ALT=/link/s SIDEEYE_TRACE_PATH=/t/trace-repro.bin LD_PRELOAD=/l/libsideeye_shim.so SIDEEYE_KILL_AT=5 SIDEEYE_SEQ_BASE= SIDEEYE_OBSERVE=syscalls" ++ pins ++ " 'toy' rotate </dev/null)",
        try reproduceLine(a, sys),
    );
    // The placeholder: a defanged byte in the argv or the directory, no directory, too long.
    var ctl = base;
    ctl.argv = &.{ "/bin/toy", "a\x01b" };
    var ctl_cwd = base;
    ctl_cwd.cwd = "/w\x1bd";
    var no_cwd = base;
    no_cwd.cwd = null;
    var long = base;
    const big = try a.alloc(u8, say_capacity);
    @memset(big, 'x');
    long.argv = &.{ "/bin/toy", big };
    for ([_]Reproduce{ ctl, ctl_cwd, no_cwd, long }) |r| {
        const line = try reproduceLine(a, r);
        try std.testing.expect(std.mem.startsWith(u8, line, "SIDEEYE_STATE_DIR=/s "));
        try std.testing.expect(std.mem.endsWith(u8, line, "SIDEEYE_KILL_ASIDE= <operation>"));
    }
    // Never an assignment of the group-kill variable, in either form: its presence alone arms it.
    for ([_]Reproduce{ base, sys, ctl, no_cwd }) |r|
        try std.testing.expect(std.mem.indexOf(u8, try reproduceLine(a, r), "SIDEEYE_KILL_GROUP=") == null);
}

/// Which verdict's text block `sayAccount` is printing for.
pub const AccountOf = enum { fail, pass, unknown };

/// The account lines the three verdict blocks share (#711): one order, one spelling, one
/// twelve-column key. They were three format strings — a FAIL's `key   value`, a PASS's
/// indented `key: value` in another order, an UNKNOWN's columns in a third — and every line
/// added since went into whichever block its change was about, so a reader comparing two
/// reports had to hunt for the same fact. One function is what keeps the next line from
/// drifting the same way.
///
/// The context lines come first, so that on an UNKNOWN they sit directly under `next`, where
/// ADR 0086 §2 put `cwd` (a line further down is not read); a blank line separates them from
/// the rest, as it always did on an UNKNOWN. Which lines each verdict prints is fixed here, not
/// at the call sites: a FAIL prints every one — `replay` and `evidence` even when they read
/// `-`, because a case that could not be saved says so rather than going quiet (ADR 0071); a
/// PASS every one but those two, which belong to a counterexample; an UNKNOWN the set it
/// printed before #711. `explored`, `oracle`, `metadata` and `checker` stay off it: a refusal
/// raised before the exploration would print "explored 0 worlds (crash points N + 1
/// baseline)" beside crash points it never reached, and the JSON carries all four on every
/// report.
pub fn sayAccount(arena: std.mem.Allocator, of: AccountOf, points: usize) void {
    sayCwd(arena, "cwd         {s}{s}\n");
    sayApparatus(arena, "apparatus   {s}\n");
    sayWarnings("warning     {s}\n");
    sayRecovery("recovery    {s}\n");
    say("\n", .{});
    if (of != .unknown) {
        say("explored    {d} worlds (crash points {d} + 1 baseline)\n", .{ explored, points });
        if (of == .pass) saySingleCrashPointNote(points);
    }
    say("expected    exit {d}\n", .{expected_status_val});
    say("atomicity   {s}\n", .{l0_note});
    if (of != .unknown) {
        say("oracle      {s}\n", .{oracle_note});
        say("metadata    {s}\n", .{metadata_note});
        say("checker     {s}\n", .{checker_note});
    }
    say("l1          {s}\n", .{l1_note});
    say("case        {s}\n", .{case_note});
    if (of == .fail) {
        say("replay      {s}\n", .{replay_note});
        say("evidence    {s}\n", .{evidenceCommand(arena, evidence_note)});
    }
    say("processes   {s}\n", .{boundary.boundaryAccount()});
    say("not tested  {s}\n", .{notTestedText()});
}

/// One exhibit's recovery object, inside that exhibit's JSON object. `command_exit` is present
/// only when the recovery command exited, as `setup_exit_code` is only when the setup did.
fn jsonRecoveryField(w: *std.ArrayList(u8), arena: std.mem.Allocator, r: RecoveryResultJson) !void {
    const res = r.result;
    try w.appendSlice(arena, ",\n    \"recovery\": {\"result\": ");
    try jsonString(w, arena, res.name());
    try w.print(arena, ", \"seconds\": {d}.{d:0>3}", .{ r.ms / 1000, r.ms % 1000 });
    if (r.command_exit) |c| try w.print(arena, ", \"command_exit\": {d}", .{c});
    try w.appendSlice(arena, "}");
}

/// The verdict line's clause for a run with exactly one crash point (#487).
///
/// Zero had a verdict line of its own — "the operation performed nothing that can change the
/// judged state" — until ADR 0091 made it the refusal `nothing_could_fail`, whose step says where
/// an undeclared define's commands run; `docs/scouting.md` calls it the tell for a store outside
/// `--state`. One had nothing: the count was in the account block and nowhere else,
/// which is where #487's reporter read past it, at the price of a full exploration and the
/// wrong conclusion. `preflight` has named its count on its own headline all along
/// (`recording accepted — N state-changing operation(s) observed`), so this is explore
/// catching up with a sibling rather than a new register.
///
/// **Not a threshold.** Two crash points get nothing added, deliberately: "two is enough" is
/// a claim this cannot make, and a genuinely single-syscall operation is a legitimate target
/// shape — `docs/target-classes.md` records papis reaching exactly one through a lone
/// `renameat`. What this does is extend zero's
/// register to the one case sitting next to it, and the cases at two and three are left
/// where they were — a define whose store resolves outside `--state` but writes one file
/// still reaches two (`open` + `write`) and gets no tell.
pub fn singleCrashPointClause(n: usize) []const u8 {
    return if (n == 1) ", over a single crash point" else "";
}

/// The verdict line's clause for a PASS whose atomicity invariant compared nothing a crash
/// could change (#683, ADR 0091). An exploration's such PASS reaches the print only because a
/// checker, or a marker over a created or removed path, judged the worlds — otherwise it is
/// refused `nothing_could_fail` — and the headline's claim stays true: the invariant held. What the
/// clause adds is that it held vacuously, on the same line, where #683's reader stopped.
/// Empty when any judged path was touched, so every other PASS reads as it did. A replay's
/// PASS carries it too: the clause does not move the verdict.
pub fn untouchedClause(arena: std.mem.Allocator, touched: u32, judged: usize) []const u8 {
    if (touched > 0) return "";
    if (judged == 0) return ", but it had no path to judge";
    return std.fmt.allocPrint(arena, ", but the operation touched none of the {d} path(s) it judged", .{judged}) catch ", but the operation touched none of the paths it judged";
}

test "the untouched clause is empty whenever a judged path was touched, and names the count otherwise (#683)" {
    const a = std.testing.allocator;
    try std.testing.expectEqualStrings("", untouchedClause(a, 1, 3));
    try std.testing.expectEqualStrings(", but it had no path to judge", untouchedClause(a, 0, 0));
    const s = untouchedClause(a, 0, 2);
    defer a.free(s);
    try std.testing.expectEqualStrings(", but the operation touched none of the 2 path(s) it judged", s);
}

/// The advice that goes with the clause above, in the account block's own style, only when
/// the run had exactly one crash point.
///
/// **The condition is `singleCrashPointClause`'s, spelled a second time.** Changing one
/// without the other leaves a verdict line that names the count with no advice under it, or
/// advice under a line that does not. They are two functions rather than one because they
/// print in two places — the literal and after it — and there is no third caller to make a
/// shared predicate worth its own name.
///
/// A call of its own rather than a `{s}` line inside a literal, which would print an indented
/// blank on every *other* PASS. Since `sayAccount` (#711) the PASS block is a sequence of calls,
/// so the note sits where it always belonged — under the `explored` line it qualifies, as a
/// continuation in the block's twelve-column style — rather than under `not tested`.
fn saySingleCrashPointNote(n: usize) void {
    if (n == 1) say("            if the define expected more, check that the target's store resolves inside the state directory\n", .{});
}

/// A JSON array of strings as a report field; with `only_unchecked`, the entries
/// `config.apparatusUnchecked` selects.
fn jsonArrayField(w: *std.ArrayList(u8), arena: std.mem.Allocator, name: []const u8, items: []const []const u8, only_unchecked: bool) !void {
    try w.appendSlice(arena, ",\n  \"");
    try w.appendSlice(arena, name);
    try w.appendSlice(arena, "\": [");
    var first = true;
    for (items) |e| {
        if (only_unchecked and !config.apparatusUnchecked(e)) continue;
        if (!first) try w.appendSlice(arena, ", ");
        first = false;
        try jsonString(w, arena, e);
    }
    try w.append(arena, ']');
}

/// The text report's `apparatus` line: the entries as declared, comma-separated, each
/// unchecked one saying so. The JSON carries the same list as two arrays.
fn apparatusNote(arena: std.mem.Allocator) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (apparatus_declared, 0..) |e, i| {
        if (i > 0) out.appendSlice(arena, ", ") catch return "(allocation failed)";
        out.appendSlice(arena, textShown(arena, e)) catch return "(allocation failed)";
        if (config.apparatusUnchecked(e)) out.appendSlice(arena, " (declared, not checked)") catch return "(allocation failed)";
    }
    return out.items;
}

/// JSON for the caller, text for the reader (DESIGN §13). Not identical content: this is
/// the complete record and the text is the reader's view of it. What §13 binds is that a
/// value both forms carry has one definition, which is why every `jsonString` below reads
/// a shared note rather than formatting one again.
///
/// Hand-written rather than derived from a type. That the fields it writes are the fields
/// `docs/report-schema.md` documents — and that `schema_status` carries the value that page
/// states — is held by `spike/check-report-schema.py` against reports this code produced.
///
/// `std.json.Stringify.encodeJsonString` was the obvious alternative and does not fit.
/// Its default options pass bytes 0x80–0xFF through unchanged — the same defect this
/// function had — and `escape_unicode` decodes them with `catch unreachable`, so invalid
/// UTF-8 is a panic rather than a bad document.
pub fn jsonString(w: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) !void {
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

pub fn violationPath(v: engine.Violation) []const u8 {
    return switch (v) {
        .missing => |p| p,
        .hybrid => |p| p,
        .rewritten => |p| p,
        .not_durable => |p| p,
    };
}

/// The opening clause of every `baseline_violates_invariant` refusal (#199): the acceptance
/// suite and the docs quote it, so it has one home, the way `not_tested_*` fragments do.
pub const baseline_refusal_lead = "the invariant failed in the world that was never crashed, so nothing found here is a consequence of crashing";

/// The other layers that failed in the same un-killed world, as a trailing clause; empty
/// when none did. The byte layer asks about both; the marker asks only about the checker.
pub fn baselineAlsoFailed(marker: bool, checker: bool) []const u8 {
    if (marker and checker) return "; the success marker's invariant and the checker failed there too";
    if (checker) return "; the checker rejected that state too";
    if (marker) return "; the success marker's invariant failed there too";
    return "";
}

/// The baseline's reading of the same kinds (#199), worded for the world that was never
/// killed: `violationObserved` speaks of a crashed state, and the baseline has none. The
/// switch is the sibling's shape — a tail per kind — and the path is spliced in once.
/// `judgeL0` hands the baseline only the first three kinds; `not_durable` is `judgeL1`'s
/// and is worded here so the switch stays total rather than hiding an `unreachable` behind
/// a judge's contract.
pub fn baselineObserved(arena: std.mem.Allocator, v: engine.Violation) []const u8 {
    const tail: []const u8 = switch (v) {
        .missing => "gone, though the recording had it before and after",
        .hybrid => "holding neither the old nor the new content",
        .rewritten => "with its recorded history no longer a prefix of its content",
        .not_durable => "not in its recorded final form",
    };
    return std.fmt.allocPrint(arena, "the re-run from the restored state left {s} {s}", .{ textShown(arena, violationPath(v)), tail }) catch "the re-run from the restored state did not leave the recorded bytes";
}

/// How `byteSpan` shows the two stretches (#688).
pub const SpanShown = enum {
    /// Where, how long and what kind of bytes — no bytes. A refusal carries this: it reaches
    /// the JSON `message`, the MCP answer (ADR 0010) and reports pasted upstream, and the
    /// stretch two runs disagree on is exactly where a per-run token or secret sits.
    shape,
    /// The same, plus both stretches quoted. Only `preflight --twice`'s text prints this, so the
    /// bytes reach the terminal of whoever typed it; its `--json` document carries the `.shape`
    /// form (#717).
    bytes,
};

/// Raw bytes of each stretch `byteSpan` quotes before it says `…`.
const span_shown_max: usize = 48;

/// What kind of bytes a stretch holds, and — for `binary` — how many are not text, counted
/// once: a stretch can be a whole file.
const StretchKind = struct {
    kind: enum { nothing, decimal, hex, text, binary },
    non_text: usize = 0,

    fn of(s: []const u8) StretchKind {
        if (s.len == 0) return .{ .kind = .nothing };
        var decimal = true;
        var hex = true;
        var has_digit = false;
        var has_letter = false;
        for (s) |c| {
            if (std.ascii.isDigit(c)) has_digit = true else decimal = false;
            if (!std.ascii.isHex(c)) hex = false else if (!std.ascii.isDigit(c)) has_letter = true;
        }
        if (decimal) return .{ .kind = .decimal };
        // Digits and letters both (review): `A`→`B`, `bad`→`fee` are hex-shaped words, and the
        // apparatus table sends "hex digits" to look for an id.
        if (hex and has_digit and has_letter) return .{ .kind = .hex };
        const n = defang.nonTextBytes(s);
        return if (n == 0) .{ .kind = .text } else .{ .kind = .binary, .non_text = n };
    }

    fn text(self: StretchKind, arena: std.mem.Allocator) []const u8 {
        return switch (self.kind) {
            .nothing => "nothing",
            .decimal => "decimal digits",
            .hex => "hex digits",
            .text => "printable text",
            .binary => std.fmt.allocPrint(arena, "{d} byte(s) outside printable text", .{self.non_text}) catch "bytes outside printable text",
        };
    }
};

fn isUtf8Continuation(c: u8) bool {
    return c & 0xc0 == 0x80;
}

/// The valid UTF-8 character that holds byte `i` of `s` without starting there — the one a
/// stretch boundary at `i` would cut — or null when `s[i]` is not a continuation byte of one.
fn charAround(s: []const u8, i: usize) ?struct { start: usize, end: usize } {
    if (i >= s.len or !isUtf8Continuation(s[i])) return null;
    var j = i;
    while (j > 0 and i - j < 3) {
        j -= 1;
        if (!isUtf8Continuation(s[j])) break;
    }
    if (isUtf8Continuation(s[j])) return null;
    const n = std.unicode.utf8ByteSequenceLength(s[j]) catch return null;
    if (j + n <= i or j + n > s.len) return null;
    if (!std.unicode.utf8ValidateSlice(s[j..][0..n])) return null;
    return .{ .start = j, .end = j + n };
}

/// `s` cut to at most `max` bytes, the cut moved back (by up to three bytes) off the middle
/// of a UTF-8 character so the quote does not end in a row of `\xNN`.
fn clipAtCharacter(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and max - n < 3 and isUtf8Continuation(s[n])) n -= 1;
    return s[0..n];
}

/// The difference between two byte strings two clean runs left at one path (#688), as an
/// observation: where they first differ, how long the differing stretch is in each, and
/// what kind of bytes it holds — never what produced them (ADR 0030; DESIGN: the engine
/// does not guess whether it was a clock, a random id or an inode-keyed cache). The
/// stretch is what is left after the common prefix and the common suffix are taken off
/// both, so a changed number in the middle of a line is that number, and the two
/// stretches can differ in length or be empty on one side. Offsets count from 0, and the
/// offset is the first byte that differs; the stretch is then widened, by up to three
/// shared bytes at either end, to whole UTF-8 characters — `café`→`cafè` differ only in
/// the last byte of the `é`, and the stretch cut there was one continuation byte read as
/// binary (review).
pub fn byteSpan(arena: std.mem.Allocator, a_name: []const u8, a: []const u8, b_name: []const u8, b: []const u8, shown: SpanShown) []const u8 {
    if (std.mem.eql(u8, a, b)) return "hold the same bytes";
    const lim = @min(a.len, b.len);
    var p: usize = 0;
    while (p < lim and a[p] == b[p]) p += 1;
    var s: usize = 0;
    while (s < lim - p and a[a.len - 1 - s] == b[b.len - 1 - s]) s += 1;
    // Widening crosses only shared bytes — everything before `p` and after the last `s` bytes
    // is the same in both, so the two stretches grow by the same characters — and only to a
    // character that is really there: a byte in 0x80–0xBF is a continuation only inside a
    // valid sequence, and in a PNG or an sqlite page most of them are not (review: the first
    // revision widened `41 90 85`/`41 90 86` to three bytes where one differs).
    var q = p;
    if (charAround(a, p)) |c| q = @min(q, c.start);
    if (charAround(b, p)) |c| q = @min(q, c.start);
    var end_a = a.len - s;
    var end_b = b.len - s;
    if (charAround(a, end_a)) |c| end_a = @max(end_a, c.end);
    if (charAround(b, end_b)) |c| end_b = @max(end_b, c.end);
    const t = @min(a.len - end_a, b.len - end_b);
    const sa = a[q .. a.len - t];
    const sb = b[q .. b.len - t];
    const ka = StretchKind.of(sa);
    const kb = StretchKind.of(sb);
    const kinds: []const u8 = if (ka.kind == kb.kind and ka.kind == .binary)
        std.fmt.allocPrint(arena, "both holding bytes outside printable text ({d} and {d})", .{ ka.non_text, kb.non_text }) catch "both holding bytes outside printable text"
    else if (ka.kind == kb.kind)
        std.fmt.allocPrint(arena, "both {s}", .{ka.text(arena)}) catch ""
    else
        std.fmt.allocPrint(arena, "{s} in {s}, {s} in {s}", .{ ka.text(arena), a_name, kb.text(arena), b_name }) catch "";
    // A widened stretch says where it starts, so the offset and the length are not read as
    // one range.
    return switch (shown) {
        .shape => std.fmt.allocPrint(arena, "first differ at byte offset {d}, in a stretch {d} byte(s) long in {s} and {d} in {s}{s} (of {d} and {d} bytes), {s}", .{
            p,
            sa.len,
            a_name,
            sb.len,
            b_name,
            if (q < p) std.fmt.allocPrint(arena, ", starting at byte offset {d} where that character begins", .{q}) catch "" else "",
            a.len,
            b.len,
            kinds,
        }) catch "differ",
        .bytes => std.fmt.allocPrint(arena, "first differ at byte offset {d}{s}: {s} {s}{s}, {s} {s}{s} — {d} and {d} byte(s) of {d} and {d}, {s}", .{
            p,
            if (q < p) std.fmt.allocPrint(arena, " (stretch from byte offset {d})", .{q}) catch "" else "",
            a_name,
            defang.quotedForReport(arena, clipAtCharacter(sa, span_shown_max)) catch "\"?\"",
            if (sa.len > span_shown_max) "…" else "",
            b_name,
            defang.quotedForReport(arena, clipAtCharacter(sb, span_shown_max)) catch "\"?\"",
            if (sb.len > span_shown_max) "…" else "",
            sa.len,
            sb.len,
            a.len,
            b.len,
            kinds,
        }) catch "differ",
    };
}

fn kindName(k: posix.Kind) []const u8 {
    return switch (k) {
        .file => "file",
        .dir => "directory",
        .symlink => "symbolic link",
        .other => "special file",
        .missing => "nothing",
    };
}

/// The clause a byte-layer `baseline_violates_invariant` adds after `baselineObserved`
/// (#688): what the recording left at the path the refusal names, against what the re-run
/// left there. Shape only — see `SpanShown.shape` for why the bytes stay out — with the
/// command that shows them named. Empty for `missing` (one side has no bytes) and whenever
/// either side cannot be found, so the sentence it extends stays whole.
pub fn baselineDiffers(arena: std.mem.Allocator, plan: engine.L0Plan, rerun: engine.Snapshot, v: engine.Violation) []const u8 {
    const rel = switch (v) {
        .hybrid, .rewritten => |p| p,
        .missing, .not_durable => return "",
    };
    const f = plan.find(rel) orelse return "";
    const e = rerun.find(rel) orelse return "";
    if (e.kind != f.post_kind)
        return std.fmt.allocPrint(arena, "; the recording left a {s} there and the re-run a {s}", .{ kindName(f.post_kind), kindName(e.kind) }) catch "";
    if (std.mem.eql(u8, e.content, f.post_content)) return "";
    return std.fmt.allocPrint(arena, "; the two runs' bytes {s}; preflight --twice quotes what two runs leave there", .{byteSpan(arena, "the recording", f.post_content, "the re-run", e.content, .shape)}) catch "";
}

test "byteSpan names where two runs' bytes differ, how long and what kind, and the bytes only when asked (#688)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // A changed number mid-line: prefix and suffix come off, the stretch is the number.
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4, in a stretch 1 byte(s) long in the recording and 1 in the re-run (of 9 and 9 bytes), both decimal digits",
        byteSpan(a, "the recording", "AAAA1BBBB", "the re-run", "AAAA2BBBB", .shape),
    );
    // Three inputs whose common prefixes differ in length, so an offset that does not come
    // from the bytes cannot pass all three.
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "run pid=1234 t=5", "y", "run pid=1299 t=5", .shape), "first differ at byte offset 10,"));
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "Z", "y", "Q", .shape), "first differ at byte offset 0,"));
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "AAAA1BBBB", "y", "AAAA12BBBB", .shape), "first differ at byte offset 5,"));
    // ... and that last one is an insertion: nothing on one side.
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "x", "AAAA1BBBB", "y", "AAAA12BBBB", .shape), "0 byte(s) long in x and 1 in y (of 9 and 10 bytes), nothing in x, decimal digits in y") != null);
    // The shape form carries no byte of either stretch.
    const shape = byteSpan(a, "first run", "tok=SECRETAAAA", "second run", "tok=OTHERVALUE", .shape);
    try std.testing.expect(std.mem.indexOf(u8, shape, "SECRET") == null and std.mem.indexOf(u8, shape, "OTHER") == null);
    // The bytes form quotes both, and a non-UTF-8 stretch is spelled, not turned into `?`.
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4: first run \"1\", second run \"2\" — 1 and 1 byte(s) of 9 and 9, both decimal digits",
        byteSpan(a, "first run", "AAAA1BBBB", "second run", "AAAA2BBBB", .bytes),
    );
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "\x89PNG\x00\x01", "s", "\x89PNG\x00\x02", .bytes), "f \"\\x01\", s \"\\x02\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "\x89PNG\x00\x01", "s", "\x89PNG\x00\x02", .shape), "both holding bytes outside printable text (1 and 1)") != null);
    // Hex, text, and the clip at 48 bytes with the full length still stated.
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "id=3fa9c1", "s", "id=b07e2d", .shape), "both hex digits") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "name=alpha;", "s", "name=omega;", .shape), "both printable text") != null);
    const long_a = "x" ** 100;
    const long_b = "y" ** 100;
    const clipped = byteSpan(a, "f", long_a, "s", long_b, .bytes);
    try std.testing.expect(std.mem.indexOf(u8, clipped, "f \"" ++ "x" ** 48 ++ "\"…, s \"" ++ "y" ** 48 ++ "\"… — 100 and 100 byte(s)") != null);
    try std.testing.expectEqualStrings("hold the same bytes", byteSpan(a, "f", "same", "s", "same", .shape));
}

test "byteSpan reads text as text: whole UTF-8 characters, lines, and hex only with digits and letters (#688 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    // `é` (C3 A9) and `è` (C3 A8) differ in their last byte; the stretch is the character.
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4 (stretch from byte offset 3): f \"é\", s \"è\" — 2 and 2 byte(s) of 6 and 6, both printable text",
        byteSpan(a, "f", "caf\xc3\xa9\n", "s", "caf\xc3\xa8\n", .bytes),
    );
    // あ (E3 81 82) and い (E3 81 84) share two leading bytes: the offset is the third, the
    // stretch is both characters whole.
    try std.testing.expectEqualStrings(
        "first differ at byte offset 2, in a stretch 3 byte(s) long in f and 3 in s, starting at byte offset 0 where that character begins (of 3 and 3 bytes), both printable text",
        byteSpan(a, "f", "あ", "s", "い", .shape),
    );
    // Bytes in 0x80-0xBF that belong to no valid character are not widened over (review):
    // one byte differs, at either end, and the stretch is that byte.
    try std.testing.expectEqualStrings(
        "first differ at byte offset 2, in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes), both holding bytes outside printable text (1 and 1)",
        byteSpan(a, "f", "\x41\x90\x85", "s", "\x41\x90\x86", .shape),
    );
    try std.testing.expectEqualStrings(
        "first differ at byte offset 0, in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes), both holding bytes outside printable text (1 and 1)",
        byteSpan(a, "f", "\x01\x90\x90", "s", "\x02\x90\x90", .shape),
    );
    // A shared tail that begins on a lead byte is left alone: `aé`/`bé` differ in the first
    // byte only.
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "a\xc3\xa9", "s", "b\xc3\xa9", .shape), "in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes)") != null);
    // A shared tail that begins mid-character is taken back to the character's end: `1ü`
    // (C3 BC) against `2ļ` (C4 BC) share only the final BC, which belongs to each.
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "1\xc3\xbc", "s", "2\xc4\xbc", .shape), "in a stretch 3 byte(s) long in f and 3 in s (of 3 and 3 bytes)") != null);
    // The stretch crosses a line: still text.
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "t=1\nu=2\n", "s", "t=3\nu=4\n", .shape), ", both printable text"));
    // Hex-shaped words are text; an id with digits and letters is hex.
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "grade=A\n", "s", "grade=B\n", .shape), ", both printable text"));
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "w=bad\n", "s", "w=fee\n", .shape), ", both printable text"));
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "id=3fa9c1\n", "s", "id=b07e2d\n", .shape), ", both hex digits"));
    // A clip that would end inside a character backs off to its start.
    // Stretches of 51 bytes whose 48th and 49th bytes are one `é`.
    const long_a = "a" ** 47 ++ "é" ++ "aaz";
    const long_b = "b" ** 47 ++ "é" ++ "bbz";
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", long_a, "s", long_b, .bytes), "f \"" ++ "a" ** 47 ++ "\"…, s \"" ++ "b" ** 47 ++ "\"…") != null);
}

test "baselineDiffers names a kind change, reads the history form, and says nothing for a missing path (#688 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var pre = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "one\n" }, .{ "k", "old" } });
    defer pre.deinit();
    var post = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "one\ntwo\n" }, .{ "k", "new" } });
    defer post.deinit();
    var plan = try engine.classify(std.testing.allocator, pre, post);
    defer plan.deinit();
    // The history form: the re-run rewrote the log's first line.
    var rerun = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "ONE\ntwo\n" }, .{ "k", "new" } });
    defer rerun.deinit();
    try std.testing.expectEqualStrings(
        "; the two runs' bytes first differ at byte offset 0, in a stretch 3 byte(s) long in the recording and 3 in the re-run (of 8 and 8 bytes), both printable text; preflight --twice quotes what two runs leave there",
        baselineDiffers(a, plan, rerun, .{ .rewritten = "h.log" }),
    );
    // A directory where the recording left a file.
    var dir_rerun: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer dir_rerun.deinit();
    try dir_rerun.entries.append(dir_rerun.arena.allocator(), .{ .rel = "k", .kind = .dir, .content = "" });
    try std.testing.expectEqualStrings("; the recording left a file there and the re-run a directory", baselineDiffers(a, plan, dir_rerun, .{ .hybrid = "k" }));
    // Nothing to compare for a path the re-run removed, and nothing for a path the plan does
    // not hold — the sentence it extends stays whole.
    try std.testing.expectEqualStrings("", baselineDiffers(a, plan, rerun, .{ .missing = "k" }));
    try std.testing.expectEqualStrings("", baselineDiffers(a, plan, rerun, .{ .hybrid = "elsewhere" }));
}

pub fn violationObserved(v: ?engine.Violation) []const u8 {
    return if (v) |vv| switch (vv) {
        .missing => "present before and after the operation, but gone from the crashed state",
        .hybrid => "holding neither the old nor the new content",
        .rewritten => "present, but its recorded history is no longer a prefix of its content",
        .not_durable => "the operation claimed success before the kill, and this part of the new state did not survive",
    } else "the checker exited non-zero after restart";
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

/// The claim exhibit (#231, ADR 0020): the `earliest` shape plus its own case
/// and replay, nested so the object is absent — fields and all — whenever no
/// violating world involved the declared checker.
pub const CheckerEarliest = struct {
    e: Earliest,
    case: []const u8,
    replay: []const u8,
    /// This exhibit's own bundle, beside its own case; `"-"` when none was written.
    evidence: []const u8,
};

fn buildJson(
    arena: std.mem.Allocator,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    checker_detail: ?CheckerEarliest,
    // Typed, not a third `?[]const u8` beside the two this already takes (#518): with
    // `unknown_reason` and `message` adjacent and same-typed, a positional slip compiles
    // and writes the reason into the message.
    unknown_reason: ?[]const u8,
    setup_error_reason: ?contract.SetupErrorReason,
    message: ?[]const u8,
    next_step: ?[]const u8,
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = &buf;
    var nb: [16]u8 = undefined;

    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"frozen\",\n");
    try w.appendSlice(arena, "  \"contract_version\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}));
    try w.appendSlice(arena, ",\n  \"verdict\": ");
    try jsonString(w, arena, verdict);
    try w.appendSlice(arena, ",\n  \"exit_code\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{exit_code}));
    // The contractual spelling of "did a second witness check this?" (#94). A caller
    // gates on `verdict == "PASS" && oracle_verified`, never on the prose `oracle` string.
    try w.appendSlice(arena, ",\n  \"oracle_verified\": ");
    try w.appendSlice(arena, if (oracle_verified) "true" else "false");
    // Emitted only when it is true, so every report a v14 consumer has seen is
    // byte-identical, and the `verdict == "PASS" &&
    // oracle_verified` gate keeps treating a run whose crash points include a child's
    // operations as unverified.
    if (oracle_verified_subject_only)
        try w.appendSlice(arena, ",\n  \"oracle_verified_subject_only\": true");
    // Read from the run's own counters rather than passed in as zeroes. An UNKNOWN raised
    // at world 4 of 6 used to report `"explored": 0`, so a caller aggregating coverage
    // from the JSON recorded nothing for every run that ended early.
    try w.appendSlice(arena, ",\n  \"crash_points\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{crash_points}));
    try w.appendSlice(arena, ",\n  \"explored\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{explored}));
    try w.appendSlice(arena, ",\n  \"violations\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{violations}));
    // Always present, even at the default: a PASS over a target whose success status
    // is 3 must be distinguishable, by machine, from a PASS that required 0.
    try w.appendSlice(arena, ",\n  \"expected_status\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{expected_status_val}));
    try appendCwd(w, arena);

    try appendDeclarations(w, arena);
    if (unknown_reason) |r| {
        try w.appendSlice(arena, ",\n  \"unknown_reason\": ");
        try jsonString(w, arena, r);
    }
    // #518, ADR 0057: the SETUP_ERROR's class, beside the other closed set, and the status
    // a failing `--setup` ended with — one integer or the other, only under `setup_failed`,
    // and neither for a status `waitpid` did not decode (the message quotes the raw number).
    // Gated on the reason rather than on `setup_status` alone: the global is set only in
    // the failing arms, but the gate is what keeps a later PASS from ever carrying it.
    if (setup_error_reason) |r| {
        try w.appendSlice(arena, ",\n  \"setup_error_reason\": ");
        try jsonString(w, arena, r.name());
        if (r == .setup_failed) if (setup_status) |st| switch (st) {
            .exited => |code| {
                try w.appendSlice(arena, ",\n  \"setup_exit_code\": ");
                try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{code}));
            },
            .signaled => |sig| {
                try w.appendSlice(arena, ",\n  \"setup_signal\": ");
                try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{sig}));
            },
            .unknown => {},
        };
    }
    if (message) |m| {
        try w.appendSlice(arena, ",\n  \"message\": ");
        try jsonString(w, arena, m);
    }
    // #274: the same rendered sentence the text report prints on its `next` line —
    // `unknown()` renders it once and passes it here, so `check-report-schema.py`'s fifth
    // claim (a bare name through `jsonString`) holds, and acceptance check 2ns holds the
    // two forms to each other by bytes.
    // #337: the syscall the oracle saw at a divergence, beside the line `message` quotes.
    // Present only on `oracle_missed_operation` — the one refusal where the oracle has a
    // line at the diverging index — and written from the same `divergence_syscall` the
    // text report prints, so the two forms cannot disagree.
    if (divergence_syscall.len > 0) {
        try w.appendSlice(arena, ",\n  \"divergence_syscall\": ");
        try jsonString(w, arena, divergence_syscall);
    }
    if (next_step) |n| {
        try w.appendSlice(arena, ",\n  \"next_step\": ");
        try jsonString(w, arena, n);
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
        if (recovery_earliest) |r| try jsonRecoveryField(w, arena, r);
        try w.appendSlice(arena, "\n  }");
    }

    if (checker_detail) |cd| {
        try w.appendSlice(arena, ",\n  \"checker_earliest\": {\n    \"crash_point\": ");
        try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{cd.e.k}));
        try w.appendSlice(arena, ",\n    \"invariant\": ");
        try jsonString(w, arena, cd.e.invariant);
        try w.appendSlice(arena, ",\n    \"after\": {\"op\": ");
        try jsonString(w, arena, cd.e.after);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, cd.e.after_path);
        try w.appendSlice(arena, "},\n    \"before\": {\"op\": ");
        try jsonString(w, arena, cd.e.before);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, cd.e.before_path);
        try w.appendSlice(arena, "},\n    \"subject\": ");
        try jsonString(w, arena, cd.e.subject);
        try w.appendSlice(arena, ",\n    \"observed\": ");
        try jsonString(w, arena, cd.e.observed);
        try w.appendSlice(arena, ",\n    \"case\": ");
        try jsonString(w, arena, cd.case);
        try w.appendSlice(arena, ",\n    \"replay\": ");
        try jsonString(w, arena, cd.replay);
        try w.appendSlice(arena, ",\n    \"evidence\": ");
        try jsonString(w, arena, cd.evidence);
        if (recovery_checker_earliest) |r| try jsonRecoveryField(w, arena, r);
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
    // Additive under the report-schema allowance surface 2 keeps open, beside `case` and
    // `replay` for the same exhibit and for the same reason they are here.
    try w.appendSlice(arena, ",\n  \"evidence\": ");
    try jsonString(w, arena, evidence_note);
    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    try w.appendSlice(arena, ",\n  \"metadata_writes\": ");
    try jsonString(w, arena, metadata_note);
    try w.appendSlice(arena, ",\n  \"checker\": ");
    try jsonString(w, arena, checker_note);
    // #606, ADR 0072: present only when a recovery was declared, the presence rule `apparatus`
    // and `scratch` follow.
    if (recovery_note) |rn| {
        try w.appendSlice(arena, ",\n  \"recovery\": ");
        try jsonString(w, arena, rn);
    }
    try w.appendSlice(arena, ",\n  \"processes\": ");
    try jsonString(w, arena, boundary.boundaryAccount());
    // Additive under the report-schema allowance the freeze keeps open (surface 2). A
    // number rather than a sentence in `l0`, so "this run has no unexamined subtree" is
    // machine-readable instead of being the absence of a phrase.
    try w.print(arena, ",\n  \"paths_attributed_to_rename\": {d}", .{attributed_to_rename});
    // Stated in the report itself, not only in the documentation: a PASS that does not
    // say what it did not look at is the kind of reassurance this tool refuses to give.
    try w.appendSlice(arena, ",\n  \"not_tested\": ");
    try w.appendSlice(arena, notTestedJson());
    try appendFigures(w, arena);
    try appendJudgedSet(w, arena);
    try w.appendSlice(arena, "\n}\n");
    return buf.items;
}

// The parts of the report the preflight document shares (#717): written by one function each,
// so the two documents cannot spell the same field two ways. Moved out of `buildJson` whole,
// in the order it writes them; the report's bytes do not move.
const W = *std.ArrayList(u8);

fn appendCwd(w: W, arena: std.mem.Allocator) !void {
    // #647: present on every report raised once the define's `cwd` has been resolved, a
    // SETUP ERROR raised after that point included — whose text is one line by design and
    // carries no `cwd` line, the way it carries no recovery line (see `sayCwd`). The string is the
    // variable the text reads; `jsonString` escapes it, `textShown` defangs it.
    if (command_cwd) |c| {
        try w.appendSlice(arena, ",\n  \"command_cwd\": ");
        try jsonString(w, arena, c);
        try w.appendSlice(arena, ",\n  \"command_cwd_declared\": ");
        try w.appendSlice(arena, if (command_cwd_declared) "true" else "false");
    }
}

fn appendDeclarations(w: W, arena: std.mem.Allocator) !void {
    // ADR 0041: present only when the define declared something (the presence rule
    // `next_step` and `divergence_syscall` follow), each entry as it was spelled; the
    // unchecked list is the same entries through the one predicate the text line uses.
    // #706, ADR 0095: present only when there is a warning, the presence rule `apparatus` follows.
    if (define_warnings.len > 0) try jsonArrayField(w, arena, "define_warnings", define_warnings, false);
    if (apparatus_declared.len > 0) {
        try jsonArrayField(w, arena, "apparatus", apparatus_declared, false);
        if (apparatusHasUnchecked()) try jsonArrayField(w, arena, "apparatus_unchecked", apparatus_declared, true);
    }
    // ADR 0043: the same presence rule, the same slice the plan judged by.
    if (scratch_declared.len > 0) try jsonArrayField(w, arena, "scratch", scratch_declared, false);
}

fn appendFigures(w: W, arena: std.mem.Allocator) !void {
    // #711, ADR 0096: what the `oracle`, `checker` and `processes` sentences state, as numbers and
    // booleans beside them. Each is present only where it was measured — none is ever written as a
    // zero or a false standing for "not known" — and none is a closed set. Before the judged set,
    // which stays last (ADR 0079).
    switch (oracle_asked) {
        .named => |kind| {
            try w.appendSlice(arena, ",\n  \"oracle_witness\": ");
            try jsonString(w, arena, kind.name());
        },
        .unparsed, .none => {},
    }
    if (oracle_operations_agreed) |n| try w.print(arena, ",\n  \"oracle_operations_agreed\": {d}", .{n});
    if (checker_declared) |d| try w.print(arena, ",\n  \"checker_declared\": {s}", .{if (d) "true" else "false"});
    if (checker_worlds) |n| try w.print(arena, ",\n  \"checker_worlds\": {d}", .{n});
    // The recording run's counts, which is all `boundary_ev` holds for them: the `processes`
    // sentence also says what an explored world showed, and these fields do not.
    if (processes_measured) {
        const ev = boundary.boundary_ev;
        try w.print(arena, ",\n  \"processes_children_admitted\": {s}", .{if (ev.children_judged) "true" else "false"});
        try w.print(arena, ",\n  \"processes_image_changes\": {d}", .{ev.exec_continuations});
        try w.print(arena, ",\n  \"processes_threads_created\": {d}", .{ev.threads});
        try w.print(arena, ",\n  \"processes_writer_threads\": {d}", .{ev.writer_threads});
    }
}

fn appendJudgedSet(w: W, arena: std.mem.Allocator) !void {
    // #638, ADR 0079. LAST in the document, and the position is the decision: this is the only
    // field whose length grows with the target's state tree, so anywhere else it pushes back
    // the fields a reader of a FAIL needs first — `message`, `next_step`, `earliest`. Written
    // here it moves no existing byte. Present only on a run that reached classification, so a
    // SETUP ERROR raised before the define was read carries neither field.
    if (l0_classified) {
        try jsonArrayField(w, arena, "l0_judged_paths", l0_judged_paths, false);
        try w.print(arena, ",\n  \"l0_judged_paths_omitted\": {d}", .{l0_judged_paths_omitted});
        // After the two it qualifies, so it moves no byte that was there before it (#683).
        if (l0_judged_paths_touched) |t| try w.print(arena, ",\n  \"l0_judged_paths_touched\": {d}", .{t});
    }
}

/// On stderr, not stdout: the text report is the process's output, and a diagnostic
/// mixed into it would be read as part of the verdict. Ends with the seal token in its
/// `none` form (see `sealToken`): a run that asked for `--json` gets exactly one token
/// whether or not the file landed.
fn jsonFailed(detail: []const u8) void {
    const prefix = "sideeye: the JSON report was not written: ";
    _ = posix.write(2, prefix.ptr, prefix.len);
    _ = posix.write(2, detail.ptr, detail.len);
    _ = posix.write(2, "\n", 1);
    recordSeal(null);
}

/// The seal on the JSON report (#597): `sideeye: json sha256=<64 hex>;` when the file is in
/// place, `sideeye: json sha256=none;` when it is not, each followed by one newline. The
/// digest is of exactly the bytes written, taken from the buffer that was written rather
/// than from the file, so a reader that receives the report through a directory the judged
/// program can also write -- the loop-closure judge's container is one -- can tell the file
/// it opens from one written after. Emitted in ONE write: on a pipe, a write of at most
/// PIPE_BUF bytes is not interleaved with another writer's, so the token arrives whole even
/// beside a program flooding the same descriptor. Not anchored to a line start on purpose,
/// and the reader must not anchor either: a flooder can take the line start away, but it
/// cannot remove the token, so a reader that counts occurrences anywhere sees the real one
/// and any forgery both. Always exactly one per run that named `--json`, so that "no token"
/// cannot be arranged by making the write fail and "one token" is never a forgery alone.
/// Not part of the report schema: it is a line on stderr, and the freeze does not cover
/// stderr's prose (docs/contract-freeze.md).
/// Recorded by `writeJsonReport` / `jsonFailed`, emitted by `emitSeal` at the exit. Deferred
/// rather than printed on the spot because the two refusal paths (`refuse.unknown`,
/// `refuse.setupError`) write the JSON BEFORE their text, and a token printed there would become
/// the first line of a run's output. The acceptance suite's CLI self-description check reads that
/// first line, and it went red when the token was printed in place — a reader that takes the first
/// line of merged output is exactly what this project's own tooling turned out to be.
const seal_prefix = "sideeye: json sha256=";
pub const seal_len = seal_prefix.len + 64 + ";\n".len;
var seal_pending: ?[32]u8 = null;
var seal_recorded = false;
var seal_emitted = false;

pub fn sealToken(buf: *[seal_len]u8, digest: ?[32]u8) []const u8 {
    if (digest) |d| {
        return std.fmt.bufPrint(buf, seal_prefix ++ "{x};\n", .{d}) catch unreachable;
    }
    return std.fmt.bufPrint(buf, seal_prefix ++ "none;\n", .{}) catch unreachable;
}

fn recordSeal(digest: ?[32]u8) void {
    seal_pending = digest;
    seal_recorded = true;
}

/// Write the token, once, for a run that named `--json`. Called immediately before every exit
/// that can follow a report; a path that never reaches one leaves no token, which the readers of
/// this token treat as a refusal — the safe direction.
pub fn emitSeal() void {
    emitWarnings();
    if (!seal_recorded or seal_emitted) return;
    seal_emitted = true;
    var buf: [seal_len]u8 = undefined;
    const tok = sealToken(&buf, seal_pending);
    _ = posix.write(2, tok.ptr, tok.len);
}

/// Written whole or not at all.
///
/// Every step here used to fail silently: a failed open, a short write, a formatting
/// error mid-document. The result was a truncated file — `{"schema": "sideeye/report",`
/// with no closing brace — beside an exit code claiming a clean verdict, and the caller
/// could not tell a broken write from a broken tool. Building the document first and
/// moving it into place with `rename` is the same discipline sideeye exists to check for
/// in other programs; applying it here is not decoration.
pub fn writeJsonReport(
    arena: std.mem.Allocator,
    path: []const u8,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    checker_detail: ?CheckerEarliest,
    unknown_reason: ?[]const u8,
    setup_error_reason: ?contract.SetupErrorReason,
    message: ?[]const u8,
    next_step: ?[]const u8,
) void {
    const doc = buildJson(arena, verdict, exit_code, detail, checker_detail, unknown_reason, setup_error_reason, message, next_step) catch
        return jsonFailed("the document could not be built");
    writeJsonDoc(path, doc);
}

/// `doc` to `path`, through a temporary name and a rename, then the seal over its bytes. The
/// one writer for both documents `--json` produces — the report, and preflight's (#717) — so
/// both land whole or not at all and both are sealed the same way.
fn writeJsonDoc(path: []const u8, doc: []const u8) void {
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

    // The seal, over the bytes that were written -- `doc`, not a re-read of the file, which
    // by now is in a directory somebody else may write (#597).
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(doc, &digest, .{});
    recordSeal(digest);
}

/// What `preflight --json` writes when preflight accepted the recording, or when `--twice`'s two
/// runs differed (#717, ADR 0102). Preflight produces no verdict, and the report's `verdict` is a
/// closed set of four, so these two outcomes get a document of their own; a refusal or a stop
/// writes the report, through `unknown()` and `setupError` as explore's do. The account comes from
/// the same variables the text block prints, written by the same functions the report uses.
pub const PreflightDoc = struct {
    runs_differ: bool,
    /// State-changing operations the recording observed — its crash points.
    operations: u32,
    marker_declared: bool,
    /// `--twice` only.
    repeat: ?PreflightRepeat,
};

pub const PreflightRepeat = struct {
    gap_ms: u64,
    total: usize,
    diffs: []const PreflightDiff,
};

pub const PreflightDiff = struct {
    path: []const u8,
    how: []const u8,
    /// The byte line in its `.shape` form: where the runs first differ, how long each stretch
    /// is and what kind of bytes it holds. Never the `.bytes` form — the stretch two runs
    /// disagree on is where a per-run token or secret sits, and this document is what an MCP
    /// call and a CI log keep.
    shape: ?[]const u8,
};

test "a preflight difference's `how` is one of the four names docs/report-schema.md lists (#717)" {
    // The document writes `@tagName` of the snapshot's enum, and its schema is frozen from the
    // first release: a renamed member would rename a frozen value with no other test noticing.
    const names = std.meta.fieldNames(engine.Difference.How);
    try std.testing.expectEqual(@as(usize, 4), names.len);
    for (names, [_][]const u8{ "only_in_first", "only_in_second", "kind_differs", "content_differs" }) |got, want|
        try std.testing.expectEqualStrings(want, got);
}

/// What preflight's `not checked` line names. The text prints it and `--json` writes it as a
/// list, both from here.
pub const preflight_not_checked = [_][]const u8{ "kill landing", "world-side process boundaries", "baseline behavior", "checker falsification", "whether any world could fail" };

pub fn writePreflightJson(arena: std.mem.Allocator, path: []const u8, pd: PreflightDoc) void {
    const doc = buildPreflightJson(arena, pd) catch return jsonFailed("the document could not be built");
    writeJsonDoc(path, doc);
}

fn buildPreflightJson(arena: std.mem.Allocator, pd: PreflightDoc) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = &buf;
    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/preflight\",\n  \"schema_status\": \"frozen\",\n");
    try w.print(arena, "  \"contract_version\": {d}", .{contract.contract_version});
    try w.print(arena, ",\n  \"outcome\": \"{s}\"", .{if (pd.runs_differ) "runs_differ" else "recording_accepted"});
    // The process's own code: 0 accepted, 1 the two runs differed — the negative answer to the
    // question `--twice` asked, not a FAIL (docs/cli.md).
    try w.print(arena, ",\n  \"exit_code\": {d}", .{@as(u8, if (pd.runs_differ) 1 else 0)});
    try w.print(arena, ",\n  \"crash_points\": {d}", .{pd.operations});
    try w.print(arena, ",\n  \"expected_status\": {d}", .{expected_status_val});
    try appendCwd(w, arena);
    try appendDeclarations(w, arena);
    try w.appendSlice(arena, ",\n  \"l0\": ");
    try jsonString(w, arena, l0_note);
    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    if (recovery_note) |rn| {
        try w.appendSlice(arena, ",\n  \"recovery\": ");
        try jsonString(w, arena, rn);
    }
    try w.appendSlice(arena, ",\n  \"processes\": ");
    try jsonString(w, arena, boundary.boundaryAccount());
    // Present only when the define declared one, as the text line is: a marker that never
    // appears is refused before a preflight document is written, so present means observed.
    if (pd.marker_declared) try w.appendSlice(arena, ",\n  \"marker_observed\": true");
    try jsonArrayField(w, arena, "not_checked", &preflight_not_checked, false);
    if (pd.repeat) |r| {
        try w.print(arena, ",\n  \"repeat_gap_ms\": {d}", .{r.gap_ms});
        try w.print(arena, ",\n  \"differences_total\": {d}", .{r.total});
        try w.appendSlice(arena, ",\n  \"differences\": [");
        for (r.diffs, 0..) |d, i| {
            try w.appendSlice(arena, if (i == 0) "\n    {\"path\": " else ",\n    {\"path\": ");
            try jsonString(w, arena, d.path);
            try w.appendSlice(arena, ", \"how\": ");
            try jsonString(w, arena, d.how);
            if (d.shape) |sh| {
                try w.appendSlice(arena, ", \"shape\": ");
                try jsonString(w, arena, sh);
            }
            try w.appendSlice(arena, "}");
        }
        try w.appendSlice(arena, if (r.diffs.len == 0) "]" else "\n  ]");
    }
    try appendFigures(w, arena);
    try appendJudgedSet(w, arena);
    try w.appendSlice(arena, "\n}\n");
    return buf.items;
}

test "the seal token is one fixed-length line under PIPE_BUF, in both forms, over the known vector (#597)" {
    var buf: [seal_len]u8 = undefined;
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("abc", &d, .{});
    const sealed = sealToken(&buf, d);
    try std.testing.expectEqualStrings(
        "sideeye: json sha256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;\n",
        sealed,
    );
    try std.testing.expectEqual(seal_len, sealed.len);
    // The exact width, not only a bound: the ADR and the buildlog quote this number, and a bound
    // lets them drift (found in review, where they said 88).
    try std.testing.expectEqual(@as(usize, 87), seal_len);
    // PIPE_BUF is 4096 on Linux and 512 on macOS; the token has to fit the smaller one for the
    // single write to be indivisible on either.
    try std.testing.expect(seal_len <= 512);
    var buf2: [seal_len]u8 = undefined;
    const none = sealToken(&buf2, null);
    try std.testing.expectEqualStrings("sideeye: json sha256=none;\n", none);
    // Both forms share the prefix a reader counts, and neither contains it twice.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sealed, seal_prefix));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, none, seal_prefix));
    // The diagnostic that precedes the `none` form shares no prefix with the token.
    try std.testing.expect(std.mem.indexOf(u8, "sideeye: the JSON report was not written: ", seal_prefix) == null);
}

/// Name the point where the two accounts split: the divergence index (1-based), the
/// raw strace line the oracle holds there, and what the shim's account holds at the
/// same position — or that either account simply ends. The detail travels through
/// `unknown` into the text and the JSON alike (DESIGN §13), so nobody has to decode
/// a binary trace by hand to learn which operation a refusal refused on (#41). On
/// allocation failure the lead sentence alone is returned: the refusal is the point,
/// the naming is the courtesy, and the courtesy must never cost the refusal.
pub fn divergenceDetail(
    arena: std.mem.Allocator,
    lead: []const u8,
    index: usize,
    shim_ops: []const engine.Op,
    oracle_lines: []const []const u8,
    oracle_names: []const []const u8,
) []const u8 {
    const oracle_part = if (index < oracle_lines.len) blk: {
        // The decomposition the reader would otherwise take from the quoted line (#337).
        // Assigned inside this arm on purpose: the other arm is the phantom case, where
        // the oracle has no line at this index and there is nothing to name.
        // The observer's own name for this operation, carried beside the line by whichever
        // reader produced it — strace's `openat`, fs_usage's `open`. Read from the list
        // rather than parsed back out of the quoted line, so both oracles answer (review
        // measured that parsing the line gives nothing on macOS: an fs_usage line opens
        // with a timestamp, not a call name).
        if (index < oracle_names.len and oracle_names[index].len > 0) divergence_syscall = oracle_names[index];
        break :blk std.fmt.allocPrint(arena, "the oracle saw: {s}", .{oracle_lines[index]}) catch return lead;
    } else std.fmt.allocPrint(arena, "the oracle's account ends after {d} operation(s)", .{index}) catch return lead;
    const shim_part = if (index < shim_ops.len) blk: {
        const op = shim_ops[index];
        break :blk if (op.aux.len > 0)
            std.fmt.allocPrint(arena, "{s} recorded: {s}(\"{s}\" -> \"{s}\")", .{ boundary.recorder(), @tagName(op.class), op.path, op.aux }) catch return lead
        else
            std.fmt.allocPrint(arena, "{s} recorded: {s}(\"{s}\")", .{ boundary.recorder(), @tagName(op.class), op.path }) catch return lead;
    } else std.fmt.allocPrint(arena, "{s}'s account ends after {d} operation(s)", .{ boundary.recorder(), index }) catch return lead;
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

test "divergence detail escapes a control byte a target put in a path" {
    // This calls `divergenceDetail`, which sets the module-level `divergence_syscall`;
    // leaving it set would hand a later test a field it never wrote (#337 review).
    defer divergence_syscall = "";
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const ops = [_]engine.Op{.{
        .class = .open,
        .seq = 1,
        .pid = 1,
        .tid = 1,
        .path = "/tmp/s/evil\nUNKNOWN  forged_reason",
        .aux = "",
    }};
    const lines = [_][]const u8{"openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3"};
    const names = [_][]const u8{"openat"};
    const detail = divergenceDetail(arena_state.allocator(), "lead", 0, &ops, &lines, &names);
    // The newline must arrive spelled out, never as a line break the report obeys.
    try std.testing.expect(std.mem.indexOf(u8, detail, "\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\\x0a") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "divergence at operation 1") != null);
}

test "a phantom divergence names no syscall: the oracle's account does not reach that index (#337)" {
    // `compare` returns `.phantom` only from the branch where the shim's list runs past
    // the oracle's, so its index is exactly the oracle's length — there is no line and no
    // name there. The report's page says the field is absent on that refusal; this is
    // what holds it. A reader tempted to fall back to `index - 1` would name the WRONG
    // operation, which is the failure this pins.
    defer divergence_syscall = "";
    divergence_syscall = "";
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const ops = [_]engine.Op{
        .{ .class = .open, .seq = 1, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" },
        .{ .class = .write, .seq = 2, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" },
    };
    // The oracle saw one operation; the shim recorded two. `compare` answers
    // `.phantom` at index 1, which is one past the end of both oracle lists.
    const lines = [_][]const u8{"openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3"};
    const names = [_][]const u8{"openat"};
    const detail = divergenceDetail(arena_state.allocator(), "lead", 1, &ops, &lines, &names);
    try std.testing.expectEqualStrings("", divergence_syscall);
    // And the detail says so in words, rather than borrowing the previous operation.
    try std.testing.expect(std.mem.indexOf(u8, detail, "the oracle's account ends after 1 operation(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "openat") == null);
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
        .pre_kind = .file,
        .post_kind = .file,
        .form = .history,
        .pre_content = "a",
        .post_content = "ab",
    });

    const note = buildL0Note(arena_state.allocator(), plan);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, '\n') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, note, "evil?name?.log") != null);
}

test "the not-tested list renders the same eight strings it shipped as two hand-written functions (#280)" {
    // The eight literals below are the output of the two functions this replaced, copied
    // from them before they were deleted. They are the point of the test: the change was
    // allowed to remove a duplicate definition and not allowed to move a byte of the
    // report. A one-time before/after comparison proves that once; this proves it on
    // every run, which is what a frozen report surface needs.
    const want_text = [4][]const u8{
        "power loss, torn writes, concurrent processes",
        "power loss, torn writes, concurrent processes, appended tails (files under the history form)",
        "power loss, torn writes, concurrent processes, post-only file contents (L1 checks existence only; post-only link targets are judged)",
        "power loss, torn writes, concurrent processes, appended tails (files under the history form), post-only file contents (L1 checks existence only; post-only link targets are judged)",
    };
    const want_json = [4][]const u8{
        "[\"power loss\", \"torn writes\", \"concurrent processes\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]",
    };
    for (want_text, 0..) |w, i| try std.testing.expectEqualStrings(w, not_tested_text_by_variant[i]);
    for (want_json, 0..) |w, i| try std.testing.expectEqualStrings(w, not_tested_json_by_variant[i]);
    // Bit 2 (ADR 0043): the same four rows again with the scratch item last, since the
    // list is built in condition order and scratch is the third condition.
    const scratch_item = "declared scratch paths (neither bytes nor presence judged)";
    for (want_text, 0..) |w, i| {
        const got = not_tested_text_by_variant[4 + i];
        try std.testing.expect(std.mem.startsWith(u8, got, w));
        try std.testing.expectEqualStrings(", " ++ scratch_item, got[w.len..]);
    }
    for (want_json, 0..) |w, i| {
        const got = not_tested_json_by_variant[4 + i];
        try std.testing.expect(std.mem.startsWith(u8, got, w[0 .. w.len - 1]));
        try std.testing.expectEqualStrings(", \"" ++ scratch_item ++ "\"]", got[w.len - 1 ..]);
    }
    try std.testing.expectEqual(@as(usize, 8), not_tested_text_by_variant.len);
}

test "the two renderings read the variant once, so they cannot describe different runs (#280)" {
    // The pair used to branch separately on the same two globals. What the duplication
    // put at risk is not whether the strings are right -- the goldens above hold that --
    // but whether both sides are answering about the same run.
    const saved_hist = l0_history_count;
    const saved_l1 = l1_configured;
    const saved_scratch = scratch_declared;
    defer {
        l0_history_count = saved_hist;
        l1_configured = saved_l1;
        scratch_declared = saved_scratch;
    }
    const one_scratch = [_][]const u8{"nondet.txt"};
    for ([_]bool{ false, true }) |s| {
        for ([_]bool{ false, true }) |h| {
            for ([_]bool{ false, true }) |l| {
                l0_history_count = if (h) 1 else 0;
                l1_configured = l;
                scratch_declared = if (s) &one_scratch else &.{};
                const want_v: usize = (if (h) @as(usize, 1) else 0) | (if (l) @as(usize, 2) else 0) | (if (s) @as(usize, 4) else 0);
                const v = notTestedVariant();
                try std.testing.expectEqual(want_v, v);
                try std.testing.expectEqualStrings(not_tested_text_by_variant[v], notTestedText());
                try std.testing.expectEqualStrings(not_tested_json_by_variant[v], notTestedJson());
                // Both renderings are the items and nothing else: the text joined by ", ",
                // the JSON the same items quoted, bracketed and in the same order.
                // Rebuilt from the item list, both forms, and compared for EQUALITY --
                // review measured that an `indexOf` on the JSON side lets a ghost item ride
                // along: appending one to the quoted rendering left the suite green.
                const items = not_tested_items_by_variant[v];
                var buf: [1024]u8 = undefined;
                var n: usize = 0;
                var jn: usize = 0;
                var jbuf: [1024]u8 = undefined;
                jbuf[jn] = '[';
                jn += 1;
                for (items, 0..) |item, i| {
                    // The buffers are asserted rather than assumed: an item long enough to
                    // overrun should report, not panic inside @memcpy.
                    try std.testing.expect(n + 2 + item.len <= buf.len);
                    try std.testing.expect(jn + 5 + item.len <= jbuf.len); // + the closing ']'
                    if (i != 0) {
                        @memcpy(buf[n..][0..2], ", ");
                        n += 2;
                        @memcpy(jbuf[jn..][0..2], ", ");
                        jn += 2;
                    }
                    @memcpy(buf[n..][0..item.len], item);
                    n += item.len;
                    jbuf[jn] = '"';
                    jn += 1;
                    @memcpy(jbuf[jn..][0..item.len], item);
                    jn += item.len;
                    jbuf[jn] = '"';
                    jn += 1;
                }
                jbuf[jn] = ']';
                jn += 1;
                try std.testing.expectEqualStrings(buf[0..n], notTestedText());
                try std.testing.expectEqualStrings(jbuf[0..jn], notTestedJson());
            }
        }
    }
}

test "an item that would need JSON escaping is rejected, and the ones shipped do not (#280)" {
    // The comptime guard beside the items cannot be reached from a test -- @compileError
    // is not catchable -- so the predicate it asks is tested here, and the guard itself
    // was seen red once by giving an item a quote and reading the build failure. Without
    // this, "the JSON side just quotes each item" rests on nothing.
    try std.testing.expect(notTestedNeedsEscaping("has a \" quote"));
    try std.testing.expect(notTestedNeedsEscaping("has a \\ backslash"));
    try std.testing.expect(notTestedNeedsEscaping("has a \n newline"));
    try std.testing.expect(notTestedNeedsEscaping("has a \t tab"));
    try std.testing.expect(!notTestedNeedsEscaping("power loss"));
    try std.testing.expect(!notTestedNeedsEscaping("post-only file contents (L1 checks existence only; post-only link targets are judged)"));
    for (not_tested_always) |item| try std.testing.expect(!notTestedNeedsEscaping(item));
    try std.testing.expect(!notTestedNeedsEscaping(not_tested_history));
    try std.testing.expect(!notTestedNeedsEscaping(not_tested_l1));
}

test "every OpClass name is its own tag, which is why the hand-written switch could go (#280)" {
    // The switch this replaced had twenty arms, each spelling its own tag, while
    // src/main.zig printed @tagName(op.class) directly in divergence detail. This asserts
    // the equality the removal rested on, so a member added with a name() that should
    // differ from its tag is a decision someone has to take deliberately rather than a
    // silent behaviour change. It also covers UnknownReason, whose name() was already
    // @tagName and is the precedent the removal followed.
    inline for (@typeInfo(contract.OpClass).@"enum".fields) |f| {
        const v: contract.OpClass = @enumFromInt(f.value);
        try std.testing.expectEqualStrings(f.name, v.name());
    }
    inline for (@typeInfo(contract.UnknownReason).@"enum".fields) |f| {
        const v: contract.UnknownReason = @enumFromInt(f.value);
        try std.testing.expectEqualStrings(f.name, v.name());
    }
    // The second closed set (#518), held to the same shape.
    inline for (@typeInfo(contract.SetupErrorReason).@"enum".fields) |f| {
        const v: contract.SetupErrorReason = @enumFromInt(f.value);
        try std.testing.expectEqualStrings(f.name, v.name());
    }
    // The oracle kind's name(), the third of the three and the one the first scan for
    // this shape missed.
    inline for (@typeInfo(boundary.BoundaryEvidence.Kind).@"enum".fields) |f| {
        const v: boundary.BoundaryEvidence.Kind = @enumFromInt(f.value);
        try std.testing.expectEqualStrings(f.name, v.name());
    }
}

test "the oracle account says no oracle was given only once the arguments were read to the end (#352)" {
    // The no-oracle wording is a byte-for-byte pin: it is what every run that named no
    // oracle published before #352, and spike/acceptance.sh's 2fi control reads it out of
    // the JSON and compares the whole string.
    try std.testing.expectEqualStrings("not run (no --oracle given)", initialOracleNote(.none));
    try std.testing.expectEqualStrings(
        "not observable (no oracle ran; the shim does not interpose ownership/permission/timestamp calls)",
        initialMetadataNote(.none, false),
    );
    // Before the parse loop finishes, and once a flag was consumed, neither account may
    // claim that none was given.
    const states = [_]OracleAsked{ .unparsed, .{ .named = .strace }, .{ .named = .fs_usage } };
    for (states) |s| {
        try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(s), "no --oracle given") == null);
        try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(s, false), "no oracle ran") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.unparsed, false), "not established") != null);
    // The named wording carries the flag that was read, and the fs_usage one is not the
    // strace one with a suffix — the acceptance legs match the whole phrase.
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .strace }), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .fs_usage }), "--oracle-fs-usage was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }, false), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .fs_usage }, false), "--oracle-fs-usage was named") != null);
    // The named metadata wording asserts no progress: the comparison block can refuse
    // after reading the capture and before assigning the metadata account, so "before its
    // capture was read" would be false there.
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }, false), "capture was read") == null);
}

test "noteOracle assigns both accounts, and the initialiser is the unparsed state (#352)" {
    const saved_o = oracle_note;
    const saved_m = metadata_note;
    defer {
        oracle_note = saved_o;
        metadata_note = saved_m;
    }
    // Fresh process state: the initialiser is the unparsed wording, not the no-oracle one.
    // Nothing else in this test binary assigns these globals, so what was saved is the
    // initialiser.
    try std.testing.expectEqualStrings(initialOracleNote(.unparsed), saved_o);
    try std.testing.expectEqualStrings(initialMetadataNote(.unparsed, false), saved_m);
    noteOracle(.{ .named = .strace });
    try std.testing.expect(std.mem.indexOf(u8, oracle_note, "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata_note, "--oracle was named") != null);
    noteOracle(.none);
    try std.testing.expectEqualStrings("not run (no --oracle given)", oracle_note);
}

test "the checker and marker accounts say none was configured only once every source was read (#352)" {
    // The two "none" wordings are byte-for-byte pins: docs/report-schema.md, docs/cli.md's
    // sample report and spike/acceptance.sh (check 2 and 2fi) carry them.
    try std.testing.expectEqualStrings("none configured", checkerNoteFor(.none));
    try std.testing.expectEqualStrings("no marker configured", l1NoteFor(.none));
    // Before the sources are read, and once one supplied a checker or a marker, neither
    // account may claim that none was configured.
    const states = [_]Declared{ .unparsed, .named };
    for (states) |s| {
        try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(s), "none configured") == null);
        try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(s), "no marker configured") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(.named), "configured") != null);
    try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(.named), "marker configured") != null);
    // The module initialisers are the unparsed state, not the "none" one. Nothing else in
    // this test binary assigns these two globals except the l1_configured test, which
    // touches only the flag.
    try std.testing.expectEqualStrings(checkerNoteFor(.unparsed), checker_note);
    try std.testing.expectEqualStrings(l1NoteFor(.unparsed), l1_note);
}

/// Save and restore the three globals `publishJudgedPaths` writes. `zig build test` runs the
/// tests of one file in a shared binary, so a test that publishes a judged set would otherwise
/// leave it in front of whatever calls `buildJson` next — the shape the `scratch_declared` test
/// above uses by hand, factored out here because four tests need it rather than one.
const SavedJudged = struct {
    paths: []const []const u8,
    omitted: u32,
    classified: bool,

    fn save() SavedJudged {
        return .{ .paths = l0_judged_paths, .omitted = l0_judged_paths_omitted, .classified = l0_classified };
    }

    fn restore(self: SavedJudged) void {
        l0_judged_paths = self.paths;
        l0_judged_paths_omitted = self.omitted;
        l0_classified = self.classified;
    }
};

/// A snapshot fixture that can carry kinds. `engine.testSnapshot` hardcodes `.file`, and the
/// set this file publishes is defined partly by the kinds `classifyWith` declines to compare.
fn snapshotWithKinds(gpa: std.mem.Allocator, entries: []const engine.Entry) !engine.Snapshot {
    var snap: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    errdefer snap.arena.deinit();
    const a = snap.arena.allocator();
    for (entries) |e| try snap.entries.append(a, .{
        .rel = try a.dupe(u8, e.rel),
        .kind = e.kind,
        .content = try a.dupe(u8, e.content),
    });
    try engine.finalizeEntries(&snap);
    return snap;
}

test "the published judged set is the shared judged pairs, not the snapshot (#638, ADR 0079)" {
    // The field's whole point is the SET, and every acceptance fixture holds nothing but
    // shared regular files — so "the post snapshot minus scratch" passes all of them while
    // answering a different question. What `classifyWith` excludes is pinned here instead:
    // a path the operation created, a path it deleted, a kind the invariants cannot compare,
    // and a declared scratch path. A symlink present on both sides is judged (#122), so it
    // is in the fixture as the control against "regular files only".
    //
    // The unsupported kind is `file -> FIFO`, and the spelling is the point. `classifyWith`
    // walks the PRE entries, so a post-only FIFO never reaches its kind test at all — it is
    // dropped by the presence rule, exactly as `new.json` is, and a leg written that way
    // measures nothing about kinds (review caught this: the first version of this fixture had
    // `pipe` post-only and the kind test could be deleted with the suite still green). A pair
    // unsupported on BOTH sides cannot occur either, because `refuseUnsupportedEntry` reads the
    // initial snapshot before classification; it reads the final one AFTER, which is what makes
    // a path that was a file and became a FIFO the reachable spelling and this leg a real one.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var pre = try snapshotWithKinds(gpa, &.{
        .{ .rel = "gone.json", .kind = .file, .content = "the operation deletes this\n" },
        .{ .rel = "key.json", .kind = .file, .content = "key=1\n" },
        .{ .rel = "link", .kind = .symlink, .content = "key.json" },
        .{ .rel = "nondet.txt", .kind = .file, .content = "before\n" },
        .{ .rel = "pipe", .kind = .file, .content = "a file the operation replaces with a FIFO\n" },
    });
    defer pre.deinit();
    var post = try snapshotWithKinds(gpa, &.{
        .{ .rel = "key.json", .kind = .file, .content = "key=2\n" },
        .{ .rel = "link", .kind = .symlink, .content = "key.json" },
        .{ .rel = "new.json", .kind = .file, .content = "the operation creates this\n" },
        .{ .rel = "nondet.txt", .kind = .file, .content = "after\n" },
        .{ .rel = "pipe", .kind = .other, .content = "" },
    });
    defer post.deinit();

    const scratch = [_][]const u8{"nondet.txt"};
    var plan = try engine.classifyWith(gpa, pre, post, &scratch);
    defer plan.deinit();

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena_state.allocator(), plan);

    try std.testing.expect(l0_classified);
    try std.testing.expectEqual(@as(u32, 0), l0_judged_paths_omitted);
    // Equality, not containment: a containment test passes for an implementation that
    // publishes the whole snapshot, which is the implementation this exists to reject.
    const want = [_][]const u8{ "key.json", "link" };
    try std.testing.expectEqual(want.len, l0_judged_paths.len);
    for (want, l0_judged_paths) |w, got| try std.testing.expectEqualStrings(w, got);
}

test "a judged set past the cap is truncated and the remainder counted (#638, ADR 0079)" {
    // One over the cap, so the boundary is measured rather than a round number well past it.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const n = max_judged_paths_listed + 1;
    const entries = try arena.alloc(engine.Entry, n);
    for (entries, 0..) |*e, i| {
        e.* = .{ .rel = try std.fmt.allocPrint(arena, "f{d:0>6}.txt", .{i}), .kind = .file, .content = "x" };
    }
    var pre = try snapshotWithKinds(gpa, entries);
    defer pre.deinit();
    var post = try snapshotWithKinds(gpa, entries);
    defer post.deinit();

    var plan = try engine.classifyWith(gpa, pre, post, &.{});
    defer plan.deinit();
    try std.testing.expectEqual(n, plan.files.items.len);

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena, plan);

    try std.testing.expectEqual(max_judged_paths_listed, l0_judged_paths.len);
    try std.testing.expectEqual(@as(u32, 1), l0_judged_paths_omitted);
    // The names are the plan's order, which is the snapshot's sorted order — so the one
    // left out is the last, and a reader who sees a non-zero count knows the list is a
    // prefix rather than a sample.
    try std.testing.expectEqualStrings("f000000.txt", l0_judged_paths[0]);
    try std.testing.expectEqualStrings("f000999.txt", l0_judged_paths[max_judged_paths_listed - 1]);
}

test "the judged set stops at the byte ceiling before the entry ceiling (#638, ADR 0079)" {
    // The entry ceiling alone does not bound the document, and the MCP server answers a report
    // over 4 MiB with a tool error rather than a verdict — so a wide tree of long names has to
    // stop on bytes. Names here are long enough that the byte ceiling binds first: the entry
    // count stays well under `max_judged_paths_listed` and the array is shorter still.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const name_len = 512;
    const n = 400; // 400 * 512 = 200 KiB of names, over the 64 KiB ceiling, under 1000 entries
    const entries = try arena.alloc(engine.Entry, n);
    for (entries, 0..) |*e, i| {
        const rel = try arena.alloc(u8, name_len);
        @memset(rel, 'x');
        _ = std.fmt.bufPrint(rel[0..8], "f{d:0>6}/", .{i}) catch unreachable;
        e.* = .{ .rel = rel, .kind = .file, .content = "x" };
    }
    var snap = try snapshotWithKinds(gpa, entries);
    defer snap.deinit();

    var plan = try engine.classifyWith(gpa, snap, snap, &.{});
    defer plan.deinit();
    try std.testing.expectEqual(n, plan.files.items.len);

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena, plan);

    // The entry ceiling did not bind — that is what makes this a test of the other one.
    try std.testing.expect(l0_judged_paths.len < max_judged_paths_listed);
    try std.testing.expectEqual(n - l0_judged_paths.len, @as(usize, l0_judged_paths_omitted));
    var bytes: usize = 0;
    for (l0_judged_paths) |q| bytes += q.len;
    try std.testing.expect(bytes <= max_judged_paths_bytes);
    // And it stopped AT the ceiling rather than well short of it: one more name would cross.
    try std.testing.expect(bytes + name_len > max_judged_paths_bytes);
}

test "a run that classified an empty judged set is not a run that never classified (#638)" {
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var empty = try snapshotWithKinds(gpa, &.{});
    defer empty.deinit();
    var plan = try engine.classifyWith(gpa, empty, empty, &.{});
    defer plan.deinit();

    const saved = SavedJudged.save();
    defer saved.restore();
    l0_classified = false;
    publishJudgedPaths(arena_state.allocator(), plan);

    try std.testing.expect(l0_classified);
    try std.testing.expectEqual(@as(usize, 0), l0_judged_paths.len);
    try std.testing.expectEqual(@as(u32, 0), l0_judged_paths_omitted);
}

test "under --observe supervised the divergence detail names the engine's account, not the shim's (#217)" {
    defer divergence_syscall = "";
    const saved = boundary.observe_mode;
    defer boundary.observe_mode = saved;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const ops = [_]engine.Op{.{ .class = .open, .seq = 1, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" }};
    const lines = [_][]const u8{ "openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3", "unlinkat(AT_FDCWD, \"/tmp/s/b\", 0) = 0" };
    const names = [_][]const u8{ "openat", "unlinkat" };

    boundary.observe_mode = .supervised;
    const held = divergenceDetail(arena, "lead", 0, &ops, &lines, &names);
    try std.testing.expect(std.mem.indexOf(u8, held, "the supervising engine recorded: open(\"/tmp/s/a\")") != null);
    const ended = divergenceDetail(arena, "lead", 1, &ops, &lines, &names);
    try std.testing.expect(std.mem.indexOf(u8, ended, "the supervising engine's account ends after 1 operation(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, held, "shim") == null);
    try std.testing.expect(std.mem.indexOf(u8, ended, "shim") == null);

    // Control: the default mode's words stand.
    boundary.observe_mode = .wrappers;
    try std.testing.expect(std.mem.indexOf(u8, divergenceDetail(arena, "lead", 0, &ops, &lines, &names), "the shim recorded: open(\"/tmp/s/a\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, divergenceDetail(arena, "lead", 1, &ops, &lines, &names), "the shim's account ends after 1 operation(s)") != null);
}

test "under --observe supervised the metadata account names the engine's filter, re-derived once the mode is known (#217)" {
    const saved = metadata_note;
    const saved_asked = oracle_asked;
    defer {
        metadata_note = saved;
        oracle_asked = saved_asked;
    }
    for ([_]OracleAsked{ .unparsed, .none, .{ .named = .strace }, .{ .named = .fs_usage } }) |asked| {
        const sup = initialMetadataNote(asked, true);
        try std.testing.expect(std.mem.indexOf(u8, sup, "the supervising engine is not notified of ownership/permission/timestamp calls") != null);
        try std.testing.expect(std.mem.indexOf(u8, sup, "shim") == null);
        // The rest of the sentence is the same claim in both modes: only the observer moves.
        const def = initialMetadataNote(asked, false);
        try std.testing.expect(std.mem.indexOf(u8, def, "the shim does not interpose ownership/permission/timestamp calls") != null);
    }
    // The parser records the oracle before the mode is known; noteObserver re-derives it.
    noteOracle(.{ .named = .strace });
    try std.testing.expect(std.mem.indexOf(u8, metadata_note, "the shim does not interpose") != null);
    noteObserver(true);
    try std.testing.expectEqualStrings(initialMetadataNote(.{ .named = .strace }, true), metadata_note);
    noteObserver(false);
    try std.testing.expectEqualStrings(initialMetadataNote(.{ .named = .strace }, false), metadata_note);
}
