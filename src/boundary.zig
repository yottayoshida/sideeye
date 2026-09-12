//! The process-and-thread boundary: what each witness saw, whether a run with another
//! writer is judged, and the `processes` account both reports print.
//!
//! `src/boundary.zig` owns the process-and-thread boundary — what each witness saw
//! (`BoundaryEvidence`), whether a run with another writer is judged
//! (`childrenMayBeJudged`, `unattributedWriterReason`), and the `processes` account both
//! reports print (`boundaryAccount`) — and `src/main.zig` fills that evidence in and holds
//! none of those bodies.
//!
//! Everything here is a function of its inputs: nothing writes a variable of another module
//! and nothing exits. `main.zig` records what the witnesses saw into `boundary_ev` (and the
//! recording run's image observation into `rec_image`) across six of its nine phases, and
//! calls in here for the two decisions and the account. The sentences of the refusals that
//! name another writer or an image change — `foreignTouchDetail`, `threadDetail`,
//! `unresolvedDetail`, the `noShimDetail` pair — live here too, and their only need outside
//! this file is `defang.zig`, the choke point every target-influenced string passes
//! through. Not every boundary refusal is here: the `child_process_detected` sentences are
//! still inline in `main.zig`, and `requireCompleteness` and the `crossed_boundary`
//! decisions are the orchestrator's. Both go with the report seam.
//!
//! First seam of #572 (ADR 0062). The bodies moved from `main.zig` byte for byte on
//! 2026-09-12, with `pub` added where `main.zig` still calls them; the sixteen tests that
//! hold them moved with them, and `build.zig` names this file in `test_sources` so their
//! collection does not depend on which test in `main.zig` happens to mention what.

const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const image = @import("image.zig");
const oracle = @import("oracle.zig");
const defang = @import("defang.zig");
const sanitizeForReport = defang.sanitizeForReport;
const textShown = defang.textShown;

/// What the operation's executable looked like immediately before the recording run
/// started. Read there and not at the refusal, because after the child has exited the
/// same name may resolve somewhere else entirely; see `image.zig`'s header for why a
/// match is still never reported as identity. Null on every path that never spawned.
pub var rec_image: ?image.Observation = null;

/// What the run has *established* about process boundaries, as it establishes it.
///
/// Evidence, not prose. The sentence is rendered at report time by `boundaryAccount()`,
/// so a refusal raised at any depth reports what this run actually looked at instead of
/// a claim nobody checked. This field used to be the prose itself, defaulting to
/// `"single process"` — an assertion about the target published on every path where no
/// witness had been able to look, which is the confusion the comment on `metadata_note`
/// (in `main.zig`) forbids: "was not seen" must not read as "did not happen" here any
/// more than anywhere else in this tool. On macOS with no oracle nothing can see a raw
/// `fork(2)`, and the account said "single process" while a child's file sat in the
/// judged directory (#405).
///
/// Rendering also removes the wholesale-replacement hazard the old shape carried: three
/// assignment sites each overwrote the whole sentence, and the world-only one dropped the
/// image-replacement disclosure the recording had set (#123) with nothing to catch it.
pub var boundary_ev: BoundaryEvidence = .{};

