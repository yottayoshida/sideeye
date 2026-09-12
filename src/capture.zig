//! The capture readers: how this program reads back bytes it did not write itself, or
//! wrote but must not trust by name.
//!
//! `src/capture.zig` owns the readers — a target's stdout (`observeCapture`), a caller-named
//! case or config (`readFileAllocCapped`), the tail a live observer appended
//! (`readFileFrom`), the oracle's capture (`readFileAlloc`), and a failing setup's last line
//! (`readSetupCapture`) — and the one rule every reader here keeps: "could not be read" is
//! never answered as "was empty" (`null` or `error.Unreadable` on one side; an empty slice,
//! a zero-length observation or `.empty` on the other). The other guards are the caller's
//! to choose, per read, through `ReadMode`, and only one of them follows from who named the
//! path: the descriptor is classified before it is trusted where the caller asks
//! (`require_regular`), and `observeCapture` and `readFileFrom` always ask; a link at the
//! final component is refused where the file is a work-directory artifact this engine
//! produced, and followed where the operator or the system named an existing file
//! (`ReadMode.no_follow`'s doc draws that line in three parts); a read is bounded in bytes
//! wherever the caller gives a ceiling — every reader here but `readFileAlloc`, which reads
//! the strace oracle's capture whole while its fs_usage sibling is capped at 2 GiB by the
//! caller. `src/main.zig` chooses the path and the mode at each call and holds none of the
//! reading.
//!
//! Why these live together: the guards are one small set of rules applied at several sites,
//! and twice a rule reached some readers and not others while they were three functions
//! four thousand lines apart in `main.zig` — the descriptor classification (#400: `lseek`
//! happened to refuse a FIFO and nothing refused `/dev/zero`) and the symlink refusal
//! (#469: given to one of the two readers of `<work>/oracle.txt`). The #400 test below
//! names all three readers under one title and pins the classification at each — and says
//! itself which of its assertions measures the guard and which only pins the behaviour,
//! `spike/case-path-deadline.py` measuring `readFileAllocCapped`'s from outside the process.
//! Not every rule about a capture is a reading rule: the work-directory captures refuse a
//! FIFO at the name because they are created with `Capture.exclusive`, which adds `O_EXCL`
//! to `posix.captureFlags`' `O_CREAT|O_TRUNC|O_NOFOLLOW` — a rule of how a capture is made,
//! and a change to it opens `src/posix.zig`, not this file. Nothing here writes a global,
//! exits, or renders a report line: a reader answers `null`, `error.Unreadable` or one of
//! `SetupCapture`'s three values, and the caller in `main.zig` decides what that means for
//! the run.
//!
//! Second seam of #572 (ADR 0062). The bodies moved from `main.zig` byte for byte on
//! 2026-09-12, with `pub` added where `main.zig` still calls them and on the three types a
//! public signature names (`ReadMode`, `SetupCapture`, `Appended`); the two `defer
//! removeFile(path)` lines in the `observeCapture` tests became `posix.unlink(z.ptr)` on the
//! handle those tests already held, because `removeFile` is the orchestrator's and this file
//! imports nothing of `main.zig`. The six tests that hold the readers moved with them, and
//! `build.zig` names this file as a test root so their collection does not depend on which
//! test in `main.zig` happens to mention what.
const std = @import("std");
const contract = @import("contract");
const posix = @import("posix.zig");

/// How much of a failing setup's capture is read back before the read is given up on.
/// A megabyte is far past any diagnosis and far short of a size that matters here; what
/// it really bounds is `readFileAllocCapped`'s arena growth, since that function reads
/// from the start and answers `null` — indistinguishably from "could not open" — the
/// moment the file exceeds the cap. That indistinguishability is why the sentence for
/// `null` says the output could not be read *back*, and names the file: an operator whose
/// setup wrote 4 MiB is told where the 4 MiB is rather than told it wrote nothing.
const setup_capture_cap: usize = 1024 * 1024;

