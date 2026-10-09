//! File operations the orchestrator, the report and the refusals all need, kept in a leaf
//! so that none of them has to import another for them.
//!
//! `removeFile` unlinks a path given as a slice and says nothing about failure: its callers
//! remove what may not be there — a previous `--json` report, a capture nobody will read
//! again, a work file after a run. `writeWholeFile` creates or truncates a path and writes
//! the parts in order, answering false on the first failure; the demo writes its checker
//! with it and the setup-capture tests write their fixtures. `writeNewExecutable` (#715) is
//! the demo's other write: its prebuilt tool, into a file the call must create. All take
//! `contract.max_path` for the NUL-terminated copy, which is why they are not in
//! `posix.zig`: that file imports `std` and `builtin` only, and these bodies spell their
//! calls with the `posix.` qualifier that a move into it would have had to strip.
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
    for (parts) |p| if (!writeAll(fd, p)) return false;
    return true;
}

/// Every byte of `bytes` to `fd`, retrying short writes; false on the first write that
/// moves nothing.
fn writeAll(fd: c_int, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const w = posix.write(fd, bytes[off..].ptr, bytes.len - off);
        if (w <= 0) return false;
        off += @intCast(w);
    }
    return true;
}

/// Create `path` as a file only its owner can read, write or run, holding `bytes`, and
/// answer whether every byte landed. The demo writes its prebuilt tool with this (#715,
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
    // Runnable by its owner as created, with no chmod after the fact.
    try std.testing.expectEqual(@as(c_int, 0), posix.access(made.ptr, posix.X_OK));
    // The bytes are the ones handed in.
    {
        const fd = posix.open(made.ptr, posix.O_RDONLY, @as(c_uint, 0));
        try std.testing.expect(fd >= 0);
        defer _ = posix.close(fd);
        var rb: [64]u8 = undefined;
        const n = posix.read(fd, &rb, rb.len);
        try std.testing.expectEqualStrings("#!/bin/sh\nexit 0\n", rb[0..@intCast(n)]);
    }
    // A second call on the same path is refused rather than writing over a file somebody
    // else may have put there — the property `O_EXCL` buys. Without it this answers true.
    try std.testing.expect(!writeNewExecutable(made, "x"));
    // A link is refused rather than followed, so the bytes do not reach its target. `O_EXCL`
    // alone already refuses here; this pins the outcome, not which flag produced it.
    if (posix.symlink(made.ptr, link.ptr) != 0) return error.SkipZigTest;
    try std.testing.expect(!writeNewExecutable(link, "y"));
}

pub fn removeFile(path: []const u8) void {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return;
    _ = posix.unlink(z.ptr);
}
