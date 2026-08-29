//! sideeye.toml — the Define contract's file form (ADR 0007, ADR 0019).
//!
//! The parser accepts a strict subset of TOML on purpose: `[world]` and `[define]`
//! section headers, `key = "double-quoted string"` pairs, the one-line argv form
//! `key = ["prog", "arg"]` on the three command keys, blank lines and `#`
//! comments — nothing else. What a config parser accepts is the width of the
//! contract, so anything unexpected is a named, line-numbered refusal rather than
//! something to skip: an ignored key is a declared invariant that silently never
//! fires, which is this tool's worst shape wearing config clothes.
//!
//! Keys exist here only once the engine enforces them. `marker` is deliberately
//! absent until the change that makes L1 judge something lands; today it refuses as
//! an unknown key instead of parsing and quietly not acting.

const std = @import("std");

/// A define command in one of its two spellings (ADR 0007 decision 5; ADR 0019).
/// The string form is split on spaces at the spawn site — no quoting, no escapes.
/// The argv form is passed to the executor verbatim, one element per argument —
/// it exists exactly for the argument a space-split string cannot spell.
pub const Command = union(enum) {
    str: []const u8,
    argv: []const []const u8,

    /// Case files carry a command as a bare JSON value — a string (the string
    /// form) or an array of strings (the argv form) — never as a tagged object.
    /// Anything else is a case from no schema this binary knows.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Command {
        return switch (try source.peekNextTokenType()) {
            .string => .{ .str = try std.json.innerParse([]const u8, allocator, source, options) },
            .array_begin => .{ .argv = try std.json.innerParse([]const []const u8, allocator, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

pub const Define = struct {
    state: []const u8,
    setup: ?Command = null,
    operation: Command,
    check: ?Command = null,
    /// The L1 success marker (ADR 0008): a byte string the operation prints on stdout
    /// when it has committed. Joined the schema in the same change that made the
    /// engine enforce it — a key that parses before it acts would accept a declared
    /// invariant and quietly not enforce it.
    marker: ?[]const u8 = null,
    /// The exit status that means the operation completed (ADR 0014). Carried as the
    /// string between the quotes — this parser knows one value shape, and the digits
    /// are validated by the same routine that validates the flag spelling, so the two
    /// cannot drift into accepting different grammars.
    expected_status: ?[]const u8 = null,
    /// The directory the define's three commands run in. Absent means the engine's own
    /// cwd, which is what every define recorded before this key existed ran under.
    ///
    /// It has no flag. A caller at a terminal can `cd` before invoking, and the two
    /// launchers this repo committed to reproduce cohort 3 do exactly that; the caller
    /// that cannot is the MCP server's, which is handed a config path and starts the
    /// engine itself. The knob exists for the caller with no other way to say it, and
    /// for the committed define that has to mean the same run on another machine.
    ///
    /// Relative spellings resolve against the toml's own directory, like `state`
    /// (ADR 0007): the same file means the same thing from any cwd.
    cwd: ?[]const u8 = null,
};

pub const Fault = struct {
    /// 1-based line number; 0 means the document as a whole (a missing key).
    line: usize,
    what: []const u8,
};

pub const Result = union(enum) {
    ok: Define,
    fault: Fault,
};

fn fault(line: usize, what: []const u8) Result {
    return .{ .fault = .{ .line = line, .what = what } };
}

pub fn parse(arena: std.mem.Allocator, text: []const u8) error{OutOfMemory}!Result {
    const Section = enum { none, world, define };
    var section: Section = .none;
    var state: ?[]const u8 = null;
    var setup: ?Command = null;
    var operation: ?Command = null;
    var check: ?Command = null;
    var marker: ?[]const u8 = null;
    var expected_status: ?[]const u8 = null;
    var cwd: ?[]const u8 = null;

    var it = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (it.next()) |raw| {
        line_no += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') {
            if (std.mem.eql(u8, line, "[world]")) {
                section = .world;
                continue;
            }
            if (std.mem.eql(u8, line, "[define]")) {
                section = .define;
                continue;
            }
            return fault(line_no, "unknown section: only [world] and [define] exist");
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse
            return fault(line_no, "not a key = \"value\" line");
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const rawv = std.mem.trim(u8, line[eq + 1 ..], " \t");
        const is_array = rawv.len > 0 and rawv[0] == '[';
        // Two slot shapes: the commands may carry either spelling (ADR 0019); every
        // other key knows exactly one value shape, and an array there is refused by
        // name rather than falling into a generic parse error — the key dispatch
        // happens before the value parse precisely so this refusal can exist.
        const Slot = union(enum) { cmd: *?Command, str: *?[]const u8 };
        const slot: Slot = switch (section) {
            .none => return fault(line_no, "a key before any section header"),
            .world => if (std.mem.eql(u8, key, "state"))
                Slot{ .str = &state }
            else
                return fault(line_no, "unknown key in [world]: only `state` exists"),
            .define => if (std.mem.eql(u8, key, "setup"))
                Slot{ .cmd = &setup }
            else if (std.mem.eql(u8, key, "operation"))
                Slot{ .cmd = &operation }
            else if (std.mem.eql(u8, key, "check"))
                Slot{ .cmd = &check }
            else if (std.mem.eql(u8, key, "marker"))
                Slot{ .str = &marker }
            else if (std.mem.eql(u8, key, "expected_status"))
                Slot{ .str = &expected_status }
            else if (std.mem.eql(u8, key, "cwd"))
                Slot{ .str = &cwd }
            else
                return fault(line_no, "unknown key in [define]: only `setup`, `operation`, `check`, `marker`, `expected_status` and `cwd` exist"),
        };
        switch (slot) {
            .str => |p| {
                if (is_array)
                    return fault(line_no, "this key takes one double-quoted string; the array form belongs to the commands (setup, operation, check)");
                const value = stripQuoted(rawv) orelse
                    return fault(line_no, "the value must be one double-quoted string (an inline # comment may follow it)");
                if (badBytes(value)) |msg| return fault(line_no, msg);
                if (p.* != null) return fault(line_no, "duplicate key");
                if (value.len == 0) return fault(line_no, "the value is empty");
                p.* = try arena.dupe(u8, value);
            },
            .cmd => |p| {
                if (p.* != null) return fault(line_no, "duplicate key");
                if (is_array) {
                    switch (try parseArrayValue(arena, rawv)) {
                        .ok => |elems| p.* = .{ .argv = elems },
                        .bad => |msg| return fault(line_no, msg),
                    }
                } else {
                    const value = stripQuoted(rawv) orelse
                        return fault(line_no, "the value must be one double-quoted string (an inline # comment may follow it)");
                    if (badBytes(value)) |msg| return fault(line_no, msg);
                    if (value.len == 0) return fault(line_no, "the value is empty");
                    p.* = .{ .str = try arena.dupe(u8, value) };
                }
            },
        }
    }
    if (state == null) return fault(0, "[world] state is required");
    if (operation == null) return fault(0, "[define] operation is required");
    return .{ .ok = .{ .state = state.?, .setup = setup, .operation = operation.?, .check = check, .marker = marker, .expected_status = expected_status, .cwd = cwd } };
}

/// The byte discipline both value shapes share. A NUL truncates at the C boundary,
/// so the config as reviewed and the command as executed would silently differ;
/// other control bytes are the report-forging class (#26). Escapes are refused
/// because there is no escape processing to back them (ADR 0007).
fn badBytes(value: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, value, '\\') != null)
        return "escape sequences are not part of the contract; anything a plain string cannot spell belongs in a script file";
    for (value) |ch| if (ch < 0x20 or ch == 0x7f)
        return "control bytes are not part of the contract; anything a plain string cannot spell belongs in a script file";
    return null;
}

const ArrayResult = union(enum) {
    ok: []const []const u8,
    bad: []const u8,
};

/// The argv form (ADR 0019): `["prog", "arg one", "arg two"]` — one line, every
/// element one double-quoted string, elements separated by commas, an inline `#`
/// comment allowed after the closing bracket. Deliberately not TOML's array
/// grammar: no multi-line arrays, no trailing comma, no non-string elements —
/// each refusal below is the boundary of the contract, not a parser limitation.
fn parseArrayValue(arena: std.mem.Allocator, v: []const u8) error{OutOfMemory}!ArrayResult {
    var elems: std.ArrayList([]const u8) = .empty;
    var i: usize = 1; // v[0] == '['
    var expect_elem = true;
    while (true) {
        while (i < v.len and (v[i] == ' ' or v[i] == '\t')) i += 1;
        if (i >= v.len)
            return .{ .bad = "the array does not close: the argv form is one `[` ... `]` on a single line" };
        if (v[i] == ']') {
            if (expect_elem and elems.items.len > 0)
                return .{ .bad = "a trailing comma before `]` is not part of the contract" };
            i += 1;
            break;
        }
        if (!expect_elem) {
            if (v[i] == ',') {
                i += 1;
                expect_elem = true;
                continue;
            }
            return .{ .bad = "array elements are separated by commas" };
        }
        if (v[i] != '"')
            return .{ .bad = "every array element is one double-quoted string" };
        const close = std.mem.indexOfScalarPos(u8, v, i + 1, '"') orelse
            return .{ .bad = "an array element's closing quote is missing" };
        const elem = v[i + 1 .. close];
        if (elem.len == 0) return .{ .bad = "an array element is empty" };
        if (badBytes(elem)) |msg| return .{ .bad = msg };
        try elems.append(arena, try arena.dupe(u8, elem));
        i = close + 1;
        expect_elem = false;
    }
    const rest = std.mem.trim(u8, v[i..], " \t");
    if (rest.len != 0 and rest[0] != '#')
        return .{ .bad = "trailing content after `]` (an inline # comment may follow it)" };
    if (elems.items.len == 0)
        return .{ .bad = "the array is empty; a command needs at least its argv[0]" };
    return .{ .ok = elems.items };
}

/// The value grammar: one double-quoted string, optionally followed by whitespace
/// and a `#` comment — DESIGN §12's own example writes `state = "./state"  # …`.
/// No escape processing: the bytes between the quotes are the value.
fn stripQuoted(v: []const u8) ?[]const u8 {
    if (v.len < 2 or v[0] != '"') return null;
    const close = std.mem.indexOfScalarPos(u8, v, 1, '"') orelse return null;
    const rest = std.mem.trim(u8, v[close + 1 ..], " \t");
    if (rest.len != 0 and rest[0] != '#') return null;
    return v[1..close];
}

// ---------------------------------------------------------------------------------

const t = std.testing;

fn parseFor(arena: std.mem.Allocator, text: []const u8) Result {
    return parse(arena, text) catch unreachable;
}

test "the DESIGN §12 example parses, inline comments and all" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const r = parseFor(as.allocator(),
        \\# sideeye.toml
        \\[world]
        \\state = "./state"                 # the directory Sideeye snapshots and restores
        \\
        \\[define]
        \\setup     = "mytool init"         # produce the initial state
        \\operation = "mytool rotate-key"   # what Sideeye kills partway through
        \\check     = "./check.sh"          # runs after crash + restart
        \\marker    = "Recorded"            # the operation's own success claim (L1)
    );
    try t.expectEqualStrings("./state", r.ok.state);
    try t.expectEqualStrings("mytool init", r.ok.setup.?.str);
    try t.expectEqualStrings("mytool rotate-key", r.ok.operation.str);
    try t.expectEqualStrings("./check.sh", r.ok.check.?.str);
    try t.expectEqualStrings("Recorded", r.ok.marker.?);
}

test "the argv form parses: verbatim elements, spaces and specials inside, inline comment after" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const r = parseFor(as.allocator(),
        \\[world]
        \\state = "./state"
        \\[define]
        \\setup     = ["./seed.sh", "two words"]
        \\operation = ["mytool", "commit", "-m", "a message with spaces"]   # argv form (ADR 0019)
        \\check     = ["./check.sh", "has # and , and [ inside"]
    );
    const op = r.ok.operation.argv;
    try t.expectEqual(@as(usize, 4), op.len);
    try t.expectEqualStrings("mytool", op[0]);
    try t.expectEqualStrings("a message with spaces", op[3]);
    try t.expectEqual(@as(usize, 2), r.ok.setup.?.argv.len);
    try t.expectEqualStrings("has # and , and [ inside", r.ok.check.?.argv[1]);
}

