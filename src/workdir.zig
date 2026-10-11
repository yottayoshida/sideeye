const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");
const defang = @import("defang.zig");

/// Held until the process exits; children do not inherit it.
pub var lock_fd: c_int = -1;

pub const Refusal = struct { reason: contract.SetupErrorReason, text: []const u8 };

/// Refused, not waited for: a run stuck in its setup would otherwise stop the next one
/// without a word. A filesystem without locks goes on as before.
pub fn lock(arena: std.mem.Allocator, work: []const u8) ?Refusal {
    const shown = defang.textShown(arena, work);
    var path_buf: [contract.max_path]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "{s}/run.lock", .{work}) catch
        return .{ .reason = .define_invalid, .text = "--work is too long" };
    const flags = posix.O_RDWR | posix.O_NOFOLLOW | posix.O_CLOEXEC | posix.O_NONBLOCK;
    // Not asked who owns a file this run just made: a filesystem that squashes the owner would
    // refuse every run.
    var made = true;
    var fd = posix.open(path.ptr, flags | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o600));
    if (fd < 0 and std.c._errno().* == posix.EEXIST) {
        made = false;
        fd = posix.open(path.ptr, flags, @as(c_uint, 0));
    }
    if (fd < 0) {
        const e = std.c._errno().*;
        return refusal(arena, "--work {s}: its lock file run.lock could not be opened (errno {d})", .{ shown, e });
    }
    if (!posix.isSoleRegularFile(fd, !made)) {
        _ = posix.close(fd);
        return refusal(arena, "--work {s}: run.lock is not a regular file of yours with one link, and Sideeye writes its pid into it. Remove it", .{shown});
    }
    if (posix.flock(fd, posix.LOCK_EX | posix.LOCK_NB) != 0) {
        const e = std.c._errno().*;
        if (e == posix.ENOLCK or e == posix.EOPNOTSUPP or e == posix.EBADF) {
            _ = posix.close(fd);
            return null;
        }
        if (e == posix.EAGAIN) {
            var pid_buf: [32]u8 = undefined;
            const n = posix.read(fd, &pid_buf, pid_buf.len);
            _ = posix.close(fd);
            const written = if (n > 0) std.mem.trim(u8, pid_buf[0..@intCast(n)], " \n") else "";
            // Do not name a pid that has exited: the holder may not have written its own yet.
            const alive = if (std.fmt.parseInt(i32, written, 10)) |pid| pid > 0 and (posix.kill(pid, 0) == 0 or std.c._errno().* == posix.EPERM) else |_| false;
            const holder = if (alive) written else "unknown";
            return refusal(arena, "--work {s} is in use by another sideeye run (pid {s}): two runs in one work directory read each other's traces and reports. Give each run its own --work", .{ shown, holder });
        }
        _ = posix.close(fd);
        return refusal(arena, "--work {s}: its lock file run.lock could not be locked (errno {d})", .{ shown, e });
    }
    _ = posix.ftruncate(fd, 0);
    var pid_txt: [32]u8 = undefined;
    const t = std.fmt.bufPrint(&pid_txt, "{d}\n", .{posix.getpid()}) catch unreachable;
    _ = posix.write(fd, t.ptr, t.len);
    lock_fd = fd;
    return null;
}

fn refusal(arena: std.mem.Allocator, comptime fmt: []const u8, args: anytype) Refusal {
    return .{ .reason = .environment, .text = std.fmt.allocPrint(arena, fmt, args) catch fmt };
}

test "a work directory another holder has locked is refused naming its pid, and one nobody holds is taken (#816)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var db: [contract.max_path]u8 = undefined;
    const dir = std.fmt.bufPrint(&db, "/tmp/sideeye-workdir-lock-{d}", .{posix.getpid()}) catch unreachable;
    var dzb: [contract.max_path]u8 = undefined;
    const dir_z = std.fmt.bufPrintZ(&dzb, "{s}", .{dir}) catch unreachable;
    var lb: [contract.max_path]u8 = undefined;
    const lock_z = std.fmt.bufPrintZ(&lb, "{s}/run.lock", .{dir}) catch unreachable;
    _ = posix.mkdir(dir_z.ptr, 0o755);
    const saved = lock_fd;
    defer {
        if (lock_fd >= 0 and lock_fd != saved) _ = posix.close(lock_fd);
        lock_fd = saved;
        _ = posix.unlink(lock_z.ptr);
        _ = posix.rmdir(dir_z.ptr);
    }

    try std.testing.expect(lock(arena, dir) == null);
    try std.testing.expect(lock_fd >= 0);
    const first = lock_fd;
    lock_fd = -1;
    const r = lock(arena, dir) orelse return error.TestUnexpectedResult;
    lock_fd = first;
    var want_buf: [64]u8 = undefined;
    const want = std.fmt.bufPrint(&want_buf, "(pid {d})", .{posix.getpid()}) catch unreachable;
    try std.testing.expect(std.mem.indexOf(u8, r.text, "is in use by another sideeye run") != null);
    try std.testing.expect(std.mem.indexOf(u8, r.text, want) != null);
}
