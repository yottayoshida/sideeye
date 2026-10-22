const std = @import("std");
const supervise = @import("supervise.zig");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const image = @import("image.zig");
const oracle = @import("oracle.zig");
const defang = @import("defang.zig");
const sanitizeForReport = defang.sanitizeForReport;
const textShown = defang.textShown;

/// started. Read there and not at the refusal, because after the child has exited the
/// same name may resolve somewhere else entirely; see `image.zig`'s header for why a
/// match is still never reported as identity. Null on every path that never spawned.
pub var rec_image: ?image.Observation = null;

pub var rec_end_deferred: ?posix.Term = null;

pub fn defersRecordingEnd(term: posix.Term, observed: ?image.Observation) bool {
    switch (term) {
        // Not on an exit status: 126 is the engine's fork stub, whose child never ran an image
        // that could have carried the marker.
        .exited => return false,
        .signaled, .unknown => {},
    }
    const obs = observed orelse return false;
    return switch (obs.facts) {
        .macho => |m| if (m.signing) |s| s.platformNamed() else false,
        else => false,
    };
}

pub var boundary_ev: BoundaryEvidence = .{};
pub var observe_mode: contract.ObserveMode = .wrappers;

/// the engine, which loads no shim and counts from outside the target. The account has the
/// shim's shape in both modes — the supervising engine writes the shim's records — so every
/// sentence that says "the shim recorded" reads its subject here rather than assuming one.
pub fn recorder() []const u8 {
    return if (observe_mode == .supervised) "the supervising engine" else "the shim";
}

pub const BoundaryEvidence = struct {
    witness: Witness = .none,
    trace_read: bool = false,
    shim_reported: bool = false,
    shim_boundary: bool = false,
    shim_hard: ?[]const u8 = null,
    shim_foreign_touch: bool = false,
    exec_continuations: u32 = 0,
    /// A subject exec whose chain did NOT survive. Carried beside the count rather than
    /// derived from `shim_hard`, which names the FIRST hard boundary only: a thread
    /// recorded before the exec takes that string, and the chain's state would vanish
    /// from the account (a shape this repository has on record — the joplin preflight
    /// transcripts print a thread refusal beside an image-replacement clause).
    exec_chain_broken: bool = false,
    /// own image. Only the account reads it; `shim_boundary` (which includes image
    /// changes) is what the oracle requirement keys on and is unchanged.
    shim_process_boundary: bool = false,
    oracle_child_touched: bool = false,
    children_judged: bool = false,
    oracle_boundary: ?[]const u8 = null,
    threads: u32 = 0,
    writer_threads: u32 = 0,
    thread_turns: u32 = 0,
    thread_joins: u32 = 0,
    thread_detaches: u32 = 0,
    unrecorded_writer_thread: bool = false,
    shim_thread_only: bool = false,
    /// held judges it. Neither "a process boundary" nor an image change may be said of it.
    shim_subject_detached: bool = false,
    world_thread_only: bool = false,
    world_subject_detached: bool = false,
    world_process_boundary: bool = false,
    world_boundary: bool = false,
    world_only: bool = false,
    world_foreign_touch: bool = false,
    second_run: ?[]const u8 = null,

    pub const Kind = enum {
        strace,
        fs_usage,

        pub fn name(self: Kind) []const u8 {
            return @tagName(self);
        }
    };

    const Witness = union(enum) {
        none,
        unread: Kind,
        read: struct { kind: Kind, children: usize, lines: usize },
    };
};

/// Rendered fresh on each call; single-threaded, and no format string reads it twice.
var boundary_buf: [1280]u8 = undefined;

