//! The evidence bundle: what a FAIL measured, written for a maintainer who has never used
//! Sideeye (#607, ADR 0071).
//!
//! A saved case is a *question* — the define, the crash point and the landing context a
//! later replay re-asks (`src/case.zig`, ADR 0009). This file holds the *observation* that
//! stood beside it: which paths differ between the pre-operation state, the completed state
//! and the crashed one; whether a changed path existed before; whether its old bytes survive
//! anywhere else the run judged; what the checker said. The two are separate files for the
//! reason `docs/contract-freeze.md` surface 4 gives: a case's version and its shape travel
//! together, and every rung of that ladder so far (3 argv, 4 cwd, 5 scratch) is a *define*
//! field. Folding an observation in would move every case to version 6, so no case this
//! release writes would replay on any earlier 1.x — and each later evidence field would move
//! it again.
//!
//! **Everything here is measured at judgement time and nothing is recomputed later.** The
//! crashed snapshot is freed at the end of its world (`defer crashed.deinit()` in
//! `phaseExploration`) and the state directory is restored for the next one, so `measure`
//! runs where the three snapshots are all alive and `Draft` carries its answers out. Bytes
//! borrowed from a snapshot are duplicated into the run arena on the way out, for the reason
//! the `repeat_diff_slots` comment in `main.zig` records: `Difference.rel` borrows from
//! whichever snapshot holds the entry, and a value that escapes its snapshots has to own its
//! bytes.
//!
//! What this file will not do: rank severity, guess, or read anything back out of Sideeye's
//! own prose. A field it cannot establish is `unknown` and says so in the rendered bundle.

const std = @import("std");
const contract = @import("contract");
const engine = @import("engine.zig");
const posix = @import("posix.zig");
const report = @import("report.zig");
const defang = @import("defang.zig");
const capture = @import("capture.zig");
const cli = @import("cli.zig");

/// The evidence file's own schema version, independent of `case_version` on purpose.
pub const current_version: u32 = 1;

/// How many changed paths the bundle names individually. Past this the rendered bundle says
/// how many more there were rather than trimming silently — the same rule `DiffCount.total`
/// exists for on the snapshot side.
pub const path_slots: usize = 256;

/// The cap on the checker's captured output, matching the falsification probe's.
const checker_read_cap: usize = 1024 * 1024;

/// What the bundle can say about a question whose answer is not a plain yes or no.
///
/// `unknown` is a measurement outcome, not a default — every site that produces it names its
/// condition in `docs/evidence.md`. `not_applicable` is separate from it on purpose: a path
/// that did not exist before the operation has no old bytes, and answering "unknown" about
/// bytes that provably never existed spends the word this bundle needs for the cases where
/// the run genuinely could not tell. Measured 2026-09-17: the first real run of the
/// surviving-copy fixture put `unknown` on a file the operation had created, which reads as
/// a gap in the measurement and is not one.
pub const Answer = enum { yes, no, unknown, not_applicable };

/// One path's state in one snapshot. Absent is `null` at the field, so "the file was not
/// there" and "the file was there and empty" are different shapes rather than both being 0.
pub const Snap = struct {
    kind: []const u8,
    size: usize,
};

/// One changed path, as the three snapshots saw it.
pub const PathRow = struct {
    path: []const u8,
    /// The state directory before the operation ran.
    before: ?Snap,
    /// The state directory after the operation ran to completion (the recording's own final).
    completed: ?Snap,
    /// The state directory after the run that was killed at this crash point.
    crashed: ?Snap,
    pre_existing: bool,
    declared_scratch: bool,
    /// Whether the pre-operation bytes of this path are still present, byte for byte, at
    /// some *other* path inside the judged state.
    old_bytes_elsewhere: Answer,
    /// The path they were found at; empty unless `old_bytes_elsewhere == .yes`.
    old_bytes_at: []const u8,
};

pub const Boundary = struct {
    /// The last state-changing operation that completed in this world.
    after_op: []const u8,
    after_path: []const u8,
    /// The operation the kill landed in front of, which never ran.
    before_op: []const u8,
    before_path: []const u8,
};

pub const Checker = struct {
    configured: bool,
    /// `null` when no checker was configured.
    failed: ?bool,
    /// The checker's own last non-empty output line in the exhibit's world, defanged and
    /// clipped. `null` when no checker ran, or when its output could not be read back —
    /// which is why this is an optional rather than an empty string.
    diagnostic: ?[]const u8,
};

/// A string rather than an enum so #606 can add a member without moving `evidence_version`.
pub const Recovery = struct {
    result: []const u8,
};

/// Which of a run's two saved exhibits this bundle describes (#231, ADR 0020). A run can
/// save both: the overall earliest failing world, and the earliest world the declared checker
/// rejected — the second is structurally later whenever they differ. The field exists from
/// version 1 because a bundle that cannot say which one it is has to guess, and the first
/// renderer guessed "the earliest" unconditionally for both.
pub const Exhibit = enum { earliest, checker };

pub const Target = struct {
    operation: []const u8,
    state_root: []const u8,
};

/// The whole bundle, as it is written to disk and as `sideeye evidence` reads it back.
/// Parsed strictly on the way in: an unknown field is a file from a future schema.
pub const Evidence = struct {
    schema: []const u8,
    evidence_version: u32,
    sideeye_version: []const u8,
    contract_version: u32,
    target: Target,
    exhibit: Exhibit,
    crash_point: u32,
    crash_points_total: u32,
    boundary: Boundary,
    invariant: []const u8,
    subject: []const u8,
    observed: []const u8,
    consequence: []const PathRow,
    /// True when more paths differed than `path_slots` could hold. The rendered bundle says
    /// so; it never presents a trimmed list as the whole list.
    consequence_truncated: bool,
    checker: Checker,
    replay: []const u8,
    case: []const u8,
    recovery: Recovery,
    caveats: []const []const u8,
};

/// What `measure` establishes inside the world loop, where the snapshots are alive. The rest
/// of `Evidence` is assembled in `phaseReport` from values that are only final after the loop.
pub const Draft = struct {
    consequence: []const PathRow,
    consequence_truncated: bool,
    checker: Checker,
};

