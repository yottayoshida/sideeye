const std = @import("std");

pub const Word = enum {
    none,
    legs_red,
    legs_malformed,
    legs_not_reported,
    exit_disagrees,
    baseline_red,
    control_failed,
    its_leg_not_reported,
    legs_incomplete,
    only_its_leg,
    more_than_its_leg,
    not_its_leg,
};

pub const Leg = struct { name: []const u8, red: bool };

pub fn isLegName(s: []const u8) bool {
    if (s.len == 0 or s.len > 64) return false;
    for (s) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) return false;
    return true;
}

// Null when a line cannot be read: which line it was is in the checker's own output.
pub fn parseLegs(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!?[]const Leg {
    var legs: std.ArrayList(Leg) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return null;
        const name = line[0..sp];
        const result = line[sp + 1 ..];
        if (!isLegName(name)) return null;
        const red = if (std.mem.eql(u8, result, "fail")) true else if (std.mem.eql(u8, result, "ok")) false else return null;
        // Not last-one-wins: a checker that prints its legs before and after its recovery would
        // have the engine read whichever came second, and say nothing about the choice.
        for (legs.items) |l| if (std.mem.eql(u8, l.name, name)) return null;
        try legs.append(arena, .{ .name = name, .red = red });
    }
    return legs.items;
}

fn anyRed(legs: []const Leg) bool {
    for (legs) |l| if (l.red) return true;
    return false;
}

fn has(legs: []const Leg, name: []const u8) bool {
    for (legs) |l| if (std.mem.eql(u8, l.name, name)) return true;
    return false;
}

pub fn baseline(checker_passed: bool, legs: ?[]const Leg) Word {
    const got = legs orelse return .legs_malformed;
    if (got.len == 0) return .legs_not_reported;
    if (checker_passed == anyRed(got)) return .exit_disagrees;
    return if (checker_passed) .none else .legs_red;
}

pub fn control(reported: []const Leg, its_leg: []const u8, checker_passed: bool, legs: ?[]const Leg) Word {
    const got = legs orelse return .legs_malformed;
    if (got.len == 0) return .legs_not_reported;
    // Against the baseline's names, not this run's: a checker that stops at its first red
    // leg leaves the control's own leg unwritten, and a misspelt key would read the same.
    if (!has(reported, its_leg)) return .its_leg_not_reported;
    for (reported) |r| if (!has(got, r.name)) return .legs_incomplete;
    if (checker_passed == anyRed(got)) return .exit_disagrees;
    if (checker_passed) return .none;
    var own = false;
    var other = false;
    for (got) |l| if (l.red) {
        if (std.mem.eql(u8, l.name, its_leg)) own = true else other = true;
    };
    if (own and !other) return .only_its_leg;
    if (own) return .more_than_its_leg;
    return .not_its_leg;
}

const t = std.testing;

test "a legs file is read line by line, and a line it cannot read or a leg named twice makes it malformed" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const ok = (try parseLegs(a, "a ok\nb fail\n\nc-1 ok\r\n")).?;
    try t.expectEqual(@as(usize, 3), ok.len);
    try t.expect(ok[1].red and !ok[0].red and std.mem.eql(u8, ok[2].name, "c-1"));
    try t.expectEqual(@as(usize, 0), (try parseLegs(a, "")).?.len);
    for ([_][]const u8{ "a ok\na fail\n", "a\n", "a  ok\n", "a OK\n", "a/b ok\n", "a ok extra\n", " a ok\n" }) |bad|
        try t.expect((try parseLegs(a, bad)) == null);
}

test "a baseline is none only when every leg is ok and the checker exited 0, and says which way it is not" {
    const all_ok = [_]Leg{ .{ .name = "a", .red = false }, .{ .name = "b", .red = false } };
    const one_red = [_]Leg{ .{ .name = "a", .red = true }, .{ .name = "b", .red = false } };
    try t.expectEqual(Word.none, baseline(true, &all_ok));
    try t.expectEqual(Word.legs_red, baseline(false, &one_red));
    try t.expectEqual(Word.exit_disagrees, baseline(false, &all_ok));
    try t.expectEqual(Word.exit_disagrees, baseline(true, &one_red));
    try t.expectEqual(Word.legs_not_reported, baseline(true, &.{}));
    try t.expectEqual(Word.legs_malformed, baseline(true, null));
}

test "each way a control can go has its own word, decided in a fixed order" {
    const base = [_]Leg{ .{ .name = "a", .red = false }, .{ .name = "b", .red = false }, .{ .name = "d", .red = false } };
    const Case = struct { want: Word, leg: []const u8 = "a", checker_ok: bool = false, legs: ?[]const Leg };
    const only_a = [_]Leg{ .{ .name = "a", .red = true }, .{ .name = "b", .red = false }, .{ .name = "d", .red = false } };
    const a_and_d = [_]Leg{ .{ .name = "a", .red = true }, .{ .name = "b", .red = false }, .{ .name = "d", .red = true } };
    const only_b = [_]Leg{ .{ .name = "a", .red = false }, .{ .name = "b", .red = true }, .{ .name = "d", .red = false } };
    const stopped_at_a = [_]Leg{.{ .name = "a", .red = true }};
    const cases = [_]Case{
        .{ .want = .only_its_leg, .legs = &only_a },
        .{ .want = .more_than_its_leg, .legs = &a_and_d },
        .{ .want = .not_its_leg, .legs = &only_b },
        .{ .want = .none, .checker_ok = true, .legs = &base },
        .{ .want = .exit_disagrees, .checker_ok = true, .legs = &only_a },
        .{ .want = .exit_disagrees, .checker_ok = false, .legs = &base },
        .{ .want = .legs_incomplete, .legs = &stopped_at_a },
        .{ .want = .its_leg_not_reported, .leg = "c", .legs = &only_a },
        .{ .want = .its_leg_not_reported, .leg = "c", .legs = &stopped_at_a },
        .{ .want = .legs_not_reported, .legs = &.{} },
        .{ .want = .legs_malformed, .legs = null },
    };
    for (cases, 0..) |c, i| {
        const got = control(&base, c.leg, c.checker_ok, c.legs);
        t.expectEqual(c.want, got) catch |e| {
            std.debug.print("case {d}: wanted {s}, got {s}\n", .{ i, @tagName(c.want), @tagName(got) });
            return e;
        };
    }
}
