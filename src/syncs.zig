const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const defang = @import("defang.zig");

// Not the judged set's budget: the MCP reader's 4 MiB allows one growing field at 64 KiB, and
// this adds two arrays and a sentence that repeats their paths.
pub const max_listed: usize = 100;
pub const max_bytes: usize = 8 * 1024;

pub const Account = struct {
    renames: u32 = 0,
    unwritten: u32 = 0,
    without_fsync: []const []const u8 = &.{},
    without_fsync_omitted: u32 = 0,
    without_dir_sync: []const []const u8 = &.{},
    without_dir_sync_omitted: u32 = 0,
    dir_checked: bool = false,
};

const Pending = struct { parent: []const u8, rel: []const u8, at: usize };

const Named = struct {
    list: std.ArrayList([]const u8) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn add(self: *Named, arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}!void {
        if ((try self.seen.getOrPut(arena, s)).found_existing) return;
        try self.list.append(arena, s);
    }
};

// Not the absolute path inside the state: a write and a rename can spell it two ways. A relative
// key never starts with `/`, so it cannot meet an outside path.
fn key(p: []const u8, root: []const u8, alt: []const u8) []const u8 {
    return engine.relUnderRoot(p, root, alt) orelse p;
}

pub fn account(arena: std.mem.Allocator, ops: []const engine.Op, root: []const u8, alt: []const u8, scratch: []const []const u8, marker: bool) error{OutOfMemory}!Account {
    var last_write: std.StringHashMapUnmanaged(usize) = .empty;
    var last_sync: std.StringHashMapUnmanaged(usize) = .empty;
    var named: Named = .{};
    var renamed_in: std.ArrayList(Pending) = .empty;
    var a: Account = .{ .dir_checked = marker };
    for (ops, 0..) |op, i| {
        switch (op.class) {
            .write, .truncate => try last_write.put(arena, key(op.path, root, alt), i),
            .fsync => try last_sync.put(arena, key(op.path, root, alt), i),
            .rename => {
                const src = key(op.path, root, alt);
                // Not carried to the new name: a file renamed on from where it was first renamed
                // to was not written at that path, and is counted, not named.
                const wrote_at = last_write.get(src);
                const synced_at = last_sync.get(src);
                _ = last_write.remove(src);
                // Nor kept for the name it replaces: that history belongs to the file no longer there.
                const dst = key(op.aux, root, alt);
                _ = last_write.remove(dst);
                _ = last_sync.remove(dst);
                const rel = engine.relUnderRoot(op.aux, root, alt) orelse continue;
                if (rel.len == 0 or engine.scratchMatches(scratch, rel)) continue;
                a.renames +|= 1;
                if (wrote_at) |w| {
                    const synced = if (synced_at) |s| s > w else false;
                    if (!synced) try named.add(arena, rel);
                } else a.unwritten +|= 1;
                if (marker) try renamed_in.append(arena, .{ .parent = parentOf(rel), .rel = rel, .at = i });
            },
            else => {},
        }
    }
    var dir_named: Named = .{};
    for (renamed_in.items) |r| {
        const synced = if (last_sync.get(r.parent)) |s| s > r.at else false;
        if (!synced) try dir_named.add(arena, r.rel);
    }
    const f = capped(named.list.items);
    a.without_fsync = f.listed;
    a.without_fsync_omitted = f.omitted;
    const d = capped(dir_named.list.items);
    a.without_dir_sync = d.listed;
    a.without_dir_sync_omitted = d.omitted;
    return a;
}

pub const Before = union(enum) { initial: []const u8, empty };

pub const WriteOpen = struct { path: []const u8, truncates: bool };

pub const Opens = struct { list: []const WriteOpen, unplaced: bool };

pub const Plan = struct { cands: []const Candidate, unmatched: u32 };

pub const Candidate = struct {
    seq: u32,
    dst: []const u8,
    before: Before,
    until: u32 = std.math.maxInt(u32),

    pub fn appliesAt(self: Candidate, k: u32) bool {
        return self.seq < k and k <= self.until;
    }
};