/// Three substrings are load-bearing for checks in `spike/acceptance.sh` that hold this
/// code to its behaviour: the world-only leg requires "refused" and "explored world" in
/// the account and forbids the pre-#169 "observed for quiescence only", and the
/// self-exec legs require "image replaced" in a FAIL that carried an image change.
pub fn boundaryAccount() []const u8 {
    var scratch: [512]u8 = undefined;
    const world_proc = boundary_ev.world_process_boundary;
    const world: []const u8 = if (boundary_ev.world_foreign_touch and boundary_ev.children_judged)
        "; a process other than the subject operated on the judged directory in an explored world too — the class the recording admitted, which a world inherits rather than re-deciding because it runs without an oracle"
    else if (boundary_ev.world_foreign_touch)
        "; a process other than the subject operated on the judged directory in an explored world"
    else if (boundary_ev.world_only and world_proc)
        "; a process boundary appeared in an explored world — refused: nothing accounts for what it did"
    else if (boundary_ev.world_only and boundary_ev.world_subject_detached)
        "; the subject left its process group in an explored world the recording never did — refused: nothing accounts for what followed"
    else if (boundary_ev.world_only)
        "; the subject replaced its own image in an explored world the recording never did — refused: the chain there is unaccounted for"
    else if (boundary_ev.world_boundary and world_proc)
        "; a process boundary appeared in an explored world, which runs with no oracle"
    else if (boundary_ev.world_boundary and boundary_ev.world_thread_only)
        "; a thread was created in an explored world"
    else if (boundary_ev.world_boundary and boundary_ev.world_subject_detached)
        "; the subject left its process group in an explored world, which runs with no oracle"
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
    // to prevent. Appended through this one variable rather than at a return site: the
    // three returns below all interpolate `{threads}`, and a clause added at one of them
    // would vanish on the other two. That has happened here before, to the world clause.
    var thread_buf: [360]u8 = undefined;
    // The counts of hand-overs, joins and detaches are left out rather than printed as
    // zeros a reader would take for measured absences.
    const threads: []const u8 = if (boundary_ev.threads > 0 and observe_mode == .supervised)
        std.fmt.bufPrint(&thread_buf, "; the supervising engine recorded {d} thread(s) created, and {d} thread id(s) of the subject's own process wrote the judged directory (under --observe supervised no join is recorded, nor which thread a creation made, so writes from two or more threads of one process refuse)", .{ boundary_ev.threads, boundary_ev.writer_threads }) catch
            "; the supervising engine recorded threads created"
    else if (boundary_ev.threads > 0)
        std.fmt.bufPrint(&thread_buf, "; the shim recorded {d} thread(s) created, and {d} thread id(s) of the subject's own process wrote the judged directory; {d} hand-over(s) between threads in causal order, {d} join(s) and {d} detach(es) recorded (v18: writes ordered by a recorded creation or join are judged, unordered ones refuse)", .{ boundary_ev.threads, boundary_ev.writer_threads, boundary_ev.thread_turns, boundary_ev.thread_joins, boundary_ev.thread_detaches }) catch
            "; the shim recorded threads created (v16)"
    else if (boundary_ev.unrecorded_writer_thread and observe_mode == .supervised)
        "; a thread the supervising engine never recorded creating wrote the judged directory, so its count of threads is a floor and no witness is held against it (v16, #543)"
    else if (boundary_ev.unrecorded_writer_thread)
        "; a thread the shim never recorded creating wrote the judged directory, so its count of threads is a floor and no witness is held against it (v16, #543)"
    else
        "";
    if (boundary_ev.exec_continuations > 0) {
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

/// (measured), so ADR 0031 §2a rules that a boundary is never tolerated under it. One
/// constant because two sites need the same sentence — the no-boundary arm below, and
/// the image-change arm above it, which must not borrow strace's stronger wording.
const fs_usage_silence = "no other process mutated the judged directory in the fs_usage capture; fs_usage excludes some processes by name, so a child that execs one of them would not appear (ADR 0031)";

fn boundaryRecordingClause(scratch: []u8) []const u8 {
    const ev = boundary_ev;
    if (!ev.trace_read)
        return if (observe_mode == .supervised)
            "not established: this run was refused before the supervising engine's account of it was read"
        else
            "not established: this run was refused before the shim's account of it was read";
    if (!ev.shim_reported)
        return if (observe_mode == .supervised)
            "not established: the supervising engine's account never opened in this run, so nothing observed process boundaries"
        else
            "not established: the shim never announced itself in this run, so nothing observed process boundaries";
    if (ev.shim_foreign_touch or ev.oracle_child_touched)
        return if (ev.children_judged)
            "a process other than the subject operated on the judged directory, and those operations hold crash-point addresses: no two processes' operations interleaved and every writing child was reaped (contract v15). An explored world does not re-check that — it runs without an oracle — so it inherits this finding, and what each world does check is that the operations before its crash point are the ones the recording numbered"
        else if (!ev.shim_foreign_touch and switch (ev.witness) {
            .read => |r| r.kind == .fs_usage,
            else => false,
        })
            "an id other than the subject's operated on the judged directory; this witness names a thread and knows no process for it, so whether that id is another process or a thread the shim never recorded is not established here. Its operations have no crash-point address"
        else
            "a process other than the subject operated on the judged directory; its operations have no crash-point address";
    if (ev.shim_hard) |name|
        return std.fmt.bufPrint(scratch, "{s} recorded {s}", .{ recorder(), name }) catch "a boundary was recorded that is refused by name";
    // The oracle's own boundary, which the child count cannot carry: a thread emits no
    // pid, so `children` stays 0 and the witness matrix below would read this as an
    // observation of a single process. Measured by review on a `CLONE_THREAD` capture.
    if (ev.oracle_boundary) |name| return switch (ev.witness) {
        .read => |r| std.fmt.bufPrint(scratch, "the {s} account reports {s}, which crosses a process boundary {s} did not record", .{ r.kind.name(), name, recorder() }) catch
            "the oracle's account reports a call that crosses a process boundary",
        else => "the oracle's account reports a call that crosses a process boundary",
    };
    // What the shim's boundary record actually was, in the account's own words. A
    // subject replacing its own image is a boundary for every purpose the engine keys
    // on `shim_boundary` — the oracle requirement and the quiescence sampling among
    // them — and it is NOT another process, so the four arms below say which they are
    // talking about rather than calling both "a process boundary". Before 2026-09-07
    const what: []const u8 = if (ev.shim_process_boundary)
        "a process boundary"
    else if (ev.shim_thread_only)
        "a thread"
    else if (ev.shim_subject_detached)
        "the subject leaving its process group"
    else
        "the subject replacing its own image";
    var recorded_buf: [96]u8 = undefined;
    const recorded: []const u8 = std.fmt.bufPrint(&recorded_buf, "{s} recorded {s}", .{ recorder(), what }) catch "a boundary was recorded";
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
            "a boundary was recorded and no second witness ran",
        .unread => |k| if (ev.shim_process_boundary)
            std.fmt.bufPrint(scratch, "{s}; the {s} account was not read, so nothing accounts for what the other process did", .{ recorded, k.name() }) catch
                "a process boundary was recorded and the oracle's account was not read"
        else
            std.fmt.bufPrint(scratch, "{s}; the {s} account was not read", .{ recorded, k.name() }) catch
                "the subject was recorded replacing its own image and the oracle's account was not read",
        .read => |r| if (r.children > 0)
            // Kept verbatim from before this field became evidence: a FAIL's reader has
            // to see that the window is attributed to the subject alone.
            toleratedChildrenClause(scratch, r.children)
        else if (ev.shim_process_boundary)
            std.fmt.bufPrint(scratch, "{s} recorded a process boundary and {s} observed no other process; the two accounts disagree and this run does not resolve them", .{ recorder(), r.kind.name() }) catch
                "the two accounts disagree about whether a process boundary happened"
        else switch (r.kind) {
            .strace => "single process",
            .fs_usage => fs_usage_silence,
        },
    };
    return switch (ev.witness) {
        .none => if (observe_mode == .supervised)
            "not established: no boundary was recorded — the supervising engine is notified of clone, clone3, fork, vfork, the exec family, setsid and setpgid at the syscall boundary, from outside the target — but no second witness ran"
        else
            "not established: no boundary was recorded, but the shim sees only libc's own entry points (fork, vfork, posix_spawn, the exec family, pthread_create, setsid, setpgid) — a child created through a raw syscall would not appear here — and no second witness ran",
        .unread => |k| std.fmt.bufPrint(scratch, "not established: no boundary was recorded by the {s}, and the {s} account was not read", .{ if (observe_mode == .supervised) "supervising engine" else "shim", k.name() }) catch
            "not established: no boundary was recorded, and the oracle's account was not read",
        .read => |r| switch (r.kind) {
            // strace follows children (`-f`), so no other pid in its account is an
            // observation that there was none.
            .strace => if (r.children > 0)
                toleratedChildrenClause(scratch, r.children)
            else
                "single process",
            .fs_usage => fs_usage_silence,
        },
    };
}

pub const ChildWall = enum {
    /// **The shim being there is what makes the step safe to give**, not a detail of the
    /// measurement. Under that mode a filter is inherited across `exec` while the `exec`
    /// resets the handler that makes it survivable, so an image the shim cannot be loaded
    /// into dies at its first state-changing call (`src/cli.zig`, measured) — and a child
    /// whose death the target survives can leave the run judged **without that child's
    /// work** (`docs/report-schema.md`, case 4, not measured). ADR 0069 declined this step
    /// for that reason and named this site; the reason still holds for the writer with no
    /// records, which is why it is not this member.
    shimmed_writer_unnumbered,
    not_the_modes_wall,
};

pub const ChildRefusal = struct {
    detail: []const u8,
    wall: ChildWall,
};

/// The step for `child_touched_state_dir` (#634), shaped after `missedOperationNext` (#599,
/// ADR 0069) and guarded the same way: the mode exists on Linux only, and naming it to a run
/// already in it would send the reader in a circle. Only the wall the mode was measured to
/// cross gets it; the rest keep the step they had, because a step that cannot work is worse
/// than one that only points at the class.
pub fn childTouchedNext(wall: ChildWall, observe: contract.ObserveMode, on_linux: bool) contract.NextStep {
    return switch (wall) {
        .shimmed_writer_unnumbered => if (observe == .wrappers and on_linux) .observe_syscalls else .unwrap_or_class_wall,
        .not_the_modes_wall => .unwrap_or_class_wall,
    };
}

pub fn unattributedWriterReason(trace: engine.TraceInfo, parsed: oracle.Parsed) contract.UnknownReason {
    if (parsed.primary_pid == null and trace.thread_records > 0 and !trace.process_boundary)
        return .multiple_threads_detected;
    return .child_touched_state_dir;
}

pub fn childrenMayBeJudged(
    arena: std.mem.Allocator,
    trace: engine.TraceInfo,
    parsed: oracle.Parsed,
) ?ChildRefusal {
    if (!trace.foreign_kill_point and !parsed.childTouched()) return null;

    const primary = trace.primary_pid orelse return .{ .wall = .not_the_modes_wall, .detail = "the trace holds state-directory operations but no process announced itself, so none of them can be attributed" };

    // compared. Written this way for cost as much as for shape: the first version asked
    // each question inside a loop over every record and every mutation, which is quadratic
    // in exactly the runs this version exists to judge — a target with many operations in
    // many children is the one that pays. One writer per process, and the comparisons are
    var shim_writers: std.ArrayList(engine.Op) = .empty;
    for (trace.ops.items) |op| {
        if (!op.class.isKillPoint() or op.pid == primary) continue;
        var seen = false;
        for (shim_writers.items) |w| {
            if (w.pid == op.pid) seen = true;
        }
        if (!seen) shim_writers.append(arena, op) catch
            return .{ .wall = .not_the_modes_wall, .detail = "out of memory while reading which processes wrote in the judged directory" };
    }
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
            return .{ .wall = .not_the_modes_wall, .detail = "out of memory while reading which processes the oracle saw write" };
    }

    for (shim_writers.items) |w| {
        var in_oracle = false;
        for (oracle_writers.items) |o| {
            if (o.id == w.pid) in_oracle = true;
        }
        if (!in_oracle)
            return .{ .wall = .not_the_modes_wall, .detail = std.fmt.allocPrint(
                arena,
                "a process other than the subject (pid {d}) performed {s}({s}) and the oracle's account does not place it. That reader resolves a relative path against the subject's working directory, so a child that changed its own is invisible to it — and with only one witness for those operations, nothing can check that nobody else wrote while they ran",
                .{ w.pid, w.class.name(), w.path },
            ) catch "a process recorded state-directory operations the oracle's account does not place" };
    }

    for (oracle_writers.items) |w| {
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
            // Is the shim in the image this writer is running NOW? The question is about
            // the image, not the pid (#634, ADR 0076). `exec` is recorded by the image that
            // calls it, before the call — so an `exec` from this pid says only that some
            // image in it called one, and the next image may be the static or env-stripped
            // one `--observe syscalls` kills. `shim_ready` is written by a shim that has
            // initialised, so the shim is here iff the LAST of the two, in trace order, is
            // a `shim_ready`. lbdb's child records `exec` then `shim_ready`, and a child
            var shim_in_writer_image = false;
            for (trace.ops.items) |op| {
                if (op.pid != w.id) continue;
                switch (op.class) {
                    .shim_ready => shim_in_writer_image = true,
                    .exec => shim_in_writer_image = false,
                    else => {},
                }
            }
            if (parsed.primary_pid == null)
                return .{ .wall = .not_the_modes_wall, .detail = std.fmt.allocPrint(
                    arena,
                    "id {d} mutated the judged directory in the oracle's account and recorded nothing of its own. This witness names a thread and knows no process for it, so this is either a process that never loaded the shim or a thread whose operations went around the shim's wrappers; calling it a process would assert the half this run cannot see. Either way its operations hold no crash-point number and the sequence the crash points were read from is incomplete",
                    .{w.id},
                ) catch "an id mutated the judged directory and the witness cannot say whether it is a process" };
            return .{
                .wall = if (shim_in_writer_image) .shimmed_writer_unnumbered else .not_the_modes_wall,
                .detail = std.fmt.allocPrint(
                    arena,
                    "process {d} mutated the judged directory in the oracle's account and recorded nothing of its own, so its operations hold no crash-point number and the sequence the crash points were read from is incomplete. {s}",
                    // Checked first (#217, review): the supervising engine writes a start record
                    // at every exec, so `shim_in_writer_image` holds there too, and the filter is
                    // inherited by every process the target starts — which is all strace follows.
                    .{ w.id, if (observe_mode == .supervised)
                        "Under --observe supervised every process the target starts inherits the engine's filter, so this one wrote the judged directory some way the filter does not watch — through a mapped file, say — or its calls were not counted"
                    else if (shim_in_writer_image)
                        "Its shim announced itself and recorded no operation, so its writes went around the interposed entry points — a buffered stream flushed inside libc does that"
                    else
                        "A child that never loaded the shim — an emptied environment, a static image — is seen only by the oracle" },
                ) catch "a process mutated the judged directory without recording anything of its own",
            };
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
        const from = window_from orelse return .{ .wall = .not_the_modes_wall, .detail = std.fmt.allocPrint(
            arena,
            "the oracle's capture does not show where process {d} was created, and it wrote in the judged directory: without that point there is no window in which to ask whether anything else wrote while it ran",
            .{w.id},
        ) catch "the capture does not show where a writing process was created" };

        var reaped_at: ?usize = null;
        for (parsed.reaps.items) |r| {
            if (r.id == w.id and r.at >= w.at) {
                reaped_at = r.at;
                break;
            }
        }
        const until = reaped_at orelse return .{ .wall = .not_the_modes_wall, .detail = std.fmt.allocPrint(
            arena,
            "a process other than the subject (pid {d}) performed {s}({s}) and nothing waited for it afterwards: its operations and the subject's are ordered by the scheduler rather than by a join, so the sequence they were numbered in is one sample rather than the order the program imposes",
            .{ w.id, if (recorded) |o| o.class.name() else "an operation", if (recorded) |o| o.path else "" },
        ) catch "nothing waited for a process that wrote in the judged directory" };

        for (parsed.mutations.items) |other| {
            if (other.id == w.id) continue;
            if (other.at > from and other.at < until)
                return .{ .wall = .not_the_modes_wall, .detail = std.fmt.allocPrint(
                    arena,
                    "a process other than the subject (pid {d}) performed {s}({s}), and process {d} wrote in the judged directory while it was still running — nothing had collected it yet. Two processes writing at once are ordered by the scheduler, so the sequence they were numbered in is the one this run happened to produce and a crash point would not name the same operation on the next. A run whose writers take turns is judged; one whose writers overlap is not",
                    .{
                        w.id,
                        if (recorded) |o| o.class.name() else "an operation",
                        if (recorded) |o| o.path else "",
                        other.id,
                    },
                ) catch "two processes wrote in the judged directory at the same time" };
        }
    }

    return null;
}