test "the argv form refuses on its boundary, each with the line" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const head = "[world]\nstate = \"s\"\n[define]\n";
    const cases = [_]struct { line: []const u8, frag: []const u8 }{
        .{ .line = "operation = [\"a\", \"b\"", .frag = "does not close" },
        .{ .line = "operation = []", .frag = "the array is empty" },
        .{ .line = "operation = [\"\"]", .frag = "element is empty" },
        .{ .line = "operation = [\"a\",]", .frag = "trailing comma" },
        .{ .line = "operation = [\"a\" \"b\"]", .frag = "separated by commas" },
        .{ .line = "operation = [\"a]", .frag = "closing quote" },
        .{ .line = "operation = [a]", .frag = "one double-quoted string" },
        .{ .line = "operation = [\"a\"] extra", .frag = "trailing content" },
        .{ .line = "operation = [\"a\\tb\"]", .frag = "escape sequences" },
        .{ .line = "operation = [\"a\tb\"]", .frag = "control bytes" },
    };
    for (cases) |c| {
        const text = std.fmt.allocPrint(a, "{s}{s}\n", .{ head, c.line }) catch unreachable;
        const r = parseFor(a, text);
        try t.expectEqual(@as(usize, 4), r.fault.line);
        try t.expect(std.mem.indexOf(u8, r.fault.what, c.frag) != null);
    }
    // A second `[` line would read as a section header; the message names the shape.
    const multi = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = [\n\"a\"]\n");
    try t.expectEqual(@as(usize, 4), multi.fault.line);
    try t.expect(std.mem.indexOf(u8, multi.fault.what, "does not close") != null);
    const dup = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = [\"a\"]\noperation = \"b\"\n");
    try t.expectEqualStrings("duplicate key", dup.fault.what);
}

