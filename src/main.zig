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

/// The trace-read ceiling this binary uses (#324). Zero — the shipped value, written as
/// a literal in build.zig rather than as a flag's default — means the engine's own
/// constant. Any other value comes from `-Dtest-trace-cap`, which builds a SEPARATE
/// artifact, so no invocation of the build can lower a released binary's cap. The shape
/// `-Dtest-seq-gap` established, for the same reason: the shipped cap is unreachable by
/// any fixture, and a branch nothing can reach is a branch nothing can check.
///
/// "No invocation of the build" was always the whole of that promise — an edit to the
/// literal is not an invocation, and CI's sha comparison cannot see one because it lands
/// in both arms. Since #365 the literal is held by a test at the bottom of this file.
const trace_cap: usize = if (engine_build_options.trace_cap_override == 0)
    engine.max_trace_bytes
else
    engine_build_options.trace_cap_override;

/// The same for the world read. Separate because the recording read happens first and
/// exits: with one shared override the world branch is unreachable, so a test artifact
/// that caps only this site is what lets the second branch fire at all.
const trace_cap_world: usize = if (engine_build_options.trace_cap_override_world == 0)
    engine.max_trace_bytes
else
    engine_build_options.trace_cap_override_world;

/// Must match `.version` in `build.zig.zon`. They are two hand-written strings for the
/// same number, and they had already drifted: the package said 0.1.0 while `--help` said
/// 0.1.0-dev. A test below holds them together.
pub const version = "1.0.0";

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
        setup: ?config.Command = null,
        operation: config.Command,
        check: ?config.Command = null,
        marker: ?[]const u8 = null,
        // Absent in a case_version 1 file; absent means "exit 0 was the contract",
        // which is exactly what every v1 case was recorded under (ADR 0014).
        expected_status: ?u8 = null,
        /// Present exactly when the case is version 4, the way the argv form is present
        /// exactly in a version 3 or later file: the version moves because the field
        /// arrived, so a define that declared no cwd still saves as the version its other
        /// fields ask for. Always the resolved spelling.
        cwd: ?[]const u8 = null,
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
/// #269, `--stop-when-orphaned`: refuse to start another world once `getppid()` stops
/// answering what it answered at process start. `startup_ppid` is captured at the top of
/// `main`, before anything else runs — parentage only changes when the parent dies, so
/// the comparison needs no pid handed in from outside and nothing that could go stale.
var stop_when_orphaned: bool = false;
var startup_ppid: c_int = 0;
var json_path: ?[]const u8 = null;
var json_arena: ?std.mem.Allocator = null;
var oracle_note: []const u8 = "not run (no --oracle given)";

/// The machine-readable half of the oracle account (#94). Set true at exactly one
/// point — beside the "agreed on N operations" note, after the comparison completed
/// and agreed. Every other outcome keeps the initial false: no --oracle given,
/// --allow-unverified without an oracle, or a comparison cut short by any refusal
/// above it (the two flags are not exclusive: an oracle that ran and agreed sets
/// true even beside an inert --allow-unverified). A fact
/// about the run, never about the verdict — a FAIL stands without an oracle.
var oracle_verified: bool = false;
/// Ownership/permission writes on the state directory (#121, option b): observed by
/// the oracle alone — the shim does not interpose them — and excluded from every
/// verdict input. The default says why absence of a note is not absence of writes:
/// without an oracle nothing can see a chown, and "was not seen" must not read as
/// "did not happen" here any more than anywhere else in this tool.
var metadata_note: []const u8 = "not observable (no oracle ran; the shim does not interpose ownership/permission/timestamp calls)";
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

/// How many differences were attributed wholesale to a directory a recorded rename moved
/// in from outside the judged root (#405, ADR 0032). Zero means the run has no such
/// window — which is the point of carrying it as a number: "no window" is then something
/// a caller reads, not something it infers from the absence of a sentence.
var attributed_to_rename: usize = 0;
/// Non-zero once any file is judged by the history form; widens `not tested`.
var l0_history_count: u32 = 0;
/// What the operation's executable looked like immediately before the recording run
/// started. Read there and not at the refusal, because after the child has exited the
/// same name may resolve somewhere else entirely; see `image.zig`'s header for why a
/// match is still never reported as identity. Null on every path that never spawned.
var rec_image: ?image.Observation = null;
/// The case/replay story (ADR 0009), one variable each read by text and JSON alike
/// (the checker_note pattern). A FAIL sets them to the saved case and its replay
/// command; a replay sets the case to what it was asked to re-verify the moment the
/// file parses, so even a `case_no_longer_applies` refusal names which case it
/// refused — the JSON consumer is the §17 audience and must not need the text.
var case_note: []const u8 = "(none)";
var replay_note: []const u8 = "-";
/// What the run has *established* about process boundaries, as it establishes it.
///
/// Evidence, not prose. The sentence is rendered at report time by `boundaryAccount()`,
/// so a refusal raised at any depth reports what this run actually looked at instead of
/// a claim nobody checked. This field used to be the prose itself, defaulting to
/// `"single process"` — an assertion about the target published on every path where no
/// witness had been able to look, which is the confusion `metadata_note`'s own comment
/// forbids thirty lines above: "was not seen" must not read as "did not happen" here any
/// more than anywhere else in this tool. On macOS with no oracle nothing can see a raw
/// `fork(2)`, and the account said "single process" while a child's file sat in the
/// judged directory (#405).
///
/// Rendering also removes the wholesale-replacement hazard the old shape carried: three
/// assignment sites each overwrote the whole sentence, and the world-only one dropped the
/// image-replacement disclosure the recording had set (#123) with nothing to catch it.
var boundary_ev: BoundaryEvidence = .{};

const BoundaryEvidence = struct {
    /// The completeness observer, and how far it got. Named is not the same as read.
    witness: Witness = .none,
    /// Whether the shim's trace has been read yet. A run refused before that — the
    /// operation exiting the wrong status, the state moving under it — has no account of
    /// its boundaries at all, and the two situations are told apart because "refused
    /// before anyone looked" and "looked and the shim was not there" are different facts.
    trace_read: bool = false,
    /// Whether the shim announced itself in that trace. Until it does, no witness looked.
    shim_reported: bool = false,
    /// The shim's account of the recording run: a boundary record, or a record from a
    /// pid that is not the subject's.
    shim_boundary: bool = false,
    /// A boundary that stays a refusal whatever an oracle says, by its own name.
    shim_hard: ?[]const u8 = null,
    /// A kill-point record from another process: its operations have no crash-point
    /// address, and the run refuses on it.
    shim_foreign_touch: bool = false,
    /// Subject execs whose chain was proven unbroken (#123).
    exec_continuations: u32 = 0,
    /// The oracle saw a non-subject operation on the judged directory.
    oracle_child_touched: bool = false,
    /// What the oracle's *own* account called a boundary — a `clone` carrying
    /// `CLONE_THREAD` or `CLONE_FS`, an `unshare`, a non-primary `setsid`/`setpgid`
    /// (`src/oracle.zig`). The child count cannot express this: a thread emits no pid of
    /// its own, so a run refusing `child_process_detected` on the oracle's evidence had
    /// `children == 0` and read as a single process until review measured it.
    oracle_boundary: ?[]const u8 = null,
    /// A boundary in an explored world. Worlds run with no oracle at all, so nothing
    /// accounts for what the other process did whichever of these applies.
    world_boundary: bool = false,
    /// The subset the recording never crossed, which is the one that refuses (#169).
    world_only: bool = false,
    /// A kill-point record from another process inside an explored world.
    world_foreign_touch: bool = false,
    /// What the shim recorded in preflight's second observed run (#199), if anything.
    /// That run's oracle capture is written and deliberately never parsed, so whatever
    /// it shows is unaccounted for — and with `--oracle` the soft check below does not
    /// even refuse. The report used to print run A's account beside it, unchanged, as
    /// though the second run had not happened.
    second_run: ?[]const u8 = null,

    const Kind = enum {
        strace,
        fs_usage,

        fn name(self: Kind) []const u8 {
            return switch (self) {
                .strace => "strace",
                .fs_usage => "fs_usage",
            };
        }
    };

    /// A union rather than a kind beside a child count, so "no oracle ran and it saw
    /// three other processes" cannot be written down at all.
    const Witness = union(enum) {
        /// No completeness oracle was asked for.
        none,
        /// One was named, and its account never became readable — the capture was
        /// unreadable or defective, or the run refused before the comparison.
        unread: Kind,
        /// Its account was parsed. `children` is the number of other processes in it,
        /// and `lines` how much of it there was — an empty capture parses into an
        /// account of nothing, which is not an observation that there was nothing. The
        /// engine refuses it as `oracle_saw_nothing`, and until review measured it the
        /// account for that refusal read `single process`.
        read: struct { kind: Kind, children: usize, lines: usize },
    };
};

/// Rendered fresh on each call; single-threaded, and no format string reads it twice.
var boundary_buf: [1024]u8 = undefined;

/// The `processes` account. Two clauses at most: what the recording established, and
/// what an explored world added, followed by the image disclosure when one applies.
///
/// Three substrings are load-bearing for checks that hold this code to its behaviour:
/// `spike/acceptance.sh:338` requires "refused" and "explored world" in the world-only
/// account and forbids the pre-#169 "observed for quiescence only"; `spike/acceptance.sh:629`
/// requires "image replaced" in a FAIL that carried a self-exec chain.
fn boundaryAccount() []const u8 {
    var scratch: [512]u8 = undefined;
    const world: []const u8 = if (boundary_ev.world_foreign_touch)
        "; a process other than the subject operated on the judged directory in an explored world"
    else if (boundary_ev.world_only)
        "; a process boundary appeared in an explored world — refused: nothing accounts for what it did"
    else if (boundary_ev.world_boundary)
        "; a process boundary appeared in an explored world, which runs with no oracle"
    else
        "";
    const recording = blk: {
        const c = boundaryRecordingClause(&scratch);
        // The bare assertion has to stay scoped when something follows it: the pre-#405
        // string said "single process in the recording" for exactly this reason, and
        // dropping the qualifier would let a sentence that goes on to disclose a world
        // boundary open by claiming the run had one process.
        if (std.mem.eql(u8, c, "single process") and
            (world.len > 0 or boundary_ev.second_run != null))
            break :blk "single process in the recording";
        break :blk c;
    };
    var second_buf: [256]u8 = undefined;
    const second: []const u8 = if (boundary_ev.second_run) |what|
        std.fmt.bufPrint(&second_buf, "; the second observed run recorded {s}, and that run's capture is never parsed, so nothing accounts for it", .{what}) catch
            "; the second observed run recorded a boundary that nothing accounts for"
    else
        "";
    if (boundary_ev.exec_continuations > 0) {
        return std.fmt.bufPrint(
            &boundary_buf,
            "{s}{s}{s}; the subject's image replaced {d} time(s), chain unbroken (#123)",
            .{ recording, world, second, boundary_ev.exec_continuations },
        ) catch "the subject's image replaced, chain unbroken";
    }
    // Not `catch recording`: that slice points into `scratch`, a stack local of this
    // frame, and returning it would hand the caller a dangling pointer on the one path
    // where the buffer is too small. Unreachable at the current lengths — the longest
    // combination measured is 494 of 1024 bytes — but "unreachable" is not a lifetime.
    return std.fmt.bufPrint(&boundary_buf, "{s}{s}{s}", .{ recording, world, second }) catch
        "the process-boundary account did not fit its buffer; treat it as not established";
}

/// The tolerated-children sentence, kept verbatim from before this field became
/// evidence: a FAIL's reader has to see that the window is attributed to the subject
/// alone, and 12 committed report artifacts hold this exact string.
fn toleratedChildrenClause(scratch: []u8, children: usize) []const u8 {
    return std.fmt.bufPrint(scratch, "{d} other process(es) observed; none touched the state directory. A FAIL's window is attributed to the subject only", .{children}) catch
        "other process(es) observed; none touched the state directory";
}

/// What the recording run established, in priority order: an operation by another
/// process outranks the question of whether a boundary was crossed, and a boundary the
/// shim named outranks the witness matrix.
fn boundaryRecordingClause(scratch: []u8) []const u8 {
    const ev = boundary_ev;
    if (!ev.trace_read)
        return "not established: this run was refused before the shim's account of it was read";
    if (!ev.shim_reported)
        return "not established: the shim never announced itself in this run, so nothing observed process boundaries";
    if (ev.shim_foreign_touch or ev.oracle_child_touched)
        return "a process other than the subject operated on the judged directory; its operations have no crash-point address";
    if (ev.shim_hard) |name|
        return std.fmt.bufPrint(scratch, "the shim recorded {s}", .{name}) catch "the shim recorded a boundary that is refused by name";
    // The oracle's own boundary, which the child count cannot carry: a thread emits no
    // pid, so `children` stays 0 and the witness matrix below would read this as an
    // observation of a single process. Measured by review on a `CLONE_THREAD` capture.
    if (ev.oracle_boundary) |name| return switch (ev.witness) {
        .read => |r| std.fmt.bufPrint(scratch, "the {s} account reports {s}, which crosses a process boundary the shim did not record", .{ r.kind.name(), name }) catch
            "the oracle's account reports a call that crosses a process boundary",
        else => "the oracle's account reports a call that crosses a process boundary",
    };
    // An account of nothing is not an observation that there was nothing. The engine
    // refuses this as `oracle_saw_nothing`; before review measured it, the refusal's
    // report said `single process`, because a capture with no lines parses to zero
    // children and zero children read as an observation of none.
    switch (ev.witness) {
        .read => |r| if (r.lines == 0) return if (ev.shim_boundary)
            std.fmt.bufPrint(scratch, "not established: the shim recorded a process boundary and the {s} capture was empty, so nothing was compared", .{r.kind.name()}) catch
                "not established: the oracle's capture was empty, so nothing was compared"
        else
            std.fmt.bufPrint(scratch, "not established: the {s} capture was empty, so nothing was compared and no other process was looked for", .{r.kind.name()}) catch
                "not established: the oracle's capture was empty, so nothing was compared",
        else => {},
    }
    if (ev.shim_boundary) return switch (ev.witness) {
        .none => "the shim recorded a process boundary and no second witness ran",
        .unread => |k| std.fmt.bufPrint(scratch, "the shim recorded a process boundary; the {s} account was not read, so nothing accounts for what the other process did", .{k.name()}) catch
            "the shim recorded a process boundary and the oracle's account was not read",
        .read => |r| if (r.children > 0)
            // Kept verbatim from before this field became evidence: a FAIL's reader has
            // to see that the window is attributed to the subject alone.
            toleratedChildrenClause(scratch, r.children)
        else
            // The two witnesses disagree. Neither is preferred here: a `vfork` that
            // failed leaves a boundary record with no child, and a child the oracle
            // lost leaves the same shape. The run says so rather than picking.
            std.fmt.bufPrint(scratch, "the shim recorded a process boundary and {s} observed no other process; the two accounts disagree and this run does not resolve them", .{r.kind.name()}) catch
                "the shim and the oracle disagree about whether a process boundary happened",
    };
    return switch (ev.witness) {
        // #405: the one assertion the old default made on every unwitnessed run.
        .none => "not established: no boundary was recorded, but the shim sees only libc's own entry points (fork, vfork, posix_spawn, the exec family, pthread_create, setsid, setpgid) — a child created through a raw syscall would not appear here — and no second witness ran",
        .unread => |k| std.fmt.bufPrint(scratch, "not established: no boundary was recorded by the shim, and the {s} account was not read", .{k.name()}) catch
            "not established: no boundary was recorded by the shim, and the oracle's account was not read",
        .read => |r| switch (r.kind) {
            // strace follows children (`-f`), so no other pid in its account is an
            // observation that there was none.
            .strace => if (r.children > 0)
                toleratedChildrenClause(scratch, r.children)
            else
                "single process",
            // fs_usage cannot establish the same thing: its default exclusion list drops
            // whole processes by name, `-e` does not lift it (measured), and ADR 0031 §2a
            // is the ruling that a boundary is therefore never tolerated under it.
            .fs_usage => "no other process mutated the judged directory in the fs_usage capture; fs_usage excludes some processes by name, so a child that execs one of them would not appear (ADR 0031)",
        },
    };
}
/// Progress, so an UNKNOWN raised mid-exploration reports what had been explored rather
/// than zero. A caller aggregating coverage reads these.
var crash_points: u32 = 0;
var explored: u32 = 0;
var violations: u32 = 0;
/// The declared success status in effect (default 0), mirrored into every report so a
/// PASS over a non-zero convention is machine-auditable (ADR 0014).
var expected_status_val: u8 = 0;

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
/// only at the initial snapshot, UNKNOWN at the four sites at or past the recording run —
/// `state_file_too_large` for the cap (#330), `state_unsnapshotable` for the rest (#351).
/// The wording does not change with the verdict; whichever message applies, it applies on
/// both sides of the split, so this reads as one refusal with two exits rather than two
/// refusals. `OutOfMemory` is the one failure that stays SETUP_ERROR at every site, on the
/// rule `spawnFailure` states — see the guard below.
fn snapshotOrRefuse(gpa: std.mem.Allocator, root: []const u8, what: []const u8) engine.Snapshot {
    var diag: engine.SnapshotDiag = .{};
    return engine.takeSnapshotCapped(gpa, root, engine.SnapshotCaps.shipped, &diag) catch |e| {
        // An allocation failure is an environment problem in either phase, the rule
        // `spawnFailure` already states. Routing it to UNKNOWN would leave a seam one
        // statement wide: this snapshot exiting 2 for OOM while the `classify` that
        // consumes it exits 3 for the same cause. The ruling on #351 listed it among the
        // errors to move; this is the deviation, taken deliberately and approved.
        if (e == error.OutOfMemory) setupError(what);

        // **Decided once, for every exit below.** Threading the reason through as a
        // parameter was the first design, and review counted what could then go wrong:
        // of the four sites that refuse here, two — the no-measured-size branch and the
        // no-arena fallback — are reached by nothing, so either could have named the
        // wrong reason with every check in the tree still green. That is what #330
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
        const answer: struct { reason: contract.UnknownReason, bare: []const u8 } = switch (e) {
            error.FileTooLarge => .{
                .reason = .state_file_too_large,
                .bare = "a state file is too large for byte-level judgment",
            },
            error.TreeTooLarge => .{
                .reason = .state_tree_too_large,
                .bare = "the state tree is too large to snapshot",
            },
            error.ReadFailed,
            error.TooDeep,
            error.PathTooLong,
            error.ClassifyFailed,
            error.EntriesNotSortedUnique,
            => .{
                .reason = .state_unsnapshotable,
                .bare = "the state tree could not be snapshotted",
            },
            error.OutOfMemory => unreachable, // refused above
        };
        const reason = answer.reason;

        if (json_arena) |ja| snapshotRefusal(reason, snapshotDetail(ja, e, what, &diag));

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
        snapshotRefusal(reason, answer.bare);
    };
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
fn snapshotDetail(ja: std.mem.Allocator, e: engine.SnapshotError, what: []const u8, diag: *engine.SnapshotDiag) []const u8 {
    return switch (e) {
        error.FileTooLarge => if (diag.file.size) |sz|
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} ({d} bytes, cap {d}); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel()), sz, engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment"
        else
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} (over the {d}-byte cap); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel()), engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment",
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
        error.ReadFailed => std.fmt.allocPrint(ja, "{s}: a file or symlink inside the state tree could not be read", .{what}) catch what,
        error.ClassifyFailed => std.fmt.allocPrint(ja, "{s}: an entry inside the state tree could not be classified as a file, directory or symlink", .{what}) catch what,
        // Not the operator's tree. Say so, or they go looking through their own files for
        // a broken invariant of ours.
        error.EntriesNotSortedUnique => std.fmt.allocPrint(ja, "{s}: the snapshot's own entry list came out unsorted or holding duplicates — that is a defect in sideeye, not in the state tree", .{what}) catch what,
        // Refused above, before this function is called. If that guard goes, this stops
        // being unreachable and the compiler says so.
        error.OutOfMemory => unreachable,
    };
}

/// A snapshot refusal's one exit, split by how far the run has got (#330, widened by #351).
fn snapshotRefusal(reason: contract.UnknownReason, detail: []const u8) noreturn {
    switch (run_phase) {
        .before_exploration => setupError(detail),
        .exploring => unknown(reason, detail),
    }
}

/// Undo the two mkdirs setup resolution needs (state, then work), so a refusal
/// leaves the filesystem as it found it. Every vet between those mkdirs and the
/// first destructive step shares this one helper: a refusal branch that forgets
/// half of it would leave a 0755 directory at a path the run just refused to use.
fn undoSetupMkdirs(work_created: bool, work_z: [*:0]const u8, state_created: bool, state_z: [*:0]const u8) void {
    if (work_created) _ = posix.rmdir(work_z);
    if (state_created) _ = posix.rmdir(state_z);
}

