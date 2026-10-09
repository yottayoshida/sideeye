//! How a run stops: the two refusal verdicts and everything an exit must not forget.
//!
//! `src/refuse.zig` owns the exits that carry a verdict without a counterexample —
//! `unknown` (UNKNOWN, exit 2) and `setupError` (SETUP_ERROR, exit 3) — the classifiers
//! that choose between them from what they hold (`spawnFailure`, `snapshotRefusal`,
//! `restoreFailure`, `rewriteFailureDisposition`, `readFailedStep`), the `*OrRefuse`
//! helpers that wrap an engine call in its refusal, and `unstartable`, the sentence for a
//! define command that cannot be started (#701, ADR 0092), which `main.zig` raises. Every verdict line that reads
//! `UNKNOWN  <reason>` or `SETUP ERROR  <detail>` comes out of `unknown` or `setupError`
//! (the usage banner lists the four verdict words too, and is no verdict), and each of the
//! two does the same things in the same order: stops the privileged observer if one
//! is registered (`fsu_live`) and drops its capture (`fsu_capture`); writes the JSON
//! document through `report.writeJsonReport` where `--json` named a path (`json_path`,
//! `json_arena`); says the text through `report.say`; exits with the code the verdict
//! names. The observer registry lives here because that is what it is for — an exit that
//! cannot forget to stop the sidecar, instead of a rule every refusing site must remember
//! (two forgot; a root `fs_usage` held kdebug for four minutes). `run_phase` and
//! `trace_budget` are here because the refusals read them to choose a verdict or a wording;
//! `main.zig` sets each once.
//!
//! Not here: the PASS and FAIL exits, `preflightReport`'s two, and the argv refusals that
//! exit 3 before any report exists — the one-line stderr refusals of a word that names no
//! command and of `help`, `version`, `mcp` and `evidence` given what they do not take
//! (`cli.answerEntry` and `main()`, #705), and a bare `sideeye`, which prints the commands
//! to stdout — none of which prints a verdict line; they are the orchestrator's and the
//! parser's.
//!
//! Third seam of #572 (ADR 0062), first half. Bodies moved from `main.zig` byte for byte on
//! 2026-09-13, with `pub` added where `main.zig` still calls them — except that a fact or
//! renderer of `report.zig` a body reaches is spelled `report.<name>` where `main.zig` had
//! it unqualified, the one edit class this move adds, every line of which the diff lists.
//! The aliases `say`, `removeFile` and `defang.zig`'s primitives are declared here as in
//! `main.zig`. Four tests moved with the behaviour they hold, and `build.zig` names this
//! file as a test root.
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
/// The step for a `ReadFailed` past the recording run, chosen on the errno the walk
/// measured (#535). Only a permission failure says "an entry this user cannot read":
/// `EACCES`, and `EPERM` for the same reason on the platforms that answer with it. An
/// entry that was gone by the time `open` reached it (`ENOENT`) is the state still
/// moving after the run was contained — the step `quiesce` already describes — and
/// every other failure, or a read that failed without a libc call (a descriptor that
/// was not a regular file, a `readlink` that filled its buffer: errno `null`), keeps
/// the environment step, which now has a named entry to point at. A first-read review
/// of the first draft found the permission sentence attached to all five ways a read
/// can fail, so one report could say `errno 2 ENOENT` in its detail and "this user
/// cannot read" in its step.
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

/// Snapshot with the per-file cap, or refuse naming the file (#265). `what` is the
/// call site's existing message, kept byte-identical for every failure except the
/// cap — there the refusal must name the file, its size and the cap, or the operator
/// is told "could not snapshot" about a tree that snapshotted fine yesterday and
/// has no way to learn what grew.
/// The entry name goes through `textShown`, the same defang every other target-chosen
/// string in a refusal takes (#26/#167). It did not when this function was written — the
/// name was spliced raw into the message, four lines of reasoning away from
/// `refuseUnsupportedEntry`, which defangs. A Unix name may hold newlines and escape
/// introducers; unlike the JSON side there is no second escaper behind the text.
///
/// The *verdict* every snapshot failure refuses with depends on `run_phase`: SETUP_ERROR
/// only at the initial snapshot, UNKNOWN at every site at or past the recording run —
/// `state_file_too_large` for the cap (#330), `state_unsnapshotable` for the rest (#351).
/// The wording does not change with the verdict; whichever message applies, it applies on
/// both sides of the split, so this reads as one refusal with two exits rather than two
/// refusals. `OutOfMemory` is the one failure that stays SETUP_ERROR at every site, on the
/// rule `spawnFailure` states — see the guard below.
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
        // rejected a per-site parameter to avoid. Computed here, the mistake has no
        // shape to take, and inverting this line reddens the cap leg and the non-cap
        // leg together — one expression cannot be half-broken.
        // **Exhaustive over `SnapshotError` on purpose**, like `snapshotDetail` below and
        // for the same reason: an error member added later must not silently take a
        // neighbour's reason. The `if` this replaced would have handed `TreeTooLarge` the
        // catch-all with nothing to notice (#323).
        //
        // The reason and the no-arena wording are decided **together, in one switch**.
        // They were two, listing the same five errors twice, and the pairing between a
        // reason and the sentence that goes with it was then a thing two lists had to
        // agree about — with only one of them reachable, so a disagreement would sit
        // there unobserved. One arm cannot disagree with itself.
        //
        // The next step is decided in the same arm (#274), and it is what splits the
        // `state_unsnapshotable` group: one reason, several remedies — a tree the
        // operator shapes (too deep, a path too long), an entry the run left that this
        // user cannot read (#535, chosen on the measured errno by `readFailedStep`), an
        // environment the operator fixes (an entry that could not be classified, or a
        // read that failed some other way), and a sorted-entry invariant that is
        // Sideeye's to fix. A reason-keyed table could not say that.
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
            // An entry the walk could not read (#535). The step is rendered only past
            // the recording run — before it, `snapshotRefusal` calls `setupError`, which
            // carries no step — and by then the initial snapshot has read the tree, so
            // the entry appeared during the run. Which step depends on *why* the read
            // failed, and only the measured errno can say: see `readFailedStep`.
            error.ReadFailed => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
                .next = readFailedStep(diag.entry.errno),
                .setup = .environment,
            },
            // An entry whose kind could not be told: `statNoFollow` failing is the
            // filesystem's answer, and the environment is where that is fixed.
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
                // The one snapshot failure that is Sideeye's own (#518): the SETUP_ERROR class
                // is chosen here, in the arm that already calls it a defect, and not from the
                // reason — `state_unsnapshotable` covers this and four environment failures.
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
        //
        // The wording comes from the same arm the reason did. As `switch (reason) { ...
        // else }` over `UnknownReason` it was not compiler-covered at all, and a new
        // reason silently took the catch-all sentence — the mistake the switch above is
        // exhaustive to prevent, one level down and on the path nothing exercises (#323).
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
    // No measured errno: the entry is still named, and no number is invented.
    diag.entry.errno = null;
    diag.entry.kind = .symlink;
    const without = report.snapshotDetail(a, error.ReadFailed, "could not snapshot a crashed state", &diag);
    try std.testing.expect(std.mem.indexOf(u8, without, "m_inmail.6c3e.69 could not be read (symlink)") != null);
    try std.testing.expect(std.mem.indexOf(u8, without, "errno") == null);
    // An entry that could not be classified is named too, with no errno clause.
    diag.entry.kind = .unclassified;
    const cls = report.snapshotDetail(a, error.ClassifyFailed, "could not snapshot a crashed state", &diag);
    try std.testing.expect(std.mem.indexOf(u8, cls, "m_inmail.6c3e.69 could not be classified") != null);
    try std.testing.expect(std.mem.indexOf(u8, cls, "errno") == null);
    // A diag nobody filled keeps the old sentence rather than naming an empty path.
    var empty: engine.SnapshotDiag = .{};
    const bare = report.snapshotDetail(a, error.ReadFailed, "could not snapshot a crashed state", &empty);
    try std.testing.expectEqualStrings("could not snapshot a crashed state: a file or symlink inside the state tree could not be read", bare);
    // The names the table knows, and a number it does not.
    try std.testing.expectEqualStrings(" EACCES", report.errnoName(posix.EACCES));
    try std.testing.expectEqualStrings("", report.errnoName(12345));
}

