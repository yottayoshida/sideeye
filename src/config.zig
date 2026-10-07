//! sideeye.toml — the Define contract's file form (ADR 0007, ADR 0019).
//!
//! The parser accepts a strict subset of TOML on purpose: `[world]`, `[define]` and
//! `[recovery]` section headers, `key = "double-quoted string"` pairs, the one-line argv form
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
const defang = @import("defang.zig");

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
    /// The paths under `state` the define declares as scratch (ADR 0043): each entry
    /// names the path itself and everything beneath it, relative to `state`, spelled
    /// without a leading `/`, without `.` or `..` segments, and with any trailing `/`
    /// dropped by the parser. The built-in invariants judge none of them — not their
    /// bytes, not their presence, in no world — and the report and the saved case carry
    /// the declaration verbatim. Absent means nothing declared, which is what every
    /// define written before this key existed says by saying nothing.
    scratch: ?[]const []const u8 = null,
    /// `[recovery] command` (#606, ADR 0072): the target's own recovery, run against a saved
    /// FAIL world's crash state after the exploration has decided its verdict. The string
    /// form only — split on spaces, no quoting — so that the replay line, where the same
    /// command travels as `--recovery`, runs exactly what the explore ran; an argv-form
    /// element holding a space could not be carried there without changing what it means.
    /// Relative spellings resolve against the toml's directory, like the checker's.
    recovery: ?[]const u8 = null,
    /// `[recovery] check`: judges the state the recovery left. Declared together with
    /// `command` or not at all — the pair is held in one place, after every source of the
    /// define has been read (`main.zig`), not here.
    recovery_check: ?[]const u8 = null,
    /// #706 (ADR 0095): a sentence for each command value the parser read as ending at an inner
    /// `"`, because a `#` right after it opened a comment — accepted as it always was
    /// (`docs/contract-freeze.md` surface 1), and said. `main.zig` adds them to the warnings.
    cut_at_comment: []const []const u8 = &.{},
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
        // Two slot shapes: the commands may carry either spelling (ADR 0019); every
        // other key knows exactly one value shape, and an array there is refused by
        // name rather than falling into a generic parse error — the key dispatch
        // happens before the value parse precisely so this refusal can exist.
        // The two array-only keys share one slot shape and differ in the grammar each
        // element is held to; the key is carried so the refusals name the right one.
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
            // Refused by name before the value parse, for the reason the dispatch sits there:
            // the `.str` slot's own array refusal names the commands in [define] as the keys
            // that take the argv form, which is the wrong advice here.
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
                        .apparatus => "apparatus takes the array form: one `[` ... `]` line of double-quoted `kind:value` entries (env:NAME, env:NAME=VALUE, preload:LIB, pythonpath:FILE, note:TEXT)",
                        .scratch => "scratch takes the array form: one `[` ... `]` line of double-quoted paths relative to the state directory",
                    });
                // `[]`, `[ ]`, `[] # comment`: all the empty array, refused in this key's own
                // words rather than the commands' ("a command needs at least its argv[0]").
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
                        // Stored normalised (trailing slashes dropped), so the report and
                        // the case carry the spelling the judge matches on.
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

/// One scratch entry (ADR 0043), normalised, or why it is not one. One grammar for the
/// toml key and the `--scratch` flag, the way `apparatus` shares its parser with its
/// flag. The value is a path relative to the state directory, naming the path itself and
/// everything beneath it: a leading `/` cannot be under the state directory, `.` and
/// `..` segments would let one spelling name two paths, and an empty segment (`a//b`) is
/// a path the snapshot never spells. Trailing slashes are dropped rather than refused
/// (`foo/` and `foo` name the same entry, because the snapshot writes a directory as
/// `foo`, never `foo/`), so the returned slice is what the judge compares against.
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

