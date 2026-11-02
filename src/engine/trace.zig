const engine_build_options = @import("engine_build_options");
const std = @import("std");
const contract = @import("contract");
const posix = @import("../posix.zig");
const read = @import("read.zig");
const snapshots = @import("snapshot.zig");

const Allocator = std.mem.Allocator;

/// `PathTooLong` is nearly unreachable rather than unreachable, and the difference was
/// found in review after the first draft claimed the stronger thing. The read's
/// `printSentinel` needs one byte more than the `bufPrint` that built the same path at the
/// call site, so the window is `path.len == max_path` exactly. At the two record sites a
/// longer sibling (`stdout-record.txt`, `stdout-record-2.txt`) is formatted into an
/// equally sized buffer first and closes it. **The world loop is not closed**: its trace
/// name is `/trace-{d}.bin`, which passes `/stdout-world.txt` in length at seven digits,
/// so a work directory of 4,078 bytes and a crash point past one million reaches it.
pub const TraceReadError = error{ OutOfMemory, PathTooLong };

pub const Op = struct {
    class: contract.OpClass,
    seq: u32,
    pid: u32,
    tid: u64,
    path: []const u8,
    aux: []const u8,
};

pub const GateExempt = struct {
    root: []const u8,
    alt: []const u8,
    scratch: []const []const u8,
    initial: *const snapshots.Snapshot,

    // Not the whole exemption: what comes later in the trace is left out, so a world cut short at its
    // crash point reads an operation as its recording does.
    pub fn inertAlone(self: GateExempt, op: Op) bool {
        if (!op.class.isKillPoint()) return false;
        const first = snapshots.relUnderRoot(op.path, self.root, self.alt) orelse return false;
        const second: ?[]const u8 = if (op.class.isTwoPath()) snapshots.relUnderRoot(op.aux, self.root, self.alt) else null;
        if (op.class.isTwoPath() and second == null) return false;
        if (snapshots.scratchMatches(self.scratch, first) and (second == null or snapshots.scratchMatches(self.scratch, second.?))) return true;
        return op.class == .mkdir and (first.len == 0 or self.initial.find(first) != null);
    }
};

const Removal = struct { pid: u32, tid: u64, at: usize, paths: [2]?[]const u8, through_link: bool = false };

const GatePlan = struct {
    e: GateExempt,
    aliases: std.StringHashMapUnmanaged(void),
    removals: []const Removal,

    fn build(arena: Allocator, e: GateExempt, bytes: []const u8) error{OutOfMemory}!GatePlan {
        var plan: GatePlan = .{ .e = e, .aliases = .empty, .removals = &.{} };
        var removals: std.ArrayList(Removal) = .empty;
        for (e.initial.entries.items) |entry| {
            if (entry.kind == .symlink) try plan.aliases.put(arena, entry.rel, {});
        }
        var off: usize = 0;
        var at: usize = 0;
        while (off < bytes.len) : (at += 1) {
            const dec = contract.decodeRecord(bytes[off..]) catch break;
            off += dec.consumed;
            const r = dec.rec;
            // Not only symlinks: a name a rename or a hard link brings in can be a link, or another name
            // for a file of the state, and the record does not say which.
            switch (r.op) {
                .symlink => if (snapshots.relUnderRoot(r.path, e.root, e.alt)) |rel| try plan.aliases.put(arena, rel, {}),
                .link, .rename => if (snapshots.relUnderRoot(r.aux, e.root, e.alt)) |rel| try plan.aliases.put(arena, rel, {}),
                else => {},
            }
            // Not the new name alone: after a hard link the old name reaches the same file. A rename's old name is gone.
            if (r.op == .link) if (snapshots.relUnderRoot(r.path, e.root, e.alt)) |rel| try plan.aliases.put(arena, rel, {});
            switch (r.op) {
                .unlink, .rmdir, .rename => {
                    const second = if (r.op == .rename) snapshots.relUnderRoot(r.aux, e.root, e.alt) else null;
                    try removals.append(arena, .{ .pid = r.pid, .tid = r.tid, .at = at, .paths = .{ snapshots.relUnderRoot(r.path, e.root, e.alt), second } });
                },
                else => {},
            }
        }
        for (removals.items) |*r| {
            for (r.paths) |maybe| if (maybe) |path| if (plan.throughAlias(path, false)) {
                r.through_link = true;
            };
        }
        plan.removals = removals.items;
        return plan;
    }

    fn throughAlias(self: GatePlan, rel: []const u8, itself: bool) bool {
        if (itself and self.aliases.contains(rel)) return true;
        var i: usize = 0;
        while (std.mem.indexOfScalarPos(u8, rel, i, '/')) |slash| : (i = slash + 1) {
            if (self.aliases.contains(rel[0..slash])) return true;
        }
        return false;
    }

    // Not a byte comparison: on a case-folding filesystem `D` removes `d`.
    fn atOrAbove(removed: []const u8, name: []const u8) bool {
        if (removed.len == 0) return true;
        if (removed.len > name.len or !std.ascii.eqlIgnoreCase(removed, name[0..removed.len])) return false;
        return removed.len == name.len or name[removed.len] == '/';
    }

    fn exempt(self: GatePlan, op: Op, at: usize) bool {
        if (!self.e.inertAlone(op)) return false;
        const first = snapshots.relUnderRoot(op.path, self.e.root, self.e.alt).?;
        // Not every class through a link: a create or a remove changes the name, not the file the link reaches.
        const follows = switch (op.class) {
            .open, .write, .fsync, .truncate => true,
            else => false,
        };
        if (self.throughAlias(first, follows)) return false;
        if (op.class.isTwoPath() and self.throughAlias(snapshots.relUnderRoot(op.aux, self.e.root, self.e.alt).?, false)) return false;
        if (snapshots.scratchMatches(self.e.scratch, first)) return true;
        // Not record order between threads: a record is written before its call runs.
        for (self.removals) |r| {
            if (r.at == at) continue;
            if (r.pid == op.pid and r.tid == op.tid and r.at > at) continue;
            if (r.through_link) return false;
            for (r.paths) |maybe| if (maybe) |path| if (atOrAbove(path, first)) return false;
        }
        return true;
    }
};

fn unplacedRefuses(op: Op) bool {
    const what = contract.unresolved_kind.opOfUnlinkedFd(op.class, op.aux) orelse return true;
    return what.unplaceableRefuses();
}

pub const TraceInfo = struct {
    arena: std.heap.ArenaAllocator,
    ops: std.ArrayList(Op),
    saw_header: bool = false,
    version_mismatch: bool = false,
    saw_shim_ready: bool = false,
    /// The first, not the last: a self-exec chain announces once per image and every
    /// image installs its own filter, so a later image's answer would let a failed
    /// install in the first one pass unseen. Empty from a shim asked for the default
    /// mode, which is also what the field carried through v13.
    observe_aux: []const u8 = "",
    /// First-wins over the *refusing* records, not over every unplaceable one. An exempt
    /// record arriving first must not hide a refusing one behind it: `close` on a low
    /// descriptor before `write` on an unlinked one is an ordinary order
    /// (`TOY_CLOSE_THEN_UNLINKED_WRITE` performs exactly it — two descriptors on one
    /// unlinked file; `TOY_CLOSE_SWEEP` does NOT, because it closes descriptors before
    /// anything is unlinked, and an earlier draft of this comment credited it), and a
    /// target can append to its own trace,
    /// so a single `unlinked-fd close fd:3` written early would otherwise switch the wall
    /// off for everything after it.
    unresolved_refusing: ?Op = null,
    first_unsupported: ?[]const u8 = null,
    kill_landed_seq: ?u32 = null,

    kill_point_count: u32 = 0,
    mutation_count: u32 = 0,
    boundary: ?contract.OpClass = null,
    /// Kept separately from `boundary` because "first boundary" can be a tolerable
    /// fork that arrives before the record that must refuse the run.
    hard_boundary: ?contract.OpClass = null,
    /// The first `.detached` record: a process that left the process group (`setsid`,
    /// `setpgid`), from anyone. The engine judges it where it held the run in a cgroup of its
    /// own and refuses it everywhere else (`containment.holds`, #559). A field of its own rather
    /// than a value of `hard_boundary`, which keeps only the first hard boundary: a detach
    /// recorded first would otherwise hide an image change that must refuse, in the very run
    /// that lets the detach through.
    detached: ?Op = null,
    shim_ready_records: u32 = 0,
    cgroup_held_records: u32 = 0,
    cgroup_kill_records: u32 = 0,
    cgroup_unanswered_live: u32 = 0,
    cgroup_unanswered_tail: u32 = 0,
    subject_detached: bool = false,
    /// cgroup, kept whole for the refusal's detail. A field of its own rather than a boundary
    /// class read through `hard_boundary`, which keeps only the first boundary a trace holds —
    /// a `setsid` recorded before the escape would hide it. A `cgroup` record whose aux this
    /// engine does not name is read here too: an answer nobody can read is not an
    /// acknowledgement, and the conservative reading of it is the one that refuses.
    cgroup_outside: ?Op = null,
    cgroup_kill_returned: ?Op = null,
    cgroup_kill_alone: ?Op = null,
    thread_records: u32 = 0,
    thread_start_records: u32 = 0,
    subject_writer_tids: u32 = 0,
    /// **One entry on an ordinary single-threaded run, not zero.** The first writer of the
    /// subject's pid is appended unconditionally below, so this list is empty only for a
    /// run in which the *subject itself* wrote nothing — only kill points of the subject's
    /// own pid are appended, so a run whose state-directory writes all came from children
    /// leaves it empty too. #544 wrote "empty for a single-threaded run" here and that
    /// was false; a caller testing emptiness to mean "no threads" fires on every run.
    /// Compare against `initial_writer_tid` instead, the way `unrecorded_writer_thread`
    /// does.
    subject_writer_tid_list: std.ArrayList(u64) = .empty,
    subject_started_tid_list: std.ArrayList(u64) = .empty,
    initial_writer_tid: ?u64 = null,
    unrecorded_writer_thread: bool = false,
    second_writer_thread: ?Op = null,
    first_writer_thread: ?Op = null,
    first_writer_thread_detached: bool = false,
    thread_turns: u32 = 0,
    thread_joins: u32 = 0,
    thread_joins_unresolved: u32 = 0,
    thread_detaches: u32 = 0,
    thread_unpaired_starts: u32 = 0,
    truncated: bool = false,
    primary_pid: ?u32 = null,
    foreign_kill_point: bool = false,
    first_foreign: ?Op = null,
    foreign_pid_seen: bool = false,
    exec_continuations: u32 = 0,
    exec_chain_broken: bool = false,
    /// Not derivable from `boundary`, which keeps the FIRST class only: a target that
    /// execs and then forks would report the exec and hide the fork.
    process_boundary: bool = false,
    kill_records: u32 = 0,
    too_large: bool = false,
    too_large_size: ?u64 = null,
    /// The whole-trace ceiling refused an allocation during this read (#377). Carried on
    /// the TraceInfo rather than raised as an error for the reason `too_large` is: the
    /// caller classifies first and refuses after, so a structural UNKNOWN still reports
    /// the L0 classification that exists. Raising it instead cost exactly that — review
    /// measured `atomicity: not classified` on a recording-site refusal, because the
    /// refusal ran before the final snapshot.
    budget_refused: ?usize = null,

    pub fn deinit(self: *TraceInfo) void {
        self.arena.deinit();
    }

    pub fn cgroupAnswered(self: *const TraceInfo, cut_by_kill: bool) bool {
        if (self.shim_ready_records == 0 or self.cgroup_unanswered_live > 0) return false;
        const cut = if (cut_by_kill) self.cgroup_unanswered_tail else 0;
        return self.cgroup_held_records + cut == self.shim_ready_records;
    }

    pub fn crossedBoundary(self: TraceInfo) bool {
        return self.boundary != null or self.foreign_pid_seen;
    }

    pub fn crossedProcessBoundary(self: TraceInfo) bool {
        return self.process_boundary or self.foreign_pid_seen;
    }

    pub fn needsOracle(self: TraceInfo) bool {
        if (self.boundary) |b| {
            if (b != .thread) return true;
        }
        return self.process_boundary or self.foreign_pid_seen;
    }

    /// Every process's operations are addresses (v15). The filter that stood here —
    /// "only the subject's operations are addresses; a child's seq counts different
    /// things" — was true while a number was a position in the writing process. It is a
    /// position in the run now, so filtering by pid would leave crash point k with no
    /// address at all whenever k belongs to an awaited child, which is exactly the case
    /// this version exists to judge.
    pub fn logicalAddress(self: TraceInfo, k: u32) struct { after: ?Op, before: ?Op } {
        var after: ?Op = null;
        var before: ?Op = null;
        for (self.ops.items) |op| {
            if (!op.class.isKillPoint()) continue;
            if (op.seq == k) before = op;
            if (op.seq == k - 1) after = op;
        }
        return .{ .after = after, .before = before };
    }
};