pub fn foreignTouchDetail(arena: std.mem.Allocator, first: ?engine.Op, when: []const u8, oracle_capture: ?[]const u8, fallback: []const u8) []const u8 {
    const op = first orelse return fallback;
    const composed = if (op.class == .kill_landed)
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

/// the same overclaim those clauses had stopped making the day before. An unbroken
/// self-exec chain leaves `hard_boundary` null, so it reaches the second branch rather than
/// the `.exec` arm, and calling it "a process boundary" would be the overclaim from the
/// other direction. `detach_refused` is whether run B's detach refuses: one run B's own cgroup
pub fn secondRunLabel(trace: engine.TraceInfo, detach_refused: bool) ?[]const u8 {
    if (trace.hard_boundary) |b| switch (b) {
        .exec => return "an image replacement",
        else => {},
    };
    if (detach_refused) return "a process leaving the containment group";
    if (trace.crossedBoundary()) {
        if (trace.crossedProcessBoundary()) return "a process boundary";
        if (trace.boundary == .thread and trace.exec_continuations == 0) return "a thread";
        if (trace.subject_detached) return "the subject leaving its process group";
        return "the subject replacing its own image";
    }
    return null;
}

pub fn threadDetail(arena: std.mem.Allocator, first: ?engine.Op, second: engine.Op, first_detached: bool, where: []const u8) []const u8 {
    const fallback = if (observe_mode == .supervised)
        "two threads of one process wrote in the judged directory, and under --observe supervised no join is recorded, nor which thread a creation made, so no crash-point address in this run can be trusted"
    else
        "two threads of one process wrote in the judged directory with no creation or join the shim recorded ordering them, so no crash-point address in this run can be trusted";
    const first_clause = if (first) |f|
        std.fmt.allocPrint(arena, "tid {d} performed {s}({s}) and ", .{ f.tid, f.class.name(), f.path }) catch return fallback
    else
        "";
    const detached_clause: []const u8 = if (first_detached and first != null)
        std.fmt.allocPrint(arena, "; tid {d} was detached, so no join could order it", .{first.?.tid}) catch return fallback
    else
        "";
    // The rule the sentence ends on is the mode's own (#217). Under `--observe supervised`
    // the engine is told a thread was created and by whom, never which thread was made, and
    // no join reaches it, so no recorded edge orders two threads' writes: a second writing
    // thread refuses however the target orders it, and the v18 sentence — "is judged" when
    // creations and joins order the writes — would send a reader to add a join that this
    // mode cannot see.
    const rule: []const u8 = if (observe_mode == .supervised)
        "Nothing the supervising engine recorded orders the first of those before the second: under --observe supervised no join is recorded, nor which thread a creation made, so however the target orders them this run cannot establish that a crash point names the same operation on the next run, and writes from two or more threads of one process refuse. The modes that load a shim, which records creations and joins, judge a process whose threads' writes they order (v18)"
    else
        "No thread creation or join the shim recorded orders the first of those before the second";
    const tail: []const u8 = if (observe_mode == .supervised)
        ""
    else
        ", so their order is the scheduler's choice on this run, the sequence they were numbered in is the one it happened to produce, and a crash point would not name the same operation on the next. A process whose threads' writes are all ordered by the creations and joins the shim recorded is judged, however many threads it created (v18)";
    const composed = std.fmt.allocPrint(
        arena,
        "two threads of process {d} wrote in the judged directory{s}: {s}tid {d} performed {s}({s}). {s}{s}{s}",
        .{ second.pid, where, first_clause, second.tid, second.class.name(), second.path, rule, if (observe_mode == .supervised) "" else detached_clause, tail },
    ) catch return fallback;
    return sanitizeForReport(arena, composed) catch fallback;
}

/// explored world", " in the second observed run". It is interpolated into the composed
/// sentence rather than passed as the fallback, because the fallback is used ONLY when
/// there is no record at all: a caller that put its location there would see it dropped
/// on every run that actually has one, and all three sites would report the recording
/// run's wording. Measured: the world and run-B legs asked for their own wording and got
pub fn unresolvedDetail(arena: std.mem.Allocator, first: ?engine.Op, where: []const u8, fallback: []const u8) []const u8 {
    const op = first orelse return fallback;
    // could number anything. The general sentence's "could not be determined" would be false.
    if (std.mem.eql(u8, op.aux, contract.unresolved_kind.before_constructor)) {
        const on = if (op.path.len > 0)
            std.fmt.allocPrint(arena, "on {s}", .{op.path}) catch return fallback
        else
            "whose path could not be read";
        const composed = std.fmt.allocPrint(
            arena,
            "a write-capable call {s} was made{s} before the shim's constructor had run (pid {d}) — from another shared library's constructor, say, which the loader can run first — so it was not numbered and cannot be placed among the crash points",
            .{ on, where, op.pid },
        ) catch return fallback;
        return sanitizeForReport(arena, composed) catch fallback;
    }
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

    try std.testing.expectEqualStrings("FALLBACK", unresolvedDetail(arena, null, " in an explored world", "FALLBACK"));
}

test "unresolvedDetail says a call before the constructor was unnumbered, not unresolved (#753)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const op: engine.Op = .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/lib.db", .aux = contract.unresolved_kind.before_constructor };
    const d = unresolvedDetail(arena, op, "", "FALLBACK");
    try std.testing.expect(std.mem.indexOf(u8, d, "on /s/lib.db") != null);
    try std.testing.expect(std.mem.indexOf(u8, d, "before the shim's constructor had run") != null);
    try std.testing.expect(std.mem.indexOf(u8, d, "could not be determined") == null);
    var bare = op;
    bare.path = "";
    const b = unresolvedDetail(arena, bare, " in an explored world", "FALLBACK");
    try std.testing.expect(std.mem.indexOf(u8, b, "whose path could not be read was made in an explored world") != null);
}

