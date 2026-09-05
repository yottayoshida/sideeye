//! The shim's trace, read back: decoding, the whole-trace budget, and the process and
//! exec accounting that turns records into a `TraceInfo`.
//!
//! Extracted from `engine.zig` (#491, ADR 0047), where it sat between the only two
//! separator rules in that file and referenced nothing else in it but `readWhole` — which
//! is `read.zig` now. `engine.zig` re-exports every public declaration here, so `main.zig`
//! reaches them as `engine.*` and does not know this file exists; a test there walks this
//! file's declarations and fails if one is missing from the facade. Nothing here imports
//! `engine.zig`.
//!
//! Comments below name declarations that live elsewhere: in `engine.zig`
//! (`max_state_file_bytes`, `max_state_tree_bytes`, `SnapshotError`, `takeSnapshotCapped`),
//! in `main.zig` (`snapshotDetail`, `readTraceOrRefuse`), in `read.zig` (`ReadWholeError`,
//! mentioned once inside `readTraceCappedInner`), and in `contract.zig` (`max_path`, written
//! unqualified where `contract.max_record_len` beside it is not). They are references, not
//! imports; the argument each one carries was written when all of this was one file.

const std = @import("std");
const contract = @import("contract");
const posix = @import("../posix.zig");
const read = @import("read.zig");

const Allocator = std.mem.Allocator;

/// What reading a trace can answer (#376).
///
/// Every failure of the underlying read is caught inside `readTraceCappedInner` — the cap
/// breach becomes `too_large` on the returned `TraceInfo` and everything else becomes an
/// empty one, which the caller reads as `no_shim_marker`. What escapes is only what this
/// function does itself: formatting the path (`PathTooLong`) and allocating into the
/// arena (`OutOfMemory`).
///
/// The point of naming it is `main.zig`'s two switches over `SnapshotError`, which are
/// exhaustive on purpose so that an error member added later cannot silently take a
/// neighbour's reason. While the trace reader declared `SnapshotError`, a member added
/// for the trace forced an arm in `snapshotDetail`, whose every sentence describes the
/// state tree — measured before this change: the compiler demanded an arm at
/// `main.zig:716`, and at `:791` once that one was filled. `docs/report-schema.md` says
/// `message` carries "what was observed"; an arm written there for a trace failure
/// carries what was not.
///
/// **What this does not buy:** nothing switches exhaustively over this set, so
/// `readTraceOrRefuse` stays a single `catch` and both members reach the operator as one
/// sentence. The guarantee is one-directional — a trace-only member cannot reach the
/// snapshot's switches, and nothing forces the trace side to say anything about it.
///
/// `PathTooLong` is nearly unreachable rather than unreachable, and the difference was
/// found in review after the first draft claimed the stronger thing. The read's
/// `bufPrintZ` needs one byte more than the `bufPrint` that built the same path at the
/// call site, so the window is `path.len == max_path` exactly. At the two record sites a
/// longer sibling (`stdout-record.txt`, `stdout-record-2.txt`) is formatted into an
/// equally sized buffer first and closes it. **The world loop is not closed**: its trace
/// name is `/trace-{d}.bin`, which passes `/stdout-world.txt` in length at seven digits,
/// so a work directory of 4,078 bytes and a crash point past one million reaches it.
/// Reported, not fixed: the refusal is correct either way, and the message is the same
/// sentence a `#377` ceiling breach or an allocation failure would print there.
pub const TraceReadError = error{ OutOfMemory, PathTooLong };

pub const Op = struct {
    class: contract.OpClass,
    seq: u32,
    pid: u32,
    path: []const u8,
    aux: []const u8,
};

pub const TraceInfo = struct {
    arena: std.heap.ArenaAllocator,
    ops: std.ArrayList(Op),
    saw_header: bool = false,
    version_mismatch: bool = false,
    saw_shim_ready: bool = false,
    /// The shim saw an operation it could not place. Any verdict computed from a trace
    /// containing one is a verdict about an incomplete picture.
    saw_unresolved: bool = false,
    /// The syscall-and-flag spelling of the first in-scope operation the shim could
    /// place but not model (v12, macOS: `RENAME_SWAP`, `exchangedata`). Borrows from
    /// the trace buffer. On Linux this refusal comes from the oracle instead, and
    /// this field stays null.
    first_unsupported: ?[]const u8 = null,
    kill_landed_seq: ?u32 = null,
    /// Who wrote the kill_landed record. `seq == k` alone is not landing evidence: a
    /// child inheriting SIDEEYE_KILL_AT counts its own operations, and its k-th is not
    /// the subject's.
    kill_landed_pid: ?u32 = null,
    kill_point_count: u32 = 0,
    mutation_count: u32 = 0,
    boundary: ?contract.OpClass = null,
    /// The boundaries that stay refusals regardless of tolerance, which are not the
    /// same set for every process: the *subject* replacing its image or creating a
    /// thread breaks addressing and determinism, while a **child** exec'ing is just a
    /// spawn doing what spawns do. `detached` is hard from anyone — escape is escape.
    /// Kept separately from `boundary` because "first boundary" can be a tolerable
    /// fork that arrives before the record that must refuse the run.
    hard_boundary: ?contract.OpClass = null,
    truncated: bool = false,
    /// The subject: whoever wrote the first `shim_ready`. The trace file is created by
    /// the first process to initialise, which is the process the engine launched —
    /// children come later, whether forked (init already done) or spawned (their init
    /// appends behind the subject's).
    primary_pid: ?u32 = null,
    /// A kill-point (or kill_landed) record from a process other than the subject.
    /// Crash points are numbered per process, so such an operation has no unique
    /// address; any run containing one is refused rather than mis-attributed.
    foreign_kill_point: bool = false,
    /// Any record at all from another process — a spawned child announcing itself
    /// counts. Evidence that the run crossed a process boundary even if no boundary
    /// record was written (a raw clone, say).
    foreign_pid_seen: bool = false,
    /// Subject execs whose chain was proven unbroken (#123): the exec record was
    /// followed by a `shim_ready` from the same pid carrying exactly the operation
    /// count the chain left off at. Such an exec is a continuation, not a boundary.
    exec_continuations: u32 = 0,
    /// A subject exec whose continuation evidence never arrived, arrived with the
    /// wrong count, or was pre-empted by another exec. `hard_boundary` is set to
    /// `.exec` alongside this; the flag exists so the refusal can say WHICH way the
    /// image change escaped observation.
    exec_chain_broken: bool = false,
    /// How many kill-point records the subject wrote. `kill_point_count` is the
    /// MAXIMUM seq; if the two disagree the numbering has gaps or duplicates — a
    /// restarted counter after an unobserved exec is exactly a duplicate — and any
    /// address computed from the trace may name a different operation than the one
    /// that ran (#123, R1 C7: prefixHash misses duplicates, logicalAddress takes
    /// the last match; a verdict over renumbered ops is a verdict about nothing).
    primary_kill_records: u32 = 0,
    /// The trace read broke its cap (#324). Distinct from `truncated`, which is the
    /// writer's side: a record that ends mid-way says the shim stopped writing, while
    /// this says the reader refused to hold what the shim did write. Without the
    /// distinction both arrive as an empty TraceInfo, and the caller reads an empty
    /// TraceInfo as "the shim never initialised".
    too_large: bool = false,
    /// The trace's size from `lseek(SEEK_END)` at the moment the cap broke; null when
    /// even that failed, in which case the refusal names the cap and no more (#265's
    /// rule: a size nobody measured must not appear in the message).
    too_large_size: ?u64 = null,
    /// The whole-trace ceiling refused an allocation during this read (#377). Carried on
    /// the TraceInfo rather than raised as an error for the reason `too_large` is: the
    /// caller classifies first and refuses after, so a structural UNKNOWN still reports
    /// the L0 classification that exists. Raising it instead cost exactly that — review
    /// measured `atomicity: not classified` on a recording-site refusal, because the
    /// refusal ran before the final snapshot.
    /// One field rather than a flag beside a size: unlike `too_large_size`, which is null
    /// when even `lseek` failed, this size always exists when the ceiling refused —
    /// it comes off the budget's own record of the request. A separate bool would be
    /// derivable from it, and derivable state is state that can disagree.
    budget_refused: ?usize = null,

    pub fn deinit(self: *TraceInfo) void {
        self.arena.deinit();
    }

    /// The logical address of crash point k: the operation it happens before, and the
    /// one it happens after. Reported instead of a bare counter so a saved case can be
    /// recognised as no longer applying when the code changes. Only the subject's
    /// operations are addresses; a child's seq counts different things.
    pub fn logicalAddress(self: TraceInfo, k: u32) struct { after: ?Op, before: ?Op } {
        var after: ?Op = null;
        var before: ?Op = null;
        for (self.ops.items) |op| {
            if (!op.class.isKillPoint()) continue;
            if (self.primary_pid != null and op.pid != self.primary_pid.?) continue;
            if (op.seq == k) before = op;
            if (op.seq == k - 1) after = op;
        }
        return .{ .after = after, .before = before };
    }
};