/// The last line with something on it, with trailing newlines and blank lines skipped.
///
/// "Last" and not "first" because #483 asks for the child's last stderr, and a command
/// that fails usually says why on its way out. Blank lines are skipped rather than
/// returned because a trailing `echo` is common and an empty quote would read as though
/// nothing was written — the exact confusion the "wrote nothing" branch exists to keep
/// honest.
fn lastNonEmptyLine(text: []const u8) []const u8 {
    var it = std.mem.splitBackwardsScalar(u8, text, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len > 0) return line;
    }
    return "";
}

/// What a setup's capture had in it, as the three answers the report distinguishes.
///
/// One reader for both callers. The refusal's sentence and the success path's
/// keep-or-remove decision have to agree about what "empty" means, and prose saying they
/// do is not the same as their being one function: two spellings of the read options
/// (`require_regular`, `no_follow`) is a way for one of them to lose a guard silently.
///
/// `unreadable` and `empty` stay apart. A file that cannot be opened is not an empty one:
/// the refusal must not assert something about a file it failed to read, and the success
/// path must not delete the only copy of an output the engine could not see. A capture
/// past `setup_capture_cap` also lands here — `readFileAllocCapped` answers `null` for it
/// — and "could not be read back" is the honest word for a file this engine did not read.
///
/// "Empty" is about content, not bytes: a lone newline is what a bare `echo` leaves.
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
    // A trailing blank line is what an `echo` at the end of a script leaves.
    try t.expectEqualStrings("why it failed", lastNonEmptyLine("noise\nwhy it failed\n\n\n"));
    try t.expectEqualStrings("why it failed", lastNonEmptyLine("noise\nwhy it failed\n   \n"));
    try t.expectEqualStrings("crlf", lastNonEmptyLine("crlf\r\n"));
    // Nothing but whitespace is nothing: the caller's "wrote nothing" branch is correct
    // for these, and a bare `""` return is how it learns that.
    try t.expectEqualStrings("", lastNonEmptyLine(""));
    try t.expectEqualStrings("", lastNonEmptyLine("\n\n"));
    try t.expectEqualStrings("", lastNonEmptyLine("   \n\t\n"));
}

/// How long `--config` may wait for a peer that has not written yet before refusing.
///
/// **This number is pinned between three constants in another file and nothing checks
/// the coupling**, so the inequality is written here rather than left to be rediscovered.
/// `spike/case-path-deadline.py` carries `WRITER_DELAY = 1.0` (how late its writer
/// opens), `min_s = 1.5` on the two deadline legs (the floor they assert this wait
/// against), and `DEADLINE = 5.0` (when it kills sideeye). **`min_s` is the binding
/// lower bound, not `WRITER_DELAY`** — measured: 1200 ms satisfies "above 1.0, below
/// 5.0" and still fails both legs at 1.21 s. So: `min_s < this << DEADLINE`. Move any of
/// the three and this has to move with them.
const config_read_deadline_ms: u64 = 2000;

/// Between attempts while a peer might still arrive. Small enough to pick up a config
/// that lands mid-wait, large enough not to spin — the measured late-writer case takes
/// around eighty reads to cover a second on both platforms.
const config_read_poll_ms: u64 = 10;

/// Bytes appended to a file since `from`, cut at the last newline so a half-written
/// line is read whole next time; `end` is where the next read starts.
///
/// The handshake first polled a fixed 4 MiB tail. On the CI runner the system-wide
/// capture grew fast enough that the sentinel's line left that window between two
/// polls 100 ms apart — the measured burst rate is 200 MB/s, at which 4 MiB is 20 ms —
/// and the fifth check of the run timed out waiting for a line that had already scrolled
/// past. Reading what was appended, and only that, cannot miss a line.
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