/// It shares its value with `max_state_file_bytes` and nothing else: the two bound
/// different things and may move apart.
pub const max_trace_bytes: usize = 64 * 1024 * 1024;

/// | shape | file bytes | budget bytes | ratio |
/// |---|---|---|---|
/// | header only | 36 | 542 | 15.1x |
/// | 100 records, 16-byte paths | 3,436 | 22,580 | 6.6x |
/// | 10,000 records, 16-byte paths | 340,036 | 2,680,986 | 7.9x |
/// | 100 records, 3000-byte path and aux | 601,836 | 2,285,906 | 3.8x |
/// | 2,000 records, 3000-byte path and aux | 12,036,036 | 45,139,816 | 3.75x |
/// | 1,973,000 records, 16-byte paths | 67,082,036 | 521,200,426 | 7.77x |
/// | **3,532,000 records, 1-byte paths** | **67,108,036** | **1,523,533,632** | **22.7x** |
/// **This ceiling therefore does NOT clear one read at the per-read cap, and that is
/// deliberate.** Clearing the last row would need 1.5 GiB, and two of them 3 GiB, which
/// is the resident set the ceiling exists to prevent — an OOM kill with no report is
/// worse than a refusal that names itself. So the two ceilings **disagree about some
/// traces**: `max_trace_bytes` admits a file this one will not hold. ADR 0029 records the
/// same shape for the snapshot, where a tree can break the per-file cap and the tree
/// ceiling and which fires depends on `readdir` order.
pub const max_trace_bytes_total: usize = 512 * 1024 * 1024;

/// **Refusal happens BEFORE the allocation.** An accounting pass that reads
/// `queryCapacity()` after the bytes are held refuses a run that has already taken the
/// memory — ADR 0029 says exactly that about its own ceiling ("the run that refuses may
/// hold more"). Here the vtable answers `null` first, so the promise is that an
/// over-budget allocation does not SUCCEED, which is a thing the code can keep.
pub const TraceBudget = struct {
    child: Allocator,
    limit: usize,
    used: usize = 0,
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

pub fn unboundedBudget(child: Allocator) TraceBudget {
    return .{ .child = child, .limit = std.math.maxInt(usize) };
}

/// had written through its slot at the call, and this reader keeps, per thread, the vector
/// as it stood after each record that gave it another thread's component (its own start,
/// each join) together with the count after that record. The creator's vector at count `n`
/// is the latest such snapshot at or below `n`, with the creator's own component set to
/// `n`. The count is the one *after* the record on purpose: taken before it, a join at
/// count 3 would be filed under 2 and a child created at 2 would inherit what the join
/// brought in (review, R2 C3). The creator's records up to `n` all precede the child's
/// start in the trace — they were written before `pthread_create` was called — so the
/// snapshot the child needs is always there when its start is read; a count the creator has
/// not reached, or a creator never seen, leaves the child with no creator and no edge.
///
/// **A vector is assigned at a start, not merged.** Linux recycles thread ids; a start on
/// an id this reader already holds is a new thread, kept as a new entry so that a join
/// naming the earlier one by its (creator, ordinal) pair merges the earlier one's final
/// vector and nothing the new one wrote (review, R2 M5). The entry's count continues from
/// the old one's, because the shim's slot — found by id — does too.
const ThreadOrder = struct {
    const Snap = struct { count: u32, clock: []u32 };
    const Thread = struct {
        tid: u64,
        idx: u32,
        alive: bool = true,
        clock: std.ArrayList(u32) = .empty,
        count: u32 = 0,
        snaps: std.ArrayList(Snap) = .empty,
        last_kp: ?u32 = null,
        last_kp_op: ?Op = null,
        detached: bool = false,
        start: ?contract.thread_aux.Joined = null,
    };
    const Proc = struct {
        pid: u32,
        threads: std.ArrayList(Thread) = .empty,
        writer: ?u32 = null,
        detached_pairs: std.ArrayList(contract.thread_aux.Joined) = .empty,
    };
    const KillPointVerdict = union(enum) {
        first,
        same,
        turned,
        unordered: struct { writer_last: Op, writer_detached: bool },
    };

    procs: std.ArrayList(Proc) = .empty,

    fn proc(self: *ThreadOrder, arena: Allocator, pid: u32) !*Proc {
        for (self.procs.items) |*p| {
            if (p.pid == pid) return p;
        }
        try self.procs.append(arena, .{ .pid = pid });
        return &self.procs.items[self.procs.items.len - 1];
    }

    fn live(p: *Proc, tid: u64) ?*Thread {
        for (p.threads.items) |*t| {
            if (t.tid == tid and t.alive) return t;
        }
        return null;
    }

    fn appendThread(arena: Allocator, p: *Proc, tid: u64, count: u32) !*Thread {
        try p.threads.append(arena, .{ .tid = tid, .idx = @intCast(p.threads.items.len), .count = count });
        return &p.threads.items[p.threads.items.len - 1];
    }

    fn thread(arena: Allocator, p: *Proc, tid: u64) !*Thread {
        return live(p, tid) orelse appendThread(arena, p, tid, 0);
    }

    fn component(clock: []const u32, idx: u32) u32 {
        return if (idx < clock.len) clock[idx] else 0;
    }

    fn setComponent(arena: Allocator, clock: *std.ArrayList(u32), idx: u32, value: u32) !void {
        while (clock.items.len <= idx) try clock.append(arena, 0);
        clock.items[idx] = value;
    }

    fn tick(self: *ThreadOrder, arena: Allocator, pid: u32, tid: u64) !void {
        const p = try self.proc(arena, pid);
        const t = try thread(arena, p, tid);
        t.count += 1;
        try setComponent(arena, &t.clock, t.idx, t.count);
    }

    fn snapshot(arena: Allocator, t: *Thread) !void {
        try t.snaps.append(arena, .{ .count = t.count, .clock = try arena.dupe(u32, t.clock.items) });
    }

    fn creatorAt(arena: Allocator, p: *Proc, creator: u64, n: u32) !?std.ArrayList(u32) {
        const ct = live(p, creator) orelse return null;
        if (ct.count < n) return null;
        var base: []const u32 = &.{};
        for (ct.snaps.items) |sn| {
            if (sn.count <= n) base = sn.clock;
        }
        var clock: std.ArrayList(u32) = .empty;
        try clock.appendSlice(arena, base);
        try setComponent(arena, &clock, ct.idx, n);
        return clock;
    }

    fn started(self: *ThreadOrder, arena: Allocator, pid: u32, tid: u64, st: contract.thread_aux.Started) !bool {
        const p = try self.proc(arena, pid);
        const t = try newIncarnation(arena, p, tid);
        t.start = .{ .creator = st.creator, .ordinal = st.ordinal };
        for (p.detached_pairs.items) |d| {
            if (d.creator == st.creator and d.ordinal == st.ordinal) t.detached = true;
        }
        const own = t.count;
        const placed = try creatorAt(arena, p, st.creator, st.written);
        if (placed) |clock| {
            t.clock = clock;
            try setComponent(arena, &t.clock, t.idx, own);
        }
        try snapshot(arena, t);
        return placed != null;
    }

    fn startedUnknown(self: *ThreadOrder, arena: Allocator, pid: u32, tid: u64) !void {
        const p = try self.proc(arena, pid);
        _ = try newIncarnation(arena, p, tid);
    }

    fn newIncarnation(arena: Allocator, p: *Proc, tid: u64) !*Thread {
        const old = live(p, tid) orelse return appendThread(arena, p, tid, 0);
        if (old.count == 0 and old.start == null) return old;
        old.alive = false;
        const fresh = try appendThread(arena, p, tid, old.count);
        try setComponent(arena, &fresh.clock, fresh.idx, fresh.count);
        return fresh;
    }

    fn byStart(p: *Proc, j: contract.thread_aux.Joined) ?*Thread {
        var found: ?*Thread = null;
        for (p.threads.items) |*t| {
            if (t.start) |st| {
                if (st.creator == j.creator and st.ordinal == j.ordinal) found = t;
            }
        }
        return found;
    }

    fn joined(self: *ThreadOrder, arena: Allocator, pid: u32, tid: u64, j: contract.thread_aux.Joined) !bool {
        const p = try self.proc(arena, pid);
        const target = byStart(p, j) orelse return false;
        const t = try thread(arena, p, tid);
        for (target.clock.items, 0..) |v, i| {
            if (v > component(t.clock.items, @intCast(i))) try setComponent(arena, &t.clock, @intCast(i), v);
        }
        try snapshot(arena, t);
        return true;
    }

    fn detached(self: *ThreadOrder, arena: Allocator, pid: u32, j: contract.thread_aux.Joined) !void {
        const p = try self.proc(arena, pid);
        if (byStart(p, j)) |t| {
            t.detached = true;
        } else {
            try p.detached_pairs.append(arena, j);
        }
    }

    fn killPoint(self: *ThreadOrder, arena: Allocator, pid: u32, tid: u64, op: Op) !KillPointVerdict {
        const p = try self.proc(arena, pid);
        const t = try thread(arena, p, tid);
        defer {
            t.last_kp = t.count;
            t.last_kp_op = op;
        }
        const w_idx = p.writer orelse {
            p.writer = t.idx;
            return .first;
        };
        if (w_idx == t.idx) return .same;
        const w = &p.threads.items[w_idx];
        const ordered = component(t.clock.items, w.idx) >= (w.last_kp orelse 0);
        if (ordered) {
            p.writer = t.idx;
            return .turned;
        }
        return .{ .unordered = .{ .writer_last = w.last_kp_op orelse op, .writer_detached = w.detached } };
    }

    fn knows(self: *const ThreadOrder, pid: u32) bool {
        for (self.procs.items) |*p| {
            if (p.pid == pid) return true;
        }
        return false;
    }

    fn reset(self: *ThreadOrder, pid: u32) void {
        for (self.procs.items, 0..) |*p, i| {
            if (p.pid == pid) {
                _ = self.procs.swapRemove(i);
                return;
            }
        }
    }
};

fn probeVerdict(seq: u32, pid: u32, tid: u64, verdict: []const u8) void {
    const path = std.c.getenv("SIDEEYE_HANDOFF_PROBE") orelse return;
    const fd = std.c.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true }, @as(std.c.mode_t, 0o644));
    if (fd < 0) return;
    defer _ = std.c.close(fd);
    var buf: [128]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "verdict seq={d} pid={d} tid={d} {s}\n", .{ seq, pid, tid, verdict }) catch return;
    _ = std.c.write(fd, line.ptr, line.len);
}