/// The trace read's ceiling (#324). Sized against the largest exploration this
/// repository has measured — 119 worlds (Borg, `spike/cohort2/borg-r3/RUNLOG.md`) — at
/// the contract's worst-case record, `contract.max_record_len` = 8210 bytes (two
/// `max_path` components plus headers): 976,990 bytes, which this cap clears 68 times
/// over. Two things that comparison does NOT say: worlds are not records (a trace also
/// carries seq-0 lifecycle, boundary and marker records, which nothing here counts), and
/// at worst-case records the cap admits 8,174 of them — not the "million operations" an
/// earlier draft claimed by silently switching to typical path lengths mid-argument.
/// It shares its value with `max_state_file_bytes` and nothing else: the two bound
/// different things and may move apart.
pub const max_trace_bytes: usize = 64 * 1024 * 1024;

/// What every live trace read may hold TOGETHER (#377).
///
/// `max_trace_bytes` bounds one read. Nothing bounded the sum: the total was held by
/// there being two read sites in one function, so the bound moved whenever someone
/// added a site — and by the time this was written there were **three**, in two
/// functions, with six comments and documents still saying two. A bound that a call
/// site can move is not a rule, it is an argument, and arguments go stale in silence.
/// This is the shape `max_state_tree_bytes` removed from the snapshot path (#323,
/// ADR 0029) one level up: there a sum of per-file caps, here a sum of per-read ones.
///
/// **The value is measured, not derived.** What a trace costs is not its file size:
/// `readWhole` reserves from the file's own length (a flat 1.50x, the arena's node
/// growth factor), and the decode then duplicates every record's `path` and `aux` and
/// grows an `ArrayList(Op)` in the same arena. A ceiling read off file sizes would bound
/// none of that. Measured here, one live read at a time (ADR 0033 carries the table):
///
/// | shape | file bytes | budget bytes | ratio |
/// |---|---|---|---|
/// | header only | 36 | 542 | 15.1x |
/// | 100 records, 16-byte paths | 3,436 | 22,580 | 6.6x |
/// | 10,000 records, 16-byte paths | 340,036 | 2,680,986 | 7.9x |
/// | 100 records, 3000-byte path and aux | 601,836 | 2,285,906 | 3.8x |
/// | 2,000 records, 3000-byte path and aux | 12,036,036 | 45,139,816 | 3.75x |
/// | 1,973,000 records, 16-byte paths | 67,082,036 | 521,200,426 | 7.77x |
/// | **3,532,000 records, 1-byte paths** | **67,108,036** | **1,523,533,632** | **22.7x** |
///
/// **Shorter records cost more**, not less: the per-record overhead is what dominates, so
/// the same file size decoded from more records holds more — by a factor of six between
/// the last two rows, at the same file size.
///
/// **This ceiling therefore does NOT clear one read at the per-read cap, and that is
/// deliberate.** Clearing the last row would need 1.5 GiB, and two of them 3 GiB, which
/// is the resident set the ceiling exists to prevent — an OOM kill with no report is
/// worse than a refusal that names itself. So the two ceilings **disagree about some
/// traces**: `max_trace_bytes` admits a file this one will not hold. ADR 0029 records the
/// same shape for the snapshot, where a tree can break the per-file cap and the tree
/// ceiling and which fires depends on `readdir` order.
///
/// What 512 MiB is sized against is the corpus rather than the cap, **and that half is an
/// estimate, not a measurement.** The largest exploration recorded here is 119 worlds
/// (Borg, cohort 2), which at `contract.max_record_len` comes to 976,990 bytes — a
/// calculated bound inherited from `max_trace_bytes` above, and it inherits that comment's
/// caveat with it: worlds are not records, and a trace also carries lifecycle, boundary
/// and marker records that the figure does not count. Taken at the worst ratio in the
/// table it suggests some 22 MB per trace and 45 MB for two, which this ceiling clears by
/// a wide margin. **No trace from that exploration was weighed**; what is measured here is
/// the shape table, and the margin is a reading off it.
///
/// An earlier draft of this comment claimed the value cleared one read at the per-read
/// cap; it was written from the 16-byte row alone, and the 1-byte row is what review
/// asked for and measurement then contradicted it with.
pub const max_trace_bytes_total: usize = 512 * 1024 * 1024;