pub const BoundaryEvidence = struct {
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
    /// A subject exec whose chain did NOT survive. Carried beside the count rather than
    /// derived from `shim_hard`, which names the FIRST hard boundary only: a thread
    /// recorded before the exec takes that string, and the chain's state would vanish
    /// from the account (a shape this repository has on record — the joplin preflight
    /// transcripts print a thread refusal beside an image-replacement clause).
    exec_chain_broken: bool = false,
    /// The shim's boundary implies a second PROCESS, not just the subject replacing its
    /// own image. Only the account reads it; `shim_boundary` (which includes image
    /// changes) is what the oracle requirement keys on and is unchanged.
    shim_process_boundary: bool = false,
    /// The oracle saw a non-subject operation on the judged directory.
    oracle_child_touched: bool = false,
    /// Those operations were admitted as crash points (v15): the two witnesses named the
    /// same writers, no two writers' operations interleaved in the trace, and every
    /// writing child was reaped. Read only by the account — the refusal is decided at the
    /// site — and it is what keeps a FAIL from saying "no crash-point address" about a
    /// run whose crash points include a child's operations.
    children_judged: bool = false,
    /// What the oracle's *own* account called a boundary — a `clone` carrying
    /// `CLONE_FS` without `CLONE_THREAD`, an `unshare`, a non-primary `setsid`/`setpgid`
    /// (`src/oracle.zig`). The child count cannot express this: such a clone emits no
    /// pid the count reads, so a run refusing `child_process_detected` on the oracle's
    /// evidence had `children == 0` and read as a single process until review measured
    /// it. A thread left this set in v16 — it is the subject's, not a boundary.
    oracle_boundary: ?[]const u8 = null,
    /// Threads the shim saw the subject create (`pthread_create` records), and how many
    /// distinct thread ids wrote the judged directory under the subject's pid (v16). The
    /// account prints both so a reader can see that a judged run had threads and that
    /// one of them did the writing — the claim the thread rule rests on.
    threads: u32 = 0,
    /// Under the subject's pid only. A child's threads are judged by the same rule and
    /// refused by the same sentence, but they are not counted here — the committed
    /// git-annex report (`spike/followup-item4/artifacts/annex.*.json`, recorded under the
    /// clause's first wording) carries "0 thread id(s) wrote the judged directory" beside
    /// a refusal naming two threads of a child, and the clause says "of the subject's own
    /// process" now so the two do not read as a contradiction.
    writer_threads: u32 = 0,
    /// A thread whose creation the shim never recorded wrote the judged directory (#543;
    /// `TraceInfo.unrecorded_writer_thread` says how it is decided). Mutually exclusive
    /// with `threads > 0` by construction — the trace asks the question only when it holds
    /// no `.thread` record at all — so the account's thread clause has two shapes and
    /// never both.
    unrecorded_writer_thread: bool = false,
    /// The shim's boundary is a thread and nothing else (v16): no other process, no image
    /// change. The account's recording clause has three shapes for a boundary the oracle
    /// did not corroborate — "a process boundary", "the subject replacing its own image",
    /// and this one — and before this field the third fell into the second, which on a
    /// judged threaded toy printed an image replacement that never happened (measured).
    shim_thread_only: bool = false,
    /// The same for an explored world: its boundary was a thread and nothing else.
    world_thread_only: bool = false,
    /// A boundary in an explored world that is **not** the subject replacing its own
    /// image — the world-side counterpart of `shim_process_boundary`, at the same
    /// granularity as `world_boundary` (one bit across every world, not one per world).
    /// A world re-runs the operation, so a self-exec target crosses a boundary in every
    /// one of them, and the account said "a process boundary appeared in an explored
    /// world" over an image change until 2026-09-07 — visible in the same sentence whose
    /// recording half this change was fixing.
    world_process_boundary: bool = false,
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

    pub const Kind = enum {
        strace,
        fs_usage,

        /// The tag, like the two in `contract.zig` (#280). This was the third
        /// hand-written switch of the same shape and the first scan for them missed it:
        /// it looked in `contract.zig` only, where the other two live, while
        /// `grep -n "fn name(self" src/*.zig` finds all three.
        pub fn name(self: Kind) []const u8 {
            return @tagName(self);
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
var boundary_buf: [1280]u8 = undefined;

/// The `processes` account. Two clauses at most: what the recording established, and
/// what an explored world added, followed by the image disclosure when one applies.
///
/// Three substrings are load-bearing for checks in `spike/acceptance.sh` that hold this
/// code to its behaviour: the world-only leg requires "refused" and "explored world" in
/// the account and forbids the pre-#169 "observed for quiescence only", and the
/// self-exec legs require "image replaced" in a FAIL that carried an image change.
/// Named by what they grep for rather than by line. The numbers that stood here — 338
/// and 629 — point at neither leg any more, and a current pair would rot the same way:
/// this change alone moved everything below its own legs by 76 lines.
pub fn boundaryAccount() []const u8 {
    var scratch: [512]u8 = undefined;
    // Same split as the recording clause below, on the world's own evidence: a world
    // re-runs the operation, so a target that replaces its own image does it in every
    // world, and calling that "a process boundary appeared" is the overclaim this change
    // is about. `world_only`'s wording keeps the refusal it names.
    const world_proc = boundary_ev.world_process_boundary;
    const world: []const u8 = if (boundary_ev.world_foreign_touch and boundary_ev.children_judged)
        // The same observation, said as what it is (v15): the class the recording admitted,
        // reappearing where a world cannot re-decide it. Without this the account ends on
        // an unqualified finding, which reads as a discovery rather than as the expected.
        "; a process other than the subject operated on the judged directory in an explored world too — the class the recording admitted, which a world inherits rather than re-deciding because it runs without an oracle"
    else if (boundary_ev.world_foreign_touch)
        "; a process other than the subject operated on the judged directory in an explored world"
    else if (boundary_ev.world_only and world_proc)
        "; a process boundary appeared in an explored world — refused: nothing accounts for what it did"
    else if (boundary_ev.world_only)
        "; the subject replaced its own image in an explored world the recording never did — refused: the chain there is unaccounted for"
    else if (boundary_ev.world_boundary and world_proc)
        "; a process boundary appeared in an explored world, which runs with no oracle"
    else if (boundary_ev.world_boundary and boundary_ev.world_thread_only)
        // A thread is not a boundary an oracle would account for (v16), so the clause
        // does not say "which runs with no oracle" of it: the thread clause after this
        // one says what the threads did.
        "; a thread was created in an explored world"
    else if (boundary_ev.world_boundary)
        "; the subject replaced its own image in an explored world, which runs with no oracle"
    else
        "";
    const recording = blk: {
        const c = boundaryRecordingClause(&scratch);
        // The bare assertion has to stay scoped when something follows it: the pre-#405
        // string said "single process in the recording" for exactly this reason, and
        // dropping the qualifier would let a sentence that goes on to disclose a world
        // boundary open by claiming the run had one process.
        if (std.mem.eql(u8, c, "single process") and
            (world.len > 0 or boundary_ev.second_run != null or boundary_ev.threads > 0 or
                boundary_ev.unrecorded_writer_thread))
            break :blk "single process in the recording";
        break :blk c;
    };
    var second_buf: [256]u8 = undefined;
    const second: []const u8 = if (boundary_ev.second_run) |what|
        std.fmt.bufPrint(&second_buf, "; the second observed run recorded {s}, and that run's capture is never parsed, so nothing accounts for it", .{what}) catch
            "; the second observed run recorded a boundary that nothing accounts for"
    else
        "";
    // The thread clause (v16), appended to whatever the clauses above say the way the
    // image-change clause is: a judged run that created threads must say so, and say
    // that one thread wrote, or a reader of "single process" would take it for a
    // single-threaded one. The shim's count is a floor — a raw clone leaves no record.
    //
    // Two shapes and never both (#543). The second is for a run whose threads the shim
    // could not count at all: a raw `clone`, or a thread started before the shim was in
    // the image, leaves no `.thread` record while its writes still carry its tid. Without
    // it that run renders a bare "single process" and a reader takes it for
    // single-threaded — the exact reading `docs/report-schema.md` says this clause exists
    // to prevent. Appended through this one variable rather than at a return site: the
    // three returns below all interpolate `{threads}`, and a clause added at one of them
    // would vanish on the other two. That has happened here before, to the world clause.
    var thread_buf: [200]u8 = undefined;
    const threads: []const u8 = if (boundary_ev.threads > 0)
        std.fmt.bufPrint(&thread_buf, "; the shim recorded {d} thread(s) created, and {d} thread id(s) of the subject's own process wrote the judged directory (v16: one per process is judged, two refuse)", .{ boundary_ev.threads, boundary_ev.writer_threads }) catch
            "; the shim recorded threads created (v16)"
    else if (boundary_ev.unrecorded_writer_thread)
        "; a thread the shim never recorded creating wrote the judged directory, so its count of threads is a floor and no witness is held against it (v16, #543)"
    else
        "";
    if (boundary_ev.exec_continuations > 0) {
        // Two sentences, because two things can be true at once: a chain that closed
        // and a later image change that escaped. Saying "chain unbroken" over the
        // second was measured on a real refusal, in one sentence with `shim_hard`'s
        // "whose chain of observation broke" (2026-09-07). Both branches keep the
        // words "image replaced" — the disclosure this clause exists for, pinned
        // across every evidence state below.
        if (boundary_ev.exec_chain_broken) {
            return std.fmt.bufPrint(
                &boundary_buf,
                "{s}{s}{s}{s}; the subject's image replaced {d} time(s) with the chain followed, and a further image change escaped observation (#123)",
                .{ recording, world, second, threads, boundary_ev.exec_continuations },
            ) catch "the subject's image replaced, and a further image change escaped observation";
        }
        return std.fmt.bufPrint(
            &boundary_buf,
            "{s}{s}{s}{s}; the subject's image replaced {d} time(s), chain unbroken (#123)",
            .{ recording, world, second, threads, boundary_ev.exec_continuations },
        ) catch "the subject's image replaced, chain unbroken";
    }
    // Not `catch recording`: that slice points into `scratch`, a stack local of this
    // frame, and returning it would hand the caller a dangling pointer on the one path
    // where the buffer is too small. Unreachable at the current lengths — the longest
    // combination measured was **626 of 1024 bytes** (2026-09-07, over `boundary_cases`
    // crossed with both chain states, both continuation states and every `second_run`
    // value; it read 494 before that day's wordings), and v16 widened the buffer to 1280
    // for a thread clause of at most 178 bytes (the literal and two u32 values; review
    // counted it), which keeps at least the margin the measurement had; the crossing itself was not re-run — but "unreachable" is not a
    // lifetime. #543 gave that clause a second shape, a fixed literal **measured at 152
    // bytes**, which is under the 178 the bound was set from, so the bound does not move.
    // The two shapes are mutually exclusive, so no run carries both.
    return std.fmt.bufPrint(&boundary_buf, "{s}{s}{s}{s}", .{ recording, world, second, threads }) catch
        "the process-boundary account did not fit its buffer; treat it as not established";
}

/// The tolerated-children sentence, kept verbatim from before this field became
/// evidence: a FAIL's reader has to see that the window is attributed to the subject
/// alone, and 12 committed report artifacts hold this exact string.
fn toleratedChildrenClause(scratch: []u8, children: usize) []const u8 {
    return std.fmt.bufPrint(scratch, "{d} other process(es) observed; none touched the state directory. A FAIL's window is attributed to the subject only", .{children}) catch
        "other process(es) observed; none touched the state directory";
}

/// What an empty `fs_usage` child list is worth, which is less than strace's: the
/// default exclusion list drops whole processes by name and `-e` does not lift it
/// (measured), so ADR 0031 §2a rules that a boundary is never tolerated under it. One
/// constant because two sites need the same sentence — the no-boundary arm below, and
/// the image-change arm above it, which must not borrow strace's stronger wording.
const fs_usage_silence = "no other process mutated the judged directory in the fs_usage capture; fs_usage excludes some processes by name, so a child that execs one of them would not appear (ADR 0031)";

/// What the recording run established, in priority order: an operation by another
/// process outranks the question of whether a boundary was crossed, and a boundary the
/// shim named outranks the witness matrix.
fn boundaryRecordingClause(scratch: []u8) []const u8 {
    const ev = boundary_ev;
    if (!ev.trace_read)
        return "not established: this run was refused before the shim's account of it was read";
    if (!ev.shim_reported)
        return "not established: the shim never announced itself in this run, so nothing observed process boundaries";
    // Above `shim_hard` deliberately, and the combination that would make the order
    // matter is unreachable rather than merely unlikely: `children_judged` is set inside
    // the oracle block, which a run with a hard boundary never reaches — the
    // `hard_boundary` refusal exits several statements earlier. What CAN hold together is
    // a foreign touch and a hard boundary with the children REFUSED, and that pair reads
    // the same sentence it always did.
    if (ev.shim_foreign_touch or ev.oracle_child_touched)
        return if (ev.children_judged)
            "a process other than the subject operated on the judged directory, and those operations hold crash-point addresses: no two processes' operations interleaved and every writing child was reaped (contract v15). An explored world does not re-check that — it runs without an oracle — so it inherits this finding, and what each world does check is that the operations before its crash point are the ones the recording numbered"
            // The same correction as the refusal this run carries (#544, ADR 0060), one
            // layer over. When the only evidence is an oracle that names threads — the
            // shim saw no foreign pid, or this account would rest on something that does
            // name processes — "a process" is a claim the run did not establish. Reaching
            // this with a thread is new: until #544 a threaded run under that oracle
            // refused at the flag and never rendered an account at all, so the sentence
            // below and the refusal beside it would have disagreed inside one report.
        else if (!ev.shim_foreign_touch and switch (ev.witness) {
            .read => |r| r.kind == .fs_usage,
            else => false,
        })
            "an id other than the subject's operated on the judged directory; this witness names a thread and knows no process for it, so whether that id is another process or a thread the shim never recorded is not established here. Its operations have no crash-point address"
        else
            "a process other than the subject operated on the judged directory; its operations have no crash-point address";
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
    // What the shim's boundary record actually was, in the account's own words. A
    // subject replacing its own image is a boundary for every purpose the engine keys
    // on `shim_boundary` — the oracle requirement and the quiescence sampling among
    // them — and it is NOT another process, so the four arms below say which they are
    // talking about rather than calling both "a process boundary". Before 2026-09-07
    // they said the latter of a self-exec run, which is the same overclaim as the
    // disagreement the `.read` arm used to report (measured on a judged run).
    const recorded: []const u8 = if (ev.shim_process_boundary)
        "the shim recorded a process boundary"
    else if (ev.shim_thread_only)
        "the shim recorded a thread"
    else
        "the shim recorded the subject replacing its own image";
    switch (ev.witness) {
        .read => |r| if (r.lines == 0) return if (ev.shim_boundary)
            std.fmt.bufPrint(scratch, "not established: {s} and the {s} capture was empty, so nothing was compared", .{ recorded, r.kind.name() }) catch
                "not established: the oracle's capture was empty, so nothing was compared"
        else
            std.fmt.bufPrint(scratch, "not established: the {s} capture was empty, so nothing was compared and no other process was looked for", .{r.kind.name()}) catch
                "not established: the oracle's capture was empty, so nothing was compared",
        else => {},
    }
    if (ev.shim_boundary) return switch (ev.witness) {
        .none => std.fmt.bufPrint(scratch, "{s} and no second witness ran", .{recorded}) catch
            "the shim recorded a boundary and no second witness ran",
        // The tail names the other process only when there was one to name: an image
        // change leaves nothing unaccounted for on that axis.
        .unread => |k| if (ev.shim_process_boundary)
            std.fmt.bufPrint(scratch, "{s}; the {s} account was not read, so nothing accounts for what the other process did", .{ recorded, k.name() }) catch
                "the shim recorded a process boundary and the oracle's account was not read"
        else
            std.fmt.bufPrint(scratch, "{s}; the {s} account was not read", .{ recorded, k.name() }) catch
                "the shim recorded the subject replacing its own image and the oracle's account was not read",
        .read => |r| if (r.children > 0)
            // Kept verbatim from before this field became evidence: a FAIL's reader has
            // to see that the window is attributed to the subject alone.
            toleratedChildrenClause(scratch, r.children)
        else if (ev.shim_process_boundary)
            // The two witnesses disagree. Neither is preferred here: a `vfork` that
            // failed leaves a boundary record with no child, and a child the oracle lost
            // leaves the same shape. The run says so rather than picking.
            std.fmt.bufPrint(scratch, "the shim recorded a process boundary and {s} observed no other process; the two accounts disagree and this run does not resolve them", .{r.kind.name()}) catch
                "the shim and the oracle disagree about whether a process boundary happened"
        else switch (r.kind) {
            // The only boundary the shim recorded is the subject replacing its own
            // image. That claims no second process, so a witness reporting one process
            // AGREES with it, and the disagreement above would report a relation that
            // does not hold — which `docs/report-schema.md` promises this field does not
            // do ("where the two witnesses disagree the note reports both"). The image
            // change is not lost by saying this: the caller appends the clause that
            // discloses it. Measured 2026-09-07 on a judged self-exec.
            .strace => "single process",
            // Not the same claim as strace's zero — see `fs_usage_silence`. **This side
            // became reachable in #544**, and the comment that stood here said it could
            // not be: a boundary under fs_usage is refused before the account renders
            // (`boundary_without_oracle`, ADR 0031 §2a), which held while every threaded
            // run refused at the flag instead. A thread is a boundary for
            // `crossedBoundary` and not for `needsOracle` (v16, ADR 0055), so a
            // single-process threaded run now arrives here with no process boundary and no
            // other writer. The wording was already right and nothing fell over; what was
            // wrong was the claim that nothing could produce it — which is the kind of
            // breakage that fails silently, since a stale reachability note compiles.
            // A case pins it now, on the same reasoning the old note used to decline one.
            .fs_usage => fs_usage_silence,
        },
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
            .fs_usage => fs_usage_silence,
        },
    };
}

/// The `child_touched_state_dir` detail, naming what the trace holds (#484): which
/// process, which operation, which path — the three things the operator's next move
/// branches on (a config flag, a `scratch` declaration, or a different invocation), and
/// the three things the old sentence dropped while the engine had them in memory. A
/// two-path operation names both ends (`rename` and `link` alike — the shim records one
/// when either end is inside the state directory, so the inside end may be the second).
/// The path is target-chosen, so the composed sentence goes through `sanitizeForReport`
/// like every other target-controlled string that reaches the text report (#26): a child
/// naming a file after a report line must not be able to forge one. `fallback` is the
/// sentence the site used to print — what comes out if the reader recorded the refusal
/// without the record (it does not; `first_foreign` is set on the line that sets
/// `foreign_kill_point`) or if the arena is exhausted: a refusal that names nothing
/// rather than one that names something wrong.
/// May a run whose children wrote in the judged directory be judged (v15)? Returns null
/// when it may, and the sentence naming what stopped it when it may not.
///
/// Two conditions, and each one is here because a run that fails it would be judged at an
/// address that is not reproducible or not there at all:
///
/// 1. **The two witnesses name the same writers**, in both directions. A process the
///    oracle saw mutate and the shim did not record wrote operations that hold no number
///    — `TOY_SPAWN_WRITES` spawns exactly that, a `/bin/sh` with an emptied environment —
///    and a run judged over the rest would be judged over an incomplete sequence. The
///    other direction is not symmetry for its own sake: `oracle.zig` resolves a relative
///    path against the SUBJECT's working directory, so a child that changed its own is
///    invisible to it, and condition 2 would then be asked about a set that does not
///    contain the writer it was meant to be asked about.
/// 2. **Each writing child had the judged directory to itself from its creation until it
///    was collected.** In the oracle's line order: from the `clone` that returned it to
///    the wait that reaped it, no other process performs a state-directory operation.
///    **The window starts at the creation and not at the child's first write**, and the
///    difference is a shape that would otherwise be admitted: fork, then the PARENT
///    writes, then the child writes, then the parent waits. Nothing orders those two
///    writes — the child was already running — and on the next run they could land the
///    other way round. `spike/followup-item3/NOTES.md` recorded that counterexample the
///    day before this was implemented, and the first implementation shipped past it. That is what a hand-off looks like
///    and what a race does not — and it is why this is decided in the oracle's order
///    rather than the trace's. **The trace cannot answer it.** An awaited child's records
///    sit between its parent's, and so do a racing sibling's; the record sequence
///    `parent, child, parent` and `child A, child B, child A` are the same shape. The
///    wait is the thing that tells them apart, and the wait and the writes are in one
///    order only in the capture. A first draft of this function did use record order and
///    was caught by its own test: it called the poster-child shape an interleaving,
///    because a parent's first and last records always straddle its children's.
///
/// What condition 2 does NOT require is that the parent was blocked across the child's
/// writes. The measurement in `spike/followup-item3/NOTES.md` shows a shell blocking in
/// `wait4` for a foreground command and reaping a pipeline stage with `WNOHANG`
/// afterwards; gating on the stronger reading would admit a target on one run and refuse
/// it on the next, depending on whether the child reached its write before the parent
/// reached its wait.
///
/// There is no mode gate. There used to be one, and it was not a third condition but the
/// absence of the first: `--observe syscalls` took its second witness from a separate
/// untrapped run, so nothing accounted for a child in the run the trace came from. The
/// oracle now watches the run it judges in that mode too, and the two conditions below are
/// asked of it the way they are asked of any other run.
/// Which refusal an unattributed writer gets, when `childrenMayBeJudged` has already said
/// that the run is refused (#544, ADR 0060 decision 8).
///
/// Separate from the message that names the writer, and separate on purpose: the two are
/// decided in different places and only the message had a test, so switching this off left
/// every unit test green. Callers pass the two witnesses; the answer is a function of them
/// and nothing else.
///
/// A process boundary the shim saw has already refused before this is asked
/// (`boundary_without_oracle`), so reaching it means none was recorded. If the shim also
/// recorded threads being created, "another thread of this process wrote" is the reading
/// the run supports — a child with no boundary record needs a raw `fork`, while an
/// unattributed thread needs only that the shim missed its writes, which is the class the
/// fs_usage oracle exists to catch. With no thread records the raw-fork shape is what is
/// left and #405's exit stands. On the strace path `primary_pid` is set from a pid, the
/// id really is a process, and nothing here changes.
pub fn unattributedWriterReason(trace: engine.TraceInfo, parsed: oracle.Parsed) contract.UnknownReason {
    if (parsed.primary_pid == null and trace.thread_records > 0 and !trace.process_boundary)
        return .multiple_threads_detected;
    return .child_touched_state_dir;
}

pub fn childrenMayBeJudged(
    arena: std.mem.Allocator,
    trace: engine.TraceInfo,
    parsed: oracle.Parsed,
) ?[]const u8 {
    if (!trace.foreign_kill_point and !parsed.childTouched()) return null;

    const primary = trace.primary_pid orelse return "the trace holds state-directory operations but no process announced itself, so none of them can be attributed";

    // Both witnesses, collapsed to one entry per writing process before anything is
    // compared. Written this way for cost as much as for shape: the first version asked
    // each question inside a loop over every record and every mutation, which is quadratic
    // in exactly the runs this version exists to judge — a target with many operations in
    // many children is the one that pays. One writer per process, and the comparisons are
    // then between two short lists.
    // The shim's writers, one entry each, carrying that process's first recorded operation
    // — which is what a refusal names (#484: the pid, the operation and its path).
    var shim_writers: std.ArrayList(engine.Op) = .empty;
    for (trace.ops.items) |op| {
        if (!op.class.isKillPoint() or op.pid == primary) continue;
        var seen = false;
        for (shim_writers.items) |w| {
            if (w.pid == op.pid) seen = true;
        }
        if (!seen) shim_writers.append(arena, op) catch
            return "out of memory while reading which processes wrote in the judged directory";
    }
    // The oracle's, carrying where each one first wrote — the point the window is measured
    // from and the one the reap has to follow.
    var oracle_writers: std.ArrayList(oracle.Event) = .empty;
    for (parsed.mutations.items) |m| {
        // The subject's threads are the subject (v16): a mutation from one is not a
        // child's, and comparing its tid against the shim's pid-keyed writer list would
        // have refused it as "recorded nothing of its own".
        if (parsed.isSubject(m.id)) continue;
        var seen = false;
        for (oracle_writers.items) |w| {
            if (w.id == m.id) seen = true;
        }
        if (!seen) oracle_writers.append(arena, m) catch
            return "out of memory while reading which processes the oracle saw write";
    }

    // Condition 1, from the shim's side: every process the shim recorded writing is one
    // the oracle placed too.
    for (shim_writers.items) |w| {
        var in_oracle = false;
        for (oracle_writers.items) |o| {
            if (o.id == w.pid) in_oracle = true;
        }
        if (!in_oracle)
            return std.fmt.allocPrint(
                arena,
                "a process other than the subject (pid {d}) performed {s}({s}) and the oracle's account does not place it. That reader resolves a relative path against the subject's working directory, so a child that changed its own is invisible to it — and with only one witness for those operations, nothing can check that nobody else wrote while they ran",
                .{ w.pid, w.class.name(), w.path },
            ) catch "a process recorded state-directory operations the oracle's account does not place";
    }

    // Condition 1's other direction, and condition 2, once per writing child.
    for (oracle_writers.items) |w| {
        // The same list built above, not a fresh walk of every record: it already holds
        // one entry per writing process, with the operation a refusal names.
        var recorded: ?engine.Op = null;
        for (shim_writers.items) |sw| {
            if (sw.pid == w.id) recorded = sw;
        }
        if (recorded == null) {
            // That this id is a PROCESS is a claim, and until #544 the refusal below made
            // it whatever the witness was. It holds for a witness that reads pids: strace
            // names the process on every line, and `Parsed.primary_pid` is set from one.
            // It does not hold for `fs_usage`, which attributes a line to a THREAD id and
            // prints no process anywhere (ADR 0031) — `src/fsusage.zig` sets no
            // `primary_pid` in consequence, and that absence is the discriminator here,
            // the same one `childTouched()` already keys on. Under that witness an id
            // which mutated the judged directory and matched none of the subject's
            // recorded writing threads (`isSubject`, above) can be either thing: a process
            // that never loaded the shim, or a thread whose operations went around the
            // shim's wrappers — a raw syscall, or a thread started before the shim was in
            // the image. Both are refused; what changes is that the sentence stops naming
            // one of the two as though the run had established which.
            //
            // A first version of this arm asked the TRACE whether it held a record from a
            // process with that id. It reads as the same question and is not: it reworded
            // the refusal on the strace path too, where the id really is a pid, and the
            // v15 fixture in this file caught it.
            if (parsed.primary_pid == null)
                return std.fmt.allocPrint(
                    arena,
                    "id {d} mutated the judged directory in the oracle's account and recorded nothing of its own. This witness names a thread and knows no process for it, so this is either a process that never loaded the shim or a thread whose operations went around the shim's wrappers; calling it a process would assert the half this run cannot see. Either way its operations hold no crash-point number and the sequence the crash points were read from is incomplete",
                    .{w.id},
                ) catch "an id mutated the judged directory and the witness cannot say whether it is a process";
            return std.fmt.allocPrint(
                arena,
                "process {d} mutated the judged directory in the oracle's account and recorded nothing of its own, so its operations hold no crash-point number and the sequence the crash points were read from is incomplete. A child that never loaded the shim — an emptied environment, a static image — is seen only by the oracle",
                .{w.id},
            ) catch "a process mutated the judged directory without recording anything of its own";
        }

        // Where this child was created. Without it the window would start at the child's
        // own first write, and a parent that wrote in between — with the child already
        // running — would be admitted.
        var spawned_at: ?usize = null;
        for (parsed.spawns.items) |c| {
            // The earliest, and **not required to precede the child's first write**: a
            // child can reach the judged directory before the `clone` that names it has
            // resumed — `spawnedPid`'s own doc records that ordering — and a `posix_spawn`
            // whose file actions open a redirect before the exec is the shape that does
            // it. Requiring the spawn to come first turned that into a refusal for a run
            // nothing was wrong with. Taking the earlier of the two keeps the window at
            // least as wide as the child's own activity, which is the property the check
            // needs.
            if (c.id == w.id and (spawned_at == null or c.at < spawned_at.?)) spawned_at = c.at;
        }
        const window_from = if (spawned_at) |sp| @min(sp, w.at) else null;
        const from = window_from orelse return std.fmt.allocPrint(
            arena,
            "the oracle's capture does not show where process {d} was created, and it wrote in the judged directory: without that point there is no window in which to ask whether anything else wrote while it ran",
            .{w.id},
        ) catch "the capture does not show where a writing process was created";

        // The first reap after that first write. Not "the first reap of it at all": a pid
        // can be reaped once, but reading the first one that follows keeps the comparison
        // honest if a capture ever holds two.
        var reaped_at: ?usize = null;
        for (parsed.reaps.items) |r| {
            if (r.id == w.id and r.at >= w.at) {
                reaped_at = r.at;
                break;
            }
        }
        const until = reaped_at orelse return std.fmt.allocPrint(
            arena,
            "a process other than the subject (pid {d}) performed {s}({s}) and nothing waited for it afterwards: its operations and the subject's are ordered by the scheduler rather than by a join, so the sequence they were numbered in is one sample rather than the order the program imposes",
            .{ w.id, if (recorded) |o| o.class.name() else "an operation", if (recorded) |o| o.path else "" },
        ) catch "nothing waited for a process that wrote in the judged directory";

        for (parsed.mutations.items) |other| {
            if (other.id == w.id) continue;
            if (other.at > from and other.at < until)
                // Named the way #484's refusal names things — pid, operation, path — for
                // the same reason: the operator's next move should not start from a guess.
                return std.fmt.allocPrint(
                    arena,
                    "a process other than the subject (pid {d}) performed {s}({s}), and process {d} wrote in the judged directory while it was still running — nothing had collected it yet. Two processes writing at once are ordered by the scheduler, so the sequence they were numbered in is the one this run happened to produce and a crash point would not name the same operation on the next. A run whose writers take turns is judged; one whose writers overlap is not",
                    .{
                        w.id,
                        if (recorded) |o| o.class.name() else "an operation",
                        if (recorded) |o| o.path else "",
                        other.id,
                    },
                ) catch "two processes wrote in the judged directory at the same time";
        }
    }

    return null;
}

pub fn foreignTouchDetail(arena: std.mem.Allocator, first: ?engine.Op, when: []const u8, oracle_capture: ?[]const u8, fallback: []const u8) []const u8 {
    const op = first orelse return fallback;
    const composed = if (op.class == .kill_landed)
        // The shim's own marker, written by a spawned child that armed itself and was
        // killed at this path: not an operation the child performed, but where it was
        // when the kill landed. The marker replaces the operation's record and carries
        // its path and aux but no class, so the sentence names the place, both ends.
        (if (op.aux.len > 0)
            std.fmt.allocPrint(arena, "a process other than the subject (pid {d}) was killed at a state-directory operation on {s} -> {s} {s}", .{ op.pid, op.path, op.aux, when }) catch return fallback
        else
            std.fmt.allocPrint(arena, "a process other than the subject (pid {d}) was killed at a state-directory operation on {s} {s}", .{ op.pid, op.path, when }) catch return fallback)
    else if (op.aux.len > 0)
        std.fmt.allocPrint(arena, "a process other than the subject (pid {d}) performed {s}({s} -> {s}) {s}", .{ op.pid, op.class.name(), op.path, op.aux, when }) catch return fallback
    else
        std.fmt.allocPrint(arena, "a process other than the subject (pid {d}) performed {s}({s}) {s}", .{ op.pid, op.class.name(), op.path, when }) catch return fallback;
    return withOracleCapture(arena, composed, oracle_capture, fallback);
}

/// What preflight's second run recorded, in the account's words, or null for nothing. A
/// function rather than the inline chain it was, so the shapes can be pinned from a trace:
/// the review of v16 found the recording and world clauses given their thread arm and this
/// site not, with a thread-only run B reported as "the subject replacing its own image" —
/// the same overclaim those clauses had stopped making the day before. An unbroken
/// self-exec chain leaves `hard_boundary` null, so it reaches the second branch rather than
/// the `.exec` arm, and calling it "a process boundary" would be the overclaim from the
/// other direction.
pub fn secondRunLabel(trace: engine.TraceInfo) ?[]const u8 {
    if (trace.hard_boundary) |b| switch (b) {
        .exec => return "an image replacement",
        .detached => return "a process leaving the containment group",
        else => {},
    };
    if (trace.crossedBoundary()) {
        if (trace.crossedProcessBoundary()) return "a process boundary";
        if (trace.boundary == .thread and trace.exec_continuations == 0) return "a thread";
        return "the subject replacing its own image";
    }
    // The inline chain this replaced had a fourth arm here, on `foreign_kill_point`. It was
    // unreachable: that flag is set together with `foreign_pid_seen`, which `crossedBoundary`
    // already answers to, so the branch above takes every such run as "a process boundary".
    // Struck rather than kept as documentation of a case that cannot happen.
    return null;
}

/// The thread refusal's sentence (v16): which process, which two threads, what each did
/// and where — what an operator needs to find both writers in their own code — with the
/// rule in one sentence after them. Both threads are named because which one the trace
/// saw first is the scheduler's choice on that run: the measured toy has its worker
/// write before the main thread, and a sentence naming only "the second" named the main
/// thread's open, which is the one the operator did not need pointing to. `where` is the
/// run it happened in, the way `unresolvedDetail` takes it.
pub fn threadDetail(arena: std.mem.Allocator, first: ?engine.Op, second: engine.Op, where: []const u8) []const u8 {
    const fallback = "two threads of one process wrote in the judged directory; two threads writing are ordered by the scheduler, so no crash-point address in this run can be trusted";
    const first_clause = if (first) |f|
        std.fmt.allocPrint(arena, "tid {d} performed {s}({s}) and ", .{ f.tid, f.class.name(), f.path }) catch return fallback
    else
        "";
    const composed = std.fmt.allocPrint(
        arena,
        "two threads of process {d} wrote in the judged directory{s}: {s}tid {d} performed {s}({s}). Two threads' writes are ordered by the scheduler, so the sequence they were numbered in is the one this run happened to produce and a crash point would not name the same operation on the next. A run whose state-directory writes come from one thread of each process is judged, however many threads it created",
        .{ second.pid, where, first_clause, second.tid, second.class.name(), second.path },
    ) catch return fallback;
    return sanitizeForReport(arena, composed) catch fallback;
}

/// The record the trace reader could not place, as a sentence (#485).
///
/// Sits beside `foreignTouchDetail` because it is the same job on the same input: a
/// `?engine.Op` becomes a refusal line, or the caller's fallback when there is none.
/// `class` and `seq` are not named — this record type writes `.unresolved` and `0` for
/// every one of them, so they identify nothing; what identifies it is the kind the shim
/// chose and the pid. The name is said only when there is one: `noteLinkByDescriptor`
/// and the trace-close marker record no path, and claiming a filename there would be
/// inventing an observation.
///
/// Sanitised once at the end, through the same choke point the neighbouring renderer
/// uses, rather than per field.
/// `where` names the run this record came from — "" for the recording run, " in an
/// explored world", " in the second observed run". It is interpolated into the composed
/// sentence rather than passed as the fallback, because the fallback is used ONLY when
/// there is no record at all: a caller that put its location there would see it dropped
/// on every run that actually has one, and all three sites would report the recording
/// run's wording. Measured: the world and run-B legs asked for their own wording and got
/// the recording run's, which is what caught it.
pub fn unresolvedDetail(arena: std.mem.Allocator, first: ?engine.Op, where: []const u8, fallback: []const u8) []const u8 {
    const op = first orelse return fallback;
    const why = if (op.aux.len > 0) op.aux else "reason not recorded";
    const named = if (op.path.len > 0)
        std.fmt.allocPrint(arena, "last named {s}", .{op.path}) catch return fallback
    else
        "no name recorded for it";
    const composed = std.fmt.allocPrint(
        arena,
        "an operation was observed{s} whose path could not be determined ({s}, pid {d}, {s}), so it cannot be placed among the crash points",
        .{ where, why, op.pid, named },
    ) catch return fallback;
    return sanitizeForReport(arena, composed) catch fallback;
}

test "unresolvedDetail puts the run it happened in into the sentence, not into the fallback" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const op: engine.Op = .{ .class = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/s/d.txt", .aux = "unlinked-fd write fd:3" };

    // The three sites' wordings, each of which must reach the reader. The fallback is
    // deliberately something no assertion below accepts: if `where` were ignored and the
    // fallback used instead, every one of these would carry it.
    const rec = unresolvedDetail(arena, op, "", "FALLBACK");
    try std.testing.expect(std.mem.indexOf(u8, rec, "an operation was observed whose path") != null);
    try std.testing.expect(std.mem.indexOf(u8, rec, "FALLBACK") == null);

    const world = unresolvedDetail(arena, op, " in an explored world", "FALLBACK");
    try std.testing.expect(std.mem.indexOf(u8, world, "observed in an explored world whose path") != null);
    try std.testing.expect(std.mem.indexOf(u8, world, "unlinked-fd write fd:3") != null);

    const run_b = unresolvedDetail(arena, op, " in the second observed run", "FALLBACK");
    try std.testing.expect(std.mem.indexOf(u8, run_b, "observed in the second observed run whose path") != null);

    // With no record there is nothing to compose, and only then is the fallback the answer.
    try std.testing.expectEqualStrings("FALLBACK", unresolvedDetail(arena, null, " in an explored world", "FALLBACK"));
}

test "unresolvedDetail names the kind and pid, and only claims a name when there is one (#485)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fb = "an operation was observed whose path could not be determined";

    // No record: the caller's sentence, unchanged.
    try std.testing.expectEqualStrings(fb, unresolvedDetail(arena, null, "", fb));

    // With a name.
    const named = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/doomed.txt", .aux = "unlinked-fd write" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, named, "unlinked-fd write") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "pid 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "last named /s/doomed.txt") != null);

    // Without one: no filename is invented. This is the path the trace-close marker and
    // link-by-descriptor take, and it had no test until the renderer moved here.
    const unnamed = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "", .aux = "link-by-descriptor" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, unnamed, "no name recorded for it") != null);
    try std.testing.expect(std.mem.indexOf(u8, unnamed, "last named") == null);

    // A shim that wrote no kind still produces a sentence rather than an empty clause.
    const nokind = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, nokind, "reason not recorded") != null);

    // Target-influenced bytes are defanged by the same choke point the neighbour uses.
    const forged = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x\nUNKNOWN  kill_did_not_land", .aux = "unlinked-fd write" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, forged, "\nUNKNOWN") == null);
}

