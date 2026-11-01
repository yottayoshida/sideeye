//! comments — nothing else. What a config parser accepts is the width of the
//! contract, so anything unexpected is a named, line-numbered refusal rather than
//! something to skip: an ignored key is a declared invariant that silently never
//! fires, which is this tool's worst shape wearing config clothes.

const std = @import("std");
const defang = @import("defang.zig");

pub const Command = union(enum) {
    str: []const u8,
    argv: []const []const u8,

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
    marker: ?[]const u8 = null,
    expected_status: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    apparatus: ?[]const []const u8 = null,
    scratch: ?[]const []const u8 = null,
    recovery: ?[]const u8 = null,
    recovery_check: ?[]const u8 = null,
    cut_at_comment: []const []const u8 = &.{},
};

pub const Fault = struct {
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
    const Section = enum { none, world, define, recovery };
    var section: Section = .none;
    var state: ?[]const u8 = null;
    var setup: ?Command = null;
    var operation: ?Command = null;
    var check: ?Command = null;
    var marker: ?[]const u8 = null;
    var expected_status: ?[]const u8 = null;
    var cwd: ?[]const u8 = null;
    var apparatus: ?[]const []const u8 = null;
    var scratch: ?[]const []const u8 = null;
    var recovery: ?[]const u8 = null;
    var recovery_check: ?[]const u8 = null;
    var cut_at_comment: std.ArrayList([]const u8) = .empty;

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
            if (std.mem.eql(u8, line, "[recovery]")) {
                section = .recovery;
                continue;
            }
            return fault(line_no, "unknown section: only [world], [define] and [recovery] exist");
        }
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse
            return fault(line_no, "not a key = \"value\" line");
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const rawv = std.mem.trim(u8, line[eq + 1 ..], " \t");
        const is_array = rawv.len > 0 and rawv[0] == '[';
        const ListKey = enum { apparatus, scratch };
        const ListSlot = struct { p: *?[]const []const u8, key: ListKey };
        const Slot = union(enum) { cmd: *?Command, str: *?[]const u8, list: ListSlot };
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
                Slot{ .list = .{ .p = &apparatus, .key = .apparatus } }
            else if (std.mem.eql(u8, key, "scratch"))
                Slot{ .list = .{ .p = &scratch, .key = .scratch } }
            else
                return fault(line_no, "unknown key in [define]: only `setup`, `operation`, `check`, `marker`, `expected_status`, `cwd`, `apparatus` and `scratch` exist"),
            .recovery => if (is_array)
                return fault(line_no, "[recovery] takes the string form only: one double-quoted command line, split on spaces, the way `--recovery` spells it on a replay")
            else if (std.mem.eql(u8, key, "command"))
                Slot{ .str = &recovery }
            else if (std.mem.eql(u8, key, "check"))
                Slot{ .str = &recovery_check }
            else
                return fault(line_no, "unknown key in [recovery]: only `command` and `check` exist"),
        };
        switch (slot) {
            .str => |p| {
                if (is_array)
                    return fault(line_no, "this key takes one double-quoted string; the array form belongs to the commands (setup, operation, check), to apparatus and to scratch");
                const value = stripQuoted(rawv) orelse
                    return fault(line_no, try notOneString(arena, key, rawv, false, section == .recovery));
                if (badBytes(value)) |msg| return fault(line_no, msg);
                if (p.* != null) return fault(line_no, "duplicate key");
                if (value.len == 0) return fault(line_no, "the value is empty");
                if (section == .recovery) if (try cutAtComment(arena, key, rawv, value, true)) |w| try cut_at_comment.append(arena, w);
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
                        return fault(line_no, try notOneString(arena, key, rawv, true, false));
                    if (badBytes(value)) |msg| return fault(line_no, msg);
                    if (value.len == 0) return fault(line_no, "the value is empty");
                    if (try cutAtComment(arena, key, rawv, value, false)) |w| try cut_at_comment.append(arena, w);
                    p.* = .{ .str = try arena.dupe(u8, value) };
                }
            },
            .list => |l| {
                if (l.p.* != null) return fault(line_no, "duplicate key");
                if (!is_array)
                    return fault(line_no, switch (l.key) {
                        .apparatus => "apparatus takes the array form: one `[` ... `]` line of double-quoted `kind:value` entries (env:NAME, env:NAME=VALUE, preload:LIB, pythonpath:FILE, pin:random, note:TEXT)",
                        .scratch => "scratch takes the array form: one `[` ... `]` line of double-quoted paths relative to the state directory",
                    });
                const inner = std.mem.trimStart(u8, rawv[1..], " \t");
                if (inner.len > 0 and inner[0] == ']')
                    return fault(line_no, switch (l.key) {
                        .apparatus => "apparatus is empty; leave the key out to declare nothing",
                        .scratch => "scratch is empty; leave the key out to declare nothing",
                    });
                switch (try parseArrayValue(arena, rawv)) {
                    .ok => |elems| l.p.* = switch (l.key) {
                        .apparatus => blk: {
                            for (elems) |e| if (apparatusFault(e)) |msg| return fault(line_no, msg);
                            break :blk elems;
                        },
                        .scratch => blk: {
                            const norm = try arena.alloc([]const u8, elems.len);
                            for (elems, 0..) |e, i| switch (parseScratchEntry(e)) {
                                .ok => |n| norm[i] = n,
                                .bad => |msg| return fault(line_no, msg),
                            };
                            break :blk norm;
                        },
                    },
                    .bad => |msg| return fault(line_no, msg),
                }
            },
        }
    }
    if (state == null) return fault(0, "[world] state is required");
    if (operation == null) return fault(0, "[define] operation is required");
    return .{ .ok = .{ .state = state.?, .setup = setup, .operation = operation.?, .check = check, .marker = marker, .expected_status = expected_status, .cwd = cwd, .apparatus = apparatus, .scratch = scratch, .recovery = recovery, .recovery_check = recovery_check, .cut_at_comment = cut_at_comment.items } };
}