/// The ceiling above, as an allocator rather than a counter call sites remember to update.
///
/// Every `TraceInfo.arena` is built on one of these, so the raw read, the decode's
/// `path`/`aux` duplicates and the `ArrayList(Op)` all charge the same limit — and
/// `TraceInfo.deinit` returns them through the arena's own `rawFree`, with no site
/// having to remember. **A fourth read site inherits the bound by construction**, which
/// is the whole point: the previous arrangement was correct and would have stayed
/// correct only for as long as nobody added a caller.
///
/// **Refusal happens BEFORE the allocation.** An accounting pass that reads
/// `queryCapacity()` after the bytes are held refuses a run that has already taken the
/// memory — ADR 0029 says exactly that about its own ceiling ("the run that refuses may
/// hold more"). Here the vtable answers `null` first, so the promise is that an
/// over-budget allocation does not SUCCEED, which is a thing the code can keep.
///
/// The judging granularity is the arena node, not the individual allocation: small
/// allocations are served from a node already charged. What the limit bounds is the
/// backing memory taken, which is what an operator runs out of.
pub const TraceBudget = struct {
    child: Allocator,
    limit: usize,
    used: usize = 0,
    /// The size of the allocation this budget refused MOST RECENTLY, cleared by the next
    /// success. The **caller** reads it after an `OutOfMemory` to tell "the budget said
    /// no" from "the machine said no" — the vtable cannot say which, because `alloc`
    /// returns `?[*]u8` and carries no error, and every failure therefore reaches the
    /// caller as the same `error.OutOfMemory`.
    ///
    /// Read by `readTraceCapped`, which turns it into `TraceInfo.budget_refused` — the
    /// verdict travels on the TraceInfo and **never joins `SnapshotError`**. A budget
    /// member added to that set would land in the snapshot walk's exhaustive switches,
    /// which the trace reader shared until #376 gave it `TraceReadError` of its own. The
    /// reason for keeping the verdict off both sets outlives that split: it is an
    /// observation about the trace, not a failure to read one.
    ///
    /// **Deliberately not sticky.** `readWhole`'s reservation failure is swallowed on
    /// purpose (`catch {}` there: a failed reservation is not an error, because turning
    /// it into one would relabel an oversized trace as `no_shim_marker`). A flag that
    /// remembered every refusal would let that swallowed one decide a later verdict, so
    /// this is cleared on success and the value always belongs to the failure that
    /// actually propagated.
    refused: ?usize = null,

    pub fn allocator(self: *TraceBudget) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    /// Written as `len > limit - used` rather than `used + len > limit`: the sum can
    /// overflow a usize and the difference cannot, since `used <= limit` holds after
    /// every arm below.
    fn wouldExceed(self: *const TraceBudget, len: usize) bool {
        return len > self.limit - self.used;
    }

    /// Record a successful movement of the charge, and clear the refusal flag.
    ///
    /// **The clearing lives here, in one place, on purpose.** It was written inline in
    /// all three of `alloc`, `resize` and `remap` first, and a mutation deleting any one
    /// of them stayed green — the other two cleared the flag on the same read, so the
    /// tests could not see the sticky behaviour they were written to catch. Three copies
    /// of a rule are three places for it to be half-removed.
    fn charge(self: *TraceBudget, add: usize, sub: usize) void {
        self.used = self.used - sub + add;
        self.refused = null;
    }

    fn alloc(ctx: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *TraceBudget = @ptrCast(@alignCast(ctx));
        if (self.wouldExceed(len)) {
            self.refused = len;
            return null;
        }
        // **A refusal by the child is not a refusal by the budget**, and the flag has to
        // say so. Without this line a large reservation refused by the ceiling, followed
        // by a smaller allocation that the ceiling admitted and the machine could not
        // meet, would report a real out-of-memory as `trace_budget_exhausted`: the stale
        // side-channel outlives the failure it described. Cleared rather than set,
        // because the budget did allow this one.
        const p = self.child.rawAlloc(len, a, ra) orelse {
            self.refused = null;
            return null;
        };
        self.charge(len, 0);
        return p;
    }

    fn resize(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *TraceBudget = @ptrCast(@alignCast(ctx));
        if (n > m.len and self.wouldExceed(n - m.len)) {
            self.refused = n - m.len;
            return false;
        }
        // Same rule as `alloc`: the child saying no is not the ceiling saying no, and a
        // stale flag would let a later reader call it one.
        if (!self.child.rawResize(m, a, n, ra)) {
            self.refused = null;
            return false;
        }
        self.charge(n, m.len);
        return true;
    }

    fn remap(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *TraceBudget = @ptrCast(@alignCast(ctx));
        if (n > m.len and self.wouldExceed(n - m.len)) {
            self.refused = n - m.len;
            return null;
        }
        const p = self.child.rawRemap(m, a, n, ra) orelse {
            self.refused = null;
            return null;
        };
        self.charge(n, m.len);
        return p;
    }

    fn free(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *TraceBudget = @ptrCast(@alignCast(ctx));
        self.child.rawFree(m, a, ra);
        self.used -= m.len;
    }
};

/// A budget with no practical limit, for reads that are not about the ceiling — tests,
/// mostly. **It is a `TraceBudget` rather than a plain allocator on purpose**: the type
/// is what keeps the ceiling from being something a call site can decline to use. A
/// caller that genuinely wants no ceiling says so here, in one named place, instead of
/// passing a general allocator and looking identical to a caller that forgot.
pub fn unboundedBudget(child: Allocator) TraceBudget {
    return .{ .child = child, .limit = std.math.maxInt(usize) };
}

pub fn readTrace(budget: *TraceBudget, path: []const u8) TraceReadError!TraceInfo {
    return readTraceCapped(budget, path, max_trace_bytes);
}

/// The capped form, parameterized for the reason `takeSnapshotCapped` is (#265): no
/// committed fixture reaches the shipped cap. This said "cannot be reached by a fixture",
/// on the grounds that the engine unlinks the trace before every run — the recording path
/// and the world path both — and the only writer is the shim. Both halves are still true
/// and they stop being an argument at the second shim'd process, which opens that same
/// name with no unlink in front of it (#488). A link planted there used to be read through
/// as well — `readWhole` opened `O_RDONLY|O_NONBLOCK` and no more — so the size that arrived
/// was the link target's; it passes `.refuse` now (#489) and that road is shut. Two are not,
/// and no open flag shuts either: a **hard link**, which `O_NOFOLLOW` does not see, and the
/// target itself, which holds the trace path in its own environment. What holds today is
/// therefore still the weak claim: nothing committed aims anything at a large file. How many
/// operations the cap takes depends on path lengths and is not claimed here; what is measured
/// is that no committed define comes near it. Tests drive this with a small `max`.
/// **Takes the budget, not an allocator.** The first version of #377 left this signature
/// alone and injected the ceiling in `main.zig`'s private wrapper, which meant the public
/// API still accepted any allocator: a read site calling `engine.readTrace(gpa, …)`
/// directly would have bypassed the ceiling in silence, while the ADR claimed every
/// `TraceInfo` was built on a budget. Review caught the gap between the claim and the
/// type. `unboundedBudget` is how a caller opts out, visibly.
pub fn readTraceCapped(budget: *TraceBudget, path: []const u8, max: usize) TraceReadError!TraceInfo {
    // **A ceiling refusal is an observation, not an error**, and this wrapper is what
    // makes it one. The read below reaches the ceiling by two different doors: during the
    // raw read, where `readWhole`'s failure collapses into an empty TraceInfo returned
    // normally, and during the decode, where a `try` propagates. Left as they come, the
    // first arrives at the caller as `no_shim_marker` and the second as a SETUP ERROR —
    // two wrong refusals for one cause, and the caller cannot tell either from the real
    // thing. Both are turned into the same flag here, which the caller answers for after
    // it has classified, exactly as it does for `too_large`.
    // **The verdict belongs to THIS read.** `refused` survives until the next successful
    // allocation, which is what makes it usable after a failure — but a read that
    // allocates nothing at all (a missing file, a failed open) would otherwise inherit
    // the previous read's refusal and report a ceiling that did not stop it.
    budget.refused = null;

    var info = readTraceCappedInner(budget, path, max) catch |err| {
        if (err == error.OutOfMemory) {
            if (budget.refused) |want| {
                var empty: TraceInfo = .{
                    .arena = std.heap.ArenaAllocator.init(budget.allocator()),
                    .ops = .empty,
                };
                empty.budget_refused = want;
                return empty;
            }
        }
        return err;
    };
    if (budget.refused) |want| {
        info.budget_refused = want;
    }
    return info;
}