/// The second half of #484: when an oracle capture exists, the refusal says where it is.
/// The operator in the issue guessed at `gc.auto` twice; the child's `execve` argv —
/// `git maintenance run --auto` — was in `<work>/oracle.txt` the whole time, and nothing
/// said the file existed. `capture` is the strace capture's path or null; the sentence is
/// what the site would have said anyway. One sanitisation for the whole line, here, so
/// the two witnesses' sentences reach the report through the same choke point.
pub fn withOracleCapture(arena: std.mem.Allocator, sentence: []const u8, capture: ?[]const u8, fallback: []const u8) []const u8 {
    const cap = capture orelse return sanitizeForReport(arena, sentence) catch fallback;
    // The capture is of this run in every mode. It said otherwise under `--observe
    // syscalls` for as long as that mode's oracle watched a separate untrapped run, and
    // the sentence had to disclose which run the reader was being pointed at — the
    // agreement line said so and this side did not, which left the two halves of one
    // report disagreeing about what was compared (review, P2). One run, one sentence.
    const joined = std.fmt.allocPrint(arena, "{s}; the oracle's capture at {s} holds the child's own lines, its execve among them", .{ sentence, cap }) catch return fallback;
    return sanitizeForReport(arena, joined) catch fallback;
}

test "foreignTouchDetail names the record, both ends of a two-path op, and defangs a forged line (#484)" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const old = "a process other than the subject performed a state-directory operation during X";
    // No record: the sentence the site used to print, untouched.
    try t.expectEqualStrings(old, foreignTouchDetail(arena, null, "during X", null, old));
    // A one-path op: pid, class, path.
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed write(/s/x) during X",
        foreignTouchDetail(arena, .{ .class = .write, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", null, old),
    );
    // A two-path op names both ends — link as well as rename, since the shim records
    // either when one end is inside the state directory.
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed link(/elsewhere/a -> /s/b) during X",
        foreignTouchDetail(arena, .{ .class = .link, .seq = 1, .pid = 9, .tid = 9, .path = "/elsewhere/a", .aux = "/s/b" }, "during X", null, old),
    );
    // The shim's own marker from a self-armed child: where it was killed, not what it did.
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) was killed at a state-directory operation on /s/x during X",
        foreignTouchDetail(arena, .{ .class = .kill_landed, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", null, old),
    );
    // The marker carries the landed operation's second end when it had one.
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) was killed at a state-directory operation on /s/x -> /s/y during X",
        foreignTouchDetail(arena, .{ .class = .kill_landed, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "/s/y" }, "during X", null, old),
    );
    // A child that names its file after a report line cannot forge one: the newline and
    // the escape come out as visible bytes, on the line they started on.
    const forged = foreignTouchDetail(arena, .{ .class = .open, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x\nUNKNOWN  kill_did_not_land\x1b[1m", .aux = "" }, "during X", null, old);
    try t.expect(std.mem.indexOfScalar(u8, forged, '\n') == null);
    try t.expect(std.mem.indexOfScalar(u8, forged, 0x1b) == null);
    try t.expect(std.mem.indexOf(u8, forged, "\\x0a") != null);
    // With an oracle capture the sentence ends by saying where it is; without one it is
    // the sentence alone, through the same choke point.
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed write(/s/x) during X; the oracle's capture at /w/oracle.txt holds the child's own lines, its execve among them",
        foreignTouchDetail(arena, .{ .class = .write, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", "/w/oracle.txt", old),
    );
    try t.expectEqualStrings("plain; the oracle's capture at /w/oracle.txt holds the child's own lines, its execve among them", withOracleCapture(arena, "plain", "/w/oracle.txt", old));
    try t.expectEqualStrings("plain", withOracleCapture(arena, "plain", null, old));
}

/// The next step for `no_shim_marker`, chosen from the same observation the detail line
/// reports (#274) — the one site where a reason's remedy is decided by the image rather
/// than by the call site's position. A statically linked ELF, a Mach-O not linked
/// against dyld, or one whose code directory names a platform or carries the
/// library-validation or hardened-runtime flag: those are the refused classes README
/// lists, and the step is the wall. A dynamically linked image with nothing on it that
/// this build looks for: the marker's absence has another cause, and the shim is the
/// thing to check. An image that could not be read or resolved says nothing about
/// linkage, so it takes the shim step too — the honest default, not a diagnosis. That reason
/// covers `.not_resolved`, `.unreadable` and `.undecidable`, and stops there: `.unrecognised`
/// means the file WAS read, and what it says is not "nothing about linkage" but "no library
/// goes into this", so that arm names the define instead (#481).
pub fn noShimNext() contract.NextStep {
    return noShimNextFor(rec_image);
}

/// The observation-to-step table above, taking its observation as an argument rather than
/// reading the global — so every arm can be pinned in a test without a recording behind it.
fn noShimNextFor(observed: ?image.Observation) contract.NextStep {
    const obs = observed orelse return .check_shim;
    return switch (obs.facts) {
        .elf => |e| if (e.has_interp) .check_shim else .class_wall,
        // Read in the same order `noShimDetail` reads them, so the step never contradicts
        // the sentence beside it: signing first, and only an unsigned image is judged by
        // its dyld linkage (review caught the reversed order on a signed, non-dyld image —
        // the detail said "another cause", the step said "the wall").
        .macho => |m| blk: {
            const s = m.signing orelse break :blk if (m.dyldlink) .check_shim else .class_wall;
            if (s.platformNamed() or s.libraryValidation() or s.hardenedRuntime()) break :blk .class_wall;
            break :blk .check_shim;
        },
        // Read, and not recognised as an executable image. `image.zig` reaches this from
        // five places: the first four bytes unreadable, a magic none of the three families
        // claims (where a `#!` script lands), an ELF class or data byte outside the two each
        // admits, and a Mach-O slice whose own magic is neither. The other three arms are
        // silent about linkage; this one is not — there is no linkage question, because
        // nothing here is a thing a library is inserted into (#481).
        .unrecognised => .operation_not_an_image,
        .not_resolved, .unreadable, .undecidable => .check_shim,
    };
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
///     (`engine/trace.zig` says so at three call sites). So the first clause reports the
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
pub fn noShimDetail(arena: std.mem.Allocator) []const u8 {
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
pub fn noShimDetailSecondRun(arena: std.mem.Allocator) []const u8 {
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
    // #544 made this one reachable, and the arm's own comment used to say no run could
    // produce it: a thread sets `shim_boundary` through `crossedBoundary` but leaves
    // `needsOracle` false, so a single-process threaded run under fs_usage renders an
    // account where it used to refuse at the flag. Pinned because it can now happen, which
    // is the test the old note applied and answered the other way.
    .{ .what = "the shim recorded a thread, fs_usage read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 3858 } } }, .may_say_single = false, .pins = "excludes some processes by name" },
    // An account of nothing is not an observation that there was nothing: the run
    // refuses `oracle_saw_nothing`, and this used to report a single process (review).
    .{ .what = "the strace capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the fs_usage capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and the empty capture was all there was", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and no oracle ran", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true }, .may_say_single = false, .pins = "no second witness ran" },
    .{ .what = "the shim recorded a boundary and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "nothing accounts for what the other process did" },
    // The two accounts disagree: a failed vfork leaves this shape, and so does a child
    // the oracle lost. Neither is preferred.
    .{ .what = "the shim recorded a boundary and strace saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = false, .pins = "disagree" },
    .{ .what = "the shim recorded a boundary and strace accounted for two children", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 2, .lines = 400 } } }, .may_say_single = false, .pins = "attributed to the subject only" },
    // The oracle's own boundary. A thread emits no pid, so `children` stays 0 and this
    // read as a single process until review measured a CLONE_THREAD capture.
    .{ .what = "strace reported a clone that crosses a boundary the shim missed", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 120 } }, .oracle_boundary = "clone" }, .may_say_single = false, .pins = "crosses a process boundary the shim did not record" },
    .{ .what = "another process performed a kill-point operation (shim)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_foreign_touch = true }, .may_say_single = false, .pins = "no crash-point address" },
    .{ .what = "an id the fs_usage account cannot attribute touched the judged directory", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 1, .lines = 900 } }, .oracle_child_touched = true }, .may_say_single = false, .pins = "knows no process for it" },
    // The same state under a witness that DOES name processes, and the reason these are
    // two rows rather than one: the pair is what holds the distinction. Soften both
    // sentences and this row fails; soften neither and the row above does (#544).
    .{ .what = "another process touched the judged directory (strace)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 1, .lines = 900 } }, .oracle_child_touched = true }, .may_say_single = false, .pins = "a process other than the subject" },
    // The same evidence with the slice admitted (v15). Pinned separately because the two
    // sentences differ in what they claim about the SAME observation, and a table that
    // held only the refusing one would let the admitting one drift into saying the
    // window is the subject's alone.
    .{ .what = "another process's operations were admitted as crash points", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_foreign_touch = true, .children_judged = true }, .may_say_single = false, .pins = "hold crash-point addresses" },
    // A `.shim_hard = "a thread"` case stood here until v16. `hard_boundary` no longer takes
    // `.thread`, so the case pinned a state the engine cannot produce and review struck it.
    // (That cross-reference used to point at the fs_usage arm as the example of the same
    // defect. It no longer applies there: #544 made that arm reachable and it has a case of
    // its own now — a reachability note is only as good as the run that cannot happen.)
    // The two below are what
    // a threaded run renders now: the committed vips report's shape (six threads, one
    // writer, judged, oracle read), and a world that created a thread the recording did
    // not. Both must say "single process" only as scoped to the recording, and both must
    // carry the thread clause, or a reader takes "single process" for single-threaded.
    .{ .what = "a judged run whose only boundary was a thread (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .threads = 6, .writer_threads = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 1262 } } }, .may_say_single = true, .pins = "6 thread(s) created, and 1 thread id(s) of the subject's own process wrote" },
    // #543: the shim recorded NO thread and a writer that is not the initial thread still
    // appeared. `shim_boundary` stays false — a raw `clone` leaves no boundary record
    // either — so before this row the state rendered a bare "single process" and nothing
    // in the table noticed. `may_say_single` is TRUE and that is not a weakening: the run
    // really is one process, and what the sentence must not do is stop there. The bit only
    // asks whether the words appear; the scoping is held by the "a bare single-process
    // claim is scoped the moment anything follows it" test below, and the clause itself by
    // `pins` here. Writing `false` here was the first attempt and the table said so.
    .{ .what = "a thread the shim never recorded creating wrote the judged directory (v16, #543)", .ev = .{ .trace_read = true, .shim_reported = true, .unrecorded_writer_thread = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 900 } } }, .may_say_single = true, .pins = "never recorded creating wrote the judged directory" },
    // `threads` is set from the same records that set `boundary`, so a run with threads
    // has `shim_boundary` — the first version of this case had `threads = 1` and no
    // boundary, a state the engine cannot produce (review, second round). The vips report
    // is this shape: recording judged, a thread in a world too.
    .{ .what = "a thread created in an explored world, on a run that had threads (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_thread_only = true, .threads = 1, .writer_threads = 1 }, .may_say_single = true, .pins = "a thread was created in an explored world" },
    // The refused shape, and the commonest in the sweep (beets): the shim recorded a
    // thread, the run refused before the oracle's capture was read, and the recording
    // clause has to say "a thread" rather than fall into the image-change arm.
    .{ .what = "the shim recorded a thread and the run refused before the oracle was read (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .witness = .{ .unread = .strace }, .threads = 3, .writer_threads = 2 }, .may_say_single = false, .pins = "the shim recorded a thread" },
    // The subject replaced its own image and nothing else crossed a boundary. The shim
    // DID record a boundary (which is why the run needs an oracle), and it claims no
    // second process, so a witness reporting one process agrees with it rather than
    // disagreeing. Before 2026-09-07 this state printed "the two accounts disagree",
    // measured on a judged self-exec run; the replacement is disclosed by the clause
    // the account appends, not by the recording sentence.
    .{ .what = "the subject replaced its own image and strace saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = true, .pins = "single process" },
    // The same boundary with nothing that could compare it. All three are reachable:
    // the first is what an oracle-less self-exec run renders before
    // `boundary_without_oracle` refuses it (a leg in `spike/acceptance.sh` produces it
    // on every suite run), and the other two are a refusal raised between the trace read
    // and the oracle parse, or a capture that came back with no lines. None of them may
    // say "single process" — nothing looked — and none of them may call the subject's own
    // image change another process.
    .{ .what = "the subject replaced its own image and no oracle ran", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1 }, .may_say_single = false, .pins = "replacing its own image and no second witness ran" },
    .{ .what = "the subject replaced its own image and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "replacing its own image; the strace account was not read" },
    .{ .what = "the subject replaced its own image and the capture was empty", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "replacing its own image and the strace capture was empty" },
    .{ .what = "the shim recorded a broken image-replacement chain", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_chain_broken = true, .shim_hard = "an image replacement whose chain of observation broke" }, .may_say_single = false, .pins = "chain of observation broke" },
    // The engine calls refusing here "the safe misreading", so the account must not
    // assert breakage either (review).
    .{ .what = "the shim recorded an image replacement before the subject announced itself", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_hard = "an image replacement before the subject announced itself" }, .may_say_single = false, .pins = "before the subject announced itself" },
    .{ .what = "the shim recorded a process leaving the containment group", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_hard = "a process leaving the containment group" }, .may_say_single = false, .pins = "leaving the containment group" },
    // World-side states. The recording half keeps its words where it earned them, and
    // the qualifier "in the recording" is what stops the sentence opening with a claim
    // about a run that went on to cross a boundary.
    .{ .what = "a world-only boundary after a witnessed single-process recording", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_process_boundary = true, .world_boundary = true, .world_only = true }, .may_say_single = true, .pins = "single process in the recording; a process boundary appeared in an explored world" },
    .{ .what = "a world-only boundary after an unwitnessed recording", .ev = .{ .trace_read = true, .shim_reported = true, .world_process_boundary = true, .world_boundary = true, .world_only = true }, .may_say_single = false, .pins = "a process boundary appeared in an explored world" },
    .{ .what = "a world crossed a boundary the recording had also crossed", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 1, .lines = 400 } }, .world_process_boundary = true, .world_boundary = true }, .may_say_single = false, .pins = "a process boundary appeared in an explored world" },
    // A self-exec target replaces its image in EVERY world, because a world re-runs the
    // operation — so these two are what the measured define renders, not a corner. The
    // first is the shape whose recording half this change fixed; the account said "a
    // process boundary appeared in an explored world" in the same sentence.
    .{ .what = "the subject replaced its own image in an explored world", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true }, .may_say_single = true, .pins = "replaced its own image in an explored world, which runs with no oracle" },
    .{ .what = "the subject replaced its own image in a world the recording never did", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_only = true }, .may_say_single = true, .pins = "replaced its own image in an explored world the recording never did" },
    .{ .what = "a world's child operated on the judged directory", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_process_boundary = true, .world_boundary = true, .world_foreign_touch = true }, .may_say_single = true, .pins = "operated on the judged directory in an explored world" },
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
    // #543. What follows here is a thread the shim could not count, and the scoping
    // condition had to learn about it separately: the existing arm keys on `threads > 0`
    // and this state has `threads == 0` by construction. Without the flag in that
    // condition the sentence opens with a bare "single process" and then discloses a
    // thread — the reading `docs/report-schema.md` says the clause exists to prevent.
    boundary_ev = witnessed;
    boundary_ev.unrecorded_writer_thread = true;
    try std.testing.expect(std.mem.startsWith(u8, boundaryAccount(), "single process in the recording;"));
}