test "unresolvedDetail names the kind and pid, and only claims a name when there is one (#485)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fb = "an operation was observed whose path could not be determined";

    try std.testing.expectEqualStrings(fb, unresolvedDetail(arena, null, "", fb));

    const named = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/doomed.txt", .aux = "unlinked-fd write" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, named, "unlinked-fd write") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "pid 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "last named /s/doomed.txt") != null);

    const unnamed = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "", .aux = "link-by-descriptor" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, unnamed, "no name recorded for it") != null);
    try std.testing.expect(std.mem.indexOf(u8, unnamed, "last named") == null);

    const nokind = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, nokind, "reason not recorded") != null);

    const forged = unresolvedDetail(arena, .{ .class = .unresolved, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x\nUNKNOWN  kill_did_not_land", .aux = "unlinked-fd write" }, "", fb);
    try std.testing.expect(std.mem.indexOf(u8, forged, "\nUNKNOWN") == null);
}

pub fn withOracleCapture(arena: std.mem.Allocator, sentence: []const u8, capture: ?[]const u8, fallback: []const u8) []const u8 {
    const cap = capture orelse return sanitizeForReport(arena, sentence) catch fallback;
    const joined = std.fmt.allocPrint(arena, "{s}; the oracle's capture at {s} holds the child's own lines, its execve among them", .{ sentence, cap }) catch return fallback;
    return sanitizeForReport(arena, joined) catch fallback;
}

test "the step for child_touched_state_dir follows the wall, not the refusal's name (#634)" {
    try std.testing.expectEqual(contract.NextStep.observe_syscalls, childTouchedNext(.shimmed_writer_unnumbered, .wrappers, true));
    try std.testing.expectEqual(contract.NextStep.unwrap_or_class_wall, childTouchedNext(.shimmed_writer_unnumbered, .syscalls, true));
    try std.testing.expectEqual(contract.NextStep.unwrap_or_class_wall, childTouchedNext(.shimmed_writer_unnumbered, .wrappers, false));
    for ([_]contract.ObserveMode{ .wrappers, .syscalls }) |m| {
        for ([_]bool{ true, false }) |linux| {
            try std.testing.expectEqual(contract.NextStep.unwrap_or_class_wall, childTouchedNext(.not_the_modes_wall, m, linux));
        }
    }
    try std.testing.expectEqual(@as(usize, 2), std.meta.fieldNames(ChildWall).len);
}

test "foreignTouchDetail names the record, both ends of a two-path op, and defangs a forged line (#484)" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const old = "a process other than the subject performed a state-directory operation during X";
    try t.expectEqualStrings(old, foreignTouchDetail(arena, null, "during X", null, old));
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed write(/s/x) during X",
        foreignTouchDetail(arena, .{ .class = .write, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", null, old),
    );
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed link(/elsewhere/a -> /s/b) during X",
        foreignTouchDetail(arena, .{ .class = .link, .seq = 1, .pid = 9, .tid = 9, .path = "/elsewhere/a", .aux = "/s/b" }, "during X", null, old),
    );
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) was killed at a state-directory operation on /s/x during X",
        foreignTouchDetail(arena, .{ .class = .kill_landed, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", null, old),
    );
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) was killed at a state-directory operation on /s/x -> /s/y during X",
        foreignTouchDetail(arena, .{ .class = .kill_landed, .seq = 0, .pid = 9, .tid = 9, .path = "/s/x", .aux = "/s/y" }, "during X", null, old),
    );
    const forged = foreignTouchDetail(arena, .{ .class = .open, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x\nUNKNOWN  kill_did_not_land\x1b[1m", .aux = "" }, "during X", null, old);
    try t.expect(std.mem.indexOfScalar(u8, forged, '\n') == null);
    try t.expect(std.mem.indexOfScalar(u8, forged, 0x1b) == null);
    try t.expect(std.mem.indexOf(u8, forged, "\\x0a") != null);
    try t.expectEqualStrings(
        "a process other than the subject (pid 9) performed write(/s/x) during X; the oracle's capture at /w/oracle.txt holds the child's own lines, its execve among them",
        foreignTouchDetail(arena, .{ .class = .write, .seq = 1, .pid = 9, .tid = 9, .path = "/s/x", .aux = "" }, "during X", "/w/oracle.txt", old),
    );
    try t.expectEqualStrings("plain; the oracle's capture at /w/oracle.txt holds the child's own lines, its execve among them", withOracleCapture(arena, "plain", "/w/oracle.txt", old));
    try t.expectEqualStrings("plain", withOracleCapture(arena, "plain", null, old));
}

pub fn noShimNext() contract.NextStep {
    return noShimNextFor(rec_image, observe_mode, supervise.available);
}

/// mark, an ABI it cannot read — and off Linux the flag answers `platform_unsupported`. The caller
/// passes whether this is Linux, not whether the kernel offers the trap: asking the kernel is a
/// `seccomp(2)` call, which the default mode had never issued, on a refusal path, and an outer
/// filter that kills on `seccomp` would end the engine before the report was written (review). A
pub fn missedOperationNext(observe: contract.ObserveMode, on_linux: bool) contract.NextStep {
    return if (observe == .wrappers and on_linux) .observe_syscalls else .class_wall;
}

pub fn fixDefineUnder(observe: contract.ObserveMode) contract.NextStep {
    return if (observe == .syscalls) .syscalls_may_have_killed else .fix_define;
}

pub fn recordingEndedStep(observe: contract.ObserveMode, exited: bool) contract.NextStep {
    if (observe == .syscalls) return .syscalls_may_have_killed;
    return if (exited) .run_then_expect_status else .run_by_hand_signalled;
}

pub fn threadsStep(observe: contract.ObserveMode) contract.NextStep {
    return if (observe == .supervised) .threads_supervised else .threads_limit;
}

test "the recording run's end and the threads refusal choose their steps by mode (#710)" {
    try std.testing.expectEqual(contract.NextStep.run_then_expect_status, recordingEndedStep(.wrappers, true));
    try std.testing.expectEqual(contract.NextStep.run_by_hand_signalled, recordingEndedStep(.wrappers, false));
    try std.testing.expectEqual(contract.NextStep.run_then_expect_status, recordingEndedStep(.supervised, true));
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, recordingEndedStep(.syscalls, true));
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, recordingEndedStep(.syscalls, false));
    try std.testing.expectEqual(contract.NextStep.threads_limit, threadsStep(.wrappers));
    try std.testing.expectEqual(contract.NextStep.threads_limit, threadsStep(.syscalls));
    try std.testing.expectEqual(contract.NextStep.threads_supervised, threadsStep(.supervised));
}

fn noShimNextFor(observed: ?image.Observation, mode: contract.ObserveMode, can_supervise: bool) contract.NextStep {
    // First, and before the image: under this mode the image's linkage is not the question
    // (`noShimDetail` says why), and a static image here is the one the mode exists for.
    if (mode == .supervised) return .environment;
    const obs = observed orelse return .check_shim;
    return switch (obs.facts) {
        .elf => |e| if (e.has_interp)
            .check_shim
        else if (staticElf64(e) and can_supervise)
            .observe_supervised
        else
            .class_wall,
        // Read in the same order `noShimDetail` reads them, so the step never contradicts
        // the sentence beside it: signing first, and only an unsigned image is judged by
        // its dyld linkage (review caught the reversed order on a signed, non-dyld image —
        // the detail said "another cause", the step said "the wall").
        .macho => |m| blk: {
            const s = m.signing orelse break :blk if (m.dyldlink) .check_shim else .class_wall;
            if (s.platformNamed()) break :blk .non_system_build;
            if (s.libraryValidation() or s.hardenedRuntime()) break :blk .class_wall;
            break :blk .check_shim;
        },
        .unrecognised => .operation_not_an_image,
        .not_resolved, .unreadable, .undecidable => .check_shim,
    };
}

fn staticElf64(e: image.Elf) bool {
    return !e.has_interp and e.class64;
}

/// crash point numbered in the default's count (ADR 0100). A flag of its own rather than a
/// reading of `report.case_note`, which is a display string set for the report's sake.
pub var replaying: bool = false;

/// A reason is not narrow enough to decide this: the same reason is raised from sites that mode
/// crosses and from sites where it refuses the same way, and a step that cannot work is worse
/// than one that only points at the class (`childTouchedNext`; the first draft keyed on reasons
pub fn staticParentNext(site_step: contract.NextStep, shape_measured: bool) contract.NextStep {
    return staticParentNextFor(site_step, shape_measured, observe_mode, rec_image, supervise.available, replaying);
}

fn staticParentNextFor(
    site_step: contract.NextStep,
    shape_measured: bool,
    mode: contract.ObserveMode,
    observed: ?image.Observation,
    can_supervise: bool,
    replay: bool,
) contract.NextStep {
    if (!shape_measured or mode == .supervised or !can_supervise or replay) return site_step;
    const obs = observed orelse return site_step;
    return switch (obs.facts) {
        .elf => |e| if (staticElf64(e)) .observe_supervised_static_parent else site_step,
        else => site_step,
    };
}

pub fn shimAnnouncedElsewhere(trace_primary: ?u32, oracle_primary: ?u32) bool {
    const t = trace_primary orelse return false;
    const o = oracle_primary orelse return false;
    return t != o;
}

pub fn traceClosedByTarget(op: ?engine.Op) bool {
    const o = op orelse return false;
    // The kind is read only off an unplaceable record: on a rename or a link `aux` holds a
    // string the target chose (`unresolved_kind.opOfUnlinkedFd` says the same).
    if (o.class != .unresolved) return false;
    const kind = if (std.mem.indexOfScalar(u8, o.aux, ' ')) |i| o.aux[0..i] else o.aux;
    return std.mem.eql(u8, kind, contract.unresolved_kind.trace_closed);
}

