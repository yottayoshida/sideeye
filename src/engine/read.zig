//! One whole file into an arena, with the flags and the classification a file the
//! engine did not name has to carry (#400, #489).
//!
//! Shared by the snapshot walk, which reads the target's tree and follows a link at the
//! name because the walk classified it first, and by the trace read, which reads the
//! engine's own artefact and refuses one. Neither owns it, so it lives beside both rather
//! than inside either — putting it in `engine.zig` and importing it from `trace.zig` would
//! have been a cycle, which #491 names as the point to stop (ADR 0047).

const std = @import("std");
const posix = @import("../posix.zig");

const Allocator = std.mem.Allocator;

/// What reading one whole file can answer, which is a subset of what walking a tree can
/// (#376). `readWhole` is the leaf both readers share; it opens, checks the kind, and
/// reads to EOF, so depth, classification, path length and the tree ceiling are not its
/// to raise. Widening this into `SnapshotError` at the walk's call site costs nothing —
/// Zig accepts the narrower set where the wider one is declared.
pub const ReadWholeError = error{ OutOfMemory, ReadFailed, FileTooLarge };

/// Whether `readWhole` may follow a symlink at the final component (#489).
///
/// The caller's to choose, because `readWhole`'s two callers read files with different
/// owners. The trace is the engine's own: the shim writes it refusing a link since #488, so
/// meeting one on the way back in can only be somebody else's substitution, and the bytes
/// decide a verdict — that read passes `.refuse`. The snapshot walk's `.file` arm reads the
/// *target's* tree, where a link at a name is ordinary and first-class (#122); the walk
/// classifies with `kindFromDirent` before it gets here, so that read meets a link only
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

/// The cap is a parameter for the same reason readLinkTarget's buffer is one: against
/// the production constant a test would need a 64 MiB fixture to see the refusal fire,
/// so the boundary would be a claim nobody falsifies — against a small cap the tests
/// below fire it for real. `size_out`, when given, receives the file's size from
/// lseek(SEEK_END) at the moment the cap breaks (null if even that fails): the
/// refusal that names the file wants to name its size, and the read loop stopped
/// before it could know. `links` is documented on `LinkPolicy` above.
pub fn readWhole(arena: Allocator, path: [*:0]const u8, max: usize, size_out: ?*?u64, links: LinkPolicy) ReadWholeError![]const u8 {
    const flags: c_int = posix.O_RDONLY | posix.O_NONBLOCK |
        @as(c_int, switch (links) {
            .follow => 0,
            .refuse => posix.O_NOFOLLOW,
        });
    const fd = posix.open(path, flags, @as(c_uint, 0));
    if (fd < 0) return error.ReadFailed;
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
    //
    // `ArenaAllocator` never frees, and its resize fast path only extends the allocation
    // sitting at the end of the current node — so a doubling list that outgrows its node
    // is copied into a new one (sized 1.5x its predecessor) and the old copy is stranded
    // there for the life of the snapshot. Measured before this: one 64 MiB file left the
    // arena holding 113,780,014 bytes, and — because where the growth falls relative to a
    // node boundary decides how much is stranded — the cost was not even monotonic in the
    // tree, with two 32 MiB files costing more than two 64 MiB ones. A ceiling read off
    // the arena inherits both, and "a tree that fits and a bigger tree that does not"
    // stops being a property an operator can predict. After: 100,663,448 for the same
    // file, a flat 1.50x that is the arena's node growth factor and nothing else.
    //
    // Reserved exactly, never `max + chunk` on a small file: over-reserving 64 KiB per
    // entry is the shape a state tree of many small files is made of.
    const reserve_from = posix.lseek(fd, 0, posix.SEEK_END);
    if (reserve_from > 0) {
        if (posix.lseek(fd, 0, posix.SEEK_SET) < 0) return error.ReadFailed;
        const len: usize = @intCast(reserve_from);
        // Past the cap the read stops one chunk over it, so that is all it can need.
        //
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
        if (n < 0) return error.ReadFailed;
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
    // Aimed at the guard's own predicate rather than at the accident that motivated it.
    // A FIFO would prove nothing here: this function ignores a failed `lseek` by design
    // (the reservation below is optional), so a FIFO reaches the read loop and stops at
    // its immediate EOF whether or not the classification runs — which is the same empty
    // success the guard exists to prevent, arriving by a different door.
    //
    // `/dev/zero` is the separating input. Measured: S_IFCHR, both `lseek`s succeed
    // returning 0, and `read` yields bytes without end. With the classification deleted
    // this call therefore runs the loop to `max` and answers `FileTooLarge` — a refusal
    // that names a size problem for a character device.
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    // That the device exists and answers what this test assumes, before relying on it:
    // `error.ReadFailed` is also what a failed open returns from this function, so on a
    // host without `/dev/zero` the assertion below would pass while measuring nothing.
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