pub fn readTrace(budget: *TraceBudget, path: []const u8) TraceReadError!TraceInfo {
    return readTraceCapped(budget, path, max_trace_bytes);
}

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
    return readTraceGated(budget, path, max, null);
}

pub fn readTraceGated(budget: *TraceBudget, path: []const u8, max: usize, gate: ?GateExempt) TraceReadError!TraceInfo {
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

    var info = readTraceCappedInner(budget, path, max, gate) catch |err| {
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

fn readTraceCappedInner(budget: *TraceBudget, path: []const u8, max: usize, gate: ?GateExempt) TraceReadError!TraceInfo {
    var info: TraceInfo = .{
        .arena = std.heap.ArenaAllocator.init(budget.allocator()),
        .ops = .empty,
    };
    errdefer info.arena.deinit();
    const arena = info.arena.allocator();

    var path_buf: [contract.max_path]u8 = undefined;
    const path_z = std.mem.printSentinel(&path_buf, "{s}", .{path}, 0) catch return error.PathTooLong;

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

    var pending_exec = false;
    var pending_base: u32 = 0;
    var awaiting_answer: std.ArrayList(u32) = .empty;

    var order: ThreadOrder = .{};
    var subject_tids: std.ArrayList(u64) = .empty;
    // Not in the trace's arena: the plan is needed only while this read lasts.
    var gate_arena = std.heap.ArenaAllocator.init(budget.allocator());
    defer gate_arena.deinit();
    const gate_plan: ?GatePlan = if (gate) |g| try GatePlan.build(gate_arena.allocator(), g, bytes[off..]) else null;
    var at: usize = 0;

    while (off < bytes.len) : (at += 1) {
        const dec = contract.decodeRecord(bytes[off..]) catch {
            info.truncated = true;
            break;
        };
        off += dec.consumed;
        const op: Op = .{
            .class = dec.rec.op,
            .seq = dec.rec.seq,
            .pid = dec.rec.pid,
            .tid = dec.rec.tid,
            .path = try arena.dupe(u8, dec.rec.path),
            .aux = try arena.dupe(u8, dec.rec.aux),
        };
        // Every record advances its thread's clock and count (v18) — except a thread's own
        // start, which the shim writes from a stack buffer outside the slot whose count the
        // creator reports, so the two sides count the same records. Whether an announcement
        // is a process's first is read before the tick, which would make the process known.
        const announced_again = op.class == .shim_ready and order.knows(op.pid);
        if (op.class != .thread_started) try order.tick(arena, op.pid, op.tid);
        switch (op.class) {
            .thread_started => {
                info.thread_start_records += 1;
                if (info.primary_pid != null and op.pid == info.primary_pid.?) try info.subject_started_tid_list.append(arena, op.tid);
                if (contract.thread_aux.parseStarted(op.aux)) |st| {
                    if (!try order.started(arena, op.pid, op.tid, st)) info.thread_unpaired_starts += 1;
                } else {
                    try order.startedUnknown(arena, op.pid, op.tid);
                    info.thread_unpaired_starts += 1;
                }
            },
            .thread_join => {
                if (contract.thread_aux.parseJoined(op.aux)) |j| {
                    if (try order.joined(arena, op.pid, op.tid, j)) info.thread_joins += 1 else info.thread_joins_unresolved += 1;
                } else info.thread_joins_unresolved += 1;
            },
            .thread_detach => {
                info.thread_detaches += 1;
                if (contract.thread_aux.parseJoined(op.aux)) |j| try order.detached(arena, op.pid, j);
            },
            .shim_ready => {
                info.saw_shim_ready = true;
                info.shim_ready_records += 1;
                // The announcement itself is counted by the shim — `init` writes it through
                // the slot — so it is counted again here, after the reset took the tick above
                // with everything else. Left uncounted, the surviving thread's count trailed
                // the shim's by one for the rest of the run and a child created after a write
                // inherited that write (review, P0). A process announcing itself for the first
                // time is left as the tick above made it: dropping and remaking its entry cost
                // the arena enough to push the trace-budget apparatus's 3 KiB ceiling on the
                // recording read (the container acceptance measured it).
                if (announced_again) {
                    order.reset(op.pid);
                    try order.tick(arena, op.pid, op.tid);
                }
                if (std.mem.indexOfScalar(u32, awaiting_answer.items, op.pid) != null)
                    info.cgroup_unanswered_live += 1
                else
                    try awaiting_answer.append(arena, op.pid);
                if (info.primary_pid == null) {
                    info.primary_pid = op.pid;
                    info.observe_aux = op.aux;
                    // The thread that ran `init`, kept so that "a worker wrote" can be told
                    // from "the main thread wrote" on a run where the shim recorded no
                    // thread creation at all (#543). Not re-set on a later announcement:
                    // an exec'd image re-announces from whichever thread survived, and the
                    // question this answers is about the run's own initial thread.
                    info.initial_writer_tid = op.tid;
                } else if (pending_exec and op.pid == info.primary_pid.?) {
                    if (op.seq == pending_base) {
                        info.exec_continuations += 1;
                    } else {
                        info.exec_chain_broken = true;
                        if (info.hard_boundary == null) info.hard_boundary = .exec;
                    }
                    pending_exec = false;
                } else if (op.pid == info.primary_pid.?) {
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
            },
            .unresolved => {
                if (info.unresolved_refusing == null and unplacedRefuses(op))
                    info.unresolved_refusing = op;
            },
            .unsupported => {
                if (info.first_unsupported == null) info.first_unsupported = op.path;
            },
            .cgroup => {
                if (std.mem.indexOfScalar(u32, awaiting_answer.items, op.pid)) |i| _ = awaiting_answer.swapRemove(i);
                if (std.mem.eql(u8, op.aux, contract.cgroup_aux.held)) {
                    info.cgroup_held_records += 1;
                } else if (std.mem.eql(u8, op.aux, contract.cgroup_aux.held_kill)) {
                    info.cgroup_held_records += 1;
                    info.cgroup_kill_records += 1;
                } else if (std.mem.eql(u8, op.aux, contract.cgroup_aux.kill_returned)) {
                    if (info.cgroup_kill_returned == null) info.cgroup_kill_returned = op;
                } else if (std.mem.eql(u8, op.aux, contract.cgroup_aux.kill_alone)) {
                    if (info.cgroup_kill_alone == null) info.cgroup_kill_alone = op;
                } else if (info.cgroup_outside == null) {
                    info.cgroup_outside = op;
                }
            },
            else => {},
        }
        if (op.class != .shim_ready and op.class != .cgroup) {
            if (std.mem.indexOfScalar(u32, awaiting_answer.items, op.pid)) |i| {
                info.cgroup_unanswered_live += 1;
                _ = awaiting_answer.swapRemove(i);
            }
        }
        info.cgroup_unanswered_tail = @intCast(awaiting_answer.items.len);
        const is_primary = info.primary_pid != null and op.pid == info.primary_pid.?;
        if (!is_primary) {
            info.foreign_pid_seen = true;
            if (op.class.isKillPoint() or op.class == .kill_landed) {
                info.foreign_kill_point = true;
                if (info.first_foreign == null) info.first_foreign = op;
            }
        }
        if (op.class.isKillPoint()) {
            info.kill_point_count = @max(info.kill_point_count, op.seq);
            info.kill_records += 1;
            if (op.class.isMutation()) info.mutation_count += 1;
            const gate_exempt = if (gate_plan) |g| g.exempt(op, at) else false;
            if (!gate_exempt) switch (blk: {
                const v = try order.killPoint(arena, op.pid, op.tid, op);
                if (engine_build_options.handoff_probe) probeVerdict(op.seq, op.pid, op.tid, @tagName(v));
                break :blk v;
            }) {
                .first, .same => {},
                .turned => info.thread_turns += 1,
                .unordered => |u| {
                    if (info.second_writer_thread == null) {
                        info.second_writer_thread = op;
                        info.first_writer_thread = u.writer_last;
                        info.first_writer_thread_detached = u.writer_detached;
                    }
                },
            };
            if (is_primary) {
                var seen = false;
                for (subject_tids.items) |t| {
                    if (t == op.tid) seen = true;
                }
                if (!seen) {
                    try subject_tids.append(arena, op.tid);
                    info.subject_writer_tids = @intCast(subject_tids.items.len);
                }
            }
        }
        if (op.class.isBoundary()) {
            if (info.boundary == null) info.boundary = op.class;
            if (op.class == .thread) info.thread_records += 1;
            if (op.class == .detached and is_primary) info.subject_detached = true;
            if (!((op.class == .exec and is_primary) or op.class == .thread or (op.class == .detached and is_primary))) info.process_boundary = true;
            const hard = switch (op.class) {
                .detached => blk: {
                    if (info.detached == null) info.detached = op;
                    break :blk false;
                },
                .thread => false,
                .exec => blk: {
                    if (info.primary_pid == null) break :blk true;
                    if (!is_primary) break :blk false;
                    // The base is REFRESHED rather than left standing, and that is part
                    // of the fix rather than a courtesy: the shim carries the count as it
                    // stands when `exec` is CALLED, and the call that succeeds is the
                    // last attempt, so a wrapper that writes state between two attempts
                    // announces the later count. A stale base would fail the comparison
                    // below and refuse a chain that held.
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
    if (pending_exec) {
        info.exec_chain_broken = true;
        if (info.hard_boundary == null) info.hard_boundary = .exec;
    }
    info.subject_writer_tid_list = subject_tids;
    // A writer the shim never saw created (#543). Asked only when it recorded no thread
    // creation at all — and NOT because two clauses would be redundant, which is what an
    // earlier version of this comment said. With a `.thread` record present the question
    // cannot be answered at all: that record carries the id of the thread that CALLED
    // `pthread_create`, never the id of the thread it made, so a writer that is not the
    // initial thread may be one the shim counted or one it missed and nothing here
    // separates them. Such a run gets the counting clause, and `docs/report-schema.md`
    // states that limit rather than leaving it to be found.
    //
    // Against the initial thread's id, NOT against the list being non-empty — the first
    // writer of the subject's pid is appended unconditionally above, so an ordinary
    // single-threaded run has exactly one entry and an emptiness test fires on every run.
    //
    // And not at all once the image changed. The inference here is "a tid that is not the
    // initial one means a thread the shim did not see created", and an `exec` breaks it on
    // Darwin: `pthread_threadid_np`, which is where the shim's tid comes from there
    // (`shim/src/common.zig`), returns a DIFFERENT id to the same surviving thread after an
    // exec — measured on this host, five runs of a self-exec, same pid and a new id every
    // time. A single-threaded target whose writes all happen after the image change would
    // then be told that a thread the shim never recorded wrote, which is false: it is the
    // same thread, renamed. The run where both sides write is refused by the thread rule
    // above before this matters, and that refusal is itself wrong on Darwin for the same
    // reason — but that is a v16 defect this flag did not introduce and cannot fix here,
    // because `writer_tids` keys on the pid alone and has no notion of an image change.
    if (info.thread_records == 0 and info.thread_start_records == 0 and info.exec_continuations == 0) {
        if (info.initial_writer_tid) |main_tid| {
            for (subject_tids.items) |t| {
                if (t != main_tid) {
                    info.unrecorded_writer_thread = true;
                    break;
                }
            }
        }
    }
    return info;
}

fn joinZ(buf: []u8, a: []const u8, b: []const u8) error{PathTooLong}![:0]const u8 {
    const s = std.mem.printSentinel(buf, "{s}/{s}", .{ a, b }, 0) catch return error.PathTooLong;
    return s;
}

test "a trace written against another contract version is a mismatch, not a short trace" {
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
    const dz = std.mem.printSentinel(&pbuf, "{s}", .{dir}, 0) catch unreachable;
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
    try std.testing.expect(!info.truncated);
    try std.testing.expect(info.saw_header);

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
    const dz = std.mem.printSentinel(&pbuf, "{s}", .{dir}, 0) catch unreachable;
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
    var fbuf: [contract.max_path]u8 = undefined;
    const real = try writeTraceForTest("trace-link", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);

    // The link sits beside the trace and points at it, so the two names differ in nothing
    // except being a link. Reading the target directly is the control: without it, a
    // `readTrace` that had started refusing everything would satisfy the assertion below.
    var lbuf: [contract.max_path]u8 = undefined;
    const link = std.mem.printSentinel(&lbuf, "{s}.link", .{std.mem.span(real)}, 0) catch unreachable;
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

    var through = try readTrace(&tb_, std.mem.span(link.ptr));
    defer through.deinit();
    try std.testing.expect(!through.saw_header);
    try std.testing.expect(!through.saw_shim_ready);
}

test "cgroup records count against announcements, and an escape or a returned kill is kept whole (v17, #559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const path = try writeTraceForTest("trace-cgroup-ack", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = contract.cgroup_aux.held_kill },
        .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = contract.cgroup_aux.held },
        .{ .op = .write, .seq = 1, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = contract.cgroup_aux.outside },
        .{ .op = .cgroup, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = contract.cgroup_aux.kill_returned },
        .{ .op = .cgroup, .seq = 1, .pid = 9, .tid = 9, .path = "/tmp/s/a", .aux = contract.cgroup_aux.kill_alone },
    }, &fbuf);
    defer _ = posix.unlink(path);

    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(path));
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 2), info.shim_ready_records);
    try std.testing.expectEqual(@as(u32, 2), info.cgroup_held_records);
    try std.testing.expectEqual(@as(u32, 1), info.cgroup_kill_records);
    try std.testing.expect(info.cgroupAnswered(false));
    try std.testing.expectEqual(@as(u32, 8), info.cgroup_outside.?.pid);
    try std.testing.expectEqual(@as(u32, 7), info.cgroup_kill_returned.?.pid);
    try std.testing.expectEqual(@as(u32, 9), info.cgroup_kill_alone.?.pid);
    try std.testing.expectEqual(@as(u32, 1), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 1), info.kill_records);
}