test "staticParentNextFor: each condition, pinned by a neighbour that differs in it alone (#685)" {
    const obs = struct {
        fn of(f: image.Facts) image.Observation {
            return .{ .path = "/x", .size = 0, .facts = f };
        }
    }.of;
    const static64: image.Facts = .{ .elf = .{ .has_interp = false, .class64 = true } };
    const S = contract.NextStep;
    try std.testing.expectEqual(S.observe_supervised_static_parent, staticParentNextFor(.observe_syscalls, true, .wrappers, obs(static64), true, false));
    try std.testing.expectEqual(S.observe_supervised_static_parent, staticParentNextFor(.class_wall, true, .syscalls, obs(static64), true, false));
    try std.testing.expectEqual(S.observe_syscalls, staticParentNextFor(.observe_syscalls, false, .wrappers, obs(static64), true, false));
    try std.testing.expectEqual(S.class_wall, staticParentNextFor(.class_wall, true, .supervised, obs(static64), true, false));
    try std.testing.expectEqual(S.observe_syscalls, staticParentNextFor(.observe_syscalls, true, .wrappers, obs(static64), false, false));
    try std.testing.expectEqual(S.observe_syscalls, staticParentNextFor(.observe_syscalls, true, .wrappers, obs(static64), true, true));
    try std.testing.expectEqual(S.observe_syscalls, staticParentNextFor(.observe_syscalls, true, .wrappers, obs(.{ .elf = .{ .has_interp = true, .class64 = true } }), true, false));
    try std.testing.expectEqual(S.class_wall, staticParentNextFor(.class_wall, true, .wrappers, obs(.{ .elf = .{ .has_interp = false, .class64 = false } }), true, false));
    try std.testing.expectEqual(S.class_wall, staticParentNextFor(.class_wall, true, .wrappers, obs(.{ .macho = .{ .dyldlink = false, .signing = null } }), true, false));
    try std.testing.expectEqual(S.class_wall, staticParentNextFor(.class_wall, true, .wrappers, null, true, false));
}

test "the two measured shapes read only what they were measured on (#685)" {
    try std.testing.expect(shimAnnouncedElsewhere(57, 41));
    try std.testing.expect(!shimAnnouncedElsewhere(41, 41)); // a static image that exec'd a dynamic one
    try std.testing.expect(!shimAnnouncedElsewhere(null, 41));
    try std.testing.expect(!shimAnnouncedElsewhere(57, null));
    const U = contract.unresolved_kind;
    const op = struct {
        fn of(aux: []const u8) engine.Op {
            return .{ .class = .unresolved, .seq = 0, .pid = 57, .tid = 57, .path = "", .aux = aux };
        }
    }.of;
    try std.testing.expect(traceClosedByTarget(op(U.trace_closed)));
    try std.testing.expect(traceClosedByTarget(op("trace-closed-by-target fd:900")));
    try std.testing.expect(!traceClosedByTarget(op("unlinked-fd write fd:3")));
    try std.testing.expect(!traceClosedByTarget(op(U.link_by_descriptor)));
    try std.testing.expect(!traceClosedByTarget(op("trace-closed-by-targetX")));
    try std.testing.expect(!traceClosedByTarget(null));
    try std.testing.expect(!traceClosedByTarget(.{ .class = .rename, .seq = 1, .pid = 57, .tid = 57, .path = "/s/a", .aux = U.trace_closed }));
}

///     this detector proves. It is not even proof that injection was refused: a trace
///     that could not be read collapses to an empty `TraceInfo` and arrives here too
///     (`engine/trace.zig` says so at three call sites). So the first clause reports the
///   - **Fields, not blame.** "carries the library-validation flag" — never "library
///     validation refused the insertion". The bit can be lifted by entitlement and a
///     non-zero platform byte is not Apple's full definition of a platform binary.
/// The path is target-derived and goes through `textShown`, like every other
/// target-controlled string that reaches the text report.
pub fn noShimDetail(arena: std.mem.Allocator) []const u8 {
    if (observe_mode == .supervised)
        return "the trace carries no start record: under --observe supervised the engine writes it itself when the operation launches, so the engine could not open or write its trace file (a full disk, say) while the operation ran";
    const opening = "the trace carries no shim marker";
    const obs = rec_image orelse return arena.dupe(u8, opening ++
        "; the operation's image was not examined") catch opening;

    const path = obs.path orelse return arena.dupe(u8, switch (obs.facts) {
        .not_resolved => |why| switch (why) {
            .path_unset => opening ++ "; the operation's first word names no path, and PATH is not set, so Sideeye did not look for the file it names",
            .not_found => opening ++ "; the operation's first word names no path, and no directory on PATH holds an executable file of that name",
        },
        else => opening ++ "; the operation's image was not examined",
    }) catch opening;
    const shown = textShown(arena, path);
    const found = if (obs.via_path) " (found along PATH)" else "";

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
        // Unreachable with a path — `observe` returns `not_resolved` only with none — and kept
        // as a sentence rather than `unreachable` because this line is a refusal's detail.
        .not_resolved => "Sideeye did not find it on PATH",
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
    const ended: []const u8 = if (rec_end_deferred) |t| switch (t) {
        .signaled => |sig| std.fmt.allocPrint(arena, "; the recording run was killed by signal {d}", .{sig}) catch "",
        .unknown => "; the recording run did not exit normally",
        .exited => "",
    } else "";
    return std.fmt.allocPrint(arena, "{s}; read before the run started, on {s}{s}: {s}{s}{s}", .{
        opening, shown, found, body, drift, ended,
    }) catch opening;
}