/// What the world loop knows about the checker in the world being measured.
pub const CheckerObservation = struct {
    configured: bool,
    failed: bool,
    /// The capture file the checker's output went to, or null when there was no checker or
    /// the capture could not be opened. Read here rather than by the caller so the read
    /// happens in the same world — the next world overwrites the file.
    output_path: ?[]const u8,
};

fn kindName(k: posix.Kind) []const u8 {
    return switch (k) {
        .file => "file",
        .dir => "directory",
        .symlink => "symlink",
        .other => "other",
        .missing => "missing",
    };
}

fn snapOf(s: engine.Snapshot, rel: []const u8) ?Snap {
    const e = s.find(rel) orelse return null;
    return .{ .kind = kindName(e.kind), .size = e.content.len };
}

/// Merge two sorted difference lists into the sorted union of their `rel`s, into `out`.
/// Both producers walk sorted, unique entry lists, so each list is itself sorted and unique.
fn unionRels(a: []const engine.Difference, b: []const engine.Difference, out: [][]const u8) usize {
    var i: usize = 0;
    var j: usize = 0;
    var n: usize = 0;
    while ((i < a.len or j < b.len) and n < out.len) {
        const take_a = if (i >= a.len) false else if (j >= b.len) true else switch (std.mem.order(u8, a[i].rel, b[j].rel)) {
            .lt, .eq => true,
            .gt => false,
        };
        if (take_a) {
            // `.eq` above takes the a-side and advances both, so a path both comparisons
            // report appears once. Advancing only `i` would emit it twice and the bundle
            // would show one path as two rows.
            if (j < b.len and std.mem.eql(u8, a[i].rel, b[j].rel)) j += 1;
            out[n] = a[i].rel;
            i += 1;
        } else {
            out[n] = b[j].rel;
            j += 1;
        }
        n += 1;
    }
    return n;
}

/// Does any path other than `rel` hold `want`, byte for byte, in the crashed state?
///
/// Regular files only. A symlink's recorded content is its target string, and a directory's
/// is empty, so neither can be a byte-identical copy of a file's contents; counting them
/// would be a hit that is not a copy. The search does not leave the judged state — what a
/// target wrote outside `--state` was never snapshotted, and `docs/evidence.md` says so
/// rather than letting `no` be read as "nowhere on the machine".
fn findCopy(crashed: engine.Snapshot, rel: []const u8, want: []const u8) ?[]const u8 {
    for (crashed.entries.items) |e| {
        if (e.kind != .file) continue;
        if (std.mem.eql(u8, e.rel, rel)) continue;
        if (std.mem.eql(u8, e.content, want)) return e.rel;
    }
    return null;
}

/// Measure the crashed world against the two states it is judged against. Called once, from
/// the world loop, for each exhibit — the overall earliest failure and, when it is a
/// different world, the earliest the checker rejected.
///
/// `initial` and `final` outlive the loop; `crashed` does not, which is why every byte this
/// returns is duplicated into `arena`.
pub fn measure(
    arena: std.mem.Allocator,
    initial: engine.Snapshot,
    final: engine.Snapshot,
    crashed: engine.Snapshot,
    plan: engine.L0Plan,
    checker: CheckerObservation,
) error{OutOfMemory}!Draft {
    const pre_diffs = try arena.alloc(engine.Difference, path_slots);
    const post_diffs = try arena.alloc(engine.Difference, path_slots);
    // Deliberately NOT `diffSnapshotsExcept`: a declared scratch path is exactly what
    // acceptance 4's second fixture is about, and leaving it out here would make
    // `declared_scratch` a column that can only ever read `no`. The judgement leaves scratch
    // alone (ADR 0043); the bundle names it and marks it.
    const pre = engine.diffSnapshots(initial, crashed, pre_diffs);
    const post = engine.diffSnapshots(final, crashed, post_diffs);

    const rels = try arena.alloc([]const u8, path_slots);
    const n = unionRels(pre_diffs[0..pre.stored], post_diffs[0..post.stored], rels);

    const rows = try arena.alloc(PathRow, n);
    for (rels[0..n], 0..) |rel, idx| {
        const before = snapOf(initial, rel);
        const pre_entry = initial.find(rel);
        // What this run did not see, as distinct from what it saw was absent: a recorded
        // rename moved a subtree in from outside the judged root (#405, ADR 0032), which was
        // never snapshotted, so "no copy here" would be a claim about a tree nothing read.
        // One search, not one per answer. `findCopy` walks every entry of the crashed
        // snapshot comparing contents, which is the only part of `measure` that is not
        // linear in the number of rows; asking it again for the path it just found would
        // double the one cost here that a large state tree actually feels.
        var found_at: ?[]const u8 = null;
        const survives: Answer = blk: {
            // Asked first: a path the operation created has no pre-operation bytes, so the
            // question does not arise. This is not the same as not knowing.
            const pe = pre_entry orelse break :blk .not_applicable;
            if (report.attributed_to_rename > 0) break :blk .unknown;
            // A directory's recorded content is empty and a symlink's is its target string,
            // so neither has file bytes to look for; and empty bytes match every empty file,
            // which would make `yes` mean nothing. Both are genuinely unanswerable here.
            if (pe.kind != .file or pe.content.len == 0) break :blk .unknown;
            found_at = findCopy(crashed, rel, pe.content);
            break :blk if (found_at != null) .yes else .no;
        };
        const at: []const u8 = if (found_at) |f| try arena.dupe(u8, f) else "";
        rows[idx] = .{
            .path = try arena.dupe(u8, rel),
            .before = before,
            .completed = snapOf(final, rel),
            .crashed = snapOf(crashed, rel),
            .pre_existing = pre_entry != null,
            .declared_scratch = plan.isScratch(rel),
            .old_bytes_elsewhere = survives,
            .old_bytes_at = at,
        };
    }

    return .{
        .consequence = rows,
        .consequence_truncated = pre.total > pre.stored or post.total > post.stored or n == path_slots,
        .checker = .{
            .configured = checker.configured,
            .failed = if (checker.configured) checker.failed else null,
            .diagnostic = if (checker.output_path) |p| lastLine(arena, p) else null,
        },
    };
}

