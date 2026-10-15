const std = @import("std");
const contract = @import("contract");
const config = @import("config.zig");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const report = @import("report.zig");
const cli = @import("cli.zig");

pub const ReplayCase = struct {
    schema: []const u8,
    case_version: u32,
    sideeye_version: []const u8,
    contract_version: u32,
    observe: ?[]const u8 = null,
    define: struct {
        state: []const u8,
        setup: ?config.Command = null,
        operation: config.Command,
        check: ?config.Command = null,
        marker: ?[]const u8 = null,
        expected_status: ?u8 = null,
        cwd: ?[]const u8 = null,
        scratch: ?[]const []const u8 = null,
    },
    k: u32,
    ops_total: u32,
    prefix_hash: []const u8,
    after_class: []const u8,
    after_path: []const u8,
    before_class: []const u8,
    before_path: []const u8,
    violation: []const u8,
};

fn jsonCommand(w: *std.ArrayList(u8), arena: std.mem.Allocator, cmd: config.Command) !void {
    switch (cmd) {
        .str => |s| try report.jsonString(w, arena, s),
        .argv => |a| {
            try w.append(arena, '[');
            for (a, 0..) |e, i| {
                if (i != 0) try w.appendSlice(arena, ", ");
                try report.jsonString(w, arena, e);
            }
            try w.append(arena, ']');
        },
    }
}

pub fn prefixHash(trace: engine.TraceInfo, k: u32, out: *[16]u8) bool {
    var h: u64 = 0xcbf29ce484222325;
    var seq: u32 = 1;
    while (seq <= k) : (seq += 1) {
        var found = false;
        for (trace.ops.items) |op| {
            if (!op.class.isKillPoint()) continue;
            // Every process's operations, for the reason `logicalAddress` carries (v15):
            // a number is a position in the run, so a prefix that skipped a child's
            // operations would hash a sequence the run never had — and would find no
            // record at all for a number a child holds, reporting the case as no longer
            // applying when nothing had changed.
            if (op.seq != seq) continue;
            for (op.class.name()) |ch| {
                h ^= ch;
                h *%= 0x100000001b3;
            }
            h ^= 0x1f; // separator, so ["ab","c"] and ["a","bc"] hash apart
            h *%= 0x100000001b3;
            found = true;
            break;
        }
        if (!found) return false;
    }
    _ = std.fmt.bufPrint(out, "{x:0>16}", .{h}) catch unreachable;
    return true;
}

