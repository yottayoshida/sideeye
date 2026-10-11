const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");

const setup_capture_cap: usize = 1024 * 1024;

pub fn lastNonEmptyLine(text: []const u8) []const u8 {
    var it = std.mem.splitBackwardsScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len > 0) return line;
    }
    return "";
}

/// `unreadable` and `empty` stay apart. A file that cannot be opened is not an empty one:
/// the refusal must not assert something about a file it failed to read, and the success
/// path must not delete the only copy of an output the engine could not see. A capture
pub const SetupCapture = union(enum) { unreadable, empty, line: []const u8 };

pub fn readSetupCapture(arena: std.mem.Allocator, path: []const u8) SetupCapture {
    const text = readFileAllocCapped(arena, path, setup_capture_cap, .{
        .require_regular = true,
        .no_follow = true,
    }) orelse return .unreadable;
    const line = lastNonEmptyLine(text);
    return if (line.len == 0) .empty else .{ .line = line };
}

test "lastNonEmptyLine takes the last line that has something on it (#483)" {
    const t = std.testing;
    try t.expectEqualStrings("boom", lastNonEmptyLine("boom"));
    try t.expectEqualStrings("boom", lastNonEmptyLine("boom\n"));
    try t.expectEqualStrings("second", lastNonEmptyLine("first\nsecond\n"));
    try t.expectEqualStrings("why it failed", lastNonEmptyLine("noise\nwhy it failed\n\n\n"));
    try t.expectEqualStrings("why it failed", lastNonEmptyLine("noise\nwhy it failed\n   \n"));
    try t.expectEqualStrings("crlf", lastNonEmptyLine("crlf\r\n"));
    try t.expectEqualStrings("", lastNonEmptyLine(""));
    try t.expectEqualStrings("", lastNonEmptyLine("\n\n"));
    try t.expectEqualStrings("", lastNonEmptyLine("   \n\t\n"));
}

/// **This number is pinned between three constants in another file and nothing checks
/// the coupling**, so the inequality is written here rather than left to be rediscovered.
/// `spike/case-path-deadline.py` carries `WRITER_DELAY = 1.0` (how late its writer
/// opens), `min_s = 1.5` on the two deadline legs (the floor they assert this wait
/// against), and `DEADLINE = 5.0` (when it kills sideeye). **`min_s` is the binding
/// lower bound, not `WRITER_DELAY`** — measured: 1200 ms satisfies "above 1.0, below
/// 5.0" and still fails both legs at 1.21 s. So: `min_s < this << DEADLINE`. Move any of
/// the three and this has to move with them.
const config_read_deadline_ms: u64 = 2000;

const config_read_poll_ms: u64 = 10;

pub const Appended = struct { text: []const u8, end: u64 };