/// Why a scratch entry is not one, or null when it is.
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
    // The trailing slash is dropped: the snapshot spells a directory without one.
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
    // The unknown-key refusal names the eighth key.
    const unknown = try parse(a, base ++ "scratchy = [\"x\"]\n");
    try t.expect(std.mem.indexOf(u8, unknown.fault.what, "`scratch` exist") != null);
    // The flag form goes through the same function.
    try t.expectEqualStrings("a/b", parseScratchEntry("a/b//").ok);
    try t.expect(scratchFault("./a") != null);
    try t.expect(scratchFault("a") == null);
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

/// The digit grammar of an expected exit status: one to three digits, 0..255, nothing
/// else (a leading zero is a digit). One grammar for the toml key `expected_status` and the
/// `--expect-status` flag, so the two cannot drift into accepting different spellings — the
/// same reason `parseApparatusEntry` below is one grammar. Null is "not that grammar"; the
/// caller refuses in the words of its own surface (the flag's, the toml's); the value they
/// produce governs the recording check, the baseline world, the saved case and the report
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
    // A leading zero is a digit: "042" was accepted as 42 before this function existed.
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

/// Parse one `kind:value` entry, or say why it is not one. One grammar for the toml key
/// and the `--apparatus` flag, so the two cannot drift into accepting different spellings
/// — the same reason `expected_status` shares its digit check with the flag
/// (`parseExpectStatus` above).
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

// ---- #706 (ADR 0095): a string-form command written for a shell ----------------------------
//
// A string-form command is split on spaces and run without a shell (ADR 0007), so its quotes
// reach the program as written and `&&` arrives as an argument. Nothing here changes how a
// command runs — the spelling stays accepted (docs/contract-freeze.md surface 1). A define that
// looks written for a shell is told, in a warning, how Sideeye reads it and how to write what
// it meant.

/// Where a define's commands came from, which decides how a warning spells the remedy: a toml
/// key can take the argv form, a flag cannot (the argv form lives only in a sideeye.toml), and a
/// `[recovery]` command has no argv form in either.
pub const From = enum { toml, flags };

/// A string-form command split the way a POSIX shell splits words, to say what its quotes
/// meant. Only quotes are read: no expansion, and no escapes outside double quotes.
const ShellWords = struct {
    words: []const []const u8,
    /// A `'` or `"` appears in the string.
    quoted: bool,
    /// A quote opened and never closed: a shell would not read one argv, so none is offered.
    unterminated: bool,
    /// The first unquoted word a shell would act on rather than pass along.
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
    // A `$` or backquote inside double quotes: a shell expands it there, so the word's text is
    // not what a shell would pass, and no argv built from it says what was meant.
    var word_expands = false;
    var word_start: usize = 0;
    var i: usize = 0;
    while (i <= s.len) {
        if (i == s.len or s[i] == ' ' or s[i] == '\t') {
            if (in_word) {
                const raw = s[word_start..i];
                // A word beginning `$` expands however it is quoted (`$'a b'`, `$"x"`).
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
                // Unquoted, mid-word: `--out=$HOME/x` expands too, and an argv built from it
                // would carry the unexpanded text as the meaning.
                if (expandsAt(s, i)) word_expands = true;
                try cur.append(arena, s[i]);
                i += 1;
            },
        }
    }
    return .{ .words = words.items, .quoted = quoted, .unterminated = unterminated, .operator = operator };
}

/// A backquote, or a `$` a shell would expand at `s[i]`: one followed by a name, a digit, `{`,
/// `(` or a special parameter. A `$` with nothing such after it (`^x$`, `s/$/x/`) stays a `$`.
fn expandsAt(s: []const u8, i: usize) bool {
    if (s[i] == '`') return true;
    if (s[i] != '$' or i + 1 >= s.len) return false;
    const n = s[i + 1];
    return n == '_' or std.ascii.isAlphanumeric(n) or std.mem.indexOfScalar(u8, "{(@*#?$!-", n) != null;
}