test "noShimNextFor: the step each image observation takes (#481)" {
    const obs = struct {
        fn of(f: image.Facts) image.Observation {
            return .{ .path = "/x", .size = 0, .facts = f };
        }
    }.of;

    // The arm this test exists for. Read, and not recognised as an executable image: the
    // insertion had nothing to go into, and the define is what changes. `image.zig` reaches
    // it from five places — unreadable first four bytes, an unknown magic (where a `#!`
    // script lands), an ELF class or data byte outside the two each admits, and a Mach-O
    // slice whose own magic is neither — and all of them take the same step, because the
    // step is about what the file is not.
    try std.testing.expectEqual(contract.NextStep.operation_not_an_image, noShimNextFor(obs(.unrecognised)));

    // The three that stay on the shim step: each is silent about linkage, so the shim is
    // still the honest thing to look at.
    //
    // `.not_resolved` is the weakest of the three and a known reading problem rather than a
    // settled answer — `docs/target-classes.md`'s chezmoi/gopass row records that the
    // refusal names static linkage only when the operation's first word is a path, and says
    // something else through PATH. A change that moves THIS arm is fixing that; it is not
    // breaking this pin.
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(obs(.not_resolved)));
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(obs(.{ .unreadable = .no_such_file })));
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(obs(.{ .undecidable = .slice_not_unique })));

    // Unchanged, and here so that widening the new arm to the whole switch fails: the two
    // that read real image facts still split the wall from the shim.
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(obs(.{ .elf = .{ .has_interp = true, .class64 = true } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, noShimNextFor(obs(.{ .elf = .{ .has_interp = false, .class64 = true } })));
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(obs(.{ .macho = .{ .dyldlink = true, .signing = null } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, noShimNextFor(obs(.{ .macho = .{ .dyldlink = false, .signing = null } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, noShimNextFor(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = 0, .platform = 1 } } })));

    // No observation at all — the run stopped before the image was read.
    try std.testing.expectEqual(contract.NextStep.check_shim, noShimNextFor(null));
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
        // Two passes over every state: the chain as the state carries it, and the same
        // state with a later image change that escaped. One pass let a contradiction
        // through — measured 2026-09-07 on a real refusal, which said "whose chain of
        // observation broke" and "chain unbroken" in one sentence, and would have
        // satisfied a grep for the disclosure alone.
        for ([_]bool{ false, true }) |force_broken| {
            boundary_ev = c.ev;
            boundary_ev.exec_continuations = 2;
            if (force_broken) boundary_ev.exec_chain_broken = true;
            const got = boundaryAccount();
            if (std.mem.indexOf(u8, got, "image replaced") == null) {
                std.debug.print("\nstate: {s} (broken={})\n  rendered: {s}\n", .{ c.what, boundary_ev.exec_chain_broken, got });
                return error.DisclosureLost;
            }
            // The negative half, BOTH ways. Read off the effective flag rather than the
            // loop variable, so the state that carries it on its own is covered too.
            //
            // One direction alone was measured to be useless: with only the first check
            // here, replacing the branch condition with `if (true)` — every chain
            // reported as escaped — passed the entire suite, because nothing anywhere
            // pinned the unbroken wording. Two mutations, two directions, two reds.
            if (boundary_ev.exec_chain_broken) {
                if (std.mem.indexOf(u8, got, "chain unbroken") != null) {
                    std.debug.print("\nstate: {s}\n  rendered: {s}\n  a chain that broke is called unbroken\n", .{ c.what, got });
                    return error.ChainClaimedUnbroken;
                }
                // The positive half of this direction. Without it the broken wording is
                // pinned by nothing: a mutation emptying that clause keeps "image
                // replaced" (the disclosure) and loses only the escape.
                if (std.mem.indexOf(u8, got, "escaped observation") == null) {
                    std.debug.print("\nstate: {s}\n  rendered: {s}\n  a chain that broke does not say so\n", .{ c.what, got });
                    return error.ChainEscapeNotReported;
                }
            } else {
                if (std.mem.indexOf(u8, got, "escaped observation") != null) {
                    std.debug.print("\nstate: {s}\n  rendered: {s}\n  a chain that held is reported as escaped\n", .{ c.what, got });
                    return error.ChainClaimedEscaped;
                }
                if (std.mem.indexOf(u8, got, "chain unbroken") == null) {
                    std.debug.print("\nstate: {s}\n  rendered: {s}\n  a chain that held does not say so\n", .{ c.what, got });
                    return error.ChainNotClaimedUnbroken;
                }
            }
            applied += 1;
        }
    }
    try std.testing.expect(applied > 40);
}

test "two witnesses that disagree are both reported and neither is preferred" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    // `shim_process_boundary` is what makes this a disagreement: the shim claimed a
    // second PROCESS and the oracle saw none. A same-pid image change claims no such
    // thing and is not a disagreement (its own case is in `boundary_cases`).
    boundary_ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } };
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
    // The world-only leg in spike/acceptance.sh reads the JSON field and requires both
    // of these (named by its predicate, not its line — see boundaryAccount's doc).
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