pub fn readFileFrom(arena: std.mem.Allocator, path: []const u8, from: u64, max: usize) ?Appended {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    // `O_NOFOLLOW` for the reason `observeCapture` has it (#469): the one production
    // caller reads the fs_usage capture out of the work directory, a file `spawnSidecar`
    // created refusing links, and reading it back *through* one would let somebody else
    // choose the bytes that decide whether the observer is covering the path.
    const fd = posix.open(z.ptr, posix.O_RDONLY | posix.O_NONBLOCK | posix.O_NOFOLLOW, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    // The `lseek` below already refuses a FIFO with ESPIPE, and that is not the reason
    // this is here: seekability and regular-file-ness are different properties, and the
    // day someone reaches the bytes another way the `lseek` stops being the guard
    // without anything saying so (#400).
    if ((posix.kindOfFd(fd) catch return null) != .file) return null;
    const size = posix.lseek(fd, 0, posix.SEEK_END);
    if (size < 0) return null;
    const usize_size: u64 = @intCast(size);
    if (usize_size <= from) return .{ .text = "", .end = from };
    if (posix.lseek(fd, @intCast(from), posix.SEEK_SET) < 0) return null;
    const want: usize = @intCast(@min(usize_size - from, @as(u64, max)));
    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (list.items.len < want) {
        const room = @min(chunk.len, want - list.items.len);
        const got = posix.read(fd, &chunk, room);
        if (got < 0) return null; // a read error is not end of file
        if (got == 0) break;
        list.appendSlice(arena, chunk[0..@intCast(got)]) catch return null;
    }
    const text = list.items;
    const nl = std.mem.lastIndexOfScalar(u8, text, '\n') orelse return .{ .text = "", .end = from };
    return .{ .text = text[0 .. nl + 1], .end = from + nl + 1 };
}

/// The scan and the fingerprint deliberately come from one read of the same bytes: two
/// observations of the capture disagreeing is the quiescence refusal (#46), and a marker
/// verdict taken from different bytes than the fingerprint would let the two claims
/// drift. The read is bounded by the size measured at open — a still-live writer must
/// not be able to keep the observer chasing EOF — so growth surfaces as the *next*
/// observation's differing fingerprint, never as a hang. The digest is Blake3 rather
/// than a cheap mix because the bytes are target-chosen: a same-length rewrite must not
/// be able to keep the fingerprint. An unreadable capture is an error, never "absent":
/// absence decides whether L1 applies to a world, and an I/O failure silently read as
/// absence would skip the invariant on the PASS side.
pub const CaptureObservation = struct {
    measured: u64,
    bytes: u64,
    digest: [std.crypto.hash.Blake3.digest_length]u8,
    marker_seen: bool,

    pub fn fingerprintEql(a: CaptureObservation, b: CaptureObservation) bool {
        return a.measured == b.measured and a.bytes == b.bytes and std.mem.eql(u8, &a.digest, &b.digest);
    }

    pub fn sawTruncation(a: CaptureObservation) bool {
        return a.bytes < a.measured;
    }
};

pub fn observeCapture(path: []const u8, needle: ?[]const u8) error{Unreadable}!CaptureObservation {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch return error.Unreadable;
    // `O_NOFOLLOW` for the reason the write side has it (#469): the same file, the same
    // threat, and until this line the two answered a planted link differently. The
    // capture is written refusing to follow a symlink and was read *through* one — so
    // whoever could reach the work directory chose the bytes the marker scan and the
    // capture fingerprint are computed from, which is a wrong verdict rather than a
    // failed run.
    //
    // **Symlinks only.** A hard link swapped in between the write and this read is the
    // same inode by definition and is not detectable here; closing that needs the read
    // to use the descriptor the write already held, which is a larger change than this
    // one flag.
    const fd = posix.open(z.ptr, posix.O_RDONLY | posix.O_NONBLOCK | posix.O_NOFOLLOW, @as(c_uint, 0));
    if (fd < 0) return error.Unreadable;
    defer _ = posix.close(fd);
    // Same reasoning as `readFileFrom`: the `lseek` refuses a FIFO today, but what this
    // path needs is that the capture is an ordinary file, which is a different sentence
    // (#400).
    if ((posix.kindOfFd(fd) catch return error.Unreadable) != .file) return error.Unreadable;
    const end = posix.lseek(fd, 0, posix.SEEK_END);
    if (end < 0) return error.Unreadable;
    if (posix.lseek(fd, 0, posix.SEEK_SET) != 0) return error.Unreadable;
    const bound: u64 = @intCast(end);

    var buf: [64 * 1024]u8 = undefined;
    const nlen: usize = if (needle) |n| n.len else 0;
    if (nlen >= buf.len) return error.Unreadable;
    var hasher = std.crypto.hash.Blake3.init(.{});
    var seen = false;
    var kept: usize = 0;
    var total: u64 = 0;
    while (total < bound) {
        const room: u64 = @intCast(buf.len - kept);
        const want: usize = @intCast(@min(room, bound - total));
        const nr = posix.read(fd, buf[kept..].ptr, want);
        if (nr < 0) {
            if (std.c._errno().* == posix.EINTR) continue;
            return error.Unreadable;
        }
        if (nr == 0) break;
        const fresh: usize = @intCast(nr);
        hasher.update(buf[kept .. kept + fresh]);
        total += fresh;
        const have = kept + fresh;
        if (needle) |n| {
            if (n.len > 0 and std.mem.indexOf(u8, buf[0..have], n) != null) seen = true;
        }
        kept = if (nlen == 0) 0 else @min(nlen - 1, have);
        std.mem.copyForwards(u8, buf[0..kept], buf[have - kept .. have]);
    }
    var out: CaptureObservation = .{ .measured = bound, .bytes = total, .digest = undefined, .marker_seen = seen };
    hasher.final(&out.digest);
    return out;
}

test "the readers ask what the descriptor is before reading it, at every call site (#400)" {
    // The flag's own wiring cannot be tested here for the same reason: it only shows
    // itself when there is no writer, and that is the hang. `spike/case-path-deadline.py`
    // measures it from outside the process, at the one call site the CLI reaches.
    var bb: [128]u8 = undefined;
    const base = std.fmt.bufPrintZ(&bb, ".zig-cache/tmp-fifo400-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base.ptr, @as(c_uint, 0o755));
    var fb: [160]u8 = undefined;
    const fifo_z = std.fmt.bufPrintZ(&fb, "{s}/pipe", .{base}) catch unreachable;
    _ = posix.unlink(fifo_z.ptr);
    try std.testing.expect(posix.mkfifo(fifo_z.ptr, @as(c_uint, 0o644)) == 0);

    // Reader first: the write end of a FIFO with no reader fails ENXIO.
    const rfd = posix.open(fifo_z.ptr, posix.O_RDONLY | posix.O_NONBLOCK, @as(c_uint, 0));
    try std.testing.expect(rfd >= 0);
    defer _ = posix.close(rfd);
    const wfd = posix.open(fifo_z.ptr, posix.O_WRONLY, @as(c_uint, 0));
    try std.testing.expect(wfd >= 0);
    defer _ = posix.close(wfd);
    const payload = "{\"schema\":\"sideeye/case\"}\n";
    try std.testing.expect(posix.write(wfd, payload.ptr, payload.len) == @as(isize, @intCast(payload.len)));

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const fifo_path = std.mem.span(@as([*:0]const u8, fifo_z.ptr));

    // **This first assertion does not measure the classification, and saying so is the
    // point.** `readFileAllocCapped` reads in a loop and returns one bit, so a
    // non-regular descriptor, an unreadable one and a file over the cap all arrive as
    // `null`: with the guard deleted the FIFO's payload is read and then the next read
    // fails EAGAIN, which is `null` again. Measured — that mutation survives this line.
    // What kills it is `spike/case-path-deadline.py`, from outside the process, where
    // the refusal *message* separates "could not be read" from "could not be parsed".
    // The line stays because it pins the behaviour; it is not evidence of wiring.
    try std.testing.expect(readFileAllocCapped(arena, fifo_path, 1024 * 1024, .{ .require_regular = true }) == null);
    try std.testing.expect(readFileFrom(arena, fifo_path, 0, 64 * 1024) == null);
    try std.testing.expectError(error.Unreadable, observeCapture(fifo_path, null));

    const devzero = "/dev/zero";
    var dzb: [16]u8 = undefined;
    const dz_z = std.fmt.bufPrintZ(&dzb, "{s}", .{devzero}) catch unreachable;
    const dzfd = posix.open(dz_z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    try std.testing.expect(dzfd >= 0);
    try std.testing.expectEqual(posix.Kind.other, try posix.kindOfFd(dzfd));
    _ = posix.close(dzfd);

    try std.testing.expect(readFileFrom(arena, devzero, 0, 64 * 1024) == null);
    try std.testing.expectError(error.Unreadable, observeCapture(devzero, null));

    var rb: [160]u8 = undefined;
    const reg_z = std.fmt.bufPrintZ(&rb, "{s}/f", .{base}) catch unreachable;
    const ofd = posix.open(reg_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(ofd >= 0);
    try std.testing.expect(posix.write(ofd, payload.ptr, payload.len) == @as(isize, @intCast(payload.len)));
    _ = posix.close(ofd);
    const reg_path = std.mem.span(@as([*:0]const u8, reg_z.ptr));

    try std.testing.expect(readFileAllocCapped(arena, reg_path, 1024 * 1024, .{ .require_regular = true }) != null);
    try std.testing.expect(readFileFrom(arena, reg_path, 0, 64 * 1024) != null);
    _ = try observeCapture(reg_path, null);

    try std.testing.expect(readFileAllocCapped(arena, reg_path, 1024 * 1024, .{}) != null);

    _ = posix.unlink(fifo_z.ptr);
    _ = posix.unlink(reg_z.ptr);
    _ = posix.rmdir(base.ptr);
}

test "the work-directory readers refuse a symlink; the operator-named ones still follow one (#469)" {
    var pb: [160]u8 = undefined;
    const base = std.fmt.bufPrintZ(&pb, "/tmp/sideeye-nofollow-read-{d}", .{posix.getpid()}) catch unreachable;
    _ = posix.mkdir(base.ptr, 0o755);
    var tb: [200]u8 = undefined;
    const target_z = std.fmt.bufPrintZ(&tb, "{s}/real", .{base}) catch unreachable;
    var lb: [200]u8 = undefined;
    const link_z = std.fmt.bufPrintZ(&lb, "{s}/link", .{base}) catch unreachable;
    defer {
        _ = posix.unlink(link_z.ptr);
        _ = posix.unlink(target_z.ptr);
        _ = posix.rmdir(base.ptr);
    }

    const fd = posix.open(target_z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    try std.testing.expect(posix.write(fd, "contents", 8) == 8);
    _ = posix.close(fd);
    try std.testing.expect(posix.symlink(target_z.ptr, link_z.ptr) == 0);

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const link = std.mem.span(link_z.ptr);
    const real = std.mem.span(target_z.ptr);

    try std.testing.expectEqualStrings("contents", readFileAllocCapped(arena, link, 4096, .{}).?);
    try std.testing.expect(readFileAllocCapped(arena, link, 4096, .{ .no_follow = true }) == null);

    try std.testing.expectEqualStrings("contents", readFileAllocCapped(arena, real, 4096, .{ .no_follow = true }).?);

    try std.testing.expect(readFileAlloc(arena, link) == null);
    try std.testing.expectEqualStrings("contents", readFileAlloc(arena, real).?);
}

test "observeCapture finds a straddling marker and fingerprints the same bytes" {
    // pid-unique name: `zig build test` runs this file in several concurrent binaries,
    // and a fixed shared path passes alone then flakes under pairing (#28).
    var pb: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-observecapture-{d}.txt", .{posix.getpid()}) catch unreachable;
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch unreachable;
    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    // 64 KiB of padding minus half the marker, so MARKER spans the read boundary.
    var pad: [64 * 1024 - 3]u8 = undefined;
    @memset(&pad, 'x');
    try std.testing.expect(posix.write(fd, &pad, pad.len) == pad.len);
    try std.testing.expect(posix.write(fd, "MARKER", 6) == 6);
    _ = posix.close(fd);
    defer _ = posix.unlink(z.ptr);

    const with = try observeCapture(path, "MARKER");
    try std.testing.expect(with.marker_seen);
    try std.testing.expectEqual(@as(u64, 64 * 1024 + 3), with.bytes);
    const without = try observeCapture(path, "ABSENT");
    try std.testing.expect(!without.marker_seen);
    try std.testing.expect(with.fingerprintEql(without));
    const unasked = try observeCapture(path, null);
    try std.testing.expect(with.fingerprintEql(unasked));

    const afd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT, @as(c_uint, 0o644));
    try std.testing.expect(afd >= 0);
    try std.testing.expect(posix.lseek(afd, 0, posix.SEEK_END) >= 0);
    try std.testing.expect(posix.write(afd, "y", 1) == 1);
    _ = posix.close(afd);
    const grown = try observeCapture(path, null);
    try std.testing.expect(!with.fingerprintEql(grown));

    try std.testing.expectError(error.Unreadable, observeCapture(".zig-cache/no-such-capture", "X"));
}

test "observeCapture separates same-length rewrites by digest alone" {
    var pb: [128]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-observecapture-rw-{d}.txt", .{posix.getpid()}) catch unreachable;
    var zb: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&zb, "{s}", .{path}) catch unreachable;
    defer _ = posix.unlink(z.ptr);

    for ([_][]const u8{ "AAAA", "AAAB" }, 0..) |content, i| {
        const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(fd >= 0);
        try std.testing.expect(posix.write(fd, content.ptr, content.len) == @as(isize, @intCast(content.len)));
        _ = posix.close(fd);
        if (i == 0) continue;
        const b = try observeCapture(path, null);
        const afd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
        try std.testing.expect(afd >= 0);
        try std.testing.expect(posix.write(afd, "AAAA", 4) == 4);
        _ = posix.close(afd);
        const a = try observeCapture(path, null);
        try std.testing.expectEqual(a.bytes, b.bytes);
        try std.testing.expect(!a.fingerprintEql(b));
    }

    const fd = posix.open(z.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_TRUNC, @as(c_uint, 0o644));
    try std.testing.expect(fd >= 0);
    _ = posix.close(fd);
    const empty = try observeCapture(path, "M");
    try std.testing.expectEqual(@as(u64, 0), empty.bytes);
    try std.testing.expectEqual(@as(u64, 0), empty.measured);
    try std.testing.expect(!empty.marker_seen);
    try std.testing.expect(!empty.sawTruncation());
}

test "a shrink observed inside one sample is its own evidence, not the next comparison's luck" {
    const digest = [_]u8{7} ** std.crypto.hash.Blake3.digest_length;
    const during = CaptureObservation{ .measured = 10, .bytes = 4, .digest = digest, .marker_seen = false };
    const honest = CaptureObservation{ .measured = 4, .bytes = 4, .digest = digest, .marker_seen = false };
    try std.testing.expect(during.sawTruncation());
    try std.testing.expect(!honest.sawTruncation());
    try std.testing.expect(!during.fingerprintEql(honest));
}

pub const ReadMode = struct {
    require_regular: bool = false,
    bounded: bool = false,
    no_follow: bool = false,
};

/// **That sentence was written for a hazard the cap cannot reach, which is #400.** A
/// FIFO does not hang the read the cap guards — it hangs the `open` in front of it, and
/// the loop is never entered to be capped. So the open takes `O_NONBLOCK` where either
/// mode asks for it. That alone then buys a second defect: past the open, a FIFO with no
/// writer returns 0 from the first read, so the file arrives *empty* and successful.
/// half. `--config` is operator-named and may legitimately be a pipe (`--config
/// /dev/stdin`, a process substitution), so refusing by kind would break spellings that
/// work today. What it can do is refuse to wait forever: keep asking while a peer might
pub fn readFileAllocCapped(
    arena: std.mem.Allocator,
    path: []const u8,
    cap: usize,
    mode: ReadMode,
) ?[]const u8 {
    var buf: [contract.max_path]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{path}) catch return null;
    // Both modes need the open to return, for different reasons: classification has to
    // get a descriptor before it can ask what it is, and the bounded read needs `EAGAIN`
    // where a blocking read would sit somewhere the deadline cannot see. Plain readers
    // keep the blocking open they had — the flag is not free, and a non-blocking read of
    // a pipe whose writer has not written yet fails where waiting would have succeeded.
    const base: c_int = if (mode.require_regular or mode.bounded)
        posix.O_RDONLY | posix.O_NONBLOCK
    else
        posix.O_RDONLY;
    const flags: c_int = if (mode.no_follow) base | posix.O_NOFOLLOW else base;
    const fd = posix.open(z.ptr, flags, @as(c_uint, 0));
    if (fd < 0) return null;
    defer _ = posix.close(fd);
    if (mode.require_regular) {
        // Asked of the descriptor rather than of the name. A name classified before the
        // open can change kind before the read, and the probe that classified names by
        // opening them is what #5 retired — for hanging on exactly this input.
        const kind = posix.kindOfFd(fd) catch return null;
        if (kind != .file) return null;
    }
    const peer_may_arrive = mode.bounded and posix.isFifoFd(fd);
    const deadline_at: u64 = if (mode.bounded) posix.monotonicMs() + config_read_deadline_ms else 0;

    var list: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    var eintr_left: u32 = 8;
    while (true) {
        const n = posix.read(fd, &chunk, chunk.len);
        if (n > 0) {
            list.appendSlice(arena, chunk[0..@intCast(n)]) catch return null;
            if (list.items.len > cap) return null;
            continue;
        }

        // Everything past here is a pass that produced no bytes, and the deadline is
        // consulted **only** here. A 300 KiB regular file finishes in six reads without
        // touching this branch, so a slow disk cannot spend the budget — which is the
        // false positive that made an earlier draft reject a time bound outright.
        if (n == 0) {
            if (!peer_may_arrive or list.items.len != 0) break;
        } else {
            const e = std.c._errno().*;
            if (e == posix.EINTR) {
                // a first-interruption `null` into eight retries. Unreachable in
                // practice on all of them today (no handler is installed anywhere), and
                // folding an interruption into "unreadable" would be a wrong answer
                // rather than a slow one.
                if (eintr_left == 0) return null;
                eintr_left -= 1;
                continue;
            }
            if (!(mode.bounded and e == posix.EAGAIN)) return null;
        }

        if (posix.monotonicMs() >= deadline_at) return null;
        posix.sleepForMs(config_read_poll_ms);
    }
    return list.items;
}

pub fn readFileAlloc(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    // A read error is not end of file (the shared loop returns null for it): treating
    // them alike once turned a truncated oracle file into a complete one, and the
    // comparison that followed was against however much happened to arrive.
    return readFileAllocCapped(arena, path, std.math.maxInt(usize), .{ .no_follow = true });
}