/// A snapshot refusal's one exit, split by how far the run has got (#330, widened by #351).
/// `setup` is the SETUP_ERROR class the raising arm chose beside its reason and step
/// (#518): decided on `SnapshotError`, where an unsorted entry list is known to be
/// Sideeye's own, not on `UnknownReason`, where it hides among four environment failures.
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
/// **Every trace read allocates from the shared budget, and no call site gets a say**
/// (#377). The defect this closes is that a property held by "there are two call sites
/// and both do the right thing" stops holding the moment someone adds a third — which
/// had already happened when it was written.
///
/// What enforces it is `engine.readTraceCapped`'s signature, not this function: it takes
/// a `*TraceBudget`, so a read site cannot supply a plain allocator even by reaching past
/// this wrapper. An earlier version injected the budget here instead, which left the
/// engine's public API accepting any allocator while the documents claimed otherwise.
/// All this wrapper does now is hand over the process-wide budget and turn a read that
/// could not happen at all into a SETUP ERROR.
pub fn readTraceOrRefuse(path: []const u8, cap: usize, setup_msg: []const u8) engine.TraceInfo {
    // Not `.?`: an ordering mistake should report itself rather than panic. It cannot
    // happen today — `main` installs the budget before any argument is parsed — and a
    // local budget could not stand in if it could, because the `TraceInfo` returned here
    // outlives this frame and frees through the budget's child.
    const b = trace_budget orelse setupError(.internal, "internal: a trace was read before the whole-trace ceiling was installed");
    return engine.readTraceCapped(b, path, cap) catch setupError(.environment, setup_msg);
}

/// The cap's refusal, separate from the read so a caller can classify first. The
/// recording site does exactly that: the comment above `engine.classify` promises every
/// UNKNOWN below it reports the classification that existed rather than the placeholder,
/// and L0 comes from the snapshots, which an oversized trace does not affect. Refusing
/// at the read would have made this the one structural UNKNOWN reporting "not
/// classified" — a regression a simplification pass introduced and review caught.
///
/// The cost of the split, stated because it is the defect this issue is about: nothing
/// forces a caller to reach this. A read site can read and never answer, which is
/// exactly how the world loop came to refuse with `kill_did_not_land`. What holds it
/// instead is the acceptance leg, which drives the recording and world sites through
/// lowered-cap engines and fails on the reason rather than the exit code; a site added
/// without an answer has no leg and is caught in review, not by the compiler.
///
/// **There are three read sites, not two** — the third arrived with `preflight --twice`
/// (#199) and answers, but has no leg of its own, which it says where it stands. The
/// sentence above used to say "a third read site COULD read and never answer", written
/// while the third already existed: the count was a claim nothing rechecked, which is
/// exactly what #377 is about. The per-read cap's pairing is still a rule callers must
/// follow; **the whole-trace ceiling is not** — that one lives inside
/// `readTraceOrRefuse`, where a site cannot fail to reach it.
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

/// The trace read broke its cap (#324). Every read site refuses the same way, so the
/// wording lives once; `where` names which read it was. (It said "both" until #377
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