fn usage() void {
    say(
        \\sideeye {s} (trace contract v{d})
        \\
        \\usage:
        \\  sideeye demo [--shim <lib>]
        \\  sideeye preflight --state <dir> --operation <cmd> [--shim <lib>] [--setup <cmd>] [--expect-status <n>] [--cwd <dir>] [--oracle <strace>] [--work <dir>] [--twice]
        \\  sideeye explore --state <dir> --operation <cmd> [--setup <cmd>] [--check <cmd>] [--marker <bytes>] [--expect-status <n>] [--cwd <dir>] [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
        \\  sideeye explore --config <sideeye.toml> [--shim <lib>] [--work <dir>] [--oracle <strace> | --oracle-fs-usage] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
        \\  sideeye replay <case.json> [--shim <lib>] [--fresh-state] [--state-under <dir>] [--oracle <strace> | --oracle-fs-usage] [--work <dir>] [--json <path>] [--allow-unverified] [--stop-when-orphaned] [--world-timeout <s>]
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
        \\  --setup      command that produces the initial state (run once)
        \\  --operation  command to explore; killed before each operation that can change state
        \\  --expect-status  the exit status that means the operation completed (0..255,
        \\               default 0). Governs the recording run and the un-killed baseline
        \\               world alike; killed worlds still require the kill signal itself
        \\  --shim       path to libsideeye_shim.so; when omitted it is looked for
        \\               beside this binary (its sibling, then ../lib — the tarball
        \\               and zig-out layouts), and absence is a loud error naming
        \\               both looked-at paths
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
    , .{ version, contract.contract_version });
}

/// Read a trace, or refuse. Pairs with `answerForOversizedTrace`, which every caller
/// must reach: forgetting the cap check at one site is the defect this exists to fix
/// (#324) — the world loop's read has no shim-marker branch to catch the collapse, so a
/// missed check there refused with `kill_did_not_land`, a claim about the engine's own
/// kill drawn from a trace it declined to read.
fn readTraceOrRefuse(gpa: std.mem.Allocator, path: []const u8, cap: usize, setup_msg: []const u8) engine.TraceInfo {
    return engine.readTraceCapped(gpa, path, cap) catch setupError(setup_msg);
}

/// The cap's refusal, separate from the read so a caller can classify first. The
/// recording site does exactly that: the comment above `engine.classify` promises every
/// UNKNOWN below it reports the classification that existed rather than the placeholder,
/// and L0 comes from the snapshots, which an oversized trace does not affect. Refusing
/// at the read would have made this the one structural UNKNOWN reporting "not
/// classified" — a regression a simplification pass introduced and review caught.
///
/// The cost of the split, stated because it is the defect this issue is about: nothing
/// forces a caller to reach this. A third read site could read and never answer, which
/// is exactly how the world loop came to refuse with `kill_did_not_land`. What holds it
/// instead is the acceptance leg, which drives BOTH sites through lowered-cap engines
/// and fails on the reason rather than the exit code; a site added without an answer
/// has no leg and is caught in review, not by the compiler.
fn answerForOversizedTrace(t: engine.TraceInfo, where: []const u8, cap: usize) void {
    if (t.too_large) traceTooLarge(t.too_large_size, where, cap);
}

/// The trace read broke its cap (#324). Both read sites refuse the same way, so the
/// wording lives once; `where` names which read it was. The size appears only when
/// `lseek` measured it — a size nobody measured must not appear in the message, the
/// rule the per-file cap's refusal already follows.
fn traceTooLarge(size: ?u64, where: []const u8, cap: usize) noreturn {
    if (json_arena) |ja| {
        if (size) |sz|
            unknown(.trace_too_large, std.fmt.allocPrint(ja, "the trace from {s} is larger than this engine will read: {d} bytes against a {d}-byte cap; the shim's account is complete, but the engine declined to hold it", .{ where, sz, cap }) catch "the trace is larger than this engine will read")
        else
            unknown(.trace_too_large, std.fmt.allocPrint(ja, "the trace from {s} is larger than this engine will read (over the {d}-byte cap); the shim's account is complete, but the engine declined to hold it", .{ where, cap }) catch "the trace is larger than this engine will read");
    }
    // Unreachable in practice for the same reason snapshotOrRefuse's fallback is:
    // json_arena is assigned before the parse loop, ahead of every call site. Kept so
    // this function does not depend on that ordering; nothing exercises it.
    unknown(.trace_too_large, "the trace is larger than this engine will read");
}

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
var fsu_live: ?LiveSidecar = null;

/// The observer's capture file, from spawn until it has been read. A `defer` on the
/// block that stopped the observer removed it — at that block's closing brace, forty
/// lines before the comparison opened it, so the comparison read nothing and the run
/// refused with "could not be read". Measured on an otherwise green end-to-end run.
/// The file is dropped at exactly two points instead: right after the comparison has
/// the bytes in memory, and inside the two refusal exits, which is where a capture
/// nobody will read again would otherwise be left at hundreds of megabytes.
var fsu_capture: ?[]const u8 = null;

fn dropCapture() void {
    const c = fsu_capture orelse return;
    fsu_capture = null;
    removeFile(c);
}

/// Stop the registered observer if one is running, and report what the pre-signal
/// observation said. `.had_exited` when nothing was registered, which is the answer
/// every non-fs_usage run gets and costs it nothing.
fn stopLiveSidecar() posix.SidecarEnd {
    const live = fsu_live orelse return .had_exited;
    fsu_live = null;
    return posix.stopSidecar(live.gpa, live.pid, &.{ "/usr/bin/sudo", "-n" }, 5000);
}

fn unknown(reason: contract.UnknownReason, detail: []const u8) noreturn {
    _ = stopLiveSidecar();
    dropCapture();
    if (json_path) |jp| if (json_arena) |ja|
        writeJsonReport(ja, jp, "UNKNOWN", @intFromEnum(contract.ExitCode.unknown), null, null, reason.name(), detail);
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
        \\expected    exit {d}
        \\not tested  {s}
        \\
        \\Sideeye could not judge this run. That is not a pass: the exit code is 2 so a
        \\caller has to decide deliberately what to do with it.
        \\
    , .{ reason.name(), detail, l0_note, l1_note, case_note, expected_status_val, notTestedText() });
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
/// `allow_unverified` exists because macOS has no oracle sideeye can use by default
/// (measured, #181, spike/macos-oracle/): DTrace's syscall provider matches no probes
/// under SIP even as root — `dtruss`, built on it, runs the target and exits 0 with no
/// syscall in its capture — `fs_usage` gave an ordered, attributed, full-path account
/// of the survey's toy but requires root, and Endpoint Security's shipped CLI
/// (`eslogger`) refuses without root plus a Full Disk Access grant.
/// Rather than branch on the platform — which would break the claim that both operating
/// systems produce the same verdict for the same scenario — the caller states the
/// weaker claim deliberately, and the report says which claim was made.
fn requireCompleteness(arena: std.mem.Allocator, has_oracle: bool, allow_unverified: bool) void {
    if (has_oracle or allow_unverified) return;
    const base = "no oracle was given, so the shim's account of what happened was not checked against anything; pass --oracle, or --allow-unverified to accept the weaker claim";
    // A discovered strace is only ever NAMED here, never attached: a second witness
    // joining on its own would silently strengthen what a flagless verdict claims —
    // and flip every caller that measured the no-oracle behavior (#78).
    const msg = if (findStraceForHint(arena)) |s|
        std.fmt.allocPrint(arena, "{s} (strace is on this machine: pass --oracle {s})", .{ base, s }) catch base
    else
        base;
    unknown(.completeness_not_verified, msg);
}

/// Linux-only PATH discovery used by refusal hints: the first absolute PATH entry
/// holding an executable `strace`, or null. Relative and empty PATH entries are
/// skipped — the hint must name a path that means the same thing wherever the
/// user pastes it (#78).
fn findStraceForHint(arena: std.mem.Allocator) ?[]const u8 {
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

/// A setup error is a verdict too, and it has to reach the JSON.
///
/// It did not, and the file was neither written nor removed: a caller running twice into
/// the same `--json` path read the *previous* run's document as this run's result. Since
/// several of these fire mid-run — after the trace is read, after a world is restored —
/// that stale verdict could be a PASS for a run that never explored anything.
fn setupError(detail: []const u8) noreturn {
    _ = stopLiveSidecar();
    dropCapture();
    if (json_path) |jp| if (json_arena) |ja|
        writeJsonReport(ja, jp, "SETUP_ERROR", @intFromEnum(contract.ExitCode.setup_error), null, null, null, detail);
    say("SETUP ERROR  {s}\n", .{detail});
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
/// `phase` decides the verdict, not just the wording. Exit 3 means the define did not run
/// (DESIGN's exit-code table: "configuration or environment problem **before exploration
/// began**"), so a wait that fails while worlds are being explored has to be UNKNOWN — the
/// distinction `recording_run_failed` and `baseline_run_failed` already draw for the same
/// phase. A first version of this fix sent every site to `setupError` and would have
/// published `verdict: "SETUP_ERROR"` for a mid-exploration failure: honest about the
/// failure, wrong about when it happened, and a silent change to the serialized shape.
///
/// How far the run has got. Three refusals share this one vocabulary rather than
/// growing a second, and all ask the same question — did any of the define run before
/// this failed? `spawnFailure` takes it as a parameter (the caller knows which step it
/// was starting); the per-file snapshot cap (#330) and the rewrite disposition (#363)
/// read `run_phase` below.
const SpawnPhase = enum {
    /// Before any world runs: `--setup`, the demo's compiler probe, the initial
    /// snapshot. A failure here really does mean the define never got started.
    before_exploration,
    /// The recording run onward. The define is running; refusing is UNKNOWN.
    exploring,
};

/// The phase the snapshot cap reads (#330). A *variable* rather than an argument
/// threaded through `snapshotOrRefuse`, and the difference is what can be verified:
/// `snapshotOrRefuse` has five call sites, one before the recording run and four at or
/// past it, and an acceptance leg can only reach one of the four. Passed as an argument,
/// the other three could name the wrong phase and every check in the tree would stay
/// green. Assigned once, immediately before the recording run, a per-site mistake is not
/// representable at all — what remains is where the single assignment sits, and the two
/// legs bound that from both sides: move it above the initial snapshot and check 2fc goes
/// red, delete it and check 2fd does. **They bound an interval, not a point** — measured,
/// by moving the assignment down to just above the final snapshot, where both legs stay
/// green because nothing between reads the variable. What is pinned is that the
/// assignment lies after the initial snapshot and at or before the final one.
///
/// A *sixth* call site added above this assignment would be misread, and no check would
/// say so — the same gap `answerForOversizedTrace` states for its own sites: caught in
/// review, not by the compiler.
var run_phase: SpawnPhase = .before_exploration;

fn spawnFailure(e: posix.SpawnError, phase: SpawnPhase, doing: []const u8) noreturn {
    if (e == error.WaitFailed) {
        const detail = "a child process ran, but its exit status could never be read: the wait was interrupted repeatedly, or failed permanently. Every verdict here rests on how that child ended, so the run refuses instead of deriving one from a status that was never written";
        switch (phase) {
            .before_exploration => setupError(detail),
            .exploring => unknown(.child_wait_failed, detail),
        }
    }
    // Fork and allocation failures are environment problems in either phase, and the
    // caller's wording already says which step was starting.
    setupError(doing);
}

/// How much fs_usage capture the engine will hold.
///
/// The capture is system-wide (`src/fsusage.zig` explains why it cannot be filtered),
/// so its size is set by whatever else the machine is doing, not by the target. Two
/// measurements, and the gap between them is the point: 27,994 lines in two seconds on
/// an idle machine, and **233 MB in a single acceptance run** on one doing ordinary
/// work — containers, a search indexer and a security agent all writing. `-t` bounds
/// the observer's time, not its output.
///
/// A run that exceeds this refuses rather than growing the arena until the engine dies.
/// That direction matters more than the number: an out-of-memory kill mid-exploration
/// leaves the target's state directory in a crash world with nobody to restore it, and
/// a refusal is recoverable where that is not.
const fsusage_capture_cap: usize = 2 * 1024 * 1024 * 1024;

/// How long `--config` may wait for a peer that has not written yet before refusing.
///
/// **This number is pinned between three constants in another file and nothing checks
/// the coupling**, so the inequality is written here rather than left to be rediscovered.
/// `spike/case-path-deadline.py` carries `WRITER_DELAY = 1.0` (how late its writer
/// opens), `min_s = 1.5` on the two deadline legs (the floor they assert this wait
/// against), and `DEADLINE = 5.0` (when it kills sideeye). **`min_s` is the binding
/// lower bound, not `WRITER_DELAY`** — measured: 1200 ms satisfies "above 1.0, below
/// 5.0" and still fails both legs at 1.21 s. So: `min_s < this << DEADLINE`. Move any of
/// the three and this has to move with them.
const config_read_deadline_ms: u64 = 2000;

/// Between attempts while a peer might still arrive. Small enough to pick up a config
/// that lands mid-wait, large enough not to spin — the measured late-writer case takes
/// around eighty reads to cover a second on both platforms.
const config_read_poll_ms: u64 = 10;

/// Bytes appended to a file since `from`, cut at the last newline so a half-written
/// line is read whole next time; `end` is where the next read starts.
///
/// The handshake first polled a fixed 4 MiB tail. On the CI runner the system-wide
/// capture grew fast enough that the sentinel's line left that window between two
/// polls 100 ms apart — the measured burst rate is 200 MB/s, at which 4 MiB is 20 ms —
/// and the fifth check of the run timed out waiting for a line that had already scrolled
/// past. Reading what was appended, and only that, cannot miss a line.
const Appended = struct { text: []const u8, end: u64 };

fn readFileFrom(arena: std.mem.Allocator, path: []const u8, from: u64, max: usize) ?Appended {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    const fd = posix.open(z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    // The `lseek` below already refuses a FIFO with ESPIPE, and that is not the reason
    // this is here: seekability and regular-file-ness are different properties, and the
    // day someone reaches the bytes another way the `lseek` stops being the guard
    // without anything saying so (#400).
    if ((posix.kindOfFd(fd) catch return null) != .file) return null;
    const size = posix.lseek(fd, 0, posix.SEEK_END);
    if (size < 0) return null;
    const usize_size: u64 = @intCast(size);
    if (usize_size <= from) return .{ .text = "", .end = from };
    if (posix.lseek(fd, @intCast(from), posix.SEEK_SET) < 0) return null;
    const want: usize = @intCast(@min(usize_size - from, @as(u64, max)));
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (list.items.len < want) {
        const room = @min(chunk.len, want - list.items.len);
        const got = posix.read(fd, &chunk, room);
        if (got < 0) return null; // a read error is not end of file
        if (got == 0) break;
        list.appendSlice(arena, chunk[0..@intCast(got)]) catch return null;
    }
    const text = list.items;
    const nl = std.mem.lastIndexOfScalar(u8, text, '\n') orelse return .{ .text = "", .end = from };
    return .{ .text = text[0 .. nl + 1], .end = from + nl + 1 };
}

/// Start `fs_usage` beside the run, or refuse with the reason.
///
/// Everything that can fail about the observer fails *here*, before the first child of
/// the measured run exists: the credential check, the launch, and the proof that the
/// capture is live. That placement is not a preference — **DESIGN's exit-code table**
/// gives exit 3 as "configuration or environment problem before exploration began", and
/// `docs/contract-freeze.md` closes the `unknown_reason` set until 2.0, so a new way to
/// fail that arrives after the recording has begun would have no honest code to leave
/// under. (An earlier revision of this paragraph attributed the exit-3 phrasing to the
/// freeze page too; surface 3 fixes which code a verdict carries and says nothing about
/// phase. Caught by a reader, #406 follow-up.)
fn startFsUsage(gpa: std.mem.Allocator, arena: std.mem.Allocator, capture_path: []const u8, sentinel: []const u8, limit_s: u32) c_int {
    // `sudo -n`: never prompt. A prompt here would block a run nobody is watching, and
    // the caller who *is* watching gets a message naming the one command to run first.
    const probe = posix.runChildCapture(gpa, &.{ "/usr/bin/sudo", "-n", "/usr/bin/true" }, &.{}, "/dev/null", null) catch
        setupError("could not run sudo to start fs_usage");
    switch (probe) {
        .exited => |c| if (c != 0) setupError("fs_usage needs root and sudo has no cached credentials; run `sudo -v` in this terminal first, then re-run. The credential cache is per-terminal, so a `sudo -v` elsewhere does not reach this process"),
        else => setupError("the sudo credential check did not exit normally"),
    }

    const limit = std.fmt.allocPrint(arena, "{d}", .{limit_s}) catch setupError("out of memory");
    // Unfiltered: `fs_usage`'s pid filter does not follow a fork, so filtering by the
    // subject leaves a raw-forked child invisible to this witness exactly where it is
    // already invisible to the shim (#405). Scope is the state root, decided in
    // `fsusage.read`. `-t` is insurance against a root observer outliving its parent
    // and holding kdebug, which SIGPIPE cannot deliver: a process that has stopped
    // writing never learns the reader is gone.
    // `-e` keeps fs_usage's own activity out of the capture. It does NOT lift the
    // default exclusion list, which the man page says covers Terminal, sshd and the
    // shells — measured, not assumed: with `-e` in force a `/bin/sh` child produced
    // zero lines under its own name, and seven lines naming the file it wrote, carried
    // by other processes' entries.
    //
    // That measurement is why scope is decided by path (`src/fsusage.zig`) rather than
    // by process identity. A design that filtered by pid or by name would lose an
    // excluded shell's mutations entirely; scoping by the state root still sees them,
    // and the account records them as a thread other than the subject — which is the
    // refusal it should be.
    const pid = posix.spawnSidecar(gpa, &.{ "/usr/bin/sudo", "-n", "/usr/bin/fs_usage", "-w", "-e", "-t", limit, "-f", "filesys" }, capture_path) catch
        setupError("could not start fs_usage");
    // Registered before anything below can refuse. From here on, every `setupError`
    // and `unknown` stops it; no call site has to.
    fsu_live = .{ .pid = pid, .gpa = gpa };
    fsu_capture = capture_path;

    // The proof that the capture is live. Not a sleep: a sleep asserts a duration and
    // this has to assert an observation. The engine creates a file inside the state
    // root and waits for that path to appear in the capture; until it does, nothing
    // the subject would do is guaranteed to be recorded.
    var zb: [contract.max_path]u8 = undefined;
    const sz = std.fmt.bufPrintZ(&zb, "{s}", .{sentinel}) catch setupError("path too long");
    // Created ONCE, before the loop. Inside it, the second iteration's O_EXCL open
    // necessarily fails on the file the first one made — which is how the first
    // version of this refused every run that needed more than one poll, under a
    // message about the *closing* sentinel that named neither the file nor the loop
    // it came from. The O_EXCL that guards against clobbering a state file and the
    // retry that waits for the observer are two different concerns; only the first
    // belongs on the open.
    const fd = posix.open(sz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o600));
    if (fd < 0) setupError("the fs_usage handshake could not create its sentinel inside the state directory; a file of that name is already there, or the directory is not writable");
    _ = posix.close(fd);

    var waited: u64 = 0;
    var seen: u64 = 0; // bytes of the capture already scanned
    while (waited < 10_000) {
        // An observer that has already exited will never show the sentinel; ten seconds
        // of polling a dead process is a wrong answer arriving late. `ktrace_start:
        // Resource busy` — another fs_usage still holding kdebug — is the usual cause.
        var st: c_int = 0;
        const w = posix.waitpid(pid, &st, posix.WNOHANG);
        if (w == pid or w < 0) {
            fsu_live = null;
            removeFile(sentinel);
            setupError("fs_usage exited before the handshake completed; if it printed `ktrace_start: Resource busy` above, another fs_usage still holds the kernel trace facility — wait for it, or stop it, and re-run");
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
        if (readFileFrom(poll_arena.allocator(), capture_path, seen, 64 * 1024 * 1024)) |a| {
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
    setupError("fs_usage started but its capture never showed the engine's own sentinel, so nothing proves the observer was recording; the run would have been judged against a capture of unknown coverage");
}

/// Spawn the operation under observation, the way the recording run does.
///
/// Extracted when `--twice` (#199) needed a second observation that cannot drift from
/// the first. Everything that decides what the run *sees* — the oracle wrapper and its
/// trace filter, the environment the child inherits, which failure wording a spawn
/// error gets — lives at one site now, so a second caller cannot quietly observe under
/// different conditions and have its snapshot compared as if it had not.
///
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
    // `oracle_path`, not `oracle`: the module imports `oracle.zig` under that name and
    // Zig refuses the shadowing rather than letting the parameter win silently.
    oracle_path: ?[]const u8,
    oracle_out: []const u8,
    trace_path: []const u8,
    stdout_path: []const u8,
    /// Where the define declared its commands run, `null` for the engine's own. Passed
    /// through to both spawns below, including the oracle's: the cwd goes on the strace
    /// invocation and the operation strace execs starts there too, because strace does
    /// not chdir between its own start and the exec.
    cwd: ?[]const u8,
) posix.Term {
    if (oracle_path) |strace_path| {
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
            .{ contract.env.trace_path, trace_path },
            // Pinned empty so an ambient value in the operator's shell cannot
            // become the first image's numbering base (R1; parseU32("") is 0).
            .{ contract.env.seq_base, "" },
            .{ preload_var, shim },
        };
        for (pairs) |kv| {
            list.append(arena, "-E") catch setupError("out of memory");
            const joined = std.fmt.allocPrint(arena, "{s}={s}", .{ kv[0], kv[1] }) catch setupError("out of memory");
            list.append(arena, joined) catch setupError("out of memory");
        }
        for (op_argv) |a| list.append(arena, a) catch setupError("out of memory");
        return posix.runChildCapture(gpa, list.items, &.{}, stdout_path, cwd) catch |e| spawnFailure(e, .exploring, "could not run --operation under the oracle");
    }
    return posix.runChildCapture(gpa, op_argv, &.{
        .{ "TOY_STATE", state_abs },
        .{ contract.env.state_dir, state_abs },
        .{ contract.env.state_dir_alt, state_alt },
        .{ contract.env.trace_path, trace_path },
        // Pinned empty: see the oracle-path pairs above.
        .{ contract.env.seq_base, "" },
        .{ preload_var, shim },
    }, stdout_path, cwd) catch |e| spawnFailure(e, .exploring, "could not run --operation");
}

/// Zig 0.16 passes the process's arguments and environment in; `std.process.argsAlloc`
/// no longer exists. The shape of `Init.Minimal` comes from `std.start.callMain`.
pub fn main(init: std.process.Init.Minimal) !void {
    // The baseline for `--stop-when-orphaned` (#269), read at the top of the process.
    //
    // Position matters more than it looks. Captured immediately before the world loop,
    // this would miss a launcher that died during `--setup` or the recording run — the
    // baseline would already be the reaper's pid, which never changes. Captured here, the
    // blind window shrinks to fork-to-exec: a launcher that dies before this line is not
    // seen, and the flag's own documentation says so.
    startup_ppid = posix.getppid();

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

    // `--help`, `-h` and `help` print the usage text and exit 0.
    //
    // The same text already reached stdout when the program was invoked wrongly, but that
    // path exits 3, so `sideeye --help` was a SETUP ERROR and `sideeye --help && …` took
    // the failure branch (#273). Asking to be told how to use the tool is not a failure.
    //
    // This adds no meaning to the exit codes: exit 0 is the success of whatever the command
    // does, not PASS specifically, and `version` below already exits 0 without producing a
    // verdict. docs/contract-freeze.md §3 says so explicitly.
    //
    // This branch is the top-level one. `<mode> --help` is answered by the branch below
    // it (#296) — deliberately as a separate exact-shape match rather than by wiring help
    // into the parse loop, which would let it run after `--json` has already called
    // removeFile. What is still not answered anywhere is help in a late position
    // (`explore --state X --help`); that needs the parser split into a side-effect-free
    // stage and a side-effecting one.
    if (argv.len >= 2 and (std.mem.eql(u8, argv[1], "--help") or
        std.mem.eql(u8, argv[1], "-h") or
        std.mem.eql(u8, argv[1], "help")))
    {
        // Refused rather than ignored, the way `version` and `mcp` refuse extras: silently
        // dropping them would answer a question the caller did not ask.
        if (argv.len != 2) {
            const msg = "sideeye help takes no arguments\n";
            _ = posix.write(2, msg.ptr, msg.len);
            std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
        }
        usage();
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // `version` prints the one line a release workflow needs to hold a tag against the
    // binary it is about to ship, and exits 0. The usage banner carries the same string
    // but exits 3 — an assert built on that would have to treat failure as success.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "version")) {
        if (argv.len != 2) {
            const msg = "sideeye version takes no arguments\n";
            _ = posix.write(2, msg.ptr, msg.len);
            std.process.exit(@intFromEnum(contract.ExitCode.setup_error));
        }
        say("sideeye {s} (trace contract v{d})\n", .{ version, contract.contract_version });
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // `<mode> --help` and `<mode> -h`, answered here rather than in the parse loop.
    //
    // #273 wired help in at the top level only, so once a mode word was consumed the
    // spelling fell through to whatever came next: `explore --help` and `preflight
    // --help` reached the loop's arity guard ("an option is missing its value" — the
    // loop treats every unrecognised flag as one that takes a value), `replay --help`
    // reached the dispatch's `else` and printed the banner with exit 3, and `demo
    // --help` hit runDemo's own refusal. Four modes, four different failures, none of
    // them help (#296). The ticket's transcript reports "unknown option" for explore;
    // that is the four-element form. Measured before this branch was written.
    //
    // WHY NOT IN THE PARSE LOOP. `--json` calls removeFile() while parsing, so a help
    // branch inside the loop would let `explore --state X --json report.json --help`
    // delete an existing report on its way to printing usage. The comment on that
    // removeFile records this project avoiding the same trap once already — a refusal
    // that had already deleted the caller's report is a refusal with a side effect.
    // Matching the exact three-argument shape here never enters the loop, so it cannot
    // reach any side effect at all.
    //
    // The shape is exact on purpose, and each part of it is load-bearing:
    //   - `explore --marker --help` stays a marker whose bytes are "--help". Four
    //     elements, no match, the loop consumes it as the value it is.
    //   - `explore --help extra` stays a refusal, the way the top level refuses extras.
    //   - Late-position help (`explore --state X --help`) is deliberately NOT answered.
    //     It needs the parser split into a side-effect-free stage and a side-effecting
    //     one, which is a larger change than this ticket.
    //
    // mcp, help and version are absent: they take no arguments, their synopsis lines
    // advertise none, and their existing refusals already name what they refused on.
    if (argv.len == 3 and
        (std.mem.eql(u8, argv[2], "--help") or std.mem.eql(u8, argv[2], "-h")) and
        (std.mem.eql(u8, argv[1], "demo") or
            std.mem.eql(u8, argv[1], "preflight") or
            std.mem.eql(u8, argv[1], "explore") or
            std.mem.eql(u8, argv[1], "replay")))
    {
        usage();
        std.process.exit(@intFromEnum(contract.ExitCode.pass));
    }

    // `demo` compiles the embedded planted-bug toy on this machine and self-execs
    // `explore` against it — it never returns. Exit codes are explore's own: the
    // expected outcome is 1 (FAIL, the planted bug found), which makes the demo double
    // as a smoke test of the installed binary + shim pair.
    if (argv.len >= 2 and std.mem.eql(u8, argv[1], "demo")) {
        runDemo(gpa, arena_state.allocator(), argv[2..]);
    }

    const Mode = enum { explore, replay, preflight };
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
        if (std.mem.eql(u8, argv[i], "--oracle-fs-usage")) {
            // Parsed on every platform; refused on Linux further down, after the state
            // path has been resolved. spike/acceptance.sh's CLI self-description check
            // requires every flag the parser knows to be accepted by some synopsis line
            // on the machine running the check, and it decides "accepted" by whether the
            // flag changes the base command's first line of output — so a parse-time
            // refusal on Linux read as a flag no mode accepts (CI, #406, twice).
            args.oracle_fs_usage = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--fresh-state")) {
            if (mode != .replay) setupError("--fresh-state applies to replay only (explore's state may be legitimately pre-populated)");
            args.fresh_state = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--stop-when-orphaned")) {
            // #269. A flag and not an environment variable, for reasons measured and
            // recorded in ADR 0010 (argv is per-invocation and is not inherited).
            if (mode == .preflight) setupError("preflight explores no worlds; --stop-when-orphaned belongs to explore and replay");
            stop_when_orphaned = true;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, argv[i], "--twice")) {
            // #199. The refusal runs the other way from the flags above: this one is
            // preflight's alone, because explore and replay already observe the
            // operation a second time — the un-killed baseline world is that run, and
            // `baseline_run_failed` is what they say when the re-run disagrees. What
            // preflight lacks is any second observation at all.
            if (mode != .preflight) setupError("--twice belongs to preflight; explore and replay already re-run the operation in the un-killed baseline world, and a divergent re-run refuses there as baseline_run_failed");
            args.twice = true;
            i += 1;
            continue;
        }
        if (i + 1 >= argv.len) setupError("an option is missing its value");
        const v = argv[i + 1];
        if (std.mem.eql(u8, argv[i], "--state")) args.state = v
        else if (std.mem.eql(u8, argv[i], "--setup")) args.setup = .{ .str = v }
        else if (std.mem.eql(u8, argv[i], "--operation")) args.operation = .{ .str = v }
        else if (std.mem.eql(u8, argv[i], "--shim")) args.shim = v
        else if (std.mem.eql(u8, argv[i], "--work")) args.work = v
        else if (std.mem.eql(u8, argv[i], "--oracle")) args.oracle = v
        else if (std.mem.eql(u8, argv[i], "--check")) args.check = .{ .str = v }
        else if (std.mem.eql(u8, argv[i], "--marker")) args.marker = v
        // Taken as spelled, unlike the toml's, which resolves against the file's own
        // directory: a flag is typed at a cwd, so a relative one already means what the
        // caller meant. It is absolutized with the rest of them further down.
        else if (std.mem.eql(u8, argv[i], "--cwd")) args.cwd = v
        else if (std.mem.eql(u8, argv[i], "--expect-status")) {
            args.expect_status = parseExpectStatus(v, "--expect-status must be an integer in 0..255");
            // Mirrored immediately: a refusal between here and the canonical binding
            // below must not report the declaration as 0 (R1 finding).
            expected_status_val = args.expect_status.?;
        }
        else if (std.mem.eql(u8, argv[i], "--world-timeout")) {
            // #263. Worlds only — the recording run, setup and checkers have no
            // budget, and the help text says so: the flag must not read as a promise
            // of a hang-free run.
            if (mode == .preflight) setupError("preflight explores no worlds; --world-timeout belongs to explore and replay");
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
        }
        else if (std.mem.eql(u8, argv[i], "--state-under")) {
            // #266. Replay only: an explore's config is the trust boundary and its
            // state is part of what the operator vets (#96); accepting the flag there
            // would be a second confinement feature nobody asked for, and preflight
            // destroys nothing.
            if (mode != .replay) setupError("--state-under applies to replay only: a config's state is part of what the operator vets, and preflight never destroys");
            // A confinement flag must not be last-wins: two spellings in one argv is
            // a caller bug, and silently taking the second would let a widened range
            // ride behind a narrow-looking one.
            if (args.state_under != null) setupError("--state-under was given twice; refusing rather than letting the second spelling win");
            args.state_under = v;
        }
        else if (std.mem.eql(u8, argv[i], "--config")) args.config = v
        else if (std.mem.eql(u8, argv[i], "--json")) {
            // Rejected before the removeFile below: a rejection that had already deleted
            // the caller's previous report would be a refusal with a side effect.
            if (mode == .preflight) setupError("preflight has no machine-readable form; sideeye explore --config answers strictly more, and --json lives there");
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

    // preflight answers one question — "does the recording phase accept this target?" —
    // before a define exists. The define-shaped flags are refused by name rather than
    // ignored: an accepted-but-inert flag would be a declared intention that silently
    // never fires, the exact shape the config parser refuses too (ADR 0007).
    // Two observers cannot both be the completeness oracle: they produce different
    // accounts of the same run, and a caller who named both has not said which one the
    // verdict rests on. Refused by name rather than resolved by precedence — the
    // accepted-but-inert shape this parser refuses everywhere else (ADR 0007).
    if (args.oracle != null and args.oracle_fs_usage)
        setupError("--oracle and --oracle-fs-usage both name a completeness oracle; pass one");
    args.has_oracle = args.oracle != null or args.oracle_fs_usage;
    // Named, not yet read. The account distinguishes the two: an oracle whose capture
    // never parsed establishes nothing about other processes, and a run refused before
    // the comparison must not report as though it had one.
    if (args.oracle_fs_usage)
        boundary_ev.witness = .{ .unread = .fs_usage }
    else if (args.oracle != null)
        boundary_ev.witness = .{ .unread = .strace };

    if (mode == .preflight) {
        if (args.oracle_fs_usage) setupError("--oracle-fs-usage belongs to explore and replay; preflight asks whether the recording phase accepts this target, and answers that without a second witness");
        if (args.check != null) setupError("preflight runs before an invariant exists; --check belongs to explore, which also falsifies it before trusting it");
        if (args.marker != null) setupError("--marker belongs to explore; preflight makes no claim a marker could strengthen");
        if (args.config != null) setupError("preflight takes the define-surface flags directly; once a sideeye.toml exists, `sideeye explore --config` answers strictly more");
        if (args.allow_unverified) setupError("preflight never claims PASS, so there is nothing --allow-unverified could weaken");
    }

    // A replay's define comes from the case file itself: the counterexample's
    // identity includes what was run, not just where it was killed (ADR 0009).
    var replay_case: ?ReplayCase = null;
    var only_k: ?u32 = null;
    if (mode == .replay) {
        if (args.state != null or args.setup != null or args.operation != null or
            args.check != null or args.marker != null or args.expect_status != null or
            args.cwd != null or args.config != null)
            setupError("replay takes its define from the case file; the define-surface flags and --config do not apply");
        const rarena = arena_state.allocator();
        const ctext = readFileAllocCapped(rarena, case_arg.?, 1024 * 1024, .{ .require_regular = true }) orelse setupError(
            std.fmt.allocPrint(rarena, "the case file could not be read (missing, not a regular file, unreadable, or over 1 MiB): {s}", .{case_arg.?}) catch "the case file could not be read",
        );
        const parsed = std.json.parseFromSlice(ReplayCase, rarena, ctext, .{}) catch
            setupError("the case file could not be parsed as a sideeye case");
        const c = parsed.value;
        if (!std.mem.eql(u8, c.schema, "sideeye/case"))
            setupError("the file does not declare itself a sideeye case");
        if (c.case_version != 1 and c.case_version != 2 and c.case_version != 3 and c.case_version != 4)
            setupError("this binary understands case schema versions 1, 2, 3 and 4 only");
        // The same travel-together law, extended to the command shape (ADR 0019): the
        // argv form arrived with version 3, so an older file carrying it is not an
        // older file — it is malformed, and reading it under a guessed contract would
        // replay a define no version-2-era binary ever produced.
        const carries_argv = (c.define.operation == .argv) or
            (c.define.setup != null and c.define.setup.? == .argv) or
            (c.define.check != null and c.define.check.? == .argv);
        if (c.case_version < 3 and carries_argv)
            setupError("a case_version 1 or 2 file cannot carry an argv-form command; the array form arrived with version 3");
        // The version and the declaration travel together (ADR 0014): a v1 file
        // carrying a declaration is not a v1 file, and a v2 file without one has
        // lost the very fact the version exists to freeze. Both are refused as
        // malformed rather than read under a guessed contract (R1 finding). One
        // deliberate softness: a JSON `null` is indistinguishable from an absent
        // field after parsing, so a v1 file spelling `"expected_status": null`
        // passes — null is not a declaration, and the meaning ("0 was the
        // contract") is the same either way. A v2 `null` refuses like an absence.
        if (c.case_version == 1 and c.define.expected_status != null)
            setupError("a case_version 1 file cannot carry an expected_status declaration; it arrived with version 2");
        if (c.case_version >= 2 and c.define.expected_status == null)
            setupError("a case_version 2, 3 or 4 file must carry define.expected_status; the case freezes the declaration");
        // The same law again, for the directory the define declared it runs in. A cwd is
        // part of what the counterexample was found against — replaying the same commands
        // somewhere else is replaying a different define — so the version moves with it.
        // Both directions, for the reason the two above give: a v3 file carrying a cwd is
        // malformed rather than old, and a v4 file without one has lost the fact the
        // version exists to freeze.
        if (c.case_version < 4 and c.define.cwd != null)
            setupError("a case_version 1, 2 or 3 file cannot carry a cwd declaration; it arrived with version 4");
        if (c.case_version == 4 and c.define.cwd == null)
            setupError("a case_version 4 file must carry define.cwd; the version exists to freeze it");
        args.state = c.define.state;
        args.setup = c.define.setup;
        args.operation = c.define.operation;
        args.check = c.define.check;
        args.marker = c.define.marker;
        args.expect_status = c.define.expected_status;
        // Taken as stored: a saved case always carries the resolved spelling, so there is
        // nothing here for a toml directory to resolve against. The vet below still runs
        // — the directory may be gone by replay time, which is a refusal, not a verdict.
        args.cwd = c.define.cwd;
        // Mirrored into the report before any refusal below can fire: a contract
        // mismatch on a status-3 case must not report expected_status 0 (R1 finding).
        expected_status_val = c.define.expected_status orelse 0;
        replay_case = c;
        only_k = c.k;
        // From here on, every verdict — including a refusal — names the case it is
        // about, in text and JSON alike. Set before the contract gate so the one
        // refusal this block raises names it too.
        case_note = case_arg.?;
        if (c.contract_version != contract.contract_version)
            unknown(.case_no_longer_applies, "the case was recorded under a different trace contract; the crash-point numbering does not carry over");
        // --fresh-state (#69) is honoured further down, on state_abs — the guard in
        // front of the deletion is lexical, and only the realpath'd spelling makes
        // it mean anything. Nothing destructive happens in this block.
    }

    // The define surface comes from exactly one place (ADR 0007): a config file or
    // the flags, never a merge — a precedence table would make the file unreadable
    // on its own, and which line was in effect would be invisible.
    if (args.config) |cfg_path| {
        if (args.state != null or args.setup != null or args.operation != null or args.check != null or args.marker != null or args.expect_status != null or args.cwd != null)
            setupError("--config and the define-surface flags (--state, --setup, --operation, --check, --marker, --expect-status, --cwd) are mutually exclusive: the define lives in one place or the other");
        const arena = arena_state.allocator();
        // Bounded, and the only reader that is. The path is operator-named and may
        // legitimately be a pipe — `--config /dev/stdin`, a process substitution — so it
        // cannot be refused by kind the way a case path is (#400), and it cannot be
        // waited on forever either. A ceiling comes with it: the largest config in this
        // repository is 4.5 KiB, and an unbounded read was one of the three ways this
        // call used not to return (`/dev/zero`; the other two were the open waiting for
        // a peer, and a read waiting for one that had opened but sent nothing).
        const text = readFileAllocCapped(arena, cfg_path, 1024 * 1024, .{ .bounded = true }) orelse setupError(
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
                args.setup = if (d.setup) |s| resolveCommand(arena, dir, s) else null;
                args.operation = resolveCommand(arena, dir, d.operation);
                args.check = if (d.check) |c| resolveCommand(arena, dir, c) else null;
                args.marker = d.marker;
                args.cwd = if (d.cwd) |c| resolvePathAgainst(arena, dir, c) else null;
                if (d.expected_status) |es| {
                    args.expect_status = parseExpectStatus(es, "expected_status must be an integer in 0..255 (one double-quoted string, as every value here)");
                    // Same mirror as the flag: refusals between here and the
                    // canonical binding must report the declaration that was read.
                    expected_status_val = args.expect_status.?;
                }
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
    // One declared value, resolved once, governs every un-killed run of the operation:
    // the recording run and the baseline world are the same command over the same
    // state, so they answer to the same success status (ADR 0014). Killed worlds are
    // untouched — a SIGKILL death is a signal, not an exit status, and the two never
    // substitute for each other.
    const expect_status: u8 = args.expect_status orelse 0;
    expected_status_val = expect_status;
    if (args.marker) |m| {
        if (m.len == 0) setupError("the marker is empty");
        if (m.len >= 4096) setupError("the marker is unreasonably long (>= 4 KiB)");
        l1_configured = true;
        l1_note = "marker configured; the recording run has not been scanned yet";
    }

    // The declared cwd is resolved and vetted here, ahead of the state directory's mkdir
    // below: a define naming a directory that is not there must refuse before anything on
    // disk has moved, and exit 3 is true of it — nothing of the define has run.
    //
    // Resolved rather than passed through. The oracle is handed this same string to
    // resolve the subject's relative paths against (see the recording run), and a
    // resolved path is also what a saved case stores as the run's identity — an
    // unresolved one would name a different directory from every other cwd, which is
    // exactly what ADR 0007 exists to remove.
    if (args.cwd) |declared| {
        var cwd_z_buf: [contract.max_path]u8 = undefined;
        const cwd_z = std.fmt.bufPrintZ(&cwd_z_buf, "{s}", .{declared}) catch setupError("the declared cwd is too long");
        var cwd_real: [contract.max_path]u8 = undefined;
        // Both refusals print a string that arrived from a config or a case file, and
        // both are declared trust boundaries — so both go through `textShown`, the way
        // the `--state-under` refusal below already does for `define.state`. Same class,
        // same batch that found it (#266): a refusal firing *on* a hostile declaration is
        // exactly where a forged control sequence would reach the console.
        const cwd_abs = posix.realpath(cwd_z.ptr, &cwd_real) orelse setupError(
            std.fmt.allocPrint(arena_state.allocator(), "the declared cwd could not be resolved: {s}", .{textShown(arena_state.allocator(), declared)}) catch "the declared cwd could not be resolved",
        );
        const cwd_span = std.mem.span(cwd_abs);
        // A regular file resolves fine and then fails at `chdir` in the child, which
        // reads as the operation exiting 125 — a diagnosis about the target for what is
        // a fault in the declaration. Refused by name here instead.
        if (!posix.isDirPath(cwd_abs)) setupError(
            std.fmt.allocPrint(arena_state.allocator(), "the declared cwd is not a directory: {s}", .{textShown(arena_state.allocator(), cwd_span)}) catch "the declared cwd is not a directory",
        );
        args.cwd = arena_state.allocator().dupe(u8, cwd_span) catch setupError("out of memory");

        // The engine's own paths are pinned here, and only here, because only a declared
        // cwd can move them. `--work`, `--shim` and `--oracle` name things the ENGINE
        // chose, but three of their uses are opened by the child *after* it has chdir'd:
        // the shim opens `SIDEEYE_TRACE_PATH` from the environment, strace opens its `-o`
        // capture, and the loader resolves the shim library. Spelled relatively, each
        // would land in the declared directory instead — measured before this pin as a
        // run whose traces were never written, reported as `no_shim_marker` and blamed on
        // the target's linking and on macOS SIP, and as an oracle that vanished after the
        // parent's own `access(X_OK)` guard had confirmed it (that guard's comment says
        // it exists to stop exactly the report it then produced).
        //
        // Joined against the engine's directory by `resolvePathAgainst` — the same helper
        // the toml route uses on `state`, rather than a second spelling of it (#65 is
        // about the copies this repo has already paid for). Lexical on purpose: `--work`
        // legitimately does not exist yet here, and the pin is about which directory the
        // name is read against, not about following symlinks. Nothing happens when no cwd
        // is declared, so a run without the key keeps the report text it has always
        // printed — these paths appear in the `case` and `reproduce` lines exactly as the
        // caller spelled them.
        var pin_cwd_buf: [contract.max_path]u8 = undefined;
        const pin_base = if (posix.getcwd(&pin_cwd_buf, pin_cwd_buf.len)) |p| std.mem.span(p) else "/";
        const pin_arena = arena_state.allocator();
        args.work = resolvePathAgainst(pin_arena, pin_base, args.work);
        if (args.shim) |s| args.shim = resolvePathAgainst(pin_arena, pin_base, s);
        if (args.oracle) |o| args.oracle = resolvePathAgainst(pin_arena, pin_base, o);
    }

    // Bound after the pin above, not before it: `findShim`'s own answer is already
    // absolute, but an explicit `--shim ./lib.dylib` is the caller's spelling, and the
    // loader resolves it in the child — after the chdir. Read too early, this const would
    // hold the unpinned string and the run would die in dyld naming the declared
    // directory, which is how the review found it.
    const shim = args.shim orelse findShim(arena_state.allocator());

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
    const state_created = posix.mkdir(state_z.ptr, 0o755) == 0;
    const state_abs = blk: {
        if (posix.realpath(state_z.ptr, &real_buf)) |p| break :blk std.mem.span(p);
        // Reachable from a replayed case (ELOOP, a component raced away), not only
        // from a broken environment — so the mkdir above is undone like every other
        // refusal between it and the first destructive step (security review,
        // Minor-3: this and the two --work refusals below predate the rule's helper
        // and were the last three keeping their side effect).
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError("--state could not be resolved to an absolute path; the shim and the engine would filter on different spellings of it");
    };

    // Still before setup runs, so the refusal is a configuration error and nothing has
    // been touched. See the flag's parse site for why this is not raised there.
    if (args.oracle_fs_usage and builtin.os.tag != .macos)
        setupError("--oracle-fs-usage is macOS only; on Linux the completeness oracle is --oracle <strace>, which needs no privilege");

    // With no descriptor number exempt from observation (contract v8), the engine's
    // own artifacts under --work — every operation's stdout capture rides the target's
    // fd 1, and the shim's trace rides a descriptor it opens from the environment —
    // would be observed as the target's state operations if the work directory sat
    // inside the state directory. That would poison the snapshots, the operation
    // count, and every saved case address, so it is refused before anything runs.
    // The other nesting (state inside work) is fine: captures land at the work root,
    // outside the state subtree.
    //
    // This vet sits *before* --fresh-state's deletion below, and cleans up the one
    // side effect its own resolution needs (mkdir before realpath): a refusal must
    // leave the state directory exactly as it found it, and the first version of the
    // check emptied the state dir — or planted <state>/work — before refusing
    // (review finding). `isInsideDir` holds --work equal to the state directory, and
    // any --work under a root state directory, inside; the hand-rolled prefix test it
    // replaced answered "outside" for state `/`.
    var work_buf: [contract.max_path]u8 = undefined;
    const work_z = std.fmt.bufPrintZ(&work_buf, "{s}", .{args.work}) catch {
        if (state_created) _ = posix.rmdir(state_z.ptr);
        setupError("--work is too long");
    };
    const work_created = posix.mkdir(work_z.ptr, 0o755) == 0;
    {
        var work_real_buf: [contract.max_path]u8 = undefined;
        const work_abs = blk: {
            if (posix.realpath(work_z.ptr, &work_real_buf)) |p| break :blk std.mem.span(p);
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError("--work could not be resolved to an absolute path");
        };
        if (contract.isInsideDir(work_abs, state_abs)) {
            // Remove only what this invocation just created: refusing while leaving
            // a fresh <state>/work behind would itself be the contamination the
            // check exists to prevent. (The state root too — `--state /opt/x --work
            // /opt/x/work` creates both, one directory up.)
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError("--work must not be the state directory or inside it: the engine's own captures and traces there would be observed as the target's state operations");
        }
    }

    // The MCP adapter's state confinement, enforced where the value is read (#266).
    //
    // The server vets the CASE's path against SIDEEYE_MCP_ROOT, but the case file
    // itself names the state directory the engine empties (`--fresh-state`) and
    // deletes-and-rebuilds once per world (`restore`). Nothing about the case path
    // says where that define points, so the server hands its destruction range down
    // as a flag and the check runs here — on the same bytes the destruction will use,
    // with no second parse and no check-to-use window.
    //
    // Strict inside, not equal: a case naming the range itself would make the
    // operator's whole workspace the sacrificial directory. Both sides are compared
    // realpath'd — state_abs already is, and the flag resolves here — or the /tmp
    // and /private/tmp spellings of the same directory would split on macOS.
    if (args.state_under) |su| {
        var su_z_buf: [contract.max_path]u8 = undefined;
        const su_z = std.fmt.bufPrintZ(&su_z_buf, "{s}", .{su}) catch {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError("--state-under is too long");
        };
        var su_real_buf: [contract.max_path]u8 = undefined;
        const su_abs = blk: {
            if (posix.realpath(su_z.ptr, &su_real_buf)) |p| break :blk std.mem.span(p);
            // Fail-closed: an unresolvable range must refuse the run, not skip the
            // confinement it was asked to apply. "Resolved" is all this checks — a
            // regular file resolves and passes here; everything under it then fails
            // strict-inside, so the outcome is refusal either way.
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError("--state-under could not be resolved; refusing rather than running unconfined");
        };
        // "/" satisfies isInsideDir for every absolute path — a range that confines
        // nothing is a misconfiguration, not a wide range.
        if (su_abs.len <= 1) {
            undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
            setupError("--state-under / would confine nothing; name the directory the case's state may live under");
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
            setupError(std.fmt.allocPrint(arena, "the case's state directory resolves outside the allowed range, or is the range itself: state {s}, --state-under {s}. Replay directly from the CLI, or set SIDEEYE_MCP_STATE_ROOT to the directory this case's state may live under", .{ textShown(arena, state_abs), textShown(arena, su_abs) }) catch "the case's state directory resolves outside the allowed range (--state-under)");
        }
    }

    // The destructive-root vet, here rather than only inside restore/freshDir.
    //
    // `engine.restore` calls `assertSafeRoot` too, but the first world is far downstream:
    // `--setup` has already run by then, and a define whose operation records nothing
    // never reaches a world at all. Refusing a system path only after running the
    // target's setup command against it is not a refusal, so the same predicate runs
    // here, on the resolved spelling, before anything else touches the state.
    //
    // It sits *after* the --work containment vet on purpose. Both are ahead of every
    // destructive step, so the order does not change what is protected — but `--state /`
    // is refused by both, and the containment vet's acceptance leg uses exactly that
    // input to hold `isInsideDir`'s empty-prefix branch (the hand-rolled test it replaced
    // answered "outside" for `/`). Vetting the root first would take that input away and
    // leave the containment logic with no CLI-level case.
    //
    // Both mkdirs are undone on refusal, for the reason the vet above states for itself:
    // a refusal must leave the filesystem as it found it, and this one would otherwise
    // create the very directory it is refusing to use.
    engine.assertSafeRoot(state_abs) catch {
        undoSetupMkdirs(work_created, work_z.ptr, state_created, state_z.ptr);
        setupError("--state names a location nothing sacrificial belongs in: exploration empties and rebuilds this directory once per world, hundreds of times. Point it at a scratch directory the run owns");
    };

    // --fresh-state (#69): empty the case's state dir before setup runs. The dir is
    // sacrificial by contract — exploration kills processes mid-write into it — and
    // the deletion rides the engine's guarded path (assertSafeRoot + the same
    // deleteTree the restore path uses). It runs on state_abs, never the case's raw
    // spelling: the guard is lexical, and "/tmp/../etc" spells safe while resolving
    // unsafe — the realpath above is the guard's other half. Sitting here also keeps
    // every earlier setup validation — the --work containment vet included — ahead of
    // the one destructive step, and the mkdir-then-resolve above already covers a
    // state dir that does not exist yet.
    if (args.fresh_state)
        engine.freshDir(state_abs) catch |e| restoreFailure(e, "--fresh-state could not empty the case's state directory");

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

    // ---- setup -------------------------------------------------------------------
    if (args.setup) |cmd| {
        const setup_argv = commandArgv(arena_state.allocator(), cmd) catch setupError("--setup is empty");
        if (setup_argv.len == 0) setupError("--setup is empty");
        const term = posix.runChild(gpa, setup_argv, &.{
            .{ "TOY_STATE", state_abs },
        }, args.cwd) catch |e| spawnFailure(e, .before_exploration, "could not run --setup");
        switch (term) {
            .exited => |code| if (code != 0) setupError("--setup exited non-zero"),
            else => setupError("--setup did not exit normally"),
        }
    }

    var initial = snapshotOrRefuse(gpa, state_abs, "could not snapshot the initial state");
    // #5, checked before anything runs: an unreproducible entry the setup left (or
    // that predates the run) fails fast — no recording, no worlds. Nothing competes
    // with this refusal here.
    refuseUnsupportedEntry(arena_state.allocator(), initial, "present before the recording run");
    defer initial.deinit();

    // ---- recording run -----------------------------------------------------------
    // The last snapshot that can honestly say "the define did not run" is above this
    // line; every one below it is at or past the recording run (#330).
    //
    // The define itself does not begin here — what follows, up to the recording run
    // below, is still engine setup (path buffers, argv splitting, the oracle's
    // executability check). Every refusal in that stretch exits 3, correctly: a
    // missing `--operation` really is a configuration problem. They can, because they
    // reach `setupError` directly and never consult this variable. The line is placed
    // by what reads it: the snapshot cap (#330) and the rewrite disposition (#363).
    run_phase = .exploring;

    var rec_trace_buf: [contract.max_path]u8 = undefined;
    const rec_trace = std.fmt.bufPrint(&rec_trace_buf, "{s}/trace-record.bin", .{args.work}) catch setupError("path too long");
    removeFile(rec_trace);

    const op_argv = commandArgv(arena_state.allocator(), operation) catch setupError("--operation is empty");
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

    // Read before the spawn, not after: `--twice` reports the interval between the two
    // runs' STARTS (the cohort protocol's definition, PROTOCOL.md "two or more seconds
    // apart"), and a mark taken after this run returned would measure the gap between
    // its end and the next one's beginning instead.
    // Before the mark, not between it and the spawn. After the run returns, the name in
    // `op_argv[0]` may resolve to a different file than the one the kernel executed, so
    // the reading has to happen on this side of the spawn — but it walks a file the
    // target named and its cost is not bounded by anything this engine controls, and
    // `--twice` promises the two runs *start* at least two seconds apart (README,
    // `--help`, CHANGELOG). Sitting between the mark and the spawn, a slow reading is
    // spent out of that gap, and two starts closer than two seconds would satisfy a wait
    // computed from a mark taken before it. Taken once per run rather than per world:
    // this is a cold-path detail, not an observer, and must not join the exploration's
    // loop.
    rec_image = image.observe(arena, op_argv[0], args.cwd);

    // The macOS observer runs beside the recording rather than wrapping it, so it is
    // started here and stopped after — and both sentinels live inside the state root,
    // where `fsusage.read` can scope them, and are removed before the snapshot that
    // judges anything sees them.
    var fsu_pid: ?c_int = null;
    var fsu_sentinel_a_buf: [contract.max_path]u8 = undefined;
    var fsu_sentinel_b_buf: [contract.max_path]u8 = undefined;
    // The engine's own pid is in the name, and both are created O_EXCL. A fixed name
    // would truncate a state file that happened to carry it — and a failed handshake
    // exits before the initial snapshot is restored, so the loss would be permanent.
    // O_EXCL makes the overwrite unmakeable rather than detected, and the pid keeps two
    // concurrent explores over one state directory from colliding with each other.
    // Built inside the flag's own branch. Constructed unconditionally, the suffix would
    // push a state root near `contract.max_path` over the limit on runs that never
    // asked for this observer — a behaviour change in the path this work promises to
    // leave byte-identical.
    var fsu_sentinel_a: []const u8 = "";
    var fsu_sentinel_b: []const u8 = "";
    if (args.oracle_fs_usage) {
        fsu_sentinel_a = std.fmt.bufPrint(&fsu_sentinel_a_buf, "{s}/.sideeye-fsusage-open.{d}", .{ state_abs, posix.getpid() }) catch setupError("path too long");
        fsu_sentinel_b = std.fmt.bufPrint(&fsu_sentinel_b_buf, "{s}/.sideeye-fsusage-close.{d}", .{ state_abs, posix.getpid() }) catch setupError("path too long");
        // The display cap cuts a pathname from the LEFT (measured: 144, 153 and 156 on
        // two machines), so a state root long enough to be cut takes its own prefix off
        // every line and nothing in the capture can be scoped to it. Checked before the
        // observer starts, so the refusal is a setup error rather than a silent hole.
        if (state_abs.len > 96)
            setupError("--oracle-fs-usage cannot scope a state directory this deep: fs_usage cuts long pathnames from the left, so the state root's own prefix would be missing from the capture and no line could be attributed to it. Use a shorter --state path");
        // 90 seconds, not the ten minutes this first carried. The observer covers the
        // recording run alone — `--oracle` has never watched the crash worlds — and a
        // recording is seconds. `-t` is the insurance against a stop that does not
        // land, so its right size is the smallest one that cannot cut a real recording
        // short, and an oversized bound is not free: a run whose stop failed wrote
        // **2.9 GB** of system-wide capture before its ten minutes were up, measured.
        fsu_pid = startFsUsage(gpa, arena, oracle_out, fsu_sentinel_a, 90);
    }

    const rec_started_ms = posix.monotonicMs();
    const rec_term = runOperationObserved(gpa, arena, op_argv, state_abs, state_alt, shim, args.oracle, oracle_out, rec_trace, rec_stdout, args.cwd);

    if (fsu_pid) |pid| {
        // The closing sentinel proves the capture was still live when the recording
        // ended. A start sentinel alone establishes only that it began, and
        // `oracle_verified` now rests on the whole window.
        var zb: [contract.max_path]u8 = undefined;
        const sz = std.fmt.bufPrintZ(&zb, "{s}", .{fsu_sentinel_b}) catch setupError("path too long");
        const fd = posix.open(sz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o600));
        // `unknown` stops the observer on its way out; this site does not have to.
        if (fd < 0) unknown(.oracle_saw_nothing, "the closing sentinel could not be created inside the state directory, so nothing can establish that the capture covered the end of the recording");
        _ = posix.close(fd);
        // Stopped, not left to `-t`: the answer to "was it still running?" is what
        // separates a capture of the whole window from one that closed early, and it
        // can only be asked before the signal.
        _ = pid;
        const end = stopLiveSidecar();
        // Removed before the final snapshot, which is what judges the state: a file the
        // engine created for its own bookkeeping must not appear as an unexplained
        // entry in the tree the verdict is about. Unconditional, so the refusals below
        // do not leave it behind either.
        removeFile(fsu_sentinel_b);
        switch (end) {
            .was_running => {},
            .had_exited => unknown(.oracle_saw_nothing, "fs_usage was no longer running when the recording finished, so its capture describes a window that closed before the run did"),
            .would_not_die => unknown(.oracle_saw_nothing, "fs_usage did not stop when asked, so nothing bounds what its capture covers"),
        }
    }
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
        .exited => |code| if (code != expect_status)
            unknown(.recording_run_failed, std.fmt.allocPrint(arena, "the operation exited {d} during the recording run where {d} was expected, so the crash points derived from it describe an execution that did not happen (a different success convention is declared with --expect-status or the toml's expected_status)", .{ code, expect_status }) catch "the operation exited with an unexpected status during the recording run"),
        else => unknown(.recording_run_failed, "the operation did not exit normally during the recording run"),
    }

    // A marker the clean run cannot produce would make every post-success obligation
    // vacuous while the report still said PASS (ADR 0008). Checked against the
    // recording run — the run that completes normally, where even an unflushed stdio
    // buffer reaches the capture through the exit-time flush. A crash world killed
    // before the marker is not this: there the conditional simply does not apply.
    // One observation serves two readers (#46): the marker scan and the capture
    // fingerprint come from the same bytes, and this is the first of the two samples
    // the tolerated-boundary path compares after containment.
    const rec_capture = observeCapture(rec_stdout, args.marker) catch
        setupError("the recording run's stdout capture could not be read back");
    if (args.marker != null) {
        if (!rec_capture.marker_seen) {
            l1_note = "marker configured; never observed, even in the recording run";
            unknown(.marker_never_observed, "the success marker never appeared in the recording run's own stdout; check the marker string, and whether the target writes it to stdout at all");
        }
        l1_note = "marker observed in the recording run; crash worlds not explored yet";
    }

    var trace = readTraceOrRefuse(gpa, rec_trace, trace_cap, "could not read the trace");
    defer trace.deinit();

    var final = snapshotOrRefuse(gpa, state_abs, "could not snapshot the final state");
    defer final.deinit();

    // Classified before the structural detectors, so every exit below — including the
    // UNKNOWNs — reports the classification that actually existed, not a placeholder.
    // The plan is the single source for both the judgement and the report (ADR 0004).
    var l0_plan = engine.classify(gpa, initial, final) catch setupError("out of memory");
    defer l0_plan.deinit();
    l0_history_count = l0_plan.history_count;
    l0_note = buildL0Note(arena, l0_plan);

    // Now that the classification exists, not at the read: see the pairing above. Ahead
    // of the version check below, and the two cannot both apply: a capped read returns
    // before `decodeHeader`, so `version_mismatch` is always false when `too_large` is set.
    answerForOversizedTrace(trace, "the recording run", trace_cap);

    // ---- structural detectors, before exploring anything --------------------------
    //
    // These run first on purpose. Exploring N worlds on top of a recording run that
    // cannot be trusted only multiplies the untrustworthiness — and every one of those
    // worlds would produce a verdict that looks just as confident.

    // The trace has been read. Whatever it says about boundaries is the account from
    // here on; before this point there is no account, which is a different fact from
    // "there was no boundary" and the report now tells them apart.
    boundary_ev.trace_read = true;

    if (trace.version_mismatch)
        unknown(.contract_version_mismatch, "the shim was built against a different trace contract than this engine");

    // One line for both platforms now, because the difference between them was never
    // the platform: it was which facts had been looked at. The old macOS clause named a
    // cause it had not measured and the old Linux clause named three (#10, #391); both
    // are replaced by what the image actually shows. `no_shim_marker` itself, the
    // verdict and the exit are unchanged, so no frozen surface moves.
    if (!trace.saw_shim_ready)
        unknown(.no_shim_marker, noShimDetail(arena));

    // The shim's half of the boundary evidence, recorded the moment the trace is known
    // to be the shim's — before every refusal below, because each of them writes a
    // report and the account has to say what had been observed by then. The order is the
    // rule `metadata_note` states and this field used to break: publish what was seen,
    // never a default standing in for it.
    boundary_ev.shim_reported = true;
    boundary_ev.shim_boundary = trace.boundary != null or trace.foreign_pid_seen;
    boundary_ev.shim_foreign_touch = trace.foreign_kill_point;
    boundary_ev.exec_continuations = trace.exec_continuations;
    if (trace.hard_boundary) |b| boundary_ev.shim_hard = switch (b) {
        // The engine says of the other .exec shape "refusing is the safe misreading"
        // (below), so the account must not assert breakage it did not establish. The
        // two wordings split on the same field the refusal splits on.
        .exec => if (trace.exec_chain_broken)
            "an image replacement whose chain of observation broke"
        else
            "an image replacement before the subject announced itself",
        .thread => "a thread",
        .detached => "a process leaving the containment group",
        else => null,
    };

    if (trace.truncated)
        unknown(.trace_truncated, "the trace ends mid-record; how many operations there were is unknown");

    if (trace.saw_unresolved)
        unknown(.unresolvable_path, "an operation was observed whose path could not be determined, so it cannot be placed among the crash points");

    // The shim's own `unsupported` refusal (v12). On Linux this arrives from the
    // oracle instead — same reason, same spelling shape ("renamex_np(RENAME_SWAP)"
    // here, "renameat2(RENAME_EXCHANGE)" there) — but macOS has no oracle, so the
    // only observer the platform has issues it. The shim scope-gates the record the
    // way the oracle scope-gates its refusal, so an out-of-scope swap refuses nothing.
    if (trace.first_unsupported) |name|
        unknown(.unsupported_syscall_observed, name);

    // The boundaries that stay refusals whatever an oracle says. exec replaces the
    // image the crash points were read from; a thread makes operation order
    // non-deterministic; a process that left the containment group is one the engine
    // cannot claim to have stopped. Read from `hard_boundary`, not `boundary`: the
    // first boundary in the trace can be a tolerable fork written *before* the record
    // that must refuse the run, and the refusal must not lose to it.
    if (trace.hard_boundary) |b| switch (b) {
        // A subject exec is hard only when its chain broke (#123): an unbroken
        // self-exec chain — exec record, then a same-pid shim_ready carrying the
        // operation count — is a continuation and never reaches here.
        .exec => if (trace.exec_chain_broken)
            unknown(.child_process_detected, "the target replaced its own image and the chain of observation broke: no continuation record carrying the operation count followed, or the subject announced itself again without an exec record (an execl-family call, a static image, or a stripped environment cannot carry the count). An unbroken self-exec chain is judged; a separate process is not (#123)")
        else
            unknown(.child_process_detected, "an image replacement was recorded before the subject announced itself; refusing is the safe misreading"),
        .thread => unknown(.multiple_threads_detected, "the target created a thread; operation order would not be deterministic"),
        .detached => unknown(.child_process_detected, "a process left the containment group (setsid/setpgid); the engine cannot claim to have stopped it"),
        else => {},
    };

    // Numbering integrity (#123): records vs highest number. A gap or a duplicate —
    // a restarted counter after an unobserved exec is a duplicate — means any
    // crash-point address may name a different operation than the one that ran.
    if (trace.primary_kill_records != trace.kill_point_count)
        unknown(.sequence_numbering_broken, "the subject's kill-point records and its highest sequence number disagree; the numbering has gaps or duplicates and no crash-point address can be trusted");

    // An unbroken self-exec chain is disclosed, never silent (#123 R1): the pid count
    // would otherwise read as one process while the crash points span more than one
    // image, and every other note in this report says what the judgement covered — this
    // one must too. The disclosure now rides in the evidence (set above, with the rest of
    // the shim's account) and `boundaryAccount()` appends it to whatever clause applies,
    // so no later assignment can drop it. One did: the world-only site overwrote the
    // whole sentence and lost this.

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
    var crossed_boundary = boundary_ev.shim_boundary;
    if (crossed_boundary and !args.has_oracle)
        unknown(.boundary_without_oracle, "the target crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; pass --oracle (Linux)");
    // The fs_usage oracle cannot account for other processes the way strace does, so a
    // boundary the shim saw is not tolerated under it. fs_usage excludes processes by
    // name — the man page lists Terminal, sshd and the shells, and `-e` does not lift
    // that (measured: a `/bin/sh` child produced zero lines under its own name) — so a
    // child that execs one of them mutates the judged directory in nobody's account.
    // Children that are visible are still caught by path scope (#405's shape refuses
    // `child_touched_state_dir`); what this refuses is the tolerance, not the detection.
    if (crossed_boundary and args.oracle_fs_usage)
        unknown(.boundary_without_oracle, "the target crossed a process boundary and the fs_usage oracle cannot account for other processes: fs_usage excludes some by name (the shells among them) and -e does not lift that, so what a child did in the state directory may be in nobody's account; on macOS the oracle verifies single-process runs");

    // ---- oracle comparison ---------------------------------------------------------
    // The wording matters: a PASS carrying this line is making a weaker claim than one
    // that says the two views agreed, and a reader should be able to see which is which
    // without knowing how the run was invoked.
    if (args.allow_unverified)
        oracle_note = "NOT VERIFIED (--allow-unverified) — nothing checked what the shim reported";
    if (args.has_oracle) {
        // Set before the exits below, not after them. Every `unknown()` in this block is
        // raised by the oracle having run and disagreed; a report saying "not run" beside
        // `unknown_reason: oracle_missed_operation` contradicts itself.
        oracle_note = "ran; the comparison did not complete";
        // "could not be read", not "produced no output": an oracle that ran and
        // recorded nothing leaves a readable empty file, which the lines-seen check
        // below answers with oracle_saw_nothing. This site fires when the capture
        // file itself cannot be read, and until #363's adjudication its message
        // claimed the other condition.
        const text = if (args.oracle_fs_usage)
            readFileAllocCapped(arena, oracle_out, fsusage_capture_cap, .{}) orelse
                unknown(.oracle_saw_nothing, "the fs_usage capture could not be read, or grew past the size this engine will hold; the comparison has nothing complete to read")
        else
            readFileAlloc(arena, oracle_out) orelse setupError("the oracle's capture file could not be read");
        // The bytes are in the arena now; the file has done its job. The capture is
        // system-wide and one measured run left 2.9 GB of it, so it does not stay.
        dropCapture();
        // The oracle resolves relative paths against the subject's cwd (ADR 0006). Where
        // the subject starts is the define's `cwd` when it declared one and the engine's
        // own otherwise; the subject's own chdir/fchdir move it from there. The alt
        // spelling is passed only when it genuinely differs, so containment accepts both.
        //
        // This line is the whole reason `cwd` is not a one-line feature. The shim reads
        // the cwd inside the child, so it follows the chdir on its own; the oracle reads
        // a trace after the fact and has to be told. Left at the engine's cwd, the two
        // observers would resolve the same relative path to two different files — and the
        // completeness check that compares them reports that as the shim having missed an
        // operation, or as a containment decision about a file nothing touched. A verdict
        // drawn from that is wrong in a way neither observer can see.
        var oracle_cwd_buf: [contract.max_path]u8 = undefined;
        const oracle_cwd = args.cwd orelse
            if (posix.getcwd(&oracle_cwd_buf, oracle_cwd_buf.len)) |p| std.mem.span(p) else "/";
        const parsed = if (args.oracle_fs_usage) blk: {
            const r = fsusage.read(arena, text, state_abs, if (alt_differs) state_alt else "", rec_trace, fsu_sentinel_a, fsu_sentinel_b, oracle_cwd) catch setupError("out of memory");
            // A capture with a hole in it is not an account to compare against. Each
            // of these says the witness itself is unreadable, which is a different
            // statement from "the two witnesses disagreed" — and only the second one
            // is a divergence.
            if (r.defect) |d| switch (d) {
                .unparsed => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "a line of the fs_usage capture did not match the grammar, so the account has a hole: {s}", .{textShown(arena, l)}) catch "a line of the fs_usage capture did not match the grammar"),
                .truncated => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "fs_usage cut a pathname at its display width, so the line cannot be scoped to the state directory either way: {s}", .{textShown(arena, l)}) catch "fs_usage cut a pathname at its display width"),
                .unresolved_fd => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the capture carries an operation on a descriptor it never saw opened, so where it points is unknown: {s}", .{textShown(arena, l)}) catch "the capture carries an operation on a descriptor it never saw opened"),
                .unresolvable_path => |l| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the capture carries an operation whose path this reader could not read or place, so where it points is unknown: {s}", .{textShown(arena, l)}) catch "the capture carries an operation whose path could not be read or placed"),
                .unknown_call => |l| unknown(.unsupported_syscall_observed, std.fmt.allocPrint(arena, "fs_usage reported a call on the state directory that this version does not model: {s}", .{textShown(arena, l)}) catch "fs_usage reported a call this version does not model"),
                .no_subject => unknown(.oracle_saw_nothing, "no thread in the fs_usage capture wrote to the shim's trace file, so the capture cannot say which lines are the subject's"),
                .missing_sentinel => |sp| unknown(.oracle_saw_nothing, std.fmt.allocPrint(arena, "the fs_usage capture is missing a sentinel the engine placed ({s}), so nothing establishes that the observer covered the whole recording", .{textShown(arena, sp)}) catch "the fs_usage capture is missing a sentinel the engine placed"),
            };
            break :blk r.parsed;
        } else oracle.parse(arena, text, state_abs, if (alt_differs) state_alt else "", oracle_cwd) catch setupError("out of memory");

        // The witness has now looked, and what it saw is part of the account from here
        // on — including on the refusals immediately below, which are exactly the runs
        // where a stale "single process" used to be published.
        boundary_ev.witness = .{ .read = .{
            .kind = if (args.oracle_fs_usage) .fs_usage else .strace,
            .children = parsed.children,
            .lines = parsed.lines_seen,
        } };
        boundary_ev.oracle_child_touched = parsed.child_touched;
        boundary_ev.oracle_boundary = parsed.boundary;

        // Set before any exit below, like oracle_note: an UNKNOWN raised by this
        // block must still carry what the oracle saw being excluded (#121).
        metadata_note = blk: {
            const items = parsed.metadata_observed.items;
            // The restore sentence rides BOTH branches: flattening is a property of
            // restore, not of the target's syscalls — a setup-created 0600 file runs
            // its crash worlds at 0644 whether or not the target ever chmods (R2,
            // the buku shape: sqlite fchowns only as root, so the note would
            // otherwise vanish exactly where the flattening bites hardest).
            if (items.len == 0) break :blk "none observed. Restore does not reproduce ownership/permission/timestamp state: crash worlds run at the engine's default modes, with timestamps assigned during restore";
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
                "{d} ownership/permission/timestamp write(s) observed and excluded from judgement — outside the judged state (#121, #190): {s}. Restore does not reproduce ownership/permission/timestamp state: crash worlds run at the engine's default modes, with timestamps assigned during restore",
                .{ items.len, names.items },
            ) catch "observed (detail unavailable)";
        };

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

        oracle_verified = true;
        // The account names the witness and, where the witness is narrower, what it did
        // not check. The promise this flag makes is that a macOS run *naming its oracle*
        // carries the Linux claim — and a reader could not tell the two apart from this
        // line, which read identically whichever observer had run. Prose, so surface 2
        // permits it: `docs/contract-freeze.md` freezes the account fields' presence and
        // the machine fields' meaning, not their wording.
        // The witness and its narrowing go at the END of the line. Two acceptance checks
        // match `agreed on N operations` as a substring (spike/acceptance.sh:703, 2835);
        // a prefix would break them, and "surface 2 permits improving the prose" is a
        // licence about the freeze, not about the checks that hold the code to it.
        const agreed = std.fmt.allocPrint(
            arena,
            // "syscall lines examined" verbatim: spike/acceptance.sh:700 extracts the
            // count with `grep -o '[0-9]* syscall lines examined'`, and dropping the word
            // made the oracle-agreement check read scanned=0 (CI, first run of #406).
            "agreed on {d} operations ({d} syscall lines examined, {d} in scope of the judged state)",
            .{ parsed.classes.items.len, parsed.lines_seen, parsed.lines_in_scope },
        ) catch "agreed";
        oracle_note = if (args.oracle_fs_usage)
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
        else
            std.fmt.allocPrint(arena, "{s}, witness strace", .{agreed}) catch agreed;

        // The oracle can reveal children the shim never saw (a raw clone whose child
        // loads nothing), and every consequence of having crossed a boundary — the
        // quiescence sampling below above all — must engage for those too. The account
        // itself needs no assignment here: the child count is in the evidence, and the
        // image disclosure rides beside it rather than having to be copied along, which
        // is what the wholesale replacement this replaced had to remember to do.
        if (parsed.children > 0) crossed_boundary = true;
    }


    // Quiescence, observed rather than proven. A tolerated child was killed with the
    // group, but a grandchild reparented away is nobody's child to wait for — so when a
    // boundary was crossed, the final state is sampled twice and any disagreement is a
    // writer still alive. Two equal samples do not prove a future writer cannot exist;
    // the report says "observed", never "proven".
    if (crossed_boundary) {
        var final_again = snapshotOrRefuse(gpa, state_abs, "could not re-snapshot the final state");
        defer final_again.deinit();
        if (!snapshotsEqual(final, final_again))
            unknown(.state_not_quiescent, "the state directory changed between two samples taken after the recording run was contained: something is still writing");
        // The capture is L1 evidence and gets the same observation (#46). Its first
        // sample was the marker scan above; the oracle-output parse sits between the
        // two, so the observed window is wide without costing an extra wait.
        const rec_capture_again = observeCapture(rec_stdout, null) catch
            setupError("the recording run's stdout capture could not be read back");
        if (rec_capture.sawTruncation() or rec_capture_again.sawTruncation() or
            !rec_capture.fingerprintEql(rec_capture_again))
            unknown(.state_not_quiescent, "the stdout capture changed between two samples taken after the recording run was contained: something is still writing to the inherited stdout");
    }

    if (!snapshotsEqual(initial, final) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed while zero mutating operations were recorded: operations were missed");

    // #5, after every trust detector above has had its say: under an oracle a mid-run
    // mknod already refused as unsupported_syscall_observed (#121's defined list keeps
    // precedence), and quiescence judged the samples themselves — this catches what
    // reaches here with no syscall witness at all, the no-oracle path being the one
    // place an unreproducible entry could otherwise slip into the worlds.
    refuseUnsupportedEntry(arena, final, "appeared during the recording run");

    // The general form of the zero-ops detector above (#405). That one asks whether the
    // state moved while *nothing* was counted, and goes silent the moment one operation
    // is recorded: a target whose libc write is seen and whose raw write is not looks
    // exactly like one that was fully observed. Measured on the shipped build — a
    // raw-forked child's file sat in the judged directory under a PASS.
    //
    // Placed after `refuseUnsupportedEntry` on purpose. A `mknod`'d FIFO is a change no
    // operation names — the shim interposes no `mknod` anywhere — so running first would
    // take three acceptance legs' refusals and answer them under this name instead of
    // the one that says what is actually wrong with the entry.
    //
    // After the oracle comparison too: where an oracle ran, `oracle_missed_operation`
    // names the specific syscall that went unseen, which is strictly more than "this
    // path is unexplained". This is the detector for the runs that have no second
    // witness at all, which is every macOS run that does not pay root.
    reconcileOrRefuse(gpa, arena, initial, final, trace.ops.items, state_abs, if (alt_differs) state_alt else "");

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
    // ---- preflight cut ------------------------------------------------------------
    //
    // Deliberately *before* the zero-op PASS branch and the exploration loop: preflight
    // makes no PASS claim (so the completeness gate does not apply), and everything a
    // preflight can honestly say is known once the recording-phase gates above have all
    // held their fire. The exploration-only refusals — kill landing, world-side process
    // boundaries, baseline behavior, checker falsification — have not run, and the
    // report says so by name. This exit is unconditional; no explore/replay code below
    // is reachable in preflight mode.
    if (mode == .preflight) {
        // Preflight binds its define from the flags alone (--config is refused above),
        // and the flags always carry the string form — so both unwraps below are
        // structurally satisfied today. They are refusals rather than unreachables so
        // that a future route feeding preflight an argv-form define fails closed with
        // the constraint named instead of printing a hint that cannot be spelled.
        // (If such a route ever exists, this check should move ahead of the recording
        // run — firing here would be a refusal after a side effect, the shape the
        // --json placement refusal above deliberately avoids.)
        const pf_msg = "preflight takes the define-surface flags, which carry the string form; the argv form lives in a sideeye.toml, and `sideeye explore --config` answers strictly more";
        const pf_setup: ?[]const u8 = if (args.setup) |s| switch (s) {
            .str => |x| x,
            .argv => setupError(pf_msg),
        } else null;
        const pf_op: []const u8 = switch (operation) {
            .str => |x| x,
            .argv => setupError(pf_msg),
        };
        // #199: the second observation, opt-in. Without `--twice` this is the answer
        // preflight has always given from one run, and the report names determinism as
        // unchecked; with it, the second run happens here and the report carries what
        // the comparison found — including, when they differ, the refusal to accept.
        const repeat: ?Repeat = if (args.twice)
            observeAgain(gpa, arena, initial, final, state_abs, state_alt, op_argv, shim, args.oracle, args.work, expect_status, rec_started_ms, args.cwd)
        else
            null;
        preflightReport(arena, n, state, pf_setup, pf_op, shim, args.oracle, args.expect_status, repeat);
    }

    if (n == 0) {
        requireCompleteness(arena, args.has_oracle, args.allow_unverified);
        // "judged state", not "state directory": a run whose only writes are
        // ownership/permission metadata lands exactly here with zero kill points,
        // and those writes DO change the directory — just nothing the verdict
        // judges. The metadata line below is the disclosure; without it this
        // headline reads as a plain falsehood over a chmod-only operation (R1 #121).
        // The oracle line rides along because it is the metadata note's provenance.
        say(
            \\PASS  the operation performed nothing that can change the judged state
            \\      explored 0 crash points; nothing to kill before
            \\      expected status: {d}
            \\      atomicity: {s}
            \\      oracle: {s}
            \\      metadata: {s}
            \\      l1: {s}
            \\      case: {s}
            \\      not tested: {s}
            \\
        , .{ expected_status_val, l0_note, oracle_note, metadata_note, l1_note, case_note, notTestedText() });
        if (args.json) |jp| writeJsonReport(arena, jp, "PASS", @intFromEnum(contract.ExitCode.pass), null, null, null, null);
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
        const cargv = commandArgv(arena, check_cmd) catch setupError("--check is empty");
        if (cargv.len == 0) setupError("--check is empty");
        check_argv = cargv;
        // Before the falsification exits, for the same reason as the oracle note above:
        // `checker_not_falsified` next to `checker: none configured` is a report arguing
        // with itself about whether a checker was given.
        checker_note = "configured; falsification did not complete";

        if (engine.countCorruptible(initial) == 0)
            unknown(.checker_not_falsified, "the state directory holds no files or symlinks, so there was nothing to corrupt and the checker could not be tested");

        engine.restore(initial, state_abs) catch |e| restoreFailure(e, "could not restore before falsifying the checker");
        // Through the same disposition as the restore one line up, not setupError:
        // corruption is the other rewrite of the recorded tree, its errors are the
        // same RestoreError set (UnsafeRoot included — engine.zig's own comment on
        // corruptState says why it re-checks the root rather than trusting its
        // neighbour), and by this line the define has run, so exit 3 would claim
        // it never did (#363).
        engine.corruptState(initial, state_abs) catch |e| restoreFailure(e, "could not corrupt the state for the falsification probe");

        // The gate's child output is captured and re-emitted with a per-line
        // `falsify: ` marker (#134). By design this step produces exactly the output
        // a real finding would produce — a target failing over a broken store — and
        // a single line harvested from an unlabeled transcript once became "world
        // evidence" (the buku correction, PR #133). A fence would not travel with an
        // excerpt; a per-line prefix does.
        var fal_buf: [contract.max_path]u8 = undefined;
        const fal_out = std.fmt.bufPrint(&fal_buf, "{s}/falsify-check.txt", .{args.work}) catch setupError("path too long");
        removeFile(fal_out);
        const probe = posix.runChildCaptureAll(gpa, cargv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
        }, fal_out, args.cwd) catch |e| spawnFailure(e, .exploring, "could not run --check");

        // Re-emitted before the verdict on the probe: unknown() exits the process,
        // and the gate's output is evidence in the refusal case too. Blank lines are
        // dropped — an empty line carries nothing harvestable and a bare marker is
        // noise. A capture that cannot be read back is said out loud rather than
        // silently swallowed.
        if (readFileAllocCapped(arena, fal_out, 1024 * 1024, .{})) |fal_text| {
            var lines = std.mem.splitScalar(u8, fal_text, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                say("falsify: {s}\n", .{line});
            }
        } else {
            say("falsify: (the gate's child output could not be read back from {s} — missing, unreadable, or over the 1 MiB re-emission cap; the capture file, if present, still holds it)\n", .{fal_out});
        }

        switch (probe) {
            .exited => |code| {
                // 126 is the capture stub's own exit code for a capture it could not
                // open (runChildImpl). Read as "the checker went red", it let
                // /bin/true pass the gate whenever the capture path was blocked — a
                // directory squatting on the default /tmp work dir did it (R1 of
                // #134). The MCP adapter already discriminates this same stub exit;
                // a checker that genuinely exits 126 is indistinguishable and gets
                // the fail-closed reading.
                if (code == 126)
                    unknown(.checker_not_falsified, "the checker probe exited 126: either the capture stub could not open its stdout capture in the work directory, or the checker itself exited 126 — indistinguishable from here, so the gate refuses rather than counting it as red");
                if (code == 0)
                    unknown(.checker_not_falsified, "the checker accepted a state whose every file had been overwritten with junk and every symlink retargeted at a nonexistent name");
            },
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
    // The claim exhibit (#231, ADR 0020): the earliest world whose violation
    // includes the declared checker, latched independently of the overall
    // earliest by the judgment-time bit (`l2_failed`), never by parsing the
    // invariant string. Often the same world as `first_failure`; the poetry
    // shape — an L0-only precision-limit world structurally ahead of the real
    // checker-red one — is where the two diverge.
    var first_checker: ?engine.WorldResult = null;
    var first_checker_l0 = false;
    var first_checker_l1 = false;
    var first_checker_path: [contract.max_path]u8 = undefined;
    var first_checker_path_len: usize = 0;
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
        // Stop if whoever launched this exploration is gone (#269, --stop-when-orphaned).
        //
        // The MCP adapter passes the flag on every self-exec: an agent host restarts MCP
        // servers as ordinary lifecycle, and an orphaned explore keeps killing processes
        // and rewriting the state directory with nobody left to report to. Checked before
        // `restore`, so what happens instead of the deletion is the refusal rather than
        // the deletion followed by one.
        //
        // The claim is narrow and the reason's own documentation says so: the next world
        // boundary **that is reached**. A setup, recording or checker run that hangs
        // never reaches one, and the process-group teardown that would help there runs at
        // the end of a world, not the start.
        if (stop_when_orphaned and posix.getppid() != startup_ppid)
            unknown(.parent_exited, "the process that launched this exploration is gone; stopping at a world boundary rather than continuing to kill processes and rewrite the state directory with nobody to report to");
        engine.restore(initial, state_abs) catch |e| restoreFailure(e, "could not restore the state directory");

        var kbuf: [16]u8 = undefined;
        const kstr = std.fmt.bufPrint(&kbuf, "{d}", .{k}) catch unreachable;
        var wt_buf: [contract.max_path]u8 = undefined;
        const world_trace = std.fmt.bufPrint(&wt_buf, "{s}/trace-{d}.bin", .{ args.work, k }) catch setupError("path too long");
        removeFile(world_trace);
        removeFile(world_stdout);

        const term = posix.runChildCaptureWorld(gpa, op_argv, &.{
            .{ "TOY_STATE", state_abs },
            .{ contract.env.state_dir, state_abs },
            .{ contract.env.state_dir_alt, state_alt },
            .{ contract.env.trace_path, world_trace },
            .{ contract.env.kill_at, kstr },
            // Pinned empty: see the recording pairs.
            .{ contract.env.seq_base, "" },
            .{ preload_var, shim },
        }, world_stdout, if (args.world_timeout_s) |s| @as(u64, s) * 1000 else null, args.cwd) catch |e| switch (e) {
            // Received here, at the one site that passes a budget, so the refusal can
            // name the limit that fired — the rule #323 and #351 shipped under:
            // a failure with a limit reports the limit, because the operator can move
            // it. `spawnFailure` never sees TimedOut; every other call site's error
            // type says so at compile time.
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
                unknown(.child_timed_out, detail);
            },
            error.ForkFailed, error.OutOfMemory, error.WaitFailed => |se| spawnFailure(se, .exploring, "could not run --operation"),
        };

        var wtrace = readTraceOrRefuse(gpa, world_trace, trace_cap_world, "could not read a world trace");
        answerForOversizedTrace(wtrace, "an explored world", trace_cap_world);
        defer wtrace.deinit();

        // The world's own boundary evidence, before the refusals that read it. Without
        // this the account for a world-side refusal is the *recording's* clause, which
        // review measured saying "no boundary was recorded" on a run refused because a
        // world's child wrote into the judged directory. The world-only site further
        // down was generalised and these four siblings were not; same class, same file.
        boundary_ev.world_boundary = boundary_ev.world_boundary or
            wtrace.boundary != null or wtrace.foreign_pid_seen;
        boundary_ev.world_foreign_touch = boundary_ev.world_foreign_touch or wtrace.foreign_kill_point;

        // The second witness again, on every explored world and the baseline. A child's
        // behaviour is allowed to differ between worlds — the parent dying earlier
        // changes which path the child takes — so clearing the recording run clears
        // nothing else.
        if (wtrace.foreign_kill_point)
            unknown(.child_touched_state_dir, "a process other than the subject performed a state-directory operation in an explored world");
        // A world may take a branch the recording run did not (the kill changes what the
        // target sees), so an unmodellable in-scope operation can first appear here.
        if (wtrace.first_unsupported) |name|
            unknown(.unsupported_syscall_observed, name);
        if (wtrace.hard_boundary) |hb| switch (hb) {
            .detached => unknown(.child_process_detected, "a process left the containment group in an explored world"),
            .thread => unknown(.multiple_threads_detected, "the target created a thread in an explored world"),
            .exec => unknown(.child_process_detected, "the target replaced its own image in an explored world without an unbroken chain of observation"),
            else => {},
        };
        if (wtrace.primary_kill_records != wtrace.kill_point_count)
            unknown(.sequence_numbering_broken, "the subject's kill-point numbering has gaps or duplicates in an explored world; the world's crash-point address cannot be trusted");

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
        // required to exit the declared success status; a different outcome here means
        // the restored state is not the state that was recorded, and every other world
        // started from it too.
        if (k > n) switch (term) {
            .exited => |code| if (code != expect_status)
                unknown(.baseline_run_failed, std.fmt.allocPrint(arena, "the un-killed baseline world exited {d} where {d} was expected although the recording run of the same command succeeded: the restored state differs from the recorded one", .{ code, expect_status }) catch "the un-killed baseline world exited with an unexpected status"),
            else => unknown(.baseline_run_failed, "the un-killed baseline world did not exit normally"),
        };

        var crashed = snapshotOrRefuse(gpa, state_abs, "could not snapshot a crashed state");
        defer crashed.deinit();

        // Same observation as after the recording run: when a boundary was crossed,
        // one sample is a moment and two agreeing samples are a state. Boundary
        // evidence is per-world as well as recording-global (#46): a recording that
        // never forked says nothing about a world where the parent dying earlier sent
        // the child down a forking path — the same reason the per-world witness above
        // re-checks what the recording already cleared.
        const world_armed = crossed_boundary or wtrace.boundary != null or wtrace.foreign_pid_seen;
        // A boundary the recording never crossed has no clearance to inherit: the
        // recording's oracle accounted for no process beside the subject, and worlds
        // run with no oracle at all, so nothing can say what this process did. The
        // per-world analog of the recording-time refusal, under the same reason
        // token — the message is what distinguishes them. The account is written
        // BEFORE the refusal so the report's processes field tells the world's
        // story, never the recording's "single process".
        if (!crossed_boundary and world_armed) {
            boundary_ev.world_only = true;
            unknown(.boundary_without_oracle, "a process boundary appeared in an explored world that the recording never crossed; explored worlds run without an oracle, so nothing accounts for what the other process did");
        }
        var world_capture_first: ?CaptureObservation = null;
        if (world_armed) {
            var crashed_again = snapshotOrRefuse(gpa, state_abs, "could not re-snapshot a crashed state");
            defer crashed_again.deinit();
            if (!snapshotsEqual(crashed, crashed_again))
                unknown(.state_not_quiescent, "the crashed state changed between two samples: something the subject started is still writing");
            // The capture's first sample (#46). The second rides the marker scan below,
            // so the observed window brackets the checker and the scan itself.
            world_capture_first = observeCapture(world_stdout, null) catch
                setupError("a world's stdout capture could not be read back");
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
            }, args.cwd) catch |e| spawnFailure(e, .exploring, "could not run --check");
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
        if (args.marker != null or world_capture_first != null) {
            const world_capture = observeCapture(world_stdout, args.marker) catch
                setupError("a world's stdout capture could not be read back");
            // The refusal comes before the marker bit is used anywhere: a scan raced
            // by a live writer must not decide whether L1 applies (#46). Two equal
            // samples are an observation, never a proof of future quiet.
            if (world_capture_first) |first| {
                if (first.sawTruncation() or world_capture.sawTruncation() or
                    !first.fingerprintEql(world_capture))
                    unknown(.state_not_quiescent, "the stdout capture of a crashed world changed between two samples: something the subject started is still writing to the inherited stdout");
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
        refuseUnsupportedEntry(arena, crashed, if (k <= n) "left in a crashed world" else "left by the baseline re-run");

        if (marker_seen and k <= n) marker_worlds += 1;
        const l1 = if (marker_seen) engine.judgeL1(l0_plan, initial, final, crashed) else null;

        // The baseline world was never killed. If the invariant fails there, it fails
        // without any help from sideeye — the checker rejects a state the operation
        // produces normally, or the operation is broken on its own — and neither is a
        // crash-consistency counterexample. Reporting it as "N of N explored worlds violated
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
                    const p = violationPath(vv);
                    @memcpy(first_failure_path[0..p.len], p);
                    first_failure_path_len = p.len;
                }
            }
            if (l2_failed and first_checker == null) {
                const v = l0 orelse l1;
                first_checker = .{ .k = k, .term = term, .landed = landed, .violation = v };
                first_checker_l0 = l0 != null;
                first_checker_l1 = l1 != null;
                if (v) |vv| {
                    const p = violationPath(vv);
                    @memcpy(first_checker_path[0..p.len], p);
                    first_checker_path_len = p.len;
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
        const what = violationObserved(f.violation);
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
        // The claim exhibit (#231, ADR 0020). Same world as the earliest: it
        // shares the earliest's case file — no duplicate is written. Different
        // world: its case is written strictly AFTER the earliest's, so in a
        // fresh work directory 000001 always belongs to the overall earliest;
        // and when the earliest's case could not be written at all, the checker
        // case is not written either, keeping that ownership an invariant even
        // under write failure. The second write sits inside the same
        // explore-only condition as the first: a replay does not mint (ADR 0009).
        const checker_detail: ?CheckerEarliest = if (first_checker) |fc| blk: {
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
                break :blk2 writeCase(arena, args.work, case_args, fc.k, n, trace, if (fc.violation) |v| @tagName(v) else "checker");
            } else null;
            const ccase = if (same_world) case_shown else (csaved orelse "(not saved)");
            const creplay = if (same_world)
                replay_cmd
            else if (csaved) |cc|
                std.fmt.allocPrint(arena, "sideeye replay {s} --shim {s}", .{ cc, shim }) catch "-"
            else
                "-";
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
                    .observed = violationObserved(fc.violation),
                    .invariant = cinvariant,
                },
                .case = ccase,
                .replay = creplay,
            };
        } else null;
        say(
            \\FAIL  {d} of {d} explored worlds violated an invariant
            \\
            \\invariant   {s}
            \\earliest    crash point {d} of {d}
            \\            after  {s}({s})
            \\            before {s}({s})
            \\path        {s}
            \\observed    {s}
            \\explored    {d} worlds (crash points {d} + 1 baseline)
            \\expected    exit {d}
            \\atomicity   {s}
            \\oracle      {s}
            \\metadata    {s}
            \\checker     {s}
            \\l1          {s}
            \\case        {s}
            \\replay      {s}
            \\
        , .{
            violations, explored,
            invariant,
            f.k,        n,
            // The three target-chosen operands go to the text defanged; the
            // JSON block below reads the raw variables (#26).
            after,      textShown(arena, after_path),
            before,     textShown(arena, before_path),
            textShown(arena, path_shown),
            what,
            explored,   n,
            expected_status_val,
            l0_note,
            oracle_note,
            metadata_note,
            checker_note,
            l1_note,
            case_shown,
            replay_cmd,
        });
        // Printed only when the two exhibits are different worlds; when the
        // earliest is itself checker-red — every FAIL this engine produced
        // before poetry — the text above is byte-identical to what it was.
        if (checker_detail) |cd| {
            if (cd.e.k != f.k) say(
                \\checker red crash point {d} of {d} ({s})
                \\            case   {s}
                \\            replay {s}
                \\
            , .{ cd.e.k, n, cd.e.invariant, cd.case, cd.replay });
        }
        say(
            \\processes   {s}
            \\not tested  {s}
            \\
            \\reproduce   SIDEEYE_STATE_DIR={s}{s} SIDEEYE_TRACE_PATH={s} {s}={s} SIDEEYE_KILL_AT={d} SIDEEYE_SEQ_BASE= <operation>
            \\
        , .{
            boundaryAccount(),
            notTestedText(),
            state_abs, alt_env, repro_trace, preload_var, shim, f.k,
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
        }, checker_detail, null, null);
        std.process.exit(@intFromEnum(contract.ExitCode.fail));
    }

    requireCompleteness(arena, args.has_oracle, args.allow_unverified);

    say(
        \\PASS  {d}/{d} explored worlds satisfied the built-in atomicity invariant
        \\      explored {d} worlds (crash points {d} + 1 baseline)
        \\      expected status: {d}
        \\      atomicity: {s}
        \\      oracle: {s}
        \\      metadata: {s}
        \\      checker: {s}
        \\      l1: {s}
        \\      case: {s}
        \\      processes: {s}
        \\      not tested: {s}
        \\
    , .{ explored, explored, explored, n, expected_status_val, l0_note, oracle_note, metadata_note, checker_note, l1_note, case_note, boundaryAccount(), notTestedText() });
    if (args.json) |jp| writeJsonReport(arena, jp, "PASS", @intFromEnum(contract.ExitCode.pass), null, null, null, null);
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
/// "0".."255", nothing else. One parser serves the flag and the config key, so the
/// two spellings of the same declaration cannot drift into accepting different
/// grammars — the value they produce governs the recording check, the baseline
/// world, the saved case, and the report alike (ADR 0014).
/// `--world-timeout` in seconds: 1..86400, digits only (#263). Zero is refused rather
/// than read as "no budget" — an operator who typed a number meant a bound, and the
/// spelling for "no bound" is omitting the flag. The ceiling is a day: any larger value
/// is more plausibly a unit mistake than an intent, and the bound is what keeps the
/// millisecond conversion trivially inside u64.
fn parseWorldTimeout(s: []const u8) u32 {
    const msg = "--world-timeout must be a whole number of seconds, 1..86400";
    if (s.len == 0 or s.len > 5) setupError(msg);
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') setupError(msg);
        v = v * 10 + (ch - '0');
    }
    if (v == 0 or v > 86400) setupError(msg);
    return v;
}

