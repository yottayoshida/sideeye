const std = @import("std");
const contract = @import("contract");
const builtin = @import("builtin");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const config = @import("config.zig");
const mcp = @import("mcp.zig");
const boundary = @import("boundary.zig");
const defang = @import("defang.zig");
const capture = @import("capture.zig");
const files = @import("files.zig");
const cli = @import("cli.zig");
const sanitizeForReport = defang.sanitizeForReport;
const textShown = defang.textShown;
const appendSanitized = defang.appendSanitized;
const removeFile = files.removeFile;
const writeWholeFile = files.writeWholeFile;

/// the next flag. The help is printed by one `say`, so its size and this buffer move together.
var out_buf: [32 * 1024]u8 = undefined;
pub const say_capacity = out_buf.len;

fn colourFor(stdout_is_tty: bool, no_color: ?[]const u8, term: ?[]const u8) bool {
    if (!stdout_is_tty) return false;
    if (no_color) |v| if (v.len > 0) return false;
    if (term) |t| if (std.mem.eql(u8, t, "dumb")) return false;
    return true;
}

var colour_decided: ?bool = null;

fn colourOn() bool {
    if (colour_decided) |c| return c;
    const no_color: ?[]const u8 = if (posix.getenv("NO_COLOR")) |z| std.mem.span(z) else null;
    const term: ?[]const u8 = if (posix.getenv("TERM")) |z| std.mem.span(z) else null;
    const c = colourFor(posix.isatty(1) == 1, no_color, term);
    colour_decided = c;
    return c;
}

pub fn paint(comptime word: []const u8) []const u8 {
    const code = comptime if (std.mem.eql(u8, word, "PASS"))
        "32"
    else if (std.mem.eql(u8, word, "FAIL"))
        "31"
    else if (std.mem.eql(u8, word, "UNKNOWN"))
        "33"
    else if (std.mem.eql(u8, word, "SETUP ERROR"))
        "35"
    else
        @compileError("paint takes a verdict word: PASS, FAIL, UNKNOWN or SETUP ERROR");
    return if (colourOn()) "\x1b[1;" ++ code ++ "m" ++ word ++ "\x1b[0m" else word;
}

test "say's capacity is the 32 KiB the whole help is held under in cli.zig (#712, #717)" {
    try std.testing.expectEqual(@as(usize, 32 * 1024), say_capacity);
}

test "the verdict is coloured only on a terminal, without NO_COLOR, and not for TERM=dumb (#712)" {
    const T = std.testing;
    for ([_]?[]const u8{ null, "xterm", "dumb" }) |term| {
        for ([_]?[]const u8{ null, "", "1" }) |nc| {
            const want_on = (nc == null or nc.?.len == 0) and !(term != null and std.mem.eql(u8, term.?, "dumb"));
            try T.expectEqual(want_on, colourFor(true, nc, term));
            try T.expectEqual(false, colourFor(false, nc, term));
        }
    }
}

pub fn sayCaptureMarked(arena: std.mem.Allocator, path: []const u8, comptime marker: []const u8) void {
    if (capture.readFileAllocCapped(arena, path, 1024 * 1024, .{ .no_follow = true })) |text| {
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            say(marker ++ ": {s}\n", .{line});
        }
    } else {
        say(marker ++ ": (the gate's child output could not be read back from {s} — missing, unreadable, or over the 1 MiB re-emission cap; the capture file, if present, still holds it)\n", .{path});
    }
}

/// This used to `catch return` on overflow, so a FAIL whose paths pushed the text past
/// 16 KB exited 1 having printed nothing at all — the caller would see a bare exit code
/// and no counterexample. Formatting into a fixed buffer is still right for a tool that
pub fn say(comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&out_buf, fmt, args) catch {
        const msg = "sideeye: the report did not fit in the output buffer; paths are unusually long\n";
        _ = posix.write(2, msg.ptr, msg.len);
        return;
    };
    var off: usize = 0;
    while (off < s.len) {
        const w = posix.write(1, s[off..].ptr, s.len - off);
        // A truncated report reads as a complete one — the reader has no way to know a
        // line was cut. Nothing can be said about it on stdout, which is the stream that
        // just failed, so it goes to stderr. Found by the same-class scan that this
        if (w <= 0) {
            const msg = "sideeye: the report was cut short; stdout stopped accepting output\n";
            _ = posix.write(2, msg.ptr, msg.len);
            return;
        }
        off += @intCast(w);
    }
}

pub var oracle_note: []const u8 = initialOracleNote(.unparsed);

pub var oracle_verified: bool = false;
/// Set instead of `oracle_verified`, never beside it, and only where a run's writing
/// children were admitted as crash points: the completeness comparison is the subject's
/// account against the oracle's view of the subject, so a crash point performed by a child
/// is one the oracle placed and ordered but did not compare operation by operation. "Both
pub var oracle_verified_subject_only: bool = false;
pub var metadata_note: []const u8 = initialMetadataNote(.unparsed, false);
var oracle_asked: OracleAsked = .unparsed;

const OracleAsked = union(enum) {
    unparsed,
    named: boundary.BoundaryEvidence.Kind,
    none,
};

fn initialOracleNote(asked: OracleAsked) []const u8 {
    return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read",
        // The flag is named so a reader can tell which observer was asked for; the two
        // phrases are matched whole by spike/acceptance.sh (2fc, 2fd, 2fi), not by the
        // `--oracle` prefix they share.
        .named => |kind| switch (kind) {
            .strace => "not compared: --oracle was named, and this run stopped before the comparison",
            .fs_usage => "not compared: --oracle-fs-usage was named, and this run stopped before the comparison",
        },
        .none => "not run (no --oracle given)",
    };
}

fn initialMetadataNote(asked: OracleAsked, supervised: bool) []const u8 {
    if (supervised) return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read; the supervising engine is not notified of ownership/permission/timestamp calls, so only a completed oracle account could show them",
        .named => |kind| switch (kind) {
            .strace => "not established: --oracle was named, and this run stopped before its metadata account was completed; the supervising engine is not notified of ownership/permission/timestamp calls",
            .fs_usage => "not established: --oracle-fs-usage was named, and this run stopped before its metadata account was completed; the supervising engine is not notified of ownership/permission/timestamp calls",
        },
        .none => "not observable (no oracle ran; the supervising engine is not notified of ownership/permission/timestamp calls)",
    };
    return switch (asked) {
        .unparsed => "not established: this run stopped while its arguments were still being read; the shim does not interpose ownership/permission/timestamp calls, so only a completed oracle account could show them",
        // "before its metadata account was completed", not "before its capture was read":
        // the comparison block reads the capture and can refuse on it before
        // `metadata_note` is assigned, and this wording has to stay true there too.
        .named => |kind| switch (kind) {
            .strace => "not established: --oracle was named, and this run stopped before its metadata account was completed; the shim does not interpose ownership/permission/timestamp calls",
            .fs_usage => "not established: --oracle-fs-usage was named, and this run stopped before its metadata account was completed; the shim does not interpose ownership/permission/timestamp calls",
        },
        .none => "not observable (no oracle ran; the shim does not interpose ownership/permission/timestamp calls)",
    };
}

pub fn noteOracle(asked: OracleAsked) void {
    oracle_note = initialOracleNote(asked);
    oracle_asked = asked;
    metadata_note = initialMetadataNote(asked, false);
}
/// Re-derive the metadata account once the observation mode is known (#217). The parser
/// records the oracle before the mode is read, so the account it wrote names the shim;
/// called before any run, so no comparison's account is overwritten.
pub fn noteObserver(supervised: bool) void {
    metadata_note = initialMetadataNote(oracle_asked, supervised);
}
pub var checker_note: []const u8 = checkerNoteFor(.unparsed);
pub var l1_note: []const u8 = l1NoteFor(.unparsed);

/// optional fields (#711, ADR 0096). Each is set on the line that writes the number into its
/// sentence, from the same value, and stays `null` — the field absent — until then: a run that
/// never reached the comparison, or never declared a checker, says nothing rather than zero.
pub var oracle_operations_agreed: ?usize = null;
pub var checker_declared: ?bool = null;
pub var checker_worlds: ?usize = null;
/// Whether the recording run's process account is a measurement (#711): set once every check on
/// the recording's trace has held, at the line `l0_judged_paths_touched` is set on, for that
/// field's reason. A refusal on a trace cut short, renumbered or never announced carries counts
/// read from part of it, so the `processes_*` fields are absent there rather than partial.
pub var processes_measured: bool = false;

const Declared = enum {
    unparsed,
    named,
    none,
};

pub fn checkerNoteFor(d: Declared) []const u8 {
    return switch (d) {
        .unparsed => "not established: this run stopped while its arguments or define were still being read",
        .named => "configured; this run stopped before the checker ran",
        // Byte for byte the pre-#352 wording; docs/report-schema.md and acceptance pin it.
        .none => "none configured",
    };
}

pub fn l1NoteFor(d: Declared) []const u8 {
    return switch (d) {
        .unparsed => "not established: this run stopped while its arguments or define were still being read",
        .named => "marker configured; the recording run has not been scanned yet",
        // Byte for byte the pre-#352 wording; docs/cli.md and docs/report-schema.md show it.
        .none => "no marker configured",
    };
}

/// "configured" where one came and "none configured" where none did (#352). Called at the
/// line each mode's last source has been read by — right after the parse loop when neither
/// a replayed case nor a toml follows, after the case in replay, after the toml under
/// `--config`. Not later: the required-flag refusals and the marker vet sit after all three,
/// and a run refused there with nothing declared must say "none", not "not established".
pub fn settleDeclared(has_check: bool, has_marker: bool) void {
    checker_declared = has_check;
    checker_note = checkerNoteFor(if (has_check) .named else .none);
    l1_note = l1NoteFor(if (has_marker) .named else .none);
}
pub var l1_configured: bool = false;
pub var l0_note: []const u8 = "not classified (the run was refused before L0 classification)";

pub var attributed_to_rename: usize = 0;
pub var l0_history_count: u32 = 0;
pub var case_note: []const u8 = "(none)";

/// **It is the observer's vocabulary, never the target's** — which matters because the
/// text report prints this value without passing it through `sanitizeForReport`, unlike
/// every path-shaped string beside it. Two producers hold that line, and neither is
/// visible from here: `src/oracle.zig`'s `syscallName` returns only `[A-Za-z0-9_]+`
/// (its loop rejects anything else), and `src/fsusage.zig` appends `ln.call`, which by
/// then has been matched against `classOf`'s table — a member of that table or its
/// `_nocancel` variant, never free text from the capture. A third producer would have to
/// keep that property; the alignment tests on both sides are where a new one would be
/// noticed, not here.
pub var divergence_syscall: []const u8 = "";
pub var setup_status: ?posix.Term = null;
pub var replay_note: []const u8 = "-";
pub var evidence_note: []const u8 = "-";
pub var crash_points: u32 = 0;
pub var explored: u32 = 0;
pub var violations: u32 = 0;
pub var expected_status_val: u8 = 0;
pub var command_cwd: ?[]const u8 = null;
pub var command_cwd_declared: bool = false;
pub var apparatus_declared: []const []const u8 = &.{};

pub var scratch_declared: []const []const u8 = &.{};

pub const max_judged_paths_listed: usize = 1000;

/// The entry ceiling alone does not bound the report. `contract.max_path` is 4096, so a
/// thousand entries is four megabytes of names before escaping, and `jsonString` expands a
/// control byte to `\uXXXX` and an invalid UTF-8 byte to `\ufffd` — six bytes each. **The MCP
/// server reads the report with a 4 MiB cap** (`mcp.zig`) and answers a larger one with a tool
/// error, so without this a wide enough state tree would turn a real verdict into "sideeye
/// produced no report". Before this field existed nothing in the report grew with the target's
pub const max_judged_paths_bytes: usize = 64 * 1024;

pub var l0_judged_paths: []const []const u8 = &.{};

pub var l0_judged_paths_omitted: u32 = 0;

/// Whether the run reached L0 classification. Not derivable from the two above: a run whose
/// judged set is legitimately empty — a define that declared everything scratch — publishes an
/// empty array with nothing omitted, and that is a different fact from never having classified.
pub var l0_classified: bool = false;

/// that ended other than they began, or that a crash point named. Null until measured, which
/// happens once every check on the recording's trace has held (the last is a contained run's
/// cgroup account), so a refusal on an untrustworthy trace carries none. Zero beside a
pub var l0_judged_paths_touched: ?u32 = null;

pub var recovery_note: ?[]const u8 = null;

pub const RecoveryResultJson = struct {
    result: contract.RecoveryResult,
    ms: u64,
    command_exit: ?u8,
};

pub var recovery_earliest: ?RecoveryResultJson = null;
pub var recovery_checker_earliest: ?RecoveryResultJson = null;

pub var crash_state_left: ?bool = null;
pub var crash_state_note: ?[]const u8 = null;

fn apparatusHasUnchecked() bool {
    for (apparatus_declared) |e| if (config.apparatusUnchecked(e)) return true;
    return false;
}

pub fn errnoName(en: c_int) []const u8 {
    if (en == posix.EACCES) return " EACCES";
    if (en == posix.EPERM) return " EPERM";
    if (en == posix.ENOENT) return " ENOENT";
    if (en == posix.EIO) return " EIO";
    if (en == posix.ELOOP) return " ELOOP";
    return "";
}

/// **Typed to `SnapshotError`, with no `else`, on purpose.** Taking `anyerror` and
/// defaulting to `what` would compile cleanly when a member is added to that error set,
/// and the new member would then produce the bare call-site wording — the pre-#351
/// behaviour this function exists to remove — while still being classified
/// `state_unsnapshotable` whether or not that is the right reason for it. Exhaustiveness
/// turns that silent regression into a build failure — measured: deleting the `TooDeep`
/// arm now fails to compile, where before it left every check green and the message bare.
///
/// `OutOfMemory` is `unreachable` here rather than absent, which states the carve-out at
/// the point a reader meets the switch. **It does not enforce it**: deleting the guard
/// above still builds, and the arm would then be reached at run time on a real allocation
/// failure. Nothing in the tree can produce that, so the carve-out is unfalsified — said
/// here rather than left for someone to assume the type checked it.
pub fn snapshotDetail(ja: std.mem.Allocator, e: engine.SnapshotError, what: []const u8, diag: *engine.SnapshotDiag) []const u8 {
    return switch (e) {
        error.FileTooLarge => if (diag.file.size) |sz|
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} ({d} bytes, cap {d}); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel.get()), sz, engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment"
        else
            std.fmt.allocPrint(ja, "a state file is too large for byte-level judgment: {s} (over the {d}-byte cap); the state tree must hold files the judgment can hold in memory", .{ textShown(ja, diag.file.rel.get()), engine.max_state_file_bytes }) catch "a state file is too large for byte-level judgment",
        // walking for the real figures. No entry name appears: the walk stops at whatever
        // `readdir` happened to reach, so a "largest so far" would be a different name on
        // a different filesystem.
        error.TreeTooLarge => std.fmt.allocPrint(ja, "the state tree is too large to snapshot: holding it reached {d} bytes of memory against a {d}-byte ceiling, after reading {d} bytes of content across {d} entries; the walk stopped there, so those count what was read and not the tree — `du -sb <state>` and `find <state> -mindepth 1 | wc -l` show the whole of it", .{ diag.tree.reached, engine.max_state_tree_bytes, diag.tree.content, diag.tree.entries }) catch "the state tree is too large to snapshot",
        // "deeper than", not "cap": the walk compares with a strict `>`, so a tree of
        // exactly this many levels passes and the next one does not.
        error.TooDeep => std.fmt.allocPrint(ja, "{s}: the state tree is nested deeper than the {d} levels the snapshot walks", .{ what, engine.max_depth }) catch what,
        // The buffer holds the state root, a separator and the entry's relative path, so
        // a long `--state` prefix reaches this with a short name inside the tree — saying
        // "a path inside the state tree" would send the operator to look at the wrong
        // half. And the bound is on the whole spelling INCLUDING its terminator, so a
        // path of exactly this many bytes already fails: "at least", not "longer than",
        // for the same reason `max_depth`'s message says "deeper than" and not "cap".
        error.PathTooLong => std.fmt.allocPrint(ja, "{s}: the state root and an entry inside it spell a path of at least {d} bytes, which is the limit the snapshot can hold", .{ what, contract.max_path }) catch what,
        error.ReadFailed => blk: {
            const rel = diag.entry.rel.get();
            if (rel.len == 0) break :blk std.fmt.allocPrint(ja, "{s}: a file or symlink inside the state tree could not be read", .{what}) catch what;
            const kind: []const u8 = if (diag.entry.kind == .symlink) "symlink" else "file";
            if (diag.entry.errno) |en| {
                break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be read ({s}; errno {d}{s})", .{ what, textShown(ja, rel), kind, en, errnoName(en) }) catch what;
            }
            break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be read ({s})", .{ what, textShown(ja, rel), kind }) catch what;
        },
        error.ClassifyFailed => blk: {
            const rel = diag.entry.rel.get();
            if (rel.len == 0) break :blk std.fmt.allocPrint(ja, "{s}: an entry inside the state tree could not be classified as a file, directory or symlink", .{what}) catch what;
            break :blk std.fmt.allocPrint(ja, "{s}: {s} could not be classified as a file, directory or symlink", .{ what, textShown(ja, rel) }) catch what;
        },
        error.MountInside => mountInsideDetail(ja, what, diag.mount.get(), diag.mount.get().len == 0),
        error.EntriesNotSortedUnique => std.fmt.allocPrint(ja, "{s}: the snapshot's own entry list came out unsorted or holding duplicates — that is a defect in sideeye, not in the state tree", .{what}) catch what,
        error.OutOfMemory => unreachable,
    };
}