/// The checker's last non-empty output line, defanged and clipped — the one line most worth
/// pasting into an upstream report.
///
/// `require_regular`, like the setup capture's read and unlike the falsification and world
/// captures': the path is under `--work`, and between the engine's own `O_EXCL` create and
/// this read sits a window a live child of the target can reach. A FIFO planted there is the
/// #400 shape, and without the flag the open waits in it — inside a world loop, with nothing
/// to time it out.
///
/// Not `report.setupOutputDetail`: that one renders into a file-scope buffer whose safety
/// rests on every caller being on its way to a `setupError` (noreturn), and this runs once
/// per exhibit inside a loop that keeps going. It also deletes an empty capture, which is the
/// setup path's business and not this one's. The line-picking rule IS shared, though —
/// `capture.lastNonEmptyLine`, rather than a second copy of "last line that holds anything".
fn lastLine(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const text = capture.readFileAllocCapped(arena, path, checker_read_cap, .{
        .require_regular = true,
        .no_follow = true,
    }) orelse return null;
    const chosen = capture.lastNonEmptyLine(text);
    if (chosen.len == 0) return null;
    var names: std.ArrayList(u8) = .empty;
    // The checker's bytes are target-influenced the way a file name is, so they go through
    // the same choke point before they reach a line of output (#26, #167).
    defang.appendSanitized(&names, arena, chosen) catch return null;
    const clipped = if (names.items.len > 400) names.items[0..400] else names.items;
    return clipped;
}

/// The sentences the report already carries about what this run could and could not see.
/// Copied from the same variables the report reads, never re-derived: two derivations of one
/// fact drift, and this one would drift towards the flattering side.
pub fn caveats(arena: std.mem.Allocator, truncated: bool) error{OutOfMemory}![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    const buf = &list;
    if (!report.oracle_verified) try buf.append(
        arena,
        "No oracle confirmed that Sideeye saw every state-changing operation of this run, so the crash points are what it observed rather than everything that happened.",
    );
    if (report.attributed_to_rename > 0) try buf.append(arena, try std.fmt.allocPrint(
        arena,
        "{d} path(s) were attributed wholesale to a directory a recorded rename moved in from outside the judged tree; that source subtree was never snapshotted.",
        .{report.attributed_to_rename},
    ));
    if (report.scratch_declared.len > 0) try buf.append(arena, try std.fmt.allocPrint(
        arena,
        "The define declared {d} scratch path(s); the built-in invariants judge none of them, in any world.",
        .{report.scratch_declared.len},
    ));
    if (truncated) try buf.append(
        arena,
        "More paths differed than this bundle lists individually; the table is the first 256 in path order.",
    );
    return buf.items;
}

/// What differs between a run's two exhibits. Everything else a bundle carries is the same for
/// both — the schema, the versions, the target, the caveats, `recovery` — and `save` fills
/// those once.
pub const Exhibited = struct {
    exhibit: Exhibit,
    crash_point: u32,
    boundary: Boundary,
    invariant: []const u8,
    subject: []const u8,
    observed: []const u8,
    replay: []const u8,
    case_path: []const u8,
    draft: Draft,
};

/// Build a bundle for one exhibit and write it beside `case_file`, returning its path or null.
///
/// One constructor for both exhibits, rather than the two near-identical struct literals the
/// first version had at the two call sites: eight fields that do not vary between them were
/// spelled twice, and a ninth added to one of the two would have shipped a bundle that carries
/// a field on the earliest exhibit and not on the claim exhibit. It lives here rather than in
/// `main.zig` for the reason the rest of this file does — and because `main.zig` is at the
/// declaration ceiling `spike/check-main-shape.sh` holds it to.
pub fn save(
    arena: std.mem.Allocator,
    case_file: []const u8,
    operation: []const u8,
    state_root: []const u8,
    crash_points_total: u32,
    e: Exhibited,
) ?[]const u8 {
    const cav = caveats(arena, e.draft.consequence_truncated) catch return null;
    return write(arena, case_file, .{
        .schema = "sideeye/evidence",
        .evidence_version = current_version,
        .sideeye_version = cli.version,
        .contract_version = contract.contract_version,
        .target = .{ .operation = operation, .state_root = state_root },
        .exhibit = e.exhibit,
        .crash_point = e.crash_point,
        .crash_points_total = crash_points_total,
        .boundary = e.boundary,
        .invariant = e.invariant,
        .subject = e.subject,
        .observed = e.observed,
        .consequence = e.draft.consequence,
        .consequence_truncated = e.draft.consequence_truncated,
        .checker = e.draft.checker,
        .replay = e.replay,
        .case = e.case_path,
        // #606's slot, held open from the first version so adding a result later is a value
        // change and not a schema change. A string, not an enum, for the same reason.
        .recovery = .{ .result = "not_configured" },
        .caveats = cav,
    });
}

/// A command as one line, for the bundle's "what happened" sentence. The engine holds the
/// operation as argv; a maintainer reads a command line.
pub fn joinArgv(arena: std.mem.Allocator, argv: []const []const u8) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (argv, 0..) |a, i| {
        if (i != 0) try out.append(arena, ' ');
        // A target chose these bytes, so they pass the same choke point a file name does
        // before they reach a line of output (#26, #167).
        try defang.appendSanitized(&out, arena, a);
    }
    return out.items;
}

// ---- writing -----------------------------------------------------------------------

fn jsonSnap(w: *std.ArrayList(u8), arena: std.mem.Allocator, s: ?Snap) !void {
    const v = s orelse {
        try w.appendSlice(arena, "null");
        return;
    };
    try w.appendSlice(arena, "{\"kind\": ");
    try report.jsonString(w, arena, v.kind);
    try w.print(arena, ", \"size\": {d}}}", .{v.size});
}

fn jsonBool(w: *std.ArrayList(u8), arena: std.mem.Allocator, b: bool) !void {
    try w.appendSlice(arena, if (b) "true" else "false");
}