pub const ScratchParse = union(enum) { ok: []const u8, bad: []const u8 };

pub fn parseScratchEntry(entry: []const u8) ScratchParse {
    if (badBytes(entry)) |msg| return .{ .bad = msg };
    if (std.mem.indexOfScalar(u8, entry, '"') != null)
        return .{ .bad = "a scratch path cannot contain a double quote (the toml form could not spell it)" };
    const path = std.mem.trimEnd(u8, entry, "/");
    if (path.len == 0) return .{ .bad = "a scratch path is empty (or only slashes); the state directory itself cannot be declared scratch" };
    if (path[0] == '/') return .{ .bad = "a scratch path is relative to the state directory; an absolute path cannot be under it" };
    var segs = std.mem.splitScalar(u8, path, '/');
    while (segs.next()) |seg| {
        if (seg.len == 0) return .{ .bad = "a scratch path has an empty segment (`//`)" };
        if (std.mem.eql(u8, seg, ".") or std.mem.eql(u8, seg, ".."))
            return .{ .bad = "a scratch path is spelled without `.` or `..` segments" };
    }
    return .{ .ok = path };
}

pub fn scratchFault(entry: []const u8) ?[]const u8 {
    return switch (parseScratchEntry(entry)) {
        .ok => null,
        .bad => |msg| msg,
    };
}

test "scratch parses as an array of relative paths, normalises trailing slashes, and refuses what cannot be under the state directory" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const base = "[world]\nstate = \"./s\"\n[define]\noperation = \"x\"\n";
    const none = try parse(a, base);
    try t.expect(none.ok.scratch == null);
    const two = try parse(a, base ++ "scratch = [\"COMMIT_EDITMSG\", \".hg/wcache/\"]\n");
    try t.expectEqual(@as(usize, 2), two.ok.scratch.?.len);
    try t.expectEqualStrings("COMMIT_EDITMSG", two.ok.scratch.?[0]);
    try t.expectEqualStrings(".hg/wcache", two.ok.scratch.?[1]);
    const str = try parse(a, base ++ "scratch = \"COMMIT_EDITMSG\"\n");
    try t.expect(std.mem.indexOf(u8, str.fault.what, "scratch takes the array form") != null);
    const empty = try parse(a, base ++ "scratch = []\n");
    try t.expect(std.mem.indexOf(u8, empty.fault.what, "scratch is empty") != null);
    const abs = try parse(a, base ++ "scratch = [\"/etc/passwd\"]\n");
    try t.expect(std.mem.indexOf(u8, abs.fault.what, "absolute path cannot be under it") != null);
    const dots = try parse(a, base ++ "scratch = [\"../outside\"]\n");
    try t.expect(std.mem.indexOf(u8, dots.fault.what, "without `.` or `..`") != null);
    const slashes = try parse(a, base ++ "scratch = [\"///\"]\n");
    try t.expect(std.mem.indexOf(u8, slashes.fault.what, "only slashes") != null);
    const dbl = try parse(a, base ++ "scratch = [\"a//b\"]\n");
    try t.expect(std.mem.indexOf(u8, dbl.fault.what, "empty segment") != null);
    const unknown = try parse(a, base ++ "scratchy = [\"x\"]\n");
    try t.expect(std.mem.indexOf(u8, unknown.fault.what, "`scratch` exist") != null);
    try t.expectEqualStrings("a/b", parseScratchEntry("a/b//").ok);
    try t.expect(scratchFault("./a") != null);
    try t.expect(scratchFault("a") == null);
}

pub const ApparatusEntry = union(enum) {
    env: struct { name: []const u8, value: ?[]const u8 },
    preload: []const u8,
    pythonpath: []const u8,
    pin_random,
    note: []const u8,
};

pub const ApparatusParse = union(enum) { ok: ApparatusEntry, bad: []const u8 };