test "an announcement without an acknowledgement is an uncontained run, and an aux nobody names is not an answer (v17, #559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const path = try writeTraceForTest("trace-cgroup-short", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = contract.cgroup_aux.held },
        .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "cgroup:a-later-value" },
    }, &fbuf);
    defer _ = posix.unlink(path);

    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(path));
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 2), info.shim_ready_records);
    try std.testing.expectEqual(@as(u32, 1), info.cgroup_held_records);
    try std.testing.expect(!info.cgroupAnswered(false));
    try std.testing.expectEqual(@as(u32, 1), info.cgroup_unanswered_tail);
    try std.testing.expectEqualStrings("cgroup:a-later-value", info.cgroup_outside.?.aux);
    try std.testing.expect(info.cgroup_kill_returned == null);
    try std.testing.expect(info.cgroup_kill_alone == null);

    // Control: a trace with no announcement acknowledges nothing, however few records it
    // is short by — zero equals zero, and that must not read as contained.
    const empty = try writeTraceForTest("trace-cgroup-none", &.{
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(empty);
    var none = try readTrace(&tb_, std.mem.span(empty));
    defer none.deinit();
    try std.testing.expect(!none.cgroupAnswered(false));
    try std.testing.expect(!none.cgroupAnswered(true));
}

test "a subject exec followed by a shim_ready carrying the count is a continuation (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-cont", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    try std.testing.expectEqual(@as(u32, 3), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 3), info.kill_records);
    _ = posix.unlink(fz);
}