fn parseExpectStatus(s: []const u8, msg: []const u8) u8 {
    if (s.len == 0 or s.len > 3) setupError(msg);
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') setupError(msg);
        v = v * 10 + (ch - '0');
    }
    if (v > 255) setupError(msg);
    return @intCast(v);
}

fn splitArgs(arena: std.mem.Allocator, cmd: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, cmd, ' ');
    while (it.next()) |tok| try list.append(arena, tok);
    return list.items;
}

/// One spawn shape for both spellings: the string form splits on spaces here (the
/// flags' rule, ADR 0007 decision 5) and the argv form passes through verbatim
/// (ADR 0019) — the executor sees a `[]const []const u8` either way, and nothing
/// downstream of this call knows which spelling the define used.
fn commandArgv(arena: std.mem.Allocator, cmd: config.Command) ![]const []const u8 {
    return switch (cmd) {
        .str => |s| splitArgs(arena, s),
        .argv => |a| a,
    };
}

// ---- preflight ---------------------------------------------------------------------

/// The gap the cohort-2 protocol asks for between the two runs' starts.
///
/// Two seconds is what epoch-second stamping needs to move, and it is the interval one
/// unpinned `borg create` split at — it is **not** a measured sufficiency threshold for
/// nondeterminism in general, and the help text says so rather than implying a target
/// that survives it is repeatable.
const repeat_gap_ms: u64 = 2000;