/// The whole-trace ceiling refused an allocation (#377, ADR 0033).
///
/// The message says what `trace_too_large`'s does not: **the trace being read may be
/// small**. What ran out is the ceiling every live trace shares, so an operator sent to
/// look for one oversized file would find none — which is the reason this is a separate
/// `unknown_reason` and not a second wording of the per-read one.
/// `wanted` is not optional, unlike the per-file cap's size: that one comes from an
/// `lseek` that can fail, this one from the budget's own record of the request it turned
/// down, so there is no "a size nobody measured" case to guard against here.
fn traceBudgetExhausted(wanted: usize, where: []const u8, limit: usize) noreturn {
    if (json_arena) |ja| {
        unknown(.trace_budget_exhausted, std.fmt.allocPrint(ja, "reading the trace from {s} would have taken this engine past the ceiling every trace it holds at once must fit under: a {d}-byte allocation against a {d}-byte ceiling. Each trace involved may be well under the per-read cap — what ran out is the sum", .{ where, wanted, limit }) catch "the engine's whole-trace ceiling was reached", .narrow_state);
    }
    unknown(.trace_budget_exhausted, "the engine's whole-trace ceiling was reached", .narrow_state);
}

/// The budget every trace read allocates from, from the moment `main` installs it
/// (#377, ADR 0033). One per process, shared by every read site, and the reason
/// `readTraceOrRefuse` is the only place that chooses an allocator for a trace.
///
/// A pointer rather than the object: the object lives as a local in `main`, which
/// outlives every `TraceInfo` built on it — a budget that died first would leave those
/// arenas holding a dangling child allocator to free through.
pub var trace_budget: ?*engine.TraceBudget = null;

/// The privileged observer, while it is running. Registered the moment it is spawned
/// and cleared when it is stopped, so that the two functions every refusal exits
/// through — `unknown` and `setupError` — can stop it on their way out.
///
/// This is the shape the alternative kept failing in: each refusing call site was
/// supposed to remember to stop the sidecar first, and two of them did not, and each
/// time one forgot, a root `fs_usage` outlived the engine holding kdebug (the single
/// system-wide trace facility) until its `-t` bound — 3:52 of it measured, 741 MB of
/// capture — and every later start on the machine failed with `Resource busy`. An
/// exit that cannot forget is cheaper than a rule that every exit must remember.
const LiveSidecar = struct { pid: c_int, gpa: std.mem.Allocator };
pub var fsu_live: ?LiveSidecar = null;

/// The observer's capture file, from spawn until it has been read. A `defer` on the
/// block that stopped the observer removed it — at that block's closing brace, forty
/// lines before the comparison opened it, so the comparison read nothing and the run
/// refused with "could not be read". Measured on an otherwise green end-to-end run.
/// The file is dropped at exactly two points instead: right after the comparison has
/// the bytes in memory, and inside the two refusal exits, which is where a capture
/// nobody will read again would otherwise be left at hundreds of megabytes.
pub var fsu_capture: ?[]const u8 = null;

pub fn dropCapture() void {
    const c = fsu_capture orelse return;
    fsu_capture = null;
    removeFile(c);
}

/// Stop the registered observer if one is running, and report what the pre-signal
/// observation said. `.had_exited` when nothing was registered, which is the answer
/// every non-fs_usage run gets and costs it nothing.
pub fn stopLiveSidecar() posix.SidecarEnd {
    const live = fsu_live orelse return .had_exited;
    fsu_live = null;
    return posix.stopSidecar(live.gpa, live.pid, &.{ "/usr/bin/sudo", "-n" }, 5000);
}

