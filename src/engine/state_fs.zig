const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const posix = @import("../posix.zig");
const build_options = @import("engine_build_options");

const Allocator = std.mem.Allocator;

const read = @import("read.zig");
const snapshot = @import("snapshot.zig");

const Snapshot = snapshot.Snapshot;
const Entry = snapshot.Entry;
const finalizeEntries = snapshot.finalizeEntries;

pub const SnapshotError = error{ OutOfMemory, ReadFailed, TooDeep, PathTooLong, ClassifyFailed, EntriesNotSortedUnique, FileTooLarge, TreeTooLarge, MountInside };

/// How deep the snapshot walk descends before refusing — **and how deep `deleteTreeAt`
/// descends before refusing to delete**, which is the reason to think twice before tuning
/// it: raising this widens what `restore` will empty, not only what the snapshot will
/// read. ADR 0024 cites it as the descriptor bound for the same reason.
pub const max_depth = 32;

pub const max_state_file_bytes: usize = 64 * 1024 * 1024;

/// The whole-snapshot ceiling (#323). `max_state_file_bytes` bounds one read; nothing
/// bounded the sum, so a tree of files each comfortably under the per-file cap — 60 MiB
/// a thousand times over — passed every check and ended in an OOM kill with no report,
/// which is the failure the per-file cap exists to remove. Under Linux's overcommit the
/// allocator's own `OutOfMemory` never arrives to be handled: the pages are touched, so
/// the kernel kills the process. This ceiling is what makes running out of memory
/// reportable at all on that platform. (macOS is unmeasured here; `mmap` may fail first
/// and reach `error.OutOfMemory`.)
/// the node-growth reason above, and then exits. Raising this value is not the safe
/// direction: here a refusal is the good outcome, and the alternative to refusing is the
/// unreported death above.
pub const max_state_tree_bytes: usize = 256 * 1024 * 1024;

pub const SnapshotCaps = struct {
    file: usize,
    tree: usize,

    /// What production passes. Every non-test call site uses this rather than spelling
    /// the constants, so the shipped pair has one definition.
    pub const shipped: SnapshotCaps = .{ .file = max_state_file_bytes, .tree = max_state_tree_bytes };
};

pub const EntryRel = struct {
    buf: [contract.max_path]u8 = undefined,
    len: usize = 0,

    pub fn get(self: *const EntryRel) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *EntryRel, rel_path: []const u8) void {
        if (rel_path.len > self.buf.len) {
            self.len = 0;
            return;
        }
        self.len = rel_path.len;
        @memcpy(self.buf[0..self.len], rel_path[0..self.len]);
    }
};

test "EntryRel names nothing rather than a cut path when the path does not fit (#535)" {
    var rel: EntryRel = .{};
    rel.set("a/b");
    try std.testing.expectEqualStrings("a/b", rel.get());
    const long = [_]u8{'x'} ** (contract.max_path + 1);
    rel.set(&long);
    try std.testing.expectEqual(@as(usize, 0), rel.get().len);
}

pub const FileTooLargeDiag = struct {
    rel: EntryRel = .{},
    size: ?u64 = null,
};

pub const EntryDiag = struct {
    rel: EntryRel = .{},
    errno: ?c_int = null,
    kind: Kind = .file,

    pub const Kind = enum { file, symlink, unclassified };
};

pub const TreeTooLargeDiag = struct {
    reached: usize = 0,
    content: u64 = 0,
    entries: u64 = 0,
};

pub const SnapshotDiag = struct {
    file: FileTooLargeDiag = .{},
    tree: TreeTooLargeDiag = .{},
    entry: EntryDiag = .{},
    /// Empty with `MountInside` when the mount table could not be read.
    mount: EntryRel = .{},
};

pub const MountScan = enum { none, found, unlisted };

/// The first thing mounted strictly below `root`, asked before anything there is read or removed.
pub fn firstMountInside(root: []const u8, out: *EntryRel) MountScan {
    out.len = 0;
    if (builtin.os.tag == .linux) {
        const table = mountTableScan(root, out);
        if (table != .none) return table;
    }
    return deviceScan(root, out);
}

var cleared_root_buf: [contract.max_path]u8 = undefined;
var cleared_root_len: usize = 0;
var table_watch: c_int = -1;

/// Linux reads the table again only when a `poll` on a descriptor opened before the last reading
/// says it changed. Do not read it at every snapshot and restore: on a host with thousands of
/// mounts the reading outweighs the world. Do not keep an answer without the
/// watch either: a bind mount made during the run, or by the setup after a replay's
/// `--fresh-state`, keeps its device number and is seen by nothing else. macOS has no such
/// notice and its walk is bounded by the state, so it walks every time.
fn mountInsideWatched(root: []const u8, out: *EntryRel) MountScan {
    out.len = 0;
    if (builtin.os.tag != .linux) return firstMountInside(root, out);
    if (cleared_root_len == root.len and std.mem.eql(u8, cleared_root_buf[0..cleared_root_len], root) and !mountTableChanged())
        return .none;
    cleared_root_len = 0;
    if (table_watch < 0) table_watch = posix.open("/proc/self/mountinfo", posix.O_RDONLY | posix.O_CLOEXEC, @as(c_uint, 0));
    const scan = firstMountInside(root, out);
    if (scan == .none and table_watch >= 0 and root.len <= cleared_root_buf.len) {
        @memcpy(cleared_root_buf[0..root.len], root);
        cleared_root_len = root.len;
    }
    return scan;
}

fn mountTableChanged() bool {
    if (table_watch < 0) return true;
    const linux = std.os.linux;
    var p = [_]linux.pollfd{.{ .fd = table_watch, .events = linux.POLL.PRI, .revents = 0 }};
    const rc = linux.poll(&p, 1, 0);
    if (linux.errno(rc) != .SUCCESS) return true;
    return rc != 0;
}

/// Not `statx`'s mount-root attribute: kernels before 5.8 have none, and a bind mount of the
/// same filesystem keeps `st_dev`, so on those kernels only the mount table names it.
fn mountTableScan(root: []const u8, out: *EntryRel) MountScan {
    const fd = posix.open("/proc/self/mountinfo", posix.O_RDONLY | posix.O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return .unlisted;
    defer _ = posix.close(fd);
    var lines: MountinfoLines = .{ .fd = fd };
    while (lines.next()) |line| {
        var mp_buf: [contract.max_path]u8 = undefined;
        const mp = mountPointOfLine(line, &mp_buf) orelse return .unlisted;
        if (relInsideRoot(mp, root)) |rel| {
            out.set(rel);
            return .found;
        }
    }
    return if (lines.failed) .unlisted else .none;
}

/// Not `getmntinfo` on macOS: its mount-on names can come back in the firmlinked spelling
/// (`/System/Volumes/Data/…`), which a realpath'd root does not share. On Linux this is what names
/// a btrfs subvolume, which the mount table does not list.
fn deviceScan(root: []const u8, out: *EntryRel) MountScan {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return .unlisted;
    const id = posix.identityOfPath(root_z.ptr) catch return .none;
    var rel_buf: [contract.max_path]u8 = undefined;
    return deviceScanAt(root, id.dev, &rel_buf, 0, 0, out);
}

/// A directory that cannot be opened or identified is passed over, not refused: nothing can be
/// removed through it either, and `walk` records it the same way.
fn deviceScanAt(root: []const u8, dev: u64, rel_buf: *[contract.max_path]u8, rel_len: usize, depth: usize, out: *EntryRel) MountScan {
    if (depth > max_depth) return .none;
    var dir_buf: [contract.max_path]u8 = undefined;
    const dir_z = (if (rel_len == 0)
        std.fmt.bufPrintZ(&dir_buf, "{s}", .{root})
    else
        joinZ(&dir_buf, root, rel_buf[0..rel_len])) catch return .unlisted;
    const dirp = posix.opendir(dir_z.ptr) orelse return .none;
    defer _ = posix.closedir(dirp);
    while (posix.readdir(dirp)) |ent| {
        const name = posix.direntName(ent);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        const sep: usize = if (rel_len == 0) 0 else 1;
        const child_len = rel_len + sep + name.len;
        if (child_len > rel_buf.len) return .unlisted;
        if (sep == 1) rel_buf[rel_len] = '/';
        @memcpy(rel_buf[rel_len + sep ..][0..name.len], name);
        var full_buf: [contract.max_path]u8 = undefined;
        const full = joinZ(&full_buf, root, rel_buf[0..child_len]) catch return .unlisted;
        var kind = posix.kindFromDirent(ent);
        if (kind == .missing) kind = posix.kindOfPathNoFollow(full.ptr) catch continue;
        if (kind != .dir) continue;
        const here = posix.identityOfPath(full.ptr) catch continue;
        if (here.dev != dev) {
            out.set(rel_buf[0..child_len]);
            return .found;
        }
        const below = deviceScanAt(root, dev, rel_buf, child_len, depth + 1, out);
        if (below != .none) return below;
    }
    return .none;
}

fn relInsideRoot(path: []const u8, root: []const u8) ?[]const u8 {
    if (!contract.isStrictlyInsideDir(path, root)) return null;
    return path[std.mem.trimEnd(u8, root, "/").len + 1 ..];
}

/// The fifth field, with the kernel's `\ooo` escapes for space, tab, newline and backslash
/// undone. Null for a line that does not parse or a path that does not fit: an unread mount
/// point could be the one inside the state.
fn mountPointOfLine(line: []const u8, out: []u8) ?[]const u8 {
    var fields = std.mem.splitScalar(u8, line, ' ');
    var i: usize = 0;
    while (i < 4) : (i += 1) _ = fields.next() orelse return null;
    const raw = fields.next() orelse return null;
    var n: usize = 0;
    var j: usize = 0;
    while (j < raw.len) {
        if (n >= out.len) return null;
        if (octalEscape(raw[j..])) |byte| {
            out[n] = byte;
            j += 4;
        } else {
            out[n] = raw[j];
            j += 1;
        }
        n += 1;
    }
    return out[0..n];
}

fn octalEscape(s: []const u8) ?u8 {
    if (s.len < 4 or s[0] != '\\') return null;
    var v: u16 = 0;
    for (s[1..4]) |c| {
        if (c < '0' or c > '7') return null;
        v = v * 8 + (c - '0');
    }
    return if (v > 255) null else @intCast(v);
}

/// A line longer than the buffer comes back as its head, and the rest of it is read past: the
/// mount point is the fifth field, ahead of the options an overlay's layer list makes long. Do
/// not fail the scan on a long line — one such line on a host would refuse every run there.
const MountinfoLines = struct {
    fd: c_int,
    buf: [16 * 1024]u8 = undefined,
    start: usize = 0,
    end: usize = 0,
    eof: bool = false,
    skipping: bool = false,
    failed: bool = false,

    fn next(self: *MountinfoLines) ?[]const u8 {
        while (true) {
            if (std.mem.indexOfScalarPos(u8, self.buf[0..self.end], self.start, '\n')) |nl| {
                const line = self.buf[self.start..nl];
                self.start = nl + 1;
                if (self.skipping) {
                    self.skipping = false;
                    continue;
                }
                return line;
            }
            if (self.skipping) self.start = self.end;
            if (self.eof) {
                if (self.start == self.end) return null;
                const tail = self.buf[self.start..self.end];
                self.start = self.end;
                return tail;
            }
            const held = self.end - self.start;
            std.mem.copyForwards(u8, self.buf[0..held], self.buf[self.start..self.end]);
            self.start = 0;
            self.end = held;
            if (self.end == self.buf.len) {
                self.start = self.end;
                self.skipping = true;
                return self.buf[0..self.end];
            }
            const got = posix.read(self.fd, self.buf[self.end..].ptr, self.buf.len - self.end);
            if (got < 0) {
                if (std.c._errno().* == posix.EINTR) continue;
                self.failed = true;
                return null;
            }
            if (got == 0) self.eof = true else self.end += @intCast(got);
        }
    }
};

fn refuseMountInside(root: []const u8) RestoreError!void {
    var rel: EntryRel = .{};
    if (mountInsideWatched(root, &rel) != .none) return error.MountInside;
}

fn joinZ(buf: []u8, a: []const u8, b: []const u8) error{PathTooLong}![:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, "{s}/{s}", .{ a, b }) catch return error.PathTooLong;
    return s;
}

const WalkCtx = struct {
    arena_state: *std.heap.ArenaAllocator,
    entries: *std.ArrayList(Entry),
    root: []const u8,
    /// Do not refuse a root that cannot be identified: a crashed state whose root the target
    /// removed is an ordinary, empty snapshot.
    root_dev: ?u64,
    caps: SnapshotCaps,
    diag: ?*SnapshotDiag,
    content: u64 = 0,
    seen: u64 = 0,

    fn arena(self: *const WalkCtx) Allocator {
        return self.arena_state.allocator();
    }

    fn charge(self: *WalkCtx, content_len: usize) SnapshotError!void {
        self.content += content_len;
        self.seen += 1;
        const reached = self.arena_state.queryCapacity();
        if (reached <= self.caps.tree) return;
        if (self.diag) |d| d.tree = .{ .reached = reached, .content = self.content, .entries = self.seen };
        return error.TreeTooLarge;
    }
};