test "an awaited child's operations are numbered in the run, and hold crash-point addresses (v15)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("run-numbering", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .rename, .seq = 2, .pid = 8, .tid = 8, .path = "/tmp/s/a", .aux = "/tmp/s/b" },
        .{ .op = .write, .seq = 3, .pid = 7, .tid = 7, .path = "/tmp/s/c", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    try std.testing.expectEqual(@as(u32, 3), info.kill_records);
    try std.testing.expectEqual(@as(u32, 3), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 3), info.mutation_count);
    try std.testing.expect(info.foreign_kill_point);
    try std.testing.expectEqual(@as(u32, 8), info.first_foreign.?.pid);

    const addr2 = info.logicalAddress(2);
    try std.testing.expectEqual(contract.OpClass.rename, addr2.before.?.class);
    try std.testing.expectEqual(@as(u32, 8), addr2.before.?.pid);
    try std.testing.expectEqualStrings("/tmp/s/a", addr2.after.?.path);
    const addr3 = info.logicalAddress(3);
    try std.testing.expectEqual(contract.OpClass.rename, addr3.after.?.class);
    _ = posix.unlink(fz);
}

test "two processes taking one number disagree with the record count (v15)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("run-numbering-dup", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 8, .tid = 8, .path = "/tmp/s/b", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 9, .tid = 9, .path = "/tmp/s/c", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 3), info.kill_records);
    try std.testing.expectEqual(@as(u32, 2), info.kill_point_count);
    try std.testing.expect(info.kill_records != info.kill_point_count);
    _ = posix.unlink(fz);
}

test "a subject exec whose shim_ready restarts at zero is a broken chain, and the renumbering is caught (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-restart", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    try std.testing.expectEqual(@as(u32, 3), info.kill_records);
    try std.testing.expectEqual(@as(u32, 2), info.kill_point_count);
    _ = posix.unlink(fz);
}

test "a subject exec with no shim_ready after it is a broken chain (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-dark", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "a second announcement with no exec record is itself an image change (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("dup-announce", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "the first unplaceable record is kept whole, with its kind and the name it had (#485)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("unresolved-first", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/doomed", .aux = "write-after-unlink" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "link-by-descriptor" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const u = info.unresolved_refusing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("write-after-unlink", u.aux);
    try std.testing.expectEqualStrings("/tmp/s/doomed", u.path);
    try std.testing.expectEqual(@as(u32, 7), u.pid);
    _ = posix.unlink(fz);
}

test "an exempt record does not hide the refusing one behind it" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("unresolved-order", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "unlinked-fd close fd:3" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "unlinked-fd write fd:4" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const u = info.unresolved_refusing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("unlinked-fd write fd:4", u.aux);
    try std.testing.expectEqualStrings("/tmp/s/b", u.path);
    _ = posix.unlink(fz);
}

test "a trace whose only unplaceable record is an exempt close leaves nothing to refuse on" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("unresolved-exempt", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "unlinked-fd close fd:3" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    try std.testing.expect(info.unresolved_refusing == null);
    _ = posix.unlink(fz);
}

test "an unplaceable record with no name is still kept, so the refusal can say there was none (#485)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("unresolved-noname", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "trace-closed-by-target" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const u = info.unresolved_refusing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("trace-closed-by-target", u.aux);
    try std.testing.expectEqual(@as(usize, 0), u.path.len);
    _ = posix.unlink(fz);
}

test "failed exec attempts before the one that lands are not image changes" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-retry", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    try std.testing.expectEqual(@as(u32, 2), info.kill_point_count);
    try std.testing.expectEqual(@as(u32, 2), info.kill_records);
    _ = posix.unlink(fz);
}

test "the continuation base follows the attempts, so a write between them still lands" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-retry-write", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    _ = posix.unlink(fz);
}

test "retried attempts do not excuse a wrong base: the chain still breaks (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-retry-wrongbase", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "retried attempts with nobody announcing at the end still break the chain (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-retry-dark", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.exec_chain_broken);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    _ = posix.unlink(fz);
}

test "an exec recorded before the subject announced itself is still hard (#123)" {
    // Negative control 3 of 3, and the one the other two cannot stand in for. Both of
    // those go red through code that sets `exec_chain_broken` on its own — the
    // wrong-base comparison and the end-of-trace check — so a mutation that stops the
    // `.exec` arm returning `hard` at all survives them. After this change that arm
    // has exactly one path left to `hard`: a record before the subject is known, which
    // is also the arm whose refusal says "before the subject announced itself".
    // Distinguished from the two above by `exec_chain_broken` being FALSE: nothing
    // established that a chain broke, and refusing is the safe misreading.
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-before-ready", &.{
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    try std.testing.expect(!info.exec_chain_broken);
    _ = posix.unlink(fz);
}

test "a child's exec never opens a continuation window and stays tolerable (#123)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("exec-child", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 9, .tid = 9, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 9, .tid = 9, .path = "/tmp/s/c", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 9, .tid = 9, .path = "/tmp/s/d", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();
    try std.testing.expect(info.hard_boundary == null);
    try std.testing.expect(!info.exec_chain_broken);
    try std.testing.expect(info.foreign_kill_point);
    const ff = info.first_foreign orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(contract.OpClass.write, ff.class);
    try std.testing.expectEqual(@as(u32, 9), ff.pid);
    try std.testing.expectEqualStrings("/tmp/s/c", ff.path);
    _ = posix.unlink(fz);
}

fn traceFixture(tag: []const u8, bytes: []const u8, path_out: []u8) ?[]const u8 {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.mem.printSentinel(&pbuf, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }, 0) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return null);
    const path = std.fmt.bufPrint(path_out, "{s}/trace.bin", .{base}) catch unreachable;
    var fz: [contract.max_path]u8 = undefined;
    const file_z = std.mem.printSentinel(&fz, "{s}", .{path}, 0) catch unreachable;
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return null;
    _ = posix.write(fd, bytes.ptr, bytes.len);
    _ = posix.close(fd);
    return path;
}

fn budgetFixture(tag: []const u8, n: usize, gpa: Allocator, fbuf: *[contract.max_path]u8) ![*:0]const u8 {
    const recs = try gpa.alloc(contract.Record, n + 1);
    defer gpa.free(recs);
    const p16 = "pppppppppppppppp";
    recs[0] = .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" };
    for (recs[1..], 0..) |*r, i| r.* = .{ .op = .write, .seq = @intCast(i + 1), .pid = 7, .tid = 7, .path = p16, .aux = "" };
    return writeTraceForTest(tag, recs, fbuf);
}

test "MEASURE what a trace costs the budget, by shape (#377, ADR 0033)" {
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
        .{ .tag = "cap1", .n = 3532000, .plen = 1, .alen = 0 },
    };
    inline for (shapes) |s| {
        var pbuf: [contract.max_path]u8 = undefined;
        @memset(&pbuf, 'p');
        var abuf: [contract.max_path]u8 = undefined;
        @memset(&abuf, 'x');
        const recs = try gpa.alloc(contract.Record, s.n + 1);
        defer gpa.free(recs);
        recs[0] = .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" };
        for (recs[1..], 0..) |*r, i| r.* = .{
            .op = .write,
            .seq = @intCast(i + 1),
            .pid = 7,
            .tid = 7,
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

test "the ceiling covers resize and remap called through the allocator interface (#377)" {
    const gpa = std.testing.allocator;

    // Not through a trace read: `ArenaAllocator` never asks its child to `remap`, and
    // whether a read reaches `resize` depends on the child growing a node in place, so
    // neither arm would be pinned by a read.
    var budget: TraceBudget = .{ .child = gpa, .limit = 4096 };
    const a = budget.allocator();

    const m = try a.alloc(u8, 2048);
    try std.testing.expectEqual(@as(usize, 2048), budget.used);

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

    var refuser: RefuseLargeAllocator = .{ .backing = gpa, .ceiling = 4096 };
    var budget: TraceBudget = .{ .child = refuser.allocator(), .limit = 64 * 1024 };
    const a = budget.allocator();

    const m = try a.alloc(u8, 2048);
    defer a.free(m);

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
    try std.testing.expect(info.budget_refused != null);
}

test "the whole-trace ceiling is shared: a second live trace is refused on the sum (#377)" {
    const gpa = std.testing.allocator;
    var fbuf_a: [contract.max_path]u8 = undefined;
    var fbuf_b: [contract.max_path]u8 = undefined;
    const a = try budgetFixture("budget-sum-a", 100, gpa, &fbuf_a);
    const b = try budgetFixture("budget-sum-b", 100, gpa, &fbuf_b);

    // Not std.testing.allocator as the child: whether the arena grows its node in place
    // depends on what that allocator still holds from earlier tests and on the OS, and a
    // read's cost moves with it — one read fitting and two not would then be luck.
    const backing = try gpa.alloc(u8, 1 << 20);
    defer gpa.free(backing);
    var fba = std.heap.FixedBufferAllocator.init(backing);
    var budget: TraceBudget = .{ .child = fba.allocator(), .limit = 64 * 1024 };
    var first = try readTraceCapped(&budget, std.mem.span(a), max_trace_bytes);
    try std.testing.expect(first.budget_refused == null);
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

    // Not std.testing.allocator as the child, for the reason the test above gives.
    const backing = try gpa.alloc(u8, 1 << 20);
    defer gpa.free(backing);
    var fba = std.heap.FixedBufferAllocator.init(backing);
    var budget: TraceBudget = .{ .child = fba.allocator(), .limit = 64 * 1024 };
    var first = try readTraceCapped(&budget, std.mem.span(a), max_trace_bytes);
    defer first.deinit();
    try std.testing.expect(first.budget_refused == null);
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
    var pbuf: [contract.max_path]u8 = undefined;
    const path = traceFixture("tracecap-reserve", "0123456789", &pbuf) orelse return error.SkipZigTest;
    defer {
        var fz: [contract.max_path]u8 = undefined;
        const file_z = std.mem.printSentinel(&fz, "{s}", .{path}, 0) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.mem.printSentinel(&dz, "/tmp/sideeye-tracecap-reserve-{d}", .{posix.getpid()}, 0) catch unreachable;
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
        const file_z = std.mem.printSentinel(&fz, "{s}", .{path}, 0) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.mem.printSentinel(&dz, "/tmp/sideeye-tracecap-{d}", .{posix.getpid()}, 0) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }

    var gb_ = unboundedBudget(gpa);
    var big = try readTraceCapped(&gb_, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
    try std.testing.expectEqual(@as(?u64, 10), big.too_large_size);
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
        const file_z = std.mem.printSentinel(&fz, "{s}", .{path}, 0) catch unreachable;
        _ = posix.unlink(file_z.ptr);
        var dz: [contract.max_path]u8 = undefined;
        const dir_z = std.mem.printSentinel(&dz, "/tmp/sideeye-tracecap-contrast-{d}", .{posix.getpid()}, 0) catch unreachable;
        _ = posix.rmdir(dir_z.ptr);
    }
    var big = try readTraceCapped(&gb_, path, 4);
    defer big.deinit();
    try std.testing.expect(big.too_large);
}

test "two threads of one process writing the judged directory are the refusal, and both are named (v16)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("two-writing-threads", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .open, .seq = 3, .pid = 7, .tid = 9, .path = "/tmp/s/b", .aux = "" },
        .{ .op = .write, .seq = 4, .pid = 7, .tid = 9, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const second = info.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 9), second.tid);
    try std.testing.expectEqual(contract.OpClass.open, second.class);
    try std.testing.expectEqualStrings("/tmp/s/b", second.path);
    const first = info.first_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 7), first.tid);
    try std.testing.expectEqualStrings("/tmp/s/a", first.path);
    try std.testing.expectEqual(@as(u32, 2), info.subject_writer_tids);
    try std.testing.expectEqual(@as(u32, 1), info.thread_records);
    try std.testing.expectEqual(@as(?contract.OpClass, null), info.hard_boundary);
    try std.testing.expect(!info.process_boundary);
    try std.testing.expect(!info.needsOracle());
    try std.testing.expect(info.crossedBoundary());
    _ = posix.unlink(fz);
}