/// `next` is required, not optional, on purpose (#274): the site that raises a refusal is
/// the one that knows why, and the compiler is what holds every site to choosing. The
/// sentence is rendered exactly once here and handed to both forms — the JSON field and
/// the text line are one value with one definition (DESIGN §13).
pub fn unknown(reason: contract.UnknownReason, detail: []const u8, next: contract.NextStep) noreturn {
    _ = stopLiveSidecar();
    dropCapture();
    const next_step = next.render();
    if (json_path) |jp| if (json_arena) |ja|
        report.writeJsonReport(ja, jp, "UNKNOWN", @intFromEnum(contract.ExitCode.unknown), null, null, reason.name(), null, detail, next_step);
    // The classification lines appear here too. The reason used to be written as
    // "DESIGN §13 demands text and JSON carry identical content, and the JSON below
    // already does" -- false where it stood, on the most divergent path of the three,
    // and §13 no longer says that (ruled 2026-09-01, #280: the JSON is the complete
    // record, the text is the reader's view, and what binds them is that a shared value
    // has one definition). The lines are here because a reader who is being refused
    // still needs to know what was classified. Before the snapshots exist this honestly
    // reads "not classified".
    // `next` sits AFTER the detail line: the acceptance suite reads the detail as the line
    // that follows `UNKNOWN  <reason>`, and that contract predates this line. `processes`
    // goes in the lower block for the same reason and joins the other verdicts there (#123):
    // the JSON has carried this account on every refusal since #405, the ordinary FAIL and
    // PASS blocks both print it, and only the UNKNOWN text left it out — so a reader refused
    // for touching the state could not tell that the engine had followed the subject across
    // an image change. Two text blocks still do not carry it and are not meant to: a
    // `SETUP_ERROR` is one line by design. (The zero-operation PASS rendered its own block until ADR
    // 0091 made it this refusal.)
    // `boundaryAccount()` answers from this run's evidence, not from a capability blurb: a
    // self-exec chain adds "the subject's image replaced N time(s), chain unbroken", a run
    // refused before the trace was read says the account was never established.
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
    // The account block the verdicts share (#711), whose context lines open it — so `cwd` stays
    // under `next` (below `divergence`), where a reader of `recording_run_failed` is: the one
    // line that can name the `cwd` an operation needed and did not get (#647).
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

/// Guards every path that ends in PASS.
///
/// FAIL does not need this — a counterexample is real whether or not the account of the
/// run was complete. "No counterexample found" is only worth something if what was
/// looked at is known. Both exits that used to PASS call this — the one PASS left, and the
/// run with no crash point, which is refused `nothing_could_fail` since ADR 0091 and asks
/// this first: that is the case where the shim saw nothing, which is precisely when the
/// question of whether it *could* see matters most.
///
/// `allow_unverified` exists because macOS has no oracle sideeye can use by default
/// (measured, #181, spike/macos-oracle/): DTrace's syscall provider matches no probes
/// under SIP even as root — `dtruss`, built on it, runs the target and exits 0 with no
/// syscall in its capture — `fs_usage` gave an ordered, attributed, full-path account
/// of the survey's toy but requires root, and Endpoint Security's shipped CLI
/// (`eslogger`) refuses without root plus a Full Disk Access grant.
/// Rather than branch on the platform — which would break the claim that both operating
/// systems produce the same verdict for the same scenario — the caller states the
/// weaker claim deliberately, and the report says which claim was made.
pub fn requireCompleteness(arena: std.mem.Allocator, has_oracle: bool, allow_unverified: bool) void {
    if (has_oracle or allow_unverified) return;
    // The verdict does not branch on the platform (the paragraph above); the step it names
    // does (#702). macOS refuses `--oracle` outright — it runs strace — so the sentence there
    // names the witness macOS has. `supervised` is Linux only, so its sentence keeps one.
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

/// Linux-only PATH discovery used by refusal hints: the first absolute PATH entry
/// holding an executable `strace`, or null. Relative and empty PATH entries are
/// skipped — the hint must name a path that means the same thing wherever the
/// user pastes it (#78).
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

/// The refusal for a define command that cannot be started (#701, ADR 0092), or null when
/// `image.startable` found nothing to say. `argv` is the command already split by the caller
/// (`commandArgv` stays in `main.zig`, where the freeze audit reads surface 1); an empty one is
/// not judged, because the site that spawns it refuses an empty command by name. `role`
/// is the define key — `setup`, `operation`, `check` — because under `--config` argv[0] is
/// already the toml-resolved absolute path and the spelling the author typed is gone; the key
/// and the resolved file are what identify it.
///
/// `cwd` is the directory the command will run in: the declared one, or Sideeye's own when
/// none was declared, so a relative name is reported as the absolute file it would have been.
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

/// The toml's own directory, resolved, set once by `main.zig` when `--config` named a regular
/// file — null for flags, for a case, and for a config read from a pipe (`/dev/stdin`, a process
/// substitution), where "add cwd = \".\"" would point at `/dev`. Read by `cwdObservation`.
pub var toml_dir: ?[]const u8 = null;

/// What was observed about where a failed command ran (#700, ADR 0093), or null.
///
/// A toml resolves its own paths and argv[0] against its directory (ADR 0007), and every other
/// argument against the directory the command runs in — Sideeye's own when no `cwd` is declared.
/// So when a command read from a toml failed, this looks for the one fact that says the two
/// came apart: an argument of THAT command (not of the define's others) that names something
/// present under the toml's directory and absent under the one the command ran in. Found, it is
/// returned as a clause for the detail; the caller's `next_step` then names the line to add
/// (`cwdStep`). Not found, nothing is said — no guess at a cause (ADR 0086 declined that).
///
/// Every element after argv[0] is tried, and the value of an `--opt=value`; a name that starts
/// with `/` is not relative and is skipped. A name is tried, then each directory above it
/// (`./state/config.json`, then `./state`), because the commonest relative argument names a file
/// the command is about to create — under no directory yet — inside one that is under the
/// toml's and not under the other (the case #700 was measured on). The walk stops at the first
/// name present where the command ran: below it, the two directories no longer differ. Both
/// directories are the resolved spellings the run already holds (`toml_dir`,
/// `report.command_cwd`), so equal directories say nothing.
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

/// The step for a refusal `cwdObservation` found something for: `declare_cwd` where the site
/// would have said `fix_define` or one of the recording run's two steps from #710, and the site's
/// own step everywhere else — above all
/// `syscalls_may_have_killed`, whose sentence says to check before changing the define.
pub fn cwdStep(observation: ?[]const u8, step: contract.NextStep) contract.NextStep {
    if (observation == null) return step;
    // The recording run's two steps from #710 (ADR 0097) are what those sites say instead of
    // `fix_define` now, and the observation outranks them the way it outranked that: the run
    // read an argument from the wrong directory, which explains its ending better than running
    // it by hand would.
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

/// `detail`, with the observation as its last clause when there is one — and the line to add
/// beside it whenever no `next_step` will name it: a SETUP ERROR has none (`step` null), and
/// under `--observe syscalls` the step stays `syscalls_may_have_killed`, which says to check
/// before changing the define (#700 review). Where the step is `declare_cwd`, the detail keeps
/// the observation and the step the action, ADR 0030's division.
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

    // A file still to be created, inside a directory that is under the toml's only: the
    // directory is what is named (the shape #700 was measured on).
    var db: [192]u8 = undefined;
    const state_t = try std.fmt.bufPrintZ(&db, "{s}/state", .{toml_z});
    _ = posix.mkdir(state_t.ptr, 0o755);
    defer _ = posix.rmdir(state_t.ptr);
    const nested = cwdObservation(a, &.{ "./cfgset", "./state/config.json", "theme" }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, nested, "./state is under the toml's directory "));
    // Found: `./seed` and `--in=seed` are under the toml's directory only.
    const o = cwdObservation(a, &.{ "/bin/cp", "./seed", "out" }) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.startsWith(u8, o, "./seed is under the toml's directory "));
    try std.testing.expect(cwdObservation(a, &.{ "tool", "--in=seed" }) != null);
    try std.testing.expectEqual(contract.NextStep.declare_cwd, cwdStep(o, .fix_define));
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, cwdStep(o, .syscalls_may_have_killed));
    // Not found: present in both, present in neither, absolute, a flag without a value, argv[0].
    try std.testing.expect(cwdObservation(a, &.{ "tool", "both", "nothing", "/abs/seed", "-v" }) == null);
    try std.testing.expect(cwdObservation(a, &.{"seed"}) == null);
    try std.testing.expectEqual(contract.NextStep.fix_define, cwdStep(null, .fix_define));
    // The clause carries the line to add unless `declare_cwd` is the step that names it.
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, .declare_cwd), "add cwd") == null);
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, .syscalls_may_have_killed), "add cwd = \".\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, withObservation(a, "d", o, null), "add cwd = \".\"") != null);
    try std.testing.expectEqualStrings("d", withObservation(a, "d", null, null));
    // Not asked at all: a declared cwd, the same directory, no toml.
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
///
/// `reason` is required, not optional, on purpose (#518, ADR 0057) — the rule `unknown()`
/// keeps for `next`: the site that refuses is the one that knows which class it is, and the
/// compiler is what holds every site to choosing. A site that funnels several failures
/// chooses by an exhaustive switch on what it holds (`spawnFailure`, `snapshotRefusal`,
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