/// Not kept once the name stops being a directory: a link swapped in since the dirent would give
/// its 0777 to the directory every world rebuilds.
fn dirModeOf(stat: ?posix.KindMode) ?u16 {
    const km = stat orelse return null;
    return if (km.kind == .dir) km.mode else null;
}

fn walk(ctx: *WalkCtx, rel_prefix: []const u8, depth: usize) SnapshotError!void {
    if (depth > max_depth) return error.TooDeep;

    const arena = ctx.arena();
    var dir_buf: [contract.max_path]u8 = undefined;
    const dir_path = if (rel_prefix.len == 0)
        std.fmt.bufPrintZ(&dir_buf, "{s}", .{ctx.root}) catch return error.PathTooLong
    else
        try joinZ(&dir_buf, ctx.root, rel_prefix);

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
        const full = try joinZ(&full_buf, ctx.root, rel);
        var kind = posix.kindFromDirent(ent);
        // Some filesystems leave dirent.type unset; ask the path directly then —
        // without opening it (a FIFO would block) and without following links (#5).
        if (kind == .missing) kind = posix.kindOfPathNoFollow(full.ptr) catch {
            // Fail-closed: an entry that cannot be classified must not silently
            // vanish from the snapshot — that would route it around #5's refusal.
            if (ctx.diag) |d| {
                d.entry.rel.set(rel);
                d.entry.kind = .unclassified;
            }
            return error.ClassifyFailed;
        };

        var charged: usize = 0;
        switch (kind) {
            .dir => {
                // Do not refuse a directory that cannot be identified: one that vanished under a
                // still-running writer is `state_not_quiescent`'s to name, and one under a parent
                // without search permission was always recorded as an empty directory.
                if (ctx.root_dev) |root_dev| {
                    if (posix.identityOfPath(full.ptr)) |here| {
                        if (here.dev != root_dev) {
                            if (ctx.diag) |d| d.mount.set(rel);
                            return error.MountInside;
                        }
                    } else |_| {}
                }
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .dir, .content = "", .mode = dirModeOf(posix.kindModeOfPathNoFollow(full.ptr)) });
                // Charged before descending, so the ceiling is not reached only on the
                // way back up out of a deep subtree.
                try ctx.charge(0);
                try walk(ctx, rel, depth + 1);
                continue;
            },
            .file => {
                var size: ?u64 = null;
                var read_errno: ?c_int = null;
                var mode: ?u16 = null;
                const content = read.readWholeDiag(arena, full.ptr, ctx.caps.file, &size, .follow, &read_errno, &mode) catch |e| {
                    if (ctx.diag) |d| switch (e) {
                        error.FileTooLarge => {
                            d.file.rel.set(rel);
                            d.file.size = size;
                        },
                        error.ReadFailed => {
                            d.entry.rel.set(rel);
                            d.entry.errno = read_errno;
                            d.entry.kind = .file;
                        },
                        else => {},
                    };
                    return e;
                };
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .file, .content = content, .mode = mode });
                charged = content.len;
            },
            .symlink => {
                // The link itself, never what it points at: readlink, no following.
                var tbuf: [contract.max_path]u8 = undefined;
                var link_errno: ?c_int = null;
                const target = readLinkTarget(full.ptr, &tbuf, &link_errno) orelse {
                    if (ctx.diag) |d| {
                        d.entry.rel.set(rel);
                        d.entry.errno = link_errno;
                        d.entry.kind = .symlink;
                    }
                    return error.ReadFailed;
                };
                const held = try arena.dupe(u8, target);
                try ctx.entries.append(arena, .{ .rel = rel, .kind = .symlink, .content = held });
                charged = held.len;
            },
            .other => try ctx.entries.append(arena, .{ .rel = rel, .kind = .other, .content = "" }),
            .missing => {},
        }
        try ctx.charge(charged);
    }
}

/// Read a symlink's target into `buf`, fail-closed: null on error AND on a result
/// that fills the buffer, because readlink reports no truncation — an exact fit and
/// a cut-off target return the same length, and a truncated target restored later
/// would be a different link. The buffer is a parameter so the boundary is testable:
fn readLinkTarget(path_z: [*:0]const u8, buf: []u8, errno_out: ?*?c_int) ?[]const u8 {
    if (errno_out) |eo| eo.* = null;
    const n = posix.readlink(path_z, buf.ptr, buf.len);
    if (n < 0) {
        // The one failure here that is a failed call (#535): read now, before anything
        // else runs. A target that filled the buffer is a successful readlink and gets
        // no errno.
        if (errno_out) |eo| eo.* = std.c._errno().*;
        return null;
    }
    if (@as(usize, @intCast(n)) >= buf.len) return null;
    return buf[0..@intCast(n)];
}

pub fn takeSnapshot(gpa: Allocator, root: []const u8) SnapshotError!Snapshot {
    return takeSnapshotCapped(gpa, root, SnapshotCaps.shipped, null);
}

pub fn takeSnapshotCapped(gpa: Allocator, root: []const u8, caps: SnapshotCaps, diag: ?*SnapshotDiag) SnapshotError!Snapshot {
    var snap: Snapshot = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .entries = .empty,
    };
    errdefer snap.arena.deinit();

    // Not on macOS: there every mount is another device, and the walk below stops at one before
    // reading inside it; walking the tree for it first would only do that twice.
    if (builtin.os.tag == .linux) {
        var mount_rel: EntryRel = .{};
        switch (mountInsideWatched(root, &mount_rel)) {
            .none => {},
            .found, .unlisted => {
                if (diag) |d| d.mount = mount_rel;
                return error.MountInside;
            },
        }
    }
    var root_z_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_z_buf, "{s}", .{root}) catch return error.PathTooLong;
    const root_dev: ?u64 = if (posix.identityOfPath(root_z.ptr)) |id| id.dev else |_| null;

    var ctx: WalkCtx = .{
        .arena_state = &snap.arena,
        .entries = &snap.entries,
        .root = root,
        .root_dev = root_dev,
        .caps = caps,
        .diag = diag,
    };
    try walk(&ctx, "", 0);
    try finalizeEntries(&snap);
    return snap;
}

pub const RestoreError = error{ PathTooLong, DeleteFailed, CreateFailed, UnsafeRoot, MountInside };

/// A denylist, not a safety boundary: it stops the mistake that has a name — a system
/// path where a scratch path was meant — and claims nothing about the ones that do not.
/// Entries are spelled the way a root arrives here. Both call sites hand over the
/// realpath'd spelling, and on macOS `/etc` and `/var/lib` resolve through `/private`,
/// so a list written in the pre-resolution spelling is silently inert on that platform.
///
/// `/var` itself is deliberately absent: `$TMPDIR` on macOS resolves to
/// `/private/var/folders/...`, and denying that tree would refuse the platform's own
/// scratch space.
///
/// `/opt` and `/srv` are absent for a different reason, and it is a judgement rather than
/// a measurement. They are site-local trees an operator populates, so `/opt/myapp/state`
/// is a plausible scratch copy in a way `/var/lib/myapp` is not — and there is no
/// override flag here, so a wrong entry is a wall rather than a warning. The corpus this
/// list was measured against contains nothing under either, which means that measurement
/// says nothing about them in the direction that matters.
///
/// sunset: **the condition that used to stand here was wrong, and #327 is what showed it.**
/// It said to delete this list once the destructive path held the root open by descriptor,
/// because that closes the swap window `assertRootResolvesToItself` only narrows. The walk
/// now does hold the root open — and nothing about this list is discharged by it. Holding
/// `/etc` by descriptor deletes `/etc` just as thoroughly; the swap window is about keeping
/// a correct target, and this list is about being handed a wrong one. Two neighbouring
/// defences, written as if one subsumed the other.
///
/// The list also has a second consumer whose *immediate* job is naming rather than
/// deleting: `mcp.zig` runs `assertSafeNamingRoot` on `SIDEEYE_MCP_ROOT` at startup. A
/// sunset phrased around deletion would authorise removing the list while that vet still
/// depends on it. **"No delete behind it" would be too strong**: with
/// `SIDEEYE_MCP_STATE_ROOT` unset the server passes the root itself as the destruction
/// range (`mcp.zig`'s fallback), so what that vet admits is what a replayed case may
/// then empty, one level down.
///
/// **Both consumers now depend on the list twice over** (#329 for the naming vet, #358 for
/// the destructive one). The entries are read outwards as well as inwards, so deleting the
/// list would not merely stop refusing roots inside these trees — it would also stop
/// refusing their ancestors, silently, since no separate ancestor rule exists to survive.
/// On the destructive side that means a root one level above a system tree becomes
/// something the engine will empty. It would additionally remove one of the three checks
/// that currently refuse a root of "/", which is the fail-open case. None of that changes
/// the conditions below; it changes how much goes with the list when they are met.
///
/// So: delete this list when **neither consumer can be handed a mistyped location** —
/// (1) the destructive root stops being a hand-written value. It arrives from exactly two
///     places — `--state` and a case's `define.state` — and both would have to become
///     engine-derived. (`SIDEEYE_MCP_ROOT` and `--state-under` are deliberately not on
///     that list: they *constrain* where a root may resolve and never supply one. Putting
///     them here would repeat the conflation this note is being corrected for.); and
/// (2) the startup vet in `mcp.zig` no longer needs a name-based refusal.
///
/// Rejected as conditions, both recorded because they are the tempting ones: an override
/// flag arriving (the `/opt`/`/srv` paragraph above turns on there being no such flag, so
/// its arrival is a reason to *list* those trees, not to drop the list), and measuring zero
/// accidents in the corpus (a guard whose job is to make the accident impossible cannot be
/// retired by the accident not happening — that measurement cannot tell the two apart).
const denied_trees = shipped_denied_trees ++ probe_denied_trees;

const shipped_denied_trees = [_][]const u8{
    "/usr",         "/etc",             "/bin",            "/sbin",              "/lib",             "/lib64",
    "/boot",        "/dev",             "/proc",           "/sys",               "/var/lib",         "/var/db",
    "/var/spool",
    // Linux resolves /var/run to /run and /var/lock to /run/lock, so the /var spellings
    // never arrive here; both are listed because a distribution that keeps them real
    // would send the other one. Same reason the /private entries below exist.
      "/var/run",         "/run",            "/System",            "/Library",         "/Applications",
    "/private/etc", "/private/var/lib", "/private/var/db", "/private/var/spool", "/private/var/run",
};

const probe_denied_trees: [if (build_options.ancestor_probe) 2 else 0][]const u8 =
    if (build_options.ancestor_probe)
        .{ "/tmp/se-anc-probe/x", "/private/tmp/se-anc-probe/x" }
    else
        .{};

/// These are matched exactly, not as trees: `/tmp/x/state` is the ordinary case and must
/// pass. The depth test rejects `/tmp` and `/home` as typed **on the destructive side**
/// (the naming side has no depth test since #329), but every call site hands over the
/// resolved spelling, and on macOS `/tmp` arrives as `/private/tmp` with two components —
/// deep enough to pass. Without these entries the guard's own stated intent ("`/tmp` is
/// rejected") does not hold on the platform the tool is developed on.
const denied_exact = [_][]const u8{
    "/tmp",         "/private/tmp",         "/var/tmp", "/private/var/tmp",
    "/var/folders", "/private/var/folders", "/home",    "/Users",
    "/Volumes",     "/mnt",                 "/media",   "/root",
};

/// Lexical only, and the caller must hand over the resolved spelling: "/tmp/../etc"
/// spells safe and resolves unsafe. `assertRootResolvesToItself` covers the other direction —
/// a root that resolved safely and was then swapped.
pub fn assertSafeRoot(root: []const u8) RestoreError!void {
    var slashes: usize = 0;
    for (root) |ch| {
        if (ch == '/') slashes += 1;
    }
    if (slashes < 2) return error.UnsafeRoot;
    try assertRootNotDeniedOrAncestor(root);
}

/// rule above. **Both clauses of the first test stay here**: the naming side happens to
/// guarantee a non-empty root before calling, the destructive side does not, and
/// dropping `root.len == 0` on the strength of the caller that does not need it turns
/// `assertSafeRoot("")` from a refusal into an out-of-bounds index.
fn assertRootNotDeniedOrAncestor(root: []const u8) RestoreError!void {
    if (root.len == 0 or root[0] != '/') return error.UnsafeRoot;
    if (std.mem.endsWith(u8, root, "/")) return error.UnsafeRoot;
    for (denied_exact) |d| {
        if (std.mem.eql(u8, root, d)) return error.UnsafeRoot;
    }
    for (denied_trees) |d| {
        if (contract.isInsideDir(root, d)) return error.UnsafeRoot;
    }
    for (denied_exact ++ denied_trees) |d| {
        if (contract.isInsideDir(d, root)) return error.UnsafeRoot;
    }
}