test "one writing thread among several is judged: no second writer, one id counted (v16)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("one-writing-thread", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .close, .seq = 0, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(?Op, null), info.first_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), info.subject_writer_tids);
    try std.testing.expectEqual(@as(u32, 2), info.thread_records);
    try std.testing.expect(!info.needsOracle());
    _ = posix.unlink(fz);
}

test "a child's two writing threads refuse the same way, and are not the subject's count (v16)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("child-two-threads", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .fork, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .mkdir, .seq = 1, .pid = 8, .tid = 8, .path = "/tmp/s/d.tmp", .aux = "" },
        .{ .op = .open, .seq = 2, .pid = 8, .tid = 11, .path = "/tmp/s/d/db", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const second = info.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 8), second.pid);
    try std.testing.expectEqual(@as(u64, 11), second.tid);
    try std.testing.expectEqual(@as(u32, 0), info.subject_writer_tids);
    try std.testing.expect(info.needsOracle());
    _ = posix.unlink(fz);
}

test "a writer the shim never recorded creating is named, and an ordinary run is not (v16, #543)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const unrecorded = try writeTraceForTest("unrecorded-writer", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_a = unboundedBudget(std.testing.allocator);
    var a = try readTrace(&tb_a, std.mem.span(unrecorded));
    defer a.deinit();
    try std.testing.expectEqual(@as(u32, 0), a.thread_records);
    try std.testing.expectEqual(@as(?u64, 7), a.initial_writer_tid);
    try std.testing.expect(a.unrecorded_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), a.subject_writer_tids);
    try std.testing.expect(a.second_writer_thread == null);
    _ = posix.unlink(unrecorded);

    // The control that matters most: an ordinary single-threaded run. Its
    // `subject_writer_tid_list` has ONE entry — the first writer of the subject's pid is
    // appended unconditionally — so a condition written as "the list is not empty" fires
    // on every run ever recorded. #544's doc said "empty for a single-threaded run" and
    // that was false; this is the assertion that stops the next reader believing it.
    var fbuf2: [contract.max_path]u8 = undefined;
    const plain = try writeTraceForTest("plain-single-thread", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf2);
    var tb_b = unboundedBudget(std.testing.allocator);
    var b = try readTrace(&tb_b, std.mem.span(plain));
    defer b.deinit();
    try std.testing.expectEqual(@as(usize, 1), b.subject_writer_tid_list.items.len);
    try std.testing.expect(!b.unrecorded_writer_thread);
    _ = posix.unlink(plain);

    var fbuf3: [contract.max_path]u8 = undefined;
    const recorded = try writeTraceForTest("recorded-worker", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .thread, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf3);
    var tb_c = unboundedBudget(std.testing.allocator);
    var c = try readTrace(&tb_c, std.mem.span(recorded));
    defer c.deinit();
    try std.testing.expectEqual(@as(u32, 1), c.thread_records);
    try std.testing.expect(!c.unrecorded_writer_thread);
    _ = posix.unlink(recorded);

    var fbuf4: [contract.max_path]u8 = undefined;
    const after_exec = try writeTraceForTest("renamed-by-exec", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .exec, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 9, .path = "/tmp/s", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf4);
    var tb_d = unboundedBudget(std.testing.allocator);
    var d = try readTrace(&tb_d, std.mem.span(after_exec));
    defer d.deinit();
    try std.testing.expectEqual(@as(u32, 1), d.exec_continuations);
    try std.testing.expect(!d.exec_chain_broken);
    try std.testing.expectEqual(@as(?u64, 7), d.initial_writer_tid);
    try std.testing.expectEqual(@as(u32, 1), d.subject_writer_tids);
    try std.testing.expect(d.second_writer_thread == null);
    try std.testing.expect(!d.unrecorded_writer_thread);
    _ = posix.unlink(after_exec);
}

test "the shim's slot-exhaustion notice is an unplaceable record the run refuses on (v16)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("slots-exhausted", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .open, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .unresolved, .seq = 0, .pid = 7, .tid = 71, .path = "", .aux = contract.unresolved_kind.thread_slots_exhausted },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    const u = info.unresolved_refusing orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(contract.unresolved_kind.thread_slots_exhausted, u.aux);
    try std.testing.expectEqual(@as(u64, 71), u.tid);
    _ = posix.unlink(fz);
}

test "the subject's writer count is distinct thread ids, not a flag that stops at two (v16)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest("three-writing-threads", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .write, .seq = 2, .pid = 7, .tid = 9, .path = "/tmp/s/b", .aux = "" },
        .{ .op = .write, .seq = 3, .pid = 7, .tid = 11, .path = "/tmp/s/c", .aux = "" },
        .{ .op = .write, .seq = 4, .pid = 7, .tid = 9, .path = "/tmp/s/b", .aux = "" },
    }, &fbuf);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(fz));
    defer info.deinit();

    try std.testing.expectEqual(@as(u32, 3), info.subject_writer_tids);
    const second = info.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 9), second.tid);
    _ = posix.unlink(fz);
}

test "a detach is kept apart from the hard boundary, so an image change after it still refuses (#559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const path = try writeTraceForTest("trace-detach-then-exec", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(path);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(path));
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 8), info.detached.?.pid);
    try std.testing.expectEqual(contract.OpClass.exec, info.hard_boundary.?);
    try std.testing.expect(info.crossedProcessBoundary());

    const alone = try writeTraceForTest("trace-detach-alone", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(alone);
    var tb2 = unboundedBudget(std.testing.allocator);
    var only = try readTrace(&tb2, std.mem.span(alone));
    defer only.deinit();
    try std.testing.expect(only.detached != null);
    try std.testing.expect(only.hard_boundary == null);
}

test "an announcement the crash point's kill cut off is not a process that escaped, and one that went on without answering is (#559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const cut = try writeTraceForTest("trace-cgroup-cut", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = contract.cgroup_aux.held_kill },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
        .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .kill_landed, .seq = 2, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(cut);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(cut));
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 1), info.cgroup_unanswered_tail);
    try std.testing.expectEqual(@as(u32, 0), info.cgroup_unanswered_live);
    try std.testing.expect(info.cgroupAnswered(true));
    try std.testing.expect(!info.cgroupAnswered(false));

    const went_on = try writeTraceForTest("trace-cgroup-went-on", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .cgroup, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = contract.cgroup_aux.held_kill },
        .{ .op = .shim_ready, .seq = 0, .pid = 8, .tid = 8, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 8, .tid = 8, .path = "", .aux = "" },
        .{ .op = .kill_landed, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(went_on);
    var tb2 = unboundedBudget(std.testing.allocator);
    var on = try readTrace(&tb2, std.mem.span(went_on));
    defer on.deinit();
    try std.testing.expectEqual(@as(u32, 1), on.cgroup_unanswered_live);
    try std.testing.expectEqual(@as(u32, 0), on.cgroup_unanswered_tail);
    try std.testing.expect(!on.cgroupAnswered(true));
}