/// The rendered-byte ceiling for the split report's list of paths.
///
/// It exists for the pathological input, not the ordinary one: a single `rel` can
/// approach `contract.max_path` (4096), and a handful of those would overrun the report
/// buffer every other line shares. **On ordinary input the binding limit is
/// `repeat_diff_slots` below** — short paths fill 64 slots long before they fill a
/// kilobyte — which is the opposite of what an earlier version of this comment implied
/// (review). Paths are target-chosen, so each goes through the same neutralisation the
/// l0 note uses: an unescaped newline in a file name would let a target forge report
/// lines. The first path is exempt from the ceiling; see `preflightReport`.
const repeat_diff_byte_budget: usize = 1024;

/// How many differences are collected before `DiffCount.total` carries the rest.
///
/// A separate bound from the byte budget above, and deliberately so: this one limits
/// what is *held*, the other limits what is *printed*. Collapsing them would tie the
/// allocation to a rendering decision — and `total` keeps counting past both, so a
/// tree that overflows either still reports its real size rather than the cap's.
const repeat_diff_slots: usize = 64;

/// What the second observation found.
const Repeat = struct {
    /// Measured between the two runs' STARTS, on the monotonic clock — not the sleep
    /// that was requested. A reported gap derived from the request would be the
    /// measurement describing its own intent.
    gap_ms: u64,
    count: engine.DiffCount,
    diffs: []const engine.Difference,
};