/// A whole unquoted word a shell acts on: a pipe, a list, a redirection, an expansion, or an
/// assignment in front of the command. Only whole words count — `x=n*10`, `ggiX<esc>`, `~>1.6`
/// and `%(title)s` mean what they say to a program run without a shell, and are left alone.
fn shellOperator(w: []const u8, first: bool) bool {
    const exact = [_][]const u8{ "&&", "||", "|", "|&", "&", ";", "(", ")" };
    for (exact) |e| if (std.mem.eql(u8, w, e)) return true;
    // A redirection: an optional fd number, then `>` or `<` (`>`, `2>&1`, `1>/dev/null`, `0<in`),
    // or `&>`. Not `>=1.6` / `<=2` (a version constraint) and not a `<esc>`-shaped key name.
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

/// `key = ["a", "b c"]`, the argv form that reads the words as meant — or null where it cannot
/// say it: an empty word (the argv form refuses one), a word with a `"` or `\` (the argv form has
/// no escapes), or a word `textShown` would rewrite (the line shown would not be the one meant).
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

/// One sentence for a string-form command that looks written for a shell, or null. `key` names
/// it as the define does (`setup`, `operation`, `check`, `recovery command`, `recovery check`);
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
    } else
        "the argv form cannot spell one of its words (an empty word, a `\"` or `\\`, or a control byte), so put it in a script";
    return try std.fmt.allocPrint(arena, "{s}: `{s}` is split on spaces and its quotes reach the program as written, grouping nothing; {s}", .{ key, shown, remedy });
}

/// Every warning a define's string-form commands earn, in the order the define names them. The
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

