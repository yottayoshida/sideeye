//! The saved case: the counterexample a FAIL writes and a replay reads back.
//!
//! `src/case.zig` owns the case file's shape on both sides. `writeCase` produces it from the
//! resolved define, the crash point and the landing context — with `prefixHash`, the
//! fingerprint of the trace prefix that decides whether a later replay still addresses the
//! same operation, and `jsonCommand`, the JSON form of a define command that mirrors
//! `config.Command.jsonParse` — and `ReplayCase` is what `replay` parses it back into,
//! strictly: an unknown field is a case from a future schema, not something to skip. The
//! `case_version` rules (ADR 0009, ADR 0019 and the versions since) are this file's to keep,
//! and since #695 they are kept here in code too: `read` parses a case file's bytes and
//! applies every one of them, returning the case or the sentence replay refuses it with.
//! `main.zig` decides when a case is written, reads the file and refuses with what `read`
//! says. Nothing here prints a report line or exits.
//!
//! Third seam of #572 (ADR 0062), second half. Bodies moved from `main.zig` byte for byte on
//! 2026-09-13 with `pub` where `main.zig` reads them; `writeCase` spells `cli.Args` and
//! `cli.version` where `main.zig` had them bare — the qualifier class seam 3a declared.
//! `read` followed on 2026-10-10 (#695, ADR 0112), its refusals word for word. This file is a
//! test root since then: `read`'s unit tests are here, and its fuzz entry point is in
//! `src/fuzz.zig`. The acceptance suite still pins the case format end to end.
const std = @import("std");
const contract = @import("contract");
const config = @import("config.zig");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const report = @import("report.zig");
const cli = @import("cli.zig");