/// Observe the operation a second time and compare the two post-states (#199).
///
/// Order is the cohort harness's, not the obvious one: **sleep, then restore**. The
/// protocol defines the gap between the two runs' starts, and restoring before the wait
/// would leave the freshly rebuilt pre-state exposed for the whole gap to anything the
/// first run left running.
///
/// Run B is gated explicitly here rather than by reusing the recording path wholesale:
/// that path writes the report globals as it goes, so a second pass through it would
/// overwrite what the first run reported.
///
/// **Not every gate run A passes.** Ten of the fifteen a preflight can reach: exit
/// status, oversized trace, shim initialisation, truncation, the shim-side foreign
/// writer, trace-contract version, the hard boundaries (exec / thread / detached), the
/// soft boundary without an oracle, quiescence of the state tree, and a state that moved
/// while nothing was recorded.
///
/// What run B does NOT get, listed because an earlier draft of this comment claimed it
/// got everything (review): `unresolvable_path`, `unsupported_syscall_observed`,
/// `sequence_numbering_broken`, the oracle comparison, and stdout quiescence. The first
/// three walk the trace's records — a second copy of that analysis is the wholesale
/// reuse this function exists to avoid — and the oracle comparison is disclosed in the
/// report's `scope` line. Stdout quiescence guards the capture the marker is read from,
/// which run B has no claim resting on.
///
/// The ones that WERE added are those whose absence would make the property's own words
/// false: "the two runs observed" is not true of a run whose shim never loaded or whose
/// operations went unrecorded, and a comparison against a run something else wrote into
/// is not a comparison of this operation. **That criterion, not the cost of the check,
/// is what decides the split** — `state_changed_without_ops` was excluded on cost in the
/// first revision and review showed the cost reason was wrong for it, so it moved.
fn observeAgain(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    initial: engine.Snapshot,
    first: engine.Snapshot,
    state_abs: []const u8,
    state_alt: []const u8,
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
) Repeat {
    // The floor is enforced, not assumed. `sleepForMs` is best effort by its own
    // documentation — a signal cuts it short and nothing re-arms it — while `--help`,
    // the README and the CHANGELOG all promise "at least two seconds". Without this
    // loop the command could print `two runs 47 ms apart left equal state` and
    // contradict its own help (review, P2). The clock is monotonic, so each pass
    // shortens the remainder and the loop terminates.
    while (true) {
        const elapsed = posix.monotonicMs() -| first_started_ms;
        if (elapsed >= repeat_gap_ms) break;
        posix.sleepForMs(repeat_gap_ms - elapsed);
    }
    engine.restore(initial, state_abs) catch |e| restoreFailure(e, "could not restore the state directory before the second observed run");

    var trace_buf: [contract.max_path]u8 = undefined;
    const trace_b = std.fmt.bufPrint(&trace_buf, "{s}/trace-record-2.bin", .{work}) catch setupError("path too long");
    var stdout_buf: [contract.max_path]u8 = undefined;
    const stdout_b = std.fmt.bufPrint(&stdout_buf, "{s}/stdout-record-2.txt", .{work}) catch setupError("path too long");
    var oracle_buf: [contract.max_path]u8 = undefined;
    const oracle_out_b = std.fmt.bufPrint(&oracle_buf, "{s}/oracle-2.txt", .{work}) catch setupError("path too long");
    removeFile(trace_b);
    removeFile(stdout_b);
    // The oracle capture too, for the same reason the recording run removes its own:
    // a stale file from a previous invocation must not be mistaken for this run's.
    // Nothing reads `oracle-2.txt` today (the report's `scope` line says so), and
    // strace truncates on open regardless — the symmetry is the point, so a future
    // reader of that file inherits the same guarantee run A's has.
    removeFile(oracle_out_b);

    const started = posix.monotonicMs();
    const term = runOperationObserved(gpa, arena, op_argv, state_abs, state_alt, shim, oracle_path, oracle_out_b, trace_b, stdout_b, cwd);

    // The same question the recording run's own status check asks, and the same reason
    // it matters: a second run that failed says nothing about repeatability, and
    // comparing its wreckage against a successful run would report the failure as a
    // split. `recording_run_failed` is the existing member for "the run this account
    // rests on did not complete" — no new closed-set name, which the v1.0 freeze
    // forbids until 2.0.
    switch (term) {
        .exited => |code| if (code != expect_status)
            unknown(.recording_run_failed, std.fmt.allocPrint(arena, "the second observed run exited {d} where {d} was expected, although the first run of the same command succeeded: the two runs cannot be compared", .{ code, expect_status }) catch "the second observed run exited with an unexpected status"),
        else => unknown(.recording_run_failed, "the second observed run did not exit normally, although the first run of the same command succeeded"),
    }

    var trace = readTraceOrRefuse(gpa, trace_b, trace_cap, "could not read the second observed run's trace");
    defer trace.deinit();
    // #324's pairing: every site that reads with a cap must answer for it. Forgetting
    // this at one site is the defect that issue exists to fix, and its own doc warns
    // that a third read site would have no acceptance leg holding it — **this is that
    // third site**, and it has no leg: the `-Dtest-trace-cap` engines cap the shared
    // constant, so run A's read fires first and run B is never reached. What holds it
    // is this comment and review. Without the answer the cap would return an empty
    // `TraceInfo` and every gate below would go vacuously green.
    answerForOversizedTrace(trace, "the second observed run", trace_cap);
    // Recorded here, above every refusal below, for the same reason run A's evidence is
    // recorded above its own: each of them writes a report, and the account has to name
    // the run it is about. An earlier revision of this said "before the refusals" while
    // sitting after four of them (`no_shim_marker`, `trace_truncated`,
    // `child_touched_state_dir`, `contract_version_mismatch`) — harmless today, because
    // preflight refuses `--json` and the UNKNOWN text block carries no `processes` line,
    // and wrong for whoever builds on the claim next. Caught by review.
    if (trace.hard_boundary) |b| boundary_ev.second_run = switch (b) {
        .exec => "an image replacement",
        .thread => "a thread",
        .detached => "a process leaving the containment group",
        else => null,
    };
    if (boundary_ev.second_run == null and (trace.boundary != null or trace.foreign_pid_seen))
        boundary_ev.second_run = "a process boundary";
    if (boundary_ev.second_run == null and trace.foreign_kill_point)
        boundary_ev.second_run = "an operation by a process other than the subject";
    // The property says "the two runs OBSERVED in this invocation". A run whose shim
    // never initialised was not observed, and reporting it as one half of a comparison
    // would make that word false — the flag exists for targets that take a different
    // path the second time, so a second run that loads nothing is not hypothetical.
    if (!trace.saw_shim_ready)
        unknown(.no_shim_marker, noShimDetailSecondRun(arena));
    // A trace that ends mid-record leaves the operation count unknown for run B, which
    // is the same reason run A refuses on it.
    if (trace.truncated)
        unknown(.trace_truncated, "the second observed run's trace ends mid-record; how many operations there were is unknown");
    // The shim-side witness for a foreign writer, and it does not depend on an oracle.
    if (trace.foreign_kill_point)
        unknown(.child_touched_state_dir, "a process other than the subject performed a state-directory operation during the second observed run");
    if (trace.version_mismatch)
        unknown(.contract_version_mismatch, "the shim and engine disagree on the trace contract version in the second observed run");
    // The boundaries that stay refusals whatever an oracle says, applied to the second
    // run exactly as run A applies them. Read from `hard_boundary` for the same reason
    // run A does: the first boundary in a trace can be a tolerable fork written before
    // the record that must refuse.
    //
    // The first version of this function had only the check below it, gated on
    // `oracle_path == null` — so passing `--oracle` REMOVED run B's boundary checking
    // instead of strengthening it, the reverse of what an oracle does for run A. A run
    // B that created a thread, replaced its image, or left the containment group was
    // reported as "left equal state" (review, P1).
    if (trace.hard_boundary) |b| switch (b) {
        .exec => unknown(.child_process_detected, "the second observed run replaced its own image, so the two runs did not execute the same program to completion and cannot be compared"),
        .thread => unknown(.multiple_threads_detected, "the second observed run created a thread; operation order would not be deterministic, so a comparison against the first run describes an ordering nobody chose"),
        .detached => unknown(.child_process_detected, "a process left the containment group (setsid/setpgid) during the second observed run; the engine cannot claim to have stopped it, so what touched the state afterwards is unaccounted for"),
        else => {},
    };
    // A soft boundary in run B and not run A is still a boundary: the shim only sees
    // what loads it, and "was not seen" must not read as "did nothing" here either.
    //
    // What this does NOT do is compare run B's oracle capture against its shim account.
    // `oracle-2.txt` is written — run B executes under the same wrapper run A did, so
    // that the two runs differ in nothing the caller controls — and it is not parsed.
    // The comparison run A performs (`oracle.compare`, reporting
    // `oracle_missed_operation` / `oracle_saw_phantom` / `child_touched_state_dir`) is
    // about the completeness of the *account*, which the property this flag establishes
    // does not rest on: the post-states are read from the filesystem, not from either
    // witness. The report's `scope` line says so, and widening it is a separate promise.
    if ((trace.boundary != null or trace.foreign_pid_seen) and oracle_path == null)
        unknown(.boundary_without_oracle, "the second observed run crossed a process boundary and no oracle was given, so nothing can account for what the other processes did; pass --oracle (Linux)");

    var second = snapshotOrRefuse(gpa, state_abs, "could not snapshot the state after the second observed run");
    defer second.deinit();
    // Quiescence, the same way the exploration path asks it: two samples back to back.
    // A tree still being written would otherwise be compared at a moment nobody chose,
    // and the difference reported as the target's nondeterminism.
    var again = snapshotOrRefuse(gpa, state_abs, "could not re-sample the state after the second observed run");
    defer again.deinit();
    var quiesce_buf: [1]engine.Difference = undefined;
    if (!engine.diffSnapshots(second, again, &quiesce_buf).equal())
        unknown(.state_not_quiescent, "two samples of the state directory taken back to back after the second observed run disagreed: something was still writing, so the comparison would describe a moment nobody chose");

    // The partial version of `no_shim_marker`, and it belongs on the same side.
    //
    // That one says nothing was observed because the shim never loaded; this one says
    // the shim loaded and still missed operations — the tree moved while zero mutating
    // calls were recorded. Both make "the two runs observed" false, and comparing a
    // post-state nobody accounted for against one that was accounted for is not a
    // comparison of this operation.
    //
    // An earlier revision left this out and justified it, in the doc above, as "analysis
    // run A performs on its own trace and snapshots". Review measured that reason wrong
    // for this one member: it needs one field of the trace already in hand and the two
    // snapshots already taken, which is why it is a single line rather than the
    // wholesale reuse the exclusion was about.
    if (!snapshotsEqual(initial, second) and trace.mutation_count == 0)
        unknown(.state_changed_without_ops, "the state directory changed during the second observed run while zero mutating operations were recorded: operations were missed");

    const diffs = arena.alloc(engine.Difference, repeat_diff_slots) catch setupError("out of memory");
    const count = engine.diffSnapshots(first, second, diffs);
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
    for (diffs[0..count.stored]) |*d|
        d.rel = arena.dupe(u8, d.rel) catch setupError("out of memory");
    return .{
        .gap_ms = started -| first_started_ms,
        .count = count,
        .diffs = diffs[0..count.stored],
    };
}