/// alike (ADR 0014). Here and not beside the flag since #572 seam 3b: the freeze audit's rung 1 settles surface 1 — the
/// config format — on this file and `src/main.zig` being unchanged, and a grammar that
/// lived in `src/cli.zig` would have been outside what it looks at.
pub fn parseExpectStatus(s: []const u8) ?u8 {
    if (s.len == 0 or s.len > 3) return null;
    var v: u32 = 0;
    for (s) |ch| {
        if (ch < '0' or ch > '9') return null;
        v = v * 10 + (ch - '0');
    }
    if (v > 255) return null;
    return @intCast(v);
}

test "parseExpectStatus: one to three digits, 0..255, nothing else" {
    const expect = std.testing.expectEqual;
    try expect(@as(?u8, 0), parseExpectStatus("0"));
    try expect(@as(?u8, 7), parseExpectStatus("7"));
    try expect(@as(?u8, 255), parseExpectStatus("255"));
    try expect(@as(?u8, 42), parseExpectStatus("042"));
    try expect(@as(?u8, 0), parseExpectStatus("00"));
    try expect(@as(?u8, null), parseExpectStatus(""));
    try expect(@as(?u8, null), parseExpectStatus("256"));
    try expect(@as(?u8, null), parseExpectStatus("1000"));
    // Four digits under 256: the length rule alone refuses these, so a mutation that lets a
    // fourth digit through is caught here and not by the range rule (review R2 of #572 seam 3b
    // found the first version of this test had no such input, and a length mutation lived).
    try expect(@as(?u8, null), parseExpectStatus("0042"));
    try expect(@as(?u8, null), parseExpectStatus("0000"));
    try expect(@as(?u8, null), parseExpectStatus("0255"));
    try expect(@as(?u8, null), parseExpectStatus("-1"));
    try expect(@as(?u8, null), parseExpectStatus("+1"));
    try expect(@as(?u8, null), parseExpectStatus(" 1"));
    try expect(@as(?u8, null), parseExpectStatus("1 "));
    try expect(@as(?u8, null), parseExpectStatus("0x1"));
}

pub fn parseApparatusEntry(entry: []const u8) ApparatusParse {
    if (badBytes(entry)) |msg| return .{ .bad = msg };
    if (std.mem.indexOfScalar(u8, entry, '"') != null)
        return .{ .bad = "an apparatus entry cannot contain a double quote (the toml form could not spell it)" };
    const colon = std.mem.indexOfScalar(u8, entry, ':') orelse
        return .{ .bad = "an apparatus entry is `kind:value`: env:NAME, env:NAME=VALUE, preload:LIB, pythonpath:FILE, pin:random or note:TEXT" };
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
    if (std.mem.eql(u8, kind, "pin")) {
        if (!std.mem.eql(u8, value, "random"))
            return .{ .bad = "pin: takes `random` only; the engine pins what libc hands out as randomness, and nothing else" };
        return .{ .ok = .pin_random };
    }
    if (std.mem.eql(u8, kind, "note")) return .{ .ok = .{ .note = value } };
    return .{ .bad = "an apparatus entry's kind is one of env, preload, pythonpath, pin, note" };
}

pub fn apparatusFault(entry: []const u8) ?[]const u8 {
    return switch (parseApparatusEntry(entry)) {
        .ok => null,
        .bad => |msg| msg,
    };
}

pub fn apparatusUnchecked(entry: []const u8) bool {
    return switch (parseApparatusEntry(entry)) {
        .ok => |e| e == .note,
        .bad => false,
    };
}

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
    const kind = parseFor(a, base ++ "apparatus = [\"seccomp:enosys.json\"]\n");
    try t.expectEqual(@as(usize, 5), kind.fault.line);
    try t.expect(std.mem.indexOf(u8, kind.fault.what, "kind is one of") != null);
    const owned = parseFor(a, base ++ "apparatus = [\"env:LD_PRELOAD=/x.so\"]\n");
    try t.expect(std.mem.indexOf(u8, owned.fault.what, "the engine sets for every child") != null);
}

test "pin:random is an apparatus kind the engine applies, and pin: takes nothing else" {
    try t.expect(parseApparatusEntry("pin:random").ok == .pin_random);
    try t.expect(std.mem.indexOf(u8, apparatusFault("pin:clock").?, "takes `random` only") != null);
    try t.expect(!apparatusUnchecked("pin:random"));
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
    const env = parseApparatusEntry("env:PAPIS_NP=0").ok;
    try t.expectEqualStrings("PAPIS_NP", env.env.name);
    try t.expectEqualStrings("0", env.env.value.?);
    try t.expect(parseApparatusEntry("env:FAKETIME").ok.env.value == null);
    try t.expectEqualStrings("libfaketime", parseApparatusEntry("preload:libfaketime").ok.preload);
    try t.expect(apparatusUnchecked("note:anything"));
    try t.expect(!apparatusUnchecked("env:FAKETIME"));
    try t.expect(!apparatusUnchecked("not an entry"));
}