/// A trace on disk for the tests below, in the shape `writeTraceForTest` builds one in
/// `src/engine/trace.zig` — the same reason it exists there: the decision under test reads
/// a `TraceInfo`, and building one by hand would let a test pass over a shape the reader
/// cannot actually produce.
fn traceFileForTest(tag: []const u8, records: []const contract.Record, fbuf: *[contract.max_path]u8) ![*:0]const u8 {
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pbuf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    const fz = std.fmt.bufPrintZ(fbuf, "{s}/trace.bin", .{dir}) catch unreachable;
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    var hbuf: [contract.header_len]u8 = undefined;
    const hn = try contract.encodeHeader(&hbuf);
    try std.testing.expectEqual(@as(isize, @intCast(hn)), posix.write(fd, &hbuf, hn));
    for (records) |rec| {
        var rbuf: [2 * contract.max_path]u8 = undefined;
        const rn = try contract.encodeRecord(&rbuf, rec);
        try std.testing.expectEqual(@as(isize, @intCast(rn)), posix.write(fd, &rbuf, rn));
    }
    _ = posix.close(fd);
    return fz.ptr;
}

test "an unattributed writer's reason is chosen on what the shim saw" {
    // The reason and the message are decided in different places, and until #544's review
    // only the message had a test — switching this rule off left every unit test green,
    // with `spike/fsusage/acceptance-local.sh` check 7 the only thing holding it and root
    // the only way to run that. Three assertions, one per condition.
    var fbuf: [contract.max_path]u8 = undefined;
    const threaded_path = try traceFileForTest("reason-threaded", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(threaded_path);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var threaded = try engine.readTrace(&tb, std.mem.span(threaded_path));
    defer threaded.deinit();
    try std.testing.expect(threaded.thread_records > 0);
    try std.testing.expect(!threaded.process_boundary);

    var fbuf2: [contract.max_path]u8 = undefined;
    const lone_path = try traceFileForTest("reason-lone", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf2);
    defer _ = posix.unlink(lone_path);
    var tb2 = engine.unboundedBudget(std.testing.allocator);
    var lone = try engine.readTrace(&tb2, std.mem.span(lone_path));
    defer lone.deinit();
    try std.testing.expectEqual(@as(u32, 0), lone.thread_records);

    const names_threads = oracle.Parsed{
        .classes = .empty,
        .names = .empty,
        .lines = .empty,
        .metadata_observed = .empty,
        .mutations = .empty,
        .reaps = .empty,
        .spawns = .empty,
        .subject_tids = .empty,
        .primary_pid = null,
    };
    var names_processes = names_threads;
    names_processes.primary_pid = 7;

    // Threads recorded, no boundary, and a witness that names threads: the writer reads as
    // another thread of this process — the reason the build before #544 gave this class by
    // refusing at the flag.
    try std.testing.expectEqual(contract.UnknownReason.multiple_threads_detected, unattributedWriterReason(threaded, names_threads));
    // A witness that names processes: the id really is a pid, and #405's exit stands.
    try std.testing.expectEqual(contract.UnknownReason.child_touched_state_dir, unattributedWriterReason(threaded, names_processes));
    // No thread record: the raw-fork shape is what is left, whatever the witness names.
    try std.testing.expectEqual(contract.UnknownReason.child_touched_state_dir, unattributedWriterReason(lone, names_threads));
}

test "an id a thread-naming witness cannot attribute is refused as an id, not as a process" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The fs_usage shape, which the v15 fixture below is not: one process, one recorded
    // writer, and a witness that names threads rather than processes. `Parsed.primary_pid`
    // is the whole of the discriminator — the strace reader sets it from a pid and
    // `src/fsusage.zig` never does — and a version of this branch that asked the TRACE
    // instead reworded the strace path too, which the fixture below caught (#544).
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try traceFileForTest("thread-witness", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(fz);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var trace = try engine.readTrace(&tb, std.mem.span(fz));
    defer trace.deinit();

    var subject_tids: std.ArrayList(u64) = .empty;
    try subject_tids.append(arena, 7);
    var mutations: std.ArrayList(oracle.Event) = .empty;
    try mutations.append(arena, .{ .id = 99, .at = 20 });

    const witness = oracle.Parsed{
        .classes = .empty,
        .names = .empty,
        .lines = .empty,
        .metadata_observed = .empty,
        .mutations = mutations,
        .reaps = .empty,
        .spawns = .empty,
        .subject_tids = subject_tids,
        .primary_pid = null,
    };
    const why = childrenMayBeJudged(arena, trace, witness) orelse return error.TestExpectedRefusal;
    // The run is refused either way; what this pins is the sentence. Delete the branch and
    // the old wording comes back, which the first assertion fails on; widen it to every
    // witness and the v15 fixture below fails. Neither direction stays green.
    try std.testing.expect(std.mem.indexOf(u8, why, "id 99 mutated the judged directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, why, "process 99 mutated") == null);
}

test "the two conditions on a run with a writing child (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The slice: subject writes, awaited child writes, subject writes again.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try traceFileForTest("slice-ok", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .rename, .seq = 2, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "/tmp/s/b" },
        .{ .op = .write, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/c", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(fz);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var trace = try engine.readTrace(&tb, std.mem.span(fz));
    defer trace.deinit();

    // The oracle's view of the same run: the parent writes at line 10, the child at 20,
    // the wait returns at 30, the parent writes again at 40. A hand-off.
    const events = struct {
        fn list(a: std.mem.Allocator, items: []const oracle.Event) !std.ArrayList(oracle.Event) {
            var l: std.ArrayList(oracle.Event) = .empty;
            for (items) |e| try l.append(a, e);
            return l;
        }
    };
    const handoff = oracle.Parsed{
        .classes = .empty,
        .names = .empty,
        .lines = .empty,
        .metadata_observed = .empty,
        .mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 8, .at = 20 }, .{ .id = 7, .at = 40 } }),
        .reaps = try events.list(arena, &.{.{ .id = 8, .at = 30 }}),
        // The fork, which is where the window opens — not the child's first write.
        .spawns = try events.list(arena, &.{.{ .id = 8, .at = 15 }}),
        .subject_tids = .empty,
        .primary_pid = 7,
    };
    try std.testing.expectEqual(@as(?[]const u8, null), childrenMayBeJudged(arena, trace, handoff));

    // Condition 2: the parent's second write moves to BEFORE the wait returned. Nothing
    // else changes — same processes, same operations, same reap — so this is the
    // ordering condition on its own.
    var overlap = handoff;
    overlap.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 8, .at = 20 }, .{ .id = 7, .at = 25 } });
    const raced = childrenMayBeJudged(arena, trace, overlap) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, raced, "(pid 8) performed rename(/tmp/s/a)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raced, "process 7 wrote in the judged directory while it was still running") != null);

    // Condition 2's other half: nothing collected the child at all.
    var no_reap = handoff;
    no_reap.reaps = .empty;
    const unreaped = childrenMayBeJudged(arena, trace, no_reap) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unreaped, "(pid 8) performed rename(/tmp/s/a) and nothing waited for it") != null);

    // Condition 1, the direction that catches a child the oracle could not place.
    var oracle_blind = handoff;
    oracle_blind.mutations = try events.list(arena, &.{.{ .id = 7, .at = 10 }});
    const unplaced = childrenMayBeJudged(arena, trace, oracle_blind) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unplaced, "(pid 8) performed rename(/tmp/s/a) and the oracle's account does not place it") != null);

    // Condition 1, the other direction: a writer the shim never recorded — the shape
    // `TOY_SPAWN_WRITES` produces, and the one that would otherwise make the whole
    // question vacuous.
    var unshimmed = handoff;
    // Its write sits AFTER pid 8 was collected and before the parent's, so the ordering
    // condition is satisfied and the only thing wrong with the run is that this writer
    // left no records. A first version of this fixture put it inside pid 8's window and
    // measured the interleaving refusal instead — two defects in one input tell you
    // nothing about which check caught them.
    unshimmed.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 8, .at = 20 }, .{ .id = 99, .at = 35 }, .{ .id = 7, .at = 40 } });
    unshimmed.reaps = try events.list(arena, &.{ .{ .id = 8, .at = 30 }, .{ .id = 99, .at = 37 } });
    const no_records = childrenMayBeJudged(arena, trace, unshimmed) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, no_records, "process 99 mutated the judged directory") != null);

    // Condition 2's window starts at the FORK, not at the child's first write. Same
    // processes, same reap, same operations — only the parent's second write moves back
    // to a point where the child was already running. Nothing orders those two, and the
    // shape is `fork, parent writes, child writes, parent waits`: admitted by a window
    // that began at the child's own first operation, refused by this one.
    var parent_in_window = handoff;
    parent_in_window.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 7, .at = 18 }, .{ .id = 8, .at = 20 } });
    const straddled = childrenMayBeJudged(arena, trace, parent_in_window) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, straddled, "process 7 wrote in the judged directory while it was still running") != null);

    // And a capture that does not show where the writer came from cannot be asked the
    // question at all.
    var no_spawn = handoff;
    no_spawn.spawns = .empty;
    const unplaced_child = childrenMayBeJudged(arena, trace, no_spawn) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unplaced_child, "does not show where process 8 was created") != null);

    // A mode gate stood here: `--observe syscalls` refused every one of these shapes,
    // because its oracle watched a separate untrapped run and nothing accounted for a
    // child in the run the trace came from. The oracle watches the judged run in that mode
    // now, so the function does not take the mode at all and there is nothing left to
    // assert about it here. What proves the two are composed is the Linux acceptance leg
    // that runs `toy_children serial` under `--observe syscalls` and reaches a verdict.
}