pub fn noShimDetailSecondRun(arena: std.mem.Allocator) []const u8 {
    if (observe_mode == .supervised)
        return "the second observed run's trace carries no start record, although the first one did: under --observe supervised the engine writes it itself when the operation launches, so the engine could not open or write that run's trace file while the operation ran";
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

pub const SelfExecStep = struct { next: contract.NextStep, detail: []const u8 };

pub fn selfExecStep(arena: std.mem.Allocator) SelfExecStep {
    return selfExecStepFor(arena, rec_image, @import("builtin").os.tag == .macos);
}

fn selfExecStepFor(arena: std.mem.Allocator, observed: ?image.Observation, darwin: bool) SelfExecStep {
    const plain: SelfExecStep = .{ .next = .unwrap_or_class_wall, .detail = "" };
    if (!darwin) return plain;
    const fw = image.frameworkPython(arena, observed orelse return plain) orelse return plain;
    const launcher = textShown(arena, fw.launcher);
    const before = if (fw.script != null) "was read before the run and is not an executable image" else "was read before the run as a Mach-O";
    const script = if (fw.script) |s|
        std.fmt.allocPrint(arena, "it is the script {s}, whose #! line names {s}{s}{s}, and ", .{
            textShown(arena, s), launcher, if (fw.script_options.len > 0) " with the options " else "", textShown(arena, fw.script_options),
        }) catch return plain
    else
        "";
    const venv = if (fw.venv_launcher) |v|
        std.fmt.allocPrint(arena, "; a pyvenv.cfg stands in {s}'s directory or the one above, so the launcher sets __PYVENV_LAUNCHER__={s}", .{ launcher, textShown(arena, v) }) catch return plain
    else
        "";
    const detail = std.fmt.allocPrint(
        arena,
        ". The operation's image {s}; at this refusal, {s}{s} resolves into the bin directory of a framework Python, whose interpreter is {s}{s}",
        .{ before, script, launcher, textShown(arena, fw.interpreter), venv },
    ) catch return plain;
    return .{ .next = .name_framework_interpreter, .detail = detail };
}

/// The reachable boundary-evidence states, written out rather than generated as a
/// product of the fields: most of the product is unreachable (a witness that never ran
/// cannot have counted children, and `oracle_child_touched` needs one that read), and a
/// table of shapes the engine cannot produce measures the renderer against fiction. Each
const boundary_cases = [_]struct {
    what: []const u8,
    ev: BoundaryEvidence,
    may_say_single: bool,
    pins: []const u8,
}{
    .{ .what = "refused before the trace was read (a wrong exit status, say)", .ev = .{}, .may_say_single = false, .pins = "refused before the shim's account" },
    .{ .what = "the shim never announced itself (no_shim_marker)", .ev = .{ .trace_read = true }, .may_say_single = false, .pins = "never announced itself" },
    .{ .what = "no boundary recorded, no oracle asked for (#405)", .ev = .{ .trace_read = true, .shim_reported = true }, .may_say_single = false, .pins = "raw syscall" },
    .{ .what = "no boundary recorded, the strace account never read", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "strace account was not read" },
    .{ .what = "no boundary recorded, the fs_usage account never read", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .unread = .fs_usage } }, .may_say_single = false, .pins = "fs_usage account was not read" },
    .{ .what = "no boundary recorded, strace read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = true, .pins = "single process" },
    .{ .what = "no boundary recorded, strace read and saw two other processes", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 2, .lines = 400 } } }, .may_say_single = false, .pins = "2 other process(es) observed" },
    .{ .what = "no boundary recorded, fs_usage read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 3858 } } }, .may_say_single = false, .pins = "excludes some processes by name" },
    .{ .what = "the shim recorded a thread, fs_usage read and saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 3858 } } }, .may_say_single = false, .pins = "excludes some processes by name" },
    .{ .what = "the strace capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the fs_usage capture was empty (oracle_saw_nothing)", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .fs_usage, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and the empty capture was all there was", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "capture was empty" },
    .{ .what = "the shim recorded a boundary and no oracle ran", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true }, .may_say_single = false, .pins = "no second witness ran" },
    .{ .what = "the shim recorded a boundary and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "nothing accounts for what the other process did" },
    .{ .what = "the shim recorded a boundary and strace saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = false, .pins = "disagree" },
    .{ .what = "the shim recorded a boundary and strace accounted for two children", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 2, .lines = 400 } } }, .may_say_single = false, .pins = "attributed to the subject only" },
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
    .{ .what = "a judged run whose only boundary was a thread (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .threads = 6, .writer_threads = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 1262 } } }, .may_say_single = true, .pins = "6 thread(s) created, and 1 thread id(s) of the subject's own process wrote" },
    .{ .what = "a thread the shim never recorded creating wrote the judged directory (v16, #543)", .ev = .{ .trace_read = true, .shim_reported = true, .unrecorded_writer_thread = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 900 } } }, .may_say_single = true, .pins = "never recorded creating wrote the judged directory" },
    // `threads` is set from the same records that set `boundary`, so a run with threads
    // has `shim_boundary` — the first version of this case had `threads = 1` and no
    // boundary, a state the engine cannot produce (review, second round). The vips report
    .{ .what = "a thread created in an explored world, on a run that had threads (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_boundary = true, .world_thread_only = true, .threads = 1, .writer_threads = 1 }, .may_say_single = true, .pins = "a thread was created in an explored world" },
    .{ .what = "the shim recorded a thread and the run refused before the oracle was read (v16)", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .witness = .{ .unread = .strace }, .threads = 3, .writer_threads = 2 }, .may_say_single = false, .pins = "the shim recorded a thread" },
    .{ .what = "the subject left its own process group and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_subject_detached = true, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "the subject leaving its process group" },
    .{ .what = "the subject replaced its own image and strace saw no other process", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } }, .may_say_single = true, .pins = "single process" },
    .{ .what = "the subject replaced its own image and no oracle ran", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1 }, .may_say_single = false, .pins = "replacing its own image and no second witness ran" },
    .{ .what = "the subject replaced its own image and the strace account was not read", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .unread = .strace } }, .may_say_single = false, .pins = "replacing its own image; the strace account was not read" },
    .{ .what = "the subject replaced its own image and the capture was empty", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_continuations = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 0 } } }, .may_say_single = false, .pins = "replacing its own image and the strace capture was empty" },
    .{ .what = "the shim recorded a broken image-replacement chain", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .exec_chain_broken = true, .shim_hard = "an image replacement whose chain of observation broke" }, .may_say_single = false, .pins = "chain of observation broke" },
    .{ .what = "the shim recorded an image replacement before the subject announced itself", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_hard = "an image replacement before the subject announced itself" }, .may_say_single = false, .pins = "before the subject announced itself" },
    .{ .what = "the shim recorded a process leaving the containment group", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .shim_hard = "a process leaving the containment group" }, .may_say_single = false, .pins = "leaving the containment group" },
    .{ .what = "a world-only boundary after a witnessed single-process recording", .ev = .{ .trace_read = true, .shim_reported = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } }, .world_process_boundary = true, .world_boundary = true, .world_only = true }, .may_say_single = true, .pins = "single process in the recording; a process boundary appeared in an explored world" },
    .{ .what = "a world-only boundary after an unwitnessed recording", .ev = .{ .trace_read = true, .shim_reported = true, .world_process_boundary = true, .world_boundary = true, .world_only = true }, .may_say_single = false, .pins = "a process boundary appeared in an explored world" },
    .{ .what = "a world crossed a boundary the recording had also crossed", .ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 1, .lines = 400 } }, .world_process_boundary = true, .world_boundary = true }, .may_say_single = false, .pins = "a process boundary appeared in an explored world" },
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
    boundary_ev = witnessed;
    boundary_ev.unrecorded_writer_thread = true;
    try std.testing.expect(std.mem.startsWith(u8, boundaryAccount(), "single process in the recording;"));
}

test "noShimNextFor: the step each image observation takes (#481, ADR 0090)" {
    const obs = struct {
        fn of(f: image.Facts) image.Observation {
            return .{ .path = "/x", .size = 0, .facts = f };
        }
    }.of;
    const next = struct {
        fn wrappers_linux(o: ?image.Observation) contract.NextStep {
            return noShimNextFor(o, .wrappers, true);
        }
    }.wrappers_linux;
    const static64: image.Facts = .{ .elf = .{ .has_interp = false, .class64 = true } };

    try std.testing.expectEqual(contract.NextStep.operation_not_an_image, next(obs(.unrecognised)));

    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .not_resolved = .path_unset })));
    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .not_resolved = .not_found })));
    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .unreadable = .no_such_file })));
    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .undecidable = .slice_not_unique })));

    try std.testing.expectEqual(contract.NextStep.observe_supervised, next(obs(static64)));
    try std.testing.expectEqual(contract.NextStep.observe_supervised, noShimNextFor(obs(static64), .syscalls, true));
    try std.testing.expectEqual(contract.NextStep.class_wall, noShimNextFor(obs(static64), .wrappers, false));
    try std.testing.expectEqual(contract.NextStep.class_wall, next(obs(.{ .elf = .{ .has_interp = false, .class64 = false } })));
    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .elf = .{ .has_interp = true, .class64 = true } })));

    try std.testing.expectEqual(contract.NextStep.environment, noShimNextFor(obs(static64), .supervised, true));
    try std.testing.expectEqual(contract.NextStep.environment, noShimNextFor(obs(.{ .not_resolved = .not_found }), .supervised, true));
    try std.testing.expectEqual(contract.NextStep.environment, noShimNextFor(null, .supervised, true));

    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .macho = .{ .dyldlink = true, .signing = null } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, next(obs(.{ .macho = .{ .dyldlink = false, .signing = null } })));
    try std.testing.expectEqual(contract.NextStep.non_system_build, next(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = 0, .platform = 1 } } })));
    try std.testing.expectEqual(contract.NextStep.non_system_build, next(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = image.cs_runtime, .platform = 1 } } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, next(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = image.cs_runtime, .platform = 0 } } })));
    try std.testing.expectEqual(contract.NextStep.class_wall, next(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = image.cs_require_lv, .platform = 0 } } })));
    try std.testing.expectEqual(contract.NextStep.check_shim, next(obs(.{ .macho = .{ .dyldlink = true, .signing = .{ .flags = 0, .platform = 0 } } })));

    try std.testing.expectEqual(contract.NextStep.check_shim, next(null));
}

test "noShimDetail says a bare name's file was found along PATH, and why none was (ADR 0090)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const saved_mode = observe_mode;
    const saved_image = rec_image;
    defer {
        observe_mode = saved_mode;
        rec_image = saved_image;
    }
    observe_mode = .wrappers;

    rec_image = .{ .path = null, .size = null, .facts = .{ .not_resolved = .path_unset } };
    try std.testing.expect(std.mem.indexOf(u8, noShimDetail(arena), "PATH is not set") != null);
    rec_image = .{ .path = null, .size = null, .facts = .{ .not_resolved = .not_found } };
    const nf = noShimDetail(arena);
    try std.testing.expect(std.mem.indexOf(u8, nf, "no directory on PATH holds an executable file of that name") != null);
    try std.testing.expect(std.mem.indexOf(u8, nf, "Sideeye did not") == null);

    rec_image = .{ .path = "/nonexistent-for-this-test/prog", .size = null, .via_path = true, .facts = .{ .unreadable = .no_such_file } };
    const via = noShimDetail(arena);
    rec_image = .{ .path = "/nonexistent-for-this-test/prog", .size = null, .via_path = false, .facts = .{ .unreadable = .no_such_file } };
    const named = noShimDetail(arena);
    try std.testing.expect(std.mem.indexOf(u8, via, "/nonexistent-for-this-test/prog (found along PATH): ") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "(found along PATH)") == null);

    rec_image = .{ .path = "/nonexistent-for-this-test/prog", .size = null, .facts = .{ .elf = .{ .has_interp = false, .class64 = true } } };
    const st = noShimDetail(arena);
    try std.testing.expect(std.mem.indexOf(u8, st, "statically linked and no preloaded library can reach it") != null);
    try std.testing.expect(std.mem.indexOf(u8, st, "--observe supervised") == null);
}

test "a platform image that died is held for the shim's marker, and every other end is refused where it was" {
    const of = struct {
        fn f(facts: image.Facts) ?image.Observation {
            return .{ .path = "/usr/bin/plutil", .size = 0, .facts = facts };
        }
    }.f;
    const platform: image.Facts = .{ .macho = .{ .dyldlink = true, .signing = .{ .flags = 0, .platform = 1 } } };
    const own_build: image.Facts = .{ .macho = .{ .dyldlink = true, .signing = .{ .flags = image.cs_runtime, .platform = 0 } } };

    try std.testing.expect(defersRecordingEnd(.{ .signaled = 6 }, of(platform)));
    try std.testing.expect(defersRecordingEnd(.{ .unknown = 0 }, of(platform)));
    try std.testing.expect(!defersRecordingEnd(.{ .exited = 126 }, of(platform)));
    try std.testing.expect(!defersRecordingEnd(.{ .exited = 1 }, of(platform)));
    try std.testing.expect(!defersRecordingEnd(.{ .signaled = 6 }, of(own_build)));
    try std.testing.expect(!defersRecordingEnd(.{ .signaled = 6 }, of(.{ .macho = .{ .dyldlink = true, .signing = null } })));
    try std.testing.expect(!defersRecordingEnd(.{ .signaled = 6 }, of(.{ .elf = .{ .has_interp = true, .class64 = true } })));
    try std.testing.expect(!defersRecordingEnd(.{ .signaled = 6 }, null));
}