/// Render the bundle as the JSON document `sideeye evidence` reads back.
pub fn buildJson(arena: std.mem.Allocator, ev: Evidence) ![]const u8 {
    var doc: std.ArrayList(u8) = .empty;
    const w = &doc;
    try w.appendSlice(arena, "{\n  \"schema\": ");
    try report.jsonString(w, arena, ev.schema);
    try w.print(arena, ",\n  \"evidence_version\": {d}", .{ev.evidence_version});
    try w.appendSlice(arena, ",\n  \"sideeye_version\": ");
    try report.jsonString(w, arena, ev.sideeye_version);
    try w.print(arena, ",\n  \"contract_version\": {d}", .{ev.contract_version});
    try w.appendSlice(arena, ",\n  \"target\": {\"operation\": ");
    try report.jsonString(w, arena, ev.target.operation);
    try w.appendSlice(arena, ", \"state_root\": ");
    try report.jsonString(w, arena, ev.target.state_root);
    // One brace, not two: `{{`/`}}` are escapes of `std.fmt`, and this line moved out of a
    // `print` into an `appendSlice`, which takes its bytes literally.
    try w.appendSlice(arena, "},\n  \"exhibit\": ");
    try report.jsonString(w, arena, @tagName(ev.exhibit));
    try w.print(arena, ",\n  \"crash_point\": {d}", .{ev.crash_point});
    try w.print(arena, ",\n  \"crash_points_total\": {d}", .{ev.crash_points_total});
    try w.appendSlice(arena, ",\n  \"boundary\": {\"after_op\": ");
    try report.jsonString(w, arena, ev.boundary.after_op);
    try w.appendSlice(arena, ", \"after_path\": ");
    try report.jsonString(w, arena, ev.boundary.after_path);
    try w.appendSlice(arena, ", \"before_op\": ");
    try report.jsonString(w, arena, ev.boundary.before_op);
    try w.appendSlice(arena, ", \"before_path\": ");
    try report.jsonString(w, arena, ev.boundary.before_path);
    try w.appendSlice(arena, "},\n  \"invariant\": ");
    try report.jsonString(w, arena, ev.invariant);
    try w.appendSlice(arena, ",\n  \"subject\": ");
    try report.jsonString(w, arena, ev.subject);
    try w.appendSlice(arena, ",\n  \"observed\": ");
    try report.jsonString(w, arena, ev.observed);
    try w.appendSlice(arena, ",\n  \"consequence\": [");
    for (ev.consequence, 0..) |r, i| {
        try w.appendSlice(arena, if (i == 0) "\n    {\"path\": " else ",\n    {\"path\": ");
        try report.jsonString(w, arena, r.path);
        try w.appendSlice(arena, ", \"before\": ");
        try jsonSnap(w, arena, r.before);
        try w.appendSlice(arena, ", \"completed\": ");
        try jsonSnap(w, arena, r.completed);
        try w.appendSlice(arena, ", \"crashed\": ");
        try jsonSnap(w, arena, r.crashed);
        try w.appendSlice(arena, ", \"pre_existing\": ");
        try jsonBool(w, arena, r.pre_existing);
        try w.appendSlice(arena, ", \"declared_scratch\": ");
        try jsonBool(w, arena, r.declared_scratch);
        try w.appendSlice(arena, ", \"old_bytes_elsewhere\": ");
        try report.jsonString(w, arena, @tagName(r.old_bytes_elsewhere));
        try w.appendSlice(arena, ", \"old_bytes_at\": ");
        try report.jsonString(w, arena, r.old_bytes_at);
        try w.appendSlice(arena, "}");
    }
    try w.appendSlice(arena, if (ev.consequence.len == 0) "]" else "\n  ]");
    try w.appendSlice(arena, ",\n  \"consequence_truncated\": ");
    try jsonBool(w, arena, ev.consequence_truncated);
    try w.appendSlice(arena, ",\n  \"checker\": {\"configured\": ");
    try jsonBool(w, arena, ev.checker.configured);
    try w.appendSlice(arena, ", \"failed\": ");
    if (ev.checker.failed) |f| try jsonBool(w, arena, f) else try w.appendSlice(arena, "null");
    try w.appendSlice(arena, ", \"diagnostic\": ");
    if (ev.checker.diagnostic) |d| try report.jsonString(w, arena, d) else try w.appendSlice(arena, "null");
    try w.appendSlice(arena, "},\n  \"replay\": ");
    try report.jsonString(w, arena, ev.replay);
    try w.appendSlice(arena, ",\n  \"case\": ");
    try report.jsonString(w, arena, ev.case);
    try w.appendSlice(arena, ",\n  \"recovery\": {\"result\": ");
    try report.jsonString(w, arena, ev.recovery.result);
    try w.appendSlice(arena, "},\n  \"caveats\": [");
    for (ev.caveats, 0..) |c, i| {
        try w.appendSlice(arena, if (i == 0) "\n    " else ",\n    ");
        try report.jsonString(w, arena, c);
    }
    try w.appendSlice(arena, if (ev.caveats.len == 0) "]" else "\n  ]");
    try w.appendSlice(arena, "\n}\n");
    return doc.items;
}

/// `<dir>/NNNNNN.json` -> `<dir>/NNNNNN.evidence.json`. A path already in the evidence form
/// is returned as itself, so `sideeye evidence` takes either name.
pub fn siblingPath(arena: std.mem.Allocator, case_path: []const u8) error{OutOfMemory}![]const u8 {
    const suffix = ".evidence.json";
    if (std.mem.endsWith(u8, case_path, suffix)) return case_path;
    const stem = if (std.mem.endsWith(u8, case_path, ".json"))
        case_path[0 .. case_path.len - ".json".len]
    else
        case_path;
    return std.fmt.allocPrint(arena, "{s}{s}", .{ stem, suffix });
}