pub fn candidates(
    arena: std.mem.Allocator,
    ops: []const engine.Op,
    root: []const u8,
    alt: []const u8,
    scratch: []const []const u8,
    initial: *const engine.Snapshot,
    opens: Opens,
) error{OutOfMemory}!Plan {
    var truncs: std.StringHashMapUnmanaged(std.ArrayList(bool)) = .empty;
    for (opens.list) |o| {
        const g = try truncs.getOrPut(arena, key(o.path, root, alt));
        if (!g.found_existing) g.value_ptr.* = .empty;
        try g.value_ptr.append(arena, o.truncates);
    }
    var recorded: std.StringHashMapUnmanaged(usize) = .empty;
    for (ops) |op| if (op.class == .open) {
        const g = try recorded.getOrPut(arena, key(op.path, root, alt));
        g.value_ptr.* = if (g.found_existing) g.value_ptr.* + 1 else 1;
    };

    var synced: std.StringHashMapUnmanaged(void) = .empty;
    var cut: std.StringHashMapUnmanaged(void) = .empty;
    var moved: std.StringHashMapUnmanaged(void) = .empty;
    var written: std.StringHashMapUnmanaged(void) = .empty;
    var linked: std.StringHashMapUnmanaged(void) = .empty;
    var opened: std.StringHashMapUnmanaged(usize) = .empty;
    var out: std.ArrayList(Candidate) = .empty;
    var unmatched: u32 = 0;
    for (ops) |op| {
        if (!op.class.isKillPoint()) continue;
        const first = key(op.path, root, alt);
        const second: ?[]const u8 = if (op.class.isTwoPath()) key(op.aux, root, alt) else null;
        if (op.class == .rename and std.mem.eql(u8, first, second.?)) continue;
        const truncating: Truncating = if (op.class == .open) blk: {
            const g = try opened.getOrPut(arena, first);
            const at = if (g.found_existing) g.value_ptr.* else 0;
            g.value_ptr.* = at + 1;
            break :blk openTruncates(truncs.get(first), recorded.get(first) orelse 0, at);
        } else .no;
        const changes = op.class != .open or truncating != .no;
        const moves = op.class == .rename or op.class == .unlink or op.class == .rmdir;
        if (changes) for (out.items) |*c| {
            if (c.until != std.math.maxInt(u32)) continue;
            if (touches(first, c.dst, moves) or (second != null and touches(second.?, c.dst, moves))) c.until = op.seq;
        };
        switch (op.class) {
            .open => if (truncating == .yes) try cut.put(arena, first, {}),
            .write => try written.put(arena, first, {}),
            .fsync => try synced.put(arena, first, {}),
            .unlink => {
                try cut.put(arena, first, {});
                _ = synced.remove(first);
            },
            .truncate, .link => try cut.put(arena, second orelse first, {}),
            .symlink => try linked.put(arena, first, {}),
            .rename => {
                const dst = second.?;
                const was_written = written.remove(first);
                _ = written.remove(dst);
                const was_synced = synced.remove(first);
                _ = synced.remove(dst);
                if (was_synced) try synced.put(arena, dst, {});
                const was_cut = cut.contains(first) or isMoved(&moved, first);
                try moved.put(arena, first, {});
                try moved.put(arena, dst, {});
                const rel = engine.relUnderRoot(op.aux, root, alt) orelse continue;
                if (rel.len == 0 or engine.scratchMatches(scratch, rel)) continue;
                if (!was_written or was_synced or linked.contains(first)) continue;
                const init_entry: ?engine.Entry = if (engine.relUnderRoot(op.path, root, alt)) |r| initial.find(r) else null;
                if (init_entry) |e| if (e.kind == .symlink) continue;
                const keeps = if (init_entry) |e| e.kind == .file and !was_cut else false;
                if (keeps and (opens.unplaced or unmatchedOpens(truncs.get(first), recorded.get(first) orelse 0))) {
                    unmatched +|= 1;
                    continue;
                }
                try out.append(arena, .{ .seq = op.seq, .dst = rel, .before = if (keeps) .{ .initial = init_entry.?.rel } else .empty });
            },
            else => {},
        }
    }
    return .{ .cands = out.items, .unmatched = unmatched };
}

const Truncating = enum { no, yes, unknown };

// Not matched by position across paths: strace and the shim interleave processes the same way only per path.
fn openTruncates(list: ?std.ArrayList(bool), recorded: usize, at: usize) Truncating {
    const l = list orelse return if (recorded == 0) .no else .unknown;
    if (l.items.len != recorded or at >= l.items.len) return .unknown;
    return if (l.items[at]) .yes else .no;
}