/// Lexical only, like `assertSafeRoot`, and the caller must hand over the resolved
/// spelling: `/opt/../var` and `//var` and `/.` all pass here. `mcp.zig` realpaths before
/// calling, which is what makes that safe and is the reason the caveat is written down
/// rather than left to the one caller that currently honours it.
pub fn assertSafeNamingRoot(root: []const u8) RestoreError!void {
    // line covers on top of the checks below is therefore **"/" alone, and even that is
    // already covered twice** — the trailing-slash test catches it, and so does the
    // outward read, since `isInsideDir(x, "/")` is true for every absolute x. So this
    // line's covered set is empty, and it is here anyway because **it is the only
    // unconditional carrier of the property**. The trailing-slash test is the destructive
    // side's spelling hygiene and may be revised on its own merits; the outward read
    // holds only while the lists are non-empty, and the sunset note above describes the
    // conditions for deleting them.
    // What fails if all three go is fail-open, not fail-closed: a root of "/" does not
    // weaken the naming boundary, it removes it (`contract.isInsideDir(x, "/")` is true
    // for every absolute path — the input `mcp.zig`'s startup vet exists to eliminate).
    if (root.len <= 1) return error.UnsafeRoot;
    try assertRootNotDeniedOrAncestor(root);
}

const RootVet = union(enum) { identified: posix.Identity, absent };

fn assertRootResolvesToItself(root: []const u8) RestoreError!RootVet {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    var real_buf: [contract.max_path]u8 = undefined;
    const resolved = posix.realpath(root_z.ptr, &real_buf) orelse {
        if (std.c._errno().* == posix.ENOENT) return .absent; // nothing there to delete
        return error.UnsafeRoot; // cannot look: refuse rather than delete blind
    };
    if (!std.mem.eql(u8, std.mem.span(resolved), root)) return error.UnsafeRoot;
    return .{ .identified = posix.identityOfPath(root_z.ptr) catch return error.UnsafeRoot };
}

const RootOpen = union(enum) { fd: c_int, absent };

/// **This does not replace `assertRootResolvesToItself`, and the callers still run it.**
/// `O_NOFOLLOW` is about the final component only: with root `/a/b/state`, replacing
/// `/a/b` with a link to somewhere else opens *that* tree, and this function would then
/// delete it race-free and thoroughly. Pinning identity is not the same property as
/// picking the right target — the same distinction the denylist's note gets wrong above.
fn openRootDir(root: []const u8, vet: RootVet) RestoreError!RootOpen {
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    const fd = posix.open(
        root_z.ptr,
        posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC,
        @as(c_uint, 0),
    );
    if (fd >= 0) {
        // **Comparing the descriptor against what the name resolves to *now* does not
        // work, and was measured not working before this shape was written.** Move the
        // vetted directory aside inside the window and put another in its place: the open
        // reaches the new one and the name resolves to the new one, the two agree, and the
        // walk empties a tree nobody vetted. That comparison can only see a swap landing
        // in the sliver between the open and the stat — a window this function would be
        // creating itself.
        //
        // What stays open is a swap that happened *before* the vet, including a bind mount
        // established before it. The vet approves whatever was there when it looked, and
        // no comparison anchored to the vet can question the vet. `#338` says so in the
        // same words; ADR 0024's Alternatives claimed the device/inode pair would cover
        // it, and ADR 0037 records that correction.
        switch (vet) {
            .identified => |want| {
                const held = posix.identityOfFd(fd) catch {
                    _ = posix.close(fd);
                    return error.UnsafeRoot;
                };
                if (!held.eql(want)) {
                    _ = posix.close(fd);
                    return error.UnsafeRoot;
                }
            },
            .absent => {
                _ = posix.close(fd);
                return error.UnsafeRoot;
            },
        }
        return .{ .fd = fd };
    }
    return switch (std.c._errno().*) {
        posix.ENOENT => .absent,
        posix.ELOOP, posix.ENOTDIR => error.UnsafeRoot,
        // Everything else — EACCES, EMFILE, ENFILE, EPERM under an LSM, ENAMETOOLONG —
        // is loud. A default arm that fell through to `absent` would turn "cannot look"
        // into "nothing there", which is the substitution this file keeps refusing.
        else => error.DeleteFailed,
    };
}

fn deleteTree(root: []const u8) RestoreError!void {
    // Reached only from tests — every production path goes through `restore`, `freshDir`
    // or `corruptState`, each of which runs the full vet. This one takes an identity of
    // its own instead. The name-resolution half of the vet demands the realpath'd spelling
    // and these callers pass `/tmp/...` literals; the identity half needs no such thing,
    // and it is the half `openRootDir` compares against. So the swap window is closed here
    // too and the name checks are not, which is the accurate statement and the reason this
    // is not a fourth production entry point.
    var vet_buf: [contract.max_path]u8 = undefined;
    const vet_z = std.fmt.bufPrintZ(&vet_buf, "{s}", .{root}) catch return error.PathTooLong;
    const vet: RootVet = if (posix.identityOfPath(vet_z.ptr)) |id| .{ .identified = id } else |_| .absent;
    switch (try openRootDir(root, vet)) {
        .absent => return,
        .fd => |fd| {
            const r = deleteTreeAt(fd, 0);
            _ = posix.close(fd);
            return r;
        },
    }
}

fn deleteTreeAt(dirfd: c_int, depth: usize) RestoreError!void {
    if (depth > max_depth) return error.DeleteFailed;
    const here = posix.identityOfFd(dirfd) catch return error.DeleteFailed;

    // Names must be collected before anything is deleted — removing entries while
    // iterating a DIR* is not portable — so a fixed buffer bounds how many can be held
    // at once. The first version stopped quietly at that bound, which left the previous
    // world's files in place and made an L2 checker report a violation at crash point k
    // that was really residue from k-1. Turning it into a hard error fixed the silence
    // and introduced a worse limit: a state directory with more than 256 entries in one
    // directory became unexplorable, reported as SETUP ERROR with no mention of a buffer.
    while (true) {
        var names_buf: [4096]u8 = undefined;
        var names_len: usize = 0;
        var offsets: [256]struct { start: usize, len: usize, dtype: u8 } = undefined;
        var count: usize = 0;
        var buffer_full = false;

        {
            // `fdopendir` takes ownership of the descriptor it is handed and `closedir`
            // closes it, so it cannot be given `dirfd` — that has to outlive the stream
            // for the `unlinkat`s below.
            //
            // **And it cannot be given `dup(dirfd)` either**, which is what this loop tried
            // first. A duplicate shares the open file description, *including the read
            // offset*, and neither libc rewinds it in `fdopendir`. Pass two then resumed
            // where pass one stopped, found nothing past the tail, and the `count == 0`
            // branch below read that as an empty directory — returning success over a
            // directory it had not drained. Measured on macOS: 144 of 400 entries left
            // behind, no error. `removed < count` cannot catch it because every entry that
            // was *collected* was removed; the loss is in the collection.
            const stream_fd = posix.openat(dirfd, ".", posix.O_RDONLY | posix.O_DIRECTORY | posix.O_CLOEXEC, @as(c_uint, 0));
            if (stream_fd < 0) return error.DeleteFailed;
            const dirp = posix.fdopendir(stream_fd) orelse {
                _ = posix.close(stream_fd);
                return error.DeleteFailed;
            };
            defer _ = posix.closedir(dirp);
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
            // The bare entry name, which is the only spelling that keeps `dirfd`
            // meaningful: an absolute path makes the kernel ignore the descriptor,
            // silently, on both platforms.
            var name_buf: [contract.max_path]u8 = undefined;
            const name_z = std.fmt.bufPrintZ(&name_buf, "{s}", .{name}) catch return error.PathTooLong;

            // Recurse only into a real directory, never into a symlink that points at one.
            //
            // The first version asked `isDirPath`, which calls `opendir` and therefore
            // follows links: a link inside the state directory pointing outside it would
            // have redirected this recursive delete out of the tree, once per explored
            // world. `assertSafeRoot` cannot see that — it only inspects the root string.
            // The DT_UNKNOWN fallback asks `fstatat` and deliberately not an `openat`
            // probe. `opendir` passes `O_NONBLOCK`; a hand-rolled open does not, and
            // posix.zig records what that costs — "a FIFO with no writer blocks that open
            // forever" is why the open-probe was retired from this project once already
            // (#5 R1). The descriptor-relative form of that same classifier has the
            // property this walk wants for free: it cannot follow a link and it cannot
            // resolve outside `dirfd`.
            const dt = offsets[i].dtype;
            const recurse = switch (dt) {
                posix.DT_DIR => true,
                posix.DT_UNKNOWN => (posix.kindAtNoFollow(dirfd, name_z.ptr) catch
                    return error.DeleteFailed) == .dir,
                else => false, // DT_REG, DT_LNK and everything else: remove the entry itself
            };
            if (recurse) {
                const child = posix.openat(
                    dirfd,
                    name_z.ptr,
                    posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC,
                    @as(c_uint, 0),
                );
                if (child >= 0) {
                    // Do not descend onto another device: what is mounted there is not the state's.
                    const there = posix.identityOfFd(child) catch {
                        _ = posix.close(child);
                        return error.DeleteFailed;
                    };
                    if (there.dev != here.dev) {
                        _ = posix.close(child);
                        return error.MountInside;
                    }
                    const r = deleteTreeAt(child, depth + 1);
                    _ = posix.close(child);
                    try r;
                    if (posix.unlinkat(dirfd, name_z.ptr, posix.AT_REMOVEDIR) == 0) removed += 1;
                }
            } else {
                if (posix.unlinkat(dirfd, name_z.ptr, 0) == 0) removed += 1;
            }
        }

        // Every collected entry must actually have been removed. The first version
        // required only `removed > 0`, which let a PARTIAL failure — three siblings
        // gone, one held by permissions — return as success and leave residue for the
        // next world to be judged against: the exact "violation at crash point k that
        // was really residue from k-1" this function's own history records. The path
        if (removed < count) return error.DeleteFailed;
        if (!buffer_full) return;
    }
}

pub fn freshDir(root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    if (posix.mkdir(root_z.ptr, 0o755) == 0) return; // did not exist: created empty
    const vet = try assertRootResolvesToItself(root);
    try refuseMountInside(root);
    switch (try openRootDir(root, vet)) {
        // `mkdir` failed AND nothing is there: a missing parent. Loud, and this is the one
        // place the two meanings of an absent root diverge — `deleteTree` treats it as
        // "nothing to delete" and returns. A `--fresh-state` that could not do its job and
        // said nothing is the exact silent no-op this flag exists to remove, so the shared
        // open cannot be allowed to carry `deleteTree`'s reading here. A regular file or a
        // permission wall stay loud too, through `openRootDir`'s map.
        .absent => return error.DeleteFailed,
        .fd => |fd| {
            const r = deleteTreeAt(fd, 0);
            _ = posix.close(fd);
            return r;
        },
    }
}

/// rather than a second full vet — the name's resolution was judged above, and a swap to a
/// symlink since then is refused by `O_NOFOLLOW` in the open, not here.
fn createRoot(root_z: [*:0]const u8, vet: RootVet) RestoreError!RootVet {
    switch (vet) {
        // The vet saw the root and approved it, so the identity to hold the descriptor to
        // is **that** one. Re-reading the name here would undo the whole change: a swap
        // between the vet and this point makes `mkdir` say `EEXIST` exactly as it would
        // have anyway, and a fresh reading then returns the intruder, which then agrees
        // with the intruder at the open. That shape was in the tree until review found it,
        // and it passed every test, because the swap test drove `openRootDir` directly and
        // never came through here.
        .identified => {
            _ = posix.mkdir(root_z, 0o755); // EEXIST is the expected answer and says nothing
            return vet;
        },
        .absent => {
            if (posix.mkdir(root_z, 0o755) != 0) {
                // Something is there that was not there a moment ago. It is not ours, and
                // `O_NOFOLLOW` will not refuse it for being real.
                if (std.c._errno().* == posix.EEXIST) return error.UnsafeRoot;
                return .absent;
            }
            return if (posix.identityOfPath(root_z)) |id| .{ .identified = id } else |_| .absent;
        },
    }
}