/// Write the bundle beside its case and return the path, or null when it could not be
/// written. Null is not a failure of the run: the FAIL report and the case are the product,
/// and an attachment must not take them down with it — the same rule `writeCase` keeps.
///
/// Called only once its case was written. The case ids are claimed `O_EXCL` and this name is
/// derived from one, so the evidence file claims no id of its own and the ordering invariant
/// the report documents — in a fresh work directory `000001` belongs to the overall earliest
/// — is untouched by whether this succeeds.
pub fn write(arena: std.mem.Allocator, case_path: []const u8, ev: Evidence) ?[]const u8 {
    const path = siblingPath(arena, case_path) catch return null;
    const doc = buildJson(arena, ev) catch return null;
    var pbuf: [contract.max_path]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&pbuf, "{s}", .{path}) catch return null;
    _ = posix.unlink(pz.ptr);
    const fd = posix.open(pz.ptr, posix.O_WRONLY | posix.O_CREAT | posix.O_EXCL, @as(c_uint, 0o644));
    if (fd < 0) return null;
    var off: usize = 0;
    while (off < doc.len) {
        const n = posix.write(fd, doc[off..].ptr, doc.len - off);
        if (n <= 0) {
            // A half-written bundle would be read back as a whole one — the reader has no
            // way to tell. Remove it rather than leave it, exactly as `writeCase` does.
            _ = posix.close(fd);
            _ = posix.unlink(pz.ptr);
            return null;
        }
        off += @intCast(n);
    }
    _ = posix.close(fd);
    return path;
}

// ---- rendering ---------------------------------------------------------------------

fn answerWord(a: Answer) []const u8 {
    return switch (a) {
        .yes => "yes",
        .no => "no",
        .unknown => "unknown",
        // Rendered as a dash rather than the tag: a table column reading `not_applicable`
        // invites the reader to wonder what was not applied.
        .not_applicable => "—",
    };
}

fn yesNo(b: bool) []const u8 {
    return if (b) "yes" else "no";
}

fn cell(w: *std.ArrayList(u8), arena: std.mem.Allocator, s: ?Snap) error{OutOfMemory}!void {
    const v = s orelse {
        try w.appendSlice(arena, "absent");
        return;
    };
    if (std.mem.eql(u8, v.kind, "file"))
        try w.print(arena, "file, {d} bytes", .{v.size})
    else
        // `asText` here for the same reason as every other string this file renders, and
        // missed on the first pass because a kind looks like the engine's own vocabulary:
        // it is a `[]const u8` parsed out of the bundle, and a crafted one can hold a
        // newline and a heading exactly as a path can.
        try w.appendSlice(arena, asText(arena, v.kind));
}

/// Every string that reaches the terminal from a bundle passes this first (#26, #167).
///
/// Not only the file names: the bundle is a file in the work directory, which the judged
/// program can write — `docs/cli.md` says a target handing Sideeye an artefact it wrote
/// itself is not something any flag stops — so on this path every field is target-influenced,
/// whoever produced the one in hand. The JSON side is escaped by `report.jsonString`; this is
/// the text side's equivalent, the same choke point `main.zig` puts every report line through.
///
/// Measured before this existed (2026-09-17): a bundle whose `consequence[].path` held
/// newlines rendered a `## Severity` heading and the word `critical` into the document, which
/// is precisely what the page's promise says a bundle never carries.
fn asText(arena: std.mem.Allocator, s: []const u8) []const u8 {
    return defang.textShown(arena, s);
}