fn readTraceCappedInner(budget: *TraceBudget, path: []const u8, max: usize) TraceReadError!TraceInfo {
    var info: TraceInfo = .{
        .arena = std.heap.ArenaAllocator.init(budget.allocator()),
        .ops = .empty,
    };
    errdefer info.arena.deinit();
    const arena = info.arena.allocator();

    var path_buf: [contract.max_path]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.PathTooLong;

    // A missing trace file is not an error here: it is the observation that the shim
    // never ran, which the caller turns into `no_shim_marker`.
    //
    // Capped since #324, and the cap breaking is the one failure this read does NOT
    // collapse. #265 left the read uncapped precisely because collapsing it would
    // relabel an oversized trace as "the shim never initialised" — a refusal with the
    // wrong reason, worse than no cap. That reasoning stands; what changed is that the
    // cap now has a way to say what it is. Every OTHER failure still collapses, because
    // for those the empty TraceInfo is the honest observation.
    var too_large_size: ?u64 = null;
    const bytes = read.readWhole(arena, path_z.ptr, max, &too_large_size, .refuse) catch |err| switch (err) {
        error.FileTooLarge => {
            info.too_large = true;
            info.too_large_size = too_large_size;
            return info;
        },
        // Exhaustive now that `readWhole` declares its own set (#376): every other
        // failure of the read collapses into an empty `TraceInfo`, which the caller
        // reads as `no_shim_marker`. Written out rather than left as `else` so a member
        // added to `read.ReadWholeError` has to be given an answer here instead of
        // inheriting one.
        //
        // **That collapse is honest for `OutOfMemory` and no longer honest for every
        // `ReadFailed`** (#489). This read passes `.refuse` now, so `ReadFailed` also
        // covers "the trace path was a symlink" — a case where the shim may well have
        // initialised and written, and the engine simply declined to read what the link
        // pointed at. `no_shim_marker` says something else. It is still what comes out,
        // because the three read sites do not land in one place: the recording and
        // `preflight --twice` both reach `no_shim_marker` (with different prose), while a
        // world has no shim-marker branch at all and refuses `kill_did_not_land` — a claim
        // about the engine's own kill, drawn from a trace it declined to read. Naming the
        // path at all three is a separate promise and is left to its own change. What
        // changed here is that this comment no longer claims the collapse is accurate for
        // both members.
        error.OutOfMemory, error.ReadFailed => return info,
    };
    if (bytes.len == 0) return info;

    var off: usize = contract.decodeHeader(bytes) catch |err| switch (err) {
        error.VersionMismatch => {
            info.saw_header = true;
            info.version_mismatch = true;
            return info;
        },
        else => {
            info.truncated = true;
            return info;
        },
    };
    info.saw_header = true;

    // The continuation window (#123): a subject exec is judged, not refused, when
    // the very next same-pid shim_ready carries exactly the operation count the
    // chain left off at. The window is open between those two records.
    var pending_exec = false;
    var pending_base: u32 = 0;

    while (off < bytes.len) {
        const dec = contract.decodeRecord(bytes[off..]) catch {
            info.truncated = true;
            break;
        };
        off += dec.consumed;
        const op: Op = .{
            .class = dec.rec.op,
            .seq = dec.rec.seq,
            .pid = dec.rec.pid,
            .path = try arena.dupe(u8, dec.rec.path),
            .aux = try arena.dupe(u8, dec.rec.aux),
        };
        switch (op.class) {
            .shim_ready => {
                info.saw_shim_ready = true;
                if (info.primary_pid == null) {
                    info.primary_pid = op.pid;
                } else if (pending_exec and op.pid == info.primary_pid.?) {
                    // The new image announcing itself. Its seq is the carried base
                    // (v10); anything else — a fresh 0 from a stripped environment
                    // or a non-interposed exec path — is a chain that broke.
                    if (op.seq == pending_base) {
                        info.exec_continuations += 1;
                    } else {
                        info.exec_chain_broken = true;
                        if (info.hard_boundary == null) info.hard_boundary = .exec;
                    }
                    pending_exec = false;
                } else if (op.pid == info.primary_pid.?) {
                    // No window is open, and the subject announced itself AGAIN. The
                    // constructor runs once per image, so a second announcement IS an
                    // image change — one that escaped interposition entirely (execl
                    // family, fexecve: no exec record, no carried count). Structural,
                    // and it needs no prior operations to fire: R1 measured an execl
                    // with zero in-scope ops before it slipping to a verdict because
                    // the numbering check's two sides were trivially equal.
                    info.exec_chain_broken = true;
                    if (info.hard_boundary == null) info.hard_boundary = .exec;
                }
            },
            .kill_landed => {
                info.kill_landed_seq = op.seq;
                info.kill_landed_pid = op.pid;
            },
            .unresolved => info.saw_unresolved = true,
            // The record's path field carries the syscall-and-flag spelling, not a
            // path (v12). First one wins: the refusal names one operation, the way
            // the oracle's `unsupported` does on Linux, and the slice borrows from
            // the trace buffer the caller keeps alive — the same lifetime `Op.path`
            // already lives with.
            .unsupported => {
                if (info.first_unsupported == null) info.first_unsupported = op.path;
            },
            else => {},
        }
        const is_primary = info.primary_pid != null and op.pid == info.primary_pid.?;
        if (!is_primary) {
            info.foreign_pid_seen = true;
            if (op.class.isKillPoint() or op.class == .kill_landed)
                info.foreign_kill_point = true;
        }
        if (op.class.isKillPoint() and is_primary) {
            info.kill_point_count = @max(info.kill_point_count, op.seq);
            info.primary_kill_records += 1;
            if (op.class.isMutation()) info.mutation_count += 1;
        }
        if (op.class.isBoundary()) {
            if (info.boundary == null) info.boundary = op.class;
            const hard = switch (op.class) {
                .detached => true,
                // A record written before the primary announced itself is attributed
                // to the primary: refusing is the safe misreading.
                .thread => is_primary or info.primary_pid == null,
                .exec => blk: {
                    // A subject exec opens the continuation window instead of
                    // refusing outright (#123). Before the subject is known, v9's
                    // safe misreading stands; a second exec while a window is
                    // still open means the intermediate image was never observed.
                    if (info.primary_pid == null) break :blk true;
                    if (!is_primary) break :blk false;
                    if (pending_exec) {
                        info.exec_chain_broken = true;
                        break :blk true;
                    }
                    pending_exec = true;
                    pending_base = info.kill_point_count;
                    break :blk false;
                },
                else => false,
            };
            if (hard and info.hard_boundary == null) info.hard_boundary = op.class;
        }
        try info.ops.append(arena, op);
    }
    // A window still open at the end of the trace is a chain that broke: the image
    // changed and nothing observed the far side.
    if (pending_exec) {
        info.exec_chain_broken = true;
        if (info.hard_boundary == null) info.hard_boundary = .exec;
    }
    return info;
}