/// case file. Returns null when nothing could be written — the FAIL report is the
/// product and must not die for the sake of its attachment.
pub fn writeCase(
    arena: std.mem.Allocator,
    work: []const u8,
    args: cli.Args,
    k: u32,
    ops_total: u32,
    trace: engine.TraceInfo,
    violation_name: []const u8,
) ?[]const u8 {
    var dbuf: [contract.max_path]u8 = undefined;
    const dz = std.mem.printSentinel(&dbuf, "{s}/cases", .{work}, 0) catch return null;
    _ = posix.mkdir(dz.ptr, 0o755); // EEXIST is fine; open below decides
    const addr = trace.logicalAddress(k);
    var hh: [16]u8 = undefined;
    if (!prefixHash(trace, k, &hh)) return null;

    var doc: std.ArrayList(u8) = .empty;
    const w = &doc;
    var nb: [16]u8 = undefined;
    // The version and the shape travel together (ADR 0019, the ADR 0014 law): a case
    // whose define carries the argv form is version 3; one spelled entirely in
    // strings stays version 2, byte-shaped exactly as every v2-era reader expects.
    const carries_argv = (args.operation.? == .argv) or
        (args.setup != null and args.setup.? == .argv) or
        (args.check != null and args.check.? == .argv);
    // A declared cwd is part of what the counterexample was found against, so it moves
    // the version the same way — and it takes precedence over the argv rule because a
    // version-3 reader would drop the field and replay the commands somewhere else.
    // A scratch declaration decides verdicts (ADR 0043), so it moves the version to 5, above
    // cwd for the reason cwd sits above argv: an older reader would drop the field and
    // judge a different question. A define that declares nothing keeps the case it always got.
    // The observation mode is the top rung (#691, ADR 0100), and only a mode other than the
    // default climbs it: a crash point is a number in that mode's count, so a replay under
    // another mode addresses a different operation. A `wrappers` case stays the version its
    // define asks for, byte for byte, so a reader before version 6 still replays it — the
    // cost ADR 0071 named for a version 6 falls only on the cases that need the field.
    const case_version: u32 = if (args.observe != .wrappers) 6 else if (args.scratch.len > 0) 5 else if (args.cwd != null) 4 else if (carries_argv) 3 else 2;
    w.appendSlice(arena, "{\n  \"schema\": \"sideeye/case\",\n  \"case_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{case_version}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"sideeye_version\": ") catch return null;
    report.jsonString(w, arena, cli.version) catch return null;
    w.appendSlice(arena, ",\n  \"contract_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}) catch return null) catch return null;
    if (case_version >= 6) {
        w.appendSlice(arena, ",\n  \"observe\": ") catch return null;
        report.jsonString(w, arena, args.observe.name()) catch return null;
    }
    w.appendSlice(arena, ",\n  \"define\": {\n    \"state\": ") catch return null;
    report.jsonString(w, arena, args.state.?) catch return null;
    if (args.setup) |s| {
        w.appendSlice(arena, ",\n    \"setup\": ") catch return null;
        jsonCommand(w, arena, s) catch return null;
    }
    w.appendSlice(arena, ",\n    \"operation\": ") catch return null;
    jsonCommand(w, arena, args.operation.?) catch return null;
    if (args.check) |c| {
        w.appendSlice(arena, ",\n    \"check\": ") catch return null;
        jsonCommand(w, arena, c) catch return null;
    }
    if (args.marker) |m| {
        w.appendSlice(arena, ",\n    \"marker\": ") catch return null;
        report.jsonString(w, arena, m) catch return null;
    }
    // Written only when it was declared, unlike `expected_status` above: an absent cwd
    // is not a default value the reader has to be told, it is the engine's own cwd — and
    // writing it anyway would push every case to version 4 and make every v2 and v3
    // reader refuse files whose defines are unchanged.
    if (args.cwd) |c| {
        w.appendSlice(arena, ",\n    \"cwd\": ") catch return null;
        report.jsonString(w, arena, c) catch return null;
    } else if (case_version >= 5) {
        w.appendSlice(arena, ",\n    \"cwd\": null") catch return null;
    }
    if (case_version >= 5) {
        w.appendSlice(arena, ",\n    \"scratch\": [") catch return null;
        for (args.scratch, 0..) |s, i| {
            if (i > 0) w.appendSlice(arena, ", ") catch return null;
            report.jsonString(w, arena, s) catch return null;
        }
        w.append(arena, ']') catch return null;
    }
    w.appendSlice(arena, ",\n    \"expected_status\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{args.expect_status orelse 0}) catch return null) catch return null;
    w.appendSlice(arena, "\n  },\n  \"k\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{k}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"ops_total\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{ops_total}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"prefix_hash\": ") catch return null;
    report.jsonString(w, arena, &hh) catch return null;
    w.appendSlice(arena, ",\n  \"after_class\": ") catch return null;
    report.jsonString(w, arena, if (addr.after) |a| a.class.name() else "(start)") catch return null;
    w.appendSlice(arena, ",\n  \"after_path\": ") catch return null;
    report.jsonString(w, arena, if (addr.after) |a| a.path else "") catch return null;
    w.appendSlice(arena, ",\n  \"before_class\": ") catch return null;
    report.jsonString(w, arena, if (addr.before) |b| b.class.name() else "(end)") catch return null;
    w.appendSlice(arena, ",\n  \"before_path\": ") catch return null;
    report.jsonString(w, arena, if (addr.before) |b| b.path else "") catch return null;
    w.appendSlice(arena, ",\n  \"violation\": ") catch return null;
    report.jsonString(w, arena, violation_name) catch return null;
    w.appendSlice(arena, "\n}\n") catch return null;

    const EEXIST: c_int = 17; // same value on Linux and Darwin
    var id: u32 = 1;
    while (id <= 999999) : (id += 1) {
        var pbuf: [contract.max_path]u8 = undefined;
        const pz = std.mem.printSentinel(&pbuf, "{s}/cases/{d:0>6}.json", .{ work, id }, 0) catch return null;
        const fd = posix.open(pz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o644));
        if (fd < 0) {
            // Only a taken id is worth trying past. An unwritable directory would
            // otherwise spin through a million opens on its way to "(not saved)".
            if (std.c._errno().* == EEXIST) continue;
            return null;
        }
        var off: usize = 0;
        while (off < doc.items.len) {
            const wn = posix.write(fd, doc.items[off..].ptr, doc.items.len - off);
            if (wn <= 0) {
                // A half-written case must not survive: it would both mislead a later
                // replay and permanently consume this id.
                _ = posix.close(fd);
                _ = posix.unlink(pz.ptr);
                return null;
            }
            off += @intCast(wn);
        }
        _ = posix.close(fd);
        return arena.dupe(u8, std.mem.span(pz.ptr)) catch null;
    }
    return null;
}

pub const Read = union(enum) { ok: ReplayCase, invalid: []const u8 };

/// Returns the refusal, never exits: the fuzz entry point calls it in-process.
pub fn read(arena: std.mem.Allocator, text: []const u8) Read {
    const parsed = std.json.parseFromSlice(ReplayCase, arena, text, .{}) catch
        return .{ .invalid = "the case file could not be parsed as a sideeye case" };
    const c = parsed.value;
    if (!std.mem.eql(u8, c.schema, "sideeye/case"))
        return .{ .invalid = "the file does not declare itself a sideeye case" };
    if (c.case_version < 1 or c.case_version > 6)
        return .{ .invalid = "this binary understands case schema versions 1, 2, 3, 4, 5 and 6 only" };
    const carries_argv = (c.define.operation == .argv) or
        (c.define.setup != null and c.define.setup.? == .argv) or
        (c.define.check != null and c.define.check.? == .argv);
    if (c.case_version < 3 and carries_argv)
        return .{ .invalid = "a case_version 1 or 2 file cannot carry an argv-form command; the array form arrived with version 3" };
    // malformed rather than read under a guessed contract (R1 finding). One
    // deliberate softness: a JSON `null` is indistinguishable from an absent
    // field after parsing, so a v1 file spelling `"expected_status": null`
    // passes — null is not a declaration, and the meaning ("0 was the
    // contract") is the same either way. A v2 `null` refuses like an absence.
    if (c.case_version == 1 and c.define.expected_status != null)
        return .{ .invalid = "a case_version 1 file cannot carry an expected_status declaration; it arrived with version 2" };
    if (c.case_version >= 2 and c.define.expected_status == null)
        return .{ .invalid = "a case_version 2, 3, 4, 5 or 6 file must carry define.expected_status; the case freezes the declaration" };
    if (c.case_version < 4 and c.define.cwd != null)
        return .{ .invalid = "a case_version 1, 2 or 3 file cannot carry a cwd declaration; it arrived with version 4" };
    if (c.case_version == 4 and c.define.cwd == null)
        return .{ .invalid = "a case_version 4 file must carry define.cwd; the version exists to freeze it" };
    // Version 5 (ADR 0043) carries the scratch declaration, which decides verdicts, and
    // it holds two independent optional fields where version 4 held one — so the gate
    // above cannot be copied: a v5 file without a cwd is not malformed. From version 5
    // a case spells both keys the ladder's top rungs introduced, `cwd` as null when
    // none was declared and `scratch` as a non-empty array, and the reader asks for
    // the KEY, which the typed parse above cannot see (an absent optional and a null
    // land in the same place), through a second, untyped parse of the same bytes. A
    if (c.case_version < 5 and c.define.scratch != null)
        return .{ .invalid = "a case_version 1, 2, 3 or 4 file cannot carry a scratch declaration; it arrived with version 5" };
    if (c.case_version < 6 and c.observe != null)
        return .{ .invalid = "a case_version 1, 2, 3, 4 or 5 file cannot carry an observation mode; it arrived with version 6" };
    if (c.case_version == 6) {
        const m = c.observe orelse return .{ .invalid = "a case_version 6 file must carry observe, `syscalls` or `supervised`; the version exists to freeze it" };
        const obs = contract.ObserveMode.parse(m) orelse return .{ .invalid = "a case_version 6 file's observe names no mode this binary knows; it must be `syscalls` or `supervised`" };
        if (obs == .wrappers) return .{ .invalid = "a case_version 6 file's observe must be `syscalls` or `supervised`: a case counted under the default is written at the version its define asks for" };
    }
    if (c.case_version == 5) {
        const decl = c.define.scratch orelse return .{ .invalid = "a case_version 5 file must carry define.scratch as a non-empty array; the version exists to freeze it" };
        if (decl.len == 0) return .{ .invalid = "a case_version 5 file must carry define.scratch as a non-empty array; the version exists to freeze it" };
    }
    if (c.case_version >= 5) {
        const raw = std.json.parseFromSlice(std.json.Value, arena, text, .{}) catch
            return .{ .invalid = "the case file could not be parsed as a sideeye case" };
        const def: std.json.Value = switch (raw.value) {
            .object => |o| o.get("define") orelse return .{ .invalid = "the case file has no define object" },
            else => return .{ .invalid = "the case file is not a JSON object" },
        };
        const has_cwd = switch (def) {
            .object => |o| o.contains("cwd"),
            else => false,
        };
        if (!has_cwd)
            return .{ .invalid = "a case_version 5 or 6 file must spell define.cwd, as null when none was declared: from version 5 both cwd and scratch are explicit" };
        // The typed parse reads an absent `scratch` and a JSON `null` alike, so the key and
        // its shape are asked of the untyped value. Version 5 already refused both through
        // the non-empty gate above; version 6, where empty is allowed, needs it here.
        const scratch_is_array = switch (def) {
            .object => |o| if (o.get("scratch")) |v| v == .array else false,
            else => false,
        };
        if (!scratch_is_array)
            return .{ .invalid = "a case_version 6 file must spell define.scratch as an array, empty when none was declared: from version 5 both cwd and scratch are explicit" };
    }
    return .{ .ok = c };
}

const test_case_v5 =
    \\{"schema":"sideeye/case","case_version":5,"sideeye_version":"1.10.0","contract_version":19,
    \\"define":{"state":"/s/state","operation":["tool","build"],"check":"/c/check.sh","cwd":null,"scratch":["m.yaml"],"expected_status":0},
    \\"k":7,"ops_total":7,"prefix_hash":"718642bf3a3cb330","after_class":"open","after_path":"/s/state/m.yaml",
    \\"before_class":"write","before_path":"/s/state/m.yaml","violation":"checker"}
;

fn testCaseWith(a: std.mem.Allocator, from: []const u8, to: []const u8) ![]const u8 {
    std.debug.assert(std.mem.indexOf(u8, test_case_v5, from) != null);
    return std.mem.replaceOwned(u8, a, test_case_v5, from, to);
}

test "read returns a valid case whole" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const c = read(a, test_case_v5).ok;
    try std.testing.expectEqual(@as(u32, 5), c.case_version);
    try std.testing.expectEqual(@as(u32, 7), c.k);
    try std.testing.expectEqualStrings("build", c.define.operation.argv[1]);
    try std.testing.expectEqualStrings("m.yaml", c.define.scratch.?[0]);
    try std.testing.expect(c.define.cwd == null);

    const v6 = try testCaseWith(a, "\"case_version\":5,", "\"case_version\":6,\"observe\":\"syscalls\",");
    const v6_empty = try std.mem.replaceOwned(u8, a, v6, "[\"m.yaml\"]", "[]");
    try std.testing.expectEqualStrings("syscalls", read(a, v6_empty).ok.observe.?);
}