/// A `runChild*` failure, refused with the right name **and the right verdict**.
///
/// `WaitFailed` names itself rather than borrowing the caller's wording: the child ran,
/// but its exit status was never read, so nothing can be said about how it ended. Every
/// verdict downstream rests on that status, and the defect #264 was filed for is exactly
/// what happens when the distinction is dropped — an unread status reads as `.exited = 0`,
/// which in a design where every explored world dies by signal becomes a confident
/// `kill_did_not_land`. The other two failures keep `doing`, which says what was starting.
///
/// `phase` decides the verdict for `WaitFailed`, not just its wording. A child *ran* and
/// its status was never read, which is a statement about the target's execution, so while
/// worlds are being explored it has to be UNKNOWN — the distinction `recording_run_failed`
/// and `baseline_run_failed` already draw for the same phase. A first version of #264's
/// fix sent every call site to `setupError` and would have published
/// `verdict: "SETUP_ERROR"` for a mid-exploration wait failure: honest about the failure,
/// wrong about what it was about, and a silent change to the serialized shape.
///
/// **The other members are phase-independent and that is deliberate**, which DESIGN's
/// exit-code table now says: `ForkFailed`, `OutOfMemory`, `StdinUnavailable` and
/// `CaptureUnavailable` are all "the engine needed something and could not get it", with
/// no child whose execution could be described. That row used to read "before exploration
/// began" and the first three already contradicted it; #469 made the class reachable
/// (2026-09-04, owner decision) and the row was corrected rather than the code.
///
/// How far the run has got. Three refusals share this one vocabulary rather than
/// growing a second, and all ask the same question — did any of the define run before
/// this failed? `spawnFailure` takes it as a parameter (the caller knows which step it
/// was starting); the per-file snapshot cap (#330) and the rewrite disposition (#363)
/// read `run_phase` below.
const SpawnPhase = enum {
    /// Before any world runs: `--setup`, the initial snapshot. A failure here really does
    /// mean the define never got started.
    before_exploration,
    /// The recording run onward. The define is running; refusing is UNKNOWN.
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
    // A child's stdin source that could not be opened (#263) is refused in the parent,
    // before any fork, and named here: the caller's `doing` says which step was starting,
    // and this says why it never started. SETUP_ERROR in either phase, the same reading
    // as a fork failure below — the environment, not the target, is what could not be
    // arranged, and no child ran whose exit status could be read as anything.
    if (e == error.StdinUnavailable) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: /dev/null could not be opened, so the command could not be started with its stdin at end-of-file", .{doing}) catch doing);
    }
    // The child's stdout capture, refused in the parent before any fork (#469). Same
    // phase-independent SETUP_ERROR as the stdin arm above and for the same reason: the
    // environment, not the target, is what could not be arranged, and no child ran whose
    // exit status could be read as anything.
    //
    // **This arm is not enforced by the compiler.** The chain above is a run of `if`s
    // ending in a bare `setupError(doing)`, so a member of `SpawnError` with no arm here
    // is not a build error — it silently becomes "could not run --operation" with no
    // reason. Adding a member to that error set means adding a line here, and the only
    // thing that says so is this paragraph and the acceptance leg that reads the text.
    //
    // The message names the path because the operator's remedy is about that path — an
    // ordinary run has nothing at it, so anything that stopped the open is either
    // something else's file or a work directory that is not theirs alone.
    //
    // **Phase-independent, and unlike its two neighbours this one is reachable during
    // exploration** — a blocked capture path is the threat the work directory actually
    // has, which is why #469 exists. Weighed against making it UNKNOWN there, and the
    // owner chose this (2026-09-04): the frozen `unknown_reason` set has no member for
    // "the parent could not arrange a world's capture", so the UNKNOWN form would have
    // had to borrow a name — `recording_run_failed` at one site, `checker_not_falsified`
    // at another, and nothing honest at the world loop — which is the misattribution
    // this change removes, reintroduced one layer down. DESIGN's exit-code table said
    // "before exploration began" and now says what the code does; it was already false
    // for `ForkFailed` and `OutOfMemory` below, which nothing had made reachable.
    if (e == error.CaptureUnavailable) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: the command's stdout capture in the work directory could not be opened. The engine refuses a capture path that is a symlink, or that already holds a file or directory the engine did not just create — check --work, and what is at the capture path inside it", .{doing}) catch doing);
    }
    // The run's cgroup (contract v17, #559), refused in the parent the way the capture is: the
    // cgroup or the pipe its child waits on could not be made, or the child — forked, and
    // waiting without running — could not be moved into it. The environment is what could not be arranged, in either phase, and
    // nothing of the command ran.
    if (e == error.CgroupJoinFailed) {
        var buf: [512]u8 = undefined;
        setupError(reason, std.fmt.bufPrint(&buf, "{s}: the engine could not arrange the run's cgroup — make it, open the pipe its child waits on, or move the child into it — so nothing of the command ran (a child already forked was killed first). Its own cgroup took a move and a new child cgroup when it was probed, so look at what changed since: permissions or limits on the cgroup, or the descriptors the engine may still open", .{doing}) catch doing);
    }
    // Fork and allocation failures are environment problems in either phase, and the
    // caller's wording already says which step was starting.
    setupError(reason, doing);
}