pub fn badBytes(value: []const u8) ?[]const u8 {
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

fn stripQuoted(v: []const u8) ?[]const u8 {
    if (v.len < 2 or v[0] != '"') return null;
    const close = std.mem.indexOfScalarPos(u8, v, 1, '"') orelse return null;
    const rest = std.mem.trim(u8, v[close + 1 ..], " \t");
    if (rest.len != 0 and rest[0] != '#') return null;
    return v[1..close];
}

pub const From = enum { toml, flags };

const ShellWords = struct {
    words: []const []const u8,
    quoted: bool,
    unterminated: bool,
    operator: ?[]const u8,
};

fn shellWords(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}!ShellWords {
    var words: std.ArrayList([]const u8) = .empty;
    var cur: std.ArrayList(u8) = .empty;
    var quoted = false;
    var unterminated = false;
    var operator: ?[]const u8 = null;
    var in_word = false;
    var word_quoted = false;
    var word_expands = false;
    var word_start: usize = 0;
    var i: usize = 0;
    while (i <= s.len) {
        if (i == s.len or s[i] == ' ' or s[i] == '\t') {
            if (in_word) {
                const raw = s[word_start..i];
                if (operator == null and (word_expands or raw[0] == '$' or (!word_quoted and shellOperator(raw, words.items.len == 0))))
                    operator = raw;
                try words.append(arena, try arena.dupe(u8, cur.items));
                cur.clearRetainingCapacity();
                in_word = false;
                word_quoted = false;
                word_expands = false;
            }
            i += 1;
            continue;
        }
        if (!in_word) {
            in_word = true;
            word_start = i;
        }
        switch (s[i]) {
            '\'' => {
                quoted = true;
                word_quoted = true;
                const close = std.mem.indexOfScalarPos(u8, s, i + 1, '\'') orelse {
                    unterminated = true;
                    try cur.appendSlice(arena, s[i + 1 ..]);
                    i = s.len;
                    continue;
                };
                try cur.appendSlice(arena, s[i + 1 .. close]);
                i = close + 1;
            },
            '"' => {
                quoted = true;
                word_quoted = true;
                var j = i + 1;
                while (j < s.len and s[j] != '"') : (j += 1) {
                    if (s[j] == '\\' and j + 1 < s.len and (s[j + 1] == '"' or s[j + 1] == '\\')) j += 1;
                    if (expandsAt(s, j)) word_expands = true;
                    try cur.append(arena, s[j]);
                }
                if (j >= s.len) {
                    unterminated = true;
                    i = s.len;
                    continue;
                }
                i = j + 1;
            },
            else => {
                if (expandsAt(s, i)) word_expands = true;
                try cur.append(arena, s[i]);
                i += 1;
            },
        }
    }
    return .{ .words = words.items, .quoted = quoted, .unterminated = unterminated, .operator = operator };
}

fn expandsAt(s: []const u8, i: usize) bool {
    if (s[i] == '`') return true;
    if (s[i] != '$' or i + 1 >= s.len) return false;
    const n = s[i + 1];
    return n == '_' or std.ascii.isAlphanumeric(n) or std.mem.indexOfScalar(u8, "{(@*#?$!-", n) != null;
}

fn shellOperator(w: []const u8, first: bool) bool {
    const exact = [_][]const u8{ "&&", "||", "|", "|&", "&", ";", "(", ")" };
    for (exact) |e| if (std.mem.eql(u8, w, e)) return true;
    var d: usize = 0;
    while (d < w.len and std.ascii.isDigit(w[d])) d += 1;
    const r = w[d..];
    if (r.len > 0 and (r[0] == '>' or r[0] == '<')) {
        const constraint = r.len > 1 and r[1] == '=';
        const key_name = d == 0 and r[0] == '<' and w.len > 1 and w[w.len - 1] == '>';
        if (!constraint and !key_name) return true;
    }
    if (std.mem.startsWith(u8, w, "&>")) return true;
    if (w[0] == '$') return true;
    if (std.mem.eql(u8, w, "~") or std.mem.startsWith(u8, w, "~/")) return true;
    if (std.mem.indexOfScalar(u8, w, '`') != null) return true;
    return first and isAssignment(w);
}

fn isAssignment(w: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, w, '=') orelse return false;
    if (eq == 0) return false;
    for (w[0..eq], 0..) |c, k| {
        if (!(c == '_' or std.ascii.isAlphabetic(c) or (k > 0 and std.ascii.isDigit(c)))) return false;
    }
    return true;
}

fn argvLine(arena: std.mem.Allocator, key: []const u8, words: []const []const u8) error{OutOfMemory}!?[]const u8 {
    if (words.len == 0) return null;
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, key);
    try out.appendSlice(arena, " = [");
    for (words, 0..) |w, k| {
        if (w.len == 0 or std.mem.indexOfAny(u8, w, "\"\\") != null) return null;
        if (!std.mem.eql(u8, defang.textShown(arena, w), w)) return null;
        if (k > 0) try out.appendSlice(arena, ", ");
        try out.append(arena, '"');
        try out.appendSlice(arena, w);
        try out.append(arena, '"');
    }
    try out.append(arena, ']');
    return out.items;
}

