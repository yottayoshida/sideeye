const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const defang = @import("defang.zig");

pub const Plan = struct {
    recording: []const engine.Op,
    recording_at: []const u32,
    world_at: []u32,
    spelled: std.StringHashMapUnmanaged(void),
    initial: engine.Snapshot,
    final: engine.Snapshot,
    root: []const u8,
    alt: []const u8,
    scratch: []const []const u8,
};

pub const Divergence = struct { seq: u32, world: ?engine.Op, recording: ?engine.Op };

pub fn plan(arena: std.mem.Allocator, recording: engine.TraceInfo, n: u32, initial: engine.Snapshot, final: engine.Snapshot, root: []const u8, alt: []const u8, scratch: []const []const u8) error{OutOfMemory}!Plan {
    const at = try arena.alloc(u32, @as(usize, n) + 1);
    index(at, recording);
    var spelled: std.StringHashMapUnmanaged(void) = .{};
    for (at[1..]) |i| {
        if (i == 0) continue;
        const op = recording.ops.items[i - 1];
        if (engine.relUnderRoot(op.path, root, alt)) |r| try spelled.put(arena, r, {});
        if (op.class.isTwoPath()) if (engine.relUnderRoot(op.aux, root, alt)) |r| try spelled.put(arena, r, {});
    }
    return .{
        .recording = recording.ops.items,
        .recording_at = at,
        .world_at = try arena.alloc(u32, @as(usize, n) + 1),
        .spelled = spelled,
        .initial = initial,
        .final = final,
        .root = root,
        .alt = alt,
        .scratch = scratch,
    };
}

/// Not compared before operation 1 or past `k - 1`: a world's own crash point and what follows
/// it are what the kill changes. `k` must not exceed the recording's count.
pub fn firstDivergence(p: *const Plan, world: engine.TraceInfo, k: u32) ?Divergence {
    if (k < 2) return null;
    index(p.world_at[0..k], world);
    var removed_any = false;
    var seq: u32 = 1;
    while (seq < k) : (seq += 1) {
        const r = opAt(p.recording, p.recording_at, seq);
        const w = opAt(world.ops.items, p.world_at, seq);
        if (r == null or w == null or !same(p, w.?, r.?, removed_any)) return .{ .seq = seq, .world = w, .recording = r };
        switch (r.?.class) {
            .unlink, .rmdir, .rename => removed_any = true,
            else => {},
        }
    }
    return null;
}

pub fn detail(arena: std.mem.Allocator, d: Divergence, p: *const Plan) []const u8 {
    const fallback = "a world reached its crash point through other operations than the recording numbered, so the crash point named an operation this world did not perform there";
    const text = std.fmt.allocPrint(
        arena,
        "a world reached its crash point through other operations than the recording numbered: operation {d} was {s} in the world and {s} in the recording, so the crash point named an operation this world did not perform there",
        .{ d.seq, describe(arena, d.world, p), describe(arena, d.recording, p) },
    ) catch return fallback;
    return defang.sanitizeForReport(arena, text) catch fallback;
}

fn describe(arena: std.mem.Allocator, op: ?engine.Op, p: *const Plan) []const u8 {
    const o = op orelse return "missing";
    const path = engine.relUnderRoot(o.path, p.root, p.alt) orelse o.path;
    const to: []const u8 = if (o.class.isTwoPath()) engine.relUnderRoot(o.aux, p.root, p.alt) orelse o.aux else "";
    return std.fmt.allocPrint(arena, "{s}({s}{s}{s})", .{ o.class.name(), path, if (to.len > 0) " -> " else "", to }) catch o.class.name();
}

