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

pub fn note(arena: std.mem.Allocator, a: Account) []const u8 {
    return noteOrError(arena, a) catch "measured; the account could not be written (out of memory)";
}

fn noteOrError(arena: std.mem.Allocator, a: Account) error{OutOfMemory}![]const u8 {
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
    try out.appendSlice(arena, " An account, not a verdict: a process crash keeps unsynced writes, and power loss is not tested.");
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
    for (spec, out, 0..) |s, *o, i| o.* = .{ .class = s[0], .seq = @intCast(i + 1), .pid = 7, .tid = 7, .path = s[1], .aux = s[2] };
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
    const line = note(a, .{ .renames = max_listed + 1, .without_fsync = f.listed, .without_fsync_omitted = f.omitted, .dir_checked = true, .without_dir_sync = f.listed, .without_dir_sync_omitted = f.omitted });
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
    const unwritten = note(a, .{ .renames = 2, .unwritten = 2 });
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
    try t.expect(std.mem.indexOf(u8, note(a, acc), "with no fsync or fdatasync recorded for it between its last recorded write and the rename: k.") != null);
    try t.expect(std.mem.startsWith(u8, note(a, .{}), "no rename into the judged state."));
    try t.expect(std.mem.indexOf(u8, note(a, .{ .renames = 2, .without_fsync = &.{"a"}, .without_fsync_omitted = 3 }), "a and 3 more not named") != null);
}