pub fn mountInsideDetail(ja: std.mem.Allocator, what: []const u8, rel: []const u8, unlisted: bool) []const u8 {
    const way = "Unmount it, or point the state at a directory with nothing mounted inside it";
    if (rel.len > 0)
        return std.fmt.allocPrint(ja, "{s}: {s} is a mount point or another device inside the state directory. Sideeye empties and rebuilds the state directory for every world, and does not reach into what is mounted inside it. {s}", .{ what, textShown(ja, rel), way }) catch what;
    if (unlisted)
        return std.fmt.allocPrint(ja, "{s}: the mount table (/proc/self/mountinfo) could not be read, so nothing shows that the state directory, which Sideeye empties for every world, has nothing mounted inside it. Run where /proc is mounted and readable", .{what}) catch what;
    return std.fmt.allocPrint(ja, "{s}: a directory inside the state directory is on another device (a mount, or a btrfs subvolume). Sideeye empties and rebuilds the state directory for every world, and does not reach into what is mounted inside it. {s}", .{ what, way }) catch what;
}

test "a mount inside the state is named when it is known, and the unread table is said apart from it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const named = mountInsideDetail(a, "could not snapshot the initial state", "sub", false);
    try std.testing.expect(std.mem.indexOf(u8, named, "sub is a mount point or another device inside the state directory") != null);
    try std.testing.expect(std.mem.indexOf(u8, named, "Unmount it") != null);
    const unread = mountInsideDetail(a, "could not snapshot the initial state", "", true);
    try std.testing.expect(std.mem.indexOf(u8, unread, "/proc/self/mountinfo") != null);
    try std.testing.expect(std.mem.indexOf(u8, unread, "Unmount it") == null);
    const device = mountInsideDetail(a, "could not restore the state directory", "", false);
    try std.testing.expect(std.mem.indexOf(u8, device, "on another device") != null);
}

pub fn exit126Note(code: anytype) []const u8 {
    return if (code == 126) "; 126 is also the code the engine's own fork stub uses for a child it could not arrange before exec — if that was it, a line on the engine's stderr names the call and the errno" else "";
}

test "exit126Note speaks only for 126" {
    try std.testing.expectEqualStrings("", exit126Note(@as(u8, 1)));
    try std.testing.expectEqualStrings("", exit126Note(@as(u8, 127)));
    try std.testing.expect(std.mem.startsWith(u8, exit126Note(@as(u8, 126)), "; 126 is also the code"));
}

const setup_line_max: usize = 200;

/// Backing store for the out-of-memory sentence in `setupOutputDetail`, at file scope
/// because that sentence outlives the call that builds it.
var setup_oom_buf: [contract.max_path + 64]u8 = undefined;

/// The clause a SETUP_ERROR adds about what the failing `--setup` wrote (#483).
///
/// Three answers, never two. The issue's complaint is that the observation "is not merely
/// unreported; it is gone", and collapsing "could not read it back" into "wrote nothing"
/// would put a second, quieter version of that same loss into the fix: the run would
/// assert something about a file it failed to open. `snapshotRefusal`'s neighbour at the
/// Sanitised once at the end, like `unresolvedDetail` and `withOracleCapture` in
/// `boundary.zig`, rather than per field — and it is needed here more than there, because
/// `setupError` prints its detail through `say` with no defang of its own, and every byte of the line
/// is the target's. One choke point also means one spelling: `textShown` per field and
/// `sanitizeForReport` at the end defang differently, so mixing them put two renderings of
/// a control byte in the same sentence.
pub fn setupOutputDetail(arena: std.mem.Allocator, path: []const u8) []const u8 {
    // Every `catch` below lands here rather than on `""`. An exhausted arena would
    // otherwise turn the refusal back into the bare `--setup exited 7` this issue is
    // about, and it would do it silently — the one failure mode where saying less looks
    // exactly like a version that was never fixed. `unresolvedDetail` takes a fallback
    // The buffer is at file scope, and that is the whole point of it being there. A first
    // version declared it here, which returns a slice of this function's frame to a caller
    // that reads it after the frame is gone — the exact shape `unresolved_kind.withFd`'s
    // doc warns about two files away, written the same day. Safe as a global because every
    // reader of the result is on the way to `setupError`, which is `noreturn`: there is no
    // second refusal to overwrite it, and no thread that could be composing another.
    const oom = std.fmt.bufPrint(
        &setup_oom_buf,
        "; what it wrote could not be described (out of memory); the capture is at {s}",
        .{path},
    ) catch "; what it wrote could not be described (out of memory)";
    const composed = switch (capture.readSetupCapture(arena, path)) {
        .unreadable => std.fmt.allocPrint(arena, "; its output could not be read back from {s}", .{path}) catch return oom,
        .empty => blk: {
            // for the sentence to name it. Removed here because this is the only place
            // that knows: `setupErrorFmt` never returns, so the failing path has no line
            // after this one, and the MCP adapter hands every call the same `--work` —
            // zero-byte pid-named files would accumulate there without bound.
            removeFile(path);
            break :blk "; it wrote nothing";
        },
        .line => |l| blk: {
            const cut = mcp.cutOnBoundary(l, setup_line_max);
            break :blk std.fmt.allocPrint(
                arena,
                "; its last output line was: {s}{s} (all of it is in {s})",
                .{ cut, if (cut.len < l.len) "..." else "", path },
            ) catch return oom;
        },
    };
    return sanitizeForReport(arena, composed) catch oom;
}

test "setupOutputDetail separates read failure, empty output, and a line — and defangs it (#483)" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var pb: [contract.max_path]u8 = undefined;
    const path = std.fmt.bufPrint(&pb, ".zig-cache/tmp-setupout-{d}.txt", .{posix.getpid()}) catch unreachable;
    defer removeFile(path);

    removeFile(path);
    const missing = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, missing, "could not be read back") != null);
    try t.expect(std.mem.indexOf(u8, missing, "wrote nothing") == null);

    try t.expect(writeWholeFile(path, &.{""}));
    const empty = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, empty, "wrote nothing") != null);
    try t.expect(std.mem.indexOf(u8, empty, "could not be read back") == null);
    try t.expect(capture.readSetupCapture(arena, path) == .unreadable);

    try t.expect(writeWholeFile(path, &.{"opening\nthe setup could not find its input\n"}));
    const line = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, line, "the setup could not find its input") != null);
    try t.expect(std.mem.indexOf(u8, line, "all of it is in") != null);

    // The control bytes are asserted, not the newline. A first version of this test wrote
    // `"x\nUNKNOWN  kill_did_not_land\n"` and checked that `"\nUNKNOWN"` was absent — but
    // `lastNonEmptyLine` splits on `'\n'`, so no return value of it can ever contain one.
    // That assertion held with `textShown` deleted outright (measured), which makes it a
    // check on the splitter rather than on the defang. ESC and CR survive the split, so
    // they are what proves the defang ran; the `foreignTouchDetail` test (in `boundary.zig`
    // since #572) has used ESC for the same reason since #484.
    try t.expect(writeWholeFile(path, &.{"safe\n\x1b[1mUNKNOWN  kill_did_not_land\rmore\n"}));
    const forged = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOfScalar(u8, forged, 0x1b) == null);
    try t.expect(std.mem.indexOfScalar(u8, forged, '\r') == null);
    try t.expect(std.mem.indexOf(u8, forged, "\nUNKNOWN") == null);
    try t.expect(std.mem.indexOf(u8, forged, "kill_did_not_land") != null);

    const ctrl = &@as([setup_line_max + 20]u8, @splat(0x01));
    try t.expect(writeWholeFile(path, &.{ctrl}));
    const defanged = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOfScalar(u8, defanged, 0x01) == null);
    try t.expect(std.mem.indexOf(u8, defanged, "\\x01") != null);
    try t.expect(defanged.len > setup_line_max);

    const long = &@as([setup_line_max + 50]u8, @splat('E'));
    try t.expect(writeWholeFile(path, &.{long}));
    const clamped = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, clamped, "...") != null);
    // Not `clamped.len < long.len`: the sentence carries a prefix and the file's path as
    // well, so its total length says nothing about whether the line was cut. What the
    // clamp promises is that the whole line is not in there.
    try t.expect(std.mem.indexOf(u8, clamped, long) == null);
    try t.expect(std.mem.indexOf(u8, clamped, &@as([setup_line_max]u8, @splat('E'))) != null);

    // The same reader the success path deletes on. It has to agree with the sentences
    // above about what "nothing" means, or a setup would be told it wrote nothing while
    // its file was kept (or the reverse).
    try t.expect(writeWholeFile(path, &.{""}));
    try t.expect(capture.readSetupCapture(arena, path) == .empty);
    try t.expect(writeWholeFile(path, &.{"\n \n"}));
    try t.expect(capture.readSetupCapture(arena, path) == .empty);
    try t.expect(writeWholeFile(path, &.{"using a stale fixture\n"}));
    try t.expectEqualStrings("using a stale fixture", capture.readSetupCapture(arena, path).line);
    removeFile(path);
    try t.expect(capture.readSetupCapture(arena, path) == .unreadable);

    // to read after the call that built them has returned. A stack-local buffer makes
    // this a read of a dead frame, which no assertion can be relied on to catch: the
    // check that matters is that the sentence survives the return at all.
    try t.expect(writeWholeFile(path, &.{"something"}));
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const starved = setupOutputDetail(failing.allocator(), path);
    try t.expect(std.mem.indexOf(u8, starved, "out of memory") != null);
    try t.expect(std.mem.indexOf(u8, starved, path) != null);
    // Read again after another call has had the chance to reuse the frame.
    var failing2 = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    _ = setupOutputDetail(failing2.allocator(), path);
    try t.expect(std.mem.indexOf(u8, starved, "out of memory") != null);
    // Naming the buffer is the assertion. Moving it back into `setupOutputDetail` — the
    // defect this test exists for — stops compiling here rather than failing at run time,
    // which matters because the run-time failure is undefined behaviour: restoring the
    // stack-local version and running the suite was measured green. A test that can only
    // observe the bug by luck is not what pins it; the reference is.
    try t.expect(std.mem.indexOf(u8, &setup_oom_buf, "out of memory") != null);
    try t.expect(std.mem.indexOf(u8, &setup_oom_buf, path) != null);

    removeFile(path);
    var db: [contract.max_path]u8 = undefined;
    const dz = try std.mem.printSentinel(&db, "{s}", .{path}, 0);
    try t.expect(posix.mkdir(dz.ptr, @as(c_uint, 0o755)) == 0);
    defer _ = posix.rmdir(dz.ptr);
    const dir = setupOutputDetail(arena, path);
    try t.expect(std.mem.indexOf(u8, dir, "could not be read back") != null);
}

pub fn buildL0Note(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
    const base = buildL0NoteBase(arena, plan);
    if (plan.scratch.len == 0) return base;
    var names: std.ArrayList(u8) = .empty;
    var listed: u32 = 0;
    for (plan.scratch) |p| {
        if (listed == 3) break;
        if (listed > 0) names.appendSlice(arena, ", ") catch return base;
        appendSanitized(&names, arena, p) catch return base;
        listed += 1;
    }
    if (plan.scratch.len > listed) {
        const more = std.fmt.allocPrint(arena, " (+{d} more)", .{plan.scratch.len - listed}) catch return base;
        names.appendSlice(arena, more) catch return base;
    }
    return std.fmt.allocPrint(arena, "{s}; {d} path(s) matched by scratch, not judged (declared: {s})", .{ base, plan.scratch_matched, names.items }) catch base;
}

/// **The plan is the only argument, and that is the design.** The set is not "the post
/// snapshot minus scratch": `classifyWith` keeps a path only where pre and post BOTH hold it
/// and both kinds are ones the built-in invariants compare. A projection handed a snapshot
/// could quietly answer the wrong question; one handed the plan cannot reach a snapshot to
/// get it wrong (`rules/memory` calls this preferring impossible over detected).
///
/// The paths are duped into the caller's arena rather than borrowed. `PlannedFile.rel`
/// borrows from the pre snapshot, which `main` frees on a defer of its own; the report is
/// built before that today, and this removes the coupling rather than relying on it.
pub fn publishJudgedPaths(arena: std.mem.Allocator, plan: engine.L0Plan) void {
    l0_classified = true;
    const total = plan.files.items.len;
    // Both ceilings, whichever binds first, decided before anything is allocated so the
    // array's length and the omitted count are two readings of one number.
    var listed: usize = 0;
    var bytes: usize = 0;
    while (listed < total and listed < max_judged_paths_listed) : (listed += 1) {
        const next = bytes + plan.files.items[listed].rel.len;
        if (next > max_judged_paths_bytes) break;
        bytes = next;
    }
    // An allocation failure must not turn into a silent lie. The count stays true and every
    // path reads as one this report did not name, which is exactly what happened.
    const out = arena.alloc([]const u8, listed) catch return omitAll(total);
    for (out, plan.files.items[0..listed]) |*slot, f| {
        slot.* = arena.dupe(u8, f.rel) catch return omitAll(total);
    }
    l0_judged_paths = out;
    l0_judged_paths_omitted = countedOmitted(total - listed);
}

fn omitAll(total: usize) void {
    l0_judged_paths = &.{};
    l0_judged_paths_omitted = countedOmitted(total);
}

/// Saturating rather than `@intCast`: the field is a count a reader compares against zero,
/// and a tree wide enough to overflow it would take the report down with a panic instead.
fn countedOmitted(n: usize) u32 {
    return if (n > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(n);
}

fn buildL0NoteBase(arena: std.mem.Allocator, plan: engine.L0Plan) []const u8 {
    const standard = plan.files.items.len - @as(usize, plan.history_count);
    if (plan.history_count == 0) {
        // "path(s)", not "file(s)": since #122 the judged pairs include symlinks and
        // kind-changed pairs, and a stow-shaped PASS would otherwise claim to have
        // judged N files over a directory holding none.
        return std.fmt.allocPrint(arena, "{d} path(s) judged pre-or-post", .{standard}) catch "classified";
    }
    var names: std.ArrayList(u8) = .empty;
    var listed: u32 = 0;
    for (plan.files.items) |f| {
        if (f.form != .history) continue;
        if (listed == 3) break;
        if (listed > 0) names.appendSlice(arena, ", ") catch return "classified";
        appendSanitized(&names, arena, f.rel) catch return "classified";
        listed += 1;
    }
    if (plan.history_count > listed) {
        const more = std.fmt.allocPrint(arena, " (+{d} more)", .{plan.history_count - listed}) catch return "classified";
        names.appendSlice(arena, more) catch return "classified";
    }
    return std.fmt.allocPrint(
        arena,
        "{d} path(s) judged pre-or-post; {d} file(s) judged by the history form (appended tails not judged): {s}",
        .{ standard, plan.history_count, names.items },
    ) catch "classified";
}

/// Comptime rather than a runtime join, deliberately: the old functions returned static
/// strings and allocate nothing, and **four of the five** call sites are inside format
/// strings where an allocation failure has nowhere to go. The tables cost nothing at
/// runtime and keep the output the same bytes it was.
const not_tested_always = [_][]const u8{ "power loss", "torn writes", "concurrent processes" };
const not_tested_history = "appended tails (files under the history form)";
const not_tested_l1 = "post-only file contents (L1 checks existence only; post-only link targets are judged)";
const not_tested_scratch = "declared scratch paths (neither bytes nor presence judged)";

const not_tested_conditions = [_][]const u8{ not_tested_history, not_tested_l1, not_tested_scratch };
const not_tested_variants = 1 << not_tested_conditions.len;

/// Go all refuse". A `\xNN` escape in a Zig literal reaches this directly, so without
/// this clause an item could build clean and ship a JSON document no parser accepts --
/// measured, before the clause existed.
fn notTestedNeedsEscaping(s: []const u8) bool {
    for (s) |c| if (c == '"' or c == '\\' or c < 0x20) return true;
    return !std.unicode.utf8ValidateSlice(s);
}

// The JSON rendering quotes each item and does nothing else, which is correct only while
// no item contains a quote, a backslash or a control byte. Rather than carry a second
comptime {
    for (not_tested_always) |item| {
        if (notTestedNeedsEscaping(item)) @compileError("not-tested item needs JSON escaping: " ++ item);
    }
    for (not_tested_conditions) |item| {
        if (notTestedNeedsEscaping(item)) @compileError("not-tested item needs JSON escaping: " ++ item);
    }
}

fn notTestedList(comptime variant: usize) []const []const u8 {
    comptime {
        var out: []const []const u8 = &not_tested_always;
        for (not_tested_conditions, 0..) |item, i| {
            if (variant & (@as(usize, 1) << i) != 0) out = out ++ [_][]const u8{item};
        }
        return out;
    }
}

fn notTestedJoined(comptime variant: usize, comptime quoted: bool) []const u8 {
    comptime {
        var out: []const u8 = if (quoted) "[" else "";
        for (notTestedList(variant), 0..) |item, i| {
            if (i != 0) out = out ++ ", ";
            out = out ++ if (quoted) "\"" ++ item ++ "\"" else item;
        }
        return out ++ if (quoted) "]" else "";
    }
}

const not_tested_items_by_variant = blk: {
    var t: [not_tested_variants][]const []const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedList(v);
    break :blk t;
};
const not_tested_text_by_variant = blk: {
    var t: [not_tested_variants][]const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedJoined(v, false);
    break :blk t;
};
const not_tested_json_by_variant = blk: {
    var t: [not_tested_variants][]const u8 = undefined;
    for (0..not_tested_variants) |v| t[v] = notTestedJoined(v, true);
    break :blk t;
};

fn notTestedCondition(comptime i: usize) bool {
    return switch (i) {
        0 => l0_history_count > 0,
        1 => l1_configured,
        2 => scratch_declared.len > 0,
        else => @compileError("a not-tested condition was added to the list without a predicate here"),
    };
}

fn notTestedVariant() usize {
    var v: usize = 0;
    inline for (0..not_tested_conditions.len) |i| {
        if (notTestedCondition(i)) v |= @as(usize, 1) << i;
    }
    return v;
}

pub fn notTestedText() []const u8 {
    return not_tested_text_by_variant[notTestedVariant()];
}

fn notTestedJson() []const u8 {
    return not_tested_json_by_variant[notTestedVariant()];
}

pub fn scratchNote(arena: std.mem.Allocator) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (scratch_declared, 0..) |e, i| {
        if (i > 0) out.appendSlice(arena, ", ") catch return "(allocation failed)";
        out.appendSlice(arena, textShown(arena, e)) catch return "(allocation failed)";
    }
    return out.items;
}