test "a no_shim_marker detail says how a held recording run ended, and nothing when none was held" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const saved_mode = observe_mode;
    const saved_image = rec_image;
    const saved_end = rec_end_deferred;
    defer {
        observe_mode = saved_mode;
        rec_image = saved_image;
        rec_end_deferred = saved_end;
    }
    observe_mode = .wrappers;
    rec_image = .{ .path = "/nonexistent-for-this-test/plutil", .size = null, .facts = .{ .macho = .{ .dyldlink = true, .signing = .{ .flags = 0, .platform = 1 } } } };

    rec_end_deferred = null;
    const plain = noShimDetail(arena);
    try std.testing.expect(std.mem.indexOf(u8, plain, "its code directory names a platform") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "recording run") == null);

    rec_end_deferred = .{ .signaled = 6 };
    try std.testing.expect(std.mem.endsWith(u8, noShimDetail(arena), "; the recording run was killed by signal 6"));
    rec_end_deferred = .{ .unknown = 0 };
    try std.testing.expect(std.mem.endsWith(u8, noShimDetail(arena), "; the recording run did not exit normally"));
}

test "missedOperationNext names the syscall mode only on Linux and only where it is not in use (#599)" {
    try std.testing.expectEqual(contract.NextStep.observe_syscalls, missedOperationNext(.wrappers, true));
    try std.testing.expectEqual(contract.NextStep.class_wall, missedOperationNext(.syscalls, true));
    try std.testing.expectEqual(contract.NextStep.class_wall, missedOperationNext(.wrappers, false));
    try std.testing.expectEqual(contract.NextStep.class_wall, missedOperationNext(.syscalls, false));
}

test "fixDefineUnder keeps fix_define except under the syscall mode (#599)" {
    try std.testing.expectEqual(contract.NextStep.syscalls_may_have_killed, fixDefineUnder(.syscalls));
    try std.testing.expectEqual(contract.NextStep.fix_define, fixDefineUnder(.wrappers));
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
    try std.testing.expect(std.mem.indexOf(u8, got, "refused") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "explored world") != null);
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
    const saved = boundary_ev;
    defer boundary_ev = saved;
    boundary_ev = .{};
    try std.testing.expectEqualStrings(
        "not established: this run was refused before the shim's account of it was read",
        boundaryAccount(),
    );
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
    const dz = std.mem.printSentinel(&pbuf, "{s}", .{dir}, 0) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    const fz = std.mem.printSentinel(fbuf, "{s}/trace.bin", .{dir}, 0) catch unreachable;
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

    try std.testing.expectEqual(contract.UnknownReason.multiple_threads_detected, unattributedWriterReason(threaded, names_threads));
    try std.testing.expectEqual(contract.UnknownReason.child_touched_state_dir, unattributedWriterReason(threaded, names_processes));
    try std.testing.expectEqual(contract.UnknownReason.child_touched_state_dir, unattributedWriterReason(lone, names_threads));
}

test "an id a thread-naming witness cannot attribute is refused as an id, not as a process" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

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
    try std.testing.expect(std.mem.indexOf(u8, why.detail, "id 99 mutated the judged directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, why.detail, "process 99 mutated") == null);
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, why.wall);
}

test "the two conditions on a run with a writing child (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

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
        .spawns = try events.list(arena, &.{.{ .id = 8, .at = 15 }}),
        .subject_tids = .empty,
        .primary_pid = 7,
    };
    try std.testing.expectEqual(@as(?ChildRefusal, null), childrenMayBeJudged(arena, trace, handoff));

    var overlap = handoff;
    overlap.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 8, .at = 20 }, .{ .id = 7, .at = 25 } });
    const raced = childrenMayBeJudged(arena, trace, overlap) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, raced.detail, "(pid 8) performed rename(/tmp/s/a)") != null);
    try std.testing.expect(std.mem.indexOf(u8, raced.detail, "process 7 wrote in the judged directory while it was still running") != null);
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, raced.wall);

    var no_reap = handoff;
    no_reap.reaps = .empty;
    const unreaped = childrenMayBeJudged(arena, trace, no_reap) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unreaped.detail, "(pid 8) performed rename(/tmp/s/a) and nothing waited for it") != null);
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, unreaped.wall);

    var oracle_blind = handoff;
    oracle_blind.mutations = try events.list(arena, &.{.{ .id = 7, .at = 10 }});
    const unplaced = childrenMayBeJudged(arena, trace, oracle_blind) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unplaced.detail, "(pid 8) performed rename(/tmp/s/a) and the oracle's account does not place it") != null);
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, unplaced.wall);

    var unshimmed = handoff;
    // Its write sits AFTER pid 8 was collected and before the parent's, so the ordering
    // condition is satisfied and the only thing wrong with the run is that this writer
    // left no records. A first version of this fixture put it inside pid 8's window and
    // measured the interleaving refusal instead — two defects in one input tell you
    // nothing about which check caught them.
    unshimmed.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 8, .at = 20 }, .{ .id = 99, .at = 35 }, .{ .id = 7, .at = 40 } });
    unshimmed.reaps = try events.list(arena, &.{ .{ .id = 8, .at = 30 }, .{ .id = 99, .at = 37 } });
    const no_records = childrenMayBeJudged(arena, trace, unshimmed) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, no_records.detail, "process 99 mutated the judged directory") != null);
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, no_records.wall);

    var announced = trace;
    var ops: std.ArrayList(engine.Op) = .empty;
    for (trace.ops.items) |op| try ops.append(arena, op);
    try ops.append(arena, .{ .class = .shim_ready, .seq = 0, .pid = 99, .tid = 99, .path = "/tmp/s", .aux = "" });
    announced.ops = ops;
    const shimmed = childrenMayBeJudged(arena, announced, unshimmed) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, shimmed.detail, "process 99 mutated the judged directory") != null);
    try std.testing.expectEqual(ChildWall.shimmed_writer_unnumbered, shimmed.wall);
    try std.testing.expect(std.mem.indexOf(u8, shimmed.detail, "Its shim announced itself") != null);
    {
        const saved_mode = observe_mode;
        defer observe_mode = saved_mode;
        observe_mode = .supervised;
        for ([_]@TypeOf(trace){ trace, announced }) |t| {
            const r = childrenMayBeJudged(arena, t, unshimmed) orelse return error.TestExpectedRefusal;
            try std.testing.expect(std.mem.indexOf(u8, r.detail, "every process the target starts inherits the engine's filter") != null);
            try std.testing.expect(std.mem.indexOf(u8, r.detail, "shim") == null);
        }
    }

    var exec_away = trace;
    var ops2: std.ArrayList(engine.Op) = .empty;
    for (announced.ops.items) |op| try ops2.append(arena, op);
    try ops2.append(arena, .{ .class = .exec, .seq = 0, .pid = 99, .tid = 99, .path = "/usr/bin/static-helper", .aux = "" });
    exec_away.ops = ops2;
    const gone = childrenMayBeJudged(arena, exec_away, unshimmed) orelse return error.TestExpectedRefusal;
    try std.testing.expectEqual(ChildWall.not_the_modes_wall, gone.wall);
    try std.testing.expect(std.mem.indexOf(u8, gone.detail, "never loaded the shim") != null);

    var parent_in_window = handoff;
    parent_in_window.mutations = try events.list(arena, &.{ .{ .id = 7, .at = 10 }, .{ .id = 7, .at = 18 }, .{ .id = 8, .at = 20 } });
    const straddled = childrenMayBeJudged(arena, trace, parent_in_window) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, straddled.detail, "process 7 wrote in the judged directory while it was still running") != null);

    var no_spawn = handoff;
    no_spawn.spawns = .empty;
    const unplaced_child = childrenMayBeJudged(arena, trace, no_spawn) orelse return error.TestExpectedRefusal;
    try std.testing.expect(std.mem.indexOf(u8, unplaced_child.detail, "does not show where process 8 was created") != null);
}

test "two children writing before either is collected are refused (v15)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

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
    try std.testing.expect(std.mem.indexOf(u8, why.detail, "(pid 8) performed write(/tmp/s/x)") != null);
    try std.testing.expect(std.mem.indexOf(u8, why.detail, "process 9 wrote in the judged directory while it was still running") != null);
}