/// The preflight verdict, on the accepted side. Refusals never reach here — they exit
/// through `unknown()` upstream with the same detector names a real run uses.
///
/// The claim is deliberately "recording accepted", not "explorable": the refusals only
/// a real exploration can raise (kill landing, world-side process boundaries, baseline
/// behavior, checker falsification) have not run, and the fixed `not checked` list
/// names them. The acceptance suite pins this wording — the claim cannot quietly grow
/// back into one this command does not earn.
fn preflightReport(arena: std.mem.Allocator, n: u32, state: []const u8, setup: ?[]const u8, operation: []const u8, shim: []const u8, oracle_path: ?[]const u8, expect_status: ?u8, repeat: ?Repeat) noreturn {
    // "not accepted", not "accepted but split". `docs/contract-freeze.md` says a
    // preflight that ACCEPTS the recording exits 0; under `--twice` the caller asked a
    // second question, so acceptance means the recording held *and* the two runs
    // agreed. Calling a split "accepted" and returning a non-zero code would contradict
    // the frozen sentence; narrowing what acceptance means under this flag does not.
    const split = if (repeat) |r| !r.count.equal() else false;
    if (split) {
        say("PREFLIGHT  not accepted — the two observed runs left different state\n\n", .{});
    } else if (n == 0) {
        say("PREFLIGHT  recording accepted, but nothing to explore — 0 state-changing operations observed\n\n", .{});
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
                // The FIRST path is always named, whatever it costs: `--help`, the
                // README and the headline all say the differing paths are named, and a
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
            }
            if (r.count.total > shown)
                say("             … and {d} more\n", .{r.count.total - shown});
            say("\n", .{});
        }
    }
    say(
        \\atomicity    {s}
        \\oracle       {s}
        \\processes    {s}
        \\
        \\not checked  kill landing, world-side process boundaries, baseline behavior,
        \\             checker falsification — only a real exploration runs these
        \\
        \\
    , .{ l0_note, oracle_note, boundaryAccount() });
    if (repeat) |r| {
        // Reported whether the runs agreed or split, and worded as an observation
        // rather than a property: two samples cannot establish that a target is
        // deterministic, and `not checked` above still carries determinism for exactly
        // that reason. The interval is the measured one — a gap printed from the sleep
        // that was requested would be the measurement describing its own intent.
        const verdict = if (split) "differed" else "left equal state";
        say(
            \\repeatability  two runs {d} ms apart {s} under --state
            \\scope          file bytes, entry kinds and symlink targets only; modes,
            \\               ownership, timestamps, and anything outside --state are
            \\               not compared, and two runs are not all runs
            \\
        , .{ r.gap_ms, verdict });
        // Stated only when an oracle ran, because otherwise it describes nothing. The
        // second run executes under the same wrapper the first did, so its capture
        // exists; what it does not get is the account comparison run A performs. The
        // post-states this line is about are read from the filesystem, not from either
        // witness — but a reader who passed --oracle would otherwise assume the second
        // run was checked the way the first was.
        if (oracle_path != null)
            say(
                \\               the second run's oracle capture is written but not
                \\               compared; only the first run's account was checked
                \\
            , .{});
        say("\n", .{});
    }
    if (oracle_path == null)
        say(
            \\note         no oracle checked the shim's account against a second witness;
            \\             explore's PASS will require --oracle <strace> (Linux) or
            \\             --allow-unverified (macOS)
            \\
            \\
        , .{});
    // When no oracle was given but strace is discoverable, the hint names the real
    // path so the next command is pasteable — named, never attached (#78).
    const oracle_part = if (oracle_path) |o|
        std.fmt.allocPrint(arena, " --oracle {s}", .{o}) catch " --oracle <strace>"
    else if (findStraceForHint(arena)) |s|
        std.fmt.allocPrint(arena, " --oracle {s}", .{s}) catch " --oracle <strace>"
    else
        " --oracle <strace>";
    // The hint carries the define that was actually accepted — dropping --setup here
    // would hand the reader a silently different define than the one preflight ran
    // (R1 finding; acceptance check 6 pins its presence). --expect-status rides the
    // same rule: preflight accepted the recording *under that status*, and a hint
    // without it would hand explore a define that refuses the very run preflight
    // just blessed (the known defect class where a hint carries a different define).
    const setup_part = if (setup) |s|
        std.fmt.allocPrint(arena, " --setup \"{s}\"", .{s}) catch " --setup <cmd>"
    else
        "";
    const expect_part = if (expect_status) |es|
        std.fmt.allocPrint(arena, " --expect-status {d}", .{es}) catch " --expect-status <n>"
    else
        "";
    if (split) {
        // No graduation hint on a split: the next step is not `explore` — that command
        // would reach the same divergence in its un-killed baseline and refuse there,
        // after the caller had written a full define. Naming the paths is the useful
        // answer, and one of them is often pinnable (a timestamp file, a temp name).
        say(
            \\next         pin or relocate what differs, then re-run this command;
            \\             explore would reach the same divergence in its baseline
            \\             world, after a full define had been written
            \\
        , .{});
        // Exit 1 here is not FAIL. `docs/ci-quickstart.md` states the rule: the four
        // verdict rows are "the verdicts a run can reach", and commands producing no
        // verdict are not in that table. preflight produces none, and the frozen
        // verdict-to-code mapping is untouched by this.
        //
        // Said plainly because review asked for it: **this is an interpretation, not a
        // quotation.** `docs/contract-freeze.md` §3 spells out the freedom of non-verdict
        // commands for exit 0 only ("Exit 0 is not reserved to PASS"); the same reading
        // extended to 1 is what this line rests on. It violates neither thing §3
        // forbids — a verdict arriving under a different code, or exit 0 read as proof a
        // check ran — but if the owner wants that reading written into §3, this comment
        // is the place that owes the reference.
        std.process.exit(@intFromEnum(contract.ExitCode.fail));
    }
    say(
        \\next         sideeye explore --state {s}{s} --operation "{s}"{s} \
        \\               --check <your-invariant.sh> --shim {s}{s}
        \\
    , .{ state, setup_part, operation, expect_part, shim, oracle_part });
    std.process.exit(@intFromEnum(contract.ExitCode.pass));
}

// ---- demo --------------------------------------------------------------------------

/// The demo's target and checker, embedded at build time (see build.zig): the same
/// files the acceptance suite drives, so the demo cannot drift from what CI proves.
const demo_toy_c = @embedFile("toy_c");
const demo_check_sh = @embedFile("check_sh");

/// Where the shim is looked for when --shim is not given: next to the binary
/// (the release-tarball layout) first, then ../lib relative to it (the zig-out
/// layout). One list serves demo, preflight, explore and replay (#78) — the demo
/// proved the order before the flag learned to default.
///
/// The list itself moved to `mcp.zig`, beside `canonicalSelf`, when `sideeye mcp`
/// became its fifth caller (#389): the server used to demand `SIDEEYE_MCP_SHIM` and
/// refuse without it, which made it the one command that did not do what `README.md`
/// says the product does. Two copies of a search order is how the two ends of that
/// sentence drift apart again.
const shim_basename = mcp.shim_basename;
fn shimCandidates(arena: std.mem.Allocator, self: []const u8) [2][]const u8 {
    return mcp.shimCandidates(arena, self) catch setupError("out of memory");
}

test "demo shim candidates: tarball sibling first, zig-out lib layout second" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const c = shimCandidates(arena, "/opt/sideeye/bin/sideeye");
    const first = std.fmt.allocPrint(arena, "/opt/sideeye/bin/{s}", .{shim_basename}) catch unreachable;
    const second = std.fmt.allocPrint(arena, "/opt/sideeye/bin/../lib/{s}", .{shim_basename}) catch unreachable;
    try std.testing.expectEqualStrings(first, c[0]);
    try std.testing.expectEqualStrings(second, c[1]);
}

/// Resolve the shim when --shim was not given (#78): the canonical binary's
/// neighbors per shimCandidates, realpath-normalized so the report and the
/// reproduce line name the real file rather than a bin/../lib spelling.
/// Absence stays loud, both looked-at paths named; argv[0] is never consulted
/// (a PATH name or a wrapper must not decide which library gets injected).
/// The probe is `mcp.findShimBeside`, not a second copy of it. Sharing only the
/// candidate list left the two ends of the search free to disagree, and they did within
/// the hour: on an allocation failure one answered the un-normalised candidate and the
/// other aborted the process. This function now owns exactly what is different about the
/// CLI — that absence is fatal here and answerable there.
fn findShim(arena: std.mem.Allocator) []const u8 {
    const self = mcp.canonicalSelf() orelse setupError("could not resolve the canonical path of this binary to look beside it for the shim; pass --shim <path>");
    const self_owned = arena.dupe(u8, self) catch setupError("out of memory");
    if (mcp.findShimBeside(arena, self_owned)) |found| return found;
    const cands = shimCandidates(arena, self_owned);
    setupError(std.fmt.allocPrint(arena, "the shim is half the product, and none was found at either place this looks — {s} and {s}. Pass --shim <path to {s}>", .{ cands[0], cands[1], shim_basename }) catch "the shim was not found beside this binary; pass --shim");
}

/// Single-quote `s` for /bin/sh: 'foo', with every embedded ' spelled '\''. Complete
/// for POSIX sh — inside single quotes nothing else is special, so this is the whole
/// escape, not a denylist.
fn shellSingleQuote(arena: std.mem.Allocator, s: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    out.append(arena, '\'') catch setupError("out of memory");
    for (s) |ch| {
        if (ch == '\'')
            out.appendSlice(arena, "'\\''") catch setupError("out of memory")
        else
            out.append(arena, ch) catch setupError("out of memory");
    }
    out.append(arena, '\'') catch setupError("out of memory");
    return out.items;
}

test "shellSingleQuote neutralizes metacharacters and embedded quotes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("'plain'", shellSingleQuote(arena, "plain"));
    try std.testing.expectEqualStrings("'a'\\''b; $(x) `y`'", shellSingleQuote(arena, "a'b; $(x) `y`"));
}

/// Create-or-truncate `path` and write `parts` in order. False on any failure —
/// the demo treats a half-written asset as a setup error, never as material.
fn writeWholeFile(path: []const u8, parts: []const []const u8) bool {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return false;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return false;
    defer _ = posix.close(fd);
    for (parts) |p| {
        var off: usize = 0;
        while (off < p.len) {
            const w = posix.write(fd, p[off..].ptr, p.len - off);
            if (w <= 0) return false;
            off += @intCast(w);
        }
    }
    return true;
}

/// `sideeye demo`: materialize the embedded planted-bug toy and checker in a scratch
/// directory, compile the toy with whatever C compiler this machine has, and self-exec
/// `explore` against it. Never returns; the exit code is explore's own (1 expected —
/// the planted bug found).
///
/// Self-exec rather than an in-process call for the same reason the MCP adapter
/// self-execs (ADR 0010): every verdict path in this file ends in `std.process.exit`.
/// Plain `execvp` with the inherited environment — not the MCP minimal-env path, which
/// exists to *withhold* credentials from an untrusted operation; the demo's operation
/// is our own toy, and the report belongs on this same stdout.
fn runDemo(gpa: std.mem.Allocator, arena: std.mem.Allocator, rest: []const []const u8) noreturn {
    var shim_flag: ?[]const u8 = null;
    var i: usize = 0;
    while (i < rest.len) {
        if (std.mem.eql(u8, rest[i], "--shim")) {
            if (i + 1 >= rest.len) setupError("--shim is missing its value");
            shim_flag = rest[i + 1];
            i += 2;
            continue;
        }
        setupError("demo takes only --shim <lib>; everything else it arranges itself");
    }

    const self = mcp.canonicalSelf() orelse setupError("could not resolve the canonical path of this binary; refusing to guess what to self-exec");
    // canonicalSelf answers from a static buffer; copy before anything else reuses it.
    const self_owned = arena.dupe(u8, self) catch setupError("out of memory");

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
    const templ = std.fmt.bufPrintZ(&templ_buf, "{s}/sideeye-demo-XXXXXX", .{troot}) catch setupError("TMPDIR is unreasonably long");
    const tmp_raw = posix.mkdtemp(templ.ptr) orelse setupError("could not create the demo's scratch directory");
    const tmp = arena.dupe(u8, std.mem.span(tmp_raw)) catch setupError("out of memory");

    const toy_src = std.fmt.allocPrint(arena, "{s}/toy.c", .{tmp}) catch setupError("out of memory");
    const tool = std.fmt.allocPrint(arena, "{s}/demo-tool", .{tmp}) catch setupError("out of memory");
    const check_path = std.fmt.allocPrint(arena, "{s}/check.sh", .{tmp}) catch setupError("out of memory");
    if (!writeWholeFile(toy_src, &.{demo_toy_c}))
        setupError("could not write the demo's toy source into the scratch directory");
    // TOY is baked into the script rather than passed through the environment: the
    // checker runs in a fresh process several layers down, and a baked value cannot be
    // lost to a change in how those layers pass environments around. Single-quoted —
    // the path contains whatever $TMPDIR contained, and an unquoted value would hand
    // its metacharacters to the shell (R1 finding). The embedded script's shebang
    // becomes a comment mid-file, which /bin/sh does not mind.
    if (!writeWholeFile(check_path, &.{ "TOY=", shellSingleQuote(arena, tool), "\nexport TOY\n", demo_check_sh }))
        setupError("could not write the demo's checker into the scratch directory");

    // Compile on the spot. cc first — every toolchain installs the alias — then the
    // real names. Each is tried with -lpthread first (older glibc needs it spelled)
    // and then without (newer glibc and macOS accept either; macOS clang warns on
    // unused -l only with -Werror, which this is not).
    const compilers = [_][]const u8{ "cc", "gcc", "clang" };
    var chosen: ?[]const u8 = null;
    outer: for (compilers) |cc| {
        for ([_]bool{ true, false }) |with_pthread| {
            var argv_l: std.ArrayList([]const u8) = .empty;
            // -w: the toy's warnings (vfork deprecation on macOS, say) are addressed
            // to this repo's developers, not to a demo viewer's terminal. Errors
            // still print — they are how a broken compile diagnoses itself.
            for ([_][]const u8{ cc, "-O0", "-w", "-DBUGGY=1", "-o", tool, toy_src }) |a|
                argv_l.append(arena, a) catch setupError("out of memory");
            if (with_pthread) argv_l.append(arena, "-lpthread") catch setupError("out of memory");
            // No cwd: this child is the demo's own compiler, not a define's command.
            const term = posix.runChild(gpa, argv_l.items, &.{}, null) catch |e| {
                // Trying the next candidate is right for a compiler that could not be
                // started. It is wrong for a wait failure: swallowing that here ends the
                // loop with "none of cc, gcc, clang worked", which diagnoses the machine's
                // toolchain for what is actually an environment problem (#264).
                if (e == error.WaitFailed) spawnFailure(e, .before_exploration, "");
                continue;
            };
            switch (term) {
                .exited => |code| if (code == 0) {
                    chosen = cc;
                    break :outer;
                },
                else => {},
            }
        }
    }
    const cc_used = chosen orelse setupError("the demo compiles its planted-bug tool on this machine and needs a C compiler; none of cc, gcc, clang worked (Debian/Ubuntu: apt install gcc; macOS: xcode-select --install)");

    say(
        \\demo  compiled the planted-bug tool with {s} into {s}
        \\demo  the tool deletes its key before renaming the replacement in; a crash
        \\demo  between those two operations leaves no key at all. exploring:
        \\
        \\
    , .{ cc_used, tmp });

    const state_dir = std.fmt.allocPrint(arena, "{s}/state", .{tmp}) catch setupError("out of memory");
    const work_dir = std.fmt.allocPrint(arena, "{s}/work", .{tmp}) catch setupError("out of memory");
    const setup_cmd = std.fmt.allocPrint(arena, "{s} init", .{tool}) catch setupError("out of memory");
    const op_cmd = std.fmt.allocPrint(arena, "{s} rotate", .{tool}) catch setupError("out of memory");
    const check_cmd = std.fmt.allocPrint(arena, "/bin/sh {s}", .{check_path}) catch setupError("out of memory");

    const exec_argv = [_][]const u8{
        self_owned,    "explore",
        "--state",     state_dir,
        "--setup",     setup_cmd,
        "--operation", op_cmd,
        "--check",     check_cmd,
        "--shim",      shim,
        "--work",      work_dir,
    };
    var argv_z: [exec_argv.len + 1]?[*:0]const u8 = undefined;
    for (exec_argv, 0..) |a, j| argv_z[j] = (arena.dupeZ(u8, a) catch setupError("out of memory")).ptr;
    argv_z[exec_argv.len] = null;
    _ = posix.execvp(argv_z[0].?, &argv_z);
    setupError("could not self-exec the exploration");
}