/// `O_NOFOLLOW` because the two halves of this file used to answer a planted symlink
/// differently (#446): `deleteTreeAt` descends with the flag and refuses a link where a
/// directory was, while the write opened without it and agreed to write *through* one —
/// sending the recorded bytes to whatever it pointed at, outside the state directory.
/// **Final component only.** The interior of a multi-component `e.rel` is still resolved
/// by name and is left open rather than argued safe — the reasoning, and why closing it
/// needs resolution the kernel enforces, is in CHANGELOG and BUILDLOG under #446.
///
/// A partial write is a failure, not a short success: returning here would start the next
/// world from a truncated file, and judgeL0 would then report a hybrid — a counterexample
/// manufactured by the tool rather than found in the target. read.readWhole distinguishes
/// these cases; the loop this replaced did not.
///
/// `exclusive`, for a name the caller has just removed: without `O_EXCL` a hard link planted
/// there is written into and chmodded.
///
/// `mode` goes on with `fchmod`, never through `openat`'s mode argument — the umask narrows that.
fn writeFileEntryAt(dirfd: c_int, rel_z: [*:0]const u8, bytes: []const u8, mode: ?u16, exclusive: bool) RestoreError!void {
    const excl: c_int = if (exclusive) posix.O_EXCL else 0;
    const wfd = posix.openat(dirfd, rel_z, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC | posix.O_NOFOLLOW | posix.O_CLOEXEC | excl, @as(c_uint, 0o644));
    if (wfd < 0) return error.CreateFailed;
    defer _ = posix.close(wfd);
    var off: usize = 0;
    while (off < bytes.len) {
        const w = posix.write(wfd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return error.CreateFailed;
        off += @intCast(w);
    }
    if (mode) |m| try applyMode(wfd, m);
}

/// A refused `fchmod` passes only when the bits are already there (a mount that fixes every
/// mode). Never pass it otherwise: a world would start from other bits than its recording.
fn applyMode(fd: c_int, want: u16) RestoreError!void {
    if (posix.fchmod(fd, want) == 0) return;
    const now = posix.kindModeOfFd(fd) catch return error.CreateFailed;
    if (now.mode == null or now.mode.? != want) return error.CreateFailed;
}

/// The owner's rwx is always added: without it the next world's `deleteTreeAt` cannot empty the
/// directory. Do not give `deleteTreeAt` a chmod instead — by name, inside a tree a target can
/// rearrange, it can be redirected.
fn dirModeFor(recorded: u16) u16 {
    return (recorded & posix.perm_bits) | 0o700;
}

pub fn restore(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    const vet = try assertRootResolvesToItself(root);
    try refuseMountInside(root);

    // Created *before* the descriptor is taken, not after the delete where it used to sit.
    // Once the root is held open, a `mkdir` on the pathname makes a different directory
    // than the one the walk and every creation below are pinned to, and each `mkdirat`
    // would then run against an unlinked inode. Before the open there is nothing to
    // disagree with: a root that is simply gone is recreated here, as it always was.
    var root_buf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&root_buf, "{s}", .{root}) catch return error.PathTooLong;
    const after = try createRoot(root_z.ptr, vet);

    const fd = switch (try openRootDir(root, after)) {
        .absent => return error.CreateFailed, // the mkdir above failed and nothing is there
        .fd => |f| f,
    };
    defer _ = posix.close(fd);

    try deleteTreeAt(fd, 0);

    for (snap.entries.items) |e| {
        var rel_buf: [contract.max_path]u8 = undefined;
        const rel_z = std.fmt.bufPrintZ(&rel_buf, "{s}", .{e.rel}) catch return error.PathTooLong;
        switch (e.kind) {
            // `missing` the moment they are judged (#164): a world starting without
            // an empty directory the recording had would read as the target's
            // violation. Strict on purpose, no EEXIST tolerance: the tree was
            // emptied above and the root itself never appears in these entries
            // (walk records children only), so an existing directory here has no
            // legitimate source — it is a leftover the delete failed to remove,
            // and accepting it would let world k judge world k-1's residue.
            .dir => {
                if (posix.mkdirat(fd, rel_z.ptr, 0o755) != 0) return error.CreateFailed;
                // Not by name: a link swapped in at it would take the chmod. Interior components
                // still resolve by name, the same limit as the file write above.
                if (e.mode) |m| {
                    const dfd = posix.openat(fd, rel_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0));
                    if (dfd < 0) return error.CreateFailed;
                    defer _ = posix.close(dfd);
                    try applyMode(dfd, dirModeFor(m));
                }
            },
            .symlink => {
                var tz_buf: [contract.max_path]u8 = undefined;
                const tz = std.fmt.bufPrintZ(&tz_buf, "{s}", .{e.content}) catch return error.PathTooLong;
                if (posix.symlinkat(tz.ptr, fd, rel_z.ptr) != 0) return error.CreateFailed;
            },
            .file => try writeFileEntryAt(fd, rel_z.ptr, e.content, e.mode, false),
            // Unreachable from any explored path since #5's refusal fires on every
            // snapshot before restore runs — kept loud, not silent: an `.other` that
            // somehow arrives here would otherwise become a tool-manufactured
            // `missing` in the next world's judgement, the exact shape #5 demoted.
            .other, .missing => return error.CreateFailed,
        }
    }
}

test "#164 pin: restore goes loud when a directory cannot be created" {
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-loud-dir-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const parent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{parent}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a/b", .kind = .dir, .content = "" });
    try std.testing.expectError(error.CreateFailed, restore(snap, root));
}

pub const corruption_probe = "sideeye-corruption-probe\n";

pub const corruption_probe_target = "sideeye-corruption-probe-target";

pub fn corruptState(snap: Snapshot, root: []const u8) RestoreError!void {
    try assertSafeRoot(root);
    // Overwriting is destructive too: a root swapped since it was resolved sends every
    // write below outside the state directory. The single call site runs this immediately
    // after `restore`, which refuses the same way — but relying on the neighbour is how a
    // guard ends up covering one entry point and not the next.
    const vet = try assertRootResolvesToItself(root);
    try refuseMountInside(root);
    // Through the same held descriptor as `restore`, for the same reason: writing by
    // pathname after the root has been vetted leaves the vet's window open, and this
    // function's own comment above says relying on the neighbour is how a guard ends up
    // covering one entry point and not the next.
    const fd = switch (try openRootDir(root, vet)) {
        .absent => return error.CreateFailed,
        .fd => |f| f,
    };
    defer _ = posix.close(fd);
    for (snap.entries.items) |e| {
        // The corruptible kinds, named once and in the same terms `countCorruptible`
        // uses. They were two separate conditions here — `== .symlink` and then
        // `!= .file` — which is the same predicate said differently in two places, and
        // the falsification gate reads the other one to decide whether corrupting is
        // even possible.
        if (e.kind != .file and e.kind != .symlink) continue;
        var rel_buf: [contract.max_path]u8 = undefined;
        const rel_z = std.fmt.bufPrintZ(&rel_buf, "{s}", .{e.rel}) catch return error.PathTooLong;
        if (e.kind == .symlink) {
            // Replace, not follow: opening the link would corrupt whatever it points
            // at, which may be outside the state directory entirely. A checker that
            // never notices every link in the state pointing at a nonexistent probe
            // name is not checking the links — the same argument as overwriting file
            // contents, applied to the only content a symlink has.
            if (posix.unlinkat(fd, rel_z.ptr, 0) != 0) return error.CreateFailed;
            if (posix.symlinkat(corruption_probe_target, fd, rel_z.ptr) != 0) return error.CreateFailed;
            continue;
        }
        // Loud on failure, per `writeFileEntryAt`: a file that could not be overwritten
        // leaves the state intact, and the run would then report `checker_not_falsified`
        // — "the checker accepted a state whose every file had been overwritten with
        // junk" — about a file this function never touched, blaming the caller's checker
        // for the engine's own failed write.
        // Remove and create, never write over: a restored 0444 or 0400 file refuses a writer who
        // is not root. Unlink only a regular file — a link where the snapshot holds a file is
        // refused, never replaced.
        if ((posix.kindAtNoFollow(fd, rel_z.ptr) catch return error.CreateFailed) != .file) return error.CreateFailed;
        if (posix.unlinkat(fd, rel_z.ptr, 0) != 0) return error.CreateFailed;
        try writeFileEntryAt(fd, rel_z.ptr, corruption_probe, e.mode, true);
    }
}

/// How many entries `corruptState` can actually corrupt. The falsification gate asks
/// this before trusting a checker; counting only files would send a symlink-farm state
/// (entries: directories and links, zero regular files) into "nothing to corrupt"
/// while corruptState has a real probe for its links (#122).
pub fn countCorruptible(snap: Snapshot) usize {
    var n: usize = 0;
    for (snap.entries.items) |e| {
        if (e.kind == .file or e.kind == .symlink) n += 1;
    }
    return n;
}

test "freshDir refuses a root a mistake would produce, before any I/O" {
    try std.testing.expectError(error.UnsafeRoot, freshDir("/tmp"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("/"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("relative/state"));
    try std.testing.expectError(error.UnsafeRoot, freshDir("/tmp/x/"));
    // The guard is LEXICAL: this spelling passes it and resolves to /tmp. That is
    // why the call site hands freshDir the realpath'd state, never the case's raw
    // string — a refactor that undoes the resolution re-opens the hole this line
    // documents. (assertSafeRoot only; calling freshDir here would empty /tmp.)
    try assertSafeRoot("/tmp/../tmp");
}

test "assertSafeRoot rejects roots a mistake would produce" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("relative/path"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot(""));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/tmp/x/"));
    try assertSafeRoot("/tmp/x/state");
    try assertSafeRoot("/work/state");
}

test "assertSafeRoot rejects the spellings production actually receives" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/var/tmp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/Users"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/home"));

    try assertSafeRoot("/private/tmp/x/state");
    try assertSafeRoot("/Users/someone/scratch/state");

    try assertSafeRoot("/private/var/folders/lm/abcdef/T/state");
}

test "assertSafeRoot rejects system trees, on component boundaries" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/lib/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/var/lib/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/usr/local/share/x"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/etc/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/private/etc/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/Library/Application Support/x"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/lib"));

    try assertSafeRoot("/var/library/state");
    try assertSafeRoot("/optimism/state");
}

test "assertSafeRoot covers what each platform resolves the shorthand to" {
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/run/myapp"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/run/lock/x"));
    try std.testing.expectError(error.UnsafeRoot, assertSafeRoot("/var/run/myapp"));

    try assertSafeRoot("/opt/myapp/state");
    try assertSafeRoot("/srv/myapp/state");
}

test "assertSafeNamingRoot drops the depth rule and refuses ancestors instead (#329)" {
    const t = std.testing;

    try assertSafeNamingRoot("/work");
    try assertSafeNamingRoot("/opt");
    try assertSafeNamingRoot("/repo");
    try assertSafeNamingRoot("/opt/myapp/state");
    try assertSafeNamingRoot("/Users/someone/scratch");
    try assertSafeNamingRoot("/var/library/state");

    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/var"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private/var"));

    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot(""));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("relative/path"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/work/"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/tmp"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/private/tmp"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/Users"));
    try t.expectError(error.UnsafeRoot, assertSafeNamingRoot("/var/lib/myapp"));

    try t.expectError(error.UnsafeRoot, assertSafeRoot("/work"));
    try t.expectError(error.UnsafeRoot, assertSafeRoot("/private/var"));
}

const root_relation_corpus = [_][]const u8{
    "/work",                        "/opt",               "/repo",                                  "/srv",             "/nix",               "/cores",
    "/data",                        "/scratch",           "/usr",                                   "/etc/myapp",       "/tmp",               "/private/tmp",
    "/Users",                       "/home",              "/var/lib/x",                             "/run/lock/x",      "/root",              "/Volumes",
    "/var",                         "/private",           "/private/var",                           "/opt/myapp/state", "/srv/myapp/state",   "/work/state",
    "/Users/someone/scratch/state", "/var/library/state", "/private/var/folders/lm/abcdef/T/state", "/optimism/state",  "/work/~cache/state", "/opt/a.b/c-d/state",
    "/srv/x y/state",               "/a/b/c/d/e/f/g/h",   "/work/state/",                           "relative/path",    "",                   "/",
    "//var",                        "/opt/../var",        "/work/.",
};

fn namingAccepts(root: []const u8) bool {
    assertSafeNamingRoot(root) catch return false;
    return true;
}

fn destructiveAccepts(root: []const u8) bool {
    assertSafeRoot(root) catch return false;
    return true;
}

