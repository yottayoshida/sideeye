//! Print one `<op> <path>` line per record in a shim trace (#344).
//!
//! Built only by `zig build -Dtrace-ops`, never shipped: it exists so
//! `spike/fsevents/survey.sh`'s L7a can ask what the shim recorded ABOUT a path rather
//! than only whether the path appears. `strings` cannot tell the two apart, and with an
//! `mmap`+`msync` mutation the distinction is the whole leg — the file has to be opened
//! before it can be mapped, so its name is in the trace either way; what must be absent
//! is any operation that would account for the bytes it now holds.
//!
//! Goes through `contract.decodeRecord`. `src/contract.zig` opens by saying there is
//! deliberately no second definition of the wire format anywhere, and a reader that
//! re-spelled the layout here would be exactly that — right until one side moved.
const std = @import("std");
const contract = @import("contract");

/// `--selftest` builds a trace in memory with `encodeRecord` and requires the walk to
/// return the ops and paths that went in. It plants an `open` and a `write` on the same
/// path on purpose: a reader that printed paths and ignored the op tag would pass a
/// test that only checked names, and that reader is precisely the one this program
/// exists to not be.
fn selfTest() !void {
    var buf: [4096]u8 = undefined;
    var n: usize = 0;
    n += try contract.encodeHeader(buf[n..]);
    n += try contract.encodeRecord(buf[n..], .{
        .op = .open, .seq = 1, .pid = 7, .path = "/tmp/a", .aux = "",
    });
    n += try contract.encodeRecord(buf[n..], .{
        .op = .write, .seq = 2, .pid = 7, .path = "/tmp/a", .aux = "",
    });
    n += try contract.encodeRecord(buf[n..], .{
        .op = .unlink, .seq = 3, .pid = 7, .path = "/tmp/b", .aux = "",
    });

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.page_allocator);
    try walk(buf[0..n], std.heap.page_allocator, &out);

    const want =
        "open /tmp/a\n" ++
        "write /tmp/a\n" ++
        "unlink /tmp/b\n";
    if (!std.mem.eql(u8, out.items, want)) {
        std.debug.print("trace-ops --selftest: got\n{s}\nwanted\n{s}\n", .{ out.items, want });
        return error.SelfTestFailed;
    }

    // A truncated trace must fail, not return a prefix. The caller reads absence as
    // evidence, so a short read that succeeds is a false negative with a success status
    // on it.
    var cut: std.ArrayList(u8) = .empty;
    defer cut.deinit(std.heap.page_allocator);
    if (walk(buf[0 .. n - 3], std.heap.page_allocator, &cut)) |_| {
        std.debug.print("trace-ops --selftest: a truncated trace walked to the end\n", .{});
        return error.SelfTestFailed;
    } else |_| {}

    // And a trace from another contract version must fail on the version, not be read
    // with today's meanings. The byte after the magic is the low byte of the u32.
    var wrong: [4096]u8 = undefined;
    @memcpy(wrong[0..n], buf[0..n]);
    wrong[contract.magic.len] +%= 1;
    var vout: std.ArrayList(u8) = .empty;
    defer vout.deinit(std.heap.page_allocator);
    if (walk(wrong[0..n], std.heap.page_allocator, &vout)) |_| {
        std.debug.print("trace-ops --selftest: a trace from another contract was read anyway\n", .{});
        return error.SelfTestFailed;
    } else |_| {}
}

/// Fails rather than stopping early, at both ends.
///
/// The header goes through `contract.decodeHeader`, which is the only function that
/// answers `VersionMismatch` — a trace written by a shim built against another contract
/// would otherwise be read with today's meanings, silently, in the very field that
/// records the version. That is the failure this whole change exists because of: v12
/// moved and the apparatus did not notice.
///
/// A record that will not decode ends the walk with an error rather than a `break`. The
/// caller's question is "does this trace carry a write for that path", and an answer of
/// "no" from a walk that stopped in the middle is a false absence — measured: truncating
/// a 1012-byte trace to 700 returned 8 of its 12 lines with a success status. A future
/// contract that adds an op class produces the same shape without any corruption, since
/// `decodeRecord` answers `BadOpClass` for a tag it does not know.
fn walk(bytes: []const u8, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    var off = try contract.decodeHeader(bytes);
    while (off < bytes.len) {
        const dec = try contract.decodeRecord(bytes[off..]);
        try out.appendSlice(gpa, @tagName(dec.rec.op));
        try out.append(gpa, ' ');
        try out.appendSlice(gpa, dec.rec.path);
        try out.append(gpa, '\n');
        off += dec.consumed;
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.args.toSlice(arena);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--selftest")) {
        try selfTest();
        std.debug.print("trace-ops --selftest: ok\n", .{});
        return;
    }
    if (args.len != 2) {
        std.debug.print("usage: trace-ops <trace.bin> | trace-ops --selftest\n", .{});
        return error.Usage;
    }

    // Read through libc rather than `std.Io`: this is apparatus, it runs on one file
    // named on the command line, and the 0.16 file API wants an `Io` instance the rest
    // of this program has no use for.
    const path_z = try arena.dupeZ(u8, args[1]);
    const fd = std.c.open(path_z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.OpenFailed;
    defer _ = std.c.close(fd);

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(arena);
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &chunk, chunk.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try bytes.appendSlice(arena, chunk[0..@intCast(n)]);
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(arena);
    try walk(bytes.items, arena, &out);

    if (out.items.len != 0) {
        const w = std.c.write(1, out.items.ptr, out.items.len);
        if (w != @as(isize, @intCast(out.items.len))) return error.WriteFailed;
    }
}