/// The text-shown spelling of a target-chosen string (#26): control bytes
/// defanged through the same predicate as the l0 note — one predicate, not
/// two that drift. The FAIL block's JSON (`earliest.*`) still reads the raw
/// variables — `jsonString` escapes controls and substitutes U+FFFD for
/// invalid UTF-8, so valid names round-trip there; prose fields built from
/// this spelling (the l0 note, refusal messages) carry the defanged form in
/// JSON too, the same bytes as the text (#167). `?` and not a hex spelling
/// on purpose: one `?` per defanged unit, never more bytes out than in, so a
/// hostile name can never bloat the report past its output buffer and erase
/// the counterexample it names.
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

/// How many unaccounted paths the refusal names before it stops counting out loud.
/// The count itself is never truncated — a caller reading three names must still be
/// told the run had thirty.
const unaccounted_shown = 4;

/// Refuse when the judged state changed at a path no recorded operation names (#405).
///
/// The account this rests on is the shim's, and the shim sees only what crosses the
/// libc boundary it interposes. A raw syscall is invisible to it — so was a raw-forked
/// child's write, measured on the shipped build reaching PASS with the child's file
/// still in the directory. The existing zero-ops detector cannot see that: it asks
/// whether *nothing* was counted, and the parent's own recorded write answers no.
///
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
    //
    // Sized from the tree rather than fixed: a bound smaller than the difference count
    // would still report `total` correctly, but the names it printed would be an
    // arbitrary prefix of the problem.
    const cap = initial.entries.items.len + final.entries.items.len + 1;
    const diffs = gpa.alloc(engine.Difference, cap) catch setupError(.environment, "out of memory");
    defer gpa.free(diffs);
    const dc = engine.diffSnapshots(initial, final, diffs);
    if (dc.equal()) return;

    const found = gpa.alloc(engine.Unaccounted, dc.stored + 1) catch setupError(.environment, "out of memory");
    defer gpa.free(found);

    // The tree's own symlinks, from the snapshots rather than from the filesystem. The
    // shim normalises path arguments lexically, so an operation on `cur/f` under
    // `cur -> v1` is recorded as `cur/f` while the difference sits at `v1/f`; joining the
    // two spellings without this turned a fully observed run into a refusal (measured:
    // one unlink through an interior symlink, PASS on the shipped 1.0.0, UNKNOWN here).
    // Reading the live tree instead would answer about the tree after the run, not the
    // one the operation crossed.
    var links: std.ArrayList(engine.Link) = .empty;
    engine.collectLinks(arena, initial, final, &links) catch setupError(.environment, "out of memory");
    const scratch = gpa.alloc(u8, 2 * contract.max_path) catch setupError(.environment, "out of memory");
    defer gpa.free(scratch);

    const r = engine.reconcile(diffs[0..dc.stored], ops, links.items, root, alt, scratch, found);

    // Disclosed on every run that has one, not only on the refusals: a reader deciding
    // what a PASS covers needs to know a subtree went unexamined. Twice, on purpose — the
    // number is the machine's copy and cannot be lost to an allocation failure, and the
    // sentence rides `l0_note`, the line that already says what the judgement covered.
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

/// What, besides a checker, could fail in a crash world of this run (#683, ADR 0091), read
/// once from the recording: how many of the paths the built-in atomicity invariant judges
/// could have changed, and whether the post-success invariant has anything of its own to judge.
pub const Judgeable = struct {
    /// Judged paths that ended other than they began, or that a crash point named (fsync and
    /// mkdir aside) or renamed a directory above (`engine.namedByMutation`). A judged path
    /// outside this set holds its pre content in every crash world, so comparing it can fail
    /// nowhere — ggshield's "6/6 over files it did not write".
    touched: u32,
    /// A non-scratch entry that only one snapshot holds. The marker's invariant judges shared
    /// paths against the post content too, but a shared path the operation did not touch holds
    /// that content in every world; what it adds over `touched` is the created and the removed.
    one_sided: bool,
    /// How many paths the atomicity invariant judges, `touched` among them — the plan's size,
    /// carried here so the refusal and the verdict line read it from the same measurement.
    judged: usize,
};

/// `Judgeable` for this recording. `ops` are the recording's own records, the set
/// `reconcileOrRefuse` reads; `alt` is the alternate spelling of the root, or "".
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
        // Ended other than it began: a crash world can stand between the two, whatever the
        // records say — and an unrecorded change that `reconcileOrRefuse` let through
        // because a `close` named the path still lands here (R1 of the plan, M1).
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

/// A declared checker whose command splits to no words has nothing to run — `check = " "` gets
/// past the config parser, and `unstartable` judges an argv only once it has a first word. The
/// exploration refuses it ahead of the falsification, and `preflight --config` at the same
/// point (#704 review), so the two give the same answer for it.
pub fn checkerArgv(split: anyerror![]const []const u8) []const []const u8 {
    const cargv = split catch setupError(.define_invalid, "--check is empty");
    if (cargv.len == 0) setupError(.define_invalid, "--check is empty");
    return cargv;
}

/// A declared checker against an initial state with nothing in it to corrupt: the
/// falsification (DESIGN §14-13) has nothing to break, so the checker cannot be shown to
/// respond. One function for the exploration's falsification and for `preflight --config`
/// (#704, ADR 0094), which reaches the same answer from the same snapshot before any world,
/// so the two say it in the same words. Called with a crash point: with none, both answer
/// `nothing_could_fail` first.
pub fn refuseNothingToCorrupt(initial: engine.Snapshot) void {
    if (engine.countCorruptible(initial) == 0)
        unknown(.checker_not_falsified, "the state directory holds no files or symlinks, so there was nothing to corrupt and the checker could not be tested", .fix_define);
}