test "two children writing before either is collected are refused (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The `rsync` shape, and the one the trace's own record order cannot tell apart from
    // the hand-off above: pid 8 writes, pid 9 writes, pid 8 writes again. Identical in
    // the trace to `parent, child, parent`.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try traceFileForTest("slice-interleaved", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 8, .tid = 8, .path = "/tmp/s/x", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 9, .tid = 9, .path = "/tmp/s/y", .aux = "" },
        .{ .op = .write, .seq = 3, .pid = 8, .tid = 8, .path = "/tmp/s/x", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(fz);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var trace = try engine.readTrace(&tb, std.mem.span(fz));
    defer trace.deinit();

    // Both witnesses agree on who wrote and both children are collected in the end —
    // every part of condition 1 is satisfied, which is what makes this the control that
    // shows condition 2 is the one doing the work here.
    var l_mut: std.ArrayList(oracle.Event) = .empty;
    for ([_]oracle.Event{ .{ .id = 8, .at = 10 }, .{ .id = 9, .at = 11 }, .{ .id = 8, .at = 12 } }) |e| try l_mut.append(arena, e);
    var l_reap: std.ArrayList(oracle.Event) = .empty;
    for ([_]oracle.Event{ .{ .id = 8, .at = 20 }, .{ .id = 9, .at = 21 } }) |e| try l_reap.append(arena, e);
    var l_spawn: std.ArrayList(oracle.Event) = .empty;
    for ([_]oracle.Event{ .{ .id = 8, .at = 1 }, .{ .id = 9, .at = 2 } }) |e| try l_spawn.append(arena, e);
    const racing = oracle.Parsed{
        .classes = .empty,
        .names = .empty,
        .lines = .empty,
        .metadata_observed = .empty,
        .mutations = l_mut,
        .reaps = l_reap,
        .spawns = l_spawn,
        .subject_tids = .empty,
        .primary_pid = 7,
    };
    const why = childrenMayBeJudged(arena, trace, racing) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, why, "(pid 8) performed write(/tmp/s/x)") != null);
    try std.testing.expect(std.mem.indexOf(u8, why, "process 9 wrote in the judged directory while it was still running") != null);
}

