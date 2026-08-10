//! The exploration engine: snapshot the state, run the target under the shim, kill it
//! at each operation in turn, and judge what is left behind.
//!
//! Every verdict this file produces has to survive one question: could it be wrong in
//! the direction of saying PASS when something was missed? The structural detectors
//! exist because of that question, and they run before any world is explored — if the
//! recording run is not trustworthy, exploring five hundred worlds built on it only
//! multiplies the untrustworthiness.

const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");

const Allocator = std.mem.Allocator;

pub const Entry = struct {
    /// Path relative to the state directory root, always using '/'.
    rel: []const u8,
    kind: posix.Kind,
    /// File contents; empty for directories.
    content: []const u8,
};

pub const Snapshot = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry),

    pub fn deinit(self: *Snapshot) void {
        self.arena.deinit();
    }

    pub fn find(self: Snapshot, rel: []const u8) ?Entry {
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.rel, rel)) return e;
        }
        return null;
    }
};

pub const SnapshotError = error{ OutOfMemory, ReadFailed, TooDeep, PathTooLong };

const max_depth = 32;

fn joinZ(buf: []u8, a: []const u8, b: []const u8) error{PathTooLong}![:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, "{s}/{s}", .{ a, b }) catch return error.PathTooLong;
    return s;
}

fn readWhole(arena: Allocator, path: [*:0]const u8) SnapshotError![]const u8 {
    const fd = posix.open(path, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) return error.ReadFailed;
    defer _ = posix.close(fd);

    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try list.appendSlice(arena, chunk[0..@intCast(n)]);
    }
    return list.items;
}

fn walk(
    arena: Allocator,
    entries: *std.ArrayList(Entry),
    root: []const u8,
    rel_prefix: []const u8,
    depth: usize,
) SnapshotError!void {
    if (depth > max_depth) return error.TooDeep;

    var dir_buf: [contract.max_path]u8 = undefined;
    const dir_path = if (rel_prefix.len == 0)
        std.fmt.bufPrintZ(&dir_buf, "{s}", .{root}) catch return error.PathTooLong
    else
        try joinZ(&dir_buf, root, rel_prefix);

    const dirp = posix.opendir(dir_path.ptr) orelse return;
    defer _ = posix.closedir(dirp);

    while (posix.readdir(dirp)) |ent| {
        const name = posix.direntName(ent);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const rel = if (rel_prefix.len == 0)
            try arena.dupe(u8, name)
        else
            try std.fmt.allocPrint(arena, "{s}/{s}", .{ rel_prefix, name });

        var full_buf: [contract.max_path]u8 = undefined;
        const full = try joinZ(&full_buf, root, rel);
        var kind = posix.kindFromDirent(ent);
        // Some filesystems leave dirent.type unset; ask the path directly then.
        if (kind == .missing) kind = posix.kindOfPath(full.ptr);

        switch (kind) {
            .dir => {
                try entries.append(arena, .{ .rel = rel, .kind = .dir, .content = "" });
                try walk(arena, entries, root, rel, depth + 1);
            },
            .file => {
                const content = try readWhole(arena, full.ptr);
                try entries.append(arena, .{ .rel = rel, .kind = .file, .content = content });
            },
            // Symlinks, sockets and devices are recorded as present but opaque. v0.1
            // does not claim to restore them faithfully, which is why the plan lists
            // snapshot fidelity as out of scope rather than pretending otherwise.
            .other => try entries.append(arena, .{ .rel = rel, .kind = .other, .content = "" }),
            .missing => {},
        }
    }
}

fn lessThanRel(_: void, a: Entry, b: Entry) bool {
    return std.mem.lessThan(u8, a.rel, b.rel);
}

pub fn takeSnapshot(gpa: Allocator, root: []const u8) SnapshotError!Snapshot {
    var snap: Snapshot = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .entries = .empty,
    };
    errdefer snap.arena.deinit();

    const arena = snap.arena.allocator();
    try walk(arena, &snap.entries, root, "", 0);
    // Sorting makes restore create parents before children and makes two snapshots of
    // the same tree compare equal regardless of directory iteration order.
    std.mem.sort(Entry, snap.entries.items, {}, lessThanRel);
    return snap;
}

pub const RestoreError = error{ PathTooLong, DeleteFailed, CreateFailed, UnsafeRoot };