/// One bounded observation of a stdout capture: how many bytes it held when opened, a
/// Blake3 digest of exactly those bytes, and whether `needle` appears among them — read
/// in chunks with an overlap so a marker straddling a chunk boundary is still found,
/// without holding a chatty target's whole stdout in memory across a few hundred worlds.
///
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
    /// The size `lseek` measured when the file was opened.
    measured: u64,
    /// The bytes actually read and digested. Less than `measured` only when the file
    /// shrank underneath the read — on a regular file that is direct evidence of a
    /// concurrent writer, which is why `sawTruncation` exists as its own predicate
    /// instead of hoping the next fingerprint happens to differ (R1: a truncate-to-b
    /// during sample one and an honest size-b sample two would otherwise compare equal).
    bytes: u64,
    digest: [std.crypto.hash.Blake3.digest_length]u8,
    marker_seen: bool,

    /// Fingerprint equality only — `marker_seen` depends on which needle was asked for.
    pub fn fingerprintEql(a: CaptureObservation, b: CaptureObservation) bool {
        return a.measured == b.measured and a.bytes == b.bytes and std.mem.eql(u8, &a.digest, &b.digest);
    }

    /// The file changed while this very sample was being read.
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
        // EOF before the measured size: the file shrank underneath us. `bytes` ends up
        // below `measured`, which `sawTruncation` reports as a change observed inside
        // this very sample — never left to the next comparison to maybe notice.
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
    // A FIFO **with a live writer and bytes already in it**. That shape is chosen so the
    // test measures the classification without reaching through the hang it guards: with
    // a writer present the open returns whether or not `O_NONBLOCK` is passed, so
    // removing the flag leaves this test fast rather than hanging a CI runner for six
    // hours. Removing the *classification* is what turns it red — the read would then
    // succeed and hand back the writer's bytes, which is the "could not be read becomes
    // was empty" defect in its readable form.
    //
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

    // `/dev/zero`, which is the input that separates this guard from the `lseek` that
    // happens to sit next to it. Measured: it is `S_IFCHR`, both `lseek`s **succeed**
    // (returning 0) and `read` returns bytes — so every reader whose refusal rests on a
    // failed seek accepts it. `readFileFrom` would answer an empty `Appended` rather
    // than null, and `observeCapture` a zero-length observation rather than an error.
    // Deleting either classification with only the FIFO above in the test leaves both
    // green, which is how these two call sites were left unguarded on the first attempt.
    const devzero = "/dev/zero";
    // First, that the device is there and answers what this test assumes. `null` and
    // `error.Unreadable` are also the answers to a failed open, so on a host without
    // `/dev/zero` the two assertions below would pass while measuring nothing at all.
    var dzb: [16]u8 = undefined;
    const dz_z = std.fmt.bufPrintZ(&dzb, "{s}", .{devzero}) catch unreachable;
    const dzfd = posix.open(dz_z.ptr, posix.O_RDONLY, @as(c_uint, 0));
    try std.testing.expect(dzfd >= 0);
    try std.testing.expectEqual(posix.Kind.other, try posix.kindOfFd(dzfd));
    _ = posix.close(dzfd);

    try std.testing.expect(readFileFrom(arena, devzero, 0, 64 * 1024) == null);
    try std.testing.expectError(error.Unreadable, observeCapture(devzero, null));

    // The control, with the same bytes in an ordinary file. Without it, readers that
    // refused everything — a `kindOfFd` stuck on `.other`, or a classification inverted
    // — would satisfy every assertion above.
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

    // And the case read still accepts an ordinary file when it is not asked to classify,
    // which is the half `--config` depends on.
    try std.testing.expect(readFileAllocCapped(arena, reg_path, 1024 * 1024, .{}) != null);

    _ = posix.unlink(fifo_z.ptr);
    _ = posix.unlink(reg_z.ptr);
    _ = posix.rmdir(base.ptr);
}