test "read refuses with replay's sentences, in replay's order" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const T = struct { text: []const u8, says: []const u8 };
    const cases = [_]T{
        .{ .text = "{", .says = "the case file could not be parsed as a sideeye case" },
        .{ .text = try testCaseWith(a, "\"k\":7,", "\"k\":7,\"extra\":1,"), .says = "the case file could not be parsed as a sideeye case" },
        .{ .text = try testCaseWith(a, "sideeye/case", "other/case"), .says = "the file does not declare itself a sideeye case" },
        .{ .text = try testCaseWith(a, "\"case_version\":5,", "\"case_version\":7,"), .says = "this binary understands case schema versions 1, 2, 3, 4, 5 and 6 only" },
        .{ .text = try testCaseWith(a, "\"case_version\":5,", "\"case_version\":6,"), .says = "a case_version 6 file must carry observe, `syscalls` or `supervised`; the version exists to freeze it" },
        .{ .text = try testCaseWith(a, "\"case_version\":5,", "\"case_version\":6,\"observe\":\"wrappers\","), .says = "a case_version 6 file's observe must be `syscalls` or `supervised`: a case counted under the default is written at the version its define asks for" },
        .{ .text = try testCaseWith(a, "\"cwd\":null,", ""), .says = "a case_version 5 or 6 file must spell define.cwd, as null when none was declared: from version 5 both cwd and scratch are explicit" },
        .{ .text = try testCaseWith(a, "\"scratch\":[\"m.yaml\"],", ""), .says = "a case_version 5 file must carry define.scratch as a non-empty array; the version exists to freeze it" },
    };
    for (cases) |cs| try std.testing.expectEqualStrings(cs.says, read(a, cs.text).invalid);

    const twice = try std.mem.replaceOwned(u8, a, try testCaseWith(a, "sideeye/case", "other/case"), "\"case_version\":5,", "\"case_version\":7,");
    try std.testing.expectEqualStrings("the file does not declare itself a sideeye case", read(a, twice).invalid);
}