test "the non-command keys refuse the array form by name" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const st = parseFor(a, "[world]\nstate = [\"s\"]\n");
    try t.expectEqual(@as(usize, 2), st.fault.line);
    try t.expect(std.mem.indexOf(u8, st.fault.what, "belongs to the commands") != null);
    const mk = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\nmarker = [\"m\"]\n");
    try t.expect(std.mem.indexOf(u8, mk.fault.what, "belongs to the commands") != null);
    const es = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\nexpected_status = [\"1\"]\n");
    try t.expect(std.mem.indexOf(u8, es.fault.what, "belongs to the commands") != null);
}

test "cwd parses as one string, stays optional, and refuses the array form by name" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const base = "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n";
    // Absent is a value, not a hole: every define written before this key existed says
    // "the engine's own cwd" by saying nothing, and must keep saying it.
    const none = parseFor(a, base);
    try t.expect(none.ok.cwd == null);
    const one = parseFor(a, base ++ "cwd = \"/work/repo\"\n");
    try t.expectEqualStrings("/work/repo", one.ok.cwd.?);
    // A relative spelling is carried through untouched — resolving it is the caller's
    // job, against the toml's own directory, and this parser never sees that directory.
    const rel = parseFor(a, base ++ "cwd = \"sub/dir\"\n");
    try t.expectEqualStrings("sub/dir", rel.ok.cwd.?);
    // It is a non-command key, so it lands in the same refusal as `marker` and
    // `expected_status` rather than growing a third value shape.
    const arr = parseFor(a, base ++ "cwd = [\"/a\", \"/b\"]\n");
    try t.expectEqual(@as(usize, 5), arr.fault.line);
    try t.expect(std.mem.indexOf(u8, arr.fault.what, "belongs to the commands") != null);
    const dup = parseFor(a, base ++ "cwd = \"/a\"\ncwd = \"/b\"\n");
    try t.expect(std.mem.indexOf(u8, dup.fault.what, "duplicate key") != null);
    const empty = parseFor(a, base ++ "cwd = \"\"\n");
    try t.expect(std.mem.indexOf(u8, empty.fault.what, "the value is empty") != null);
}