/// The line a value the parser refused would have been read as, when one exists. A comment
/// (a `#` after a space or tab) is kept after the fixed value; a `#` with no space before it is
/// part of the value. A value in single quotes, unquoted, or with quotes inside its double
/// quotes becomes one double-quoted string — or, for a command whose words those inner quotes
/// group, the argv form (`\"` counted as a quote, the way a reader of a toml string means it).
/// Offered only when the line it builds parses back as that value; `.script` is the one remedy
/// for a `[recovery]` command whose words need quotes, which has no argv form.
fn fixedLine(arena: std.mem.Allocator, key: []const u8, rawv: []const u8, command: bool, recovery: bool) error{OutOfMemory}!?Fix {
    // Empty, or nothing but a comment (`cwd = # TODO`): there is no value to fix.
    if (rawv.len == 0 or rawv[0] == '#') return null;
    var value: []const u8 = rawv;
    var comment: []const u8 = "";
    if (rawv[0] == '\'') {
        const close = std.mem.indexOfScalarPos(u8, rawv, 1, '\'') orelse return null;
        value = rawv[0 .. close + 1];
        comment = std.mem.trim(u8, rawv[close + 1 ..], " \t");
        if (comment.len != 0 and comment[0] != '#') return null;
    } else if (rawv[0] == '"') {
        // The first `"` followed by nothing, or by a space and a comment, closes the value — so a
        // comment holding a `"` of its own (`# see "docs"`) stays a comment.
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
    // What this quotes back is toml text the parser never vetted: anything `textShown` would
    // rewrite (a control byte, C1, invalid UTF-8) means no line is offered, so none is printed raw.
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
        // `"a" "b"` reads two ways — a toml string holding `a" "b`, or two shell words — and
        // the two argvs differ, so neither is offered. The ordinary case does not: read as
        // shell words, `"tool put "a b""` gives `tool put a` as argv[0], which no one meant.
        if (value[0] == '"') {
            // The inner reading is taken only where the shell reading's argv[0] holds a space —
            // the form nobody means. `"tool" "a b"` reads as shell words with a sane argv[0]
            // (`tool`, `a b`), and the inner reading would give `tool a`, `b`: no line.
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

/// A command value the parser read as ending at an inner `"` because a `#` follows that quote
/// with no space: `check = "grep -c "#include" f"` is the command `grep -c ` and a comment.
/// Accepted as it always was (surface 1 of `docs/contract-freeze.md`); said, with the argv form
/// when reading the inner quotes as meant gives one. `key` is the toml key; a `[recovery]`
/// value is named `recovery <key>` and, having no argv form, pointed at a script.
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

/// The parser's refusal of a value that is not one double-quoted string, with the line it would
/// have been read as when there is one (#706, ADR 0095).
fn notOneString(arena: std.mem.Allocator, key: []const u8, rawv: []const u8, command: bool, recovery: bool) error{OutOfMemory}![]const u8 {
    const base = "the value must be one double-quoted string (an inline # comment may follow it)";
    const fix = (try fixedLine(arena, key, rawv, command, recovery)) orelse return base;
    return switch (fix) {
        .line => |l| try std.fmt.allocPrint(arena, "{s}; write it as: {s}", .{ base, l }),
        .script => base ++ "; a [recovery] command has no argv form, so one whose words need quotes belongs in a script",
    };
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

    // Absent means nothing declared: every define written before the section existed.
    const absent = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n");
    try t.expect(absent.ok.recovery == null and absent.ok.recovery_check == null);

    // One without the other parses here; the pair is held where every source of the define
    // has been read (a flag can supply the other half on nothing, but a config with one key
    // must still reach that single check rather than a second copy of it).
    const half = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ncommand = \"x\"\n");
    try t.expectEqualStrings("x", half.ok.recovery.?);
    try t.expect(half.ok.recovery_check == null);

    const argv = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ncommand = [\"ninja\", \"-C\", \"build\"]\n");
    try t.expectEqual(@as(usize, 6), argv.fault.line); // the `command = [...]` line itself
    try t.expect(std.mem.indexOf(u8, argv.fault.what, "string form only") != null);

    const unknown_key = parseFor(as.allocator(), "[world]\nstate = \"s\"\n[define]\noperation = \"op\"\n[recovery]\ntimeout = \"5\"\n");
    try t.expectEqualStrings("unknown key in [recovery]: only `command` and `check` exist", unknown_key.fault.what);

    // The define's own `check` is not the recovery's: a `[recovery]` key does not leak
    // into `[define]`, and `[define] check` does not satisfy `[recovery] check`.
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
    // Quotes: the argv form the words meant, as a toml line, or as the toml spelling of a flag.
    const q = (try shellWarning(a, .toml, "check", "./c.sh 'a b' x", false)).?;
    try t.expect(std.mem.indexOf(u8, q, "check = [\"./c.sh\", \"a b\", \"x\"]") != null);
    try t.expect(std.mem.indexOf(u8, q, "grouping nothing") != null);
    const qf = (try shellWarning(a, .flags, "check", "./c.sh \"a b\"", false)).?;
    try t.expect(std.mem.indexOf(u8, qf, "in a sideeye.toml, the argv form") != null);
    // A recovery has no argv form to offer.
    const qr = (try shellWarning(a, .toml, "recovery command", "./fix 'a b'", true)).?;
    try t.expect(std.mem.indexOf(u8, qr, "no argv form") != null and std.mem.indexOf(u8, qr, "[\"") == null);
    // Whole unquoted words a shell acts on: passed as written, and the sentence says so.
    const op = (try shellWarning(a, .toml, "operation", "tool run && echo ok", false)).?;
    try t.expect(std.mem.indexOf(u8, op, "holds `&&`") != null and std.mem.indexOf(u8, op, "script") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "tool > out.txt", false)).?, "holds `>`") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "tool $HOME/x", false)).?, "nothing expands it") != null);
    try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "setup", "FOO=1 tool", false)).?, "`env NAME=VALUE program ...`") != null);
    // Redirections with an fd number, and `|&`, are whole words a shell acts on.
    for ([_][]const u8{ "tool 1>&2", "tool 1>/dev/null", "tool 0<in", "tool |& tee x" }) |redir|
        try t.expect(std.mem.indexOf(u8, (try shellWarning(a, .toml, "operation", redir, false)).?, "put them in a script") != null);
    // Inside double quotes a shell expands `$` and backquotes, and `$'…'` is a quoting of its
    // own: no argv is offered as "what they meant" — it would carry the unexpanded text.
    for ([_][]const u8{ "./c.sh \"$HOME/a b\"", "test \"$(cat f)\" = 3", "./c.sh \"`date`\"", "./c.sh $'a b'" }) |exp| {
        const w = (try shellWarning(a, .flags, "check", exp, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "nothing expands it") != null);
        try t.expect(std.mem.indexOf(u8, w, "groups what they meant") == null);
    }
    // Inside quotes an operator is a character: the quotes are named, a shell is not.
    const inq = (try shellWarning(a, .toml, "check", "grep -q 'a|b' f", false)).?;
    try t.expect(std.mem.indexOf(u8, inq, "holds") == null);
    try t.expect(std.mem.indexOf(u8, inq, "check = [\"grep\", \"-q\", \"a|b\", \"f\"]") != null);
    // Left alone: what a program run without a shell reads as meant — four of them are defines
    // this repository runs (kakoune, mapshaper, tenv, yt-dlp).
    for ([_][]const u8{ "kak -n -e ggiX<esc>", "mapshaper -each x=n*10 in.shp", "tenv tf constraint ~>1.6", "yt-dlp -o %(title)s.%(ext)s u", "toy rotate", "grep -E ^x$ f", "tenv tf constraint >=1.6", "kak -e <esc>" }) |plain|
        try t.expect((try shellWarning(a, .toml, "operation", plain, false)) == null);
    // No argv is offered where it would not be the one meant, and no raw control byte is quoted.
    const ctl = try std.fmt.allocPrint(a, "./c.sh \"a{c}b\"", .{@as(u8, 1)});
    for ([_][]const u8{ "./c.sh 'unterminated", "./c.sh '' x", "./c.sh 'a\\b'", ctl }) |odd| {
        const w = (try shellWarning(a, .flags, "check", odd, false)).?;
        try t.expect(std.mem.indexOf(u8, w, "groups what they meant") == null);
        try t.expect(std.mem.indexOfScalar(u8, w, 1) == null);
    }
    // The define's commands in order; the argv form is not looked at.
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
        // A comment that holds a `"` of its own stays a comment.
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva put \"a b\"\"  # see \"docs\"\n", .want = "; write it as: operation = [\"./kva\", \"put\", \"a b\"]  # see \"docs\"" },
        // Nothing is offered that would not read back as what was written.
        .{ .text = head ++ "marker = say \"done\"\n", .want = null },
        .{ .text = head ++ "check = ./c.sh 'unterminated\n", .want = null },
        // Two readings with different argvs (`a b` or `a`, `b`): neither is offered — nor where
        // each word is quoted on its own and the shell reading's argv[0] is sane.
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"a\" \"b\"\n", .want = null },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"./kva\" \"put\" \"hello world\"\n", .want = null },
        .{ .text = "[world]\nstate = \"s\"\n[define]\noperation = \"tool\" \"a b\"\n", .want = null },
        // Nothing but a comment is not a value to fix.
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
    // A value or comment `textShown` would rewrite (raw C1, encoded C1) earns no line, so the
    // refusal never prints toml bytes the parser did not vet.
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
    // An ordinary trailing comment is not a cut, quoted or not.
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
    // A flag has no argv form: the advice names the toml's.
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
    // `$` at the end of a regex stays a `$`, inside double quotes too.
    const re = (try shellWarning(a, .toml, "check", "grep -E \"^x$\" f", false)).?;
    try t.expect(std.mem.indexOf(u8, re, "check = [\"grep\", \"-E\", \"^x$\", \"f\"]") != null);
    try t.expect((try shellWarning(a, .toml, "check", "sed s/$/x/ f", false)) == null);
}