fn unmatchedOpens(list: ?std.ArrayList(bool), recorded: usize) bool {
    const n = if (list) |l| l.items.len else 0;
    return n != recorded;
}

// Not every operation on a directory above: a mkdir the shim records can fail on a name that exists, and a failed one
// leaves the file below it as it was. Only a rename moves what is below.
fn isMoved(moved: *const std.StringHashMapUnmanaged(void), p: []const u8) bool {
    var at = p;
    while (at.len > 0) {
        if (moved.contains(at)) return true;
        at = at[0 .. std.mem.lastIndexOfScalar(u8, at, '/') orelse return false];
    }
    return false;
}

fn byRel(rel: []const u8, e: engine.Entry) std.math.Order {
    return std.mem.order(u8, rel, e.rel);
}

// Not a copy of the bytes: the world borrows `crashed`'s and `initial`'s, so `crashed` must outlive it.
pub fn compose(gpa: std.mem.Allocator, crashed: engine.Snapshot, initial: *const engine.Snapshot, cands: []const Candidate, k: u32) error{OutOfMemory}!?engine.Snapshot {
    var out: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    errdefer out.deinit();
    var entries: ?[]engine.Entry = null;
    for (cands) |c| {
        if (!c.appliesAt(k)) continue;
        const at = std.sort.binarySearch(engine.Entry, crashed.entries.items, c.dst, byRel) orelse continue;
        const e = crashed.entries.items[at];
        if (e.kind != .file) continue;
        const content = switch (c.before) {
            .initial => |r| (initial.find(r) orelse continue).content,
            .empty => "",
        };
        if (std.mem.eql(u8, content, e.content)) continue;
        const list = entries orelse try out.arena.allocator().dupe(engine.Entry, crashed.entries.items);
        list[at].content = content;
        entries = list;
    }
    out.entries = .fromOwnedSlice(entries orelse {
        out.deinit();
        return null;
    });
    return out;
}

// Not every operation on a directory above the name: a sync of it leaves the name's data as unsynced as before.
fn touches(p: []const u8, dst: []const u8, moves: bool) bool {
    if (std.mem.eql(u8, p, dst)) return true;
    return moves and p.len > 0 and std.mem.startsWith(u8, dst, p) and dst.len > p.len and dst[p.len] == '/';
}

fn parentOf(rel: []const u8) []const u8 {
    const cut = std.mem.lastIndexOfScalar(u8, rel, '/') orelse return "";
    return rel[0..cut];
}

fn capped(items: []const []const u8) struct { listed: []const []const u8, omitted: u32 } {
    var listed: usize = 0;
    var bytes: usize = 0;
    while (listed < items.len and listed < max_listed) : (listed += 1) {
        const next = bytes + items[listed].len;
        if (next > max_bytes) break;
        bytes = next;
    }
    const rest = items.len - listed;
    return .{ .listed = items[0..listed], .omitted = if (rest > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(rest) };
}

pub fn note(arena: std.mem.Allocator, a: Account, rule_judged: bool) []const u8 {
    return noteOrError(arena, a, rule_judged) catch "measured; the account could not be written (out of memory)";
}

fn noteOrError(arena: std.mem.Allocator, a: Account, rule_judged: bool) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    if (a.renames == 0) {
        try out.appendSlice(arena, "no rename into the judged state.");
    } else {
        try out.print(arena, "{d} rename(s) into the judged state.", .{a.renames});
        if (a.without_fsync.len + a.without_fsync_omitted > 0) {
            try out.appendSlice(arena, " Renamed with no fsync or fdatasync recorded for it between its last recorded write and the rename: ");
            try listPaths(arena, &out, a.without_fsync, a.without_fsync_omitted);
            try out.append(arena, '.');
        } else if (a.renames > a.unwritten) {
            try out.appendSlice(arena, " Each file with a write recorded was synced (fsync or fdatasync) after its last recorded write and before its rename.");
        }
        if (a.unwritten > 0) try out.print(arena, " {d} of a file with no write recorded at the path it was renamed from, not judged.", .{a.unwritten});
        if (a.dir_checked) {
            if (a.without_dir_sync.len + a.without_dir_sync_omitted == 0) {
                try out.appendSlice(arena, " The directory of each was synced after its rename.");
            } else {
                try out.appendSlice(arena, " With no sync of its directory recorded after the rename: ");
                try listPaths(arena, &out, a.without_dir_sync, a.without_dir_sync_omitted);
                try out.append(arena, '.');
            }
        }
    }
    try out.appendSlice(arena, if (rule_judged)
        " An account, not a verdict: a process crash keeps unsynced writes, and the power loss line says what the rule judged."
    else
        " An account, not a verdict: a process crash keeps unsynced writes, and power loss is not tested.");
    return out.items;
}