/// Copied from `engine.zig` rather than imported (#491): three lines around `bufPrintZ`
/// with no contract of their own, used here only by the test fixtures below.
fn joinZ(buf: []u8, a: []const u8, b: []const u8) error{PathTooLong}![:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, "{s}/{s}", .{ a, b }) catch return error.PathTooLong;
    return s;
}

test "a trace written against another contract version is a mismatch, not a short trace" {
    // The third structural detector, and the only one that had never been seen firing.
    // It is what stops a stale shim paired with a fresh engine from being read as a
    // target that performed fewer operations than it did — sharing contract.zig at build
    // time says nothing about which binaries end up in the same run.
    var buf: [contract.header_len]u8 = undefined;
    _ = try contract.encodeHeader(&buf);
    std.mem.writeInt(u32, buf[contract.magic.len..][0..4], contract.contract_version + 1, .little);

    // Pid-unique path: engine tests run in more than one test binary, and
    // `zig build test` runs those binaries concurrently — a fixed name raced
    // between the write, the read and the unlink, failing a different assert
    // each time it lost (#28: measured at three distinct lines in one day).
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-version-test-{d}", .{posix.getpid()}) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pbuf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try joinZ(&fbuf, dir, "trace.bin");
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, buf.len), posix.write(fd, &buf, buf.len));
    _ = posix.close(fd);

    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz.ptr));
    defer info.deinit();
    try std.testing.expect(info.version_mismatch);
    // Distinct from truncation: the two lead to different verdicts and different advice.
    try std.testing.expect(!info.truncated);
    try std.testing.expect(info.saw_header);

    // Control: the same header at the right version is not a mismatch.
    var ok_buf: [contract.header_len]u8 = undefined;
    _ = try contract.encodeHeader(&ok_buf);
    const fd2 = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd2 >= 0);
    try std.testing.expectEqual(@as(isize, ok_buf.len), posix.write(fd2, &ok_buf, ok_buf.len));
    _ = posix.close(fd2);
    var ok_info = try readTrace(&tb_, std.mem.span(fz.ptr));
    defer ok_info.deinit();
    try std.testing.expect(!ok_info.version_mismatch);

    _ = posix.unlink(fz.ptr);
    _ = posix.rmdir(dz.ptr);
}

fn writeTraceForTest(dir_tag: []const u8, records: []const contract.Record, fbuf: *[contract.max_path]u8) ![*:0]const u8 {
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-{s}-{d}", .{ dir_tag, posix.getpid() }) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&pbuf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    const fz = try joinZ(fbuf, dir, "trace.bin");
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

test "the trace read refuses a symlink, and reads the same bytes named directly (#489)" {
    // The call site, not the constant. `readTrace` is what `main.zig` reaches through at
    // all three read sites, so passing it a link is the same question the acceptance leg
    // asks of the real binary — and it asks it on **this** host, where the container that
    // runs acceptance is not available. A mutation that flips `readTraceCappedInner`'s
    // `.refuse` back to `.follow` reddens this and nothing else in `zig build test`.
    var fbuf: [contract.max_path]u8 = undefined;
    const real = try writeTraceForTest("trace-link", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);

    // The link sits beside the trace and points at it, so the two names differ in nothing
    // except being a link. Reading the target directly is the control: without it, a
    // `readTrace` that had started refusing everything would satisfy the assertion below.
    var lbuf: [contract.max_path]u8 = undefined;
    const link = std.fmt.bufPrintZ(&lbuf, "{s}.link", .{std.mem.span(real)}) catch unreachable;
    _ = posix.unlink(link.ptr);
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink(real, link.ptr));
    defer {
        _ = posix.unlink(link.ptr);
        _ = posix.unlink(real);
    }

    var tb_ = unboundedBudget(std.testing.allocator);

    var direct = try readTrace(&tb_, std.mem.span(real));
    defer direct.deinit();
    try std.testing.expect(direct.saw_header);
    try std.testing.expect(direct.saw_shim_ready);

    // Through the link: the open is refused, `readWhole` answers `ReadFailed`, and
    // `readTraceCappedInner` collapses it to the empty `TraceInfo` the caller reads as
    // `no_shim_marker`. `saw_header` is the observation point because it is set only after
    // bytes were decoded (`decodeHeader` succeeded), so it separates "read nothing" from
    // "read something".
    var through = try readTrace(&tb_, std.mem.span(link.ptr));
    defer through.deinit();
    try std.testing.expect(!through.saw_header);
    try std.testing.expect(!through.saw_shim_ready);
}

test "a subject exec followed by a shim_ready carrying the count is a continuation (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-cont", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 2, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 3, .pid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    try std.testing.expectEqual(@as(u32, 3), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 3), info.primary_kill_records);
    _ = posix.unlink(fz);
}

test "a subject exec whose shim_ready restarts at zero is a broken chain, and the renumbering is caught (#123)" {
    // The stale-shim shape contract v10 exists for: numbering restarted after the
    // image change. Two independent detectors must both see it — the continuation
    // predicate (wrong base) and the records-vs-max disagreement.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-restart", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    // records = 3, max = 2: the duplicate seq 1 collapses under @max.
    try std.testing.expectEqual(@as(u32, 3), info.primary_kill_records);
    try std.testing.expectEqual(@as(u32, 2), info.kill_point_count);
    _ = posix.unlink(fz);
}