/// fsync changes nothing a snapshot reads, and a mkdir on a directory that is there changes
/// nothing at all: holding either to a name would refuse orders that are harmless. Not after
/// anything was removed or renamed: by a symlink, a case-folding filesystem or a directory
/// above, a removal can reach a name it does not spell.
fn same(p: *const Plan, w: engine.Op, r: engine.Op, removed_any: bool) bool {
    const gate: engine.GateExempt = .{ .root = p.root, .alt = p.alt, .scratch = p.scratch, .initial = &p.initial };
    if (gate.inertAlone(w) != gate.inertAlone(r)) return false;
    if (w.class != r.class) return false;
    if (w.class == .fsync) return true;
    if (w.class == .mkdir and !removed_any and startedWith(p, w.path) and startedWith(p, r.path)) return true;
    if (!sameWhereRecorded(p, w.path, r.path)) return false;
    return !w.class.isTwoPath() or sameWhereRecorded(p, w.aux, r.aux);
}

/// Not compared when the world's name is one the recording never spelled and the recording's
/// is not one the state started with: a pid, a random suffix or a clock in a scratch name
/// differs between runs and says nothing about order.
fn sameWhereRecorded(p: *const Plan, world_path: []const u8, recording_path: []const u8) bool {
    if (std.mem.eql(u8, world_path, recording_path)) return true;
    const w = engine.relUnderRoot(world_path, p.root, p.alt);
    const r = engine.relUnderRoot(recording_path, p.root, p.alt);
    const w_spelled = if (w) |x| p.spelled.contains(x) or p.initial.find(x) != null or p.final.find(x) != null else false;
    const r_initial = if (r) |x| p.initial.find(x) != null else false;
    if (!w_spelled and !r_initial) return true;
    return std.mem.eql(u8, w orelse return false, r orelse return false);
}

fn startedWith(p: *const Plan, path: []const u8) bool {
    const r = engine.relUnderRoot(path, p.root, p.alt) orelse return false;
    return p.initial.find(r) != null;
}

fn index(at: []u32, trace: engine.TraceInfo) void {
    @memset(at, 0);
    for (trace.ops.items, 0..) |op, i| {
        if (!op.class.isKillPoint() or op.seq == 0 or op.seq >= at.len or at[op.seq] != 0) continue;
        at[op.seq] = @intCast(i + 1);
    }
}

fn opAt(ops: []const engine.Op, at: []const u32, seq: u32) ?engine.Op {
    const i = at[seq];
    return if (i == 0) null else ops[i - 1];
}

fn testTrace(arena: std.mem.Allocator, ops: []const engine.Op) !engine.TraceInfo {
    var t: engine.TraceInfo = .{ .arena = std.heap.ArenaAllocator.init(arena), .ops = .empty };
    for (ops) |o| try t.ops.append(arena, o);
    return t;
}

fn testOp(class: contract.OpClass, seq: u32, path: []const u8, aux: []const u8) engine.Op {
    return .{ .class = class, .seq = seq, .pid = 1, .tid = 1, .path = path, .aux = aux };
}

test "a world that reaches its crash point through the recording's names in another order is held to the first name out of place, and one through fresh names is not" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{.{ "marker", "" }});
    defer start.deinit();
    var end = try engine.testSnapshot(std.testing.allocator, &.{ .{ "alpha", "" }, .{ "beta", "" }, .{ "marker", "" } });
    defer end.deinit();
    const rec = try testTrace(a, &.{ testOp(.open, 1, "/s/alpha", ""), testOp(.write, 2, "/s/alpha", ""), testOp(.open, 3, "/s/beta", ""), testOp(.write, 4, "/s/beta", "") });
    const p = try plan(a, rec, 4, start, end, "/s", "", &.{});

    const swapped = try testTrace(a, &.{ testOp(.open, 1, "/s/beta", ""), testOp(.write, 2, "/s/beta", ""), testOp(.open, 3, "/s/alpha", "") });
    const d = firstDivergence(&p, swapped, 3).?;
    try std.testing.expectEqual(@as(u32, 1), d.seq);
    try std.testing.expect(std.mem.indexOf(u8, detail(a, d, &p), "operation 1 was open(beta) in the world and open(alpha) in the recording") != null);

    const same_order = try testTrace(a, &.{ testOp(.open, 1, "/s/alpha", ""), testOp(.write, 2, "/s/alpha", ""), testOp(.open, 3, "/s/beta", "") });
    try std.testing.expect(firstDivergence(&p, same_order, 3) == null);
    try std.testing.expect(firstDivergence(&p, swapped, 1) == null);

    var only_alpha = try engine.testSnapshot(std.testing.allocator, &.{.{ "alpha", "" }});
    defer only_alpha.deinit();
    const fresh_rec = try testTrace(a, &.{ testOp(.open, 1, "/s/x.111.tmp", ""), testOp(.write, 2, "/s/x.111.tmp", ""), testOp(.rename, 3, "/s/x.111.tmp", "/s/alpha") });
    const fp = try plan(a, fresh_rec, 3, only_alpha, only_alpha, "/s", "", &.{});
    const fresh_world = try testTrace(a, &.{ testOp(.open, 1, "/s/x.222.tmp", ""), testOp(.write, 2, "/s/x.222.tmp", ""), testOp(.rename, 3, "/s/x.222.tmp", "/s/alpha") });
    try std.testing.expect(firstDivergence(&fp, fresh_world, 3) == null);
}

