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

var out_buf: [16 * 1024]u8 = undefined;

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
pub var metadata_note: []const u8 = initialMetadataNote(.unparsed);

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

fn initialMetadataNote(asked: OracleAsked) []const u8 {
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
    metadata_note = initialMetadataNote(asked);
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
/// Progress, so an UNKNOWN raised mid-exploration reports what had been explored rather
/// than zero. A caller aggregating coverage reads these.
pub var crash_points: u32 = 0;
pub var explored: u32 = 0;
pub var violations: u32 = 0;
/// The declared success status in effect (default 0), mirrored into every report so a
/// PASS over a non-zero convention is machine-auditable (ADR 0014).
pub var expected_status_val: u8 = 0;
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

/// The verdict line's clause for a run with exactly one crash point (#487).
///
/// Zero has a verdict line of its own — "the operation performed nothing that can change the
/// judged state" — and `docs/scouting.md` names it as the tell for a store that resolved
/// outside `--state`. One had nothing: the count was in the account block and nowhere else,
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

/// The advice that goes with the clause above, in the account block's own style, only when
/// the run had exactly one crash point.
///
/// **The condition is `singleCrashPointClause`'s, spelled a second time.** Changing one
/// without the other leaves a verdict line that names the count with no advice under it, or
/// advice under a line that does not. They are two functions rather than one because they
/// print in two places — the literal and after it — and there is no third caller to make a
/// shared predicate worth its own name.
///
/// A separate call after the block, the way `sayApparatus` is, rather than a `{s}` line
/// inside the multiline literal: `\\      {s}` prints six spaces on every *other* PASS when
/// the string is empty, and a check that greps for wording would never see that. The cost is
/// the position — this lands under `not tested:` rather than beside the count — and the
/// alternative was splitting the report's one `say` in two for a single line of advice.
pub fn saySingleCrashPointNote(n: usize) void {
    if (n == 1) say("      if the define expected more, check that the target's store resolves inside the state directory\n", .{});
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
/// Hand-written rather than derived from a type: the schema is explicitly experimental
/// until v1.0, and generating it would suggest a stability this release does not offer.
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

    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"experimental\",\n");
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

    // ADR 0041: present only when the define declared something (the presence rule
    // `next_step` and `divergence_syscall` follow), each entry as it was spelled; the
    // unchecked list is the same entries through the one predicate the text line uses.
    if (apparatus_declared.len > 0) {
        try jsonArrayField(w, arena, "apparatus", apparatus_declared, false);
        if (apparatusHasUnchecked()) try jsonArrayField(w, arena, "apparatus_unchecked", apparatus_declared, true);
    }
    // ADR 0043: the same presence rule, the same slice the plan judged by.
    if (scratch_declared.len > 0) try jsonArrayField(w, arena, "scratch", scratch_declared, false);
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
    try w.appendSlice(arena, ",\n  \"metadata_writes\": ");
    try jsonString(w, arena, metadata_note);
    try w.appendSlice(arena, ",\n  \"checker\": ");
    try jsonString(w, arena, checker_note);
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
        initialMetadataNote(.none),
    );
    // Before the parse loop finishes, and once a flag was consumed, neither account may
    // claim that none was given.
    const states = [_]OracleAsked{ .unparsed, .{ .named = .strace }, .{ .named = .fs_usage } };
    for (states) |s| {
        try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(s), "no --oracle given") == null);
        try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(s), "no oracle ran") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.unparsed), "not established") != null);
    // The named wording carries the flag that was read, and the fs_usage one is not the
    // strace one with a suffix — the acceptance legs match the whole phrase.
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .strace }), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .fs_usage }), "--oracle-fs-usage was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .fs_usage }), "--oracle-fs-usage was named") != null);
    // The named metadata wording asserts no progress: the comparison block can refuse
    // after reading the capture and before assigning the metadata account, so "before its
    // capture was read" would be false there.
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }), "capture was read") == null);
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
    try std.testing.expectEqualStrings(initialMetadataNote(.unparsed), saved_m);
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