test "a subject exec with no shim_ready after it is a broken chain (#123)" {
    // The static-image / stripped-environment / execl-family shape: the far side of
    // the image change was never observed at all.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-dark", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .path = "", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "a second announcement with no exec record is itself an image change (#123)" {
    // The execl-family shape with nothing recorded before it: no exec record, so
    // no window — but the constructor runs once per image, and a second same-pid
    // shim_ready is self-contained evidence the image changed. R1 measured this
    // slipping to a verdict when only the numbering check stood behind it (zero
    // prior ops make records == max trivially).
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("dup-announce", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "a child's exec never opens a continuation window and stays tolerable (#123)" {
    // The pass shape: children exec and the subject keeps going. The exec itself is
    // not hard; the child's state-directory write is what refuses the run, through
    // foreign_kill_point — the boundary stays a spawn doing what spawns do.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-child", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 9, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 9, .path = "/tmp/s/c", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expect(info.foreign_kill_point);
    _ = posix.unlink(fz);
}

/// A trace file of `n` bytes in a pid-unique directory, plus its cleanup. Built the
/// way the per-file cap's test builds its root (#28: the resolved parent, because
/// macOS `/tmp` is itself a link).
fn traceFixture(tag: []const u8, bytes: []const u8, path_out: []u8) ?[]const u8 {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return null);
    const path = std.fmt.bufPrint(path_out, "{s}/trace.bin", .{base}) catch unreachable;
    var fz: [contract.max_path]u8 = undefined;
    const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return null;
    _ = posix.write(fd, bytes.ptr, bytes.len);
    _ = posix.close(fd);
    return path;
}

/// A trace of `n` write records with 16-byte paths, for the budget tests. Measured at
/// n=100: 3,436 bytes of file and 22,580 bytes of budget.
fn budgetFixture(tag: []const u8, n: usize, gpa: Allocator, fbuf: *[contract.max_path]u8) ![*:0]const u8 {
    const recs = try gpa.alloc(contract.Record, n + 1);
    defer gpa.free(recs);
    const p16 = "pppppppppppppppp";
    recs[0] = .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" };
    for (recs[1..], 0..) |*r, i| r.* = .{ .op = .write, .seq = @intCast(i + 1), .pid = 7, .path = p16, .aux = "" };
    return writeTraceForTest(tag, recs, fbuf);
}

test "MEASURE what a trace costs the budget, by shape (#377, ADR 0033)" {
    // **The table in `max_trace_bytes_total`'s doc, in ADR 0033 and in BUILDLOG is this
    // test's output.** Kept rather than deleted so the numbers a value was chosen from
    // are reproducible by whoever questions the value — review's first pass could not
    // check them against anything, which is a fair complaint about a claim that says
    // "measured". Gated because the last two shapes cost about a minute and 1.5 GB of
    // resident memory between them, which CI should not pay on every push:
    //
    //   SIDEEYE_MEASURE=1 zig build test 2>&1 | grep '#377'
    if (posix.getenv("SIDEEYE_MEASURE") == null) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    const shapes = [_]struct { tag: []const u8, n: usize, plen: usize, alen: usize }{
        .{ .tag = "hdr", .n = 0, .plen = 0, .alen = 0 },
        .{ .tag = "s100", .n = 100, .plen = 16, .alen = 0 },
        .{ .tag = "s10k", .n = 10000, .plen = 16, .alen = 0 },
        .{ .tag = "l100", .n = 100, .plen = 3000, .alen = 3000 },
        .{ .tag = "l2k", .n = 2000, .plen = 3000, .alen = 3000 },
        // Just under `max_trace_bytes` at 34 bytes a record. 1,974,000 would be 67,116,036
        // bytes — over the cap, refused before the decode, and the measurement would be of
        // the raw read alone (`ops=0`, which is how the first attempt reported it).
        .{ .tag = "cap16", .n = 1973000, .plen = 16, .alen = 0 },
        // The same file size at 19 bytes a record. The shim can write a one-character
        // unresolved operand, so this shape is reachable, and it is six times the cost of
        // the row above — which is why the ceiling is not sized against the per-read cap.
        .{ .tag = "cap1", .n = 3532000, .plen = 1, .alen = 0 },
    };
    inline for (shapes) |s| {
        var pbuf: [contract.max_path]u8 = undefined;
        @memset(&pbuf, 'p');
        var abuf: [contract.max_path]u8 = undefined;
        @memset(&abuf, 'x');
        const recs = try gpa.alloc(contract.Record, s.n + 1);
        defer gpa.free(recs);
        recs[0] = .{ .op = .shim_ready, .seq = 0, .pid = 7, .path = "/tmp/s", .aux = "" };
        for (recs[1..], 0..) |*r, i| r.* = .{
            .op = .write,
            .seq = @intCast(i + 1),
            .pid = 7,
            .path = pbuf[0..s.plen],
            .aux = abuf[0..s.alen],
        };
        var fbuf: [contract.max_path]u8 = undefined;
        const fz = try writeTraceForTest("budget-m-" ++ s.tag, recs, &fbuf);

        var budget = unboundedBudget(gpa);
        var info = try readTraceCapped(&budget, std.mem.span(fz), max_trace_bytes);
        std.debug.print("[#377] {s:>6}: recs={d:>7} plen={d:>4} alen={d:>4} used={d:>11} ops={d:>7} too_large={any}\n", .{
            s.tag, s.n, s.plen, s.alen, budget.used, info.ops.items.len, info.too_large,
        });
        info.deinit();
        try std.testing.expectEqual(@as(usize, 0), budget.used);
    }
}

test "the ceiling covers resize and remap, which no trace read reaches (#377)" {
    const gpa = std.testing.allocator;

    // **`ArenaAllocator` never asks its child to `remap`, and only `resize`s its last
    // node.** So the two growth arms of this vtable are unreachable through every other
    // test in this file: deleting their ceiling checks left the whole suite green,
    // measured. They are reachable through the allocator interface directly, which is
    // what a future non-arena caller would use, and that is what this drives.
    var budget: TraceBudget = .{ .child = gpa, .limit = 4096 };
    const a = budget.allocator();

    const m = try a.alloc(u8, 2048);
    try std.testing.expectEqual(@as(usize, 2048), budget.used);

    // Growing by more than the 2048 that remain: both arms must refuse, and must say the
    // budget was the one refusing. `resize` reports `false` and `remap` reports `null`,
    // which the child also does when it simply cannot move the allocation — `refused` is
    // how the two are told apart.
    budget.refused = null;
    try std.testing.expect(!a.resize(m, 5000));
    try std.testing.expect(budget.refused != null);

    budget.refused = null;
    try std.testing.expect(a.remap(m, 5000) == null);
    try std.testing.expect(budget.refused != null);

    // Shrinking is never refused BY THE BUDGET. Whether the child can do it in place is
    // a different question — `std.testing.allocator` answers false for 2048 → 1024,
    // measured — so what this asserts is that the ceiling did not object, not that the
    // resize happened.
    budget.refused = null;
    _ = a.resize(m, 1024);
    try std.testing.expect(budget.refused == null);

    a.free(m);
    try std.testing.expectEqual(@as(usize, 0), budget.used);
}

test "a child refusal is not a ceiling refusal, on all three arms (#377)" {
    const gpa = std.testing.allocator;

    // A budget with room to spare over a child that refuses anything large: the shape
    // where the ceiling says yes and the machine says no. Both answer the caller with
    // the same `null`/`false`, so the only thing that separates them is `refused` —
    // which means a stale value here reports a real out-of-memory as a ceiling refusal.
    var refuser: RefuseLargeAllocator = .{ .backing = gpa, .ceiling = 4096 };
    var budget: TraceBudget = .{ .child = refuser.allocator(), .limit = 64 * 1024 };
    const a = budget.allocator();

    const m = try a.alloc(u8, 2048);
    defer a.free(m);

    // The real order, not a flag set by hand: a genuine ceiling refusal first, then a
    // request the ceiling admits and the child declines. Each arm has to clear.
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 128 * 1024));
    try std.testing.expect(budget.refused != null);
    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 5000));
    try std.testing.expect(budget.refused == null);

    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 128 * 1024));
    try std.testing.expect(budget.refused != null);
    try std.testing.expect(!a.resize(m, 5000));
    try std.testing.expect(budget.refused == null);

    try std.testing.expectError(error.OutOfMemory, a.alloc(u8, 128 * 1024));
    try std.testing.expect(budget.refused != null);
    try std.testing.expect(a.remap(m, 5000) == null);
    try std.testing.expect(budget.refused == null);
}