/// The bundle as Markdown, for pasting into an upstream issue.
///
/// Every line here is a field of `ev`. Nothing is inferred from another field, and no
/// sentence ranks what it describes: a maintainer decides what the measurement is worth,
/// which is the whole reason the impact columns are here instead of a label.
pub fn render(arena: std.mem.Allocator, ev: Evidence) error{OutOfMemory}![]const u8 {
    var doc: std.ArrayList(u8) = .empty;
    const w = &doc;

    try w.appendSlice(arena, "## What happened\n\n");
    try w.print(arena, "`{s}` was interrupted between two of its own file operations. ", .{asText(arena, ev.target.operation)});
    // Which exhibit this is, said rather than assumed. A run can save two (#231, ADR 0020):
    // the overall earliest, and the earliest world the declared checker rejected — which is
    // structurally later whenever the two differ. An unconditional "this is the earliest"
    // was false on the second bundle, and no field distinguished them until this one.
    if (ev.exhibit == .earliest)
        try w.print(arena, "This is crash point {d} of {d} that Sideeye explored; it is the earliest one whose result differed.\n\n", .{ ev.crash_point, ev.crash_points_total })
    else
        try w.print(arena, "This is crash point {d} of {d} that Sideeye explored; it is the earliest one the declared checker rejected, which is not necessarily the earliest one that differed.\n\n", .{ ev.crash_point, ev.crash_points_total });

    try w.appendSlice(arena, "## Consequence\n\n");
    if (ev.consequence.len == 0) {
        try w.appendSlice(arena, "No path under the judged state directory differed between the three states.\n\n");
    } else {
        try w.appendSlice(arena, "| Path | Before | After a completed run | After the interruption | Existed before | Old bytes elsewhere | Declared scratch |\n");
        try w.appendSlice(arena, "|---|---|---|---|---|---|---|\n");
        for (ev.consequence) |r| {
            try w.appendSlice(arena, "| `");
            try w.appendSlice(arena, asText(arena, r.path));
            try w.appendSlice(arena, "` | ");
            try cell(w, arena, r.before);
            try w.appendSlice(arena, " | ");
            try cell(w, arena, r.completed);
            try w.appendSlice(arena, " | ");
            try cell(w, arena, r.crashed);
            try w.print(arena, " | {s} | {s}", .{ yesNo(r.pre_existing), answerWord(r.old_bytes_elsewhere) });
            if (r.old_bytes_elsewhere == .yes) {
                try w.appendSlice(arena, " (at `");
                try w.appendSlice(arena, asText(arena, r.old_bytes_at));
                try w.appendSlice(arena, "`)");
            }
            try w.print(arena, " | {s} |\n", .{yesNo(r.declared_scratch)});
        }
        if (ev.consequence_truncated)
            try w.appendSlice(arena, "\nMore paths differed than this table lists; see the caveats below.\n");
        try w.appendSlice(arena, "\n`Old bytes elsewhere` asks whether the path's pre-interruption contents are still present, byte for byte, somewhere else inside the judged state directory. `unknown` means this run could not establish it either way; a dash means the path did not exist before, so it had no old bytes.\n\n");
    }

    try w.appendSlice(arena, "## Where it was interrupted\n\n```\n");
    try w.print(arena, "{s: <8}{s}\n", .{ "after:", asText(arena, ev.boundary.after_op) });
    try w.print(arena, "        {s}\n", .{asText(arena, ev.boundary.after_path)});
    try w.appendSlice(arena, "<-- the process was terminated here -->\n");
    try w.print(arena, "{s: <8}{s}\n", .{ "before:", asText(arena, ev.boundary.before_op) });
    try w.print(arena, "        {s}\n", .{asText(arena, ev.boundary.before_path)});
    try w.appendSlice(arena, "```\n\nThe operation named under `after` completed; the one under `before` never ran.\n\n");

    try w.appendSlice(arena, "## Built-in invariant\n\n");
    try w.print(arena, "{s} — {s}: {s}\n\n", .{ asText(arena, ev.invariant), asText(arena, ev.subject), asText(arena, ev.observed) });

    try w.appendSlice(arena, "## Checker\n\n");
    if (!ev.checker.configured) {
        try w.appendSlice(arena, "None was configured, so nothing here says whether the resulting state is correct for the application.\n\n");
    } else {
        try w.print(arena, "The define's own checker {s} in this world.\n\n", .{if (ev.checker.failed orelse false) "rejected the state" else "accepted the state"});
        if (ev.checker.diagnostic) |d| {
            try w.appendSlice(arena, "Its last output line:\n\n> ");
            try w.appendSlice(arena, asText(arena, d));
            try w.appendSlice(arena, "\n\n");
        } else {
            try w.appendSlice(arena, "Its output could not be read back, so what it said is unknown.\n\n");
        }
    }

    try w.appendSlice(arena, "## Reproducing it\n\n```\n");
    try w.appendSlice(arena, asText(arena, ev.replay));
    try w.appendSlice(arena, "\n```\n\n");
    try w.print(arena, "Saved case: `{s}`\n\n", .{asText(arena, ev.case)});

    try w.appendSlice(arena, "## Recovery\n\n");
    if (std.mem.eql(u8, ev.recovery.result, "not_configured"))
        try w.appendSlice(arena, "Not configured — this run did not measure whether the tool repairs the state on its next start.\n\n")
    else
        try w.print(arena, "{s}\n\n", .{asText(arena, ev.recovery.result)});

    try w.appendSlice(arena, "## What this measurement did and did not establish\n\n");
    if (ev.caveats.len == 0) {
        try w.appendSlice(arena, "- The run carried no observation caveats.\n");
    } else {
        for (ev.caveats) |c| {
            try w.appendSlice(arena, "- ");
            try w.appendSlice(arena, asText(arena, c));
            try w.appendSlice(arena, "\n");
        }
    }
    try w.print(arena, "\nMeasured by Sideeye {s} (trace contract v{d}) against `{s}`.\n", .{ asText(arena, ev.sideeye_version), ev.contract_version, asText(arena, ev.target.state_root) });
    return doc.items;
}

// ---- the subcommand ----------------------------------------------------------------

fn fail(msg: []const u8) u8 {
    const lead = "sideeye: ";
    _ = posix.write(2, lead.ptr, lead.len);
    _ = posix.write(2, msg.ptr, msg.len);
    _ = posix.write(2, "\n", 1);
    // 3, not 2: exit 2 is UNKNOWN, a verdict, and this command produces none
    // (`docs/contract-freeze.md` surface 3). The unknown-mode banner exits 3 as well.
    return 3;
}

/// `sideeye evidence <case.json>` — render the bundle saved beside a case.
///
/// No flags, deliberately. The machine-readable form is the evidence file itself, whose path
/// the report names beside the case's; a `--format json` would be a second way to ask for
/// bytes that are already on disk.
pub fn runCommand(gpa: std.mem.Allocator, case_arg: []const u8) u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const path = siblingPath(arena, case_arg) catch return fail("out of memory");
    const text = capture.readFileAllocCapped(arena, path, 16 * 1024 * 1024, .{ .require_regular = true }) orelse
        return fail("no evidence file could be read beside that case. A bundle is written when the FAIL is found, by a sideeye new enough to write one; an older case has none, and re-running the define writes it.");
    // Unknown fields are ignored here, unlike in a saved case. The two files answer to
    // different rules: a case is a frozen question, and a field it does not understand means
    // it is not the question this engine can re-ask, so `ReplayCase` refuses. A bundle is a
    // record, and the useful direction for a record is the report schema's — a consumer
    // tolerates fields it does not know (`docs/contract-freeze.md`, surface 2). Without this,
    // the first field added at version 2 would make every version-1 bundle already on disk
    // unreadable by a sideeye that could still read it perfectly well.
    const parsed = std.json.parseFromSlice(Evidence, arena, text, .{ .ignore_unknown_fields = true }) catch
        return fail("the evidence file could not be parsed as a sideeye evidence bundle");
    const ev = parsed.value;
    if (!std.mem.eql(u8, ev.schema, "sideeye/evidence")) return fail("that file is not a sideeye evidence bundle");
    // Refuses upward only: a bundle from a newer sideeye may carry fields whose ABSENCE this
    // reader would misread, which is a different thing from not knowing extra ones.
    if (ev.evidence_version > current_version) return fail("that evidence bundle was written by a newer sideeye than this one");

    const out = render(arena, ev) catch return fail("out of memory");
    var off: usize = 0;
    while (off < out.len) {
        const n = posix.write(1, out[off..].ptr, out.len - off);
        if (n <= 0) return fail("the bundle was cut short; stdout stopped accepting output");
        off += @intCast(n);
    }
    return 0;
}

// ---- tests --------------------------------------------------------------------------