test "the work-directory readers refuse a symlink; the operator-named ones still follow one (#469)" {
    // Both directions in one test, because the flag is a *split* and only one half of it
    // is a guard. A build that set `no_follow` everywhere would pass the first pair and
    // fail the second, which is the regression that matters here: `--config` and a saved
    // case are paths the operator chose, and keeping either behind a link is ordinary.
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

    // The control first: without the flag the link is followed and the bytes arrive, so
    // the refusal below is about the flag and not about this path or these contents.
    try std.testing.expectEqualStrings("contents", readFileAllocCapped(arena, link, 4096, .{}).?);
    try std.testing.expect(readFileAllocCapped(arena, link, 4096, .{ .no_follow = true }) == null);

    // And the flag refuses the link, not reading as such: the same call on the file the
    // link pointed at still succeeds. Without this leg a build whose `no_follow` open
    // always failed would satisfy the assertion above.
    try std.testing.expectEqualStrings("contents", readFileAllocCapped(arena, real, 4096, .{ .no_follow = true }).?);

    // `readFileAlloc` is the oracle capture's reader and sets the flag for its one
    // caller; asserted here rather than trusted, because it reaches the flag through a
    // wrapper and a default rather than through an argument at the call site.
    try std.testing.expect(readFileAlloc(arena, link) == null);
    try std.testing.expectEqualStrings("contents", readFileAlloc(arena, real).?);
}

test "observeCapture finds a straddling marker and fingerprints the same bytes" {
    // posix directly, like the engine itself: the std file API wants an `Io` instance
    // threaded through every call, and this test needs one file, not a runtime.
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
    // The fingerprint is a property of the bytes, not of the needle asked about.
    try std.testing.expect(with.fingerprintEql(without));
    const unasked = try observeCapture(path, null);
    try std.testing.expect(with.fingerprintEql(unasked));

    // One appended byte moves the fingerprint.
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

    // An empty capture observes cleanly: zero bytes, nothing seen, no truncation.
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
    // The racy schedule itself (truncate between lseek and read) cannot be staged
    // deterministically, so the predicate is pinned on the recorded shape: a sample
    // whose read ended below its measured size. The hazard (R1): truncate-to-b during
    // sample one, then an honest size-b sample two — identical bytes, identical digest,
    // equal fingerprints if `measured` were not part of the comparison.
    const digest = [_]u8{7} ** std.crypto.hash.Blake3.digest_length;
    const during = CaptureObservation{ .measured = 10, .bytes = 4, .digest = digest, .marker_seen = false };
    const honest = CaptureObservation{ .measured = 4, .bytes = 4, .digest = digest, .marker_seen = false };
    try std.testing.expect(during.sawTruncation());
    try std.testing.expect(!honest.sawTruncation());
    try std.testing.expect(!during.fingerprintEql(honest));
}

/// What the caller wants of the read, beyond the byte ceiling.
///
/// A struct rather than two positional booleans: `(…, true, false)` and `(…, false,
/// true)` are both well-typed and mean opposite things, Zig has no named arguments, and
/// this codebase already carries an incident about an argument arriving silently in the
/// wrong place (`open`'s variadic `mode`, wrong on one architecture and plausible on the
/// other).
pub const ReadMode = struct {
    /// Refuse a descriptor that is not a regular file, before reading a byte (#400).
    require_regular: bool = false,
    /// Bound the read in wall-clock time as well as in bytes: keep asking while a peer
    /// might still arrive, and refuse at the deadline rather than waiting forever.
    bounded: bool = false,
    /// Refuse a symlink at the final component (#469).
    ///
    /// Off by default because **who names the path decides this**, and it is the same
    /// split the two flags above already draw. `--config` and a saved case are named by
    /// the operator, who may legitimately keep either behind a link; `/etc/ld.so.preload`
    /// is the system's. Set it for the work-directory artifacts the engine produced and
    /// reads back, where a link at the name can only be somebody else's substitution and
    /// the bytes decide a verdict.
    ///
    /// `<work>/oracle.txt` is the reason this exists rather than staying a per-caller
    /// argument: **two readers open that one file** — `readFileFrom` at the fs_usage
    /// handshake and this function at the oracle's account — and #469 gave the flag to
    /// one of them. The same file answered two ways is the shape that issue is about.
    no_follow: bool = false,
};