/// `raw` is the string as written, before argv[0] is resolved against a toml's directory. Every
/// piece of `raw` it quotes goes through `textShown`: a flag's value never met `badBytes`.
pub fn shellWarning(arena: std.mem.Allocator, from: From, key: []const u8, raw: []const u8, recovery: bool) error{OutOfMemory}!?[]const u8 {
    const sw = try shellWords(arena, raw);
    const shown = defang.textShown(arena, raw);
    if (sw.operator) |op| {
        const tail: []const u8 = if (std.mem.indexOfAny(u8, op, "$`") != null or op[0] == '~')
            "nothing expands it; a command that needs a shell belongs in a script the define names"
        else if (isAssignment(op))
            "it is run as a program of that name; to set a variable for the command, run it through `env` (`env NAME=VALUE program ...`) or set it where Sideeye runs"
        else
            "to pipe, redirect or chain commands through a shell, put them in a script the define names";
        return try std.fmt.allocPrint(arena, "{s}: `{s}` holds `{s}`, which reaches the program as written: a string-form command is split on spaces and never run by a shell; {s}", .{ key, shown, defang.textShown(arena, op), tail });
    }
    if (!sw.quoted) return null;
    const line: ?[]const u8 = if (recovery or sw.unterminated) null else try argvLine(arena, key, sw.words);
    const remedy: []const u8 = if (recovery)
        "a [recovery] command has no argv form, so put it in a script"
    else if (line) |l| switch (from) {
        .toml => try std.fmt.allocPrint(arena, "the argv form groups what they meant: {s}", .{l}),
        .flags => try std.fmt.allocPrint(arena, "in a sideeye.toml, the argv form groups what they meant: {s}", .{l}),
    } else if (sw.unterminated) switch (from) {
        .toml => "one of its quotes is never closed, so what it meant is not one argv; write the argv form, or put it in a script",
        .flags => "one of its quotes is never closed, so what it meant is not one argv; write the argv form in a sideeye.toml, or put it in a script",
    } else "the argv form cannot spell one of its words (an empty word, a `\"` or `\\`, or a control byte), so put it in a script";
    return try std.fmt.allocPrint(arena, "{s}: `{s}` is split on spaces and its quotes reach the program as written, grouping nothing; {s}", .{ key, shown, remedy });
}

/// argv form says what it means and is not looked at. Called once the define is read, from a
/// toml or from flags — never for a replay, whose case holds the commands an exploration
/// already read (and, from a toml, with argv[0] resolved to a path this would misread).
pub fn shellWarnings(arena: std.mem.Allocator, from: From, setup: ?Command, operation: ?Command, check: ?Command, recovery: ?[]const u8, recovery_check: ?[]const u8) []const []const u8 {
    const Item = struct { key: []const u8, raw: ?[]const u8, recovery: bool };
    const items = [_]Item{
        .{ .key = "setup", .raw = stringForm(setup), .recovery = false },
        .{ .key = "operation", .raw = stringForm(operation), .recovery = false },
        .{ .key = "check", .raw = stringForm(check), .recovery = false },
        .{ .key = "recovery command", .raw = recovery, .recovery = true },
        .{ .key = "recovery check", .raw = recovery_check, .recovery = true },
    };
    var out: std.ArrayList([]const u8) = .empty;
    for (items) |it| {
        const raw = it.raw orelse continue;
        const w = (shellWarning(arena, from, it.key, raw, it.recovery) catch return out.items) orelse continue;
        out.append(arena, w) catch return out.items;
    }
    return out.items;
}

fn stringForm(c: ?Command) ?[]const u8 {
    const cmd = c orelse return null;
    return switch (cmd) {
        .str => |s| s,
        .argv => null,
    };
}

const Fix = union(enum) { line: []const u8, script };