test "the union of two difference lists names each path once, in order" {
    const a = [_]engine.Difference{
        .{ .rel = "a", .how = .content_differs },
        .{ .rel = "c", .how = .only_in_first },
    };
    const b = [_]engine.Difference{
        .{ .rel = "b", .how = .content_differs },
        .{ .rel = "c", .how = .content_differs },
    };
    var out: [8][]const u8 = undefined;
    const n = unionRels(&a, &b, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("a", out[0]);
    try std.testing.expectEqualStrings("b", out[1]);
    // The control the duplicate exists for: without the `.eq` arm advancing `j`, this is
    // "c" twice and `n` is 4 — one path rendered as two rows of the consequence table.
    try std.testing.expectEqualStrings("c", out[2]);
}

test "the union stops at the caller's buffer rather than past it" {
    const a = [_]engine.Difference{
        .{ .rel = "a", .how = .content_differs },
        .{ .rel = "b", .how = .content_differs },
        .{ .rel = "c", .how = .content_differs },
    };
    var out: [2][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 2), unionRels(&a, &.{}, &out));
}

test "the evidence path is derived from the case's and is idempotent" {
    const arena = std.testing.allocator;
    const a = try siblingPath(arena, "/w/cases/000001.json");
    defer arena.free(a);
    try std.testing.expectEqualStrings("/w/cases/000001.evidence.json", a);
    // Idempotent, so `sideeye evidence` takes either name: applied to its own output the
    // rule must not produce `000001.evidence.evidence.json`.
    const b = try siblingPath(arena, a);
    try std.testing.expectEqualStrings(a, b);
}

test "a bundle round-trips through its own JSON" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const rows = [_]PathRow{.{
        .path = "README.md",
        .before = .{ .kind = "file", .size = 61 },
        .completed = .{ .kind = "file", .size = 60 },
        .crashed = .{ .kind = "file", .size = 0 },
        .pre_existing = true,
        .declared_scratch = false,
        .old_bytes_elsewhere = .no,
        .old_bytes_at = "",
    }};
    const ev: Evidence = .{
        .schema = "sideeye/evidence",
        .evidence_version = current_version,
        .sideeye_version = cli.version,
        .contract_version = contract.contract_version,
        .target = .{ .operation = "mdl --fix README.md", .state_root = "/st" },
        .exhibit = .earliest,
        .crash_point = 2,
        .crash_points_total = 5,
        .boundary = .{ .after_op = "open", .after_path = "/st/README.md", .before_op = "write", .before_path = "/st/README.md" },
        .invariant = "built-in atomicity (L0)",
        .subject = "README.md",
        .observed = "holding neither the old nor the new content",
        .consequence = &rows,
        .consequence_truncated = false,
        .checker = .{ .configured = true, .failed = true, .diagnostic = "FAIL: README.md lost \"Title\"" },
        .replay = "sideeye replay /w/cases/000001.json",
        .case = "/w/cases/000001.json",
        .recovery = .{ .result = "not_configured" },
        .caveats = &.{"No oracle confirmed it."},
    };
    const text = try buildJson(arena, ev);
    // Strict: an unknown field is a file from a future schema, the rule `ReplayCase` keeps.
    const back = try std.json.parseFromSlice(Evidence, arena, text, .{});
    try std.testing.expectEqual(@as(u32, 2), back.value.crash_point);
    try std.testing.expectEqual(@as(usize, 1), back.value.consequence.len);
    try std.testing.expectEqual(Answer.no, back.value.consequence[0].old_bytes_elsewhere);
    try std.testing.expectEqual(@as(usize, 0), back.value.consequence[0].crashed.?.size);
    try std.testing.expectEqualStrings("not_configured", back.value.recovery.result);
    // The diagnostic carries a quote; the JSON escape and the parse have to agree about it.
    try std.testing.expectEqualStrings("FAIL: README.md lost \"Title\"", back.value.checker.diagnostic.?);
}

test "the checker exhibit's bundle does not call itself the earliest" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const rows = [_]PathRow{.{
        .path = "a.txt",
        .before = .{ .kind = "file", .size = 5 },
        .completed = .{ .kind = "file", .size = 5 },
        .crashed = .{ .kind = "file", .size = 5 },
        .pre_existing = true,
        .declared_scratch = false,
        .old_bytes_elsewhere = .no,
        .old_bytes_at = "",
    }};
    var ev: Evidence = .{
        .schema = "sideeye/evidence",
        .evidence_version = current_version,
        .sideeye_version = "1.4.0",
        .contract_version = 18,
        .target = .{ .operation = "tool", .state_root = "/st" },
        .exhibit = .checker,
        .crash_point = 7,
        .crash_points_total = 9,
        .boundary = .{ .after_op = "rename", .after_path = "/st/a.txt", .before_op = "rename", .before_path = "/st/b.txt" },
        .invariant = "the checker (L2)",
        .subject = "(named by the checker, not by path)",
        .observed = "the checker rejected the state",
        .consequence = &rows,
        .consequence_truncated = false,
        .checker = .{ .configured = true, .failed = true, .diagnostic = "FAIL: a.txt is gen2 but b.txt is gen1" },
        .replay = "sideeye replay /w/cases/000002.json",
        .case = "/w/cases/000002.json",
        .recovery = .{ .result = "not_configured" },
        .caveats = &.{},
    };
    const claim = "it is the earliest one whose result differed";
    const md = try render(arena, ev);
    // The claim exhibit is structurally later than the overall earliest whenever the two
    // differ (#231, ADR 0020), so this sentence is false on its bundle. The first renderer
    // printed it unconditionally, which is what the `exhibit` field exists to stop.
    try std.testing.expect(std.mem.indexOf(u8, md, claim) == null);
    try std.testing.expect(std.mem.indexOf(u8, md, "the earliest one the declared checker rejected") != null);
    // The control: the same bundle as the other exhibit DOES carry the sentence, so this
    // test fails if the branch stops distinguishing them in either direction.
    ev.exhibit = .earliest;
    const md2 = try render(arena, ev);
    try std.testing.expect(std.mem.indexOf(u8, md2, claim) != null);
}