test "preflight's second run names a thread as a thread, not as an image change (v16)" {
    // The shape review measured as wrong: run B creates a thread and nothing else, and
    // the account said "the subject replacing its own image". The control is a fork,
    // which is the process boundary the same branch has always named.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try traceFileForTest("secondrun-thread", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(fz);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var threaded = try engine.readTrace(&tb, std.mem.span(fz));
    defer threaded.deinit();
    try std.testing.expectEqualStrings("a thread", secondRunLabel(threaded).?);

    var fbuf2: [contract.max_path]u8 = undefined;
    const fz2 = try traceFileForTest("secondrun-fork", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf2);
    defer _ = posix.unlink(fz2);
    var tb2 = engine.unboundedBudget(std.testing.allocator);
    var forked = try engine.readTrace(&tb2, std.mem.span(fz2));
    defer forked.deinit();
    try std.testing.expectEqualStrings("a process boundary", secondRunLabel(forked).?);

    // And nothing at all reads as nothing.
    var fbuf3: [contract.max_path]u8 = undefined;
    const fz3 = try traceFileForTest("secondrun-plain", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf3);
    defer _ = posix.unlink(fz3);
    var tb3 = engine.unboundedBudget(std.testing.allocator);
    var plain = try engine.readTrace(&tb3, std.mem.span(fz3));
    defer plain.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), secondRunLabel(plain));
}