test "the subject leaving its own process group is not a second process, and a child leaving it is (#559)" {
    var fbuf: [contract.max_path]u8 = undefined;
    const own = try writeTraceForTest("trace-subject-detach", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 7, .tid = 7, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(own);
    var tb_ = unboundedBudget(std.testing.allocator);
    var info = try readTrace(&tb_, std.mem.span(own));
    defer info.deinit();
    try std.testing.expect(info.subject_detached);
    try std.testing.expect(info.detached != null);
    try std.testing.expect(!info.process_boundary);

    const child = try writeTraceForTest("trace-child-detach", &.{
        .{ .op = .shim_ready, .seq = 0, .pid = 7, .tid = 7, .path = "/tmp/s", .aux = "" },
        .{ .op = .detached, .seq = 0, .pid = 8, .tid = 8, .path = "", .aux = "" },
        .{ .op = .write, .seq = 1, .pid = 7, .tid = 7, .path = "/tmp/s/a", .aux = "" },
    }, &fbuf);
    defer _ = posix.unlink(child);
    var tb2 = unboundedBudget(std.testing.allocator);
    var other = try readTrace(&tb2, std.mem.span(child));
    defer other.deinit();
    try std.testing.expect(!other.subject_detached);
    try std.testing.expect(other.process_boundary);
}

const R = contract.Record;
fn rd(tid: u64, op: contract.OpClass, seq: u32, path: []const u8, aux: []const u8) R {
    return .{ .op = op, .seq = seq, .pid = 7, .tid = tid, .path = path, .aux = aux };
}
/// The budget is the caller's: the returned `TraceInfo`'s arena frees through it on
/// `deinit`, so it has to outlive the info — a budget local to this helper would be a
/// dangling pointer by then (measured: an integer overflow in `TraceBudget.free`).
fn readShape(tag: []const u8, records: []const R, budget: *TraceBudget) !TraceInfo {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest(tag, records, &fbuf);
    return try readTrace(budget, std.mem.span(fz));
}

test "a worker that writes and is joined before the main thread writes is one order: judged, one hand-over (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-writes", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/b", ""),
        rd(9, .write, 2, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .open, 3, "/tmp/s/a", ""),
        rd(7, .write, 4, "/tmp/s/a", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), info.thread_turns);
    try std.testing.expectEqual(@as(u32, 1), info.thread_joins);
    try std.testing.expectEqual(@as(u32, 0), info.thread_joins_unresolved);
    try std.testing.expectEqual(@as(u32, 2), info.subject_writer_tids);
    try std.testing.expectEqual(@as(u32, 1), info.thread_records);
}

test "the main thread writes, creates a worker that writes, joins it and writes again: judged, two hand-overs (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-turns", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .write, 2, "/tmp/s/a", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 3 1"),
        rd(9, .open, 3, "/tmp/s/b", ""),
        rd(9, .write, 4, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .open, 5, "/tmp/s/c", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 2), info.thread_turns);
}

test "two workers created by the same thread that both write are siblings: refused, and the refusal names both (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-siblings", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(7, .thread, 0, "", ""),
        rd(10, .thread_started, 0, "", "7 2 2"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(10, .open, 2, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .thread_join, 0, "", "7 2"),
        rd(7, .open, 3, "/tmp/s/c", ""),
    }, &tb);
    defer info.deinit();
    const second = info.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 10), second.tid);
    try std.testing.expectEqualStrings("/tmp/s/b", second.path);
    const first = info.first_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 9), first.tid);
    try std.testing.expectEqualStrings("/tmp/s/a", first.path);
    try std.testing.expect(!info.first_writer_thread_detached);
}

test "the main thread writes before joining the worker that wrote: refused (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-race", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .open, 2, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 1"),
    }, &tb);
    defer info.deinit();
    const second = info.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 7), second.tid);
    try std.testing.expectEqualStrings("/tmp/s/b", second.path);
    try std.testing.expectEqual(@as(u64, 9), (info.first_writer_thread orelse return error.TestUnexpectedResult).tid);
}

test "a detached worker that wrote, then the main thread writes: refused, and the refusal knows the detach (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-detach", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(7, .thread_detach, 0, "", "7 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expect(info.second_writer_thread != null);
    try std.testing.expect(info.first_writer_thread_detached);
    try std.testing.expectEqual(@as(u32, 1), info.thread_detaches);
}

test "a detach recorded before the detached thread's start still marks it: the refusal knows the detach either way (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-detach-first", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(7, .thread_detach, 0, "", "7 1"),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expect(info.second_writer_thread != null);
    try std.testing.expect(info.first_writer_thread_detached);
}

test "a grandchild that writes, joined by the worker, joined by the main thread: judged through the chain (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-grandchild", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .thread, 0, "", ""),
        rd(10, .thread_started, 0, "", "9 0 1"),
        rd(10, .open, 1, "/tmp/s/s", ""),
        rd(9, .thread_join, 0, "", "9 1"),
        rd(9, .open, 2, "/tmp/s/w", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .open, 3, "/tmp/s/m", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 2), info.thread_turns);
    try std.testing.expectEqual(@as(u32, 2), info.thread_joins);
}

test "the child's clock is the creator's at the creation, not at the child's start: a write after the creation is not inherited (v18, R2 M7)" {
    var tb = unboundedBudget(std.testing.allocator);
    var racy = try readShape("v18-late-start", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .thread, 0, "", ""),
        rd(7, .open, 2, "/tmp/s/b", ""),
        rd(9, .thread_started, 0, "", "7 2 1"),
        rd(9, .open, 3, "/tmp/s/c", ""),
    }, &tb);
    defer racy.deinit();
    const second = racy.second_writer_thread orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 9), second.tid);
    try std.testing.expectEqualStrings("/tmp/s/b", (racy.first_writer_thread orelse return error.TestUnexpectedResult).path);
    var ordered = try readShape("v18-late-start-ok", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 2 1"),
        rd(9, .open, 2, "/tmp/s/c", ""),
    }, &tb);
    defer ordered.deinit();
    try std.testing.expectEqual(@as(?Op, null), ordered.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), ordered.thread_turns);
}

test "a snapshot is filed under the count after its record: a creation before a join does not inherit the join (v18, R2 C3)" {
    var tb = unboundedBudget(std.testing.allocator);
    var before = try readShape("v18-snap-before-join", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/x", ""),
        rd(7, .thread, 0, "", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(10, .thread_started, 0, "", "7 3 2"),
        rd(10, .open, 2, "/tmp/s/y", ""),
    }, &tb);
    defer before.deinit();
    try std.testing.expectEqual(@as(u64, 10), (before.second_writer_thread orelse return error.TestUnexpectedResult).tid);
    var after = try readShape("v18-snap-after-join", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/x", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .thread, 0, "", ""),
        rd(10, .thread_started, 0, "", "7 4 2"),
        rd(10, .open, 2, "/tmp/s/y", ""),
    }, &tb);
    defer after.deinit();
    try std.testing.expectEqual(@as(?Op, null), after.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), after.thread_turns);
}

test "a start whose creator is unknown, or whose count the creator never reached, gives no edge (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var unknown_creator = try readShape("v18-unknown-creator", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(9, .thread_started, 0, "", "55 0 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .thread_join, 0, "", "55 1"),
        rd(7, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer unknown_creator.deinit();
    try std.testing.expectEqual(@as(u32, 1), unknown_creator.thread_unpaired_starts);
    try std.testing.expectEqual(@as(u32, 1), unknown_creator.thread_joins);
    try std.testing.expectEqual(@as(?Op, null), unknown_creator.second_writer_thread);
    var ahead = try readShape("v18-count-ahead", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 99 1"),
        rd(9, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer ahead.deinit();
    try std.testing.expectEqual(@as(u32, 1), ahead.thread_unpaired_starts);
    try std.testing.expect(ahead.second_writer_thread != null);
    var malformed = try readShape("v18-malformed-start", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(9, .thread_started, 0, "", "not a pair"),
        rd(9, .open, 1, "/tmp/s/a", ""),
    }, &tb);
    defer malformed.deinit();
    try std.testing.expectEqual(@as(u32, 1), malformed.thread_unpaired_starts);
}

test "a join the shim could not name draws no edge (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-join-unknown", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .thread_join, 0, "", contract.thread_aux.unknown),
        rd(7, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 1), info.thread_joins_unresolved);
    try std.testing.expectEqual(@as(u32, 0), info.thread_joins);
    try std.testing.expectEqual(@as(u64, 7), (info.second_writer_thread orelse return error.TestUnexpectedResult).tid);
}

test "a thread id the kernel recycled is a new thread: a join of the earlier one carries nothing the later one wrote (v18, R2 M5)" {
    var tb = unboundedBudget(std.testing.allocator);
    var reused = try readShape("v18-tid-reuse", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 2 2"),
        rd(9, .open, 1, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 1"),
        rd(7, .open, 2, "/tmp/s/c", ""),
    }, &tb);
    defer reused.deinit();
    try std.testing.expectEqual(@as(u64, 7), (reused.second_writer_thread orelse return error.TestUnexpectedResult).tid);
    try std.testing.expectEqual(@as(u32, 1), reused.thread_joins);
    var joined_second = try readShape("v18-tid-reuse-ok", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 2 2"),
        rd(9, .open, 1, "/tmp/s/b", ""),
        rd(7, .thread_join, 0, "", "7 2"),
        rd(7, .open, 2, "/tmp/s/c", ""),
    }, &tb);
    defer joined_second.deinit();
    try std.testing.expectEqual(@as(?Op, null), joined_second.second_writer_thread);
}

test "an image change starts the order over: the thread that survives it writes as the first writer (v18)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-exec-reset", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .thread, 0, "", ""),
        rd(9, .thread_started, 0, "", "7 1 1"),
        rd(9, .open, 1, "/tmp/s/a", ""),
        rd(7, .exec, 0, "", ""),
        rd(7, .shim_ready, 1, "/tmp/s", ""),
        rd(7, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 1), info.exec_continuations);
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
}

test "after an image change the surviving thread's count matches the shim's, so a child created after its write does not inherit the write (v18, review P0)" {
    // child's write was judged in order with a write it raced. The `.thread` record is left
    // out here on purpose — the shim drops it when re-entered (ADR 0067 decision 3), and with
    // it in, the one-record slip lands on a record that is not a kill point and the verdict
    // does not turn: the second reviewer measured the first version of this test green with
    // the fix removed.
    var tb = unboundedBudget(std.testing.allocator);
    var racy = try readShape("v18-exec-count", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .exec, 0, "", ""),
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .write, 2, "/tmp/s/a", ""),
        rd(9, .thread_started, 0, "", "7 2 1"),
        rd(9, .open, 3, "/tmp/s/b", ""),
    }, &tb);
    defer racy.deinit();
    try std.testing.expectEqual(@as(u32, 1), racy.exec_continuations);
    try std.testing.expectEqual(@as(u64, 9), (racy.second_writer_thread orelse return error.TestUnexpectedResult).tid);
    var ordered = try readShape("v18-exec-count-ok", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .exec, 0, "", ""),
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(7, .write, 2, "/tmp/s/a", ""),
        rd(9, .thread_started, 0, "", "7 3 1"),
        rd(9, .open, 3, "/tmp/s/b", ""),
    }, &tb);
    defer ordered.deinit();
    try std.testing.expectEqual(@as(?Op, null), ordered.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), ordered.thread_turns);
}