test "the report names where the define's commands ran, and whether that was declared, only once it is known (#647)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const saved_cwd = command_cwd;
    const saved_decl = command_cwd_declared;
    defer {
        command_cwd = saved_cwd;
        command_cwd_declared = saved_decl;
    }

    command_cwd = null;
    const before = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .define_invalid, "m", null);
    try std.testing.expect(std.mem.indexOf(u8, before, "command_cwd") == null);

    command_cwd = "/tmp/proj";
    command_cwd_declared = true;
    const decl = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, decl, "\n  \"command_cwd\": \"/tmp/proj\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, decl, "\n  \"command_cwd_declared\": true") != null);

    command_cwd = "/home/runner/work";
    command_cwd_declared = false;
    const own = try buildJson(a, "UNKNOWN", 2, null, null, "recording_run_failed", null, "m", "Do this.");
    try std.testing.expect(std.mem.indexOf(u8, own, "\n  \"command_cwd\": \"/home/runner/work\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, own, "\n  \"command_cwd_declared\": false") != null);

    const after = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "m", null);
    try std.testing.expect(std.mem.indexOf(u8, after, "\"command_cwd\"") != null);

    command_cwd = "/tmp/a\nb";
    const esc = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, esc, "/tmp/a\\nb") != null);
    try std.testing.expect(std.mem.indexOf(u8, esc, "/tmp/a\nb") == null);
}

test "a SETUP_ERROR report carries its class, and the setup's status only under setup_failed and only as measured (#518)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const saved = setup_status;
    defer setup_status = saved;

    setup_status = .{ .exited = 7 };
    const exited = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup exited 7", null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "\n  \"setup_error_reason\": \"setup_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "\n  \"setup_exit_code\": 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "setup_signal") == null);
    try std.testing.expect(std.mem.indexOf(u8, exited, "\"setup_error_reason\"").? < std.mem.indexOf(u8, exited, "\"message\"").?);

    setup_status = .{ .signaled = 9 };
    const killed = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup was killed by signal 9", null);
    try std.testing.expect(std.mem.indexOf(u8, killed, "\n  \"setup_signal\": 9") != null);
    try std.testing.expect(std.mem.indexOf(u8, killed, "setup_exit_code") == null);

    setup_status = .{ .unknown = 0x1234 };
    const undecoded = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .setup_failed, "--setup ended in a way waitpid reported as status 4660", null);
    try std.testing.expect(std.mem.indexOf(u8, undecoded, "\"setup_error_reason\": \"setup_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, undecoded, "setup_exit_code") == null and std.mem.indexOf(u8, undecoded, "setup_signal") == null);

    setup_status = .{ .exited = 7 };
    const env = try buildJson(a, "SETUP_ERROR", 3, null, null, null, .environment, "out of memory", null);
    try std.testing.expect(std.mem.indexOf(u8, env, "\"setup_error_reason\": \"environment\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, env, "setup_exit_code") == null);
    const unk = try buildJson(a, "UNKNOWN", 2, null, null, "no_shim_marker", null, "m", "Do this.");
    try std.testing.expect(std.mem.indexOf(u8, unk, "setup_error_reason") == null and std.mem.indexOf(u8, unk, "setup_exit_code") == null);
    const pass = try buildJson(a, "PASS", 0, null, null, null, null, null, null);
    try std.testing.expect(std.mem.indexOf(u8, pass, "setup_") == null);
}

pub fn sayApparatus(arena: std.mem.Allocator, comptime fmt: []const u8) void {
    if (apparatus_declared.len > 0) say(fmt, .{apparatusNote(arena)});
}

pub var define_warnings: []const []const u8 = &.{};
var warnings_emitted = false;

pub fn sayWarnings(comptime fmt: []const u8) void {
    for (define_warnings) |w| say(fmt, .{w});
}

/// Each warning once, on stderr, as `sideeye: warning: …`. At the end and not when the define is
/// read, for the seal's reason (below): a reader of merged output who takes its first line must
/// still find the verdict there (`docs/cli.md`). Called by `emitSeal`, which every exit after a
pub fn emitWarnings() void {
    if (warnings_emitted) return;
    warnings_emitted = true;
    const prefix = "sideeye: warning: ";
    for (define_warnings) |w| {
        _ = posix.write(2, prefix.ptr, prefix.len);
        _ = posix.write(2, w.ptr, w.len);
        _ = posix.write(2, "\n", 1);
    }
}

pub fn sayRecovery(comptime fmt: []const u8) void {
    if (recovery_note) |rn| say(fmt, .{rn});
}

pub fn sayCrashState(comptime fmt: []const u8) void {
    if (crash_state_note) |cn| say(fmt, .{cn});
}

/// so. Defanged: a declared `cwd` arrives from a config or a case file, outside the trust
/// boundary, and a control byte in a directory name would otherwise forge a report line.
pub fn sayCwd(arena: std.mem.Allocator, comptime fmt: []const u8) void {
    if (command_cwd) |c| say(fmt, .{ defang.textShown(arena, c), if (command_cwd_declared) "" else "  (none declared: Sideeye's own)" });
}

pub fn shellQuote(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.append(arena, '\'');
    for (s) |ch| {
        if (ch == '\'') try out.appendSlice(arena, "'\\''") else try out.append(arena, ch);
    }
    try out.append(arena, '\'');
    return out.items;
}

/// argument. The set leaves out `=`, which would make a first word an assignment and which zsh
/// (macOS's shell) expands at the start of a word, `~`, `*`, `?` and the brackets, which a shell
/// expands, and everything a shell splits or redirects on; an empty value is `''`, which a bare
/// word cannot spell.
pub fn shellWord(arena: std.mem.Allocator, s: []const u8) error{OutOfMemory}![]const u8 {
    if (s.len == 0) return shellQuote(arena, s);
    for (s) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and std.mem.indexOfScalar(u8, "_./:@%+,-", ch) == null)
            return shellQuote(arena, s);
    }
    return s;
}

pub fn observeFlags(arena: std.mem.Allocator, observe: contract.ObserveMode, shim_given: ?[]const u8) []const u8 {
    const mode_part: []const u8 = switch (observe) {
        .wrappers => "",
        .syscalls => " --observe syscalls",
        .supervised => return " --observe supervised",
    };
    const s = shim_given orelse return mode_part;
    return std.mem.concat(arena, u8, &.{ mode_part, flagWord(arena, "--shim", s) catch return mode_part }) catch mode_part;
}

pub fn flagWord(arena: std.mem.Allocator, flag: []const u8, value: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(arena, " {s} {s}", .{ flag, try shellWord(arena, value) });
}

pub const NextDefine = struct {
    state: []const u8,
    setup: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    operation: []const u8,
    expect_status: ?u8 = null,
    apparatus: []const []const u8 = &.{},
    scratch: []const []const u8 = &.{},
};

pub fn nextDefineWords(arena: std.mem.Allocator, d: NextDefine) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, try flagWord(arena, "--state", d.state));
    if (d.setup) |x| try out.appendSlice(arena, try flagWord(arena, "--setup", x));
    if (d.cwd) |x| try out.appendSlice(arena, try flagWord(arena, "--cwd", x));
    try out.appendSlice(arena, try flagWord(arena, "--operation", d.operation));
    if (d.expect_status) |x| try out.print(arena, " --expect-status {d}", .{x});
    for (d.apparatus) |x| try out.appendSlice(arena, try flagWord(arena, "--apparatus", x));
    for (d.scratch) |x| try out.appendSlice(arena, try flagWord(arena, "--scratch", x));
    return out.items;
}

pub const NextRun = struct {
    work: ?[]const u8 = null,
    state_under: ?[]const u8 = null,
    observe: contract.ObserveMode = .wrappers,
    shim: ?[]const u8 = null,
    oracle: ?[]const u8 = null,
    oracle_found: ?[]const u8 = null,
};

pub fn nextRunWords(arena: std.mem.Allocator, r: NextRun) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    // Left off, explore falls back to the default work directory, which may be the one another
    // user owns or another run holds — the reason this run was given its own.
    if (r.work) |x| try out.appendSlice(arena, try flagWord(arena, "--work", x));
    // Left off, the pasted command explores without the bound the operator asked preflight for,
    // and nothing refuses to say so: the flag only narrows.
    if (r.state_under) |x| try out.appendSlice(arena, try flagWord(arena, "--state-under", x));
    try out.appendSlice(arena, observeFlags(arena, r.observe, r.shim));
    if (r.oracle orelse r.oracle_found) |x|
        try out.appendSlice(arena, try flagWord(arena, "--oracle", x))
    else
        try out.appendSlice(arena, if (builtin.os.tag == .macos) " --allow-unverified" else " --oracle <strace>");
    return out.items;
}

test "the next line's words are the define's and the run's, each quoted only where a shell would change it" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    try t.expectEqualStrings(
        " --state '/a b/$HOME' --cwd /c --operation 't rotate' --expect-status 3 --apparatus 'note:x `y`' --scratch k --scratch 'm n'",
        try nextDefineWords(a, .{ .state = "/a b/$HOME", .cwd = "/c", .operation = "t rotate", .expect_status = 3, .apparatus = &.{"note:x `y`"}, .scratch = &.{ "k", "m n" } }),
    );
    try t.expectEqualStrings(
        " --work /w --state-under /u --observe syscalls --shim /l.so --oracle /usr/bin/strace",
        try nextRunWords(a, .{ .work = "/w", .state_under = "/u", .observe = .syscalls, .shim = "/l.so", .oracle = "/usr/bin/strace" }),
    );
    try t.expectEqualStrings(" --observe supervised --oracle '/o p'", try nextRunWords(a, .{ .observe = .supervised, .shim = "/l.so", .oracle_found = "/o p" }));
}

pub fn replayLine(arena: std.mem.Allocator, case_path: []const u8, args: cli.Args) []const u8 {
    return replayWords(arena, case_path, args) catch "-";
}

fn replayWords(arena: std.mem.Allocator, case_path: []const u8, args: cli.Args) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(arena, "sideeye replay {s}", .{try shellWord(arena, case_path)});
    try out.appendSlice(arena, observeFlags(arena, args.observe, args.shim));
    if (args.oracle) |o| try out.appendSlice(arena, try flagWord(arena, "--oracle", o));
    if (args.recovery) |rc| if (args.recovery_check) |rcc|
        try out.print(arena, " --recovery {s} --recovery-check {s}", .{ try shellQuote(arena, rc), try shellQuote(arena, rcc) });
    // Only when named: a default written into the line would read as the operator's choice.
    if (args.work_named) try out.appendSlice(arena, try flagWord(arena, "--work", args.work));
    if (args.state_under) |u| try out.appendSlice(arena, try flagWord(arena, "--state-under", u));
    if (args.allow_unverified) try out.appendSlice(arena, " --allow-unverified");
    if (args.world_timeout_s) |t| try out.print(arena, " --world-timeout {d}", .{t});
    return out.items;
}

test "a replay line names --shim only when the run was given one" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    try t.expectEqualStrings("sideeye replay /w/cases/000001.json", replayLine(a, "/w/cases/000001.json", .{}));
    try t.expectEqualStrings("sideeye replay /w/cases/000001.json --shim /opt/lib/libsideeye_shim.so", replayLine(a, "/w/cases/000001.json", .{ .shim = "/opt/lib/libsideeye_shim.so" }));
    try t.expectEqualStrings("sideeye replay /w/c.json --observe syscalls", replayLine(a, "/w/c.json", .{ .observe = .syscalls }));
    try t.expectEqualStrings("sideeye replay /w/c.json --observe syscalls --shim /l.so --recovery 'r' --recovery-check 'c'", replayLine(a, "/w/c.json", .{ .observe = .syscalls, .shim = "/l.so", .recovery = "r", .recovery_check = "c" }));
    try t.expectEqualStrings("sideeye replay /w/c.json --observe supervised", replayLine(a, "/w/c.json", .{ .observe = .supervised, .shim = "/l.so" }));
    try t.expectEqualStrings("sideeye replay '/w/a b.json' --shim '/x y/l.so'", replayLine(a, "/w/a b.json", .{ .shim = "/x y/l.so" }));
}

test "a replay line carries the --oracle its run was given, so a FAIL across a process boundary replays as printed" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    const t = std.testing;
    try t.expectEqualStrings("sideeye replay /w/c.json --oracle /opt/x/strace", replayLine(a, "/w/c.json", .{ .oracle = "/opt/x/strace" }));
    try t.expectEqualStrings("sideeye replay /w/c.json --observe supervised --oracle '/o p/strace' --recovery 'r' --recovery-check 'c'", replayLine(a, "/w/c.json", .{ .observe = .supervised, .shim = "/l.so", .oracle = "/o p/strace", .recovery = "r", .recovery_check = "c" }));
    try t.expectEqualStrings("sideeye replay /w/c.json --shim /l.so --oracle ./strace", replayLine(a, "/w/c.json", .{ .shim = "/l.so", .oracle = "./strace" }));
}

const ArgsField = std.meta.FieldEnum(cli.Args);

fn withField(comptime field: ArgsField) cli.Args {
    var args: cli.Args = .{};
    const name = @tagName(field);
    const T = @FieldType(cli.Args, name);
    @field(args, name) = if (T == bool)
        true
    else if (T == []const u8 or T == ?[]const u8)
        "/x"
    else if (T == ?config.Command)
        .{ .str = "x" }
    else if (T == []const []const u8)
        &.{"x"}
    else if (T == ?u8 or T == ?u32)
        3
    else if (T == contract.ObserveMode)
        .syscalls
    else
        @compileError("no off-default value for a field of this type: " ++ name);
    switch (field) {
        .work => args.work_named = true,
        .recovery, .recovery_check => {
            args.recovery = "r";
            args.recovery_check = "c";
        },
        else => {},
    }
    return args;
}

fn hasFlag(line: []const u8, flag: []const u8) bool {
    var words = std.mem.tokenizeScalar(u8, line, ' ');
    while (words.next()) |w| if (std.mem.eql(u8, w, flag)) return true;
    return false;
}

