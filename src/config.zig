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
    /// The devices the define assumes are present in the environment the operation
    /// inherits — `env:NAME`, `env:NAME=VALUE`, `preload:LIB`, `pythonpath:FILE`,
    /// `note:TEXT` — as spelled, in order (ADR 0041). The engine checks each entry it can
    /// after `setup`, refuses the run as SETUP ERROR when one is missing, and carries the
    /// list into the report verbatim. Absent means nothing declared, which is what every
    /// define written before this key existed says by saying nothing.
    apparatus: ?[]const []const u8 = null,
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
    var apparatus: ?[]const []const u8 = null;

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
        const Slot = union(enum) { cmd: *?Command, str: *?[]const u8, list: *?[]const []const u8 };
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
            else if (std.mem.eql(u8, key, "apparatus"))
                Slot{ .list = &apparatus }
            else
                return fault(line_no, "unknown key in [define]: only `setup`, `operation`, `check`, `marker`, `expected_status`, `cwd` and `apparatus` exist"),
        };
        switch (slot) {
            .str => |p| {
                if (is_array)
                    return fault(line_no, "this key takes one double-quoted string; the array form belongs to the commands (setup, operation, check) and to apparatus");
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
            .list => |p| {
                if (p.* != null) return fault(line_no, "duplicate key");
                if (!is_array)
                    return fault(line_no, "apparatus takes the array form: one `[` ... `]` line of double-quoted `kind:value` entries (env:NAME, env:NAME=VALUE, preload:LIB, pythonpath:FILE, note:TEXT)");
                // `[]`, `[ ]`, `[] # comment`: all the empty array, refused in this key's own
                // words rather than the commands' ("a command needs at least its argv[0]").
                const inner = std.mem.trimStart(u8, rawv[1..], " \t");
                if (inner.len > 0 and inner[0] == ']')
                    return fault(line_no, "apparatus is empty; leave the key out to declare nothing");
                switch (try parseArrayValue(arena, rawv)) {
                    .ok => |elems| {
                        for (elems) |e| if (apparatusFault(e)) |msg| return fault(line_no, msg);
                        p.* = elems;
                    },
                    .bad => |msg| return fault(line_no, msg),
                }
            },
        }
    }
    if (state == null) return fault(0, "[world] state is required");
    if (operation == null) return fault(0, "[define] operation is required");
    return .{ .ok = .{ .state = state.?, .setup = setup, .operation = operation.?, .check = check, .marker = marker, .expected_status = expected_status, .cwd = cwd, .apparatus = apparatus } };
}

/// One apparatus entry, parsed (ADR 0041). The parser and the engine's check both go
/// through `parseApparatusEntry`, so the grammar has one home and a kind added here
/// reaches the check as a compile error in its `switch`, never as a runtime "the parser
/// should have refused it". The entry's spelling is what the report carries; this is
/// what the engine acts on.
pub const ApparatusEntry = union(enum) {
    env: struct { name: []const u8, value: ?[]const u8 },
    preload: []const u8,
    pythonpath: []const u8,
    note: []const u8,
};

pub const ApparatusParse = union(enum) { ok: ApparatusEntry, bad: []const u8 };

/// Parse one `kind:value` entry, or say why it is not one. One grammar for the toml key
/// and the `--apparatus` flag, so the two cannot drift into accepting different spellings
/// — the same reason `expected_status` shares its digit check with the flag.
pub fn parseApparatusEntry(entry: []const u8) ApparatusParse {
    if (badBytes(entry)) |msg| return .{ .bad = msg };
    // The toml's array form cannot spell a double quote inside an element, so the flag
    // form does not accept one either: one grammar, not a superset on the command line.
    if (std.mem.indexOfScalar(u8, entry, '"') != null)
        return .{ .bad = "an apparatus entry cannot contain a double quote (the toml form could not spell it)" };
    const colon = std.mem.indexOfScalar(u8, entry, ':') orelse
        return .{ .bad = "an apparatus entry is `kind:value`: env:NAME, env:NAME=VALUE, preload:LIB, pythonpath:FILE or note:TEXT" };
    const kind = entry[0..colon];
    const value = entry[colon + 1 ..];
    if (value.len == 0) return .{ .bad = "an apparatus entry has nothing after its `kind:`" };
    if (std.mem.eql(u8, kind, "env")) {
        const eq = std.mem.indexOfScalar(u8, value, '=');
        const name = if (eq) |i| value[0..i] else value;
        if (name.len == 0) return .{ .bad = "env: needs a variable name before the `=`" };
        for (name) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_'))
            return .{ .bad = "env: names a variable: letters, digits and underscores only" };
        if (engineOwnedEnv(name))
            return .{ .bad = "env: names a variable the engine sets for every child (LD_PRELOAD, DYLD_INSERT_LIBRARIES, TOY_STATE, SIDEEYE_*); the engine's own doing is not the define's apparatus" };
        return .{ .ok = .{ .env = .{ .name = name, .value = if (eq) |i| value[i + 1 ..] else null } } };
    }
    if (std.mem.eql(u8, kind, "preload")) {
        if (std.mem.indexOfScalar(u8, value, '/') != null)
            return .{ .bad = "preload: names a library by the start of its basename (libfaketime), not by path" };
        return .{ .ok = .{ .preload = value } };
    }
    if (std.mem.eql(u8, kind, "pythonpath")) {
        if (std.mem.indexOfScalar(u8, value, '/') != null)
            return .{ .bad = "pythonpath: names a file directly under a PYTHONPATH entry (sitecustomize.py), not a path" };
        return .{ .ok = .{ .pythonpath = value } };
    }
    if (std.mem.eql(u8, kind, "note")) return .{ .ok = .{ .note = value } };
    return .{ .bad = "an apparatus entry's kind is one of env, preload, pythonpath, note" };
}