test "a rename is held to its destination apart from its source, and a class out of place is a divergence whatever the names" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{.{ "old", "" }});
    defer start.deinit();
    var end = try engine.testSnapshot(std.testing.allocator, &.{ .{ "alpha", "" }, .{ "beta", "" } });
    defer end.deinit();
    const rec = try testTrace(a, &.{ testOp(.rename, 1, "/s/alpha.tmp", "/s/alpha"), testOp(.rename, 2, "/s/beta.tmp", "/s/beta"), testOp(.unlink, 3, "/s/old", "") });
    const p = try plan(a, rec, 3, start, end, "/s", "", &.{});
    const crossed = try testTrace(a, &.{ testOp(.rename, 1, "/s/alpha.tmp", "/s/beta"), testOp(.rename, 2, "/s/beta.tmp", "/s/alpha") });
    try std.testing.expectEqual(@as(u32, 1), firstDivergence(&p, crossed, 3).?.seq);
    const reclassed = try testTrace(a, &.{ testOp(.rename, 1, "/s/alpha.tmp", "/s/alpha"), testOp(.unlink, 2, "/s/beta.tmp", "") });
    try std.testing.expectEqual(@as(u32, 2), firstDivergence(&p, reclassed, 3).?.seq);
}

test "fsync and a mkdir on a directory already there are not held to a name, and a mkdir after anything was removed or renamed is" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{ .{ "d1", "" }, .{ "d2", "" }, .{ "f", "" } });
    defer start.deinit();
    const rec = try testTrace(a, &.{ testOp(.mkdir, 1, "/s/d1", ""), testOp(.mkdir, 2, "/s/d2", ""), testOp(.fsync, 3, "/s/d1", ""), testOp(.write, 4, "/s/f", "") });
    const p = try plan(a, rec, 4, start, start, "/s", "", &.{});
    const swapped = try testTrace(a, &.{ testOp(.mkdir, 1, "/s/d2", ""), testOp(.mkdir, 2, "/s/d1", ""), testOp(.fsync, 3, "/s/d2", ""), testOp(.write, 4, "/s/f", "") });
    try std.testing.expect(firstDivergence(&p, swapped, 4) == null);

    const rrec = try testTrace(a, &.{ testOp(.rmdir, 1, "/s/d1", ""), testOp(.rmdir, 2, "/s/d2", ""), testOp(.mkdir, 3, "/s/d1", ""), testOp(.mkdir, 4, "/s/d2", "") });
    const rp = try plan(a, rrec, 4, start, start, "/s", "", &.{});
    const rswapped = try testTrace(a, &.{ testOp(.rmdir, 1, "/s/d1", ""), testOp(.rmdir, 2, "/s/d2", ""), testOp(.mkdir, 3, "/s/d2", ""), testOp(.mkdir, 4, "/s/d1", "") });
    try std.testing.expectEqual(@as(u32, 3), firstDivergence(&rp, rswapped, 4).?.seq);

    const mrec = try testTrace(a, &.{ testOp(.rename, 1, "/s/f", "/s/g"), testOp(.mkdir, 2, "/s/d1", ""), testOp(.mkdir, 3, "/s/d2", "") });
    const mp = try plan(a, mrec, 3, start, start, "/s", "", &.{});
    const mswapped = try testTrace(a, &.{ testOp(.rename, 1, "/s/f", "/s/g"), testOp(.mkdir, 2, "/s/d2", ""), testOp(.mkdir, 3, "/s/d1", "") });
    try std.testing.expectEqual(@as(u32, 2), firstDivergence(&mp, mswapped, 3).?.seq);
}