test "every flag the replay line carries reaches it, and no flag it leaves off or a case carries does" {
    var as = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer as.deinit();
    const a = as.allocator();
    inline for (comptime std.enums.values(ArgsField)) |field| {
        const class = comptime cli.carried(field).replay;
        if (class != .derived) {
            const line = replayLine(a, "/c.json", withField(field));
            std.testing.expectEqual(class == .printed, hasFlag(line, cli.flagOf(field))) catch |e| {
                std.debug.print("{s} is classified {s} on the replay line, and the line is: {s}\n", .{ @tagName(field), @tagName(class), line });
                return e;
            };
        }
    }
}

test "every flag the replay and next lines are classified as printing is one the pasted command takes" {
    var buf: [64][]const u8 = undefined;
    const replay_flags = cli.synopsisFlags("replay", &buf);
    var buf2: [64][]const u8 = undefined;
    const explore_flags = cli.synopsisFlags("explore", &buf2);
    inline for (comptime std.enums.values(ArgsField)) |field| {
        const c = comptime cli.carried(field);
        if (c.replay == .printed) try std.testing.expect(containsFlag(replay_flags, cli.flagOf(field)));
        if (c.next == .printed) try std.testing.expect(containsFlag(explore_flags, cli.flagOf(field)));
    }
    for (replay_flags) |flag| {
        var named = false;
        inline for (comptime std.enums.values(ArgsField)) |field| {
            if (comptime cli.carried(field).replay != .derived) named = named or std.mem.eql(u8, cli.flagOf(field), flag);
        }
        std.testing.expect(named) catch |e| {
            std.debug.print("replay takes {s}, and no field of cli.Args is classified under that flag\n", .{flag});
            return e;
        };
    }
}

fn containsFlag(flags: []const []const u8, flag: []const u8) bool {
    for (flags) |f| if (std.mem.eql(u8, f, flag)) return true;
    return false;
}

test "a shell word is the value itself unless a shell would read it otherwise (#711)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings("/tmp/se/work/cases/000001.json", try shellWord(a, "/tmp/se/work/cases/000001.json"));
    try std.testing.expectEqualStrings("'/tmp/a b/c'", try shellWord(a, "/tmp/a b/c"));
    try std.testing.expectEqualStrings("''", try shellWord(a, ""));
    try std.testing.expectEqualStrings("'NAME=x'", try shellWord(a, "NAME=x"));
    try std.testing.expectEqualStrings("'it'\\''s'", try shellWord(a, "it's"));
    try std.testing.expectEqualStrings("'$HOME'", try shellWord(a, "$HOME"));
    try std.testing.expectEqualStrings("'~/x'", try shellWord(a, "~/x"));
}

pub fn evidenceCommand(arena: std.mem.Allocator, bundle: []const u8) []const u8 {
    if (std.mem.eql(u8, bundle, "-")) return bundle;
    const word = shellWord(arena, bundle) catch return bundle;
    return std.fmt.allocPrint(arena, "sideeye evidence {s}", .{word}) catch bundle;
}

/// pasted line runs the operation the way a world did — except two kinds, which belong to a
/// world's own process group and cgroup and which a pasted line runs in neither of. The cgroup
/// ones are pinned empty, as the engine pins them for a recording: the shim reads empty as none,
/// and a value left in the reader's shell from an earlier run would otherwise be read.
/// `SIDEEYE_KILL_GROUP` is **unset** in the line's subshell, not pinned: the shim reads its
/// presence, not its value, and with it the kill takes the reader's own shell down with the target
/// (measured twice — see the FAIL block in `main.zig`; the second time was this line's first
/// version, which pinned it empty and killed the acceptance suite's own shell). `TOY_STATE` is not
/// carried: it is the demo toy's own name for the state directory, which the toy reads
/// `SIDEEYE_STATE_DIR` for when it is unset, and printing it would hide whether the line's
/// `SIDEEYE_STATE_DIR_ALT` reaches the shim (acceptance check 2m spells the state its own way).
pub const Reproduce = struct {
    cwd: ?[]const u8,
    state: []const u8,
    state_alt: ?[]const u8,
    trace: []const u8,
    preload_var: []const u8,
    shim: []const u8,
    kill_at: usize,
    /// The observation mode's name: without `SIDEEYE_OBSERVE=syscalls` the shim counts the
    /// default way, and under that mode the kill lands on another operation (measured).
    observe: []const u8,
    argv: []const []const u8,
};

/// It used to end in the placeholder `<operation>`, and still does, with no `cd`, when the line
/// cannot be printed as a command that means the same run: the argv or the directory holds a
/// byte the report defangs (printed raw it would let a define's bytes forge report lines,
/// printed defanged it would name another program or directory), Sideeye could not name the
/// directory, or the line would not fit the text report's output buffer, which drops a write
/// that overruns it.
pub fn reproduceLine(arena: std.mem.Allocator, r: Reproduce) error{OutOfMemory}![]const u8 {
    var env: std.ArrayList(u8) = .empty;
    try env.print(arena, "{s}={s} {s}={s}", .{
        contract.env.state_dir,     try shellWord(arena, r.state),
        contract.env.state_dir_alt, if (r.state_alt) |alt| try shellWord(arena, alt) else "",
    });
    try env.print(arena, " {s}={s} {s}={s} {s}={d} {s}= {s}={s} {s}= {s}= {s}=", .{
        contract.env.trace_path,  try shellWord(arena, r.trace),
        r.preload_var,            try shellWord(arena, r.shim),
        contract.env.kill_at,     r.kill_at,
        contract.env.seq_base,    contract.env.observe,
        r.observe,                contract.env.run_cgroup,
        contract.env.kill_cgroup, contract.env.kill_aside,
    });
    const as_command = blk: {
        const c = r.cwd orelse break :blk false;
        if (r.argv.len == 0 or !std.mem.eql(u8, defang.textShown(arena, c), c)) break :blk false;
        for (r.argv) |a| if (!std.mem.eql(u8, defang.textShown(arena, a), a)) break :blk false;
        break :blk true;
    };
    const placeholder = try std.fmt.allocPrint(arena, "{s} <operation>", .{env.items});
    if (!as_command) return placeholder;
    var out: std.ArrayList(u8) = .empty;
    // The trace emptied first: the shim numbers each operation from the highest number already in
    // it (v15), so a second paste into the same file would count from where the first stopped and
    // never reach k — the line ran to completion and said nothing (measured, #711's review).
    try out.print(arena, "(cd {s} && unset {s} && : > {s} && {s}", .{
        try shellWord(arena, r.cwd.?), contract.env.kill_group, try shellWord(arena, r.trace), env.items,
    });
    for (r.argv, 0..) |a, i| {
        const bare_name = i == 0 and std.mem.indexOfScalar(u8, a, '/') == null;
        try out.print(arena, " {s}", .{if (bare_name) try shellQuote(arena, a) else try shellWord(arena, a)});
    }
    try out.appendSlice(arena, " </dev/null)");
    if (out.items.len + 16 > say_capacity) return placeholder;
    return out.items;
}

test "the reproduce line is a command in a subshell, or keeps the placeholder when it cannot mean the same run (#711)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const pins = " SIDEEYE_RUN_CGROUP= SIDEEYE_KILL_CGROUP= SIDEEYE_KILL_ASIDE=";
    const base: Reproduce = .{
        .cwd = "/w d",
        .state = "/s",
        .state_alt = null,
        .trace = "/t/trace-repro.bin",
        .preload_var = "LD_PRELOAD",
        .shim = "/l/libsideeye_shim.so",
        .kill_at = 5,
        .observe = "wrappers",
        .argv = &.{ "/bin/toy", "rotate", "a b" },
    };
    try std.testing.expectEqualStrings(
        "(cd '/w d' && unset SIDEEYE_KILL_GROUP && : > /t/trace-repro.bin && SIDEEYE_STATE_DIR=/s SIDEEYE_STATE_DIR_ALT= SIDEEYE_TRACE_PATH=/t/trace-repro.bin LD_PRELOAD=/l/libsideeye_shim.so SIDEEYE_KILL_AT=5 SIDEEYE_SEQ_BASE= SIDEEYE_OBSERVE=wrappers" ++ pins ++ " /bin/toy rotate 'a b' </dev/null)",
        try reproduceLine(a, base),
    );
    var sys = base;
    sys.observe = "syscalls";
    sys.state_alt = "/link/s";
    sys.argv = &.{ "toy", "rotate" };
    try std.testing.expectEqualStrings(
        "(cd '/w d' && unset SIDEEYE_KILL_GROUP && : > /t/trace-repro.bin && SIDEEYE_STATE_DIR=/s SIDEEYE_STATE_DIR_ALT=/link/s SIDEEYE_TRACE_PATH=/t/trace-repro.bin LD_PRELOAD=/l/libsideeye_shim.so SIDEEYE_KILL_AT=5 SIDEEYE_SEQ_BASE= SIDEEYE_OBSERVE=syscalls" ++ pins ++ " 'toy' rotate </dev/null)",
        try reproduceLine(a, sys),
    );
    var ctl = base;
    ctl.argv = &.{ "/bin/toy", "a\x01b" };
    var ctl_cwd = base;
    ctl_cwd.cwd = "/w\x1bd";
    var no_cwd = base;
    no_cwd.cwd = null;
    var long = base;
    const big = try a.alloc(u8, say_capacity);
    @memset(big, 'x');
    long.argv = &.{ "/bin/toy", big };
    for ([_]Reproduce{ ctl, ctl_cwd, no_cwd, long }) |r| {
        const line = try reproduceLine(a, r);
        try std.testing.expect(std.mem.startsWith(u8, line, "SIDEEYE_STATE_DIR=/s "));
        try std.testing.expect(std.mem.endsWith(u8, line, "SIDEEYE_KILL_ASIDE= <operation>"));
    }
    for ([_]Reproduce{ base, sys, ctl, no_cwd }) |r|
        try std.testing.expect(std.mem.indexOf(u8, try reproduceLine(a, r), "SIDEEYE_KILL_GROUP=") == null);
}

pub const AccountOf = enum { fail, pass, unknown };

/// PASS every one but those two, which belong to a counterexample; an UNKNOWN the set it
/// printed before #711. `explored`, `oracle`, `metadata` and `checker` stay off it: a refusal
/// raised before the exploration would print "explored 0 worlds (crash points N + 1
/// baseline)" beside crash points it never reached, and the JSON carries all four on every
/// report.
pub fn sayAccount(arena: std.mem.Allocator, of: AccountOf, points: usize) void {
    sayCwd(arena, "cwd         {s}{s}\n");
    sayApparatus(arena, "apparatus   {s}\n");
    sayWarnings("warning     {s}\n");
    sayRecovery("recovery    {s}\n");
    sayCrashState("crash state {s}\n");
    say("\n", .{});
    if (of != .unknown) {
        say("explored    {d} worlds (crash points {d} + 1 baseline)\n", .{ explored, points });
        if (of == .pass) saySingleCrashPointNote(points);
    }
    say("expected    exit {d}\n", .{expected_status_val});
    say("atomicity   {s}\n", .{l0_note});
    if (of != .unknown) {
        say("oracle      {s}\n", .{oracle_note});
        say("metadata    {s}\n", .{metadata_note});
        say("checker     {s}\n", .{checker_note});
    }
    say("l1          {s}\n", .{l1_note});
    say("case        {s}\n", .{case_note});
    if (of == .fail) {
        say("replay      {s}\n", .{replay_note});
        say("evidence    {s}\n", .{evidenceCommand(arena, evidence_note)});
    }
    say("processes   {s}\n", .{boundary.boundaryAccount()});
    say("not tested  {s}\n", .{notTestedText()});
}

fn jsonRecoveryField(w: *std.ArrayList(u8), arena: std.mem.Allocator, r: RecoveryResultJson) !void {
    const res = r.result;
    try w.appendSlice(arena, ",\n    \"recovery\": {\"result\": ");
    try jsonString(w, arena, res.name());
    try w.print(arena, ", \"seconds\": {d}.{d:0>3}", .{ r.ms / 1000, r.ms % 1000 });
    if (r.command_exit) |c| try w.print(arena, ", \"command_exit\": {d}", .{c});
    try w.appendSlice(arena, "}");
}

pub fn singleCrashPointClause(n: usize) []const u8 {
    return if (n == 1) ", over a single crash point" else "";
}

pub fn untouchedClause(arena: std.mem.Allocator, touched: u32, judged: usize) []const u8 {
    if (touched > 0) return "";
    if (judged == 0) return ", but it had no path to judge";
    return std.fmt.allocPrint(arena, ", but the operation touched none of the {d} path(s) it judged", .{judged}) catch ", but the operation touched none of the paths it judged";
}

test "the untouched clause is empty whenever a judged path was touched, and names the count otherwise (#683)" {
    const a = std.testing.allocator;
    try std.testing.expectEqualStrings("", untouchedClause(a, 1, 3));
    try std.testing.expectEqualStrings(", but it had no path to judge", untouchedClause(a, 0, 0));
    const s = untouchedClause(a, 0, 2);
    defer a.free(s);
    try std.testing.expectEqualStrings(", but the operation touched none of the 2 path(s) it judged", s);
}

/// **The condition is `singleCrashPointClause`'s, spelled a second time.** Changing one
/// without the other leaves a verdict line that names the count with no advice under it, or
/// advice under a line that does not. They are two functions rather than one because they
/// A call of its own rather than a `{s}` line inside a literal, which would print an indented
/// blank on every *other* PASS. Since `sayAccount` (#711) the PASS block is a sequence of calls,
fn saySingleCrashPointNote(n: usize) void {
    if (n == 1) say("            if the define expected more, check that the target's store resolves inside the state directory\n", .{});
}

fn jsonArrayField(w: *std.ArrayList(u8), arena: std.mem.Allocator, name: []const u8, items: []const []const u8, only_unchecked: bool) !void {
    try w.appendSlice(arena, ",\n  \"");
    try w.appendSlice(arena, name);
    try w.appendSlice(arena, "\": [");
    var first = true;
    for (items) |e| {
        if (only_unchecked and !config.apparatusUnchecked(e)) continue;
        if (!first) try w.appendSlice(arena, ", ");
        first = false;
        try jsonString(w, arena, e);
    }
    try w.append(arena, ']');
}

fn apparatusNote(arena: std.mem.Allocator) []const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (apparatus_declared, 0..) |e, i| {
        if (i > 0) out.appendSlice(arena, ", ") catch return "(allocation failed)";
        out.appendSlice(arena, textShown(arena, e)) catch return "(allocation failed)";
        if (config.apparatusUnchecked(e)) out.appendSlice(arena, " (declared, not checked)") catch return "(allocation failed)";
    }
    return out.items;
}

/// `std.json.Stringify.encodeJsonString` was the obvious alternative and does not fit.
/// Its default options pass bytes 0x80–0xFF through unchanged — the same defect this
/// function had — and `escape_unicode` decodes them with `catch unreachable`, so invalid
/// UTF-8 is a panic rather than a bad document.
pub fn jsonString(w: *std.ArrayList(u8), arena: std.mem.Allocator, s: []const u8) !void {
    try w.append(arena, '"');
    var i: usize = 0;
    while (i < s.len) {
        const ch = s[i];
        switch (ch) {
            '"' => {
                try w.appendSlice(arena, "\\\"");
                i += 1;
            },
            '\\' => {
                try w.appendSlice(arena, "\\\\");
                i += 1;
            },
            '\n' => {
                try w.appendSlice(arena, "\\n");
                i += 1;
            },
            '\r' => {
                try w.appendSlice(arena, "\\r");
                i += 1;
            },
            '\t' => {
                try w.appendSlice(arena, "\\t");
                i += 1;
            },
            else => {
                if (ch < 0x20) {
                    var esc: [6]u8 = undefined;
                    try w.appendSlice(arena, try std.fmt.bufPrint(&esc, "\\u{x:0>4}", .{ch}));
                    i += 1;
                } else if (ch < 0x80) {
                    try w.append(arena, ch);
                    i += 1;
                } else {
                    // A path on Linux is an arbitrary byte string; a JSON document must be
                    // valid UTF-8. Passing these through raw produced a file that jq,
                    // Python and Go all refuse — the caller loses the counterexample
                    // entirely, which is worse than losing one character of a filename.
                    const len = std.unicode.utf8ByteSequenceLength(ch) catch {
                        try w.appendSlice(arena, "\\ufffd");
                        i += 1;
                        continue;
                    };
                    if (i + len > s.len or !std.unicode.utf8ValidateSlice(s[i..][0..len])) {
                        try w.appendSlice(arena, "\\ufffd");
                        i += 1;
                        continue;
                    }
                    try w.appendSlice(arena, s[i..][0..len]);
                    i += len;
                }
            },
        }
    }
    try w.append(arena, '"');
}

pub fn violationPath(v: engine.Violation) []const u8 {
    return switch (v) {
        .missing => |p| p,
        .hybrid => |p| p,
        .rewritten => |p| p,
        .not_durable => |p| p,
    };
}