test "Command.jsonParse reads the bare-value shapes and refuses the rest" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const Box = struct { c: Command };
    const s = std.json.parseFromSliceLeaky(Box, a, "{\"c\": \"a b\"}", .{}) catch unreachable;
    try t.expectEqualStrings("a b", s.c.str);
    const v = std.json.parseFromSliceLeaky(Box, a, "{\"c\": [\"a\", \"b c\"]}", .{}) catch unreachable;
    try t.expectEqual(@as(usize, 2), v.c.argv.len);
    try t.expectEqualStrings("b c", v.c.argv[1]);
    try t.expectError(error.UnexpectedToken, std.json.parseFromSliceLeaky(Box, a, "{\"c\": 42}", .{}));
    try t.expectError(error.UnexpectedToken, std.json.parseFromSliceLeaky(Box, a, "{\"c\": [1, 2]}", .{}));
}

test "setup and check are optional; state and operation are not" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const ok = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n");
    try t.expect(ok.ok.setup == null and ok.ok.check == null);
    const no_state = parseFor(as.allocator(), "[define]\noperation = \"op\"\n");
    try t.expectEqualStrings("[world] state is required", no_state.fault.what);
    try t.expectEqual(@as(usize, 0), no_state.fault.line);
    const no_op = parseFor(as.allocator(), "[world]\nstate = \"s\"\n");
    try t.expectEqualStrings("[define] operation is required", no_op.fault.what);
}