/// The exploration with no crash point (#682, ADR 0091): it is UNKNOWN, not PASS, with or
/// without a checker — a checker has no world to run in. Raised in `preflight` too, which the
/// README promises names the detector a real run would use. Without an oracle the detail says
/// what that leaves open: an operation that rewrote a file with the bytes it already held
/// through a raw syscall changes no snapshot and leaves no record, so "nothing" is the shim's
/// word alone.
pub fn refuseNoCrashPoint(arena: std.mem.Allocator, has_oracle: bool, observation: ?[]const u8) noreturn {
    const who = boundary.recorder();
    const detail = if (has_oracle)
        "the operation performed no state-changing operation inside the state directory, so there was no crash point and no world in which anything could fail"
    else
        std.fmt.allocPrint(arena, "{s} recorded no state-changing operation inside the state directory, so there was no crash point and no world in which anything could fail; no oracle ran, so an operation {s} did not see is not ruled out", .{ who, who }) catch
            "no state-changing operation was recorded inside the state directory, so there was no crash point and no world in which anything could fail; no oracle ran, so an operation that was not seen is not ruled out";
    // #700 (ADR 0093): an operation whose relative argument was read under the wrong directory
    // can find nothing to do there and exit 0 — or write outside the state — and record nothing.
    // Where the operation's arguments show that (`cwdObservation`), the step names the line to
    // add instead of saying the operation changed nothing.
    const step: contract.NextStep = if (observation != null) .declare_cwd else .nothing_in_state;
    unknown(.nothing_could_fail, withObservation(arena, detail, observation, step), step);
}

/// An exploration with crash points in which still nothing could have failed (#683, ADR 0091).
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