/// The opening clause of every `baseline_violates_invariant` refusal (#199): the acceptance
/// suite and the docs quote it, so it has one home, the way `not_tested_*` fragments do.
pub const baseline_refusal_lead = "the invariant failed in the world that was never crashed, so nothing found here is a consequence of crashing";

pub fn baselineAlsoFailed(marker: bool, checker: bool) []const u8 {
    if (marker and checker) return "; the success marker's invariant and the checker failed there too";
    if (checker) return "; the checker rejected that state too";
    if (marker) return "; the success marker's invariant failed there too";
    return "";
}

pub fn baselineObserved(arena: std.mem.Allocator, v: engine.Violation) []const u8 {
    const tail: []const u8 = switch (v) {
        .missing => "gone, though the recording had it before and after",
        .hybrid => "holding neither the old nor the new content",
        .rewritten => "with its recorded history no longer a prefix of its content",
        .not_durable => "not in its recorded final form",
    };
    return std.fmt.allocPrint(arena, "the re-run from the restored state left {s} {s}", .{ textShown(arena, violationPath(v)), tail }) catch "the re-run from the restored state did not leave the recorded bytes";
}

pub const SpanShown = enum {
    /// Where, how long and what kind of bytes — no bytes. A refusal carries this: it reaches
    /// the JSON `message`, the MCP answer (ADR 0010) and reports pasted upstream, and the
    /// stretch two runs disagree on is exactly where a per-run token or secret sits.
    shape,
    bytes,
};

const span_shown_max: usize = 48;

const StretchKind = struct {
    kind: enum { nothing, decimal, hex, text, binary },
    non_text: usize = 0,

    fn of(s: []const u8) StretchKind {
        if (s.len == 0) return .{ .kind = .nothing };
        var decimal = true;
        var hex = true;
        var has_digit = false;
        var has_letter = false;
        for (s) |c| {
            if (std.ascii.isDigit(c)) has_digit = true else decimal = false;
            if (!std.ascii.isHex(c)) hex = false else if (!std.ascii.isDigit(c)) has_letter = true;
        }
        if (decimal) return .{ .kind = .decimal };
        if (hex and has_digit and has_letter) return .{ .kind = .hex };
        const n = defang.nonTextBytes(s);
        return if (n == 0) .{ .kind = .text } else .{ .kind = .binary, .non_text = n };
    }

    fn text(self: StretchKind, arena: std.mem.Allocator) []const u8 {
        return switch (self.kind) {
            .nothing => "nothing",
            .decimal => "decimal digits",
            .hex => "hex digits",
            .text => "printable text",
            .binary => std.fmt.allocPrint(arena, "{d} byte(s) outside printable text", .{self.non_text}) catch "bytes outside printable text",
        };
    }
};

fn isUtf8Continuation(c: u8) bool {
    return c & 0xc0 == 0x80;
}

fn charAround(s: []const u8, i: usize) ?struct { start: usize, end: usize } {
    if (i >= s.len or !isUtf8Continuation(s[i])) return null;
    var j = i;
    while (j > 0 and i - j < 3) {
        j -= 1;
        if (!isUtf8Continuation(s[j])) break;
    }
    if (isUtf8Continuation(s[j])) return null;
    const n = std.unicode.utf8ByteSequenceLength(s[j]) catch return null;
    if (j + n <= i or j + n > s.len) return null;
    if (!std.unicode.utf8ValidateSlice(s[j..][0..n])) return null;
    return .{ .start = j, .end = j + n };
}

fn clipAtCharacter(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    var n = max;
    while (n > 0 and max - n < 3 and isUtf8Continuation(s[n])) n -= 1;
    return s[0..n];
}

pub fn byteSpan(arena: std.mem.Allocator, a_name: []const u8, a: []const u8, b_name: []const u8, b: []const u8, shown: SpanShown) []const u8 {
    if (std.mem.eql(u8, a, b)) return "hold the same bytes";
    const lim = @min(a.len, b.len);
    var p: usize = 0;
    while (p < lim and a[p] == b[p]) p += 1;
    var s: usize = 0;
    while (s < lim - p and a[a.len - 1 - s] == b[b.len - 1 - s]) s += 1;
    var q = p;
    if (charAround(a, p)) |c| q = @min(q, c.start);
    if (charAround(b, p)) |c| q = @min(q, c.start);
    var end_a = a.len - s;
    var end_b = b.len - s;
    if (charAround(a, end_a)) |c| end_a = @max(end_a, c.end);
    if (charAround(b, end_b)) |c| end_b = @max(end_b, c.end);
    const t = @min(a.len - end_a, b.len - end_b);
    const sa = a[q .. a.len - t];
    const sb = b[q .. b.len - t];
    const ka = StretchKind.of(sa);
    const kb = StretchKind.of(sb);
    const kinds: []const u8 = if (ka.kind == kb.kind and ka.kind == .binary)
        std.fmt.allocPrint(arena, "both holding bytes outside printable text ({d} and {d})", .{ ka.non_text, kb.non_text }) catch "both holding bytes outside printable text"
    else if (ka.kind == kb.kind)
        std.fmt.allocPrint(arena, "both {s}", .{ka.text(arena)}) catch ""
    else
        std.fmt.allocPrint(arena, "{s} in {s}, {s} in {s}", .{ ka.text(arena), a_name, kb.text(arena), b_name }) catch "";
    return switch (shown) {
        .shape => std.fmt.allocPrint(arena, "first differ at byte offset {d}, in a stretch {d} byte(s) long in {s} and {d} in {s}{s} (of {d} and {d} bytes), {s}", .{
            p,
            sa.len,
            a_name,
            sb.len,
            b_name,
            if (q < p) std.fmt.allocPrint(arena, ", starting at byte offset {d} where that character begins", .{q}) catch "" else "",
            a.len,
            b.len,
            kinds,
        }) catch "differ",
        .bytes => std.fmt.allocPrint(arena, "first differ at byte offset {d}{s}: {s} {s}{s}, {s} {s}{s} — {d} and {d} byte(s) of {d} and {d}, {s}", .{
            p,
            if (q < p) std.fmt.allocPrint(arena, " (stretch from byte offset {d})", .{q}) catch "" else "",
            a_name,
            defang.quotedForReport(arena, clipAtCharacter(sa, span_shown_max)) catch "\"?\"",
            if (sa.len > span_shown_max) "…" else "",
            b_name,
            defang.quotedForReport(arena, clipAtCharacter(sb, span_shown_max)) catch "\"?\"",
            if (sb.len > span_shown_max) "…" else "",
            sa.len,
            sb.len,
            a.len,
            b.len,
            kinds,
        }) catch "differ",
    };
}

fn kindName(k: posix.Kind) []const u8 {
    return switch (k) {
        .file => "file",
        .dir => "directory",
        .symlink => "symbolic link",
        .other => "special file",
        .missing => "nothing",
    };
}

pub fn baselineDiffers(arena: std.mem.Allocator, plan: engine.L0Plan, rerun: engine.Snapshot, v: engine.Violation) []const u8 {
    const rel = switch (v) {
        .hybrid, .rewritten => |p| p,
        .missing, .not_durable => return "",
    };
    const f = plan.find(rel) orelse return "";
    const e = rerun.find(rel) orelse return "";
    if (e.kind != f.post_kind)
        return std.fmt.allocPrint(arena, "; the recording left a {s} there and the re-run a {s}", .{ kindName(f.post_kind), kindName(e.kind) }) catch "";
    if (std.mem.eql(u8, e.content, f.post_content)) return "";
    return std.fmt.allocPrint(arena, "; the two runs' bytes {s}; preflight --twice quotes what two runs leave there", .{byteSpan(arena, "the recording", f.post_content, "the re-run", e.content, .shape)}) catch "";
}

test "byteSpan names where two runs' bytes differ, how long and what kind, and the bytes only when asked (#688)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4, in a stretch 1 byte(s) long in the recording and 1 in the re-run (of 9 and 9 bytes), both decimal digits",
        byteSpan(a, "the recording", "AAAA1BBBB", "the re-run", "AAAA2BBBB", .shape),
    );
    // Three inputs whose common prefixes differ in length, so an offset that does not come
    // from the bytes cannot pass all three.
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "run pid=1234 t=5", "y", "run pid=1299 t=5", .shape), "first differ at byte offset 10,"));
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "Z", "y", "Q", .shape), "first differ at byte offset 0,"));
    try std.testing.expect(std.mem.startsWith(u8, byteSpan(a, "x", "AAAA1BBBB", "y", "AAAA12BBBB", .shape), "first differ at byte offset 5,"));
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "x", "AAAA1BBBB", "y", "AAAA12BBBB", .shape), "0 byte(s) long in x and 1 in y (of 9 and 10 bytes), nothing in x, decimal digits in y") != null);
    const shape = byteSpan(a, "first run", "tok=SECRETAAAA", "second run", "tok=OTHERVALUE", .shape);
    try std.testing.expect(std.mem.indexOf(u8, shape, "SECRET") == null and std.mem.indexOf(u8, shape, "OTHER") == null);
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4: first run \"1\", second run \"2\" — 1 and 1 byte(s) of 9 and 9, both decimal digits",
        byteSpan(a, "first run", "AAAA1BBBB", "second run", "AAAA2BBBB", .bytes),
    );
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "\x89PNG\x00\x01", "s", "\x89PNG\x00\x02", .bytes), "f \"\\x01\", s \"\\x02\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "\x89PNG\x00\x01", "s", "\x89PNG\x00\x02", .shape), "both holding bytes outside printable text (1 and 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "id=3fa9c1", "s", "id=b07e2d", .shape), "both hex digits") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "name=alpha;", "s", "name=omega;", .shape), "both printable text") != null);
    const long_a = &@as([100]u8, @splat('x'));
    const long_b = &@as([100]u8, @splat('y'));
    const clipped = byteSpan(a, "f", long_a, "s", long_b, .bytes);
    try std.testing.expect(std.mem.indexOf(u8, clipped, "f \"" ++ @as([48]u8, @splat('x')) ++ "\"…, s \"" ++ @as([48]u8, @splat('y')) ++ "\"… — 100 and 100 byte(s)") != null);
    try std.testing.expectEqualStrings("hold the same bytes", byteSpan(a, "f", "same", "s", "same", .shape));
}

test "byteSpan reads text as text: whole UTF-8 characters, lines, and hex only with digits and letters (#688 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    try std.testing.expectEqualStrings(
        "first differ at byte offset 4 (stretch from byte offset 3): f \"é\", s \"è\" — 2 and 2 byte(s) of 6 and 6, both printable text",
        byteSpan(a, "f", "caf\xc3\xa9\n", "s", "caf\xc3\xa8\n", .bytes),
    );
    try std.testing.expectEqualStrings(
        "first differ at byte offset 2, in a stretch 3 byte(s) long in f and 3 in s, starting at byte offset 0 where that character begins (of 3 and 3 bytes), both printable text",
        byteSpan(a, "f", "あ", "s", "い", .shape),
    );
    try std.testing.expectEqualStrings(
        "first differ at byte offset 2, in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes), both holding bytes outside printable text (1 and 1)",
        byteSpan(a, "f", "\x41\x90\x85", "s", "\x41\x90\x86", .shape),
    );
    try std.testing.expectEqualStrings(
        "first differ at byte offset 0, in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes), both holding bytes outside printable text (1 and 1)",
        byteSpan(a, "f", "\x01\x90\x90", "s", "\x02\x90\x90", .shape),
    );
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "a\xc3\xa9", "s", "b\xc3\xa9", .shape), "in a stretch 1 byte(s) long in f and 1 in s (of 3 and 3 bytes)") != null);
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", "1\xc3\xbc", "s", "2\xc4\xbc", .shape), "in a stretch 3 byte(s) long in f and 3 in s (of 3 and 3 bytes)") != null);
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "t=1\nu=2\n", "s", "t=3\nu=4\n", .shape), ", both printable text"));
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "grade=A\n", "s", "grade=B\n", .shape), ", both printable text"));
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "w=bad\n", "s", "w=fee\n", .shape), ", both printable text"));
    try std.testing.expect(std.mem.endsWith(u8, byteSpan(a, "f", "id=3fa9c1\n", "s", "id=b07e2d\n", .shape), ", both hex digits"));
    const long_a = @as([47]u8, @splat('a')) ++ "é" ++ "aaz";
    const long_b = @as([47]u8, @splat('b')) ++ "é" ++ "bbz";
    try std.testing.expect(std.mem.indexOf(u8, byteSpan(a, "f", long_a, "s", long_b, .bytes), "f \"" ++ @as([47]u8, @splat('a')) ++ "\"…, s \"" ++ @as([47]u8, @splat('b')) ++ "\"…") != null);
}

test "baselineDiffers names a kind change, reads the history form, and says nothing for a missing path (#688 review)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var pre = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "one\n" }, .{ "k", "old" } });
    defer pre.deinit();
    var post = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "one\ntwo\n" }, .{ "k", "new" } });
    defer post.deinit();
    var plan = try engine.classify(std.testing.allocator, pre, post);
    defer plan.deinit();
    var rerun = try engine.testSnapshot(std.testing.allocator, &.{ .{ "h.log", "ONE\ntwo\n" }, .{ "k", "new" } });
    defer rerun.deinit();
    try std.testing.expectEqualStrings(
        "; the two runs' bytes first differ at byte offset 0, in a stretch 3 byte(s) long in the recording and 3 in the re-run (of 8 and 8 bytes), both printable text; preflight --twice quotes what two runs leave there",
        baselineDiffers(a, plan, rerun, .{ .rewritten = "h.log" }),
    );
    var dir_rerun: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator), .entries = .empty };
    defer dir_rerun.deinit();
    try dir_rerun.entries.append(dir_rerun.arena.allocator(), .{ .rel = "k", .kind = .dir, .content = "" });
    try std.testing.expectEqualStrings("; the recording left a file there and the re-run a directory", baselineDiffers(a, plan, dir_rerun, .{ .hybrid = "k" }));
    try std.testing.expectEqualStrings("", baselineDiffers(a, plan, rerun, .{ .missing = "k" }));
    try std.testing.expectEqualStrings("", baselineDiffers(a, plan, rerun, .{ .hybrid = "elsewhere" }));
}

pub fn violationObserved(v: ?engine.Violation) []const u8 {
    return if (v) |vv| switch (vv) {
        .missing => "present before and after the operation, but gone from the crashed state",
        .hybrid => "holding neither the old nor the new content",
        .rewritten => "present, but its recorded history is no longer a prefix of its content",
        .not_durable => "the operation claimed success before the kill, and this part of the new state did not survive",
    } else "the checker exited non-zero after restart";
}

const Earliest = struct {
    k: u32,
    after: []const u8,
    after_path: []const u8,
    before: []const u8,
    before_path: []const u8,
    subject: []const u8,
    observed: []const u8,
    invariant: []const u8,
};

pub const CheckerEarliest = struct {
    e: Earliest,
    case: []const u8,
    replay: []const u8,
    evidence: []const u8,
};