test "a crafted bundle cannot forge a section through any rendered string" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // Every string a bundle carries that reaches the document, each holding a forged
    // heading. The bundle is a file in the work directory, which the judged program can
    // write, so "who would put that there" is answered: the target can.
    const forged = "x\n## Forged\ny";
    const rows = [_]PathRow{.{
        .path = forged,
        // The one that was missed on the first pass: a kind reads like the engine's own
        // word, and is a string parsed out of the file like every other.
        .before = .{ .kind = forged, .size = 1 },
        .completed = null,
        .crashed = .{ .kind = forged, .size = 2 },
        .pre_existing = true,
        .declared_scratch = false,
        .old_bytes_elsewhere = .yes,
        .old_bytes_at = forged,
    }};
    const ev: Evidence = .{
        .schema = "sideeye/evidence",
        .evidence_version = current_version,
        .sideeye_version = forged,
        .contract_version = 18,
        .target = .{ .operation = forged, .state_root = forged },
        .exhibit = .earliest,
        .crash_point = 1,
        .crash_points_total = 1,
        .boundary = .{ .after_op = forged, .after_path = forged, .before_op = forged, .before_path = forged },
        .invariant = forged,
        .subject = forged,
        .observed = forged,
        .consequence = &rows,
        .consequence_truncated = false,
        .checker = .{ .configured = true, .failed = true, .diagnostic = forged },
        .replay = forged,
        .case = forged,
        .recovery = .{ .result = forged },
        .caveats = &.{forged},
    };
    const md = try render(arena, ev);
    // The assertion is STRUCTURAL, not textual. `appendSanitized` replaces each control
    // byte with `?`, so the forged text survives as `?## Forged?` inside its cell — and it
    // should: those are the target's own bytes, and a bundle that dropped them would be
    // hiding what it measured. What must not survive is the LINE START, because that is
    // what makes it a section. The first version of this test asserted the substring was
    // gone, went red against a correct renderer, and was measuring the wrong property.
    try std.testing.expect(std.mem.indexOf(u8, md, "\n## Forged") == null);
    // The denominator: the document still rendered, so the assertion above is not passing
    // on an empty string.
    try std.testing.expect(std.mem.indexOf(u8, md, "## Consequence") != null);
    var headings: usize = 0;
    var it = std.mem.splitScalar(u8, md, '\n');
    while (it.next()) |line| if (std.mem.startsWith(u8, line, "## ")) {
        headings += 1;
    };
    try std.testing.expectEqual(@as(usize, 8), headings);
}

test "the rendered bundle carries the measured fields and no severity word" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const rows = [_]PathRow{
        .{
            .path = "README.md",
            .before = .{ .kind = "file", .size = 61 },
            .completed = .{ .kind = "file", .size = 60 },
            .crashed = .{ .kind = "file", .size = 0 },
            .pre_existing = true,
            .declared_scratch = false,
            .old_bytes_elsewhere = .no,
            .old_bytes_at = "",
        },
        .{
            .path = "cache/x",
            .before = null,
            .completed = .{ .kind = "file", .size = 3 },
            .crashed = null,
            .pre_existing = false,
            .declared_scratch = true,
            // What `measure` produces for a path the operation created: the question does
            // not arise, which is not the same as not knowing the answer.
            .old_bytes_elsewhere = .not_applicable,
            .old_bytes_at = "",
        },
        .{
            .path = "moved/in",
            .before = .{ .kind = "file", .size = 2 },
            .completed = .{ .kind = "file", .size = 2 },
            .crashed = .{ .kind = "file", .size = 2 },
            .pre_existing = true,
            .declared_scratch = false,
            .old_bytes_elsewhere = .unknown,
            .old_bytes_at = "",
        },
    };
    const ev: Evidence = .{
        .schema = "sideeye/evidence",
        .evidence_version = current_version,
        .sideeye_version = "1.4.0",
        .contract_version = 18,
        .target = .{ .operation = "mdl --fix README.md", .state_root = "/st" },
        .exhibit = .earliest,
        .crash_point = 2,
        .crash_points_total = 5,
        .boundary = .{ .after_op = "open", .after_path = "/st/README.md", .before_op = "write", .before_path = "/st/README.md" },
        .invariant = "built-in atomicity (L0)",
        .subject = "README.md",
        .observed = "holding neither the old nor the new content",
        .consequence = &rows,
        .consequence_truncated = false,
        .checker = .{ .configured = true, .failed = true, .diagnostic = "FAIL: README.md lost Title" },
        .replay = "sideeye replay /w/cases/000001.json",
        .case = "/w/cases/000001.json",
        .recovery = .{ .result = "not_configured" },
        .caveats = &.{},
    };
    const md = try render(arena, ev);
    try std.testing.expect(std.mem.indexOf(u8, md, "61 bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "0 bytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "crash point 2 of 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "FAIL: README.md lost Title") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "sideeye replay /w/cases/000001.json") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "Not configured") != null);
    // The absent-before row must read `absent`, not `file, 0 bytes`: those are different
    // observations and the table is the only place a reader can tell them apart.
    try std.testing.expect(std.mem.indexOf(u8, md, "absent") != null);
    // Asserted on the rendered CELLS, not on the word appearing anywhere in the document:
    // the table's own legend contains "unknown", so `indexOf(md, "unknown")` passes on a
    // renderer that prints no row at all. Each of the three answers gets its own cell here.
    try std.testing.expect(std.mem.indexOf(u8, md, "| no | no |") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "| no | — | yes |") != null);
    try std.testing.expect(std.mem.indexOf(u8, md, "| yes | unknown | no |") != null);
    // The half of the promise that says the bundle never ranks what it found. Lower-cased
    // so a capitalised heading cannot slip one past.
    var lower = try arena.alloc(u8, md.len);
    for (md, 0..) |c, i| lower[i] = std.ascii.toLower(c);
    for ([_][]const u8{ "critical", "severe", "high severity", "data-loss", "data loss" }) |banned|
        try std.testing.expect(std.mem.indexOf(u8, lower, banned) == null);
}
