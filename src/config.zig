//! sideeye.toml — the Define contract's file form (ADR 0007).
//!
//! The parser accepts a strict subset of TOML on purpose: `[world]` and `[define]`
//! section headers, `key = "double-quoted string"` pairs, blank lines and `#`
//! comments — nothing else. What a config parser accepts is the width of the
//! contract, so anything unexpected is a named, line-numbered refusal rather than
//! something to skip: an ignored key is a declared invariant that silently never
//! fires, which is this tool's worst shape wearing config clothes.
//!
//! Keys exist here only once the engine enforces them. `marker` is deliberately
//! absent until the change that makes L1 judge something lands; today it refuses as
//! an unknown key instead of parsing and quietly not acting.

const std = @import("std");

pub const Define = struct {
    state: []const u8,
    setup: ?[]const u8 = null,
    operation: []const u8,
    check: ?[]const u8 = null,
    /// The L1 success marker (ADR 0008): a byte string the operation prints on stdout
    /// when it has committed. Joined the schema in the same change that made the
    /// engine enforce it — a key that parses before it acts would accept a declared
    /// invariant and quietly not enforce it.
    marker: ?[]const u8 = null,
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
    var setup: ?[]const u8 = null;
    var operation: ?[]const u8 = null;
    var check: ?[]const u8 = null;
    var marker: ?[]const u8 = null;

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
        const value = stripQuoted(std.mem.trim(u8, line[eq + 1 ..], " \t")) orelse
            return fault(line_no, "the value must be one double-quoted string (an inline # comment may follow it)");
        if (std.mem.indexOfScalar(u8, value, '\\') != null)
            return fault(line_no, "escape sequences are not part of the contract; anything a plain string cannot spell belongs in a script file");
        // A NUL truncates at the C boundary, so the config as reviewed and the command
        // as executed would silently differ; other control bytes are the report-forging
        // class (#26). The flags could never carry these — the file must not widen that.
        for (value) |ch| if (ch < 0x20 or ch == 0x7f)
            return fault(line_no, "control bytes are not part of the contract; anything a plain string cannot spell belongs in a script file");
        const slot: *?[]const u8 = switch (section) {
            .none => return fault(line_no, "a key before any section header"),
            .world => if (std.mem.eql(u8, key, "state"))
                &state
            else
                return fault(line_no, "unknown key in [world]: only `state` exists"),
            .define => if (std.mem.eql(u8, key, "setup"))
                &setup
            else if (std.mem.eql(u8, key, "operation"))
                &operation
            else if (std.mem.eql(u8, key, "check"))
                &check
            else if (std.mem.eql(u8, key, "marker"))
                &marker
            else
                return fault(line_no, "unknown key in [define]: only `setup`, `operation`, `check` and `marker` exist"),
        };
        if (slot.* != null) return fault(line_no, "duplicate key");
        if (value.len == 0) return fault(line_no, "the value is empty");
        slot.* = try arena.dupe(u8, value);
    }
    if (state == null) return fault(0, "[world] state is required");
    if (operation == null) return fault(0, "[define] operation is required");
    return .{ .ok = .{ .state = state.?, .setup = setup, .operation = operation.?, .check = check, .marker = marker } };
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
    try t.expectEqualStrings("mytool init", r.ok.setup.?);
    try t.expectEqualStrings("mytool rotate-key", r.ok.operation);
    try t.expectEqualStrings("./check.sh", r.ok.check.?);
    try t.expectEqualStrings("Recorded", r.ok.marker.?);
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