fn listPaths(arena: std.mem.Allocator, out: *std.ArrayList(u8), listed: []const []const u8, omitted: u32) error{OutOfMemory}!void {
    for (listed, 0..) |p, i| {
        if (i > 0) try out.appendSlice(arena, ", ");
        try out.appendSlice(arena, defang.textShown(arena, p));
    }
    if (omitted > 0) try out.print(arena, " and {d} more not named", .{omitted});
}

fn opsFor(arena: std.mem.Allocator, spec: []const struct { contract.OpClass, []const u8, []const u8 }) ![]engine.Op {
    const out = try arena.alloc(engine.Op, spec.len);
    var seq: u32 = 0;
    for (spec, out) |s, *o| {
        if (s[0].isKillPoint()) seq += 1;
        o.* = .{ .class = s[0], .seq = if (s[0].isKillPoint()) seq else 0, .pid = 7, .tid = 7, .path = s[1], .aux = s[2] };
    }
    return out;
}

fn accountOf(arena: std.mem.Allocator, spec: anytype, marker: bool) !Account {
    return account(arena, try opsFor(arena, spec), "/s", "", &.{"scratch"}, marker);
}

test "a file renamed into the state is named only when no fsync of it follows its last write and precedes the rename" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const no_sync = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, false);
    try t.expectEqual(@as(usize, 1), no_sync.without_fsync.len);
    try t.expectEqualStrings("k", no_sync.without_fsync[0]);
    const synced = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, false);
    try t.expectEqual(@as(usize, 0), synced.without_fsync.len);
    const wrote_after = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, false);
    try t.expectEqual(@as(usize, 1), wrote_after.without_fsync.len);
    const other_synced = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/other", "" }, .{ .fsync, "/s", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, false);
    try t.expectEqual(@as(usize, 1), other_synced.without_fsync.len);
    const prefix = try accountOf(a, &.{ .{ .write, "/s/k", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .rename, "/s/k", "/s/j" } }, false);
    try t.expectEqualStrings("j", prefix.without_fsync[0]);
    const after = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" }, .{ .fsync, "/s/k", "" } }, false);
    try t.expectEqual(@as(usize, 1), after.without_fsync.len);
}

test "a rename from a path where no write was recorded is counted and not named, and scratch is left out" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const chain = try accountOf(a, &.{ .{ .write, "/s/a", "" }, .{ .rename, "/s/a", "/s/b" }, .{ .rename, "/s/b", "/s/c" } }, false);
    try t.expectEqual(@as(u32, 2), chain.renames);
    try t.expectEqual(@as(u32, 1), chain.unwritten);
    try t.expectEqual(@as(usize, 1), chain.without_fsync.len);
    try t.expectEqualStrings("b", chain.without_fsync[0]);
    const to_scratch = try accountOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/scratch/k" } }, false);
    try t.expectEqual(@as(u32, 0), to_scratch.renames);
    const outside = try accountOf(a, &.{ .{ .write, "/t/k", "" }, .{ .rename, "/t/k", "/t/j" } }, false);
    try t.expectEqual(@as(u32, 0), outside.renames);
}