fn buildJson(
    arena: std.mem.Allocator,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    checker_detail: ?CheckerEarliest,
    // Typed, not a third `?[]const u8` beside the two this already takes (#518): with
    // `unknown_reason` and `message` adjacent and same-typed, a positional slip compiles
    // and writes the reason into the message.
    unknown_reason: ?[]const u8,
    setup_error_reason: ?contract.SetupErrorReason,
    message: ?[]const u8,
    next_step: ?[]const u8,
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = &buf;
    var nb: [16]u8 = undefined;

    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"frozen\",\n");
    try w.appendSlice(arena, "  \"contract_version\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{contract.contract_version}));
    try w.appendSlice(arena, ",\n  \"verdict\": ");
    try jsonString(w, arena, verdict);
    try w.appendSlice(arena, ",\n  \"exit_code\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{exit_code}));
    try w.appendSlice(arena, ",\n  \"oracle_verified\": ");
    try w.appendSlice(arena, if (oracle_verified) "true" else "false");
    // Emitted only when it is true, so every report a v14 consumer has seen is
    // byte-identical, and the `verdict == "PASS" &&
    // oracle_verified` gate keeps treating a run whose crash points include a child's
    // operations as unverified.
    if (oracle_verified_subject_only)
        try w.appendSlice(arena, ",\n  \"oracle_verified_subject_only\": true");
    // Read from the run's own counters rather than passed in as zeroes. An UNKNOWN raised
    // at world 4 of 6 used to report `"explored": 0`, so a caller aggregating coverage
    // from the JSON recorded nothing for every run that ended early.
    try w.appendSlice(arena, ",\n  \"crash_points\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{crash_points}));
    try w.appendSlice(arena, ",\n  \"explored\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{explored}));
    try w.appendSlice(arena, ",\n  \"violations\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{violations}));
    // Always present, even at the default: a PASS over a target whose success status
    // is 3 must be distinguishable, by machine, from a PASS that required 0.
    try w.appendSlice(arena, ",\n  \"expected_status\": ");
    try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{expected_status_val}));
    try appendCwd(w, arena);

    try appendDeclarations(w, arena);
    if (unknown_reason) |r| {
        try w.appendSlice(arena, ",\n  \"unknown_reason\": ");
        try jsonString(w, arena, r);
    }
    // Gated on the reason rather than on `setup_status` alone: the global is set only in
    // the failing arms, but the gate is what keeps a later PASS from ever carrying it.
    if (setup_error_reason) |r| {
        try w.appendSlice(arena, ",\n  \"setup_error_reason\": ");
        try jsonString(w, arena, r.name());
        if (r == .setup_failed) if (setup_status) |st| switch (st) {
            .exited => |code| {
                try w.appendSlice(arena, ",\n  \"setup_exit_code\": ");
                try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{code}));
            },
            .signaled => |sig| {
                try w.appendSlice(arena, ",\n  \"setup_signal\": ");
                try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{sig}));
            },
            .unknown => {},
        };
    }
    if (message) |m| {
        try w.appendSlice(arena, ",\n  \"message\": ");
        try jsonString(w, arena, m);
    }
    if (divergence_syscall.len > 0) {
        try w.appendSlice(arena, ",\n  \"divergence_syscall\": ");
        try jsonString(w, arena, divergence_syscall);
    }
    if (next_step) |n| {
        try w.appendSlice(arena, ",\n  \"next_step\": ");
        try jsonString(w, arena, n);
    }

    if (detail) |d| {
        try w.appendSlice(arena, ",\n  \"earliest\": {\n    \"crash_point\": ");
        try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{d.k}));
        try w.appendSlice(arena, ",\n    \"invariant\": ");
        try jsonString(w, arena, d.invariant);
        try w.appendSlice(arena, ",\n    \"after\": {\"op\": ");
        try jsonString(w, arena, d.after);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, d.after_path);
        try w.appendSlice(arena, "},\n    \"before\": {\"op\": ");
        try jsonString(w, arena, d.before);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, d.before_path);
        try w.appendSlice(arena, "},\n    \"subject\": ");
        try jsonString(w, arena, d.subject);
        try w.appendSlice(arena, ",\n    \"observed\": ");
        try jsonString(w, arena, d.observed);
        if (recovery_earliest) |r| try jsonRecoveryField(w, arena, r);
        try w.appendSlice(arena, "\n  }");
    }

    if (checker_detail) |cd| {
        try w.appendSlice(arena, ",\n  \"checker_earliest\": {\n    \"crash_point\": ");
        try w.appendSlice(arena, try std.fmt.bufPrint(&nb, "{d}", .{cd.e.k}));
        try w.appendSlice(arena, ",\n    \"invariant\": ");
        try jsonString(w, arena, cd.e.invariant);
        try w.appendSlice(arena, ",\n    \"after\": {\"op\": ");
        try jsonString(w, arena, cd.e.after);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, cd.e.after_path);
        try w.appendSlice(arena, "},\n    \"before\": {\"op\": ");
        try jsonString(w, arena, cd.e.before);
        try w.appendSlice(arena, ", \"path\": ");
        try jsonString(w, arena, cd.e.before_path);
        try w.appendSlice(arena, "},\n    \"subject\": ");
        try jsonString(w, arena, cd.e.subject);
        try w.appendSlice(arena, ",\n    \"observed\": ");
        try jsonString(w, arena, cd.e.observed);
        try w.appendSlice(arena, ",\n    \"case\": ");
        try jsonString(w, arena, cd.case);
        try w.appendSlice(arena, ",\n    \"replay\": ");
        try jsonString(w, arena, cd.replay);
        try w.appendSlice(arena, ",\n    \"evidence\": ");
        try jsonString(w, arena, cd.evidence);
        if (recovery_checker_earliest) |r| try jsonRecoveryField(w, arena, r);
        try w.appendSlice(arena, "\n  }");
    }

    try w.appendSlice(arena, ",\n  \"l0\": ");
    try jsonString(w, arena, l0_note);
    try w.appendSlice(arena, ",\n  \"l1\": ");
    try jsonString(w, arena, l1_note);
    try w.appendSlice(arena, ",\n  \"case\": ");
    try jsonString(w, arena, case_note);
    try w.appendSlice(arena, ",\n  \"replay\": ");
    try jsonString(w, arena, replay_note);
    try w.appendSlice(arena, ",\n  \"evidence\": ");
    try jsonString(w, arena, evidence_note);
    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    try w.appendSlice(arena, ",\n  \"metadata_writes\": ");
    try jsonString(w, arena, metadata_note);
    try w.appendSlice(arena, ",\n  \"checker\": ");
    try jsonString(w, arena, checker_note);
    if (recovery_note) |rn| {
        try w.appendSlice(arena, ",\n  \"recovery\": ");
        try jsonString(w, arena, rn);
    }
    if (crash_state_left) |left| {
        try w.appendSlice(arena, if (left) ",\n  \"crash_state_left\": true" else ",\n  \"crash_state_left\": false");
    }
    if (crash_state_note) |cn| {
        try w.appendSlice(arena, ",\n  \"crash_state_note\": ");
        try jsonString(w, arena, cn);
    }
    try w.appendSlice(arena, ",\n  \"processes\": ");
    try jsonString(w, arena, boundary.boundaryAccount());
    try w.print(arena, ",\n  \"paths_attributed_to_rename\": {d}", .{attributed_to_rename});
    try w.appendSlice(arena, ",\n  \"not_tested\": ");
    try w.appendSlice(arena, notTestedJson());
    try appendFigures(w, arena);
    try appendJudgedSet(w, arena);
    try w.appendSlice(arena, "\n}\n");
    return buf.items;
}

const W = *std.ArrayList(u8);

fn appendCwd(w: W, arena: std.mem.Allocator) !void {
    if (command_cwd) |c| {
        try w.appendSlice(arena, ",\n  \"command_cwd\": ");
        try jsonString(w, arena, c);
        try w.appendSlice(arena, ",\n  \"command_cwd_declared\": ");
        try w.appendSlice(arena, if (command_cwd_declared) "true" else "false");
    }
}

fn appendDeclarations(w: W, arena: std.mem.Allocator) !void {
    if (define_warnings.len > 0) try jsonArrayField(w, arena, "define_warnings", define_warnings, false);
    if (apparatus_declared.len > 0) {
        try jsonArrayField(w, arena, "apparatus", apparatus_declared, false);
        if (apparatusHasUnchecked()) try jsonArrayField(w, arena, "apparatus_unchecked", apparatus_declared, true);
    }
    if (scratch_declared.len > 0) try jsonArrayField(w, arena, "scratch", scratch_declared, false);
}

fn appendFigures(w: W, arena: std.mem.Allocator) !void {
    // booleans beside them. Each is present only where it was measured — none is ever written as a
    // zero or a false standing for "not known" — and none is a closed set. Before the judged set,
    // which stays last (ADR 0079).
    switch (oracle_asked) {
        .named => |kind| {
            try w.appendSlice(arena, ",\n  \"oracle_witness\": ");
            try jsonString(w, arena, kind.name());
        },
        .unparsed, .none => {},
    }
    if (oracle_operations_agreed) |n| try w.print(arena, ",\n  \"oracle_operations_agreed\": {d}", .{n});
    if (checker_declared) |d| try w.print(arena, ",\n  \"checker_declared\": {s}", .{if (d) "true" else "false"});
    if (checker_worlds) |n| try w.print(arena, ",\n  \"checker_worlds\": {d}", .{n});
    if (processes_measured) {
        const ev = boundary.boundary_ev;
        try w.print(arena, ",\n  \"processes_children_admitted\": {s}", .{if (ev.children_judged) "true" else "false"});
        try w.print(arena, ",\n  \"processes_image_changes\": {d}", .{ev.exec_continuations});
        try w.print(arena, ",\n  \"processes_threads_created\": {d}", .{ev.threads});
        try w.print(arena, ",\n  \"processes_writer_threads\": {d}", .{ev.writer_threads});
    }
}

fn appendJudgedSet(w: W, arena: std.mem.Allocator) !void {
    // #638, ADR 0079. LAST in the document, and the position is the decision: this is the only
    // field whose length grows with the target's state tree, so anywhere else it pushes back
    // the fields a reader of a FAIL needs first — `message`, `next_step`, `earliest`. Written
    // here it moves no existing byte. Present only on a run that reached classification, so a
    if (l0_classified) {
        try jsonArrayField(w, arena, "l0_judged_paths", l0_judged_paths, false);
        try w.print(arena, ",\n  \"l0_judged_paths_omitted\": {d}", .{l0_judged_paths_omitted});
        // After the two it qualifies, so it moves no byte that was there before it (#683).
        if (l0_judged_paths_touched) |t| try w.print(arena, ",\n  \"l0_judged_paths_touched\": {d}", .{t});
    }
}

/// On stderr, not stdout: the text report is the process's output, and a diagnostic
/// mixed into it would be read as part of the verdict. Ends with the seal token in its
/// `none` form (see `sealToken`): a run that asked for `--json` gets exactly one token
/// whether or not the file landed.
fn jsonFailed(detail: []const u8) void {
    const prefix = "sideeye: the JSON report was not written: ";
    _ = posix.write(2, prefix.ptr, prefix.len);
    _ = posix.write(2, detail.ptr, detail.len);
    _ = posix.write(2, "\n", 1);
    recordSeal(null);
}

/// it opens from one written after. Emitted in ONE write: on a pipe, a write of at most
/// PIPE_BUF bytes is not interleaved with another writer's, so the token arrives whole even
/// beside a program flooding the same descriptor. Not anchored to a line start on purpose,
/// and the reader must not anchor either: a flooder can take the line start away, but it
/// cannot remove the token, so a reader that counts occurrences anywhere sees the real one
/// and any forgery both. Always exactly one per run that named `--json`, so that "no token"
/// cannot be arranged by making the write fail and "one token" is never a forgery alone.
/// Recorded by `writeJsonReport` / `jsonFailed`, emitted by `emitSeal` at the exit. Deferred
/// rather than printed on the spot because the two refusal paths (`refuse.unknown`,
/// `refuse.setupError`) write the JSON BEFORE their text, and a token printed there would become
/// the first line of a run's output. The acceptance suite's CLI self-description check reads that
/// first line, and it went red when the token was printed in place — a reader that takes the first
/// line of merged output is exactly what this project's own tooling turned out to be.
const seal_prefix = "sideeye: json sha256=";
pub const seal_len = seal_prefix.len + 64 + ";\n".len;
var seal_pending: ?[32]u8 = null;
var seal_recorded = false;
var seal_emitted = false;

pub fn sealToken(buf: *[seal_len]u8, digest: ?[32]u8) []const u8 {
    if (digest) |d| {
        return std.fmt.bufPrint(buf, seal_prefix ++ "{x};\n", .{d}) catch unreachable;
    }
    return std.fmt.bufPrint(buf, seal_prefix ++ "none;\n", .{}) catch unreachable;
}

fn recordSeal(digest: ?[32]u8) void {
    seal_pending = digest;
    seal_recorded = true;
}

/// Write the token, once, for a run that named `--json`. Called immediately before every exit
/// that can follow a report; a path that never reaches one leaves no token, which the readers of
/// this token treat as a refusal — the safe direction.
pub fn emitSeal() void {
    emitWarnings();
    if (!seal_recorded or seal_emitted) return;
    seal_emitted = true;
    var buf: [seal_len]u8 = undefined;
    const tok = sealToken(&buf, seal_pending);
    _ = posix.write(2, tok.ptr, tok.len);
}

/// Every step here used to fail silently: a failed open, a short write, a formatting
/// error mid-document. The result was a truncated file — `{"schema": "sideeye/report",`
/// with no closing brace — beside an exit code claiming a clean verdict, and the caller
/// could not tell a broken write from a broken tool. Building the document first and
pub fn writeJsonReport(
    arena: std.mem.Allocator,
    path: []const u8,
    verdict: []const u8,
    exit_code: u8,
    detail: ?Earliest,
    checker_detail: ?CheckerEarliest,
    unknown_reason: ?[]const u8,
    setup_error_reason: ?contract.SetupErrorReason,
    message: ?[]const u8,
    next_step: ?[]const u8,
) void {
    const doc = buildJson(arena, verdict, exit_code, detail, checker_detail, unknown_reason, setup_error_reason, message, next_step) catch
        return jsonFailed("the document could not be built");
    writeJsonDoc(path, doc);
}

fn writeJsonDoc(path: []const u8, doc: []const u8) void {
    var pbuf: [contract.max_path]u8 = undefined;
    const pz = std.mem.printSentinel(&pbuf, "{s}", .{path}, 0) catch
        return jsonFailed("--json path is too long");
    var tbuf: [contract.max_path]u8 = undefined;
    const temp = openFreshTemp(&tbuf, std.fs.path.dirname(path) orelse ".", null) orelse
        return jsonFailed("the file could not be opened for writing");
    const tz = temp.path;
    const fd = temp.fd;
    var off: usize = 0;
    while (off < doc.len) {
        const written = posix.write(fd, doc[off..].ptr, doc.len - off);
        if (written <= 0) {
            _ = posix.close(fd);
            _ = posix.unlink(tz.ptr);
            return jsonFailed("the write did not complete");
        }
        off += @intCast(written);
    }
    _ = posix.close(fd);

    if (posix.rename(tz.ptr, pz.ptr) != 0) {
        _ = posix.unlink(tz.ptr);
        return jsonFailed("the finished document could not be moved into place");
    }

    // The seal, over the bytes that were written -- `doc`, not a re-read of the file, which
    // by now is in a directory somebody else may write (#597).
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(doc, &digest, .{});
    recordSeal(digest);
}

const FreshTemp = struct { path: [:0]const u8, fd: c_int };

fn openFreshTemp(buf: []u8, dir: []const u8, first_name: ?[]const u8) ?FreshTemp {
    const sep: []const u8 = if (std.mem.endsWith(u8, dir, "/")) "" else "/";
    var attempt: usize = 0;
    while (attempt < 8) : (attempt += 1) {
        var hex: [16]u8 = undefined;
        var name_buf: [64]u8 = undefined;
        const name = if (attempt == 0 and first_name != null) first_name.? else std.fmt.bufPrint(&name_buf, ".sideeye-json-{s}.tmp", .{posix.randomHex(&hex) orelse return null}) catch return null;
        const tz = std.mem.printSentinel(buf, "{s}{s}{s}", .{ dir, sep, name }, 0) catch return null;
        // Never O_TRUNC an existing name: whatever sits there, a link included, would be written through.
        const fd = posix.open(tz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL | posix.O_NOFOLLOW | posix.O_CLOEXEC, @as(c_uint, 0o644));
        if (fd >= 0) return .{ .path = tz, .fd = fd };
        const err = std.c._errno().*;
        if (err != posix.EEXIST and err != posix.ELOOP) return null;
    }
    return null;
}

pub const ReportSlot = union(enum) {
    leave,
    remove,
    refuse: []const u8,
};

pub fn reportSlot(path: []const u8) ReportSlot {
    var zb: [contract.max_path]u8 = undefined;
    const z = std.mem.printSentinel(&zb, "{s}", .{path}, 0) catch return .leave;
    const kind = posix.kindOfPathNoFollow(z.ptr) catch return .{ .refuse = "a path whose kind could not be read" };
    switch (kind) {
        .missing => return .leave,
        .symlink => return .{ .refuse = "a symbolic link" },
        .dir => return .{ .refuse = "a directory" },
        .other => return .{ .refuse = "a device, a FIFO or a socket" },
        .file => {},
    }
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const bytes = capture.readFileAllocCapped(arena, path, report_slot_cap, .{ .require_regular = true, .no_follow = true }) orelse
        return .{ .refuse = "a file that could not be read, or one larger than any report" };
    if (bytes.len == 0 or isOneOwnDocument(arena, bytes)) return .remove;
    return .{ .refuse = "a file that is not a report Sideeye wrote" };
}

/// Not unbounded: a mistyped `--json` can name a file of any size.
const report_slot_cap = 4 * 1024 * 1024;

/// Not judged by the first member alone: a log of reports appended one per line starts like one, and
/// a mistyped `--json` would lose every report in it.
fn isOneOwnDocument(arena: std.mem.Allocator, bytes: []const u8) bool {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return false;
    if (parsed != .object) return false;
    const schema = switch (parsed.object.get("schema") orelse return false) {
        .string => |t| t,
        else => return false,
    };
    return std.mem.eql(u8, schema, "sideeye/report") or std.mem.eql(u8, schema, "sideeye/preflight");
}