test "the naming vet refuses a subset of what the destructive vet refuses (#359)" {
    const t = std.testing;

    var naming_only_accepts: usize = 0; // naming yes, destructive no — the depth rule's cell
    var both_accept: usize = 0;
    var both_refuse: usize = 0;

    for (root_relation_corpus) |root| {
        const naming = namingAccepts(root);
        const destructive = destructiveAccepts(root);
        var slashes: usize = 0;
        for (root) |ch| {
            if (ch == '/') slashes += 1;
        }

        // 0. The relation as an equality, which is what the property sentence says: the
        //    destructive vet accepts exactly what the naming vet accepts and is deep
        //    enough. Assertions 1 and 2 decompose it into the two directions and name
        //    which one broke; this line is what makes them an equality rather than a
        //    containment. Without it a destructive-side-only check confined to depth-1
        //    roots passes everything, because the cell it empties is still filled by the
        //    other seven.
        if (destructive != (naming and slashes >= 2)) {
            std.debug.print(
                "#359: {s} — naming {}, destructive {}, slashes {d}: the vets differ by something other than depth\n",
                .{ root, naming, destructive, slashes },
            );
            return error.VetsDifferBySomethingOtherThanDepth;
        }

        if (!naming and destructive) {
            std.debug.print("#359: naming refuses {s} but the destructive vet accepts it\n", .{root});
            return error.NamingRefusalNotCoveredByDestructive;
        }

        if (naming and !destructive) {
            if (slashes >= 2) {
                std.debug.print("#359: the destructive vet refuses {s} for a reason that is not depth\n", .{root});
                return error.DestructiveRefusalIsNotTheDepthRule;
            }
            naming_only_accepts += 1;
        } else if (naming and destructive) {
            both_accept += 1;
        } else {
            both_refuse += 1;
        }
    }

    // 3. The corpus separates them. Without this, a mutation can satisfy 1 and 2 by
    //    making one of the cells unreachable — which is exactly what adding the depth
    //    rule to the naming side does.
    try t.expect(naming_only_accepts > 0);
    try t.expect(both_accept > 0);
    try t.expect(both_refuse > 0);
}

test "assertSafeRoot refuses the ancestor a typed /var resolves to (#358)" {
    const t = std.testing;

    // On Linux `realpath("/var")` is `/var`, one component, refused by the depth rule
    // before and after this change — so a green here proves nothing on that platform and
    // is not counted. The assertion below is the macOS job's.
    var buf: [contract.max_path]u8 = undefined;
    const resolved_z = posix.realpath("/var", &buf) orelse {
        // A failure, not a skip: a host without /var would otherwise make this vacuous
        // and nobody would learn that the check stopped looking.
        return error.TestUnexpectedResult;
    };
    const resolved = std.mem.span(resolved_z);
    try t.expectError(error.UnsafeRoot, assertSafeRoot(resolved));

    // The refusal above is not enough on its own: on Linux the resolver returns `/var`,
    // which the depth rule refuses, so a green there says nothing about the outward read.
    // Count the components and assert which rule is doing the work. Two or more means the
    // depth rule passed it and something else refused it — on this repository's lists,
    // only the outward read can. One component means the platform never composes the
    // shape this test is about, and the assertion above is the depth rule's.
    var slashes: usize = 0;
    for (resolved) |ch| {
        if (ch == '/') slashes += 1;
    }
    if (slashes >= 2) {
        try t.expect(std.mem.eql(u8, resolved, "/private/var"));
    }
}

test "assertRootResolvesToItself refuses a root swapped for a symlink after resolution" {
    // Pid-unique parent (#28: zig build test runs test binaries concurrently), and the
    // base is taken back through realpath: on macOS /tmp is itself a link, so a literal
    // "/tmp/..." root never resolves to itself and every assertion below would be about
    // the wrong thing.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-rootswap-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var good_buf: [contract.max_path]u8 = undefined;
    const good = std.fmt.bufPrint(&good_buf, "{s}/state", .{base}) catch unreachable;
    var good_z: [contract.max_path]u8 = undefined;
    const good_zs = std.fmt.bufPrintZ(&good_z, "{s}", .{good}) catch unreachable;
    var other_buf: [contract.max_path]u8 = undefined;
    const other = std.fmt.bufPrint(&other_buf, "{s}/elsewhere", .{base}) catch unreachable;
    var other_z: [contract.max_path]u8 = undefined;
    const other_zs = std.fmt.bufPrintZ(&other_z, "{s}", .{other}) catch unreachable;
    defer {
        _ = posix.unlink(good_zs.ptr);
        _ = posix.rmdir(good_zs.ptr);
        _ = posix.rmdir(other_zs.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    try std.testing.expect(posix.mkdir(good_zs.ptr, 0o755) == 0);
    try std.testing.expect((try assertRootResolvesToItself(good)) == .identified);

    try std.testing.expect(posix.mkdir(other_zs.ptr, 0o755) == 0);
    try std.testing.expect(posix.rmdir(good_zs.ptr) == 0);
    try std.testing.expect(posix.symlink(other_zs.ptr, good_zs.ptr) == 0);

    try std.testing.expectError(error.UnsafeRoot, assertRootResolvesToItself(good));
    // Control: the sibling the link points at is itself fine, so the refusal above is
    // about the swap and not about anything in this directory.
    try std.testing.expect((try assertRootResolvesToItself(other)) == .identified);

    try std.testing.expect(posix.unlink(good_zs.ptr) == 0);
    try std.testing.expect((try assertRootResolvesToItself(good)) == .absent);
}

test "openRootDir refuses a root swapped between the vet and the open (#338)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vetwin-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    var bb: [contract.max_path]u8 = undefined;
    const moved_z = std.fmt.bufPrintZ(&bb, "{s}/moved", .{rparent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(moved_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    const vet = try assertRootResolvesToItself(root);
    try std.testing.expect(vet == .identified);

    // Control first: nothing swapped, the open is accepted. Without this the refusal below
    // is satisfied by a guard that refuses everything.
    switch (try openRootDir(root, vet)) {
        .fd => |fd| _ = posix.close(fd),
        .absent => return error.TestUnexpectedResult,
    }

    try std.testing.expect(posix.rename(root_z.ptr, moved_z.ptr) == 0);
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    try std.testing.expectError(error.UnsafeRoot, openRootDir(root, vet));

    const fd2 = posix.open(root_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fd2 >= 0);
    defer _ = posix.close(fd2);
    const held = try posix.identityOfFd(fd2);
    const named = try posix.identityOfPath(root_z.ptr);
    try std.testing.expect(held.eql(named)); // the rejected comparison passes here
    try std.testing.expect(!held.eql(vet.identified)); // the shipped one does not
}

test "openRootDir refuses a root that appeared after the vet found nothing (#338)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vetabs-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    try std.testing.expect((try assertRootResolvesToItself(root)) == .absent);
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    try std.testing.expectError(error.UnsafeRoot, openRootDir(root, .absent));

    // Control: the same directory, opened against a vet that did see it, is accepted — so
    // the refusal above is about the `.absent` verdict and not about this directory.
    const seen = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };
    switch (try openRootDir(root, seen)) {
        .fd => |fd| _ = posix.close(fd),
        .absent => return error.TestUnexpectedResult,
    }
}

test "createRoot keeps the vetted identity across a swap, rather than re-reading the name (#338)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-keepid-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var ab: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&ab, "{s}/state", .{parent}) catch unreachable;
    var bb: [contract.max_path]u8 = undefined;
    const moved_z = std.fmt.bufPrintZ(&bb, "{s}/moved", .{parent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(moved_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    const approved = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };

    // Control: no swap, and the identity comes back unchanged — so the assertion below is
    // about what `createRoot` does with the name, not about it returning a constant.
    const quiet = try createRoot(root_z.ptr, approved);
    try std.testing.expect(quiet.identified.eql(approved.identified));

    try std.testing.expect(posix.rename(root_z.ptr, moved_z.ptr) == 0);
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    const kept = try createRoot(root_z.ptr, approved);
    try std.testing.expect(kept.identified.eql(approved.identified));
    const intruder = try posix.identityOfPath(root_z.ptr);
    try std.testing.expect(!intruder.eql(approved.identified)); // the swap really happened
    try std.testing.expectError(error.UnsafeRoot, openRootDir(std.mem.span(root_z.ptr), kept));
}

test "a vetted root that vanishes leaves createRoot's own directory unvetted (#338)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-vanish-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    const approved = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };

    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    const kept = try createRoot(root_z.ptr, approved);
    try std.testing.expect(kept.identified.eql(approved.identified)); // still the vetted one
    try std.testing.expect((try posix.kindOfPathNoFollow(root_z.ptr)) == .dir); // and it did create

    // Whether the open refuses depends on the one thing the pair cannot see. Measured
    // 2026-09-01: overlayfs under Linux hands the new directory the number the old one had,
    // on the very next `mkdir`, three runs of three; APFS does not, three of three. So the
    // reuse case is not exotic on Linux -- it is what remove-then-recreate does by default.
    //
    // What it lets through is narrow, and worth writing beside the test rather than only in
    // the ADR. `O_NOFOLLOW` means the walk always reaches a real directory *at the vetted
    // path*, so a swap cannot redirect it elsewhere; the harm of one is that something worth
    // keeping ends up at that path. A directory *moved* there brings its own inode and is
    // refused. Only an object the filesystem created after the vetted one was unlinked can
    // inherit the number, and that object is a new, empty directory.
    //
    // Asserting the refusal where it is deliverable, and naming the world otherwise, rather
    // than asserting a portable refusal that is not.
    const now = try posix.identityOfPath(root_z.ptr);
    if (!now.eql(approved.identified)) {
        try std.testing.expectError(error.UnsafeRoot, openRootDir(root, kept));
    }
}

test "createRoot refuses a root that arrived after the vet found nothing (#338)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-mkwin-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var ab: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&ab, "{s}/state", .{parent}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    // First run: the vet saw nothing and nothing is there. The `mkdir` succeeds and names
    // what it made. This is the ordinary path, asserted first so the refusal below cannot
    // be satisfied by a rule that refuses whenever the vet was empty.
    const first = try createRoot(root_z.ptr, .absent);
    try std.testing.expect(first == .identified);
    try std.testing.expect((try posix.kindOfPathNoFollow(root_z.ptr)) == .dir);

    try std.testing.expectError(error.UnsafeRoot, createRoot(root_z.ptr, .absent));

    const seen = RootVet{ .identified = try posix.identityOfPath(root_z.ptr) };
    const again = try createRoot(root_z.ptr, seen);
    try std.testing.expect(again == .identified);
    try std.testing.expect(again.identified.eql(seen.identified));
}

test "restore still creates a root that is not there yet (#338)" {
    // The over-strictness detector. #338 makes three destructive paths refuse a root they
    // did not vet, and the first run of every world arrives here with no root at all: the
    // vet answers `.absent`, `restore`'s own `mkdir` puts the directory there, and the
    // identity it holds the descriptor to has to be taken after that `mkdir` rather than
    // before it. An implementation that refuses whenever the vet found nothing passes
    // every swap test above and breaks every ordinary run.
    const gpa = std.testing.allocator;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent = std.fmt.bufPrint(&pbuf, "/tmp/sideeye-firstrun-{d}", .{std.c.getpid()}) catch unreachable;
    var pz: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{parent}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var dbuf: [contract.max_path]u8 = undefined;
    const rparent = std.mem.span(posix.realpath(parent_z.ptr, &dbuf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&ab, "{s}/state", .{rparent}) catch unreachable;
    var az: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&az, "{s}", .{root}) catch unreachable;
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a", .kind = .file, .content = "x" });

    try std.testing.expect((try assertRootResolvesToItself(root)) == .absent);
    try restore(snap, root);

    var eb: [contract.max_path]u8 = undefined;
    const entry_z = try joinZ(&eb, root, "a");
    try std.testing.expect((try posix.kindOfPathNoFollow(entry_z.ptr)) == .file);
    _ = posix.unlink(entry_z.ptr);

    try std.testing.expect((try assertRootResolvesToItself(root)) == .identified);
    try restore(snap, root);
    try std.testing.expect((try posix.kindOfPathNoFollow(entry_z.ptr)) == .file);
}

test "restore and freshDir refuse a swapped root — the guard is wired in front of the delete" {
    // The test above drives assertRootResolvesToItself directly, which says nothing about
    // whether the destructive path calls it. Deleting the call from `restore` left that
    // test green (measured), so this one aims at the call sites instead: a guard that
    // exists and never executes is the failure mode being ruled out here.
    const gpa = std.testing.allocator;

    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-wired-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{base}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    var obuf: [contract.max_path]u8 = undefined;
    const outside = std.fmt.bufPrint(&obuf, "{s}/outside", .{base}) catch unreachable;
    var ozbuf: [contract.max_path]u8 = undefined;
    const outside_z = std.fmt.bufPrintZ(&ozbuf, "{s}", .{outside}) catch unreachable;
    defer {
        _ = posix.unlink(root_z.ptr); // the symlink, if the swap below happened
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        deleteTree(outside) catch {};
        _ = posix.rmdir(outside_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(outside_z.ptr, 0o755) == 0);

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "a", .kind = .file, .content = "x" });

    // Control: the unswapped root restores. Without this the refusal below could be
    // about anything in this directory rather than about the swap.
    try restore(snap, root);

    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    const fd = posix.open(sentinel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);

    deleteTree(root) catch {};
    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    try std.testing.expect(posix.symlink(outside_z.ptr, root_z.ptr) == 0);

    try std.testing.expectError(error.UnsafeRoot, restore(snap, root));
    try std.testing.expectError(error.UnsafeRoot, freshDir(root));
    try std.testing.expectError(error.UnsafeRoot, corruptState(snap, root));

    try std.testing.expectEqual(posix.Kind.file, try posix.kindOfPathNoFollow(sentinel_z.ptr));
}