/// The step for `requireSomethingCouldFail`. A marker judges what only one snapshot holds;
/// where there is nothing of that kind — a define that declared every changed path scratch,
/// say — offering one would be offering what cannot help (R1 of the diff), and where one is
/// declared already, asking for it would ask for what the define has.
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
        // The same bytes, swapped in atomically: unchanged, and still named.
        .{ .class = .rename, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/same.txt.tmp", .aux = "/tmp/s/same.txt" },
        // Records that never count: an fsync of the untouched file, a mkdir of the root.
        .{ .class = .fsync, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/keep.txt", .aux = "" },
        .{ .class = .mkdir, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
    };
    // `grown.txt` changed with no record naming it (the M1 shape) and still counts.
    try std.testing.expectEqual(@as(u32, 2), countTouched(plan, &ops, &.{}, "/tmp/s", "", &scratch));
    // With nothing named and nothing changed, nothing counts: the control.
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

/// A SETUP ERROR whose sentence carries values; when even the sentence cannot be built
/// the format string itself is the fallback, so the refusal still names its subject.
pub fn setupErrorFmt(arena: std.mem.Allocator, reason: contract.SetupErrorReason, comptime fmt: []const u8, args: anytype) noreturn {
    setupError(reason, std.fmt.allocPrint(arena, fmt, args) catch fmt);
}

test "resolveFailure names the shallowest missing directory, and the errno otherwise (#486)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // ENOENT: the answer is a directory the operator can create, not the literal parent.
    // `/` exists, so a deep absent path must name the shallowest absent step.
    const deep = resolveFailure(arena, "/nope-for-test/a/b/leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, deep, "/nope-for-test does not exist") != null);
    try std.testing.expect(std.mem.indexOf(u8, deep, "the directory / does not exist") == null);

    // A bare relative leaf has no directory above it: saying "." would be false.
    const bare = resolveFailure(arena, "leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, bare, "no directory above it") != null);
    try std.testing.expect(std.mem.indexOf(u8, bare, "the directory . ") == null);

    // Any other errno is named, not reduced to a number -- the four-arm switch this
    // replaced covered four of ~130 and dropped the rest to a bare integer, which is
    // the shape #486 is about.
    const denied = resolveFailure(arena, "/x/y", @intFromEnum(std.posix.E.ACCES));
    try std.testing.expect(std.mem.indexOf(u8, denied, "ACCES") != null);
    const io = resolveFailure(arena, "/x/y", @intFromEnum(std.posix.E.IO));
    try std.testing.expect(std.mem.indexOf(u8, io, "IO") != null);

    // Control bytes from a case file's `define.state` do not reach the console raw (#266).
    const forged = resolveFailure(arena, "/nope-for-test\x1b[1m/leaf", posix.ENOENT);
    try std.testing.expect(std.mem.indexOf(u8, forged, "\x1b") == null);
}

/// Why `realpath` refused, in the words of the command the operator types next (#486).
///
/// The old sentence said the path "could not be resolved to an absolute path" about a
/// path that visibly *is* absolute, so the first move it invites is to re-check the
/// spelling of an already-correct flag. What was observed is the errno, and for the
/// common case (`ENOENT`) the actionable half of it is which directory is missing:
/// the engine creates the leaf and never the parent, and that contract is written
/// nowhere else.
///
/// Read the errno BEFORE any cleanup call — `rmdir`/`undoSetupMkdirs` overwrite it.
pub fn resolveFailure(arena: std.mem.Allocator, path: []const u8, err: c_int) []const u8 {
    if (err == posix.ENOENT) {
        // The *shallowest* missing component, not the literal parent: for
        // `--state /nope/deep/leaf` with `/nope` absent, naming `/nope/deep` sends the
        // operator to a `mkdir` that fails the same way. Walking up until something
        // exists is the only form of this sentence that names a directory they can
        // actually create.
        //
        // `dirname` returning null (a bare relative leaf) means there is no directory
        // above it to be missing, so the generic clause is the honest one — the earlier
        // version said "the parent directory . does not exist", which is false.
        const parent = std.fs.path.dirname(path) orelse
            return "it could not be resolved: ENOENT, and the name has no directory above it";
        // Keep the shallowest component that is still missing, rather than stopping on
        // the first one that exists: the loop below walks up, and the answer is the last
        // absent step before something existed. Stopping *at* the existing directory
        // named `/` in the first version, which is both true and useless.
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
    // The tag rather than a hand-written switch, for the reason `OpClass.name` records
    // (#280): a switch spelling its own tags covers only the arms someone thought of.
    // The first version here had four, out of the ~130 `std.posix.E` holds, so EPERM,
    // EIO and EBADF fell to a bare number — which is the "restates its own name" shape
    // #486 is about. `E` is non-exhaustive, so an unlisted value returns null rather
    // than trapping, and the number is what remains to say.
    if (std.enums.tagName(std.posix.E, @as(std.posix.E, @enumFromInt(err)))) |tag|
        return std.fmt.allocPrint(arena, "it could not be resolved: {s} (errno {d})", .{ tag, err }) catch "it could not be resolved";
    return std.fmt.allocPrint(arena, "it could not be resolved (errno {d})", .{err}) catch "it could not be resolved";
}

/// The destructive root stopped being the directory this run resolved.
///
/// Two decisions live here, deliberately in one pure function so they cannot drift.
///
/// **The error decides the wording.** Every `restore`/`freshDir`/`corruptState` call
/// site folds its errors into one message, which used to swallow the one error that
/// says something different: `UnsafeRoot` means the state directory was replaced between
/// the resolution and the destructive step, not that the step failed. It no longer comes
/// only from `assertRootResolvesToItself` — since #338 the identity comparison in
/// `openRootDir` and `createRoot`'s `EEXIST` rule raise it too, which is why the wording
/// below names a fourth cause. That is an actionable difference — a setup command or the
/// recorded operation left a link there — and it is the case an acceptance check can
/// assert on.
///
/// **The phase decides the verdict** (#330's discipline, third application after
/// `spawnFailure` and `snapshotRefusal`): before the recording run a rewrite that
/// fails really is a setup problem, and from the recording run onward the define is
/// running, so exit 3 would claim it never did (#363).
///
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
        // Four causes now, and the fourth reads nothing like the other three. #327 added
        // the third by moving a non-directory at the root from DeleteFailed to UnsafeRoot,
        // which is the right class — the root is not a thing to rewrite. #338 added the
        // fourth, and it is the one an operator would otherwise stare at: the path is a
        // perfectly ordinary readable directory that resolves to itself, and it is simply
        // not the one this run has anything to do with.
        //
        // "Vetted or created", not "the one that was checked": #338 raises this on two
        // paths and the narrower wording covers only one. Either the directory checked
        // earlier was replaced by another, or nothing was there when the check looked and
        // a directory appeared before this run could make its own. A refusal that states
        // the wrong cause is worse than one that states none, which is why each is named,
        // and why the message is generated from the error rather than written at the call
        // sites: three of the four arrived after the first wording.
        //
        // "Destructive access", not "empty": the same refusal serves the falsification
        // probe's corruption (#363), which overwrites rather than empties.
        error.UnsafeRoot => "the state directory could not be confirmed as the one this run resolved: it now resolves elsewhere (a symlink or a moved parent), it is not a directory, it could not be read at all, or the path names a directory this run neither vetted nor created (one appeared, or replaced another, between the check and the open). Refusing destructive access to it",
        error.DeleteFailed, error.CreateFailed, error.PathTooLong => doing,
    };
    return .{
        .exit = switch (phase) {
            .before_exploration => .setup,
            .exploring => .unknown,
        },
        .detail = detail,
        // Decided per cause, beside the wording and for the same reason (#274): a path
        // the engine cannot spell is the operator's tree to shorten; a root that
        // resolves elsewhere, or a delete or create the filesystem refused, is the
        // environment to put right. None is the define's.
        // Step and SETUP_ERROR class, from one switch because they split the same way
        // (#274 for the step, #518 for the class): a path the engine cannot spell is the
        // operator's tree to shorten and the define's as written; a root that resolves
        // elsewhere, or a delete or create the filesystem refused, is the environment to
        // put right and the machine's answer. `UnsafeRoot` here and the parse-time
        // `assertSafeRoot` refusal are two classes on purpose: at parse time the define
        // named a root nothing sacrificial belongs in (`define_invalid`); here a root that
        // was vetted moved under the run (`environment`).
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
    // Every member, both phases. The production switch is exhaustive, so a fifth
    // RestoreError member stops compilation there; this count keeps the TEST honest
    // about having covered the whole set when that day comes.
    const errs = [_]engine.RestoreError{
        error.UnsafeRoot, error.DeleteFailed, error.CreateFailed, error.PathTooLong,
    };
    try std.testing.expectEqual(@as(usize, 4), @typeInfo(engine.RestoreError).error_set.?.len);
    for (errs) |e| {
        for ([_]SpawnPhase{ .before_exploration, .exploring }) |phase| {
            const d = rewriteFailureDisposition(phase, e, doing);
            // The phase alone decides the exit.
            try std.testing.expectEqual(phase == .exploring, d.exit == .unknown);
            // The error alone decides the wording, phase-invariantly: what to tell
            // the operator does not change with when it happened.
            if (e == error.UnsafeRoot) {
                try std.testing.expect(
                    std.mem.indexOf(u8, d.detail, "Refusing destructive access") != null,
                );
            } else {
                try std.testing.expectEqualStrings(doing, d.detail);
            }
            // The SETUP_ERROR class, also phase-invariant and also decided by the error
            // (#518): a path the engine cannot spell is the define's as written, and the
            // other three are the filesystem's answer. Asserted here because the
            // `define_invalid` arm has no other coverage — the fresh-state acceptance leg
            // reaches the `environment` one only.
            try std.testing.expectEqual(
                if (e == error.PathTooLong) contract.SetupErrorReason.define_invalid else contract.SetupErrorReason.environment,
                d.setup_reason,
            );
        }
    }
}
