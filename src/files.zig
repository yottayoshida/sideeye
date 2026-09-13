//! Two file operations the orchestrator, the report and the refusals all need, kept in a
//! leaf so that none of them has to import another for them.
//!
//! `removeFile` unlinks a path given as a slice and says nothing about failure: its callers
//! remove what may not be there — a previous `--json` report, a capture nobody will read
//! again, a work file after a run. `writeWholeFile` creates or truncates a path and writes
//! the parts in order, answering false on the first failure; the demo writes its toy with
//! it and the setup-capture tests write their fixtures. Both take `contract.max_path` for
//! the NUL-terminated copy, which is why they are not in `posix.zig`: that file imports
//! `std` and `builtin` only, and these bodies spell their calls with the `posix.` qualifier
//! that a move into it would have had to strip.
//!
//! Third seam of #572 (ADR 0062): the second leaf a seam has forced (the first was
//! `defang.zig`). Bodies moved from `main.zig` byte for byte on 2026-09-13, `pub` added;
//! `main.zig`, `report.zig` and `refuse.zig` alias both names so their call sites read as
//! they did.
const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");

/// Create-or-truncate `path` and write `parts` in order. False on any failure —
/// the demo treats a half-written asset as a setup error, never as material.
pub fn writeWholeFile(path: []const u8, parts: []const []const u8) bool {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return false;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return false;
    defer _ = posix.close(fd);
    for (parts) |p| {
        var off: usize = 0;
        while (off < p.len) {
            const w = posix.write(fd, p[off..].ptr, p.len - off);
            if (w <= 0) return false;
            off += @intCast(w);
        }
    }
    return true;
}

pub fn removeFile(path: []const u8) void {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = posix.unlink(z.ptr);
}