test "the rebuild refuses to write through a symlink at an entry name (#446)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    const root = fx.init("writeentry") orelse return error.SkipZigTest;
    defer fx.deinit();
    const outside = try fx.sibling("outside");

    const keep = "keep-me-intact\n";
    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    try TreeFixture.writeAt(sentinel_z.ptr, keep);

    var rz: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{root}) catch unreachable;
    const fd = posix.open(root_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0));
    try std.testing.expect(fd >= 0);
    defer _ = posix.close(fd);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Control first: a real entry name is written, so the refusal below is about the link
    // and not about this directory, these flags, or these bytes.
    try writeFileEntryAt(fd, "real", "recorded bytes", null, false);
    var real_buf: [contract.max_path]u8 = undefined;
    const real_z = try joinZ(&real_buf, root, "real");
    try std.testing.expectEqualStrings("recorded bytes", try read.readWhole(arena, real_z.ptr, 4096, null, .follow));

    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = try joinZ(&lbuf, root, "planted");
    try std.testing.expect(posix.symlink(sentinel_z.ptr, link_z.ptr) == 0);

    try std.testing.expectError(error.CreateFailed, writeFileEntryAt(fd, "planted", "recorded bytes", null, false));

    // The bytes outside are untouched — the whole point. `expectEqualStrings` rather than
    // a length or an existence check: a followed write truncates first and would leave an
    // empty file that still exists.
    try std.testing.expectEqualStrings(keep, try read.readWhole(arena, sentinel_z.ptr, 4096, null, .follow));
    try std.testing.expectEqual(posix.Kind.symlink, try posix.kindOfPathNoFollow(link_z.ptr));
}

test "corruptState refuses a planted symlink rather than corrupting what it points at (#446)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    const root = fx.init("corrupt-nofollow") orelse return error.SkipZigTest;
    defer fx.deinit();
    const outside = try fx.sibling("outside");

    const keep = "not-a-probe\n";
    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    try TreeFixture.writeAt(sentinel_z.ptr, keep);

    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    // A real entry before the planted one, as the positive control: without it, the two
    // assertions below are also satisfied by a `corruptState` that refused before reaching
    // any write at all — `openRootDir` answering `.absent`, say. The probe landing in this
    // file is what says the write path was entered.
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "real", .kind = .file, .content = "recorded" });
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "planted", .kind = .file, .content = "recorded" });
    var real_buf: [contract.max_path]u8 = undefined;
    const real_z = try joinZ(&real_buf, root, "real");
    try TreeFixture.writeAt(real_z.ptr, "recorded");

    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = try joinZ(&lbuf, root, "planted");
    try std.testing.expect(posix.symlink(sentinel_z.ptr, link_z.ptr) == 0);

    try std.testing.expectError(error.CreateFailed, corruptState(snap, root));

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The control: the entry that is a real file was corrupted, so the refusal above is
    // the write path saying no to the link, not this function stopping short of it.
    try std.testing.expectEqualStrings(corruption_probe, try read.readWhole(arena, real_z.ptr, 4096, null, .follow));
    try std.testing.expectEqualStrings(keep, try read.readWhole(arena, sentinel_z.ptr, 4096, null, .follow));
}

test "the walk drains a directory past its collection bound, in one call (#327)" {
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-drain-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(base_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var rb: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rb, "{s}/state", .{base}) catch unreachable;
    var rzb: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzb, "{s}", .{root}) catch unreachable;
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);

    var i: usize = 0;
    while (i < 400) : (i += 1) {
        var nb: [contract.max_path]u8 = undefined;
        const n_z = std.fmt.bufPrintZ(&nb, "{s}/entry-{d}", .{ root, i }) catch unreachable;
        const fd = posix.open(n_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(fd >= 0);
        _ = posix.close(fd);
    }

    try deleteTree(root);

    // Counted rather than sampled: "the first entry is gone" is true of a partial drain.
    var snap = try takeSnapshot(std.testing.allocator, root);
    defer snap.deinit();
    try std.testing.expectEqual(@as(usize, 0), snap.entries.items.len);
}

test "freshDir on a missing parent stays loud; the shared open has two meanings (#327)" {
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-noparent-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.rmdir(base_z.ptr); // must not exist; a leftover from a crashed run would hide the case
    var rb: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rb, "{s}/gone/state", .{base_z}) catch unreachable;

    try std.testing.expectError(error.DeleteFailed, freshDir(root));

    // Control: with the parent there, the same call succeeds — so the refusal above is
    // about the missing parent and not about the path being rejected for some other reason.
    var gb: [contract.max_path]u8 = undefined;
    const gone_z = std.fmt.bufPrintZ(&gb, "{s}/gone", .{base_z}) catch unreachable;
    var rzb: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzb, "{s}", .{root}) catch unreachable;
    defer {
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(gone_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    try std.testing.expect(posix.mkdir(base_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(gone_z.ptr, 0o755) == 0);
    try freshDir(root);
}

test "the walk on its own follows a swapped root; the descriptor is what stops it (#327)" {
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-isolated-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);

    var rbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&rbuf, "{s}/state", .{base}) catch unreachable;
    var rzbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rzbuf, "{s}", .{root}) catch unreachable;
    var obuf: [contract.max_path]u8 = undefined;
    const outside = std.fmt.bufPrint(&obuf, "{s}/outside", .{base}) catch unreachable;
    var ozbuf: [contract.max_path]u8 = undefined;
    const outside_z = std.fmt.bufPrintZ(&ozbuf, "{s}", .{outside}) catch unreachable;
    defer {
        _ = posix.unlink(root_z.ptr); // the symlink planted below
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        deleteTree(outside) catch {};
        _ = posix.rmdir(outside_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }
    try std.testing.expect(posix.mkdir(root_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(outside_z.ptr, 0o755) == 0);

    var sbuf: [contract.max_path]u8 = undefined;
    const sentinel_z = try joinZ(&sbuf, outside, "keep-me");
    const fd = posix.open(sentinel_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);

    try std.testing.expect(posix.rmdir(root_z.ptr) == 0);
    try std.testing.expect(posix.symlink(outside_z.ptr, root_z.ptr) == 0);

    deleteTree(root) catch {};

    try std.testing.expectEqual(posix.Kind.file, try posix.kindOfPathNoFollow(sentinel_z.ptr));
}

test "readLinkTarget is fail-closed at its own boundary (#122)" {
    var dbuf: [contract.max_path]u8 = undefined;
    const dir_z = std.fmt.bufPrintZ(&dbuf, "/tmp/sideeye-readlink-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(dir_z.ptr, 0o755);
    var lbuf: [contract.max_path]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&lbuf, "{s}/l", .{dir_z}) catch unreachable;
    _ = posix.unlink(link_z.ptr);
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("0123456789", link_z.ptr));
    defer {
        _ = posix.unlink(link_z.ptr);
        _ = posix.rmdir(dir_z.ptr);
    }

    var small: [8]u8 = undefined;
    var trunc_errno: ?c_int = 99;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(link_z.ptr, &small, &trunc_errno));
    try std.testing.expectEqual(@as(?c_int, null), trunc_errno);
    var exact: [10]u8 = undefined;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(link_z.ptr, &exact, null));
    var roomy: [11]u8 = undefined;
    try std.testing.expectEqualStrings("0123456789", readLinkTarget(link_z.ptr, &roomy, null).?);
    var missing_buf: [contract.max_path]u8 = undefined;
    const missing_z = std.fmt.bufPrintZ(&missing_buf, "{s}/absent", .{dir_z}) catch unreachable;
    var big: [64]u8 = undefined;
    var missing_errno: ?c_int = null;
    try std.testing.expectEqual(@as(?[]const u8, null), readLinkTarget(missing_z.ptr, &big, &missing_errno));
    try std.testing.expectEqual(@as(?c_int, posix.ENOENT), missing_errno);
}

test "snapshot, restore and corruptState carry symlinks as links (#122)" {
    const gpa = std.testing.allocator;

    // Pid-unique root (#28: zig build test runs test binaries concurrently), built from
    // the RESOLVED parent: `restore` requires the root to resolve to itself
    // (assertRootResolvesToItself), which is what the call sites hand it. A literal "/tmp/..."
    // root satisfies that on Linux and fails on macOS, where /tmp is itself a link.
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-symlink-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var dbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&dbuf, "{s}/state", .{base}) catch unreachable;
    var rbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var fbuf: [contract.max_path]u8 = undefined;
    const file_z = try joinZ(&fbuf, root, "key.json");
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 4), posix.write(fd, "k=1\n", 4));
    _ = posix.close(fd);
    var lbuf: [contract.max_path]u8 = undefined;
    const rel_link_z = try joinZ(&lbuf, root, "rel-link");
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("key.json", rel_link_z.ptr));
    var gbuf: [contract.max_path]u8 = undefined;
    const dangling_z = try joinZ(&gbuf, root, "dangling");
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("/nowhere/dangling", dangling_z.ptr));

    var snap = try takeSnapshot(gpa, root);
    defer snap.deinit();
    try std.testing.expectEqual(@as(usize, 3), snap.entries.items.len);
    const rl = snap.find("rel-link") orelse return error.MissingEntry;
    try std.testing.expectEqual(posix.Kind.symlink, rl.kind);
    try std.testing.expectEqualStrings("key.json", rl.content);
    const dg = snap.find("dangling") orelse return error.MissingEntry;
    try std.testing.expectEqual(posix.Kind.symlink, dg.kind);
    try std.testing.expectEqualStrings("/nowhere/dangling", dg.content);
    try std.testing.expectEqual(@as(usize, 3), countCorruptible(snap));

    try std.testing.expectEqual(@as(c_int, 0), posix.unlink(rel_link_z.ptr));
    try std.testing.expectEqual(@as(c_int, 0), posix.symlink("elsewhere", rel_link_z.ptr));
    try std.testing.expectEqual(@as(c_int, 0), posix.unlink(dangling_z.ptr));
    try restore(snap, root);
    var tbuf: [contract.max_path]u8 = undefined;
    var n = posix.readlink(rel_link_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("key.json", tbuf[0..@intCast(n)]);
    n = posix.readlink(dangling_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("/nowhere/dangling", tbuf[0..@intCast(n)]);

    try corruptState(snap, root);
    n = posix.readlink(rel_link_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings(corruption_probe_target, tbuf[0..@intCast(n)]);
    n = posix.readlink(dangling_z.ptr, &tbuf, tbuf.len);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings(corruption_probe_target, tbuf[0..@intCast(n)]);
}

test "a links-only state is corruptible, so the falsification gate keeps meaning (#122)" {
    const gpa = std.testing.allocator;
    var snap: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer snap.deinit();
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "pkg", .kind = .dir, .content = "" });
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "pkg/bin", .kind = .symlink, .content = "../stow/pkg/bin" });
    try std.testing.expectEqual(@as(usize, 1), countCorruptible(snap));
}

test "ownership/permission writes change nothing a snapshot judges (#121's own predicate)" {
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-chmod-inv-{d}", .{posix.getpid()}) catch unreachable;
    var dz_buf: [contract.max_path]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&dz_buf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(dz.ptr, 0o755);
    var fbuf: [contract.max_path]u8 = undefined;
    const fz = try joinZ(&fbuf, dir, "f.txt");
    const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 2), posix.write(fd, "x\n", 2));
    _ = posix.close(fd);
    defer {
        _ = posix.unlink(fz.ptr);
        _ = posix.rmdir(dz.ptr);
    }

    const gpa = std.testing.allocator;
    var before = try takeSnapshot(gpa, dir);
    defer before.deinit();
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(fz.ptr, 0o600));
    var after = try takeSnapshot(gpa, dir);
    defer after.deinit();

    try std.testing.expectEqual(before.entries.items.len, after.entries.items.len);
    for (before.entries.items, after.entries.items) |b, a| {
        try std.testing.expectEqualStrings(b.rel, a.rel);
        try std.testing.expectEqual(b.kind, a.kind);
        try std.testing.expectEqualStrings(b.content, a.content);
    }
}

