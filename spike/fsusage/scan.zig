//! Run the shipped reader over a real capture and say what it rejects, and why.
//!
//! It calls `fsusage.read` itself rather than restating the grammar: a diagnostic that
//! reimplements the thing it measures reports on the copy. Built ad hoc, not wired into
//! `zig build` — it exists to turn "which lines would refuse?" from a guess into a
//! count while the rules are still being set.
//!
//!   zig run spike/fsusage/scan.zig --dep contract -Mcontract=src/contract.zig \
//!       --dep fsusage -Mroot=spike/fsusage/scan.zig -Mfsusage=src/fsusage.zig -lc -- ...

const std = @import("std");
const fsusage = @import("fsusage");
const posix = @import("posix");

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa = gpa_state.allocator();
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try init.args.toSlice(arena);
    if (args.len < 6) {
        std.debug.print("usage: scan <capture> <state-root> <trace> <sentinel-open> <sentinel-close>\n", .{});
        std.process.exit(2);
    }

    var zb: [4096]u8 = undefined;
    const z = try std.fmt.bufPrintZ(&zb, "{s}", .{args[1]});
    const fd = posix.open(z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    if (fd < 0) { std.debug.print("cannot open {s}\n", .{args[1]}); std.process.exit(2); }
    defer _ = posix.close(fd);
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n <= 0) break;
        try list.appendSlice(arena, chunk[0..@intCast(n)]);
    }
    const text = list.items;

    const r = try fsusage.read(arena, text, args[2], "", args[3], args[4], args[5]);

    std.debug.print("lines_seen={d} in_scope={d} classes={d} child_touched={} children={d} subject_tid={s}\n", .{
        r.parsed.lines_seen,
        r.parsed.lines_in_scope,
        r.parsed.classes.items.len,
        r.parsed.child_touched,
        r.parsed.children,
        r.subject_tid orelse "(none)",
    });
    if (r.defect) |d| switch (d) {
        .unparsed => |l| std.debug.print("DEFECT unparsed: {s}\n", .{l}),
        .truncated => |l| std.debug.print("DEFECT truncated: {s}\n", .{l}),
        .unresolved_fd => |l| std.debug.print("DEFECT unresolved_fd: {s}\n", .{l}),
        .unknown_call => |l| std.debug.print("DEFECT unknown_call: {s}\n", .{l}),
        .no_subject => std.debug.print("DEFECT no_subject\n", .{}),
        .missing_sentinel => |p| std.debug.print("DEFECT missing_sentinel: {s}\n", .{p}),
    } else std.debug.print("no defect\n", .{});
}