/// `readFileAlloc` with a ceiling: a caller-named file is input, and reading until EOF
/// from something that never ends (a device, a fifo) would hang the run before any
/// refusal could fire. Over the cap answers like unreadable.
///
/// **That sentence was written for a hazard the cap cannot reach, which is #400.** A
/// FIFO does not hang the read the cap guards — it hangs the `open` in front of it, and
/// the loop is never entered to be capped. So the open takes `O_NONBLOCK` where either
/// mode asks for it. That alone then buys a second defect: past the open, a FIFO with no
/// writer returns 0 from the first read, so the file arrives *empty* and successful.
/// Measured on macOS against a real FIFO: `open` ok, `fstat` S_IFIFO, `lseek` ESPIPE,
/// `read` n=0 with errno untouched.
///
/// The two `ReadMode` halves are the caller's to choose, because the callers differ in
/// who names the path and in what may be refused.
///
/// **`require_regular`** is the case read's. A case file is named by whoever runs
/// `replay`, and it is an ordinary file or it is not a case file — so a descriptor that
/// is anything else is refused before a byte is read.
///
/// **`bounded`** is `--config`'s, and it exists because that path cannot take the other
/// half. `--config` is operator-named and may legitimately be a pipe (`--config
/// /dev/stdin`, a process substitution), so refusing by kind would break spellings that
/// work today. What it can do is refuse to wait forever: keep asking while a peer might
/// still arrive, and stop at a deadline. Three inputs made that necessary, and each one
/// used to be a run with no exit code — a FIFO with no writer (the open), a pipe whose
/// writer opened and sent nothing (the read), and `/dev/zero` (a read that never ends).
///
/// **What `bounded` costs.** The deadline is absolute, not idle-based: a producer slower
/// than it, or a config that streams across it, is refused with the partial read
/// discarded. And a pipe whose writer opened, wrote nothing and closed is indisputably
/// *empty*, but reads exactly like one whose writer has not arrived — POSIX offers no
/// way to tell them apart — so it waits out the deadline and is reported unreadable
/// rather than empty. Both are measured and disclosed in the CHANGELOG.
///
/// The falsification and world captures ask for neither. They are written by this process
/// or its child inside the work directory: demanding regularity would refuse nothing that
/// happens, and a deadline would bound something the run already bounds. The setup capture
/// (#483) does ask for `require_regular`, because its path is the one an operator can aim
/// somewhere else with `--work`, and because the answer decides whether a file is deleted.
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
    // Asked once. The answer cannot change for an open descriptor, and asking per read
    // would cost an fstat on every empty pass — around eighty of them in the measured
    // late-writer case.
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
            // End of file — unless a peer might still show up. A FIFO with no writer
            // answers 0 exactly as an empty regular file does, and the only difference
            // is whether waiting could change the answer. `/dev/null` is not a FIFO, so
            // it takes this break and stays as fast as it is today.
            if (!peer_may_arrive or list.items.len != 0) break;
        } else {
            const e = std.c._errno().*;
            if (e == posix.EINTR) {
                // The repo's shape for this: an EINTR-only bounded retry, counted by the
                // loop rather than by hand (`posix.zig`'s wait). It applies to every
                // mode, and it is the plain readers — the ones without the flag, whose
                // read *does* block — that can actually reach it; for them this changes
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

        // Only `bounded` reaches here: the `n == 0` arm above needs `peer_may_arrive`
        // and the `n < 0` arm needs `mode.bounded` explicitly. Reading the clock
        // unconditionally rather than re-testing the mode keeps that from reading as a
        // case someone still has to think about.
        if (posix.monotonicMs() >= deadline_at) return null;
        posix.sleepForMs(config_read_poll_ms);
    }
    return list.items;
}

pub fn readFileAlloc(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    // A read error is not end of file (the shared loop returns null for it): treating
    // them alike once turned a truncated oracle file into a complete one, and the
    // comparison that followed was against however much happened to arrive.
    //
    // `no_follow` here rather than at the call site because there is exactly one caller
    // and it reads `<work>/oracle.txt` (#469). A second caller reading an operator-named
    // path would have to take the mode as an argument instead.
    return readFileAllocCapped(arena, path, std.math.maxInt(usize), .{ .no_follow = true });
}