test "deleteTree refuses a PARTIAL failure instead of leaving residue (#121, R1)" {
    if (std.c.geteuid() == 0) return error.SkipZigTest; // root ignores modes
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&dbuf, "/tmp/sideeye-deltree-{d}/state", .{posix.getpid()}) catch unreachable;
    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-deltree-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var rz_buf: [contract.max_path]u8 = undefined;
    const rz = std.fmt.bufPrintZ(&rz_buf, "{s}", .{dir}) catch unreachable;
    _ = posix.mkdir(rz.ptr, 0o755);
    var sb: [contract.max_path]u8 = undefined;
    const sub_z = try joinZ(&sb, dir, "locked");
    _ = posix.mkdir(sub_z.ptr, 0o755);
    var ib: [contract.max_path]u8 = undefined;
    const inner_z = try joinZ(&ib, dir, "locked/held.txt");
    const fd = posix.open(inner_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    var gb: [contract.max_path]u8 = undefined;
    const gone_z = try joinZ(&gb, dir, "goes.txt");
    const fd2 = posix.open(gone_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd2 >= 0);
    _ = posix.close(fd2);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(sub_z.ptr, 0o000));
    defer {
        _ = std.c.chmod(sub_z.ptr, 0o755);
        _ = posix.unlink(inner_z.ptr);
        _ = posix.rmdir(sub_z.ptr);
        _ = posix.unlink(gone_z.ptr);
        _ = posix.rmdir(rz.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    try std.testing.expectError(error.DeleteFailed, deleteTree(dir));
}

test "the per-file cap refuses, names the file, and carries its size (#265)" {
    const gpa = std.testing.allocator;

    var pbuf: [contract.max_path]u8 = undefined;
    const parent_z = std.fmt.bufPrintZ(&pbuf, "/tmp/sideeye-filecap-test-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(parent_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var dbuf: [contract.max_path]u8 = undefined;
    const root = std.fmt.bufPrint(&dbuf, "{s}/state", .{base}) catch unreachable;
    var rbuf: [contract.max_path]u8 = undefined;
    const root_z = std.fmt.bufPrintZ(&rbuf, "{s}", .{root}) catch unreachable;
    _ = posix.mkdir(root_z.ptr, 0o755);
    defer {
        deleteTree(root) catch {};
        _ = posix.rmdir(root_z.ptr);
        _ = posix.rmdir(parent_z.ptr);
    }

    var fbuf: [contract.max_path]u8 = undefined;
    const file_z = try joinZ(&fbuf, root, "grown.log");
    const fd = posix.open(file_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expectEqual(@as(isize, 9), posix.write(fd, "123456789", 9));
    _ = posix.close(fd);

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.FileTooLarge,
        takeSnapshotCapped(gpa, root, onlyFileCap(8), &diag),
    );
    try std.testing.expectEqualStrings("grown.log", diag.file.rel.get());
    try std.testing.expectEqual(@as(?u64, 9), diag.file.size);

    var ok = try takeSnapshotCapped(gpa, root, onlyFileCap(9), null);
    defer ok.deinit();
    try std.testing.expectEqual(@as(usize, 1), ok.entries.items.len);
    try std.testing.expectEqualStrings("123456789", ok.entries.items[0].content);
}

fn onlyFileCap(n: usize) SnapshotCaps {
    return .{ .file = n, .tree = std.math.maxInt(usize) };
}

fn onlyTreeCap(n: usize) SnapshotCaps {
    return .{ .file = std.math.maxInt(usize), .tree = n };
}

const TreeFixture = struct {
    parent_z: [contract.max_path]u8 = undefined,
    root_buf: [contract.max_path]u8 = undefined,
    root: []const u8 = &.{},
    outside_buf: [contract.max_path]u8 = undefined,
    outside: []const u8 = &.{},

    fn init(self: *TreeFixture, tag: []const u8) ?[]const u8 {
        const parent_z = std.fmt.bufPrintZ(&self.parent_z, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() }) catch unreachable;
        _ = posix.mkdir(parent_z.ptr, 0o755);
        var base_buf: [contract.max_path]u8 = undefined;
        // Every caller does `init(...) orelse return error.SkipZigTest`, which is BEFORE
        // its `defer deinit()` — so a failure here has to take the parent back out itself
        // or leave a directory behind for the rest of the machine's life.
        const base = std.mem.span(posix.realpath(parent_z.ptr, &base_buf) orelse {
            _ = posix.rmdir(parent_z.ptr);
            return null;
        });
        self.root = std.fmt.bufPrint(&self.root_buf, "{s}/state", .{base}) catch unreachable;
        var rz: [contract.max_path]u8 = undefined;
        const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{self.root}) catch unreachable;
        _ = posix.mkdir(root_z.ptr, 0o755);
        return self.root;
    }

    /// **One per fixture.** There is a single slot, so a second call would overwrite the
    /// first and leave that directory behind for the rest of the machine's life; the
    /// assert makes that a test failure rather than a slow leak.
    fn sibling(self: *TreeFixture, name: []const u8) ![]const u8 {
        std.debug.assert(self.outside.len == 0);
        const base = std.fs.path.dirname(self.root) orelse return error.SkipZigTest;
        self.outside = std.fmt.bufPrint(&self.outside_buf, "{s}/{s}", .{ base, name }) catch unreachable;
        var oz: [contract.max_path]u8 = undefined;
        const outside_z = std.fmt.bufPrintZ(&oz, "{s}", .{self.outside}) catch unreachable;
        if (posix.mkdir(outside_z.ptr, 0o755) != 0) return error.SkipZigTest;
        return self.outside;
    }

    fn deinit(self: *TreeFixture) void {
        deleteTree(self.root) catch {};
        var rz: [contract.max_path]u8 = undefined;
        const root_z = std.fmt.bufPrintZ(&rz, "{s}", .{self.root}) catch unreachable;
        _ = posix.rmdir(root_z.ptr);
        if (self.outside.len != 0) {
            deleteTree(self.outside) catch {};
            var oz: [contract.max_path]u8 = undefined;
            const outside_z = std.fmt.bufPrintZ(&oz, "{s}", .{self.outside}) catch unreachable;
            _ = posix.rmdir(outside_z.ptr);
        }
        var pz: [contract.max_path]u8 = undefined;
        const parent_z = std.fmt.bufPrintZ(&pz, "{s}", .{std.mem.sliceTo(&self.parent_z, 0)}) catch unreachable;
        _ = posix.rmdir(parent_z.ptr);
    }

    /// A short write fails the test rather than skipping it. `fill` and `fillDirs` skip on
    /// everything, which is right for bulk setup, and wrong here: callers use this to
    /// place the bytes an assertion is about — a positive control that quietly turned into
    /// a skip would leave the guard unmeasured and the suite green. The open keeps
    /// `SkipZigTest`, because that one is about whether the environment can host the test
    /// at all, which is the same question `init` and `sibling` answer.
    fn writeAt(path_z: [*:0]const u8, bytes: []const u8) !void {
        const fd = posix.open(path_z, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        if (fd < 0) return error.SkipZigTest;
        defer _ = posix.close(fd);
        try std.testing.expectEqual(@as(isize, @intCast(bytes.len)), posix.write(fd, bytes.ptr, bytes.len));
    }

    fn fillDirs(self: *TreeFixture, n: usize) !void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var dbuf: [contract.max_path]u8 = undefined;
            var nbuf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&nbuf, "d{d:0>5}", .{i}) catch unreachable;
            const dz = try joinZ(&dbuf, self.root, name);
            if (posix.mkdir(dz.ptr, 0o755) != 0) return error.SkipZigTest;
        }
    }

    fn fill(self: *TreeFixture, n: usize, bytes: usize) !void {
        var chunk: [4096]u8 = @splat('x');
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var fbuf: [contract.max_path]u8 = undefined;
            var nbuf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&nbuf, "f{d:0>5}", .{i}) catch unreachable;
            const fz = try joinZ(&fbuf, self.root, name);
            const fd = posix.open(fz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
            if (fd < 0) return error.SkipZigTest;
            defer _ = posix.close(fd);
            var left = bytes;
            while (left > 0) {
                const take = @min(left, chunk.len);
                if (posix.write(fd, &chunk, take) != @as(isize, @intCast(take))) return error.SkipZigTest;
                left -= take;
            }
        }
    }
};

test "the tree ceiling stops the walk where it breaks, rather than after reading everything (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-stop") orelse return error.SkipZigTest;
    defer fx.deinit();

    const files = 40;
    const each = 64 * 1024;
    const cap = 256 * 1024;
    try fx.fill(files, each);

    var full = try takeSnapshotCapped(gpa, fx.root, onlyTreeCap(std.math.maxInt(usize)), null);
    const full_capacity = full.arena.queryCapacity();
    try std.testing.expectEqual(@as(usize, files), full.entries.items.len);
    full.deinit();

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(cap), &diag),
    );

    // The ceiling was passed — otherwise the refusal is reporting something else.
    try std.testing.expect(diag.tree.reached > cap);

    try std.testing.expect(diag.tree.reached < full_capacity);

    try std.testing.expect(diag.tree.entries < files);
    try std.testing.expect(diag.tree.entries > 0);

    // **The two counters pinned against each other, not just bounded.** Every file here
    // is the same size, so the product is exact — and a bound alone does not hold them:
    // review measured that deleting `charged = content.len` from the `.file` branch left
    // the whole suite green, because `0 < files * each` is true and the empty-tree test
    // below wants `content == 0` anyway. The operator-facing half of the refusal could
    // have been permanently zero with nothing noticing.
    try std.testing.expectEqual(diag.tree.entries * each, diag.tree.content);

    // Positive control on the same tree: above its footprint, the snapshot succeeds and
    // carries every entry. **It also pins "over, not at"** — the ceiling passed here is
    // `full_capacity` exactly, so tightening `charge`'s `reached <= caps.tree` to `<`
    // reddens this line. What no fixture can do is land `queryCapacity` on a *chosen*
    // value, because `ArenaAllocator` hands out whole nodes sized 1.5x their predecessor;
    // taking the boundary from the tree's own measured cost is the way around that, and
    // it is why this control is not the decoration it looks like.
    var ok = try takeSnapshotCapped(gpa, fx.root, onlyTreeCap(full_capacity), null);
    defer ok.deinit();
    try std.testing.expectEqual(@as(usize, files), ok.entries.items.len);
}

test "the tree ceiling charges directories too, which is the only entry kind with its own charge (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-dirs") orelse return error.SkipZigTest;
    defer fx.deinit();

    try fx.fillDirs(500);

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(32 * 1024), &diag),
    );
    try std.testing.expectEqual(@as(u64, 0), diag.tree.content);
    try std.testing.expect(diag.tree.entries < 500);
}

test "the tree ceiling counts what the snapshot holds, not the bytes it read (#323)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    _ = fx.init("treecap-metric") orelse return error.SkipZigTest;
    defer fx.deinit();

    try fx.fill(2000, 0);

    var diag: SnapshotDiag = .{};
    try std.testing.expectError(
        error.TreeTooLarge,
        takeSnapshotCapped(gpa, fx.root, onlyTreeCap(32 * 1024), &diag),
    );

    try std.testing.expectEqual(@as(u64, 0), diag.tree.content);
    try std.testing.expect(diag.tree.entries > 0);
    try std.testing.expect(diag.tree.reached > 32 * 1024);
}

test "this file's public surface is the twenty-three the facade re-exports (#491)" {
    // The three aliases above (`Snapshot`, `Entry`, `finalizeEntries`) are private on
    // purpose, and `engine.zig`'s facade walk cannot see it if one becomes `pub`: it would
    // find that name already re-exported from `snapshot.zig`, and the identity check would
    // compare the same declaration to itself. So the count is checked here instead, the way
    // `judge.zig` checks its eight. `std.meta.declarations` lists public declarations only.
    //
    // Another public declaration is not a mistake by itself — it is a new name for the
    // facade to re-export, and this number moves with it: nineteen until #535 added
    // `EntryRel` and `EntryDiag`, twenty-one until #817 added `MountScan` and
    // `firstMountInside`, twenty-three since.
    try std.testing.expectEqual(@as(usize, 23), std.meta.declarations(@This()).len);
}

test "an entry the walk cannot read is named in the diag, with the open's errno (#535)" {
    if (posix.geteuid() == 0) return error.SkipZigTest; // root reads mode 0000
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrintZ(&dbuf, "/tmp/sideeye-unreadable-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(dir.ptr, 0o755);
    var fb: [contract.max_path]u8 = undefined;
    const ok_z = try joinZ(&fb, dir, "readable.txt");
    const fd0 = posix.open(ok_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd0 >= 0);
    _ = posix.close(fd0);
    var lb: [contract.max_path]u8 = undefined;
    const lock_z = try joinZ(&lb, dir, "m_inmail.lock");
    const fd = posix.open(lock_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o000));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    defer {
        _ = posix.unlink(lock_z.ptr);
        _ = posix.unlink(ok_z.ptr);
        _ = posix.rmdir(dir.ptr);
    }
    var diag: SnapshotDiag = .{};
    try std.testing.expectError(error.ReadFailed, takeSnapshotCapped(std.testing.allocator, dir, SnapshotCaps.shipped, &diag));
    try std.testing.expectEqualStrings("m_inmail.lock", diag.entry.rel.get());
    try std.testing.expectEqual(EntryDiag.Kind.file, diag.entry.kind);
    try std.testing.expectEqual(@as(?c_int, posix.EACCES), diag.entry.errno);
    try std.testing.expectEqual(@as(usize, 0), diag.file.rel.len);
}