/// Refuses to operate on a root that is suspiciously shallow.
///
/// restore() deletes the directory tree before rebuilding it. That is the one
/// genuinely destructive thing the engine does, and it runs once per explored world,
/// so a mistaken root would be applied hundreds of times before anyone noticed.
fn assertSafeRoot(root: []const u8) RestoreError!void {
    if (root.len == 0 or root[0] != '/') return error.UnsafeRoot;
    var slashes: usize = 0;
    for (root) |ch| {
        if (ch == '/') slashes += 1;
    }
    // "/", "/tmp", "/home" and friends are rejected; "/tmp/x/state" is accepted.
    if (slashes < 2) return error.UnsafeRoot;
    if (std.mem.endsWith(u8, root, "/")) return error.UnsafeRoot;
}

fn deleteTree(root: []const u8, rel_prefix: []const u8, depth: usize) RestoreError!void {
    if (depth > max_depth) return error.DeleteFailed;

    var dir_buf: [contract.max_path]u8 = undefined;
    const dir_path = if (rel_prefix.len == 0)
        std.fmt.bufPrintZ(&dir_buf, "{s}", .{root}) catch return error.PathTooLong
    else
        try joinZ(&dir_buf, root, rel_prefix);

    // Removed in passes, reopening the directory each time.
    //
    // Names must be collected before anything is deleted — removing entries while
    // iterating a DIR* is not portable — so a fixed buffer bounds how many can be held
    // at once. The first version stopped quietly at that bound, which left the previous
    // world's files in place and made an L2 checker report a violation at crash point k
    // that was really residue from k-1. Turning it into a hard error fixed the silence
    // and introduced a worse limit: a state directory with more than 256 entries in one
    // directory became unexplorable, reported as SETUP ERROR with no mention of a buffer.
    // Neither is a limit worth having. A pass that takes as many as fit and then reopens
    // drains a directory of any size, and the buffer stops being part of the contract.
    while (true) {
        var names_buf: [4096]u8 = undefined;
        var names_len: usize = 0;
        var offsets: [256]struct { start: usize, len: usize, dtype: u8 } = undefined;
        var count: usize = 0;
        var buffer_full = false;

        {
            const dirp = posix.opendir(dir_path.ptr) orelse return;
            defer _ = posix.closedir(dirp);
            // The entry type is collected with the name, because it is the only
            // description of the entry that has not followed a symlink yet.
            while (posix.readdir(dirp)) |ent| {
                const name = posix.direntName(ent);
                if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
                if (count >= offsets.len or names_len + name.len > names_buf.len) {
                    buffer_full = true;
                    break;
                }
                @memcpy(names_buf[names_len..][0..name.len], name);
                offsets[count] = .{ .start = names_len, .len = name.len, .dtype = ent.type };
                names_len += name.len;
                count += 1;
            }
        }

        if (count == 0) {
            // Nothing collected. Either the directory is empty — done — or a single name
            // was too long to hold, which would otherwise loop forever making no progress.
            if (buffer_full) return error.DeleteFailed;
            return;
        }

        var removed: usize = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const name = names_buf[offsets[i].start..][0..offsets[i].len];
            var child_rel_buf: [contract.max_path]u8 = undefined;
            const child_rel = if (rel_prefix.len == 0)
                std.fmt.bufPrint(&child_rel_buf, "{s}", .{name}) catch return error.PathTooLong
            else
                std.fmt.bufPrint(&child_rel_buf, "{s}/{s}", .{ rel_prefix, name }) catch return error.PathTooLong;

            var full_buf: [contract.max_path]u8 = undefined;
            const full = try joinZ(&full_buf, root, child_rel);

            // Recurse only into a real directory, never into a symlink that points at one.
            //
            // The first version asked `isDirPath`, which calls `opendir` and therefore
            // follows links: a link inside the state directory pointing outside it would
            // have redirected this recursive delete out of the tree, once per explored
            // world. `assertSafeRoot` cannot see that — it only inspects the root string.
            // Unlinking a symlink removes the link itself, which is what is wanted here.
            const dt = offsets[i].dtype;
            const recurse = switch (dt) {
                posix.DT_DIR => true,
                posix.DT_UNKNOWN => !posix.isSymlink(full.ptr) and posix.isDirPath(full.ptr),
                else => false, // DT_REG, DT_LNK and everything else: remove the entry itself
            };
            if (recurse) {
                try deleteTree(root, child_rel, depth + 1);
                if (posix.rmdir(full.ptr) == 0) removed += 1;
            } else {
                if (posix.unlink(full.ptr) == 0) removed += 1;
            }
        }

        // A pass that removes nothing would be repeated forever by the loop above. It
        // means the entries cannot be deleted at all — a permission problem, not a
        // capacity one — and the caller has to hear about it.
        if (removed == 0) return error.DeleteFailed;
        if (!buffer_full) return;
    }
}

