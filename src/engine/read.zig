const std = @import("std");
const contract = @import("contract");
const posix = @import("../posix.zig");

const Allocator = std.mem.Allocator;

pub const ReadWholeError = error{ OutOfMemory, ReadFailed, FileTooLarge };

/// through the window between the classification and the open. **Closing that window changes
/// what a snapshot refuses**, with its own promise and its own leg (`src/posix.zig` says so),
/// and is not something to acquire as a side effect of the trace's flag — so the walk passes
/// `.follow`.
///
/// A parameter rather than an unconditional flag for that reason, and a parameter rather than
/// a check in front of the open: asking `kindOfPathNoFollow` about the path first would put a
/// classify-to-open window into *this* read, which is the very thing the paragraph above
/// declines to inherit.
pub const LinkPolicy = enum { follow, refuse };

/// The one place errno is read for a caller (#535): the first statement after a failed
/// libc call, before anything else can run.
fn captureErrno(eo: ?*?c_int) void {
    if (eo) |p| p.* = std.c._errno().*;
}

pub fn readWhole(arena: Allocator, path: [*:0]const u8, max: usize, size_out: ?*?u64, links: LinkPolicy) ReadWholeError![]const u8 {
    return readWholeDiag(arena, path, max, size_out, links, null);
}

/// A number nobody measured must not reach a message.
pub fn readWholeDiag(arena: Allocator, path: [*:0]const u8, max: usize, size_out: ?*?u64, links: LinkPolicy, errno_out: ?*?c_int) ReadWholeError![]const u8 {
    if (errno_out) |eo| eo.* = null;
    const flags: c_int = posix.O_RDONLY | posix.O_NONBLOCK |
        @as(c_int, switch (links) {
            .follow => 0,
            .refuse => posix.O_NOFOLLOW,
        });
    const fd = posix.open(path, flags, @as(c_uint, 0));
    if (fd < 0) {
        captureErrno(errno_out);
        return error.ReadFailed;
    }
    defer _ = posix.close(fd);

    // Nothing that is not a regular file may reach the loop below (#400). The loop reads
    // to EOF, and a FIFO with no writer answers EOF on the first read — so the flag
    // above, alone, would turn a path that used to hang into one that succeeds empty.
    // For the trace this is worse than the hang it replaces: an empty read collapses to
    // an empty `TraceInfo`, which the engine reports as `no_shim_marker` — the shim
    // declared never to have run, on evidence nobody read. The failed `lseek` is not the
    // guard here, because this function deliberately ignores one (see the reservation
    // below); the walk's kind check is not it either, since `readTraceCapped` does not
    // go through the walk.
    if ((posix.kindOfFd(fd) catch return error.ReadFailed) != .file) return error.ReadFailed;

    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;

    // Ask the file how long it is and take that much at once, instead of doubling the way
    // there (#323). The size is a HINT and nothing below trusts it: the loop still reads
    // to EOF, so a file that grows keeps growing the list and one that shrinks just
    // over-reserved. What it changes is the arena.
    // Reserved exactly, never `max + chunk` on a small file: over-reserving 64 KiB per
    // entry is the shape a state tree of many small files is made of.
    const reserve_from = posix.lseek(fd, 0, posix.SEEK_END);
    if (reserve_from > 0) {
        if (posix.lseek(fd, 0, posix.SEEK_SET) < 0) {
            captureErrno(errno_out);
            return error.ReadFailed;
        }
        const len: usize = @intCast(reserve_from);
        // **A failed reservation is not an error.** The other caller of this function is
        // `readTraceCapped`, whose catch collapses everything except `FileTooLarge` into
        // an empty `TraceInfo` — which the engine reads as `no_shim_marker`. Returning
        // `OutOfMemory` from here would turn "the trace is larger than this engine will
        // read" into "the shim never initialised" whenever the reservation could not be
        // met, which is the exact relabelling the cap's own comment says is worse than
        // having no cap. Dropping it leaves the read loop to grow as it did before this
        // reservation existed, so the failure path is the one that was there already.
        list.ensureTotalCapacityPrecise(arena, if (len <= max) len else max +| chunk.len) catch {};
    }
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n < 0) {
            captureErrno(errno_out);
            return error.ReadFailed;
        }
        if (n == 0) break;
        try list.appendSlice(arena, chunk[0..@intCast(n)]);
        if (list.items.len > max) {
            if (size_out) |so| {
                const end = posix.lseek(fd, 0, posix.SEEK_END);
                so.* = if (end >= 0) @intCast(end) else null;
            }
            return error.FileTooLarge;
        }
    }
    return list.items;
}

test "readWhole classifies the descriptor before the loop, and /dev/zero is what separates that from a failed seek (#400)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const dzfd = posix.open("/dev/zero", posix.O_RDONLY, @as(c_uint, 0));
    try std.testing.expect(dzfd >= 0);
    try std.testing.expectEqual(posix.Kind.other, try posix.kindOfFd(dzfd));
    _ = posix.close(dzfd);

    try std.testing.expectError(
        error.ReadFailed,
        readWhole(arena_state.allocator(), "/dev/zero", 4096, null, .follow),
    );

    // The control. Without it a classification stuck on "refuse" — or a `kindOfFd` that
    // answered `.other` for everything — would satisfy the assertion above while
    // refusing every state file in every snapshot.
    var bb: [128]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-readwhole400-{d}", .{posix.getpid()}) catch unreachable;
    const fd = posix.open(path_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    const bytes = "abc\n";
    try std.testing.expect(posix.write(fd, bytes.ptr, bytes.len) == @as(isize, @intCast(bytes.len)));
    _ = posix.close(fd);
    const got = try readWhole(arena_state.allocator(), path_z.ptr, 4096, null, .follow);
    try std.testing.expectEqualStrings(bytes, got);
    _ = posix.unlink(path_z.ptr);
}

test "readWholeDiag: a file this user cannot open reports the open's errno; a directory reports none (#535)" {
    if (posix.geteuid() == 0) return error.SkipZigTest; // root reads mode 0000
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dbuf: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrintZ(&dbuf, "/tmp/sideeye-readdiag-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(dir.ptr, 0o755);
    var fbuf: [contract.max_path]u8 = undefined;
    const lock = std.fmt.bufPrintZ(&fbuf, "{s}/lock", .{dir}) catch unreachable;
    const fd = posix.open(lock.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o000));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    defer {
        _ = posix.unlink(lock.ptr);
        _ = posix.rmdir(dir.ptr);
    }
    var err: ?c_int = 99;
    try std.testing.expectError(error.ReadFailed, readWholeDiag(arena, lock.ptr, 4096, null, .follow, &err));
    try std.testing.expectEqual(@as(?c_int, posix.EACCES), err);
    err = 99;
    try std.testing.expectError(error.ReadFailed, readWholeDiag(arena, dir.ptr, 4096, null, .follow, &err));
    try std.testing.expectEqual(@as(?c_int, null), err);
    try std.testing.expectError(error.ReadFailed, readWhole(arena, lock.ptr, 4096, null, .follow));
}