test "a world that writes a scratch name where the recording wrote a name the state started with is held to it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{ .{ "alpha", "" }, .{ "beta", "" } });
    defer start.deinit();
    const rec = try testTrace(a, &.{ testOp(.open, 1, "/s/alpha", ""), testOp(.write, 2, "/s/alpha", ""), testOp(.open, 3, "/s/beta.111.tmp", ""), testOp(.write, 4, "/s/beta.111.tmp", ""), testOp(.rename, 5, "/s/beta.111.tmp", "/s/beta") });
    const p = try plan(a, rec, 5, start, start, "/s", "", &.{});
    const flipped = try testTrace(a, &.{ testOp(.open, 1, "/s/beta.222.tmp", ""), testOp(.write, 2, "/s/beta.222.tmp", "") });
    try std.testing.expectEqual(@as(u32, 1), firstDivergence(&p, flipped, 2).?.seq);
}

test "a world that trades a scratch write for a state write is held to the trade, whatever the names" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{});
    defer start.deinit();
    var end = try engine.testSnapshot(std.testing.allocator, &.{.{ "new.json", "" }});
    defer end.deinit();
    const rec = try testTrace(a, &.{ testOp(.write, 1, "/s/new.json", ""), testOp(.write, 2, "/s/tmp/t.123", "") });
    const traded = try testTrace(a, &.{ testOp(.write, 1, "/s/tmp/t.456", ""), testOp(.write, 2, "/s/new.json", "") });
    const p = try plan(a, rec, 2, start, end, "/s", "", &.{"tmp"});
    try std.testing.expectEqual(@as(u32, 1), (firstDivergence(&p, traded, 2) orelse return error.TestUnexpectedResult).seq);
    const unscratched = try plan(a, rec, 2, start, end, "/s", "", &.{});
    try std.testing.expect(firstDivergence(&unscratched, traded, 2) == null);
    const scratch_first = try testTrace(a, &.{ testOp(.write, 1, "/s/tmp/t.123", ""), testOp(.write, 2, "/s/new.json", "") });
    const p_scratch = try plan(a, scratch_first, 2, start, end, "/s", "", &.{"tmp"});
    try std.testing.expect(firstDivergence(&p_scratch, try testTrace(a, &.{ testOp(.write, 1, "/s/tmp/t.789", ""), testOp(.write, 2, "/s/new.json", "") }), 2) == null);
}

test "a world cut short before a later removal reads a mkdir of a directory the state started with as its recording does" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var start = try engine.testSnapshot(std.testing.allocator, &.{.{ "d", "" }});
    defer start.deinit();
    var end = try engine.testSnapshot(std.testing.allocator, &.{.{ "x", "" }});
    defer end.deinit();
    var later = testOp(.rmdir, 3, "/s/d", "");
    later.tid = 2;
    var worker_write = testOp(.write, 2, "/s/x", "");
    worker_write.tid = 2;
    const rec = try testTrace(a, &.{ testOp(.mkdir, 1, "/s/d", ""), worker_write, later });
    const p = try plan(a, rec, 3, start, end, "/s", "", &.{});
    try std.testing.expect(firstDivergence(&p, try testTrace(a, &.{ testOp(.mkdir, 1, "/s/d", ""), worker_write }), 2) == null);
}