pub fn restore(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    try deleteTree(root, "", 0);

    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    _ = posix.mkdir(root_z.ptr, 0o755);

    for (snap.entries.items) |e| {
        var full_buf: [contract.max_path]u8 = undefined;
        const full = try joinZ(&full_buf, root, e.rel);
        switch (e.kind) {
            .dir => _ = posix.mkdir(full.ptr, 0o755),
            .file => {
                const fd = posix.open(full.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
                if (fd < 0) return error.CreateFailed;
                var off: usize = 0;
                while (off < e.content.len) {
                    const w = posix.write(fd, e.content[off..].ptr, e.content.len - off);
                    // Breaking here and returning success would start the next world from
                    // a truncated file, and judgeL0 would then report a hybrid — a
                    // counterexample manufactured by the tool rather than found in the
                    // target. readWhole distinguishes these cases; this loop did not.
                    if (w <= 0) {
                        _ = posix.close(fd);
                        return error.CreateFailed;
                    }
                    off += @intCast(w);
                }
                _ = posix.close(fd);
            },
            else => {},
        }
    }
}

// ---------------------------------------------------------------------------------

pub const Op = struct {
    class: contract.OpClass,
    seq: u32,
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
    kill_landed_seq: ?u32 = null,
    kill_point_count: u32 = 0,
    mutation_count: u32 = 0,
    boundary: ?contract.OpClass = null,
    truncated: bool = false,

    pub fn deinit(self: *TraceInfo) void {
        self.arena.deinit();
    }

    /// The logical address of crash point k: the operation it happens before, and the
    /// one it happens after. Reported instead of a bare counter so a saved case can be
    /// recognised as no longer applying when the code changes.
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

pub fn readTrace(gpa: Allocator, path: []const u8) SnapshotError!TraceInfo {
    var info: TraceInfo = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .ops = .empty,
    };
    errdefer info.arena.deinit();
    const arena = info.arena.allocator();

    var path_buf: [contract.max_path]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buf, "{s}", .{path}) catch return error.PathTooLong;

    // A missing trace file is not an error here: it is the observation that the shim
    // never ran, which the caller turns into `no_shim_marker`.
    const bytes = readWhole(arena, path_z.ptr) catch return info;
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

    while (off < bytes.len) {
        const dec = contract.decodeRecord(bytes[off..]) catch {
            info.truncated = true;
            break;
        };
        off += dec.consumed;
        const op: Op = .{
            .class = dec.rec.op,
            .seq = dec.rec.seq,
            .path = try arena.dupe(u8, dec.rec.path),
            .aux = try arena.dupe(u8, dec.rec.aux),
        };
        switch (op.class) {
            .shim_ready => info.saw_shim_ready = true,
            .kill_landed => info.kill_landed_seq = op.seq,
            .unresolved => info.saw_unresolved = true,
            else => {},
        }
        if (op.class.isKillPoint()) {
            info.kill_point_count = @max(info.kill_point_count, op.seq);
            if (op.class.isMutation()) info.mutation_count += 1;
        }
        if (op.class.isBoundary() and info.boundary == null) info.boundary = op.class;
        try info.ops.append(arena, op);
    }
    return info;
}

// ---------------------------------------------------------------------------------

pub const Violation = union(enum) {
    /// A path present before and after the operation is gone from the crashed state.
    missing: []const u8,
    /// Present, but holding neither the old nor the new content.
    hybrid: []const u8,
};

/// L0: the built-in atomicity invariant.
///
/// DESIGN §12 states it as "the state directory equals the pre-operation snapshot or
/// the post-operation result, never a hybrid". Implementing that literally fails a
/// *correct* target: the standard write-temp-then-rename idiom leaves `key.json.tmp`
/// behind at several crash points, so the directory equals neither snapshot.
///
/// The invariant that actually separates a correct target from a broken one is
/// narrower — it is about the paths the operation is *replacing*:
///
///   for every path present in both the pre and post snapshots,
///   the crashed state must contain it, holding either the pre or the post content.
///
/// Paths in neither snapshot (temporaries) are ignored. Paths only in pre (deleted by
/// the operation) or only in post (created by it) may legitimately be absent mid-flight.
pub fn judgeL0(pre: Snapshot, post: Snapshot, crashed: Snapshot) ?Violation {
    for (pre.entries.items) |pe| {
        if (pe.kind != .file) continue;
        const po = post.find(pe.rel) orelse continue;
        if (po.kind != .file) continue;

        const ce = crashed.find(pe.rel) orelse return .{ .missing = pe.rel };
        if (std.mem.eql(u8, ce.content, pe.content)) continue;
        if (std.mem.eql(u8, ce.content, po.content)) continue;
        return .{ .hybrid = pe.rel };
    }
    return null;
}