test "with a marker, every rename into the state whose directory has no sync after it is named, and without one none is" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const spec = .{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } };
    const with_marker = try accountOf(a, &spec, true);
    try t.expectEqual(@as(usize, 0), with_marker.without_fsync.len);
    try t.expectEqualStrings("k", with_marker.without_dir_sync[0]);
    const without_marker = try accountOf(a, &spec, false);
    try t.expectEqual(@as(usize, 0), without_marker.without_dir_sync.len);
    try t.expect(!without_marker.dir_checked);
    const before_only = try accountOf(a, &.{ .{ .fsync, "/s", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, true);
    try t.expectEqual(@as(usize, 1), before_only.without_dir_sync.len);
    const other_dir = try accountOf(a, &.{ .{ .rename, "/s/k.tmp", "/s/k" }, .{ .fsync, "/s/sub", "" } }, true);
    try t.expectEqual(@as(usize, 1), other_dir.without_dir_sync.len);
    const synced_dir = try accountOf(a, &.{ .{ .rename, "/s/k.tmp", "/s/k" }, .{ .fsync, "/s", "" } }, true);
    try t.expectEqual(@as(usize, 0), synced_dir.without_dir_sync.len);
}

test "a rename over a name forgets that name's history, and the line stays within the text report's buffer" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const over = try accountOf(a, &.{ .{ .write, "/s/k", "" }, .{ .fsync, "/s/k", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" }, .{ .rename, "/s/k", "/s/bak" } }, false);
    try t.expectEqual(@as(usize, 1), over.without_fsync.len);
    try t.expectEqualStrings("k", over.without_fsync[0]);
    try t.expectEqual(@as(u32, 1), over.unwritten);
    var many: [max_listed + 1][]const u8 = undefined;
    const control: [100]u8 = @splat(1);
    for (&many, 0..) |*m, i| m.* = try std.fmt.allocPrint(a, "{d}{s}", .{ i, &control });
    const f = capped(&many);
    const line = note(a, .{ .renames = max_listed + 1, .without_fsync = f.listed, .without_fsync_omitted = f.omitted, .dir_checked = true, .without_dir_sync = f.listed, .without_dir_sync_omitted = f.omitted }, false);
    try t.expect(f.omitted > 0);
    try t.expect(line.len < 32 * 1024);
}

test "a rename onto its own name keeps the sync recorded before it, and a run of unwritten renames claims no sync" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const same = try accountOf(a, &.{ .{ .write, "/s/k", "" }, .{ .fsync, "/s/k", "" }, .{ .rename, "/s/k", "/s/k" } }, false);
    try t.expectEqual(@as(usize, 0), same.without_fsync.len);
    const unwritten = note(a, .{ .renames = 2, .unwritten = 2 }, false);
    try t.expect(std.mem.indexOf(u8, unwritten, "Each file") == null);
    try t.expect(std.mem.indexOf(u8, unwritten, "2 of a file with no write recorded at the path it was renamed from, not judged.") != null);
}

test "the state's other spelling is read as the state, and the account says what it measured" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    const ops = try opsFor(a, &.{ .{ .write, "/private/s/k.tmp", "" }, .{ .rename, "/private/s/k.tmp", "/private/s/k" } });
    const acc = try account(a, ops, "/s", "/private/s", &.{}, false);
    try t.expectEqualStrings("k", acc.without_fsync[0]);
    try t.expect(std.mem.indexOf(u8, note(a, acc, false), "with no fsync or fdatasync recorded for it between its last recorded write and the rename: k.") != null);
    try t.expect(std.mem.startsWith(u8, note(a, .{}, false), "no rename into the judged state."));
    try t.expect(std.mem.indexOf(u8, note(a, .{ .renames = 2, .without_fsync = &.{"a"}, .without_fsync_omitted = 3 }, false), "a and 3 more not named") != null);
}

fn candidatesOf(arena: std.mem.Allocator, spec: anytype, initial: *const engine.Snapshot, opens: []const WriteOpen) ![]const Candidate {
    return (try candidates(arena, try opsFor(arena, spec), "/s", "", &.{"scratch"}, initial, .{ .list = opens, .unplaced = false })).cands;
}

test "a rename with no sync of its file is a candidate from the crash point after it, numbered by crash point and not by place in the trace" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{.{ "k", "old" }});
    defer initial.deinit();
    const c = try candidatesOf(a, &.{ .{ .close, "/s/x", "" }, .{ .write, "/s/k.tmp", "" }, .{ .fork, "", "" }, .{ .close, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" }, .{ .close, "/s/y", "" } }, &initial, &.{});
    try t.expectEqual(@as(usize, 1), c.len);
    try t.expectEqual(@as(u32, 2), c[0].seq);
    try t.expectEqualStrings("k", c[0].dst);
    try t.expect(c[0].before == .empty);
    try t.expect(!c[0].appliesAt(2));
    try t.expect(c[0].appliesAt(3));
}

test "a candidate stops applying once its new name is written, synced or moved, and a sync of its directory does not stop it" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{});
    defer initial.deinit();
    const head = .{ .{ .write, "/s/d/k.tmp", "" }, .{ .rename, "/s/d/k.tmp", "/s/d/k" } };
    inline for (.{
        .{ .write, "/s/d/k", "" },
        .{ .fsync, "/s/d/k", "" },
        .{ .rename, "/s/d/k", "/s/d/j" },
        .{ .unlink, "/s/d/k", "" },
        .{ .rename, "/s/d", "/s/e" },
    }) |later| {
        const c = try candidatesOf(a, &(head ++ .{later}), &initial, &.{});
        try t.expectEqual(@as(u32, 3), c[0].until);
        try t.expect(c[0].appliesAt(3));
        try t.expect(!c[0].appliesAt(4));
    }
    const dir_synced = try candidatesOf(a, &(head ++ .{.{ .fsync, "/s/d", "" }}), &initial, &.{});
    try t.expect(dir_synced[0].appliesAt(4));
    const written_before = try candidatesOf(a, &.{ .{ .write, "/s/d/k", "" }, .{ .write, "/s/d/k.tmp", "" }, .{ .rename, "/s/d/k.tmp", "/s/d/k" } }, &initial, &.{});
    try t.expectEqual(@as(usize, 1), written_before.len);
}