test "the whole-trace ceiling charges the decode, not only the raw read (#377)" {
    const gpa = std.testing.allocator;
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try budgetFixture("budget-decode", 100, gpa, &fbuf);

    // **This is the leg that separates a budget from an accounting pass over the raw
    // read.** Measured: this trace is 3,436 bytes of file and 22,580 bytes of budget,
    // because the decode duplicates every record's path into the same arena. The raw
    // read alone costs about 1.50x the file — some 6 KiB. A ceiling of 12 KiB is
    // therefore well clear of the raw bytes and well under the decoded trace, so an
    // implementation that charged only `readWhole` would let this through.
    var budget: TraceBudget = .{ .child = gpa, .limit = 12 * 1024 };
    var info = try readTraceCapped(&budget, std.mem.span(fz), max_trace_bytes);
    defer info.deinit();
    // Not an error: a ceiling refusal is an observation the caller answers for after it
    // has classified, like `too_large`. The read reports it on the TraceInfo.
    try std.testing.expect(info.budget_refused != null);
}

test "the whole-trace ceiling is shared: a second live trace is refused on the sum (#377)" {
    const gpa = std.testing.allocator;
    var fbuf_a: [contract.max_path]u8 = undefined;
    var fbuf_b: [contract.max_path]u8 = undefined;
    const a = try budgetFixture("budget-sum-a", 100, gpa, &fbuf_a);
    const b = try budgetFixture("budget-sum-b", 100, gpa, &fbuf_b);

    // 32 KiB admits one 22,580-byte trace and not two. **Neither trace is too large by
    // itself** — that is the whole distinction between this and `trace_too_large`, and
    // the reason the two carry different `unknown_reason` values.
    var budget: TraceBudget = .{ .child = gpa, .limit = 32 * 1024 };
    var first = try readTraceCapped(&budget, std.mem.span(a), max_trace_bytes);
    var refused = try readTraceCapped(&budget, std.mem.span(b), max_trace_bytes);
    try std.testing.expect(refused.budget_refused != null);
    refused.deinit();

    // And it is the SUM that refused, not the second file: freeing the first admits it.
    // Without this arm the test above passes for an implementation that simply refuses
    // every second read. It also pins the verdict to the read that produced it — the
    // wrapper clears the side-channel on entry, and without that this second read would
    // inherit the first refusal and report a ceiling that did not stop it.
    first.deinit();
    var second = try readTraceCapped(&budget, std.mem.span(b), max_trace_bytes);
    try std.testing.expect(second.budget_refused == null);
    second.deinit();
    try std.testing.expectEqual(@as(usize, 0), budget.used);
}

test "a read that allocates nothing does not inherit the previous refusal (#377)" {
    const gpa = std.testing.allocator;
    var fbuf_a: [contract.max_path]u8 = undefined;
    var fbuf_b: [contract.max_path]u8 = undefined;
    const a = try budgetFixture("budget-inherit-a", 100, gpa, &fbuf_a);
    const b = try budgetFixture("budget-inherit-b", 100, gpa, &fbuf_b);

    // **The case the entry reset exists for, and the only one that reaches it.** A read
    // that succeeds clears the side-channel on its own first allocation, so the reset is
    // invisible there — the mutation deleting it survived every other test in this file,
    // measured. A read that allocates NOTHING has no such moment: a missing file fails at
    // `open`, before the arena takes a byte, and returns the empty TraceInfo that means
    // "the shim never ran". Without the reset it would carry the previous read's refusal
    // and be reported as a ceiling that never stopped it.
    var budget: TraceBudget = .{ .child = gpa, .limit = 32 * 1024 };
    var first = try readTraceCapped(&budget, std.mem.span(a), max_trace_bytes);
    defer first.deinit();
    var refused = try readTraceCapped(&budget, std.mem.span(b), max_trace_bytes);
    try std.testing.expect(refused.budget_refused != null);
    refused.deinit();

    var absent = try readTraceCapped(&budget, "/tmp/sideeye-no-such-trace-for-inherit-test", max_trace_bytes);
    defer absent.deinit();
    try std.testing.expect(absent.budget_refused == null);
    try std.testing.expect(!absent.saw_shim_ready);
}

test "the whole-trace ceiling is returned by deinit, so a loop does not drift (#377)" {
    const gpa = std.testing.allocator;
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try budgetFixture("budget-loop", 100, gpa, &fbuf);

    // The world loop reads a trace per world. A budget that charged without returning
    // would refuse a long exploration for no reason the operator could act on — and it
    // would do so at a world number that depends on the ceiling, which is the kind of
    // failure nobody reproduces. Ten passes at a ceiling that fits exactly one.
    var budget: TraceBudget = .{ .child = gpa, .limit = 32 * 1024 };
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var info = try readTraceCapped(&budget, std.mem.span(fz), max_trace_bytes);
        info.deinit();
        try std.testing.expectEqual(@as(usize, 0), budget.used);
    }
}