test "restore puts back the permission bits the walk read, whatever the umask (#678)" {
    const gpa = std.testing.allocator;
    var fx: TreeFixture = .{};
    const root = fx.init("modes") orelse return error.SkipZigTest;
    defer fx.deinit();
    const chmodAt = struct {
        fn f(path_z: [*:0]const u8, m: u16) !void {
            const fd = posix.open(path_z, posix.O_RDONLY | posix.O_CLOEXEC, @as(c_uint, 0));
            if (fd < 0) return error.SkipZigTest;
            defer _ = posix.close(fd);
            try std.testing.expectEqual(@as(c_int, 0), posix.fchmod(fd, m));
        }
    }.f;
    const files = [_]struct { []const u8, u16 }{ .{ "exe", 0o755 }, .{ "key", 0o600 }, .{ "ro", 0o400 }, .{ "plain", 0o644 } };
    var pbuf: [contract.max_path]u8 = undefined;
    for (files) |f| {
        const p = try joinZ(&pbuf, root, f[0]);
        try TreeFixture.writeAt(p.ptr, "x");
        try chmodAt(p.ptr, f[1]);
    }
    const d5 = try joinZ(&pbuf, root, "d500");
    try std.testing.expect(posix.mkdir(d5.ptr, 0o755) == 0);
    const d5c = try joinZ(&pbuf, root, "d500/child");
    try TreeFixture.writeAt(d5c.ptr, "c");
    // Its own buffer: `pbuf` is reused for every other path below.
    var d5buf: [contract.max_path]u8 = undefined;
    const d5z = try joinZ(&d5buf, root, "d500");
    try chmodAt(d5z.ptr, 0o500);
    const d7 = try joinZ(&pbuf, root, "d750");
    try std.testing.expect(posix.mkdir(d7.ptr, 0o755) == 0);
    try chmodAt(d7.ptr, 0o750);

    var snap = try takeSnapshot(gpa, root);
    defer snap.deinit();
    try std.testing.expectEqual(@as(?u16, 0o755), snap.find("exe").?.mode);
    try std.testing.expectEqual(@as(?u16, 0o400), snap.find("ro").?.mode);
    try std.testing.expectEqual(@as(?u16, 0o500), snap.find("d500").?.mode);
    try snap.entries.append(snap.arena.allocator(), .{ .rel = "unread", .kind = .file, .content = "u" });
    try finalizeEntries(&snap);
    // Before the first rebuild: `deleteTreeAt` cannot empty a directory its owner cannot write.
    try chmodAt(d5z.ptr, 0o755);

    // Without this umask, bits passed through `openat`'s mode argument would pass too.
    const old_mask = std.c.umask(0o077);
    defer _ = std.c.umask(old_mask);
    try restore(snap, root);
    const want = [_]struct { []const u8, u16 }{
        .{ "exe", 0o755 },  .{ "key", 0o600 },  .{ "ro", 0o400 },     .{ "plain", 0o644 },
        .{ "d750", 0o750 }, .{ "d500", 0o700 }, .{ "unread", 0o600 },
    };
    for (want) |w| {
        const p = try joinZ(&pbuf, root, w[0]);
        try std.testing.expectEqual(@as(?u16, w[1]), (posix.kindModeOfPathNoFollow(p.ptr) orelse posix.KindMode{ .kind = .missing, .mode = null }).mode);
    }
    try restore(snap, root);
    const rz = try joinZ(&pbuf, root, "ro");
    try std.testing.expectEqual(@as(?u16, 0o400), (posix.kindModeOfPathNoFollow(rz.ptr) orelse posix.KindMode{ .kind = .missing, .mode = null }).mode);
    try corruptState(snap, root);
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    try std.testing.expectEqualStrings(corruption_probe, try read.readWhole(arena_state.allocator(), rz.ptr, 4096, null, .follow));
    try std.testing.expectEqual(@as(?u16, 0o400), (posix.kindModeOfPathNoFollow(rz.ptr) orelse posix.KindMode{ .kind = .missing, .mode = null }).mode);
}

test "the walk's directory reading names its kind, and an exclusive write refuses a name that is there (#678)" {
    var fx: TreeFixture = .{};
    const root = fx.init("kindmode") orelse return error.SkipZigTest;
    defer fx.deinit();
    var dbuf: [contract.max_path]u8 = undefined;
    const d = try joinZ(&dbuf, root, "d");
    try std.testing.expect(posix.mkdir(d.ptr, 0o755) == 0);
    var lbuf: [contract.max_path]u8 = undefined;
    const l = try joinZ(&lbuf, root, "l");
    try std.testing.expect(posix.symlink(d.ptr, l.ptr) == 0);
    try std.testing.expectEqual(posix.Kind.dir, posix.kindModeOfPathNoFollow(d.ptr).?.kind);
    try std.testing.expectEqual(posix.Kind.symlink, posix.kindModeOfPathNoFollow(l.ptr).?.kind);

    var rbuf: [contract.max_path]u8 = undefined;
    const root_z = try joinZ(&rbuf, root, "");
    const fd = posix.open(root_z.ptr, posix.O_RDONLY | posix.O_DIRECTORY | posix.O_CLOEXEC, @as(c_uint, 0));
    if (fd < 0) return error.SkipZigTest;
    defer _ = posix.close(fd);
    try writeFileEntryAt(fd, "f", "one", null, false);
    try std.testing.expectError(error.CreateFailed, writeFileEntryAt(fd, "f", "two", null, true));
    try writeFileEntryAt(fd, "f", "three", null, false);
}

test "a directory entry keeps the bits only of a directory (#678)" {
    try std.testing.expectEqual(@as(?u16, 0o750), dirModeOf(.{ .kind = .dir, .mode = 0o750 }));
    try std.testing.expectEqual(@as(?u16, null), dirModeOf(.{ .kind = .symlink, .mode = 0o777 }));
    try std.testing.expectEqual(@as(?u16, null), dirModeOf(.{ .kind = .file, .mode = 0o644 }));
    try std.testing.expectEqual(@as(?u16, null), dirModeOf(null));
}

test "a mount table line yields its mount point with the kernel's escapes undone" {
    var b: [contract.max_path]u8 = undefined;
    try std.testing.expectEqualStrings("/s/state/sub", mountPointOfLine("36 35 98:0 /outside /s/state/sub rw,relatime shared:1 - ext4 /dev/vda1 rw", &b).?);
    try std.testing.expectEqualStrings("/s/my state/a\\b", mountPointOfLine("36 35 98:0 / /s/my\\040state/a\\134b rw - ext4 /dev/vda1 rw", &b).?);
    try std.testing.expectEqualStrings("/s/\\9xx", mountPointOfLine("1 2 3:4 / /s/\\9xx rw - x y rw", &b).?);
    try std.testing.expect(mountPointOfLine("36 35 98:0 /outside", &b) == null);
    var small: [4]u8 = undefined;
    try std.testing.expect(mountPointOfLine("36 35 98:0 / /s/state/sub rw - ext4 x rw", &small) == null);
}

test "a mount point is inside the state only strictly below its root" {
    try std.testing.expectEqualStrings("sub", relInsideRoot("/s/state/sub", "/s/state").?);
    try std.testing.expectEqualStrings("a/b", relInsideRoot("/s/state/a/b", "/s/state").?);
    try std.testing.expect(relInsideRoot("/s/state", "/s/state") == null);
    try std.testing.expect(relInsideRoot("/s/state2", "/s/state") == null);
    try std.testing.expect(relInsideRoot("/s/state2/sub", "/s/state") == null);
    try std.testing.expect(relInsideRoot("/s", "/s/state") == null);
}

test "the mount table is read whole across reads, and a line longer than the reader's buffer yields its head and the next line" {
    var pb: [contract.max_path]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-mountinfo-{d}", .{posix.getpid()}) catch unreachable;
    defer _ = posix.unlink(path_z.ptr);

    const filler = "21 1 0:20 / /proc rw,nosuid - proc proc rw\n";
    {
        const fd = posix.open(path_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o600));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        var i: usize = 0;
        while (i < 1000) : (i += 1) try std.testing.expect(posix.write(fd, filler, filler.len) == filler.len);
        const last = "99 1 0:21 / /s/state/sub rw - tmpfs t rw";
        try std.testing.expect(posix.write(fd, last, last.len) == last.len);
    }
    {
        const fd = posix.open(path_z.ptr, posix.O_RDONLY, @as(c_uint, 0));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        var lines: MountinfoLines = .{ .fd = fd };
        var count: usize = 0;
        var last_mp: [contract.max_path]u8 = undefined;
        var last_len: usize = 0;
        while (lines.next()) |line| {
            count += 1;
            const mp = mountPointOfLine(line, &last_mp).?;
            last_len = mp.len;
        }
        try std.testing.expect(!lines.failed);
        try std.testing.expectEqual(@as(usize, 1001), count);
        try std.testing.expectEqualStrings("/s/state/sub", last_mp[0..last_len]);
    }
    {
        const fd = posix.open(path_z.ptr, posix.O_WRONLY | posix.O_TRUNC, @as(c_uint, 0));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        const head = "99 1 0:21 / /s/state/sub rw - overlay overlay rw,lowerdir=";
        try std.testing.expect(posix.write(fd, head, head.len) == head.len);
        var layers: [40 * 1024]u8 = undefined;
        @memset(&layers, 'l');
        try std.testing.expect(posix.write(fd, &layers, layers.len) == layers.len);
        const next_line = "\n42 1 0:22 / /other rw - tmpfs t rw\n";
        try std.testing.expect(posix.write(fd, next_line, next_line.len) == next_line.len);
    }
    {
        const fd = posix.open(path_z.ptr, posix.O_RDONLY, @as(c_uint, 0));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        var lines: MountinfoLines = .{ .fd = fd };
        var mp_buf: [contract.max_path]u8 = undefined;
        try std.testing.expectEqualStrings("/s/state/sub", mountPointOfLine(lines.next().?, &mp_buf).?);
        try std.testing.expectEqualStrings("/other", mountPointOfLine(lines.next().?, &mp_buf).?);
        try std.testing.expect(lines.next() == null);
        try std.testing.expect(!lines.failed);
    }
}

test "a directory under a parent without search permission is snapshotted as before, not refused" {
    if (posix.geteuid() == 0) return error.SkipZigTest; // root searches mode 0444
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-nosearch-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(base_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var db: [contract.max_path]u8 = undefined;
    const d_z = try joinZ(&db, base, "d");
    var sb: [contract.max_path]u8 = undefined;
    const sub_z = try joinZ(&sb, base, "d/sub");
    try std.testing.expect(posix.mkdir(d_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(sub_z.ptr, 0o755) == 0);
    try std.testing.expectEqual(@as(c_int, 0), std.c.chmod(d_z.ptr, 0o444));
    defer {
        _ = std.c.chmod(d_z.ptr, 0o755);
        _ = posix.rmdir(sub_z.ptr);
        _ = posix.rmdir(d_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    var snap = try takeSnapshot(std.testing.allocator, base);
    defer snap.deinit();
    try std.testing.expectEqual(@as(usize, 2), snap.entries.items.len);
    try std.testing.expectEqualStrings("d/sub", snap.entries.items[1].rel);
}

test "an ordinary tree has nothing on another device below its root" {
    var pb: [contract.max_path]u8 = undefined;
    const base_z = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-devscan-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base_z.ptr, 0o755);
    var base_buf: [contract.max_path]u8 = undefined;
    const base = std.mem.span(posix.realpath(base_z.ptr, &base_buf) orelse return error.SkipZigTest);
    var ab: [contract.max_path]u8 = undefined;
    const a_z = try joinZ(&ab, base, "a");
    var bb: [contract.max_path]u8 = undefined;
    const b_z = try joinZ(&bb, base, "a/b");
    try std.testing.expect(posix.mkdir(a_z.ptr, 0o755) == 0);
    try std.testing.expect(posix.mkdir(b_z.ptr, 0o755) == 0);
    defer {
        _ = posix.rmdir(b_z.ptr);
        _ = posix.rmdir(a_z.ptr);
        _ = posix.rmdir(base_z.ptr);
    }
    var rel: EntryRel = .{};
    try std.testing.expectEqual(MountScan.none, deviceScan(base, &rel));
    try std.testing.expectEqual(@as(usize, 0), rel.get().len);
}