const SlotTestDir = struct {
    dir_buf: [128]u8 = undefined,
    dir: []const u8 = "",
    path_buf: [192]u8 = undefined,
    names: [20][]const u8 = undefined,
    n: usize = 0,

    fn init(self: *SlotTestDir, tag: []const u8) !void {
        self.dir = try std.fmt.bufPrint(&self.dir_buf, "/tmp/sideeye-{s}-{d}", .{ tag, posix.getpid() });
        var zb: [128]u8 = undefined;
        _ = posix.mkdir(try std.mem.printSentinel(&zb, "{s}", .{self.dir}, 0), 0o700);
    }
    fn at(self: *SlotTestDir, name: []const u8) [:0]const u8 {
        return std.mem.printSentinel(&self.path_buf, "{s}/{s}", .{ self.dir, name }, 0) catch unreachable;
    }
    fn track(self: *SlotTestDir, name: []const u8) void {
        self.names[self.n] = name;
        self.n += 1;
    }
    fn file(self: *SlotTestDir, name: []const u8, bytes: []const u8) !void {
        self.track(name);
        if (!files.writeWholeFile(self.at(name), &.{bytes})) return error.Setup;
    }
    fn link(self: *SlotTestDir, target: []const u8, name: []const u8) !void {
        self.track(name);
        var tb: [192]u8 = undefined;
        const tz = try std.mem.printSentinel(&tb, "{s}/{s}", .{ self.dir, target }, 0);
        if (posix.symlink(tz.ptr, self.at(name).ptr) != 0) return error.Setup;
    }
    fn read(self: *SlotTestDir, name: []const u8, out: []u8) []const u8 {
        const fd = posix.open(self.at(name).ptr, posix.O_RDONLY, @as(c_uint, 0));
        if (fd < 0) return "";
        defer _ = posix.close(fd);
        const r = posix.read(fd, out.ptr, out.len);
        return if (r > 0) out[0..@intCast(r)] else "";
    }
    fn deinit(self: *SlotTestDir) void {
        for (self.names[0..self.n]) |name| {
            _ = posix.unlink(self.at(name).ptr);
            _ = posix.rmdir(self.at(name).ptr);
        }
        var zb: [128]u8 = undefined;
        _ = posix.rmdir((std.mem.printSentinel(&zb, "{s}", .{self.dir}, 0) catch return).ptr);
    }
};

test "--json removes only a report or an empty file, and refuses anything else by kind (#818)" {
    var t: SlotTestDir = .{};
    try t.init("slot");
    defer t.deinit();
    try t.file("empty", "");
    try t.file("report", "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"frozen\"\n}\n");
    try t.file("preflight", "{\n  \"schema\": \"sideeye/preflight\",\n  \"outcome\": \"runs_differ\"\n}\n");
    try t.file("case", "{\n  \"schema\": \"sideeye/case\",\n  \"case_version\": 5\n}\n");
    try t.file("toml", "[world]\nstate = \"./state\"\n");
    try t.file("compact", "{\"schema\":\"sideeye/report\",\"verdict\":\"PASS\"}");
    try t.file("spaced", "\n{ \"schema\" :\t\"sideeye/preflight\" }");
    try t.file("sorted", "{\"contract_version\":19,\"schema\":\"sideeye/report\"}");
    try t.file("history", "{\"schema\":\"sideeye/report\",\"verdict\":\"PASS\"}\n{\"schema\":\"sideeye/report\",\"verdict\":\"FAIL\"}\n");
    try t.file("cut", "{\n  \"schema\": \"sideeye/report\",\n  \"schema_status\": \"fro");
    t.track("dir");
    if (posix.mkdir(t.at("dir").ptr, 0o700) != 0) return error.Setup;
    try t.link("report", "link");

    try std.testing.expect(reportSlot(t.at("absent")) == .leave);
    try std.testing.expect(reportSlot(t.at("absent/below")) == .leave);
    try std.testing.expect(reportSlot(t.at("empty")) == .remove);
    try std.testing.expect(reportSlot(t.at("report")) == .remove);
    try std.testing.expect(reportSlot(t.at("preflight")) == .remove);
    try std.testing.expect(reportSlot(t.at("compact")) == .remove);
    try std.testing.expect(reportSlot(t.at("spaced")) == .remove);
    try std.testing.expect(reportSlot(t.at("sorted")) == .remove);
    t.track("fifo");
    if (posix.mkfifo(t.at("fifo").ptr, @as(c_uint, 0o600)) != 0) return error.Setup;
    for ([_][]const u8{ "case", "toml", "history", "cut", "dir", "link", "fifo", "toml/below" }) |name|
        try std.testing.expect(reportSlot(t.at(name)) == .refuse);
    try std.testing.expect(reportSlot("/dev/null") == .refuse);
}

test "the report's temporary file is always one this call created (#818)" {
    var t: SlotTestDir = .{};
    try t.init("fresh-temp");
    defer t.deinit();
    try t.file("victim", "keep");
    try t.link("victim", "taken-link");
    try t.file("taken-file", "keep too");

    for ([_][]const u8{ "taken-link", "taken-file" }) |occupied| {
        var tb: [contract.max_path]u8 = undefined;
        const made = openFreshTemp(&tb, t.dir, occupied) orelse return error.NoTemp;
        defer _ = posix.close(made.fd);
        defer _ = posix.unlink(made.path.ptr);
        try std.testing.expect(!std.mem.endsWith(u8, made.path, occupied));
        try std.testing.expect(posix.write(made.fd, "x", 1) == 1);
    }
    var rb: [16]u8 = undefined;
    try std.testing.expectEqualStrings("keep", t.read("victim", &rb));
    try std.testing.expectEqualStrings("keep too", t.read("taken-file", &rb));
}

pub const PreflightDoc = struct {
    runs_differ: bool,
    operations: u32,
    marker_declared: bool,
    repeat: ?PreflightRepeat,
};

pub const PreflightRepeat = struct {
    gap_ms: u64,
    total: usize,
    diffs: []const PreflightDiff,
};

pub const PreflightDiff = struct {
    path: []const u8,
    how: []const u8,
    /// The byte line in its `.shape` form: where the runs first differ, how long each stretch
    /// is and what kind of bytes it holds. Never the `.bytes` form — the stretch two runs
    /// disagree on is where a per-run token or secret sits, and this document is what an MCP
    /// call and a CI log keep.
    shape: ?[]const u8,
};

test "a preflight difference's `how` is one of the four names docs/report-schema.md lists (#717)" {
    // The document writes `@tagName` of the snapshot's enum, and its schema is frozen from the
    // first release: a renamed member would rename a frozen value with no other test noticing.
    const names = std.meta.fieldNames(engine.Difference.How);
    try std.testing.expectEqual(@as(usize, 4), names.len);
    for (names, [_][]const u8{ "only_in_first", "only_in_second", "kind_differs", "content_differs" }) |got, want|
        try std.testing.expectEqualStrings(want, got);
}

pub const preflight_not_checked = [_][]const u8{ "kill landing", "world-side process boundaries", "baseline behavior", "checker falsification", "whether any world could fail" };

pub fn writePreflightJson(arena: std.mem.Allocator, path: []const u8, pd: PreflightDoc) void {
    const doc = buildPreflightJson(arena, pd) catch return jsonFailed("the document could not be built");
    writeJsonDoc(path, doc);
}

fn buildPreflightJson(arena: std.mem.Allocator, pd: PreflightDoc) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    const w = &buf;
    try w.appendSlice(arena, "{\n  \"schema\": \"sideeye/preflight\",\n  \"schema_status\": \"frozen\",\n");
    try w.print(arena, "  \"contract_version\": {d}", .{contract.contract_version});
    try w.print(arena, ",\n  \"outcome\": \"{s}\"", .{if (pd.runs_differ) "runs_differ" else "recording_accepted"});
    try w.print(arena, ",\n  \"exit_code\": {d}", .{@as(u8, if (pd.runs_differ) 1 else 0)});
    try w.print(arena, ",\n  \"crash_points\": {d}", .{pd.operations});
    try w.print(arena, ",\n  \"expected_status\": {d}", .{expected_status_val});
    try appendCwd(w, arena);
    try appendDeclarations(w, arena);
    try w.appendSlice(arena, ",\n  \"l0\": ");
    try jsonString(w, arena, l0_note);
    try w.appendSlice(arena, ",\n  \"oracle\": ");
    try jsonString(w, arena, oracle_note);
    if (recovery_note) |rn| {
        try w.appendSlice(arena, ",\n  \"recovery\": ");
        try jsonString(w, arena, rn);
    }
    try w.appendSlice(arena, ",\n  \"processes\": ");
    try jsonString(w, arena, boundary.boundaryAccount());
    if (pd.marker_declared) try w.appendSlice(arena, ",\n  \"marker_observed\": true");
    try jsonArrayField(w, arena, "not_checked", &preflight_not_checked, false);
    if (pd.repeat) |r| {
        try w.print(arena, ",\n  \"repeat_gap_ms\": {d}", .{r.gap_ms});
        try w.print(arena, ",\n  \"differences_total\": {d}", .{r.total});
        try w.appendSlice(arena, ",\n  \"differences\": [");
        for (r.diffs, 0..) |d, i| {
            try w.appendSlice(arena, if (i == 0) "\n    {\"path\": " else ",\n    {\"path\": ");
            try jsonString(w, arena, d.path);
            try w.appendSlice(arena, ", \"how\": ");
            try jsonString(w, arena, d.how);
            if (d.shape) |sh| {
                try w.appendSlice(arena, ", \"shape\": ");
                try jsonString(w, arena, sh);
            }
            try w.appendSlice(arena, "}");
        }
        try w.appendSlice(arena, if (r.diffs.len == 0) "]" else "\n  ]");
    }
    try appendFigures(w, arena);
    try appendJudgedSet(w, arena);
    try w.appendSlice(arena, "\n}\n");
    return buf.items;
}

test "the seal token is one fixed-length line under PIPE_BUF, in both forms, over the known vector (#597)" {
    var buf: [seal_len]u8 = undefined;
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("abc", &d, .{});
    const sealed = sealToken(&buf, d);
    try std.testing.expectEqualStrings(
        "sideeye: json sha256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;\n",
        sealed,
    );
    try std.testing.expectEqual(seal_len, sealed.len);
    // The exact width, not only a bound: the ADR and the buildlog quote this number, and a bound
    // lets them drift (found in review, where they said 88).
    try std.testing.expectEqual(@as(usize, 87), seal_len);
    // PIPE_BUF is 4096 on Linux and 512 on macOS; the token has to fit the smaller one for the
    // single write to be indivisible on either.
    try std.testing.expect(seal_len <= 512);
    var buf2: [seal_len]u8 = undefined;
    const none = sealToken(&buf2, null);
    try std.testing.expectEqualStrings("sideeye: json sha256=none;\n", none);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, sealed, seal_prefix));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, none, seal_prefix));
    try std.testing.expect(std.mem.indexOf(u8, "sideeye: the JSON report was not written: ", seal_prefix) == null);
}

/// a binary trace by hand to learn which operation a refusal refused on (#41). On
/// allocation failure the lead sentence alone is returned: the refusal is the point,
/// the naming is the courtesy, and the courtesy must never cost the refusal.
pub fn divergenceDetail(
    arena: std.mem.Allocator,
    lead: []const u8,
    index: usize,
    shim_ops: []const engine.Op,
    oracle_lines: []const []const u8,
    oracle_names: []const []const u8,
) []const u8 {
    const oracle_part = if (index < oracle_lines.len) blk: {
        // Assigned inside this arm on purpose: the other arm is the phantom case, where
        // the oracle has no line at this index and there is nothing to name.
        // reader produced it — strace's `openat`, fs_usage's `open`. Read from the list
        // rather than parsed back out of the quoted line, so both oracles answer (review
        // measured that parsing the line gives nothing on macOS: an fs_usage line opens
        // with a timestamp, not a call name).
        if (index < oracle_names.len and oracle_names[index].len > 0) divergence_syscall = oracle_names[index];
        break :blk std.fmt.allocPrint(arena, "the oracle saw: {s}", .{oracle_lines[index]}) catch return lead;
    } else std.fmt.allocPrint(arena, "the oracle's account ends after {d} operation(s)", .{index}) catch return lead;
    const shim_part = if (index < shim_ops.len) blk: {
        const op = shim_ops[index];
        break :blk if (op.aux.len > 0)
            std.fmt.allocPrint(arena, "{s} recorded: {s}(\"{s}\" -> \"{s}\")", .{ boundary.recorder(), @tagName(op.class), op.path, op.aux }) catch return lead
        else
            std.fmt.allocPrint(arena, "{s} recorded: {s}(\"{s}\")", .{ boundary.recorder(), @tagName(op.class), op.path }) catch return lead;
    } else std.fmt.allocPrint(arena, "{s}'s account ends after {d} operation(s)", .{ boundary.recorder(), index }) catch return lead;
    const composed = std.fmt.allocPrint(arena, "{s}; divergence at operation {d}: {s}; {s}", .{
        lead, index + 1, oracle_part, shim_part,
    }) catch return lead;
    // Shim paths are raw bytes the target chose, and even strace's own escaping is
    // not a contract this report should lean on: a filename carrying a newline or an
    // escape sequence must not be able to forge report lines (the class of #26). One
    // choke point, applied to the whole composed detail, keeps the text and the JSON
    // carrying the same bytes.
    return sanitizeForReport(arena, composed) catch lead;
}

test "divergence detail escapes a control byte a target put in a path" {
    // This calls `divergenceDetail`, which sets the module-level `divergence_syscall`;
    // leaving it set would hand a later test a field it never wrote (#337 review).
    defer divergence_syscall = "";
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const ops = [_]engine.Op{.{
        .class = .open,
        .seq = 1,
        .pid = 1,
        .tid = 1,
        .path = "/tmp/s/evil\nUNKNOWN  forged_reason",
        .aux = "",
    }};
    const lines = [_][]const u8{"openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3"};
    const names = [_][]const u8{"openat"};
    const detail = divergenceDetail(arena_state.allocator(), "lead", 0, &ops, &lines, &names);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "\\x0a") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "divergence at operation 1") != null);
}

test "a phantom divergence names no syscall: the oracle's account does not reach that index (#337)" {
    // what holds it. A reader tempted to fall back to `index - 1` would name the WRONG
    // operation, which is the failure this pins.
    defer divergence_syscall = "";
    divergence_syscall = "";
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const ops = [_]engine.Op{
        .{ .class = .open, .seq = 1, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" },
        .{ .class = .write, .seq = 2, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" },
    };
    const lines = [_][]const u8{"openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3"};
    const names = [_][]const u8{"openat"};
    const detail = divergenceDetail(arena_state.allocator(), "lead", 1, &ops, &lines, &names);
    try std.testing.expectEqualStrings("", divergence_syscall);
    try std.testing.expect(std.mem.indexOf(u8, detail, "the oracle's account ends after 1 operation(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "openat") == null);
}

test "the l0 note neutralises control bytes in target-chosen file names" {
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var plan: engine.L0Plan = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .files = .empty,
        .history_count = 1,
    };
    defer plan.deinit();
    try plan.files.append(plan.arena.allocator(), .{
        .rel = "evil\nname\x1b.log",
        .pre_kind = .file,
        .post_kind = .file,
        .form = .history,
        .pre_content = "a",
        .post_content = "ab",
    });

    const note = buildL0Note(arena_state.allocator(), plan);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, '\n') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, note, 0x1b) == null);
    try std.testing.expect(std.mem.indexOf(u8, note, "evil?name?.log") != null);
}

test "the not-tested list renders the same eight strings it shipped as two hand-written functions (#280)" {
    const want_text = [4][]const u8{
        "power loss, torn writes, concurrent processes",
        "power loss, torn writes, concurrent processes, appended tails (files under the history form)",
        "power loss, torn writes, concurrent processes, post-only file contents (L1 checks existence only; post-only link targets are judged)",
        "power loss, torn writes, concurrent processes, appended tails (files under the history form), post-only file contents (L1 checks existence only; post-only link targets are judged)",
    };
    const want_json = [4][]const u8{
        "[\"power loss\", \"torn writes\", \"concurrent processes\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]",
        "[\"power loss\", \"torn writes\", \"concurrent processes\", \"appended tails (files under the history form)\", \"post-only file contents (L1 checks existence only; post-only link targets are judged)\"]",
    };
    for (want_text, 0..) |w, i| try std.testing.expectEqualStrings(w, not_tested_text_by_variant[i]);
    for (want_json, 0..) |w, i| try std.testing.expectEqualStrings(w, not_tested_json_by_variant[i]);
    const scratch_item = "declared scratch paths (neither bytes nor presence judged)";
    for (want_text, 0..) |w, i| {
        const got = not_tested_text_by_variant[4 + i];
        try std.testing.expect(std.mem.startsWith(u8, got, w));
        try std.testing.expectEqualStrings(", " ++ scratch_item, got[w.len..]);
    }
    for (want_json, 0..) |w, i| {
        const got = not_tested_json_by_variant[4 + i];
        try std.testing.expect(std.mem.startsWith(u8, got, w[0 .. w.len - 1]));
        try std.testing.expectEqualStrings(", \"" ++ scratch_item ++ "\"]", got[w.len - 1 ..]);
    }
    try std.testing.expectEqual(@as(usize, 8), not_tested_text_by_variant.len);
}