fn fixedLine(arena: std.mem.Allocator, key: []const u8, rawv: []const u8, command: bool, recovery: bool) error{OutOfMemory}!?Fix {
    if (rawv.len == 0 or rawv[0] == '#') return null;
    var value: []const u8 = rawv;
    var comment: []const u8 = "";
    if (rawv[0] == '\'') {
        const close = std.mem.indexOfScalarPos(u8, rawv, 1, '\'') orelse return null;
        value = rawv[0 .. close + 1];
        comment = std.mem.trim(u8, rawv[close + 1 ..], " \t");
        if (comment.len != 0 and comment[0] != '#') return null;
    } else if (rawv[0] == '"') {
        var k: usize = 2;
        while (k <= rawv.len) : (k += 1) {
            if (rawv[k - 1] != '"') continue;
            const rest = std.mem.trim(u8, rawv[k..], " \t");
            if (rest.len == 0 or (rest[0] == '#' and (rawv[k] == ' ' or rawv[k] == '\t'))) {
                value = rawv[0..k];
                comment = rest;
                break;
            }
        } else return null;
    } else {
        var k: usize = 1;
        while (k < rawv.len) : (k += 1) {
            if (rawv[k] == '#' and (rawv[k - 1] == ' ' or rawv[k - 1] == '\t')) {
                value = std.mem.trimEnd(u8, rawv[0..k], " \t");
                comment = rawv[k..];
                break;
            }
        }
    }
    if (!std.mem.eql(u8, defang.textShown(arena, comment), comment)) return null;
    var inner: []const u8 = value;
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        inner = try std.mem.replaceOwned(u8, arena, value[1 .. value.len - 1], "\\\"", "\"");
    } else if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
        inner = value[1 .. value.len - 1];
    }
    if (inner.len == 0 or badBytes(inner) != null) return null;
    if (!std.mem.eql(u8, defang.textShown(arena, inner), inner)) return null;
    var line: []const u8 = undefined;
    if (std.mem.indexOfAny(u8, inner, "\"'") != null) {
        if (!command) return if (recovery) .script else null;
        const sw = try shellWords(arena, inner);
        if (sw.unterminated or sw.operator != null) return null;
        if (value[0] == '"') {
            const whole = try shellWords(arena, value);
            if (!whole.unterminated and whole.words.len > 0 and std.mem.indexOfScalar(u8, whole.words[0], ' ') == null) return null;
        }
        line = (try argvLine(arena, key, sw.words)) orelse return null;
    } else {
        line = try std.fmt.allocPrint(arena, "{s} = \"{s}\"", .{ key, inner });
    }
    if (comment.len != 0) line = try std.fmt.allocPrint(arena, "{s}  {s}", .{ line, comment });
    const nv = line[key.len + 3 ..];
    if (nv[0] == '[') {
        switch (try parseArrayValue(arena, nv)) {
            .ok => {},
            .bad => return null,
        }
    } else {
        const v = stripQuoted(nv) orelse return null;
        if (badBytes(v) != null) return null;
    }
    return .{ .line = line };
}

/// Accepted as it always was (surface 1 of `docs/contract-freeze.md`); said, with the argv form
/// when reading the inner quotes as meant gives one. `key` is the toml key; a `[recovery]`
fn cutAtComment(arena: std.mem.Allocator, key: []const u8, rawv: []const u8, value: []const u8, recovery: bool) error{OutOfMemory}!?[]const u8 {
    const after = rawv[value.len + 2 ..];
    if (after.len == 0 or after[0] != '#' or std.mem.indexOfScalar(u8, after, '"') == null) return null;
    const label = if (recovery) try std.fmt.allocPrint(arena, "recovery {s}", .{key}) else key;
    const remedy: []const u8 = if (recovery)
        "a [recovery] command has no argv form, so put it in a script"
    else if (try fixedLine(arena, key, rawv, true, false)) |fix| switch (fix) {
        .line => |l| try std.fmt.allocPrint(arena, "the argv form says so: {s}", .{l}),
        .script => "put it in a script",
    } else "write it in the argv form";
    return try std.fmt.allocPrint(arena, "{s}: the value ends at its second `\"`, so `{s}` is read as a comment and the command is `{s}`; if those quotes belong to the command, {s}", .{ label, defang.textShown(arena, after), defang.textShown(arena, value), remedy });
}

fn notOneString(arena: std.mem.Allocator, key: []const u8, rawv: []const u8, command: bool, recovery: bool) error{OutOfMemory}![]const u8 {
    const base = "the value must be one double-quoted string (an inline # comment may follow it)";
    const fix = (try fixedLine(arena, key, rawv, command, recovery)) orelse return base;
    return switch (fix) {
        .line => |l| try std.fmt.allocPrint(arena, "{s}; write it as: {s}", .{ base, l }),
        .script => base ++ "; a [recovery] command has no argv form, so one whose words need quotes belongs in a script",
    };
}

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
    const none = parseFor(a, base);
    try t.expect(none.ok.cwd == null);
    const one = parseFor(a, base ++ "cwd = \"/work/repo\"\n");
    try t.expectEqualStrings("/work/repo", one.ok.cwd.?);
    const rel = parseFor(a, base ++ "cwd = \"sub/dir\"\n");
    try t.expectEqualStrings("sub/dir", rel.ok.cwd.?);
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