/// Content written over every file when probing whether a checker actually looks at
/// the state. Distinctive enough to recognise in a report, and not valid content for
/// anything a target is likely to store.
pub const corruption_probe = "sideeye-corruption-probe\n";

/// Overwrite every file in the state directory, leaving the structure intact.
///
/// This exists for DESIGN §14-13: before exploring, a deliberately corrupted state must
/// make the checker fail, otherwise the checker is not testing what it claims and every
/// PASS it produces afterwards is meaningless.
///
/// Emptying the directory would be the obvious way to corrupt it and is the wrong one.
/// A checker that compares a diagnostic command against reality — the shape sideeye
/// exists to encourage — finds an empty state perfectly *consistent*: the diagnostic
/// says unhealthy, nothing loads, the two agree. Replacing contents while keeping the
/// files in place breaks the agreement instead of removing the subject.
pub fn corruptState(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    for (snap.entries.items) |e| {
        if (e.kind != .file) continue;
        var full_buf: [contract.max_path]u8 = undefined;
        const full = try joinZ(&full_buf, root, e.rel);
        const fd = posix.open(full.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        // A file that could not be overwritten leaves the state intact, and an intact
        // state is one the checker is right to accept. The run would then report
        // `checker_not_falsified` — "the checker accepted a state whose every file had
        // been overwritten with junk" — about files this function failed to touch,
        // blaming the caller's checker for the engine's own failed write. The same
        // silence was fixed in `restore` and `deleteTree`; the scan that found those
        // looked at the two functions named in the finding and missed this one.
        if (fd < 0) return error.CreateFailed;
        var off: usize = 0;
        while (off < corruption_probe.len) {
            const w = posix.write(fd, corruption_probe[off..].ptr, corruption_probe.len - off);
            if (w <= 0) {
                _ = posix.close(fd);
                return error.CreateFailed;
            }
            off += @intCast(w);
        }
        _ = posix.close(fd);
    }
}

pub fn countFiles(snap: Snapshot) usize {
    var n: usize = 0;
    for (snap.entries.items) |e| {
        if (e.kind == .file) n += 1;
    }
    return n;
}

pub const WorldResult = struct {
    k: u32,
    term: posix.Term,
    landed: bool,
    violation: ?Violation,
};

test "assertSafeRoot rejects roots a mistake would produce" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("relative/path"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot(""));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp/x/"));
    try assertSafeRoot("/tmp/x/state");
    try assertSafeRoot("/work/state");
}

fn testSnapshot(gpa: Allocator, pairs: []const [2][]const u8) !Snapshot {
    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    const arena = snap.arena.allocator();
    for (pairs) |p| {
        try snap.entries.append(arena, .{
            .rel = try arena.dupe(u8, p[0]),
            .kind = .file,
            .content = try arena.dupe(u8, p[1]),
        });
    }
    return snap;
}

test "L0 catches the delete-before-rename window" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    // The crashed state from the buggy toy at k=5: the key is gone, a temp remains.
    var crashed = try testSnapshot(gpa, &.{.{ "key.json.tmp", "key=2\n" }});
    defer crashed.deinit();

    const v = judgeL0(pre, post, crashed) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.missing);
}

test "L0 accepts a leftover temporary file" {
    // This is the case a literal reading of DESIGN §12 gets wrong: the corrected toy
    // leaves key.json.tmp behind at several crash points and must still pass.
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    var mid = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" },
        .{ "key.json.tmp", "key=2\n" },
    });
    defer mid.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(pre, post, mid));

    var done = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer done.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(pre, post, done));
}

test "L0 catches content that is neither the old nor the new value" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();
    var torn = try testSnapshot(gpa, &.{.{ "key.json", "key=" }});
    defer torn.deinit();

    const v = judgeL0(pre, post, torn) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.hybrid);
}

test "L0 ignores files the operation legitimately creates or deletes" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "old.json", "gone\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "new.json", "fresh\n" }});
    defer post.deinit();
    // Neither file present: mid-flight, and not a violation, since no path appears in
    // both snapshots.
    var empty = try testSnapshot(gpa, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(pre, post, empty));
}