test "the two renderings read the variant once, so they cannot describe different runs (#280)" {
    const saved_hist = l0_history_count;
    const saved_l1 = l1_configured;
    const saved_scratch = scratch_declared;
    defer {
        l0_history_count = saved_hist;
        l1_configured = saved_l1;
        scratch_declared = saved_scratch;
    }
    const one_scratch = [_][]const u8{"nondet.txt"};
    for ([_]bool{ false, true }) |s| {
        for ([_]bool{ false, true }) |h| {
            for ([_]bool{ false, true }) |l| {
                l0_history_count = if (h) 1 else 0;
                l1_configured = l;
                scratch_declared = if (s) &one_scratch else &.{};
                const want_v: usize = (if (h) @as(usize, 1) else 0) | (if (l) @as(usize, 2) else 0) | (if (s) @as(usize, 4) else 0);
                const v = notTestedVariant();
                try std.testing.expectEqual(want_v, v);
                try std.testing.expectEqualStrings(not_tested_text_by_variant[v], notTestedText());
                try std.testing.expectEqualStrings(not_tested_json_by_variant[v], notTestedJson());
                // Rebuilt from the item list, both forms, and compared for EQUALITY --
                // review measured that an `indexOf` on the JSON side lets a ghost item ride
                // along: appending one to the quoted rendering left the suite green.
                const items = not_tested_items_by_variant[v];
                var buf: [1024]u8 = undefined;
                var n: usize = 0;
                var jn: usize = 0;
                var jbuf: [1024]u8 = undefined;
                jbuf[jn] = '[';
                jn += 1;
                for (items, 0..) |item, i| {
                    try std.testing.expect(n + 2 + item.len <= buf.len);
                    try std.testing.expect(jn + 5 + item.len <= jbuf.len); // + the closing ']'
                    if (i != 0) {
                        @memcpy(buf[n..][0..2], ", ");
                        n += 2;
                        @memcpy(jbuf[jn..][0..2], ", ");
                        jn += 2;
                    }
                    @memcpy(buf[n..][0..item.len], item);
                    n += item.len;
                    jbuf[jn] = '"';
                    jn += 1;
                    @memcpy(jbuf[jn..][0..item.len], item);
                    jn += item.len;
                    jbuf[jn] = '"';
                    jn += 1;
                }
                jbuf[jn] = ']';
                jn += 1;
                try std.testing.expectEqualStrings(buf[0..n], notTestedText());
                try std.testing.expectEqualStrings(jbuf[0..jn], notTestedJson());
            }
        }
    }
}

test "an item that would need JSON escaping is rejected, and the ones shipped do not (#280)" {
    try std.testing.expect(notTestedNeedsEscaping("has a \" quote"));
    try std.testing.expect(notTestedNeedsEscaping("has a \\ backslash"));
    try std.testing.expect(notTestedNeedsEscaping("has a \n newline"));
    try std.testing.expect(notTestedNeedsEscaping("has a \t tab"));
    try std.testing.expect(!notTestedNeedsEscaping("power loss"));
    try std.testing.expect(!notTestedNeedsEscaping("post-only file contents (L1 checks existence only; post-only link targets are judged)"));
    for (not_tested_always) |item| try std.testing.expect(!notTestedNeedsEscaping(item));
    try std.testing.expect(!notTestedNeedsEscaping(not_tested_history));
    try std.testing.expect(!notTestedNeedsEscaping(not_tested_l1));
}

test "every OpClass name is its own tag, which is why the hand-written switch could go (#280)" {
    for (std.meta.tags(contract.OpClass)) |v| try std.testing.expectEqualStrings(@tagName(v), v.name());
    for (std.meta.tags(contract.UnknownReason)) |v| try std.testing.expectEqualStrings(@tagName(v), v.name());
    for (std.meta.tags(contract.SetupErrorReason)) |v| try std.testing.expectEqualStrings(@tagName(v), v.name());
    for (std.meta.tags(boundary.BoundaryEvidence.Kind)) |v| try std.testing.expectEqualStrings(@tagName(v), v.name());
}

test "the oracle account says no oracle was given only once the arguments were read to the end (#352)" {
    try std.testing.expectEqualStrings("not run (no --oracle given)", initialOracleNote(.none));
    try std.testing.expectEqualStrings(
        "not observable (no oracle ran; the shim does not interpose ownership/permission/timestamp calls)",
        initialMetadataNote(.none, false),
    );
    const states = [_]OracleAsked{ .unparsed, .{ .named = .strace }, .{ .named = .fs_usage } };
    for (states) |s| {
        try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(s), "no --oracle given") == null);
        try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(s, false), "no oracle ran") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.unparsed, false), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .strace }), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialOracleNote(.{ .named = .fs_usage }), "--oracle-fs-usage was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }, false), "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .fs_usage }, false), "--oracle-fs-usage was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialMetadataNote(.{ .named = .strace }, false), "capture was read") == null);
}

test "noteOracle assigns both accounts, and the initialiser is the unparsed state (#352)" {
    const saved_o = oracle_note;
    const saved_m = metadata_note;
    defer {
        oracle_note = saved_o;
        metadata_note = saved_m;
    }
    // Nothing else in this test binary assigns these globals, so what was saved is the
    // initialiser.
    try std.testing.expectEqualStrings(initialOracleNote(.unparsed), saved_o);
    try std.testing.expectEqualStrings(initialMetadataNote(.unparsed, false), saved_m);
    noteOracle(.{ .named = .strace });
    try std.testing.expect(std.mem.indexOf(u8, oracle_note, "--oracle was named") != null);
    try std.testing.expect(std.mem.indexOf(u8, metadata_note, "--oracle was named") != null);
    noteOracle(.none);
    try std.testing.expectEqualStrings("not run (no --oracle given)", oracle_note);
}

test "the checker and marker accounts say none was configured only once every source was read (#352)" {
    try std.testing.expectEqualStrings("none configured", checkerNoteFor(.none));
    try std.testing.expectEqualStrings("no marker configured", l1NoteFor(.none));
    const states = [_]Declared{ .unparsed, .named };
    for (states) |s| {
        try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(s), "none configured") == null);
        try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(s), "no marker configured") == null);
    }
    try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(.unparsed), "not established") != null);
    try std.testing.expect(std.mem.indexOf(u8, checkerNoteFor(.named), "configured") != null);
    try std.testing.expect(std.mem.indexOf(u8, l1NoteFor(.named), "marker configured") != null);
    try std.testing.expectEqualStrings(checkerNoteFor(.unparsed), checker_note);
    try std.testing.expectEqualStrings(l1NoteFor(.unparsed), l1_note);
}

/// Save and restore the three globals `publishJudgedPaths` writes. `zig build test` runs the
/// tests of one file in a shared binary, so a test that publishes a judged set would otherwise
/// leave it in front of whatever calls `buildJson` next — the shape the `scratch_declared` test
/// above uses by hand, factored out here because four tests need it rather than one.
const SavedJudged = struct {
    paths: []const []const u8,
    omitted: u32,
    classified: bool,

    fn save() SavedJudged {
        return .{ .paths = l0_judged_paths, .omitted = l0_judged_paths_omitted, .classified = l0_classified };
    }

    fn restore(self: SavedJudged) void {
        l0_judged_paths = self.paths;
        l0_judged_paths_omitted = self.omitted;
        l0_classified = self.classified;
    }
};

fn snapshotWithKinds(gpa: std.mem.Allocator, entries: []const engine.Entry) !engine.Snapshot {
    var snap: engine.Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    errdefer snap.arena.deinit();
    const a = snap.arena.allocator();
    for (entries) |e| try snap.entries.append(a, .{
        .rel = try a.dupe(u8, e.rel),
        .kind = e.kind,
        .content = try a.dupe(u8, e.content),
    });
    try engine.finalizeEntries(&snap);
    return snap;
}

test "the published judged set is the shared judged pairs, not the snapshot (#638, ADR 0079)" {
    // The field's whole point is the SET, and every acceptance fixture holds nothing but
    // shared regular files — so "the post snapshot minus scratch" passes all of them while
    // answering a different question. What `classifyWith` excludes is pinned here instead:
    // a path the operation created, a path it deleted, a kind the invariants cannot compare,
    // and a declared scratch path. A symlink present on both sides is judged (#122), so it
    // is in the fixture as the control against "regular files only".
    //
    // The unsupported kind is `file -> FIFO`, and the spelling is the point. `classifyWith`
    // walks the PRE entries, so a post-only FIFO never reaches its kind test at all — it is
    // dropped by the presence rule, exactly as `new.json` is, and a leg written that way
    // measures nothing about kinds (review caught this: the first version of this fixture had
    // `pipe` post-only and the kind test could be deleted with the suite still green). A pair
    // unsupported on BOTH sides cannot occur either, because `refuseUnsupportedEntry` reads the
    // initial snapshot before classification; it reads the final one AFTER, which is what makes
    // a path that was a file and became a FIFO the reachable spelling and this leg a real one.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var pre = try snapshotWithKinds(gpa, &.{
        .{ .rel = "gone.json", .kind = .file, .content = "the operation deletes this\n" },
        .{ .rel = "key.json", .kind = .file, .content = "key=1\n" },
        .{ .rel = "link", .kind = .symlink, .content = "key.json" },
        .{ .rel = "nondet.txt", .kind = .file, .content = "before\n" },
        .{ .rel = "pipe", .kind = .file, .content = "a file the operation replaces with a FIFO\n" },
    });
    defer pre.deinit();
    var post = try snapshotWithKinds(gpa, &.{
        .{ .rel = "key.json", .kind = .file, .content = "key=2\n" },
        .{ .rel = "link", .kind = .symlink, .content = "key.json" },
        .{ .rel = "new.json", .kind = .file, .content = "the operation creates this\n" },
        .{ .rel = "nondet.txt", .kind = .file, .content = "after\n" },
        .{ .rel = "pipe", .kind = .other, .content = "" },
    });
    defer post.deinit();

    const scratch = [_][]const u8{"nondet.txt"};
    var plan = try engine.classifyWith(gpa, pre, post, &scratch);
    defer plan.deinit();

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena_state.allocator(), plan);

    try std.testing.expect(l0_classified);
    try std.testing.expectEqual(@as(u32, 0), l0_judged_paths_omitted);
    // Equality, not containment: a containment test passes for an implementation that
    // publishes the whole snapshot, which is the implementation this exists to reject.
    const want = [_][]const u8{ "key.json", "link" };
    try std.testing.expectEqual(want.len, l0_judged_paths.len);
    for (want, l0_judged_paths) |w, got| try std.testing.expectEqualStrings(w, got);
}

test "a judged set past the cap is truncated and the remainder counted (#638, ADR 0079)" {
    // One over the cap, so the boundary is measured rather than a round number well past it.
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const n = max_judged_paths_listed + 1;
    const entries = try arena.alloc(engine.Entry, n);
    for (entries, 0..) |*e, i| {
        e.* = .{ .rel = try std.fmt.allocPrint(arena, "f{d:0>6}.txt", .{i}), .kind = .file, .content = "x" };
    }
    var pre = try snapshotWithKinds(gpa, entries);
    defer pre.deinit();
    var post = try snapshotWithKinds(gpa, entries);
    defer post.deinit();

    var plan = try engine.classifyWith(gpa, pre, post, &.{});
    defer plan.deinit();
    try std.testing.expectEqual(n, plan.files.items.len);

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena, plan);

    try std.testing.expectEqual(max_judged_paths_listed, l0_judged_paths.len);
    try std.testing.expectEqual(@as(u32, 1), l0_judged_paths_omitted);
    try std.testing.expectEqualStrings("f000000.txt", l0_judged_paths[0]);
    try std.testing.expectEqualStrings("f000999.txt", l0_judged_paths[max_judged_paths_listed - 1]);
}

test "the judged set stops at the byte ceiling before the entry ceiling (#638, ADR 0079)" {
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const name_len = 512;
    const n = 400; // 400 * 512 = 200 KiB of names, over the 64 KiB ceiling, under 1000 entries
    const entries = try arena.alloc(engine.Entry, n);
    for (entries, 0..) |*e, i| {
        const rel = try arena.alloc(u8, name_len);
        @memset(rel, 'x');
        _ = std.fmt.bufPrint(rel[0..8], "f{d:0>6}/", .{i}) catch unreachable;
        e.* = .{ .rel = rel, .kind = .file, .content = "x" };
    }
    var snap = try snapshotWithKinds(gpa, entries);
    defer snap.deinit();

    var plan = try engine.classifyWith(gpa, snap, snap, &.{});
    defer plan.deinit();
    try std.testing.expectEqual(n, plan.files.items.len);

    const saved = SavedJudged.save();
    defer saved.restore();
    publishJudgedPaths(arena, plan);

    // The entry ceiling did not bind — that is what makes this a test of the other one.
    try std.testing.expect(l0_judged_paths.len < max_judged_paths_listed);
    try std.testing.expectEqual(n - l0_judged_paths.len, @as(usize, l0_judged_paths_omitted));
    var bytes: usize = 0;
    for (l0_judged_paths) |q| bytes += q.len;
    try std.testing.expect(bytes <= max_judged_paths_bytes);
    try std.testing.expect(bytes + name_len > max_judged_paths_bytes);
}

test "a run that classified an empty judged set is not a run that never classified (#638)" {
    const gpa = std.testing.allocator;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();

    var empty = try snapshotWithKinds(gpa, &.{});
    defer empty.deinit();
    var plan = try engine.classifyWith(gpa, empty, empty, &.{});
    defer plan.deinit();

    const saved = SavedJudged.save();
    defer saved.restore();
    l0_classified = false;
    publishJudgedPaths(arena_state.allocator(), plan);

    try std.testing.expect(l0_classified);
    try std.testing.expectEqual(@as(usize, 0), l0_judged_paths.len);
    try std.testing.expectEqual(@as(u32, 0), l0_judged_paths_omitted);
}

test "under --observe supervised the divergence detail names the engine's account, not the shim's (#217)" {
    defer divergence_syscall = "";
    const saved = boundary.observe_mode;
    defer boundary.observe_mode = saved;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const ops = [_]engine.Op{.{ .class = .open, .seq = 1, .pid = 1, .tid = 1, .path = "/tmp/s/a", .aux = "" }};
    const lines = [_][]const u8{ "openat(AT_FDCWD, \"/tmp/s/a\", O_RDWR) = 3", "unlinkat(AT_FDCWD, \"/tmp/s/b\", 0) = 0" };
    const names = [_][]const u8{ "openat", "unlinkat" };

    boundary.observe_mode = .supervised;
    const held = divergenceDetail(arena, "lead", 0, &ops, &lines, &names);
    try std.testing.expect(std.mem.indexOf(u8, held, "the supervising engine recorded: open(\"/tmp/s/a\")") != null);
    const ended = divergenceDetail(arena, "lead", 1, &ops, &lines, &names);
    try std.testing.expect(std.mem.indexOf(u8, ended, "the supervising engine's account ends after 1 operation(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, held, "shim") == null);
    try std.testing.expect(std.mem.indexOf(u8, ended, "shim") == null);

    boundary.observe_mode = .wrappers;
    try std.testing.expect(std.mem.indexOf(u8, divergenceDetail(arena, "lead", 0, &ops, &lines, &names), "the shim recorded: open(\"/tmp/s/a\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, divergenceDetail(arena, "lead", 1, &ops, &lines, &names), "the shim's account ends after 1 operation(s)") != null);
}

test "under --observe supervised the metadata account names the engine's filter, re-derived once the mode is known (#217)" {
    const saved = metadata_note;
    const saved_asked = oracle_asked;
    defer {
        metadata_note = saved;
        oracle_asked = saved_asked;
    }
    for ([_]OracleAsked{ .unparsed, .none, .{ .named = .strace }, .{ .named = .fs_usage } }) |asked| {
        const sup = initialMetadataNote(asked, true);
        try std.testing.expect(std.mem.indexOf(u8, sup, "the supervising engine is not notified of ownership/permission/timestamp calls") != null);
        try std.testing.expect(std.mem.indexOf(u8, sup, "shim") == null);
        const def = initialMetadataNote(asked, false);
        try std.testing.expect(std.mem.indexOf(u8, def, "the shim does not interpose ownership/permission/timestamp calls") != null);
    }
    noteOracle(.{ .named = .strace });
    try std.testing.expect(std.mem.indexOf(u8, metadata_note, "the shim does not interpose") != null);
    noteObserver(true);
    try std.testing.expectEqualStrings(initialMetadataNote(.{ .named = .strace }, true), metadata_note);
    noteObserver(false);
    try std.testing.expectEqualStrings(initialMetadataNote(.{ .named = .strace }, false), metadata_note);
}