/// One sentence naming which form judged which files. Counts and names come from the
/// same L0Plan the judgement reads (ADR 0004), so the report cannot describe a
/// different classification than the one that ran. Names are bounded — the point is
/// "which files got the weaker claim", not an inventory.
fn buildL0Note(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
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

/// One scan unit of a target-chosen byte string, shared by the two text-side
/// defang predicates (#167): `len` bytes starting at `i` are either kept
/// verbatim or defanged as a unit. C0 controls and DEL keep their original
/// treatment. The C1 range (U+0080–U+009F) is defanged in *both* encodings —
/// as a raw byte (invalid UTF-8) and as its valid two-byte form — because an
/// 8-bit-CSI terminal interprets either arrival as an escape introducer. Any
/// other invalid UTF-8 defangs one byte at a time (resync). A valid multi-byte
/// sequence outside the C1 codepoints passes through whole, which is what
/// keeps a continuation byte that merely *falls* in 0x80–0x9F (À is C3 80)
/// from being mangled — the classification is by codepoint, never by byte.
const DefangUnit = struct { len: usize, defang: bool };
fn defangUnit(s: []const u8, i: usize) DefangUnit {
    const ch = s[i];
    if (ch < 0x20 or ch == 0x7f) return .{ .len = 1, .defang = true };
    if (ch < 0x80) return .{ .len = 1, .defang = false };
    const len = std.unicode.utf8ByteSequenceLength(ch) catch return .{ .len = 1, .defang = true };
    if (i + len > s.len or !std.unicode.utf8ValidateSlice(s[i..][0..len]))
        return .{ .len = 1, .defang = true };
    const cp = std.unicode.utf8Decode(s[i..][0..len]) catch return .{ .len = 1, .defang = true };
    if (cp >= 0x80 and cp <= 0x9f) return .{ .len = len, .defang = true };
    return .{ .len = len, .defang = false };
}

/// Target-chosen file names go into the text report verbatim, and a Unix file name may
/// contain newlines and control bytes — enough to forge whole report lines. The JSON
/// side is escaped in `jsonString`; this is the text side's equivalent, first built
/// for the l0 note and since #26's fix also the FAIL block's route (via `textShown`
/// below — the v0.1-era exposure there is closed by the same predicate). One `?` per
/// defanged unit — never more bytes out than in, so a hostile name cannot bloat the
/// report past its output buffer (a two-byte encoded C1 shrinks to one `?`).
fn appendSanitized(names: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}!void {
    var i: usize = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) try names.append(arena, '?') else try names.appendSlice(arena, s[i..][0..u.len]);
        i += u.len;
    }
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
fn refuseUnsupportedEntry(arena: std.mem.Allocator, snap: engine.Snapshot, phase: []const u8) void {
    if (engine.firstUnsupportedEntry(snap)) |rel| {
        const detail = std.fmt.allocPrint(
            arena,
            "the state directory holds an entry that is neither a regular file, a directory nor a symlink ({s}: {s}) — restore cannot recreate it, so every explored world would run against a tree the recording run never had",
            .{ phase, textShown(arena, rel) },
        ) catch "the state directory holds an entry that restore cannot recreate (a FIFO, socket or device)";
        unknown(.unsupported_state_entry, detail);
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
fn reconcileOrRefuse(
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
    const diffs = gpa.alloc(engine.Difference, cap) catch setupError("out of memory");
    defer gpa.free(diffs);
    const dc = engine.diffSnapshots(initial, final, diffs);
    if (dc.equal()) return;

    const found = gpa.alloc(engine.Unaccounted, dc.stored + 1) catch setupError("out of memory");
    defer gpa.free(found);

    // The tree's own symlinks, from the snapshots rather than from the filesystem. The
    // shim normalises path arguments lexically, so an operation on `cur/f` under
    // `cur -> v1` is recorded as `cur/f` while the difference sits at `v1/f`; joining the
    // two spellings without this turned a fully observed run into a refusal (measured:
    // one unlink through an interior symlink, PASS on the shipped 1.0.0, UNKNOWN here).
    // Reading the live tree instead would answer about the tree after the run, not the
    // one the operation crossed.
    var links: std.ArrayList(engine.Link) = .empty;
    engine.collectLinks(arena, initial, final, &links) catch setupError("out of memory");
    const scratch = gpa.alloc(u8, 2 * contract.max_path) catch setupError("out of memory");
    defer gpa.free(scratch);

    const r = engine.reconcile(diffs[0..dc.stored], ops, links.items, root, alt, scratch, found);

    // Disclosed on every run that has one, not only on the refusals: a reader deciding
    // what a PASS covers needs to know a subtree went unexamined. Twice, on purpose — the
    // number is the machine's copy and cannot be lost to an allocation failure, and the
    // sentence rides `l0_note`, the line that already says what the judgement covered.
    attributed_to_rename = r.by_rename_prefix;
    if (r.by_rename_prefix > 0)
        l0_note = std.fmt.allocPrint(
            arena,
            "{s}; {d} path(s) attributed to a directory a recorded rename moved in from outside the judged root, and not individually accounted for — that source subtree was never snapshotted, so what arrived with the move and what an unrecorded writer added afterwards cannot be told apart",
            .{ l0_note, r.by_rename_prefix },
        ) catch l0_note;

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
        "the judged state changed at {d} path(s) that no recorded operation names, so the account of this run is incomplete: {s}{s}. The shim records what crosses libc; a raw syscall, or a process that never loaded it, leaves no record at all",
        .{ r.total, names.items, more },
    ) catch "the judged state changed at a path that no recorded operation names";
    unknown(.state_changed_unaccounted, detail);
}

/// The `no_shim_marker` detail line, built from what was observed rather than from a
/// list of things that might have been true.
///
/// The old line named four candidate causes and the engine had looked at none of them.
/// A user who checked all of them honestly — #391 did, against an Apple-signed git —
/// found every one false and was left with nothing to do next, because the mechanism
/// that applied was a fifth the message never mentioned. README opens the limits
/// section with "Sideeye refuses to guess", which is the sentence this rebuilds toward.
///
/// Three rules hold the line, and each of them is a thing this function does NOT say:
///
///   - **The observation comes first, and it is small.** The marker's absence is all
///     this detector proves. It is not even proof that injection was refused: a trace
///     that could not be read collapses to an empty `TraceInfo` and arrives here too
///     (`engine.zig` says so at three call sites). So the first clause reports the
///     absence, and when nothing was found on the image the line says the cause lies
///     elsewhere instead of falling back to the old guesses.
///   - **Fields, not blame.** "carries the library-validation flag" — never "library
///     validation refused the insertion". The bit can be lifted by entitlement and a
///     non-zero platform byte is not Apple's full definition of a platform binary.
///   - **No time, no identity.** When the second reading disagrees with the first the
///     line says the two readings disagree. It does not say the file was replaced
///     *after* the run: a swap before the spawn produces the same disagreement, and
///     nothing here can tell them apart.
///
/// The path is target-derived and goes through `textShown`, like every other
/// target-controlled string that reaches the text report.
fn noShimDetail(arena: std.mem.Allocator) []const u8 {
    const opening = "the trace carries no shim marker";
    const obs = rec_image orelse return arena.dupe(u8, opening ++
        "; the operation's image was not examined") catch opening;

    const path = obs.path orelse return arena.dupe(u8, opening ++
        "; the operation's first word names no path, so the OS resolved it through PATH and Sideeye did not") catch opening;
    const shown = textShown(arena, path);

    // "the two readings do not agree", and nothing further. Not "the content differs":
    // losing read permission after the run, or a transient failure, moves the answer
    // without moving a byte. Not "it was replaced after the run" either — a swap before
    // the spawn produces the same disagreement.
    const moved = !image.sameAnswer(obs, image.reobserve(arena, path));
    const drift = if (moved)
        " — and reading that path again now does not agree with the reading above, so the two observations are not of one thing"
    else
        "";

    const body: []const u8 = switch (obs.facts) {
        .not_resolved => "the OS resolved it through PATH and Sideeye did not",
        .unreadable => |u| switch (u) {
            .no_such_file => "nothing is there now",
            .permission_denied => "it cannot be opened for reading",
            .not_a_regular_file => "it is not a regular file",
            .read_failed => "it could not be read",
        },
        .unrecognised => "it is neither ELF nor Mach-O, so nothing was read from it",
        .undecidable => |u| switch (u) {
            .slice_not_unique => "it is a universal binary and which slice this machine runs is not decided here, so nothing was read from it",
            .code_directories_disagree => "its signature carries code directories that disagree, so nothing was read from it",
            .structure_out_of_range => "its structure runs outside the file, so nothing was read from it",
        },
        .elf => |e| if (e.has_interp)
            "it names an interpreter, so it is dynamically linked and the marker's absence has another cause"
        else
            "it names no interpreter, so it is statically linked and no preloaded library can reach it",
        .macho => |m| blk: {
            const s = m.signing orelse break :blk if (m.dyldlink)
                "it is dynamically linked and carries no code signature"
            else
                "it carries no code signature and is not linked against dyld";
            if (s.platformNamed())
                break :blk "its code directory names a platform, the marker an Apple-shipped binary carries";
            if (s.libraryValidation())
                break :blk "its code directory carries the library-validation flag, which admits only libraries signed by the same team";
            if (s.hardenedRuntime())
                break :blk "its code directory carries the hardened-runtime flag";
            break :blk "its code directory carries no flag this build looks for and names no platform, so the marker's absence has another cause";
        },
    };

    // "before the run started", not "as it started". The reading is taken ahead of the
    // spawn and nothing pins it to the instant of exec; the honest upper bound on what
    // the observation supports is that it happened first.
    return std.fmt.allocPrint(arena, "{s}; read before the run started, on {s}: {s}{s}", .{
        opening, shown, body, drift,
    }) catch opening;
}

/// The second observed run's version, and deliberately a different line.
///
/// The first run's marker is a counterexample to every signing or linkage story about
/// this file: the shim did initialise from it, minutes ago. Repeating those fields here
/// would be reporting facts that the run itself has already answered — so the only
/// observation worth making is whether the path still reads the same as it did before
/// the first run, and even that is stated as a disagreement between two readings rather
/// than as a replacement with a time on it.
fn noShimDetailSecondRun(arena: std.mem.Allocator) []const u8 {
    const opening = "the second observed run carries no shim marker, although the first one did";
    const obs = rec_image orelse return opening;
    const path = obs.path orelse return opening;

    if (image.sameAnswer(obs, image.reobserve(arena, path))) return opening;
    return std.fmt.allocPrint(
        arena,
        "{s}; reading {s} again now does not agree with the reading taken before the first run, so the two observations are not of one thing",
        .{ opening, textShown(arena, path) },
    ) catch opening;
}

fn textShown(arena: std.mem.Allocator, s: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    appendSanitized(&out, arena, s) catch return "(allocation failed)";
    return out.items;
}

/// The `not tested` list is not constant: whenever any file was judged by the history
/// form, its appended tail joined the untested set, and a PASS headline must not
/// stand without that narrowing beside it.
fn notTestedText() []const u8 {
    const history = l0_history_count > 0;
    if (history and l1_configured)
        return "power loss, torn writes, concurrent processes, appended tails (files under the history form), post-only file contents (L1 checks existence only; post-only link targets are judged)";
    if (history)
        return "power loss, torn writes, concurrent processes, appended tails (files under the history form)";
    if (l1_configured)
        return "power loss, torn writes, concurrent processes, post-only file contents (L1 checks existence only; post-only link targets are judged)";
    return "power loss, torn writes, concurrent processes";
}

fn notTestedJson() []const u8 {
    const history = l0_history_count > 0;
    if (history and l1_configured)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]";
    if (history)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\"]";
    if (l1_configured)
        return "[\"power loss\", \"torn writes\", \"concurrent processes\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]";
    return "[\"power loss\", \"torn writes\", \"concurrent processes\"]";
}

/// One bounded observation of a stdout capture: how many bytes it held when opened, a
/// Blake3 digest of exactly those bytes, and whether `needle` appears among them — read
/// in chunks with an overlap so a marker straddling a chunk boundary is still found,
/// without holding a chatty target's whole stdout in memory across a few hundred worlds.
///
/// The scan and the fingerprint deliberately come from one read of the same bytes: two
/// observations of the capture disagreeing is the quiescence refusal (#46), and a marker
/// verdict taken from different bytes than the fingerprint would let the two claims
/// drift. The read is bounded by the size measured at open — a still-live writer must
/// not be able to keep the observer chasing EOF — so growth surfaces as the *next*
/// observation's differing fingerprint, never as a hang. The digest is Blake3 rather
/// than a cheap mix because the bytes are target-chosen: a same-length rewrite must not
/// be able to keep the fingerprint. An unreadable capture is an error, never "absent":
/// absence decides whether L1 applies to a world, and an I/O failure silently read as
/// absence would skip the invariant on the PASS side.
const CaptureObservation = struct {
    /// The size `lseek` measured when the file was opened.
    measured: u64,
    /// The bytes actually read and digested. Less than `measured` only when the file
    /// shrank underneath the read — on a regular file that is direct evidence of a
    /// concurrent writer, which is why `sawTruncation` exists as its own predicate
    /// instead of hoping the next fingerprint happens to differ (R1: a truncate-to-b
    /// during sample one and an honest size-b sample two would otherwise compare equal).
    bytes: u64,
    digest: [std.crypto.hash.Blake3.digest_length]u8,
    marker_seen: bool,

    /// Fingerprint equality only — `marker_seen` depends on which needle was asked for.
    fn fingerprintEql(a: CaptureObservation, b: CaptureObservation) bool {
        return a.measured == b.measured and a.bytes == b.bytes and std.mem.eql(u8, &a.digest, &b.digest);
    }

    /// The file changed while this very sample was being read.
    fn sawTruncation(a: CaptureObservation) bool {
        return a.bytes < a.measured;
    }
};