test "a start record is a recorded creation: with every `.thread` dropped, the account does not call the thread unrecorded (v18, review)" {
    var tb = unboundedBudget(std.testing.allocator);
    var info = try readShape("v18-start-only", &.{
        rd(7, .shim_ready, 0, "/tmp/s", ""),
        rd(7, .open, 1, "/tmp/s/a", ""),
        rd(9, .thread_started, 0, "", "7 2 1"),
        rd(9, .open, 2, "/tmp/s/b", ""),
    }, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(u32, 0), info.thread_records);
    try std.testing.expectEqual(@as(u32, 1), info.thread_start_records);
    try std.testing.expect(!info.unrecorded_writer_thread);
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), info.thread_turns);
}

test "more threads than the shim has slots for do not break the reader (v18, R2 M4)" {
    var tb = unboundedBudget(std.testing.allocator);
    var records: [3 + 70 + 1]R = undefined;
    records[0] = rd(7, .shim_ready, 0, "/tmp/s", "");
    records[1] = rd(7, .thread, 0, "", "");
    records[2] = rd(7, .open, 1, "/tmp/s/a", "");
    var i: usize = 0;
    var auxes: [70][24]u8 = undefined;
    while (i < 70) : (i += 1) {
        const aux = std.fmt.bufPrint(&auxes[i], "7 3 {d}", .{i + 1}) catch unreachable;
        records[3 + i] = rd(100 + @as(u64, i), .thread_started, 0, "", aux);
    }
    records[73] = rd(169, .open, 2, "/tmp/s/z", "");
    var info = try readShape("v18-many", &records, &tb);
    defer info.deinit();
    try std.testing.expectEqual(@as(?Op, null), info.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 1), info.thread_turns);
    try std.testing.expectEqual(@as(u32, 0), info.thread_unpaired_starts);
}

fn readGated(tag: []const u8, records: []const R, budget: *TraceBudget, gate: GateExempt) !TraceInfo {
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try writeTraceForTest(tag, records, &fbuf);
    return try readTraceGated(budget, std.mem.span(fz), max_trace_bytes, gate);
}

fn testInitial(entries: []const snapshots.Entry) snapshots.Snapshot {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .{ .items = @constCast(entries), .capacity = entries.len, .pointer_stability = .{} } };
}

const siblings_head = [_]R{
    rd(7, .shim_ready, 0, "/tmp/s", ""),
    rd(7, .thread, 0, "", ""),
    rd(9, .thread_started, 0, "", "7 1 1"),
    rd(7, .thread, 0, "", ""),
    rd(10, .thread_started, 0, "", "7 2 2"),
};

fn siblings(comptime tail: []const R) [siblings_head.len + tail.len]R {
    return siblings_head ++ tail[0..tail.len].*;
}

test "two sibling threads that only mkdir the state root are not held to an order" {
    const initial = testInitial(&.{});
    const gate: GateExempt = .{ .root = "/tmp/s", .alt = "", .scratch = &.{}, .initial = &initial };
    const shape = siblings(&.{ rd(9, .mkdir, 1, "/tmp/s", ""), rd(10, .mkdir, 2, "/tmp/s", "") });
    var tb = unboundedBudget(std.testing.allocator);
    var gated = try readGated("gate-root-mkdir", &shape, &tb, gate);
    defer gated.deinit();
    try std.testing.expectEqual(@as(?Op, null), gated.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 2), gated.subject_writer_tids);
    var tb2 = unboundedBudget(std.testing.allocator);
    var ungated = try readShape("gate-root-mkdir-control", &shape, &tb2);
    defer ungated.deinit();
    try std.testing.expect(ungated.second_writer_thread != null);
}

test "a mkdir of a directory the state started with is held to the order once another thread removes that directory, even later in the trace" {
    const before = [_]snapshots.Entry{ .{ .rel = "d", .kind = .dir, .content = "" }, .{ .rel = "e", .kind = .dir, .content = "" } };
    const initial = testInitial(&before);
    const gate: GateExempt = .{ .root = "/tmp/s", .alt = "", .scratch = &.{}, .initial = &initial };
    var tb = unboundedBudget(std.testing.allocator);
    var removed = try readGated("gate-mkdir-removed", &siblings(&.{ rd(9, .mkdir, 1, "/tmp/s/d", ""), rd(10, .rmdir, 2, "/tmp/s/D", "") }), &tb, gate);
    defer removed.deinit();
    try std.testing.expect(removed.second_writer_thread != null);
    var tb2 = unboundedBudget(std.testing.allocator);
    var sibling_removed = try readGated("gate-mkdir-sibling-removed", &siblings(&.{ rd(9, .mkdir, 1, "/tmp/s/d", ""), rd(10, .rmdir, 2, "/tmp/s/e", "") }), &tb2, gate);
    defer sibling_removed.deinit();
    try std.testing.expectEqual(@as(?Op, null), sibling_removed.second_writer_thread);
    var tb3 = unboundedBudget(std.testing.allocator);
    var new_dir = try readGated("gate-mkdir-new", &siblings(&.{ rd(9, .mkdir, 1, "/tmp/s/n", ""), rd(10, .mkdir, 2, "/tmp/s/n", "") }), &tb3, gate);
    defer new_dir.deinit();
    try std.testing.expect(new_dir.second_writer_thread != null);
}

test "writes under a declared scratch path are not held to an order, unless they pass through a link the run made" {
    const initial = testInitial(&.{});
    const gate: GateExempt = .{ .root = "/tmp/s", .alt = "/private/tmp/s", .scratch = &.{"tmp"}, .initial = &initial };
    const in_scratch = siblings(&.{ rd(9, .write, 1, "/private/tmp/s/tmp/x.123", ""), rd(10, .write, 2, "/tmp/s/a", "") });
    var tb = unboundedBudget(std.testing.allocator);
    var gated = try readGated("gate-scratch", &in_scratch, &tb, gate);
    defer gated.deinit();
    try std.testing.expectEqual(@as(?Op, null), gated.second_writer_thread);
    try std.testing.expectEqual(@as(u32, 2), gated.subject_writer_tids);
    var tb2 = unboundedBudget(std.testing.allocator);
    var ungated = try readShape("gate-scratch-control", &in_scratch, &tb2);
    defer ungated.deinit();
    try std.testing.expect(ungated.second_writer_thread != null);
    var tb3 = unboundedBudget(std.testing.allocator);
    var linked = try readGated("gate-scratch-link", &siblings(&.{
        rd(10, .symlink, 1, "/tmp/s/tmp/l", ""),
        rd(9, .write, 2, "/tmp/s/tmp/l/x", ""),
        rd(10, .write, 3, "/tmp/s/a", ""),
    }), &tb3, gate);
    defer linked.deinit();
    try std.testing.expect(linked.second_writer_thread != null);
    var tb5 = unboundedBudget(std.testing.allocator);
    var renamed_in = try readGated("gate-scratch-renamed-in", &siblings(&.{
        rd(10, .symlink, 1, "/tmp/s/x", ""),
        rd(10, .rename, 2, "/tmp/s/x", "/tmp/s/tmp/d"),
        rd(9, .open, 3, "/tmp/s/tmp/d/f", ""),
        rd(10, .write, 4, "/tmp/s/a", ""),
    }), &tb5, gate);
    defer renamed_in.deinit();
    try std.testing.expect(renamed_in.second_writer_thread != null);
    var tb6 = unboundedBudget(std.testing.allocator);
    var hard_linked = try readGated("gate-scratch-hard-link", &siblings(&.{
        rd(10, .link, 1, "/tmp/s/a", "/tmp/s/tmp/b"),
        rd(9, .write, 2, "/tmp/s/tmp/b", ""),
        rd(10, .write, 3, "/tmp/s/c", ""),
    }), &tb6, gate);
    defer hard_linked.deinit();
    try std.testing.expect(hard_linked.second_writer_thread != null);
    var tb8 = unboundedBudget(std.testing.allocator);
    var linked_out = try readGated("gate-scratch-linked-out", &siblings(&.{
        rd(10, .link, 1, "/tmp/s/tmp/a", "/tmp/s/b"),
        rd(9, .write, 2, "/tmp/s/tmp/a", ""),
        rd(10, .write, 3, "/tmp/s/c", ""),
    }), &tb8, gate);
    defer linked_out.deinit();
    try std.testing.expect(linked_out.second_writer_thread != null);
    var tb7 = unboundedBudget(std.testing.allocator);
    var made_link = try readGated("gate-scratch-made-link", &siblings(&.{ rd(9, .symlink, 1, "/tmp/s/tmp/arg0", ""), rd(10, .write, 2, "/tmp/s/a", "") }), &tb7, gate);
    defer made_link.deinit();
    try std.testing.expectEqual(@as(?Op, null), made_link.second_writer_thread);
    var tb4 = unboundedBudget(std.testing.allocator);
    var outside = try readGated("gate-scratch-outside", &siblings(&.{ rd(9, .write, 1, "/tmp/s/b", ""), rd(10, .write, 2, "/tmp/s/a", "") }), &tb4, gate);
    defer outside.deinit();
    try std.testing.expect(outside.second_writer_thread != null);
}