/// A saved counterexample (ADR 0009): the resolved define it was found against, the
/// crash point, and the landing context that decides whether a later replay still
/// addresses the same operation. Parsed strictly — an unknown field is a case from a
/// future schema, not something to skip.
pub const ReplayCase = struct {
    schema: []const u8,
    case_version: u32,
    sideeye_version: []const u8,
    contract_version: u32,
    /// Present exactly when the case is version 6 (#691, ADR 0100): the observation mode the
    /// crash point was counted under, `syscalls` or `supervised`. Beside `contract_version`
    /// and outside `define` because it is the same kind of fact — how the numbering `k` was
    /// produced — and because a `sideeye.toml` has no key for it (frozen surface 1). Absent,
    /// the file does not say: a case written since version 6 exists was counted under the
    /// default, `wrappers`, and one written before may have been counted under any mode — the
    /// limit #691 was about — so its replay takes the flag, or the default, as it always did.
    observe: ?[]const u8 = null,
    define: struct {
        state: []const u8,
        setup: ?config.Command = null,
        operation: config.Command,
        check: ?config.Command = null,
        marker: ?[]const u8 = null,
        // Absent in a case_version 1 file; absent means "exit 0 was the contract",
        // which is exactly what every v1 case was recorded under (ADR 0014).
        expected_status: ?u8 = null,
        /// Present exactly when the case is version 4, the way the argv form is present
        /// exactly in a version 3 or later file: the version moves because the field
        /// arrived, so a define that declared no cwd still saves as the version its other
        /// fields ask for. Always the resolved spelling.
        cwd: ?[]const u8 = null,
        /// Present exactly when the case is version 5 (ADR 0043) or 6 (ADR 0100): non-empty in
        /// version 5, which exists for it, and possibly empty in version 6, which exists for the
        /// observation mode. Both spell `cwd` too, as null when none was declared; those keys'
        /// presence is checked on a second, untyped parse, since this one cannot tell an absent
        /// optional from a null.
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

/// A define command as a bare JSON value, mirroring `config.Command.jsonParse`:
/// the string form is one JSON string, the argv form one array of strings. The two
/// functions are the write and read halves of the same shape — a case written here
/// parses back through there.
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

/// FNV-1a over the class names of the subject's counted operations 1..k, hex-encoded.
/// Classes only, deliberately: paths may legitimately differ between runs
/// (pid-embedded temp names), and the replay treats a path difference as a warning,
/// never as identity (ADR 0009).
/// Returns false when any of seq 1..k is missing from the trace: a numbering gap
/// means the recording itself is not a sequence this hash can vouch for, and hashing
/// only what happens to be present would let two differently-broken traces agree.
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

/// Write the counterexample to `<work>/cases/NNNNNN.json` and return its path. The id
/// is claimed with O_EXCL, so two runs over one work directory cannot silently share a
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
    const dz = std.fmt.bufPrintZ(&dbuf, "{s}/cases", .{work}) catch return null;
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
        // From version 5 `cwd` is explicit beside `scratch` (ADR 0043): `null` says "none
        // declared" in the file itself, so a reader can tell it from a key edited out.
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
    // Written even at the default (case_version 2): a case is a frozen contract, and
    // "0 because nothing was declared" and "0 by declaration" must replay identically
    // years later without consulting anything outside the file.
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
        const pz = std.fmt.bufPrintZ(&pbuf, "{s}/cases/{d:0>6}.json", .{ work, id }) catch return null;
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

/// What `read` makes of a case file's bytes: the case, or the sentence replay refuses it with.
/// Every refusal is `define_invalid`; the caller adds the reason.
pub const Read = union(enum) { ok: ReplayCase, invalid: []const u8 };

/// Parse and validate a saved case the way `replay` does, from the bytes alone (#695, ADR
/// 0112). Moved from `main.zig`'s replay branch, where each refusal was a `setupError` that
/// ended the process; each is now returned, word for word, and the caller ends the process
/// with it. The order of the checks is the order they had there, so the first broken law in a
/// file is still the one named. Reads nothing but `text`: the caller reads the file (and owns
/// the 1 MiB cap and the regular-file rule), and resolves paths against its directory after.
/// Allocates into `arena` and frees nothing — the caller's arena owns the case it returns.
pub fn read(arena: std.mem.Allocator, text: []const u8) Read {
    const parsed = std.json.parseFromSlice(ReplayCase, arena, text, .{}) catch
        return .{ .invalid = "the case file could not be parsed as a sideeye case" };
    const c = parsed.value;
    if (!std.mem.eql(u8, c.schema, "sideeye/case"))
        return .{ .invalid = "the file does not declare itself a sideeye case" };
    if (c.case_version < 1 or c.case_version > 6)
        return .{ .invalid = "this binary understands case schema versions 1, 2, 3, 4, 5 and 6 only" };
    // The same travel-together law, extended to the command shape (ADR 0019): the
    // argv form arrived with version 3, so an older file carrying it is not an
    // older file — it is malformed, and reading it under a guessed contract would
    // replay a define no version-2-era binary ever produced.
    const carries_argv = (c.define.operation == .argv) or
        (c.define.setup != null and c.define.setup.? == .argv) or
        (c.define.check != null and c.define.check.? == .argv);
    if (c.case_version < 3 and carries_argv)
        return .{ .invalid = "a case_version 1 or 2 file cannot carry an argv-form command; the array form arrived with version 3" };
    // The version and the declaration travel together (ADR 0014): a v1 file
    // carrying a declaration is not a v1 file, and a v2 file without one has
    // lost the very fact the version exists to freeze. Both are refused as
    // malformed rather than read under a guessed contract (R1 finding). One
    // deliberate softness: a JSON `null` is indistinguishable from an absent
    // field after parsing, so a v1 file spelling `"expected_status": null`
    // passes — null is not a declaration, and the meaning ("0 was the
    // contract") is the same either way. A v2 `null` refuses like an absence.
    if (c.case_version == 1 and c.define.expected_status != null)
        return .{ .invalid = "a case_version 1 file cannot carry an expected_status declaration; it arrived with version 2" };
    if (c.case_version >= 2 and c.define.expected_status == null)
        return .{ .invalid = "a case_version 2, 3, 4, 5 or 6 file must carry define.expected_status; the case freezes the declaration" };
    // The same law again, for the directory the define declared it runs in. A cwd is
    // part of what the counterexample was found against — replaying the same commands
    // somewhere else is replaying a different define — so the version moves with it.
    // Both directions, for the reason the two above give: a v3 file carrying a cwd is
    // malformed rather than old, and a v4 file without one has lost the fact the
    // version exists to freeze.
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
    // hand-edited v5 file that lost `cwd` refuses rather than replaying a define that
    // ran somewhere else. The entries themselves are validated where they are
    // normalised, in the apply block below, with the same refusals the flag gives.
    if (c.case_version < 5 and c.define.scratch != null)
        return .{ .invalid = "a case_version 1, 2, 3 or 4 file cannot carry a scratch declaration; it arrived with version 5" };
    // Version 6 (#691, ADR 0100) carries the observation mode, and only a mode other than the
    // default. It is a third independent optional fact, so it keeps version 5's law — every
    // key the ladder's top rungs introduced is spelled — with one change: `scratch` may be
    // the empty array there, because version 6 exists for the mode, not for scratch. Both
    // directions again: an older file carrying `observe` is malformed, and a version-6 file
    // without a mode it could not have been written for — absent, or the default — has
    // lost the fact the version exists to freeze.
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

// ---------------------------------------------------------------------------
// `read`'s unit tests (#695). The acceptance suite drives the same sentences through the
// binary; these hold the order and the wording without a container.

/// The shape of a case a FAIL writes today (spike/dogfood/2026-10-09-followups-2, bat), with
/// its paths shortened. Every key from version 5's law is spelled.
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

test "read returns a valid case whole (#695)" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const c = read(a, test_case_v5).ok;
    try std.testing.expectEqual(@as(u32, 5), c.case_version);
    try std.testing.expectEqual(@as(u32, 7), c.k);
    try std.testing.expectEqualStrings("build", c.define.operation.argv[1]);
    try std.testing.expectEqualStrings("m.yaml", c.define.scratch.?[0]);
    try std.testing.expect(c.define.cwd == null);

    // Version 6 carries a mode other than the default, and may spell scratch empty.
    const v6 = try testCaseWith(a, "\"case_version\":5,", "\"case_version\":6,\"observe\":\"syscalls\",");
    const v6_empty = try std.mem.replaceOwned(u8, a, v6, "[\"m.yaml\"]", "[]");
    try std.testing.expectEqualStrings("syscalls", read(a, v6_empty).ok.observe.?);
}

test "read refuses with replay's sentences, in replay's order (#695)" {
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

    // Order: a file broken twice is refused for the check replay ran first. Wrong schema AND
    // an unknown version names the schema, as the inline checks in main.zig did.
    const twice = try std.mem.replaceOwned(u8, a, try testCaseWith(a, "sideeye/case", "other/case"), "\"case_version\":5,", "\"case_version\":7,");
    try std.testing.expectEqualStrings("the file does not declare itself a sideeye case", read(a, twice).invalid);
}
