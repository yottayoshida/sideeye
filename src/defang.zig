const std = @import("std");

const DefangUnit = struct { len: usize, defang: bool };

fn defangUnit(s: []const u8, i: usize) DefangUnit {
    const ch = s[i];
    if (ch < 0x20 or ch == 0x7f) return .{ .len = 1, .defang = true };
    if (ch < 0x80) return .{ .len = 1, .defang = false };
    const len = std.unicode.utf8ByteSequenceLength(ch) catch return .{ .len = 1, .defang = true };
    if (i + len > s.len or !std.unicode.utf8ValidateSlice(s[i..][0..len]))
        return .{ .len = 1, .defang = true };
    const cp = std.unicode.utf8Decode(s[i..][0..len]) catch return .{ .len = 1, .defang = true };
    if (cp >= 0x80 and cp <= 0x9f) return .{ .len = len, .defang = true };
    return .{ .len = len, .defang = false };
}

/// below — the v0.1-era exposure there is closed by the same predicate). One `?` per
/// defanged unit — never more bytes out than in, so a hostile name cannot bloat the
/// report past its output buffer (a two-byte encoded C1 shrinks to one `?`).
pub fn appendSanitized(names: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}!void {
    var i: usize = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) try names.append(arena, '?') else try names.appendSlice(arena, s[i..][0..u.len]);
        i += u.len;
    }
}

pub fn textShown(arena: std.mem.Allocator, s: []const u8) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    appendSanitized(&out, arena, s) catch return "(allocation failed)";
    return out.items;
}

pub fn sanitizeForReport(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    var clean = true;
    var i: usize = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) {
            clean = false;
            break;
        }
        i += u.len;
    }
    if (clean) return s;
    var out: std.ArrayList(u8) = .empty;
    i = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang) {
            for (s[i..][0..u.len]) |ch| {
                var nb: [4]u8 = undefined;
                try out.appendSlice(arena, std.fmt.bufPrint(&nb, "\\x{x:0>2}", .{ch}) catch unreachable);
            }
        } else {
            try out.appendSlice(arena, s[i..][0..u.len]);
        }
        i += u.len;
    }
    return out.items;
}

fn isDisplayControl(cp: u21) bool {
    return cp == 0x061c or (cp >= 0x200b and cp <= 0x200f) or (cp >= 0x202a and cp <= 0x202e) or
        (cp >= 0x2060 and cp <= 0x2064) or (cp >= 0x2066 and cp <= 0x2069) or cp == 0xfeff or
        (cp >= 0xe0000 and cp <= 0xe007f);
}

fn contentUnit(s: []const u8, i: usize) DefangUnit {
    const u = defangUnit(s, i);
    if (u.defang or u.len == 1) return u;
    const cp = std.unicode.utf8Decode(s[i..][0..u.len]) catch return .{ .len = u.len, .defang = true };
    return .{ .len = u.len, .defang = isDisplayControl(cp) };
}

pub fn quotedForReport(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '"');
    var i: usize = 0;
    while (i < s.len) {
        const u = contentUnit(s, i);
        if (u.defang) {
            for (s[i..][0..u.len]) |ch| {
                var nb: [4]u8 = undefined;
                try out.appendSlice(arena, std.fmt.bufPrint(&nb, "\\x{x:0>2}", .{ch}) catch unreachable);
            }
        } else if (s[i] == '"' or s[i] == '\\') {
            try out.append(arena, '\\');
            try out.append(arena, s[i]);
        } else {
            try out.appendSlice(arena, s[i..][0..u.len]);
        }
        i += u.len;
    }
    try out.append(arena, '"');
    return out.items;
}

pub fn nonTextBytes(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const u = defangUnit(s, i);
        if (u.defang and !(u.len == 1 and (s[i] == '\t' or s[i] == '\n' or s[i] == '\r'))) n += u.len;
        i += u.len;
    }
    return n;
}

test "quotedForReport gives a stretch visible edges and the same classification as the report's (#688)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("\"\"", try quotedForReport(arena, ""));
    try std.testing.expectEqualStrings("\"a b \"", try quotedForReport(arena, "a b "));
    try std.testing.expectEqualStrings("\"q\\\"\\\\\"", try quotedForReport(arena, "q\"\\"));
    try std.testing.expectEqualStrings("\"\\x89PNG\\x0d\\x0a\"", try quotedForReport(arena, "\x89PNG\r\n"));
    try std.testing.expectEqualStrings("\"A\\xc2\\x9bB€\"", try quotedForReport(arena, "A\xc2\x9bB€"));
    try std.testing.expectEqualStrings("\"a\\xe2\\x80\\xaeb\"", try quotedForReport(arena, "a\u{202e}b"));
    try std.testing.expectEqualStrings("\"x\\xe2\\x80\\x8by\"", try quotedForReport(arena, "x\u{200b}y"));
    try std.testing.expectEqualStrings("\"é\"", try quotedForReport(arena, "é"));
    try std.testing.expectEqual(@as(usize, 1), nonTextBytes("\x89PNG\r\n"));
    try std.testing.expectEqual(@as(usize, 0), nonTextBytes("t=1\nu=2\r\n\tv"));
    try std.testing.expectEqual(@as(usize, 2), nonTextBytes("A\xc2\x9bB€"));
    try std.testing.expectEqual(@as(usize, 0), nonTextBytes("a\u{202e}b\u{200d}c"));
    try std.testing.expectEqual(@as(usize, 0), nonTextBytes("plain"));
    try std.testing.expectEqualStrings("\"\\xd8\\x9c\"", try quotedForReport(arena, "\u{061c}"));
    try std.testing.expectEqualStrings("\"\\xe2\\x81\\xa0\"", try quotedForReport(arena, "\u{2060}"));
    try std.testing.expectEqualStrings("\"\\xf3\\xa0\\x80\\x81\"", try quotedForReport(arena, "\u{e0001}"));
}

test "the defang classifier covers raw C1, encoded C1 and invalid bytes, and spares real UTF-8 (#167)" {
    // À is C3 80 and € is E2 82 AC — continuation bytes that *fall* inside the
    // C1 range. A lazy byte-wise widening would mangle both; é (C3 A9) would
    // not catch that, its continuation byte lies outside 0x80–0x9F. 0xFF is
    // the invalid-but-not-C1 independent pin: raw 0x9B alone cannot tell
    // "defangs C1" from "defangs any invalid byte".
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\x9bB")); // raw C1
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xc2\x9bB")); // encoded C1 (U+009B, CSI)
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xffB")); // invalid, not C1
    try std.testing.expectEqualStrings("ÀB€", textShown(arena, "ÀB€")); // real UTF-8 spared
    try std.testing.expectEqualStrings("A\\x9bB", try sanitizeForReport(arena, "A\x9bB"));
    try std.testing.expectEqualStrings("A\\xc2\\x9bB", try sanitizeForReport(arena, "A\xc2\x9bB"));
    try std.testing.expectEqualStrings("A\\xffB", try sanitizeForReport(arena, "A\xffB"));
    try std.testing.expectEqualStrings("ÀB€", try sanitizeForReport(arena, "ÀB€"));
}
