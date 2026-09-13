//! The saved case: the counterexample a FAIL writes and a replay reads back.
//!
//! `src/case.zig` owns the case file's shape on both sides. `writeCase` produces it from the
//! resolved define, the crash point and the landing context — with `prefixHash`, the
//! fingerprint of the trace prefix that decides whether a later replay still addresses the
//! same operation, and `jsonCommand`, the JSON form of a define command that mirrors
//! `config.Command.jsonParse` — and `ReplayCase` is what `replay` parses it back into,
//! strictly: an unknown field is a case from a future schema, not something to skip. The
//! `case_version` rules (ADR 0009, ADR 0019 and the versions since) are this file's to keep;
//! `main.zig` decides when a case is written and what a replayed one may declare. Nothing
//! here prints a report line or exits.
//!
//! Third seam of #572 (ADR 0062), second half. Bodies moved from `main.zig` byte for byte on
//! 2026-09-13 with `pub` where `main.zig` reads them; `writeCase` spells `cli.Args` and
//! `cli.version` where `main.zig` had them bare — the qualifier class seam 3a declared. No
//! unit test holds these bodies directly (the acceptance suite pins the case format), so this
//! file is not a test root.
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
        /// Present exactly when the case is version 5 (ADR 0043), non-empty there. A
        /// version-5 file spells `cwd` too, as null when none was declared; that key's
        /// presence is checked on a second, untyped parse, since this one cannot tell
        /// an absent optional from a null.
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
    const case_version: u32 = if (args.scratch.len > 0) 5 else if (args.cwd != null) 4 else if (carries_argv) 3 else 2;
    w.appendSlice(arena, "{\n  \"schema\": \"sideeye/case\",\n  \"case_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{case_version}) catch return null) catch return null;
    w.appendSlice(arena, ",\n  \"sideeye_version\": ") catch return null;
    report.jsonString(w, arena, cli.version) catch return null;
    w.appendSlice(arena, ",\n  \"contract_version\": ") catch return null;
    w.appendSlice(arena, std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}) catch return null) catch return null;
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