test "[recovery] parses command and check as strings, stays optional, and refuses the argv form and unknown keys by name" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const r = parseFor(as.allocator(),
        \\[world]
        \\state = "s"
        \\[define]
        \\operation = "op"
        \\[recovery]
        \\command = "ninja -C build"   # the tool's own next start
        \\check = "./check-recovered.sh"
    );
    try t.expectEqualStrings("ninja -C build", r.ok.recovery.?);
    try t.expectEqualStrings("./check-recovered.sh", r.ok.recovery_check.?);

    const absent = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n");
    try t.expect(absent.ok.recovery == null and absent.ok.recovery_check == null);

    const half = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ncommand = \"x\"\n");
    try t.expectEqualStrings("x", half.ok.recovery.?);
    try t.expect(half.ok.recovery_check == null);

    const argv = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ncommand = [\"ninja\", \"-C\", \"build\"]\n");
    try t.expectEqual(@as(usize, 6), argv.fault.line); // the `command = [...]` line itself
    try t.expect(std.mem.indexOf(u8, argv.fault.what, "string form only") != null);

    const unknown_key = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ntimeout = \"5\"\n");
    try t.expectEqualStrings("unknown key in [recovery]: only `command` and `check` exist", unknown_key.fault.what);

    const separate = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\ncheck = \"c\"\n[recovery]\ncommand = \"r\"\n");
    try t.expectEqualStrings("c", separate.ok.check.?.str);
    try t.expect(separate.ok.recovery_check == null);

    const bad_section = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[recover]\n");
    try t.expectEqualStrings("unknown section: only [world], [define] and [recovery] exist", bad_section.fault.what);
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

test "a string-form command written for a shell earns one sentence saying what Sideeye does with it (#706)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const q = (try shellWarning(a, .toml, "check", "./c.sh 'a b' x", false)).?;
    try t.expect(std.mem.indexOf(u8, q, "check = [\"./c.sh\", \"a b\", \"x\"]") != null);
    try t.expect(std.mem.indexOf(u8, q, "grouping nothing") != null);
    const qf = (try shellWarning(a, .flags, "check", "./c.sh \"a b\"", false)).?;
    try t.expect(std.mem.indexOf(u8, qf, "in a sideeye.toml, the argv form") != null);
    const qr = (try shellWarning(a, .toml, "recovery command", "./fix 'a b'", true)).?;
    try t.expect(std.mem.indexOf(u8, qr, "no argv form") != null and std.mem.indexOf(u8, qr, "[\"") == null);
    const op = (try shellWarning(a, .toml, "operation", "tool run && echo ok", false)).?;
    try t.expect(std.mem.indexOf(u8, op, "holds `&&`") != null and std.mem.indexOf(u8, op, "script") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "tool > out.txt", false)).?, "holds `>`") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "tool $HOME/x", false)).?, "nothing expands it") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "FOO=1 tool", false)).?, "`env NAME=VALUE program ...`") != null);
    for ([_][]const u8{ "tool 1>&2", "tool 1>/dev/null", "tool 0<in", "tool |& tee x" }) |redir|
        try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "operation", redir, false)).?, "put them in a script") != null);
    for ([_][]const u8{ "./c.sh \"$HOME/a b\"", "test \"$(cat f)\" = 3", "./c.sh \"`date`\"", "./c.sh $'a b'" }) |exp| {
        const w = (try shellWarning(a, .flags, "check", exp, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "nothing expands it") != null);
        try t.expect(std.mem.indexOf(u8, w, "groups what they meant") == null);
    }
    const inq = (try shellWarning(a, .toml, "check", "grep -q 'a|b' f", false)).?;
    try t.expect(std.mem.indexOf(u8, inq, "holds") == null);
    try t.expect(std.mem.indexOf(u8, inq, "check = [\"grep\", \"-q\", \"a|b\", \"f\"]") != null);
    for ([_][]const u8{ "kak -n -e ggiX<esc>", "mapshaper -each x=n*10 in.shp", "tenv tf constraint ~>1.6", "yt-dlp -o %(title)s.%(ext)s u", "toy rotate", "grep -E ^x$ f", "tenv tf constraint >=1.6", "kak -e <esc>" }) |plain|
        try t.expect((try shellWarning(a, .toml, "operation", plain, false)) == null);
    const ctl = try std.fmt.allocPrint(a, "./c.sh \"a{c}b\"", .{@as(u8, 1)});
    for ([_][]const u8{ "./c.sh 'unterminated", "./c.sh '' x", "./c.sh 'a\\b'", ctl }) |odd| {
        const w = (try shellWarning(a, .flags, "check", odd, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "groups what they meant") == null);
        try t.expect(std.mem.indexOfScalar(u8, w, 1) == null);
    }
    const all = shellWarnings(a, .toml, .{ .str = "s 'x y'" }, .{ .argv = &.{ "o", "'z'" } }, .{ .str = "c" }, "r && r", null);
    try t.expectEqual(@as(usize, 2), all.len);
    try t.expect(std.mem.startsWith(u8, all[0], "setup: ") and std.mem.startsWith(u8, all[1], "recovery command: "));
}