test "expected_status parses as a string value and stays optional" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const r = parseFor(as.allocator(),
        \\[world]
        \\state = "s"
        \\[define]
        \\operation = "op"
        \\expected_status = "3"   # digits validated where the flag is validated
    );
    try t.expectEqualStrings("3", r.ok.expected_status.?);
    const absent = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n");
    try t.expect(absent.ok.expected_status == null);
}

test "an unknown key refuses with its line" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const r = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\nbudget = \"x\"\n");
    try t.expectEqual(@as(usize, 5), r.fault.line);
    try t.expect(std.mem.indexOf(u8, r.fault.what, "unknown key") != null);
}

test "a bare value, a duplicate, an unknown section and a homeless key all refuse" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const bare = parseFor(as.allocator(), "[world]\nstate = ./state\n");
    try t.expectEqual(@as(usize, 2), bare.fault.line);
    const dup = parseFor(as.allocator(), "[world]\nstate = \"a\"\nstate = \"b\"\n");
    try t.expectEqualStrings("duplicate key", dup.fault.what);
    const sec = parseFor(as.allocator(), "[worlds]\n");
    try t.expect(std.mem.indexOf(u8, sec.fault.what, "unknown section") != null);
    const homeless = parseFor(as.allocator(), "state = \"s\"\n");
    try t.expect(std.mem.indexOf(u8, homeless.fault.what, "before any section") != null);
}

test "a NUL or raw control byte in a value refuses: the C boundary would truncate it silently" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const nul = parseFor(as.allocator(), "[world]\nstate = \"/tmp/a\x00b\"\n");
    try t.expect(std.mem.indexOf(u8, nul.fault.what, "control bytes") != null);
    try t.expectEqual(@as(usize, 2), nul.fault.line);
    const tab = parseFor(as.allocator(), "[world]\nstate = \"a\tb\"\n");
    try t.expect(std.mem.indexOf(u8, tab.fault.what, "control bytes") != null);
}

test "escapes, empty values and trailing junk after the closing quote refuse" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const esc = parseFor(as.allocator(), "[world]\nstate = \"a\\tb\"\n");
    try t.expect(std.mem.indexOf(u8, esc.fault.what, "escape sequences") != null);
    const empty = parseFor(as.allocator(), "[world]\nstate = \"\"\n");
    try t.expectEqualStrings("the value is empty", empty.fault.what);
    const junk = parseFor(as.allocator(), "[world]\nstate = \"s\" extra\n");
    try t.expect(std.mem.indexOf(u8, junk.fault.what, "double-quoted") != null);
}