fn observeCapture(path: []const u8, needle: ?[]const u8) error{Unreadable}!CaptureObservation {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return error.Unreadable;
    const fd = posix.open(z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    if (fd < 0) return error.Unreadable;
    defer _ = posix.close(fd);
    // Same reasoning as `readFileFrom`: the `lseek` refuses a FIFO today, but what this
    // path needs is that the capture is an ordinary file, which is a different sentence
    // (#400).
    if ((posix.kindOfFd(fd) catch return error.Unreadable) != .file) return error.Unreadable;
    const end = posix.lseek(fd, 0, posix.SEEK_END);
    if (end < 0) return error.Unreadable;
    if (posix.lseek(fd, 0, posix.SEEK_SET) != 0) return error.Unreadable;
    const bound: u64 = @intCast(end);

    var buf: [64 * 1024]u8 = undefined;
    const nlen: usize = if (needle) |n| n.len else 0;
    if (nlen >= buf.len) return error.Unreadable;
    var hasher = std.crypto.hash.Blake3.init(.{});
    var seen = false;
    var kept: usize = 0;
    var total: u64 = 0;
    while (total < bound) {
        const room: u64 = @intCast(buf.len - kept);
        const want: usize = @intCast(@min(room, bound - total));
        const nr = posix.read(fd, buf[kept..].ptr, want);
        if (nr < 0) {
            if (std.c._errno().* == posix.EINTR) continue;
            return error.Unreadable;
        }
        // EOF before the measured size: the file shrank underneath us. `bytes` ends up
        // below `measured`, which `sawTruncation` reports as a change observed inside
        // this very sample — never left to the next comparison to maybe notice.
        if (nr == 0) break;
        const fresh: usize = @intCast(nr);
        hasher.update(buf[kept .. kept + fresh]);
        total += fresh;
        const have = kept + fresh;
        if (needle) |n| {
            if (n.len > 0 and std.mem.indexOf(u8, buf[0..have], n) != null) seen = true;
        }
        kept = if (nlen == 0) 0 else @min(nlen - 1, have);
        std.mem.copyForwards(u8, buf[0..kept], buf[have - kept .. have]);
    }
    var out: CaptureObservation = .{ .measured = bound, .bytes = total, .digest = undefined, .marker_seen = seen };
    hasher.final(&out.digest);
    return out;
}

test "the readers ask what the descriptor is before reading it, at every call site (#400)" {
    // A FIFO **with a live writer and bytes already in it**. That shape is chosen so the
    // test measures the classification without reaching through the hang it guards: with
    // a writer present the open returns whether or not `O_NONBLOCK` is passed, so
    // removing the flag leaves this test fast rather than hanging a CI runner for six
    // hours. Removing the *classification* is what turns it red — the read would then
    // succeed and hand back the writer's bytes, which is the "could not be read becomes
    // was empty" defect in its readable form.
    //
    // The flag's own wiring cannot be tested here for the same reason: it only shows
    // itself when there is no writer, and that is the hang. `spike/case-path-deadline.py`
    // measures it from outside the process, at the one call site the CLI reaches.
    var bb: [128]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-fifo400-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base.ptr, @as(c_uint, 0o755));
    var fb: [160]u8 = undefined;
    const fifo_z = std.fmt.bufPrintZ(&fb, "{s}/pipe", .{base}) catch unreachable;
    _ = posix.unlink(fifo_z.ptr);
    try std.testing.expect(posix.mkfifo(fifo_z.ptr, @as(c_uint, 0o644)) == 0);

    // Reader first: the write end of a FIFO with no reader fails ENXIO.
    const rfd = posix.open(fifo_z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    try std.testing.expect(rfd >= 0);
    defer _ = posix.close(rfd);
    const wfd = posix.open(fifo_z.ptr, posix.O_WRONLY, @as(c_uint, 0));
    try std.testing.expect(wfd >= 0);
    defer _ = posix.close(wfd);
    const payload = "{\"schema\":\"sideeye/case\"}\n";
    try std.testing.expect(posix.write(wfd, payload.ptr, payload.len) == @as(isize, @intCast(payload.len)));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fifo_path = std.mem.span(@as([*:0]const u8, fifo_z.ptr));

    // **This first assertion does not measure the classification, and saying so is the
    // point.** `readFileAllocCapped` reads in a loop and returns one bit, so a
    // non-regular descriptor, an unreadable one and a file over the cap all arrive as
    // `null`: with the guard deleted the FIFO's payload is read and then the next read
    // fails EAGAIN, which is `null` again. Measured — that mutation survives this line.
    // What kills it is `spike/case-path-deadline.py`, from outside the process, where
    // the refusal *message* separates "could not be read" from "could not be parsed".
    // The line stays because it pins the behaviour; it is not evidence of wiring.
    try std.testing.expect(readFileAllocCapped(arena, fifo_path, 1024 * 1024, .{ .require_regular = true }) == null);
    try std.testing.expect(readFileFrom(arena, fifo_path, 0, 64 * 1024) == null);
    try std.testing.expectError(error.Unreadable, observeCapture(fifo_path, null));

    // `/dev/zero`, which is the input that separates this guard from the `lseek` that
    // happens to sit next to it. Measured: it is `S_IFCHR`, both `lseek`s **succeed**
    // (returning 0) and `read` returns bytes — so every reader whose refusal rests on a
    // failed seek accepts it. `readFileFrom` would answer an empty `Appended` rather
    // than null, and `observeCapture` a zero-length observation rather than an error.
    // Deleting either classification with only the FIFO above in the test leaves both
    // green, which is how these two call sites were left unguarded on the first attempt.
    const devzero = "/dev/zero";
    // First, that the device is there and answers what this test assumes. `null` and
    // `error.Unreadable` are also the answers to a failed open, so on a host without
    // `/dev/zero` the two assertions below would pass while measuring nothing at all.
    var dzb: [16]u8 = undefined;
    const dz_z = std.fmt.bufPrintZ(&dzb, "{s}", .{devzero}) catch unreachable;
    const dzfd = posix.open(dz_z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    try std.testing.expect(dzfd >= 0);
    try std.testing.expectEqual(posix.Kind.other, try posix.kindOfFd(dzfd));
    _ = posix.close(dzfd);

    try std.testing.expect(readFileFrom(arena, devzero, 0, 64 * 1024) == null);
    try std.testing.expectError(error.Unreadable, observeCapture(devzero, null));

    // The control, with the same bytes in an ordinary file. Without it, readers that
    // refused everything — a `kindOfFd` stuck on `.other`, or a classification inverted
    // — would satisfy every assertion above.
    var rb: [160]u8 = undefined;
    const reg_z = std.fmt.bufPrintZ(&rb, "{s}/f", .{base}) catch unreachable;
    const ofd = posix.open(reg_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(ofd >= 0);
    try std.testing.expect(posix.write(ofd, payload.ptr, payload.len) == @as(isize, @intCast(payload.len)));
    _ = posix.close(ofd);
    const reg_path = std.mem.span(@as([*:0]const u8, reg_z.ptr));

    try std.testing.expect(readFileAllocCapped(arena, reg_path, 1024 * 1024, .{ .require_regular = true }) != null);
    try std.testing.expect(readFileFrom(arena, reg_path, 0, 64 * 1024) != null);
    _ = try observeCapture(reg_path, null);

    // And the case read still accepts an ordinary file when it is not asked to classify,
    // which is the half `--config` depends on.
    try std.testing.expect(readFileAllocCapped(arena, reg_path, 1024 * 1024, .{}) != null);

    _ = posix.unlink(fifo_z.ptr);
    _ = posix.unlink(reg_z.ptr);
    _ = posix.rmdir(base.ptr);
}

test "observeCapture finds a straddling marker and fingerprints the same bytes" {
    // posix directly, like the engine itself: the std file API wants an `Io` instance
    // threaded through every call, and this test needs one file, not a runtime.
    // pid-unique name: `zig build test` runs this file in several concurrent binaries,
    // and a fixed shared path passes alone then flakes under pairing (#28).
    var pb: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-observecapture-{d}.txt", .{posix.getpid()}) catch unreachable;
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

    const with = try observeCapture(path, "MARKER");
    try std.testing.expect(with.marker_seen);
    try std.testing.expectEqual(@as(u64, 64 * 1024 + 3), with.bytes);
    const without = try observeCapture(path, "ABSENT");
    try std.testing.expect(!without.marker_seen);
    // The fingerprint is a property of the bytes, not of the needle asked about.
    try std.testing.expect(with.fingerprintEql(without));
    const unasked = try observeCapture(path, null);
    try std.testing.expect(with.fingerprintEql(unasked));

    // One appended byte moves the fingerprint.
    const afd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT, @as(c_uint, 0o644));
    try std.testing.expect(afd >= 0);
    try std.testing.expect(posix.lseek(afd, 0, posix.SEEK_END) >= 0);
    try std.testing.expect(posix.write(afd, "y", 1) == 1);
    _ = posix.close(afd);
    const grown = try observeCapture(path, null);
    try std.testing.expect(!with.fingerprintEql(grown));

    try std.testing.expectError(error.Unreadable, observeCapture(".zig-cache/no-such-capture", "X"));
}

test "observeCapture separates same-length rewrites by digest alone" {
    var pb: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-observecapture-rw-{d}.txt", .{posix.getpid()}) catch unreachable;
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch unreachable;
    defer removeFile(path);

    for ([_][]const u8{ "AAAA", "AAAB" }, 0..) |content, i| {
        const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(fd >= 0);
        try std.testing.expect(posix.write(fd, content.ptr, content.len) == @as(isize, @intCast(content.len)));
        _ = posix.close(fd);
        if (i == 0) continue;
        const b = try observeCapture(path, null);
        const afd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(afd >= 0);
        try std.testing.expect(posix.write(afd, "AAAA", 4) == 4);
        _ = posix.close(afd);
        const a = try observeCapture(path, null);
        try std.testing.expectEqual(a.bytes, b.bytes);
        try std.testing.expect(!a.fingerprintEql(b));
    }

    // An empty capture observes cleanly: zero bytes, nothing seen, no truncation.
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    const empty = try observeCapture(path, "M");
    try std.testing.expectEqual(@as(u64, 0), empty.bytes);
    try std.testing.expectEqual(@as(u64, 0), empty.measured);
    try std.testing.expect(!empty.marker_seen);
    try std.testing.expect(!empty.sawTruncation());
}

test "a shrink observed inside one sample is its own evidence, not the next comparison's luck" {
    // The racy schedule itself (truncate between lseek and read) cannot be staged
    // deterministically, so the predicate is pinned on the recorded shape: a sample
    // whose read ended below its measured size. The hazard (R1): truncate-to-b during
    // sample one, then an honest size-b sample two — identical bytes, identical digest,
    // equal fingerprints if `measured` were not part of the comparison.
    const digest = [_]u8{7} ** std.crypto.hash.Blake3.digest_length;
    const during = CaptureObservation{ .measured = 10, .bytes = 4, .digest = digest, .marker_seen = false };
    const honest = CaptureObservation{ .measured = 4, .bytes = 4, .digest = digest, .marker_seen = false };
    try std.testing.expect(during.sawTruncation());
    try std.testing.expect(!honest.sawTruncation());
    try std.testing.expect(!during.fingerprintEql(honest));
}

/// What the caller wants of the read, beyond the byte ceiling.
///
/// A struct rather than two positional booleans: `(…, true, false)` and `(…, false,
/// true)` are both well-typed and mean opposite things, Zig has no named arguments, and
/// this codebase already carries an incident about an argument arriving silently in the
/// wrong place (`open`'s variadic `mode`, wrong on one architecture and plausible on the
/// other).
const ReadMode = struct {
    /// Refuse a descriptor that is not a regular file, before reading a byte (#400).
    require_regular: bool = false,
    /// Bound the read in wall-clock time as well as in bytes: keep asking while a peer
    /// might still arrive, and refuse at the deadline rather than waiting forever.
    bounded: bool = false,
};

/// `readFileAlloc` with a ceiling: a caller-named file is input, and reading until EOF
/// from something that never ends (a device, a fifo) would hang the run before any
/// refusal could fire. Over the cap answers like unreadable.
///
/// **That sentence was written for a hazard the cap cannot reach, which is #400.** A
/// FIFO does not hang the read the cap guards — it hangs the `open` in front of it, and
/// the loop is never entered to be capped. So the open takes `O_NONBLOCK` where either
/// mode asks for it. That alone then buys a second defect: past the open, a FIFO with no
/// writer returns 0 from the first read, so the file arrives *empty* and successful.
/// Measured on macOS against a real FIFO: `open` ok, `fstat` S_IFIFO, `lseek` ESPIPE,
/// `read` n=0 with errno untouched.
///
/// The two `ReadMode` halves are the caller's to choose, because the callers differ in
/// who names the path and in what may be refused.
///
/// **`require_regular`** is the case read's. A case file is named by whoever runs
/// `replay`, and it is an ordinary file or it is not a case file — so a descriptor that
/// is anything else is refused before a byte is read.
///
/// **`bounded`** is `--config`'s, and it exists because that path cannot take the other
/// half. `--config` is operator-named and may legitimately be a pipe (`--config
/// /dev/stdin`, a process substitution), so refusing by kind would break spellings that
/// work today. What it can do is refuse to wait forever: keep asking while a peer might
/// still arrive, and stop at a deadline. Three inputs made that necessary, and each one
/// used to be a run with no exit code — a FIFO with no writer (the open), a pipe whose
/// writer opened and sent nothing (the read), and `/dev/zero` (a read that never ends).
///
/// **What `bounded` costs.** The deadline is absolute, not idle-based: a producer slower
/// than it, or a config that streams across it, is refused with the partial read
/// discarded. And a pipe whose writer opened, wrote nothing and closed is indisputably
/// *empty*, but reads exactly like one whose writer has not arrived — POSIX offers no
/// way to tell them apart — so it waits out the deadline and is reported unreadable
/// rather than empty. Both are measured and disclosed in the CHANGELOG.
///
/// The two captures ask for neither. They are written by this process or its child
/// inside the work directory: demanding regularity would refuse nothing that happens,
/// and a deadline would bound something the run already bounds.
fn readFileAllocCapped(
    arena: std.mem.Allocator,
    path: []const u8,
    cap: usize,
    mode: ReadMode,
) ?[]const u8 {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    // Both modes need the open to return, for different reasons: classification has to
    // get a descriptor before it can ask what it is, and the bounded read needs `EAGAIN`
    // where a blocking read would sit somewhere the deadline cannot see. Plain readers
    // keep the blocking open they had — the flag is not free, and a non-blocking read of
    // a pipe whose writer has not written yet fails where waiting would have succeeded.
    const flags: c_int = if (mode.require_regular or mode.bounded)
        posix.O_RDONLY | posix.O_NONBLOCK
    else
        posix.O_RDONLY;
    const fd = posix.open(z.ptr, flags, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    if (mode.require_regular) {
        // Asked of the descriptor rather than of the name. A name classified before the
        // open can change kind before the read, and the probe that classified names by
        // opening them is what #5 retired — for hanging on exactly this input.
        const kind = posix.kindOfFd(fd) catch return null;
        if (kind != .file) return null;
    }
    // Asked once. The answer cannot change for an open descriptor, and asking per read
    // would cost an fstat on every empty pass — around eighty of them in the measured
    // late-writer case.
    const peer_may_arrive = mode.bounded and posix.isFifoFd(fd);
    const deadline_at: u64 = if (mode.bounded) posix.monotonicMs() + config_read_deadline_ms else 0;

    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    var eintr_left: u32 = 8;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n > 0) {
            list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
            if (list.items.len > cap) return null;
            continue;
        }

        // Everything past here is a pass that produced no bytes, and the deadline is
        // consulted **only** here. A 300 KiB regular file finishes in six reads without
        // touching this branch, so a slow disk cannot spend the budget — which is the
        // false positive that made an earlier draft reject a time bound outright.
        if (n == 0) {
            // End of file — unless a peer might still show up. A FIFO with no writer
            // answers 0 exactly as an empty regular file does, and the only difference
            // is whether waiting could change the answer. `/dev/null` is not a FIFO, so
            // it takes this break and stays as fast as it is today.
            if (!peer_may_arrive or list.items.len != 0) break;
        } else {
            const e = std.c._errno().*;
            if (e == posix.EINTR) {
                // The repo's shape for this: an EINTR-only bounded retry, counted by the
                // loop rather than by hand (`posix.zig`'s wait). It applies to every
                // mode, and it is the plain readers — the ones without the flag, whose
                // read *does* block — that can actually reach it; for them this changes
                // a first-interruption `null` into eight retries. Unreachable in
                // practice on all of them today (no handler is installed anywhere), and
                // folding an interruption into "unreadable" would be a wrong answer
                // rather than a slow one.
                if (eintr_left == 0) return null;
                eintr_left -= 1;
                continue;
            }
            if (!(mode.bounded and e == posix.EAGAIN)) return null;
        }

        // Only `bounded` reaches here: the `n == 0` arm above needs `peer_may_arrive`
        // and the `n < 0` arm needs `mode.bounded` explicitly. Reading the clock
        // unconditionally rather than re-testing the mode keeps that from reading as a
        // case someone still has to think about.
        if (posix.monotonicMs() >= deadline_at) return null;
        posix.sleepForMs(config_read_poll_ms);
    }
    return list.items;
}

fn readFileAlloc(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    // A read error is not end of file (the shared loop returns null for it): treating
    // them alike once turned a truncated oracle file into a complete one, and the
    // comparison that followed was against however much happened to arrive.
    return readFileAllocCapped(arena, path, std.math.maxInt(usize), .{});
}

/// A define command as a bare JSON value, mirroring `config.Command.jsonParse`:
/// the string form is one JSON string, the argv form one array of strings. The two
/// functions are the write and read halves of the same shape — a case written here
/// parses back through there.
fn jsonCommand(w: *std.ArrayList(u8), arena: std.mem.Allocator, cmd: config.Command) !void {
    switch (cmd) {
        .str => |s| try jsonString(w, arena, s),
        .argv => |a| {
            try w.append(arena, '[');
            for (a, 0..) |e, i| {
                if (i != 0) try w.appendSlice(arena, ", ");
                try jsonString(w, arena, e);
            }
            try w.append(arena, ']');
        },
    }
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

fn violationPath(v: engine.Violation) []const u8 {
    return switch (v) {
        .missing => |p| p,
        .hybrid => |p| p,
        .rewritten => |p| p,
        .not_durable => |p| p,
    };
}

fn violationObserved(v: ?engine.Violation) []const u8 {
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
const CheckerEarliest = struct {
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
    // The contractual spelling of "did a second witness check this?" (#94). A caller
    // gates on `verdict == "PASS" && oracle_verified`, never on the prose `oracle` string.
    try w.appendSlice(arena, ",\n  \"oracle_verified\": ");
    try w.appendSlice(arena, if (oracle_verified) "true" else "false");
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
    try jsonString(w, arena, boundaryAccount());
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
fn writeJsonReport(
    arena: std.mem.Allocator,
    path: []const u8,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    checker_detail: ?CheckerEarliest,
    unknown_reason: ?[]const u8,
    message: ?[]const u8,
) void {
    const doc = buildJson(arena, verdict, exit_code, detail, checker_detail, unknown_reason, message) catch
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

/// The destructive root stopped being the directory this run resolved.
///
/// Two decisions live here, deliberately in one pure function so they cannot drift.
///
/// **The error decides the wording.** Every `restore`/`freshDir`/`corruptState` call
/// site folds its errors into one message, which used to swallow the one error that
/// says something different: `UnsafeRoot` from `assertRootResolvesToItself` means the
/// state directory was replaced between the resolution and the destructive step, not
/// that the step failed. That is an actionable difference — a setup command or the
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
const RewriteDisposition = struct { exit: enum { setup, unknown }, detail: []const u8 };

fn rewriteFailureDisposition(
    phase: SpawnPhase,
    e: engine.RestoreError,
    doing: []const u8,
) RewriteDisposition {
    const detail: []const u8 = switch (e) {
        // Three causes, not two: #327 added the third by moving a non-directory at the
        // root from DeleteFailed to UnsafeRoot, which is the right class — the root is
        // not a thing to rewrite — but the old wording named only a swap, and a refusal
        // that states the wrong cause is worse than one that states none. "Destructive
        // access", not "empty": the same refusal now serves the falsification probe's
        // corruption (#363), which overwrites rather than empties.
        error.UnsafeRoot => "the state directory could not be confirmed as the one this run resolved: it now resolves elsewhere (a symlink or a moved parent), it is not a directory, or it could not be read at all. Refusing destructive access to it",
        error.DeleteFailed, error.CreateFailed, error.PathTooLong => doing,
    };
    return .{
        .exit = switch (phase) {
            .before_exploration => .setup,
            .exploring => .unknown,
        },
        .detail = detail,
    };
}

fn restoreFailure(e: engine.RestoreError, doing: []const u8) noreturn {
    const d = rewriteFailureDisposition(run_phase, e, doing);
    switch (d.exit) {
        .setup => setupError(d.detail),
        .unknown => unknown(.state_rewrite_failed, d.detail),
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
        }
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

/// The Command-shaped face of the same rule. The string form goes through
/// `resolveCommandAgainst` unchanged. The argv form resolves element 0 only, under
/// the names-a-place test — minus the string form's leading-space skip, on purpose:
/// that skip mirrors how the space-split executor finds argv[0], and the argv form
/// has no split — its bytes are verbatim, so an element 0 with a leading space is
/// the author's own byte string, passed through untouched (and failing loudly at
/// exec). The remaining elements are arguments — data, never paths to rewrite.
fn resolveCommand(arena: std.mem.Allocator, dir: []const u8, cmd: config.Command) config.Command {
    switch (cmd) {
        .str => |s| return .{ .str = resolveCommandAgainst(arena, dir, s) },
        .argv => |a| {
            // The parser refuses empty arrays; this guard is for any future route
            // that reaches here without it — pass through, and let the spawn site's
            // own emptiness refusal speak.
            if (a.len == 0) return .{ .argv = a };
            const head = a[0];
            if (head.len == 0 or head[0] == '/' or head[0] == ' ' or std.mem.indexOfScalar(u8, head, '/') == null)
                return .{ .argv = a };
            const out = arena.alloc([]const u8, a.len) catch setupError("out of memory");
            out[0] = std.fmt.allocPrint(arena, "{s}/{s}", .{ dir, head }) catch setupError("out of memory");
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
    // argv[0] is found the way the executor finds it: leading spaces must not let a
    // place-naming command slip past resolution and run cwd-relative.
    try std.testing.expectEqualStrings("/cfg/./check.sh", resolveCommandAgainst(a, "/cfg", " ./check.sh"));
    // The argv arm: element 0 only, same names-a-place test, tail untouched — and
    // verbatim means verbatim: a leading space disqualifies resolution instead of
    // being skipped, because nothing here splits or trims (ADR 0019).
    const rel = resolveCommand(a, "/cfg", .{ .argv = &.{ "./check.sh", "--strict", "a b" } });
    try std.testing.expectEqualStrings("/cfg/./check.sh", rel.argv[0]);
    try std.testing.expectEqualStrings("--strict", rel.argv[1]);
    try std.testing.expectEqualStrings("a b", rel.argv[2]);
    const bare = resolveCommand(a, "/cfg", .{ .argv = &.{ "mytool", "x/y" } });
    try std.testing.expectEqualStrings("mytool", bare.argv[0]);
    try std.testing.expectEqualStrings("x/y", bare.argv[1]);
    const abs = resolveCommand(a, "/cfg", .{ .argv = &.{"/usr/bin/tool"} });
    try std.testing.expectEqualStrings("/usr/bin/tool", abs.argv[0]);
    const spaced = resolveCommand(a, "/cfg", .{ .argv = &.{" ./check.sh"} });
    try std.testing.expectEqualStrings(" ./check.sh", spaced.argv[0]);
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
    // The version and the shape travel together (ADR 0019, the ADR 0014 law): a case
    // whose define carries the argv form is version 3; one spelled entirely in
    // strings stays version 2, byte-shaped exactly as every v2-era reader expects.
    const carries_argv = (args.operation.? == .argv) or
        (args.setup != null and args.setup.? == .argv) or
        (args.check != null and args.check.? == .argv);
    // A declared cwd is part of what the counterexample was found against, so it moves
    // the version the same way — and it takes precedence over the argv rule because a
    // version-3 reader would drop the field and replay the commands somewhere else.
    const case_version: u32 = if (args.cwd != null) 4 else if (carries_argv) 3 else 2;
    w.appendSlice(arena, "{\n  \"schema\": \"sideeye/case\",\n  \"case_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{case_version}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"sideeye_version\": ") catch return null;
    jsonString(w, arena, version) catch return null;
    w.appendSlice(arena, ",\n  \"contract_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"define\": {\n    \"state\": ") catch return null;
    jsonString(w, arena, args.state.?) catch return null;
    if (args.setup) |s| {
        w.appendSlice(arena, ",\n    \"setup\": ") catch return null;
        jsonCommand(w, arena, s) catch return null;
    }
    w.appendSlice(arena, ",\n    \"operation\": ") catch return null;
    jsonCommand(w, arena, args.operation.?) catch return null;
    if (args.check) |c| {
        w.appendSlice(arena, ",\n    \"check\": ") catch return null;
        jsonCommand(w, arena, c) catch return null;
    }
    if (args.marker) |m| {
        w.appendSlice(arena, ",\n    \"marker\": ") catch return null;
        jsonString(w, arena, m) catch return null;
    }
    // Written only when it was declared, unlike `expected_status` above: an absent cwd
    // is not a default value the reader has to be told, it is the engine's own cwd — and
    // writing it anyway would push every case to version 4 and make every v2 and v3
    // reader refuse files whose defines are unchanged.
    if (args.cwd) |c| {
        w.appendSlice(arena, ",\n    \"cwd\": ") catch return null;
        jsonString(w, arena, c) catch return null;
    }
    // Written even at the default (case_version 2): a case is a frozen contract, and
    // "0 because nothing was declared" and "0 by declaration" must replay identically
    // years later without consulting anything outside the file.
    w.appendSlice(arena, ",\n    \"expected_status\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{args.expect_status orelse 0}) catch return null) catch return null;
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

/// Replace each defanged unit (see `defangUnit`: C0/DEL, C1 in either encoding,
/// invalid UTF-8) with a visible `\xNN` spelling per byte. The JSON side escapes
/// controls already; the text side printed them raw, which let target-chosen
/// names inject report lines. Everything else passes through untouched.
fn sanitizeForReport(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var clean = true;
    var i: usize = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) {
            clean = false;
            break;
        }
        i += u.len;
    }
    if (clean) return s;
    var out: std.ArrayList(u8) = .empty;
    i = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) {
            for (s[i..][0..u.len]) |ch| {
                var nb: [4]u8 = undefined;
                try out.appendSlice(arena, std.fmt.bufPrint(&nb, "\\x{x:0>2}", .{ch}) catch unreachable);
            }
        } else {
            try out.appendSlice(arena, s[i..][0..u.len]);
        }
        i += u.len;
    }
    return out.items;
}

test "the defang classifier covers raw C1, encoded C1 and invalid bytes, and spares real UTF-8 (#167)" {
    // À is C3 80 and € is E2 82 AC — continuation bytes that *fall* inside the
    // C1 range. A lazy byte-wise widening would mangle both; é (C3 A9) would
    // not catch that, its continuation byte lies outside 0x80–0x9F. 0xFF is
    // the invalid-but-not-C1 independent pin: raw 0x9B alone cannot tell
    // "defangs C1" from "defangs any invalid byte".
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The l0-note/FAIL route: one '?' per defanged unit.
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\x9bB")); // raw C1
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xc2\x9bB")); // encoded C1 (U+009B, CSI)
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xffB")); // invalid, not C1
    try std.testing.expectEqualStrings("ÀB€", textShown(arena, "ÀB€")); // real UTF-8 spared
    // The divergence route: same classification, visible \xNN spelling.
    try std.testing.expectEqualStrings("A\\x9bB", try sanitizeForReport(arena, "A\x9bB"));
    try std.testing.expectEqualStrings("A\\xc2\\x9bB", try sanitizeForReport(arena, "A\xc2\x9bB"));
    try std.testing.expectEqualStrings("A\\xffB", try sanitizeForReport(arena, "A\xffB"));
    try std.testing.expectEqualStrings("ÀB€", try sanitizeForReport(arena, "ÀB€"));
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

/// Two snapshots agree, on the same three fields `diffSnapshots` compares.
///
/// One implementation, not two. This was a length check plus a `find` per entry until
/// `--twice` (#199) needed the differences themselves rather than a yes/no, and keeping
/// both would leave two answers to one question free to drift — the shape #65 is about.
/// The merge is also cheaper: linear in the two lengths rather than a binary search per
/// entry, and it stops counting the moment a caller only wants `equal()`… which it does
/// not, so the buffer is one slot and the count runs to completion. Callers that need
/// the yes/no keep reading exactly that.
fn snapshotsEqual(a: engine.Snapshot, b: engine.Snapshot) bool {
    var one: [1]engine.Difference = undefined;
    return engine.diffSnapshots(a, b, &one).equal();
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

test "the shipped engine options carry the shipped values (#365)" {
    // What a released binary is built with. Until #365 the only machine holding these was
    // the sha comparison in CI between a build with `-Dtest-trace-cap` and one without —
    // and an edit to the literal in build.zig lands in BOTH arms of that comparison, so it
    // stays green. What the comparison covers is the FLAG leaking in, not the value.
    //
    // A loud edit is caught elsewhere: at 64 bytes every acceptance leg that drives the
    // SHIPPED binary refuses on a trace that size, and most of the suite does drive it —
    // not all, since four apparatus binaries are driven by their own names. A quiet one
    // is caught nowhere: 128 MiB passes acceptance (no toy trace comes near it), passes
    // the sha step, and ships an engine whose ceiling disagrees with engine.max_trace_bytes.
    // That quiet mutation is what these tests exist for, and it is the half that was
    // measured; the loud half is read off spike/acceptance.sh rather than run.
    try std.testing.expectEqual(@as(usize, 0), engine_build_options.trace_cap_override);
    try std.testing.expectEqual(@as(usize, 0), engine_build_options.trace_cap_override_world);
    try std.testing.expect(!engine_build_options.ancestor_probe);
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
}

test "no fourth engine build option arrives unchecked (#365)" {
    // The ratchet. Asserting three values says nothing about a FOURTH option arriving, and
    // the promise is universal: a `-Dtest-…` added later with no assertion above would
    // leave it false while CI stayed green. Pinning the count makes the next option fail
    // here until someone writes its line. Same instrument as the RestoreError arity pin
    // above and the OpClass enumeration in contract.zig.
    const decls = @typeInfo(engine_build_options).@"struct".decls;
    try std.testing.expectEqual(@as(usize, 3), decls.len);
}

/// The reachable boundary-evidence states, written out rather than generated as a
/// product of the fields: most of the product is unreachable (a witness that never ran
/// cannot have counted children, and `oracle_child_touched` needs one that read), and a
/// table of shapes the engine cannot produce measures the renderer against fiction. Each
/// row names the run that reaches it and pins a phrase, so a mutation that empties a
/// clause is caught rather than passing the entitlement bit.
const boundary_cases = [_]struct {
    what: []const u8,
    ev: BoundaryEvidence,
    /// Whether this state is entitled to say the words "single process" at all.
    may_say_single: bool,
    /// A phrase the rendered account must contain. One bit per state is not coverage:
    /// review found that a mutation blanking a clause passed a table that only asked
    /// whether "single process" appeared.
    pins: []const u8,
}{
    .{ .what = "refused before the trace was read (a wrong exit status, say)", .ev = .{}, .may_say_single = false, .pins = "refused before the shim's account" },
    .{ .what = "the shim never announced itself (no_shim_marker)", .ev = .{ .trace_read = true }, .may_say_single = false, .pins = "never announced itself" },
    // #405, and the reason this table exists.
    .{ .what = "no boundary recorded, no oracle asked for (#405)", .ev = .{ .trace_read = true, .shim_reported = true }, .may_say_single = false, .pins = "raw syscall" },
    .{ .what = "no boundary recorded, the strace account never read", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "strace account was not read" },
    .{ .what = "no boundary recorded, the fs_usage account never read", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .unread = .fs_usage } }, .may_say_single = false, .pins = "fs_usage account was not read" },
    // The one entitled state: both witnesses looked and neither saw another process.
    .{ .what = "no boundary recorded, strace read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = true, .pins = "single process" },
    .{ .what = "no boundary recorded, strace read and saw two other processes", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 2, .lines = 400 } } }, .may_say_single = false, .pins = "2 other process(es) observed" },
    // fs_usage drops whole processes by name, so its zero is not an observation of none.
    .{ .what = "no boundary recorded, fs_usage read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 3858 } } }, .may_say_single = false, .pins = "excludes some processes by name" },
    // An account of nothing is not an observation that there was nothing: the run
    // refuses `oracle_saw_nothing`, and this used to report a single process (review).
    .{ .what = "the strace capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the fs_usage capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and the empty capture was all there was", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and no oracle ran", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true }, .may_say_single = false, .pins = "no second witness ran" },
    .{ .what = "the shim recorded a boundary and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "nothing accounts for what the other process did" },
    // The two accounts disagree: a failed vfork leaves this shape, and so does a child
    // the oracle lost. Neither is preferred.
    .{ .what = "the shim recorded a boundary and strace saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = false, .pins = "disagree" },
    .{ .what = "the shim recorded a boundary and strace accounted for two children", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 2, .lines = 400 } } }, .may_say_single = false, .pins = "attributed to the subject only" },
    // The oracle's own boundary. A thread emits no pid, so `children` stays 0 and this
    // read as a single process until review measured a CLONE_THREAD capture.
    .{ .what = "strace reported a clone that crosses a boundary the shim missed", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 120 } }, .oracle_boundary = "clone" }, .may_say_single = false, .pins = "crosses a process boundary the shim did not record" },
    .{ .what = "another process performed a kill-point operation (shim)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_foreign_touch = true }, .may_say_single = false, .pins = "no crash-point address" },
    .{ .what = "another process touched the judged directory (oracle)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 1, .lines = 900 } }, .oracle_child_touched = true }, .may_say_single = false, .pins = "no crash-point address" },
    .{ .what = "the shim recorded a thread", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_hard = "a thread" }, .may_say_single = false, .pins = "the shim recorded a thread" },
    .{ .what = "the shim recorded a broken image-replacement chain", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_hard = "an image replacement whose chain of observation broke" }, .may_say_single = false, .pins = "chain of observation broke" },
    // The engine calls refusing here "the safe misreading", so the account must not
    // assert breakage either (review).
    .{ .what = "the shim recorded an image replacement before the subject announced itself", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_hard = "an image replacement before the subject announced itself" }, .may_say_single = false, .pins = "before the subject announced itself" },
    .{ .what = "the shim recorded a process leaving the containment group", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_hard = "a process leaving the containment group" }, .may_say_single = false, .pins = "leaving the containment group" },
    // World-side states. The recording half keeps its words where it earned them, and
    // the qualifier "in the recording" is what stops the sentence opening with a claim
    // about a run that went on to cross a boundary.
    .{ .what = "a world-only boundary after a witnessed single-process recording", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_only = true }, .may_say_single = true, .pins = "single process in the recording" },
    .{ .what = "a world-only boundary after an unwitnessed recording", .ev = .{ .trace_read = true, .shim_reported = true, .world_boundary = true, .world_only = true }, .may_say_single = false, .pins = "explored world" },
    .{ .what = "a world crossed a boundary the recording had also crossed", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 1, .lines = 400 } }, .world_boundary = true }, .may_say_single = false, .pins = "appeared in an explored world" },
    .{ .what = "a world's child operated on the judged directory", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_foreign_touch = true }, .may_say_single = true, .pins = "operated on the judged directory in an explored world" },
    .{ .what = "preflight's second observed run crossed a boundary (#199)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .second_run = "a process boundary" }, .may_say_single = true, .pins = "the second observed run recorded a process boundary" },
};

test "the processes account says 'single process' only where a witness able to see a boundary looked and saw none" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    var checked: usize = 0;
    for (boundary_cases) |c| {
        boundary_ev = c.ev;
        const got = boundaryAccount();
        const says = std.mem.indexOf(u8, got, "single process") != null;
        if (says != c.may_say_single) {
            std.debug.print("\nstate: {s}\n  rendered: {s}\n  wanted single-process wording: {}\n", .{ c.what, got, c.may_say_single });
            return error.WrongEntitlement;
        }
        // One bit per state is not coverage: a clause emptied by a mutation keeps the
        // bit and loses the sentence.
        if (std.mem.indexOf(u8, got, c.pins) == null) {
            std.debug.print("\nstate: {s}\n  rendered: {s}\n  missing: {s}\n", .{ c.what, got, c.pins });
            return error.ClauseLost;
        }
        checked += 1;
    }
    // The loop is the assertion; an empty table would pass it silently.
    try std.testing.expectEqual(boundary_cases.len, checked);
    try std.testing.expect(checked > 20);
}

test "a bare single-process claim is scoped the moment anything follows it" {
    // The pre-#405 string said "single process in the recording" on the world-only path
    // for this reason. Rendering it from parts nearly dropped the qualifier: review
    // caught the sentence opening with an unscoped claim about a run that went on to
    // disclose a boundary.
    const saved = boundary_ev;
    defer boundary_ev = saved;
    const witnessed: BoundaryEvidence = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } };
    boundary_ev = witnessed;
    try std.testing.expectEqualStrings("single process", boundaryAccount());
    boundary_ev = witnessed;
    boundary_ev.world_boundary = true;
    boundary_ev.world_only = true;
    try std.testing.expect(std.mem.startsWith(u8, boundaryAccount(), "single process in the recording;"));
    boundary_ev = witnessed;
    boundary_ev.second_run = "a thread";
    try std.testing.expect(std.mem.startsWith(u8, boundaryAccount(), "single process in the recording;"));
}

test "the image-replacement disclosure survives every evidence state (#123)" {
    // The regression this pins is real and was in the shipped build: the world-only site
    // assigned the whole sentence and dropped the disclosure the recording had set. Its
    // acceptance check matches "refused" and "explored world" only, so it stayed green.
    const saved = boundary_ev;
    defer boundary_ev = saved;
    var applied: usize = 0;
    for (boundary_cases) |c| {
        // `exec_continuations` is written beside `shim_reported`, so a state that never
        // read the trace cannot carry one. Forcing it there would measure a shape the
        // engine does not produce (review).
        if (!c.ev.shim_reported) continue;
        boundary_ev = c.ev;
        boundary_ev.exec_continuations = 2;
        const got = boundaryAccount();
        if (std.mem.indexOf(u8, got, "image replaced") == null) {
            std.debug.print("\nstate: {s}\n  rendered: {s}\n", .{ c.what, got });
            return error.DisclosureLost;
        }
        applied += 1;
    }
    try std.testing.expect(applied > 20);
}

test "two witnesses that disagree are both reported and neither is preferred" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    boundary_ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } };
    const got = boundaryAccount();
    try std.testing.expect(std.mem.indexOf(u8, got, "the shim recorded a process boundary") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "strace observed no other process") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "disagree") != null);
    // Control: the same shape with the shim silent is the one entitled state, so the
    // difference above is the shim's record and not the renderer refusing on principle.
    boundary_ev.shim_boundary = false;
    try std.testing.expectEqualStrings("single process", boundaryAccount());
}

test "the world-only account keeps the substrings its acceptance check matches (#169)" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    boundary_ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_only = true };
    const got = boundaryAccount();
    // spike/acceptance.sh:338 reads the JSON field and requires both of these.
    try std.testing.expect(std.mem.indexOf(u8, got, "refused") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "explored world") != null);
    // …and rejects the pre-#169 tolerate wording surviving anywhere in it.
    try std.testing.expect(std.mem.indexOf(u8, got, "observed for quiescence only") == null);
}

test "an unwitnessed run reports what could not have been seen, not that it did not happen (#405)" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    boundary_ev = .{ .trace_read = true, .shim_reported = true };
    const got = boundaryAccount();
    try std.testing.expect(std.mem.indexOf(u8, got, "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "raw syscall") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "single process") == null);
}

test "a run refused before the trace is read says so, rather than reporting the shim's silence" {
    // Measured: a toy whose operation exited the wrong status refused as
    // `recording_run_failed`, and the shipped build published `processes: single process`
    // into the JSON for it. The trace had not been read at that point; neither had
    // anything else. The two absences are different and the account names which one.
    const saved = boundary_ev;
    defer boundary_ev = saved;
    boundary_ev = .{};
    try std.testing.expectEqualStrings(
        "not established: this run was refused before the shim's account of it was read",
        boundaryAccount(),
    );
    // Control: once the trace is read, the same all-false evidence is a different fact.
    boundary_ev.trace_read = true;
    try std.testing.expect(std.mem.indexOf(u8, boundaryAccount(), "never announced itself") != null);
}
