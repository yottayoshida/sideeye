//! The choke point every target-influenced string passes before it reaches a report line
//! (#26, #167): raw C1 controls, encoded C1 and invalid bytes are neutralised, so that a
//! file name a target chose cannot forge a line of the report that judges it.
//!
//! A leaf beside `main.zig` and `boundary.zig` rather than inside either (#572, ADR 0062):
//! the boundary's refusal sentences (six call sites in `boundary.zig`) and the report side
//! (thirty-four call sites across fourteen functions of `main.zig`, at the time of the move)
//! both pass through it, and inside either file it would be an import from the other — the shape
//! ADR 0047 gave `engine/read.zig`. Imports `std` and nothing else. The bodies moved from
//! `main.zig` byte for byte on 2026-09-12.

const std = @import("std");

/// One scan unit of a target-chosen byte string, shared by the two text-side
/// defang predicates (#167): `len` bytes starting at `i` are either kept
/// verbatim or defanged as a unit. C0 controls and DEL keep their original
/// treatment. The C1 range (U+0080–U+009F) is defanged in *both* encodings —
/// as a raw byte (invalid UTF-8) and as its valid two-byte form — because an
/// 8-bit-CSI terminal interprets either arrival as an escape introducer. Any
/// other invalid UTF-8 defangs one byte at a time (resync). A valid multi-byte
/// sequence outside the C1 codepoints passes through whole, which is what
/// keeps a continuation byte that merely *falls* in 0x80–0x9F (À is C3 80)
/// from being mangled — the classification is by codepoint, never by byte.
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

/// Target-chosen file names go into the text report verbatim, and a Unix file name may
/// contain newlines and control bytes — enough to forge whole report lines. The JSON
/// side is escaped in `jsonString`; this is the text side's equivalent, first built
/// for the l0 note and since #26's fix also the FAIL block's route (via `textShown`
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

/// Replace each defanged unit (see `defangUnit`: C0/DEL, C1 in either encoding,
/// invalid UTF-8) with a visible `\xNN` spelling per byte. The JSON side escapes
/// controls already; the text side printed them raw, which let target-chosen
/// names inject report lines. Everything else passes through untouched.
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

test "the defang classifier covers raw C1, encoded C1 and invalid bytes, and spares real UTF-8 (#167)" {
    // À is C3 80 and € is E2 82 AC — continuation bytes that *fall* inside the
    // C1 range. A lazy byte-wise widening would mangle both; é (C3 A9) would
    // not catch that, its continuation byte lies outside 0x80–0x9F. 0xFF is
    // the invalid-but-not-C1 independent pin: raw 0x9B alone cannot tell
    // "defangs C1" from "defangs any invalid byte".
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The l0-note/FAIL route: one '?' per defanged unit.
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\x9bB")); // raw C1
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xc2\x9bB")); // encoded C1 (U+009B, CSI)
    try std.testing.expectEqualStrings("A?B", textShown(arena, "A\xffB")); // invalid, not C1
    try std.testing.expectEqualStrings("ÀB€", textShown(arena, "ÀB€")); // real UTF-8 spared
    // The divergence route: same classification, visible \xNN spelling.
    try std.testing.expectEqualStrings("A\\x9bB", try sanitizeForReport(arena, "A\x9bB"));
    try std.testing.expectEqualStrings("A\\xc2\\x9bB", try sanitizeForReport(arena, "A\xc2\x9bB"));
    try std.testing.expectEqualStrings("A\\xffB", try sanitizeForReport(arena, "A\xffB"));
    try std.testing.expectEqualStrings("ÀB€", try sanitizeForReport(arena, "ÀB€"));
}