test "a value that is not one double-quoted string is refused with the line it would have been read as (#706)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const head = "[world]\nstate = \"s\"\n[define]\noperation = \"o\"\n";
    const cases = [_]struct { text: []const u8, want: ?[]const u8 }{
        .{ .text = "[world]\nstate = './state'  # dir\n", .want = "; write it as: state = \"./state\"  # dir" },
        .{ .text = head ++ "expected_status = 0\n", .want = "; write it as: expected_status = \"0\"" },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva put \"hello world\"\"\n", .want = "; write it as: operation = [\"./kva\", \"put\", \"hello world\"]" },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva put \\\"hello world\\\"\"\n", .want = "; write it as: operation = [\"./kva\", \"put\", \"hello world\"]" },
        .{ .text = head ++ "check = ./check.sh # x\n", .want = "; write it as: check = \"./check.sh\"  # x" },
        .{ .text = head ++ "marker = done#1\n", .want = "; write it as: marker = \"done#1\"" },
        .{ .text = head ++ "[recovery]\ncommand = \"./fix \"a b\"\"\n", .want = "belongs in a script" },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva put \"a b\"\"  # see \"docs\"\n", .want = "; write it as: operation = [\"./kva\", \"put\", \"a b\"]  # see \"docs\"" },
        .{ .text = head ++ "marker = say \"done\"\n", .want = null },
        .{ .text = head ++ "check = ./c.sh 'unterminated\n", .want = null },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"a\" \"b\"\n", .want = null },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva\" \"put\" \"hello world\"\n", .want = null },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"tool\" \"a b\"\n", .want = null },
        .{ .text = head ++ "cwd = # TODO\n", .want = null },
    };
    for (cases) |c| {
        const what = parseFor(a, c.text).fault.what;
        try t.expect(std.mem.startsWith(u8, what, "the value must be one double-quoted string"));
        if (c.want) |w|
            try t.expect(std.mem.indexOf(u8, what, w) != null)
        else
            try t.expect(std.mem.indexOf(u8, what, "write it as") == null);
    }
    for ([_][]const u8{ "\x9b", "\xc2\x9b" }) |c1| {
        const v = try std.fmt.allocPrint(a, "[world]\nstate = './st{s}2J'\n", .{c1});
        const cm = try std.fmt.allocPrint(a, "[world]\nstate = './state'  # {s}2J\n", .{c1});
        for ([_][]const u8{ v, cm }) |text| {
            const what = parseFor(a, text).fault.what;
            try t.expect(std.mem.indexOf(u8, what, "write it as") == null);
            try t.expect(std.mem.indexOf(u8, what, c1) == null);
        }
    }
}

test "a command value cut at an inner quote by a comment is accepted as before, and said (#706)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    const d = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = \"o\"\ncheck = \"grep -c \"#include\" f\"\n[recovery]\ncommand = \"fix \"#1\" now\"\n").ok;
    try t.expectEqualStrings("grep -c ", d.check.?.str);
    try t.expectEqual(@as(usize, 2), d.cut_at_comment.len);
    try t.expect(std.mem.startsWith(u8, d.cut_at_comment[0], "check: the value ends at its second `\"`"));
    try t.expect(std.mem.indexOf(u8, d.cut_at_comment[0], "check = [\"grep\", \"-c\", \"#include\", \"f\"]") != null);
    try t.expect(std.mem.startsWith(u8, d.cut_at_comment[1], "recovery command: ") and std.mem.indexOf(u8, d.cut_at_comment[1], "script") != null);
    const plain = parseFor(a, "[world]\nstate = \"s\"\n[define]\noperation = \"o\" # \"x\"\ncheck = \"c\"#y\n").ok;
    try t.expectEqual(@as(usize, 0), plain.cut_at_comment.len);
}

test "where the argv form cannot spell a word, the remedy is a script (#706)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    for ([_][]const u8{ "./c.sh '' x", "./c.sh 'a\\b'" }) |odd| {
        const w = (try shellWarning(a, .toml, "check", odd, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "cannot spell one of its words") != null);
    }
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "check", "./c.sh 'open", false)).?, "never closed") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .flags, "check", "./c.sh 'open", false)).?, "argv form in a sideeye.toml") != null);
}

test "a $ a shell would expand, quoted or mid-word, gets no argv; a $ it would not, does (#706)" {
    var as = std.heap.ArenaAllocator.init(t.allocator);
    defer as.deinit();
    const a = as.allocator();
    for ([_][]const u8{ "./tool --out=$HOME/x 'a b'", "./tool \"a b\" pre${X}post" }) |exp| {
        const w = (try shellWarning(a, .toml, "check", exp, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "nothing expands it") != null);
        try t.expect(std.mem.indexOf(u8, w, "groups what they meant") == null);
    }
    const re = (try shellWarning(a, .toml, "check", "grep -E \"^x$\" f", false)).?;
    try t.expect(std.mem.indexOf(u8, re, "check = [\"grep\", \"-E\", \"^x$\", \"f\"]") != null);
    try t.expect((try shellWarning(a, .toml, "check", "sed s/$/x/ f", false)) == null);
}