test "a file synced anywhere in the run, a symbolic link, and a rename of nothing written are not candidates" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{});
    defer initial.deinit();
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, &initial, &.{})).len);
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .fsync, "/s/k.tmp", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, &initial, &.{})).len);
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .symlink, "/s/k.tmp", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, &initial, &.{})).len);
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{.{ .rename, "/s/k.tmp", "/s/k" }}, &initial, &.{})).len);
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/scratch/k" } }, &initial, &.{})).len);
    var linked = engine.Snapshot{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer linked.deinit();
    try linked.entries.append(linked.arena.allocator(), .{ .rel = "k.tmp", .kind = .symlink, .content = "elsewhere" });
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }, &linked, &.{})).len);
}

test "a candidate's file holds what it held before the run only when the run neither truncated nor replaced it" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{.{ "log", "old lines\n" }});
    defer initial.deinit();
    const append = .{ .{ .open, "/s/log", "" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" } };
    const appended = try candidatesOf(a, &append, &initial, &.{.{ .path = "/s/log", .truncates = false }});
    try t.expectEqualStrings("log", appended[0].before.initial);
    const by_open = try candidatesOf(a, &append, &initial, &.{.{ .path = "/s/log", .truncates = true }});
    try t.expect(by_open[0].before == .empty);
    const by_call = try candidatesOf(a, &.{ .{ .truncate, "/s/log", "" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" } }, &initial, &.{});
    try t.expect(by_call[0].before == .empty);
    const recreated = try candidatesOf(a, &.{ .{ .unlink, "/s/log", "" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" } }, &initial, &.{});
    try t.expect(recreated[0].before == .empty);
    const replaced = try candidatesOf(a, &.{ .{ .write, "/s/n", "" }, .{ .rename, "/s/n", "/s/log" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" } }, &initial, &.{});
    try t.expect(replaced[1].before == .empty);
    const rotated_twice = try candidatesOf(a, &.{ .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.2" } }, &initial, &.{});
    try t.expectEqualStrings("log", rotated_twice[0].before.initial);
    try t.expect(rotated_twice[1].before == .empty);
    var nested = try engine.testSnapshot(std.testing.allocator, &.{.{ "d/log", "old\n" }});
    defer nested.deinit();
    const dir_moved = try candidatesOf(a, &.{ .{ .rename, "/s/d", "/s/e" }, .{ .mkdir, "/s/d", "" }, .{ .write, "/s/d/log", "" }, .{ .rename, "/s/d/log", "/s/log.1" } }, &nested, &.{});
    try t.expect(dir_moved[0].before == .empty);
    const dir_made = try candidatesOf(a, &.{ .{ .mkdir, "/s/d", "" }, .{ .write, "/s/d/log", "" }, .{ .rename, "/s/d/log", "/s/log.1" } }, &nested, &.{});
    try t.expectEqualStrings("d/log", dir_made[0].before.initial);
    const later_trunc = try candidatesOf(a, &.{ .{ .open, "/s/log", "" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" }, .{ .open, "/s/log", "" } }, &initial, &.{ .{ .path = "/s/log", .truncates = false }, .{ .path = "/s/log", .truncates = true } });
    try t.expectEqualStrings("log", later_trunc[0].before.initial);
}

test "a file whose opens cannot be matched with strace's is left unjudged and counted, never given what it held before" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{.{ "log", "old\n" }});
    defer initial.deinit();
    const ops = try opsFor(a, &.{ .{ .open, "/s/log", "" }, .{ .write, "/s/log", "" }, .{ .rename, "/s/log", "/s/log.1" } });
    const missing = try candidates(a, ops, "/s", "", &.{}, &initial, .{ .list = &.{}, .unplaced = false });
    try t.expectEqual(@as(usize, 0), missing.cands.len);
    try t.expectEqual(@as(u32, 1), missing.unmatched);
    const unplaced = try candidates(a, ops, "/s", "", &.{}, &initial, .{ .list = &.{.{ .path = "/s/log", .truncates = false }}, .unplaced = true });
    try t.expectEqual(@as(u32, 1), unplaced.unmatched);
    const fresh = try candidates(a, try opsFor(a, &.{ .{ .open, "/s/k.tmp", "" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" } }), "/s", "", &.{}, &initial, .{ .list = &.{}, .unplaced = true });
    try t.expect(fresh.cands[0].before == .empty);
}

test "a sync belongs to the file it synced, so a second file under the same temporary name is still a candidate" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{});
    defer initial.deinit();
    const c = try candidatesOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .fsync, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/a" }, .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/b" } }, &initial, &.{});
    try t.expectEqual(@as(usize, 1), c.len);
    try t.expectEqualStrings("b", c[0].dst);
    const moved_then_renamed = try candidatesOf(a, &.{ .{ .write, "/s/x", "" }, .{ .fsync, "/s/x", "" }, .{ .rename, "/s/x", "/s/y" }, .{ .write, "/s/y", "" }, .{ .rename, "/s/y", "/s/z" } }, &initial, &.{});
    try t.expectEqual(@as(usize, 0), moved_then_renamed.len);
    try t.expectEqual(@as(usize, 0), (try candidatesOf(a, &.{ .{ .write, "/s/x", "" }, .{ .rename, "/s/x", "/s/x" } }, &initial, &.{})).len);
    const opened_after = try candidatesOf(a, &.{ .{ .write, "/s/k.tmp", "" }, .{ .rename, "/s/k.tmp", "/s/k" }, .{ .open, "/s/k", "" } }, &initial, &.{.{ .path = "/s/k", .truncates = false }});
    try t.expect(opened_after[0].appliesAt(4));
}

test "the power-loss world replaces only the applying candidates' contents, and is no world when it changes nothing" {
    const t = std.testing;
    var initial = try engine.testSnapshot(std.testing.allocator, &.{.{ "k", "old" }});
    defer initial.deinit();
    var crashed = try engine.testSnapshot(std.testing.allocator, &.{ .{ "j", "other" }, .{ "k", "new" } });
    defer crashed.deinit();
    const cands = [_]Candidate{.{ .seq = 2, .dst = "k", .before = .{ .initial = "k" } }};
    var world = (try compose(std.testing.allocator, crashed, &initial, &cands, 3)).?;
    defer world.deinit();
    try t.expectEqualStrings("old", world.find("k").?.content);
    try t.expectEqualStrings("other", world.find("j").?.content);
    try t.expect((try compose(std.testing.allocator, crashed, &initial, &cands, 2)) == null);
    const emptied = [_]Candidate{.{ .seq = 2, .dst = "k", .before = .empty }};
    var empty_world = (try compose(std.testing.allocator, crashed, &initial, &emptied, 3)).?;
    defer empty_world.deinit();
    try t.expectEqualStrings("", empty_world.find("k").?.content);
    var same = try engine.testSnapshot(std.testing.allocator, &.{.{ "k", "old" }});
    defer same.deinit();
    try t.expect((try compose(std.testing.allocator, same, &initial, &cands, 3)) == null);
}