test "a budget refusal during the RAW read returns an empty trace, not an error (#377)" {
    const gpa = std.testing.allocator;
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try budgetFixture("budget-rawread", 100, gpa, &fbuf);

    // **The shape that made the first implementation ship the wrong refusal.** This
    // function collapses every `readWhole` failure except the per-read cap into an empty
    // `TraceInfo` and returns it NORMALLY — so a budget refusal during the raw read is
    // not an error the caller can catch. It arrives as a trace with no shim marker,
    // which `main.zig` reports as `no_shim_marker`: the shim never initialised.
    //
    // Measured on a real run before this was pinned: `preflight --twice` under a lowered
    // ceiling refused the second observation with `no_shim_marker`. The unit tests at the
    // time all passed, because every one of them drove the path where the error DOES
    // propagate (the decode's `try`), and this path is the other one.
    //
    // What this pins is therefore an obligation on the caller, not a behaviour of this
    // function: after any read, a budget with `refused` set means the read was refused,
    // whether or not it returned an error.
    var budget: TraceBudget = .{ .child = gpa, .limit = 4 * 1024 };
    var info = try readTraceCapped(&budget, std.mem.span(fz), max_trace_bytes);
    defer info.deinit();
    try std.testing.expect(!info.saw_shim_ready);
    try std.testing.expectEqual(@as(usize, 0), info.ops.items.len);
    try std.testing.expect(budget.refused != null);
}

test "a success clears the budget's refusal flag, so it always names the last failure (#377)" {
    const gpa = std.testing.allocator;

    // Driven through the allocator rather than through a read, because that is the only
    // way to reach the case: `readWhole` reserves the same bytes its read loop goes on to
    // need, so no ceiling refuses the reservation and admits the loop. An earlier version
    // of this test tried it through a read, asserted a flag that was never set, and
    // survived the sticky mutation — measured, which is how this version exists.
    //
    // Why it matters: `readWhole`'s reservation failure is swallowed on purpose, so a
    // flag that remembered every refusal would let a swallowed one mark a read that then
    // succeeded. The read's own verdict would say the ceiling stopped it when nothing did.
    var budget: TraceBudget = .{ .child = gpa, .limit = 4096 };
    const alloc = budget.allocator();

    try std.testing.expectError(error.OutOfMemory, alloc.alloc(u8, 8192));
    try std.testing.expect(budget.refused != null);

    const m = try alloc.alloc(u8, 1024);
    defer alloc.free(m);
    try std.testing.expect(budget.refused == null);
}

/// An allocator that refuses any single request over `ceiling` and passes the rest
/// through. `std.testing.FailingAllocator` cannot express this: its `alloc_index` only
/// advances on success, so a `fail_index` that catches the first request catches every
/// request after it too — which tests "nothing can be allocated", a different thing from
/// "this one large reservation could not be met".
const RefuseLargeAllocator = struct {
    backing: Allocator,
    ceiling: usize,

    fn allocator(self: *RefuseLargeAllocator) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    fn alloc(ctx: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (len > self.ceiling) return null;
        return self.backing.rawAlloc(len, a, ra);
    }
    fn resize(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (n > self.ceiling) return false;
        return self.backing.rawResize(m, a, n, ra);
    }
    fn remap(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        if (n > self.ceiling) return null;
        return self.backing.rawRemap(m, a, n, ra);
    }
    fn free(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const self: *RefuseLargeAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(m, a, ra);
    }
};

test "a reservation that cannot be met does not relabel an oversized trace (#323)" {
    // #323 gave `readWhole` a reservation taken from the file's own length. This test is
    // about what happens when that reservation FAILS, and it is aimed at the call site
    // rather than the function: `readTraceCapped`'s catch collapses every error except
    // `FileTooLarge` into an empty `TraceInfo`, which the engine reads as
    // `no_shim_marker`. A reservation that returned `OutOfMemory` would therefore turn
    // "the trace is larger than this engine will read" into "the shim never initialised"
    // — the relabelling `max_trace_bytes`' own comment calls worse than having no cap.
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap-reserve", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-reserve-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }

    // Past a cap of 4 the reservation asks for `4 + one chunk`; the read loop's own
    // requests are a few hundred bytes. A ceiling between the two fails exactly the
    // reservation and nothing else, which is what separates "the reservation is a hint"
    // from "the reservation is load-bearing".
    var refuser: RefuseLargeAllocator = .{ .backing = std.testing.allocator, .ceiling = 16 * 1024 };
    var rb_ = unboundedBudget(refuser.allocator());
    var info = try readTraceCapped(&rb_, path, 4);
    defer info.deinit();

    // The answer is the cap's, not the empty read's — which is the whole point.
    try std.testing.expect(info.too_large);
    try std.testing.expect(!info.saw_shim_ready);

    // Positive control, same fixture and same allocator, under the cap: the read
    // completes. Without it, an allocator that broke every read would satisfy the line
    // above for the wrong reason — "nothing can be allocated at all" is a different
    // failure that would otherwise pass as correct here.
    var ok = try readTraceCapped(&rb_, path, 4096);
    defer ok.deinit();
    try std.testing.expect(!ok.too_large);
    try std.testing.expectEqual(@as(usize, 0), ok.ops.items.len);
}

test "an oversized trace says so, instead of collapsing into the empty read (#324)" {
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }

    // Over the cap: the flag is set and the size is the file's true length, read by
    // lseek rather than counted from the truncated read.
    var gb_ = unboundedBudget(gpa);
    var big = try readTraceCapped(&gb_, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
    try std.testing.expectEqual(@as(?u64, 10), big.too_large_size);
    // What makes this a distinct answer rather than a relabelled one: the flag the
    // caller checks for "the shim never ran" is NOT set by a capped read. Were it the
    // only signal, this trace would refuse as `no_shim_marker`.
    try std.testing.expect(!big.saw_shim_ready);
    try std.testing.expect(!big.truncated);

    // At the cap exactly, no breach — the boundary is "over", not "at" (the per-file
    // cap's boundary, kept identical so the two caps cannot drift in that detail).
    var ok = try readTraceCapped(&gb_, path, 10);
    defer ok.deinit();
    try std.testing.expect(!ok.too_large);
}

test "a cap breach and an unreadable trace are different observations (#324)" {
    const gpa = std.testing.allocator;

    // A trace that is not there at all: the empty TraceInfo, exactly as before this
    // change — the honest observation that the shim never wrote anything.
    var gb_ = unboundedBudget(gpa);
    var absent = try readTraceCapped(&gb_, "/tmp/sideeye-no-such-trace-file-does-not-exist", 4);
    defer absent.deinit();
    try std.testing.expect(!absent.too_large);
    try std.testing.expect(absent.too_large_size == null);
    try std.testing.expect(!absent.saw_shim_ready);
    try std.testing.expectEqual(@as(usize, 0), absent.ops.items.len);

    // The contrast, from the same reader: a file that exists and breaks the cap does
    // set the flag. Without this leg the assertions above pass for an implementation
    // that never sets `too_large` at all.
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap-contrast", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.fmt.bufPrintZ(&fz, "{s}", .{path}) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.fmt.bufPrintZ(&dz, "/tmp/sideeye-tracecap-contrast-{d}", .{posix.getpid()}) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }
    var big = try readTraceCapped(&gb_, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
}