/// Why an apparatus entry is not one, or null when it is.
pub fn apparatusFault(entry: []const u8) ?[]const u8 {
    return switch (parseApparatusEntry(entry)) {
        .ok => null,
        .bad => |msg| msg,
    };
}

/// The one predicate behind `apparatus_unchecked` and the text line's "(declared, not
/// checked)": an entry the engine carries without checking. Today that is `note:` alone;
/// both renderings read this, so they cannot disagree about which entries those are.
pub fn apparatusUnchecked(entry: []const u8) bool {
    return switch (parseApparatusEntry(entry)) {
        .ok => |e| e == .note,
        .bad => false,
    };
}

/// The variables the engine sets for every child it spawns. Declaring one as apparatus
/// would declare the engine's own doing, and a value the define wrote there is overwritten
/// before the operation sees it.
pub fn engineOwnedEnv(name: []const u8) bool {
    return std.mem.eql(u8, name, "LD_PRELOAD") or std.mem.eql(u8, name, "DYLD_INSERT_LIBRARIES") or
        std.mem.eql(u8, name, "TOY_STATE") or std.mem.startsWith(u8, name, "SIDEEYE_");
}

test "apparatus parses as an array of kind:value entries, stays optional, and refuses the string form by name" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const base = "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n";
    const none = parseFor(a, base);
    try t.expect(none.ok.apparatus == null);
    const two = parseFor(a, base ++ "apparatus = [\"env:FAKETIME=@2024-01-01 00:00:00\", \"preload:libfaketime\", \"note:hgrc revbranchcache.mmap = no\"]\n");
    try t.expectEqual(@as(usize, 3), two.ok.apparatus.?.len);
    try t.expectEqualStrings("env:FAKETIME=@2024-01-01 00:00:00", two.ok.apparatus.?[0]);
    try t.expectEqualStrings("preload:libfaketime", two.ok.apparatus.?[1]);
    try t.expectEqualStrings("note:hgrc revbranchcache.mmap = no", two.ok.apparatus.?[2]);
    // The string form is refused by name, the mirror of the array refusal on `cwd`.
    const str = parseFor(a, base ++ "apparatus = \"env:FAKETIME\"\n");
    try t.expectEqual(@as(usize, 5), str.fault.line);
    try t.expect(std.mem.indexOf(u8, str.fault.what, "takes the array form") != null);
    const empty = parseFor(a, base ++ "apparatus = []\n");
    try t.expect(std.mem.indexOf(u8, empty.fault.what, "apparatus is empty") != null);
    const empty_sp = parseFor(a, base ++ "apparatus = [ ]\n");
    try t.expect(std.mem.indexOf(u8, empty_sp.fault.what, "apparatus is empty") != null);
    const empty_c = parseFor(a, base ++ "apparatus = [] # nothing yet\n");
    try t.expect(std.mem.indexOf(u8, empty_c.fault.what, "apparatus is empty") != null);
    const dup = parseFor(a, base ++ "apparatus = [\"note:a\"]\napparatus = [\"note:b\"]\n");
    try t.expect(std.mem.indexOf(u8, dup.fault.what, "duplicate key") != null);
    // A bad entry is refused at its line, with the entry grammar's own words.
    const kind = parseFor(a, base ++ "apparatus = [\"seccomp:enosys.json\"]\n");
    try t.expectEqual(@as(usize, 5), kind.fault.line);
    try t.expect(std.mem.indexOf(u8, kind.fault.what, "kind is one of") != null);
    const owned = parseFor(a, base ++ "apparatus = [\"env:LD_PRELOAD=/x.so\"]\n");
    try t.expect(std.mem.indexOf(u8, owned.fault.what, "the engine sets for every child") != null);
}

test "apparatusFault: the entry grammar, one case per refusal" {
    try t.expect(apparatusFault("env:FAKETIME") == null);
    try t.expect(apparatusFault("env:PAPIS_NP=0") == null);
    try t.expect(apparatusFault("preload:libfaketime") == null);
    try t.expect(apparatusFault("pythonpath:sitecustomize.py") == null);
    try t.expect(apparatusFault("note:anything at all, with spaces: and colons") == null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("faketime").?, "kind:value") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("env:").?, "nothing after") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("env:=1").?, "before the `=`") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("env:MY-VAR").?, "letters, digits") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("env:SIDEEYE_TRACE_PATH=/x").?, "engine sets") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("env:TOY_STATE").?, "engine sets") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("preload:/usr/lib/libfaketime.so").?, "not by path") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("pythonpath:pins/sitecustomize.py").?, "not a path") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("seccomp:enosys").?, "kind is one of") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("note:a\x01b").?, "control bytes") != null);
    try t.expect(std.mem.indexOf(u8, apparatusFault("note:say \"hi\"").?, "double quote") != null);
    try t.expect(engineOwnedEnv("SIDEEYE_STATE_DIR"));
    try t.expect(!engineOwnedEnv("FAKETIME"));
    // The parsed shape the engine acts on, and the one predicate both renderings share.
    const env = parseApparatusEntry("env:PAPIS_NP=0").ok;
    try t.expectEqualStrings("PAPIS_NP", env.env.name);
    try t.expectEqualStrings("0", env.env.value.?);
    try t.expect(parseApparatusEntry("env:FAKETIME").ok.env.value == null);
    try t.expectEqualStrings("libfaketime", parseApparatusEntry("preload:libfaketime").ok.preload);
    try t.expect(apparatusUnchecked("note:anything"));
    try t.expect(!apparatusUnchecked("env:FAKETIME"));
    try t.expect(!apparatusUnchecked("not an entry"));
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
