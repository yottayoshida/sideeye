const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");

pub fn writeWholeFile(path: []const u8, parts: []const []const u8) bool {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return false;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    if (fd < 0) return false;
    defer _ = posix.close(fd);
    for (parts) |p| if (!writeAll(fd, p)) return false;
    return true;
}

fn writeAll(fd: c_int, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const w = posix.write(fd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return false;
        off += @intCast(w);
    }
    return true;
}

/// ADR 0101) and then executes the path, so the file has to be one this call made: `O_EXCL`
/// refuses anything already there — a symlink included, dangling or not, which is POSIX's
/// rule for `O_CREAT|O_EXCL` — and `O_NOFOLLOW` keeps that refusal from resting on `O_EXCL`
/// alone, as #469 did for the captures; the test below cannot tell the two apart and does
/// not claim to. The mode is set at creation — there is no moment where the path the demo
/// is about to run exists with looser bits than it ends with, which a create-then-`chmod`
/// would have. A short write unlinks what it wrote: a truncated executable is worse than
/// none, and the caller reports the failure either way.
pub fn writeNewExecutable(path: []const u8, bytes: []const u8) bool {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return false;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0o700));
    if (fd < 0) return false;
    if (!writeAll(fd, bytes)) {
        _ = posix.close(fd);
        _ = posix.unlink(z.ptr);
        return false;
    }
    // Closed before anyone executes it: on Linux an image still open for writing refuses
    // to run (ETXTBSY).
    if (posix.close(fd) != 0) {
        _ = posix.unlink(z.ptr);
        return false;
    }
    return true;
}

test "writeNewExecutable makes the file it runs, and nothing it did not make (#715)" {
    var pb: [96]u8 = undefined;
    const base = try std.fmt.bufPrint(&pb, "/tmp/sideeye-newexec-{d}", .{posix.getpid()});
    var b1: [128]u8 = undefined;
    var b2: [128]u8 = undefined;
    const made = try std.fmt.bufPrintZ(&b1, "{s}-made", .{base});
    const link = try std.fmt.bufPrintZ(&b2, "{s}-link", .{base});
    _ = posix.unlink(made.ptr);
    _ = posix.unlink(link.ptr);
    defer _ = posix.unlink(made.ptr);
    defer _ = posix.unlink(link.ptr);

    try std.testing.expect(writeNewExecutable(made, "#!/bin/sh\nexit 0\n"));
    try std.testing.expectEqual(@as(c_int, 0), posix.access(made.ptr, posix.X_OK));
    {
        const fd = posix.open(made.ptr, posix.O_RDONLY, @as(c_uint, 0));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        var rb: [64]u8 = undefined;
        const n = posix.read(fd, &rb, rb.len);
        try std.testing.expectEqualStrings("#!/bin/sh\nexit 0\n", rb[0..@intCast(n)]);
    }
    try std.testing.expect(!writeNewExecutable(made, "x"));
    if (posix.symlink(made.ptr, link.ptr) != 0) return error.SkipZigTest;
    try std.testing.expect(!writeNewExecutable(link, "y"));
}

pub fn removeFile(path: []const u8) void {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = posix.unlink(z.ptr);
}