test "preflight's second run names a thread as a thread, not as an image change (v16)" {
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
    try std.testing.expectEqualStrings("a thread", secondRunLabel(threaded, false).?);

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
    try std.testing.expectEqualStrings("a process boundary", secondRunLabel(forked, false).?);

    var fbuf3: [contract.max_path]u8 = undefined;
    const fz3 = try traceFileForTest("secondrun-plain", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf3);
    defer _ = posix.unlink(fz3);
    var tb3 = engine.unboundedBudget(std.testing.allocator);
    var plain = try engine.readTrace(&tb3, std.mem.span(fz3));
    defer plain.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), secondRunLabel(plain, false));
}

test "preflight's second run names a detach only where it refuses, and the subject's own as its own (#559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try traceFileForTest("secondrun-detach", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 8, .tid = 8, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(fz);
    var tb = engine.unboundedBudget(std.testing.allocator);
    var child = try engine.readTrace(&tb, std.mem.span(fz));
    defer child.deinit();
    try std.testing.expectEqualStrings("a process leaving the containment group", secondRunLabel(child, true).?);
    try std.testing.expectEqualStrings("a process boundary", secondRunLabel(child, false).?);

    var fbuf2: [contract.max_path]u8 = undefined;
    const fz2 = try traceFileForTest("secondrun-own-detach", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf2);
    defer _ = posix.unlink(fz2);
    var tb2 = engine.unboundedBudget(std.testing.allocator);
    var own = try engine.readTrace(&tb2, std.mem.span(fz2));
    defer own.deinit();
    try std.testing.expectEqualStrings("the subject leaving its process group", secondRunLabel(own, false).?);
}

test "under --observe supervised the thread refusal states that mode's rule and names no shim; the default mode's sentence is unchanged (#217)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const saved = observe_mode;
    defer observe_mode = saved;
    const first: engine.Op = .{ .class = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/s/a", .aux = "" };
    const second: engine.Op = .{ .class = .write, .seq = 2, .pid = 7, .tid = 8, .path = "/s/b", .aux = "" };

    observe_mode = .supervised;
    const sup = threadDetail(arena, first, second, false, "");
    try std.testing.expect(std.mem.indexOf(u8, sup, "tid 7 performed write(/s/a) and tid 8 performed write(/s/b)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "Nothing the supervising engine recorded orders") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "no join is recorded, nor which thread a creation made") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "however the target orders them this run cannot establish that a crash point names the same operation") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "would not name the same operation") == null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "the shim recorded") == null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "is judged, however many threads") == null);
    try std.testing.expect(std.mem.indexOf(u8, threadDetail(arena, first, second, true, ""), "detached") == null);

    observe_mode = .wrappers;
    try std.testing.expectEqualStrings(
        "two threads of process 7 wrote in the judged directory: tid 7 performed write(/s/a) and tid 8 performed write(/s/b). No thread creation or join the shim recorded orders the first of those before the second, so their order is the scheduler's choice on this run, the sequence they were numbered in is the one it happened to produce, and a crash point would not name the same operation on the next. A process whose threads' writes are all ordered by the creations and joins the shim recorded is judged, however many threads it created (v18)",
        threadDetail(arena, first, second, false, ""),
    );
    try std.testing.expect(std.mem.indexOf(u8, threadDetail(arena, first, second, true, ""), "; tid 7 was detached, so no join could order it, so their order") != null);
}

test "under --observe supervised the processes line names the engine and that mode's thread rule (#217)" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    const saved_mode = observe_mode;
    defer observe_mode = saved_mode;
    boundary_ev = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_thread_only = true, .threads = 3, .writer_threads = 1, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 40 } } };

    observe_mode = .supervised;
    const sup = boundaryAccount();
    try std.testing.expect(std.mem.indexOf(u8, sup, "the supervising engine recorded 3 thread(s) created, and 1 thread id(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "no join is recorded, nor which thread a creation made, so writes from two or more threads of one process refuse") != null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "the shim") == null);
    try std.testing.expect(std.mem.indexOf(u8, sup, "writes ordered by a recorded creation or join are judged") == null);

    observe_mode = .wrappers;
    const def = boundaryAccount();
    try std.testing.expect(std.mem.indexOf(u8, def, "the shim recorded 3 thread(s) created") != null);
    try std.testing.expect(std.mem.indexOf(u8, def, "(v18: writes ordered by a recorded creation or join are judged, unordered ones refuse)") != null);
}

test "under --observe supervised a boundary and a refused-early run name the engine, not the shim (#217)" {
    const saved = boundary_ev;
    defer boundary_ev = saved;
    const saved_mode = observe_mode;
    defer observe_mode = saved_mode;
    const disagree: BoundaryEvidence = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .shim_process_boundary = true, .witness = .{ .read = .{ .kind = .strace, .children = 0, .lines = 68 } } };
    const unread: BoundaryEvidence = .{ .trace_read = true, .shim_reported = true, .shim_boundary = true, .witness = .{ .unread = .strace } };

    observe_mode = .supervised;
    boundary_ev = disagree;
    try std.testing.expect(std.mem.indexOf(u8, boundaryAccount(), "the supervising engine recorded a process boundary and strace observed no other process") != null);
    boundary_ev = unread;
    try std.testing.expect(std.mem.indexOf(u8, boundaryAccount(), "the supervising engine recorded the subject replacing its own image; the strace account was not read") != null);
    boundary_ev = .{};
    try std.testing.expectEqualStrings("not established: this run was refused before the supervising engine's account of it was read", boundaryAccount());
    for ([_]BoundaryEvidence{ disagree, unread, .{}, .{ .trace_read = true } }) |ev| {
        boundary_ev = ev;
        try std.testing.expect(std.mem.indexOf(u8, boundaryAccount(), "shim") == null);
    }

    observe_mode = .wrappers;
    boundary_ev = disagree;
    try std.testing.expect(std.mem.indexOf(u8, boundaryAccount(), "the shim recorded a process boundary and strace observed no other process") != null);
    boundary_ev = .{};
    try std.testing.expectEqualStrings("not established: this run was refused before the shim's account of it was read", boundaryAccount());
}

test "under --observe supervised a missing start record and an unrecorded writer are explained as that mode's, not the shim's (#217 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const saved = observe_mode;
    defer observe_mode = saved;

    observe_mode = .supervised;
    for ([_][]const u8{ noShimDetail(arena), noShimDetailSecondRun(arena) }) |d| {
        try std.testing.expect(std.mem.indexOf(u8, d, "the engine writes it itself when the operation launches") != null);
        try std.testing.expect(std.mem.indexOf(u8, d, "shim") == null);
        try std.testing.expect(std.mem.indexOf(u8, d, "statically linked") == null);
    }
    observe_mode = .wrappers;
    try std.testing.expect(std.mem.startsWith(u8, noShimDetail(arena), "the trace carries no shim marker"));
    try std.testing.expect(std.mem.startsWith(u8, noShimDetailSecondRun(arena), "the second observed run carries no shim marker"));
}

test "selfExecStepFor: a framework Python's launcher is named on macOS, and nothing else changes (#703)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const ff = try image.fakeFrameworkForTest(a, "boundary-selfexec");
    defer ff.remove();
    const launcher = image.reobserve(a, ff.launcher);

    for ([_]SelfExecStep{
        selfExecStepFor(a, launcher, false),
        selfExecStepFor(a, null, true),
        selfExecStepFor(a, image.reobserve(a, ff.stray), true),
        selfExecStepFor(a, .{ .path = null, .size = null, .facts = .{ .not_resolved = .not_found } }, true),
    }) |sx| {
        try std.testing.expectEqual(contract.NextStep.unwrap_or_class_wall, sx.next);
        try std.testing.expectEqualStrings("", sx.detail);
    }

    const direct = selfExecStepFor(a, launcher, true);
    try std.testing.expectEqual(contract.NextStep.name_framework_interpreter, direct.next);
    try std.testing.expect(std.mem.indexOf(u8, direct.detail, "Resources/Python.app/Contents/MacOS/Python") != null);
    try std.testing.expect(std.mem.indexOf(u8, direct.detail, "__PYVENV_LAUNCHER__") == null);
    try std.testing.expect(std.mem.indexOf(u8, direct.detail, "#! line") == null);
    try std.testing.expect(std.mem.indexOf(u8, direct.detail, "was read before the run as a Mach-O; at this refusal, ") != null);

    const venv = selfExecStepFor(a, image.reobserve(a, ff.venv_python), true);
    try std.testing.expectEqual(contract.NextStep.name_framework_interpreter, venv.next);
    try std.testing.expect(std.mem.indexOf(u8, venv.detail, "__PYVENV_LAUNCHER__=") != null);
    const script = selfExecStepFor(a, image.reobserve(a, ff.script), true);
    try std.testing.expectEqual(contract.NextStep.name_framework_interpreter, script.next);
    try std.testing.expect(std.mem.indexOf(u8, script.detail, "is not an executable image; at this refusal, it is the script ") != null);
    try std.testing.expect(std.mem.indexOf(u8, script.detail, "whose #! line names") != null);
    try std.testing.expect(std.mem.indexOf(u8, venv.detail, "'s directory or the one above") != null);
    try std.testing.expect(std.mem.indexOf(u8, script.detail, "with the options -sE") != null);
    try std.testing.expect(std.mem.indexOf(u8, script.detail, "__PYVENV_LAUNCHER__=") != null);
}
