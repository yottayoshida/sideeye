const std = @import("std");
const posix = @import("../posix.zig");
const snapshot = @import("snapshot.zig");

const Allocator = std.mem.Allocator;
const Snapshot = snapshot.Snapshot;
const Entry = snapshot.Entry;
const testSnapshot = snapshot.testSnapshot;
const scratchMatches = snapshot.scratchMatches;

pub const Violation = union(enum) {
    missing: []const u8,
    hybrid: []const u8,
    rewritten: []const u8,
    not_durable: []const u8,
};

pub const FileForm = enum {
    standard,
    history,
};

pub const PlannedFile = struct {
    /// All three slices borrow from the pre/post snapshots handed to `classify`;
    /// the plan must not outlive them.
    rel: []const u8,
    pre_kind: posix.Kind,
    post_kind: posix.Kind,
    form: FileForm,
    pre_content: []const u8,
    post_content: []const u8,
};

pub const L0Plan = struct {
    arena: std.heap.ArenaAllocator,
    files: std.ArrayList(PlannedFile),
    history_count: u32 = 0,
    scratch: []const []const u8 = &.{},
    scratch_matched: u32 = 0,

    pub fn deinit(self: *L0Plan) void {
        self.arena.deinit();
    }

    pub fn isScratch(self: L0Plan, rel: []const u8) bool {
        return scratchMatches(self.scratch, rel);
    }

    /// (#688: what the recording left there, beside what the re-run left). Linear: its one
    /// caller runs once, at a refusal, never inside a world's loop.
    pub fn find(self: L0Plan, rel: []const u8) ?PlannedFile {
        for (self.files.items) |f| if (std.mem.eql(u8, f.rel, rel)) return f;
        return null;
    }
};

fn isJudgedKind(k: posix.Kind) bool {
    return k == .file or k == .symlink or k == .dir;
}

/// Decide, once and from the snapshots alone, which invariant each shared file is
/// judged by. Both the judgement (`judgeL0`) and the report's `l0` note read from the
/// same plan — there is deliberately no second place where the classification is
/// computed, because two classifiers would drift.
///
/// A file enters the history form iff its pre content is non-empty and its post
/// content strictly extends it. Non-empty matters: `startsWith(anything, "")` is
/// vacuously true, so an empty "history" would constrain nothing — such files keep
/// the standard rule, where the atomic-write check still means something.
pub fn classify(gpa: Allocator, pre: Snapshot, post: Snapshot) error{OutOfMemory}!L0Plan {
    return classifyWith(gpa, pre, post, &.{});
}

pub fn classifyWith(gpa: Allocator, pre: Snapshot, post: Snapshot, scratch: []const []const u8) error{OutOfMemory}!L0Plan {
    var plan: L0Plan = .{ .arena = std.heap.ArenaAllocator.init(gpa), .files = .empty, .scratch = scratch };
    errdefer plan.arena.deinit();
    const arena = plan.arena.allocator();
    if (scratch.len > 0) {
        for (pre.entries.items) |pe| if (scratchMatches(scratch, pe.rel)) {
            plan.scratch_matched += 1;
        };
        for (post.entries.items) |po| if (pre.find(po.rel) == null and scratchMatches(scratch, po.rel)) {
            plan.scratch_matched += 1;
        };
    }
    for (pre.entries.items) |pe| {
        if (!isJudgedKind(pe.kind)) continue;
        if (scratchMatches(scratch, pe.rel)) continue;
        const po = post.find(pe.rel) orelse continue;
        if (!isJudgedKind(po.kind)) continue;
        // A dir-to-dir pair used to be skipped as carrying "nothing to compare" —
        // but its kind IS the comparison (#164): an empty directory replaced by a
        // file, or deleted outright, was invisible exactly because the pair never
        // entered the plan. A directory with children is reached through the
        // children's own pairs; an empty one has no other witness, so every judged
        // pair enters now — kind changes included (#122: stow's unfold, fold
        // symlink → real directory, is the window that define exists to explore).
        const history = pe.kind == .file and po.kind == .file and pe.content.len > 0 and
            !std.mem.eql(u8, po.content, pe.content) and
            std.mem.startsWith(u8, po.content, pe.content);
        if (history) plan.history_count += 1;
        try plan.files.append(arena, .{
            .rel = pe.rel,
            .pre_kind = pe.kind,
            .post_kind = po.kind,
            .form = if (history) FileForm.history else FileForm.standard,
            .pre_content = pe.content,
            .post_content = po.content,
        });
    }
    return plan;
}

pub fn judgeL0(plan: L0Plan, crashed: Snapshot) ?Violation {
    for (plan.files.items) |f| {
        const ce = crashed.find(f.rel) orelse return .{ .missing = f.rel };
        switch (f.form) {
            .standard => {
                // The identity on each side is (kind, content) as a pair: a symlink's
                // content is its target string, so a same-named regular file holding
                // those bytes — or a directory beside an empty pre content — must not
                // read as preserved state (#122). A pair whose kind changed between
                // the clean runs (stow's unfold: symlink → directory) is judged by
                // the same two-sided rule; killed mid-swap, the path matches neither
                // side, and that is the violation.
                if (ce.kind == f.pre_kind and std.mem.eql(u8, ce.content, f.pre_content)) continue;
                if (ce.kind == f.post_kind and std.mem.eql(u8, ce.content, f.post_content)) continue;
                return .{ .hybrid = f.rel };
            },
            .history => {
                // Both arms check kind now (#122); this one keeps its own because its
                // violation is `rewritten`, not `hybrid`, and because an empty prefix
                // test would otherwise accept a directory's empty content.
                if (ce.kind != .file) return .{ .rewritten = f.rel };
                if (std.mem.startsWith(u8, ce.content, f.pre_content)) continue;
                return .{ .rewritten = f.rel };
            },
        }
    }
    return null;
}

pub fn judgeL1(plan: L0Plan, pre: Snapshot, post: Snapshot, crashed: Snapshot) ?Violation {
    for (plan.files.items) |f| {
        const ce = crashed.find(f.rel) orelse return .{ .not_durable = f.rel };
        switch (f.form) {
            // The success claim promised the post state, kind and content both:
            // a directory's content is the empty string, so an empty post file
            // replaced by a same-named directory would compare equal on content
            // alone. The plan carries the post kind, so no second lookup (#122).
            .standard => if (ce.kind != f.post_kind or !std.mem.eql(u8, ce.content, f.post_content))
                return .{ .not_durable = f.rel },
            .history => {
                if (ce.kind != .file) return .{ .not_durable = f.rel };
                if (!std.mem.startsWith(u8, ce.content, f.pre_content))
                    return .{ .not_durable = f.rel };
                if (ce.content.len <= f.pre_content.len)
                    return .{ .not_durable = f.rel };
            },
        }
    }
    for (post.entries.items) |e| {
        if (pre.find(e.rel) != null) continue;
        // A declared scratch path is not required to exist here either (ADR 0043): this
        // loop and the next walk the snapshots, not the plan, so the plan's omission of
        // scratch pairs does not reach them and they ask the declaration themselves.
        if (plan.isScratch(e.rel)) continue;
        const ce = crashed.find(e.rel) orelse return .{ .not_durable = e.rel };
        if (ce.kind != e.kind) return .{ .not_durable = e.rel };
        if (e.kind == .symlink and !std.mem.eql(u8, ce.content, e.content))
            return .{ .not_durable = e.rel };
    }
    for (pre.entries.items) |e| {
        if (post.find(e.rel) != null) continue;
        if (plan.isScratch(e.rel)) continue;
        if (crashed.find(e.rel) != null) return .{ .not_durable = e.rel };
    }
    return null;
}

fn snapWith(gpa: Allocator, entries: []const Entry) !Snapshot {
    var s: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    errdefer s.deinit();
    for (entries) |e| try s.entries.append(s.arena.allocator(), e);
    return s;
}

test "ADR 0043: a shared scratch pair leaves the plan, and a hybrid there is not a violation" {
    const gpa = std.testing.allocator;
    var pre = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=1\n" }, .{ .rel = "nondet.txt", .kind = .file, .content = "a\n" } });
    defer pre.deinit();
    var post = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=2\n" }, .{ .rel = "nondet.txt", .kind = .file, .content = "b\n" } });
    defer post.deinit();
    const decl = [_][]const u8{"nondet.txt"};
    var plan = try classifyWith(gpa, pre, post, &decl);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqualStrings("key.json", plan.files.items[0].rel);
    try std.testing.expectEqual(@as(u32, 1), plan.scratch_matched);
    var hybrid = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=2\n" }, .{ .rel = "nondet.txt", .kind = .file, .content = "zzz\n" } });
    defer hybrid.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, hybrid));
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, hybrid));
    var gone = try snapWith(gpa, &.{.{ .rel = "key.json", .kind = .file, .content = "k=2\n" }});
    defer gone.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, gone));
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, gone));
    var bare = try classify(gpa, pre, post);
    defer bare.deinit();
    try std.testing.expectEqualStrings("nondet.txt", judgeL0(bare, hybrid).?.hybrid);
    try std.testing.expectEqualStrings("nondet.txt", judgeL0(bare, gone).?.missing);
}

test "ADR 0043: a post-only scratch path may be absent and a pre-only one may return, under L1" {
    const gpa = std.testing.allocator;
    var pre = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=1\n" }, .{ .rel = "old.tmp", .kind = .file, .content = "t\n" } });
    defer pre.deinit();
    var post = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=2\n" }, .{ .rel = "receipt.txt", .kind = .file, .content = "ok\n" } });
    defer post.deinit();
    const decl = [_][]const u8{ "receipt.txt", "old.tmp" };
    var plan = try classifyWith(gpa, pre, post, &decl);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 2), plan.scratch_matched);
    var world = try snapWith(gpa, &.{ .{ .rel = "key.json", .kind = .file, .content = "k=2\n" }, .{ .rel = "old.tmp", .kind = .file, .content = "t\n" } });
    defer world.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, world));
    var bare = try classify(gpa, pre, post);
    defer bare.deinit();
    try std.testing.expectEqualStrings("receipt.txt", judgeL1(bare, pre, post, world).?.not_durable);
}

test "ADR 0043: a directory named scratch covers its own pair and its children, and no more" {
    const gpa = std.testing.allocator;
    var pre = try snapWith(gpa, &.{ .{ .rel = "cache", .kind = .dir, .content = "" }, .{ .rel = "cache/a", .kind = .file, .content = "1" }, .{ .rel = "cachex", .kind = .file, .content = "x" } });
    defer pre.deinit();
    var post = try snapWith(gpa, &.{ .{ .rel = "cache", .kind = .dir, .content = "" }, .{ .rel = "cache/a", .kind = .file, .content = "2" }, .{ .rel = "cachex", .kind = .file, .content = "y" } });
    defer post.deinit();
    const decl = [_][]const u8{"cache"};
    var plan = try classifyWith(gpa, pre, post, &decl);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqualStrings("cachex", plan.files.items[0].rel);
    try std.testing.expectEqual(@as(u32, 2), plan.scratch_matched);
    var gone = try snapWith(gpa, &.{.{ .rel = "cachex", .kind = .file, .content = "y" }});
    defer gone.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, gone));
    var sib = try snapWith(gpa, &.{.{ .rel = "cachex", .kind = .file, .content = "zzz" }});
    defer sib.deinit();
    try std.testing.expectEqualStrings("cachex", judgeL0(plan, sib).?.hybrid);
}

test "ADR 0043: a declaration that matches nothing recorded counts zero and changes no verdict" {
    const gpa = std.testing.allocator;
    var pre = try snapWith(gpa, &.{.{ .rel = "key.json", .kind = .file, .content = "k=1\n" }});
    defer pre.deinit();
    var post = try snapWith(gpa, &.{.{ .rel = "key.json", .kind = .file, .content = "k=2\n" }});
    defer post.deinit();
    const decl = [_][]const u8{"other.txt"};
    var plan = try classifyWith(gpa, pre, post, &decl);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 0), plan.scratch_matched);
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    var hybrid = try snapWith(gpa, &.{.{ .rel = "key.json", .kind = .file, .content = "k=" }});
    defer hybrid.deinit();
    try std.testing.expectEqualStrings("key.json", judgeL0(plan, hybrid).?.hybrid);
}

fn expectHybridAgainstCrashedKind(pre_content: []const u8, post_content: []const u8, crashed_kind: posix.Kind) !void {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "note", pre_content }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "note", post_content }});
    defer post.deinit();
    var crashed: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer crashed.deinit();
    try crashed.entries.append(crashed.arena.allocator(), .{ .rel = "note", .kind = crashed_kind, .content = "" });
    const v = (try testJudge(gpa, pre, post, crashed)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("note", v.hybrid);
}

test "#27 pin: a post-empty file pair rejects a crashed directory" {
    try expectHybridAgainstCrashedKind("x", "", .dir);
}

test "#27 pin: a pre-empty file pair rejects a crashed directory" {
    try expectHybridAgainstCrashedKind("", "x", .dir);
}

test "#27 pin: an .other crashed kind is not the emptied file" {
    try expectHybridAgainstCrashedKind("x", "", .other);
}

test "#27 control: a non-empty pair rejects the same directory as always" {
    // Content alone already refuses this shape, so the kind-blind mutation
    // that reds the three pins above spares this one — it keeps rejecting.
    try expectHybridAgainstCrashedKind("x", "y", .dir);
}

test "#164: a dir-to-dir pair enters the plan and an intact world judges clean" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(FileForm.standard, plan.files.items[0].form);
    var intact: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer intact.deinit();
    try intact.entries.append(intact.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, intact));
}

test "#164 pin: an empty directory replaced by an empty file is a violation" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    var as_file: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_file.deinit();
    try as_file.entries.append(as_file.arena.allocator(), .{ .rel = "box", .kind = .file, .content = "" });
    try std.testing.expectEqualStrings("box", judgeL0(plan, as_file).?.hybrid);
}

test "#164 pin: an empty directory deleted outright is missing" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "box", .kind = .dir, .content = "" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    var gone: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer gone.deinit();
    try std.testing.expectEqualStrings("box", judgeL0(plan, gone).?.missing);
}

fn testJudge(gpa: Allocator, pre: Snapshot, post: Snapshot, crashed: Snapshot) !?Violation {
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    return judgeL0(plan, crashed);
}

test "L0 catches the delete-before-rename window" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    var crashed = try testSnapshot(gpa, &.{.{ "key.json.tmp", "key=2\n" }});
    defer crashed.deinit();

    const v = (try testJudge(gpa, pre, post, crashed)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.missing);
}

test "L0 accepts a leftover temporary file" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();

    var mid = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" },
        .{ "key.json.tmp", "key=2\n" },
    });
    defer mid.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, mid));

    var done = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer done.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, done));
}

test "L0 catches content that is neither the old nor the new value" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();
    var torn = try testSnapshot(gpa, &.{.{ "key.json", "key=" }});
    defer torn.deinit();

    const v = (try testJudge(gpa, pre, post, torn)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.hybrid);
}

test "L0 ignores files the operation legitimately creates or deletes" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "old.json", "gone\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "new.json", "fresh\n" }});
    defer post.deinit();
    var empty = try testSnapshot(gpa, &.{});
    defer empty.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, empty));
}

test "classify puts only a non-empty strict extension into the history form" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{
        .{ "grew.log", "born\n" }, // non-empty strict extension -> history
        .{ "key.json", "key=1\n" }, // diverged -> standard
        .{ "same.txt", "still\n" }, // unchanged -> standard
        .{ "fresh.log", "" }, // empty pre -> standard, however post grew
        .{ "shrunk.db", "abc\n" }, // post shorter -> standard
    });
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{
        .{ "grew.log", "born\nappended\n" },
        .{ "key.json", "key=2\n" },
        .{ "same.txt", "still\n" },
        .{ "fresh.log", "grown\n" },
        .{ "shrunk.db", "a" },
    });
    defer post.deinit();

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 1), plan.history_count);
    for (plan.files.items) |f| {
        const expected: FileForm = if (std.mem.eql(u8, f.rel, "grew.log")) .history else .standard;
        try std.testing.expectEqual(expected, f.form);
    }
}

test "the post-success invariant judges the whole post snapshot (ADR 0008)" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" }, // standard: must equal post in a marker world
        .{ "audit.log", "e1\n" }, // history: must have gained something
        .{ "old.tmp", "x\n" }, // pre-only: the operation deletes it
    });
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" }, // post-only: the operation creates it
    });
    defer post.deinit();
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();

    var durable = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2 different-tail\n" },
        .{ "receipt.txt", "different-content\n" }, // existence only; content not judged
    });
    defer durable.deinit();
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, durable));

    var stale = try testSnapshot(gpa, &.{
        .{ "key.json", "key=1\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" },
    });
    defer stale.deinit();
    try std.testing.expectEqualStrings("key.json", judgeL1(plan, pre, post, stale).?.not_durable);

    var ungrown = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\n" },
        .{ "receipt.txt", "ok\n" },
    });
    defer ungrown.deinit();
    try std.testing.expectEqualStrings("audit.log", judgeL1(plan, pre, post, ungrown).?.not_durable);

    var uncreated = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
    });
    defer uncreated.deinit();
    try std.testing.expectEqualStrings("receipt.txt", judgeL1(plan, pre, post, uncreated).?.not_durable);
    var undeleted = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "ok\n" },
        .{ "old.tmp", "x\n" },
    });
    defer undeleted.deinit();
    try std.testing.expectEqualStrings("old.tmp", judgeL1(plan, pre, post, undeleted).?.not_durable);

    var kind_swap = try testSnapshot(gpa, &.{
        .{ "key.json", "key=2\n" },
        .{ "audit.log", "e1\ne2\n" },
        .{ "receipt.txt", "" },
    });
    defer kind_swap.deinit();
    for (kind_swap.entries.items) |*e| {
        if (std.mem.eql(u8, e.rel, "receipt.txt")) e.kind = .dir;
    }
    try std.testing.expectEqualStrings("receipt.txt", judgeL1(plan, pre, post, kind_swap).?.not_durable);
}

test "history form tolerates any tail and the loss of none of the history" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t=17\n" }});
    defer post.deinit();

    var untouched = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer untouched.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, untouched));

    var torn = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t" }});
    defer torn.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, torn));

    var other_tail = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2 t=99 and longer than recorded\n" }});
    defer other_tail.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, other_tail));
}

test "history form catches history that was rewritten, truncated or replaced" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "audit.log", "entry-1\nentry-2\n" }});
    defer post.deinit();

    var emptied = try testSnapshot(gpa, &.{.{ "audit.log", "" }});
    defer emptied.deinit();
    const v1 = (try testJudge(gpa, pre, post, emptied)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v1.rewritten);

    var cut = try testSnapshot(gpa, &.{.{ "audit.log", "entry" }});
    defer cut.deinit();
    const v2 = (try testJudge(gpa, pre, post, cut)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v2.rewritten);

    var swapped = try testSnapshot(gpa, &.{.{ "audit.log", "Xntry-1\nentry-2\n" }});
    defer swapped.deinit();
    const v3 = (try testJudge(gpa, pre, post, swapped)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v3.rewritten);

    var gone = try testSnapshot(gpa, &.{});
    defer gone.deinit();
    const v4 = (try testJudge(gpa, pre, post, gone)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v4.missing);

    var as_dir: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_dir.deinit();
    try as_dir.entries.append(as_dir.arena.allocator(), .{ .rel = "audit.log", .kind = .dir, .content = "" });
    const v5 = (try testJudge(gpa, pre, post, as_dir)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("audit.log", v5.rewritten);
}

test "a standard-form file does not inherit the history form's tolerance" {
    // An implementation that applies the prefix rule to every changed file passes
    // the history tests above and fails here.
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "key.json", "key=1\n" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "key.json", "key=2\n" }});
    defer post.deinit();
    var extended = try testSnapshot(gpa, &.{.{ "key.json", "key=1\ngarbage" }});
    defer extended.deinit();

    const v = (try testJudge(gpa, pre, post, extended)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("key.json", v.hybrid);
}

test "an empty-pre file keeps the standard rule instead of a vacuous history" {
    const gpa = std.testing.allocator;
    var pre = try testSnapshot(gpa, &.{.{ "fresh.log", "" }});
    defer pre.deinit();
    var post = try testSnapshot(gpa, &.{.{ "fresh.log", "first entry\n" }});
    defer post.deinit();

    var partial = try testSnapshot(gpa, &.{.{ "fresh.log", "first en" }});
    defer partial.deinit();
    const v = (try testJudge(gpa, pre, post, partial)) orelse return error.TestExpectedViolation;
    try std.testing.expectEqualStrings("fresh.log", v.hybrid);

    var empty = try testSnapshot(gpa, &.{.{ "fresh.log", "" }});
    defer empty.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, empty));
    var full = try testSnapshot(gpa, &.{.{ "fresh.log", "first entry\n" }});
    defer full.deinit();
    try std.testing.expectEqual(@as(?Violation, null), try testJudge(gpa, pre, post, full));
}

test "a symlink pair is judged by kind and by target (#122)" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v1" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v2" });

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].pre_kind);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].post_kind);
    try std.testing.expectEqual(@as(u32, 0), plan.history_count);

    var old_t: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer old_t.deinit();
    try old_t.entries.append(old_t.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions/v1" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, old_t));

    var third: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer third.deinit();
    try third.entries.append(third.arena.allocator(), .{ .rel = "current", .kind = .symlink, .content = "versions" });
    try std.testing.expectEqualStrings("current", judgeL0(plan, third).?.hybrid);

    var as_file: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer as_file.deinit();
    try as_file.entries.append(as_file.arena.allocator(), .{ .rel = "current", .kind = .file, .content = "versions/v1" });
    try std.testing.expectEqualStrings("current", judgeL0(plan, as_file).?.hybrid);

    var gone: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer gone.deinit();
    try std.testing.expectEqualStrings("current", judgeL0(plan, gone).?.missing);
}

test "a pair whose kind changes between the clean runs is judged, not skipped (#122)" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    try pre.entries.append(pre.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "../stow/A/sub" });
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "target/sub", .kind = .dir, .content = "" });

    var plan = try classify(gpa, pre, post);
    defer plan.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan.files.items.len);
    try std.testing.expectEqual(posix.Kind.symlink, plan.files.items[0].pre_kind);
    try std.testing.expectEqual(posix.Kind.dir, plan.files.items[0].post_kind);

    var before: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer before.deinit();
    try before.entries.append(before.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "../stow/A/sub" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, before));

    var after: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer after.deinit();
    try after.entries.append(after.arena.allocator(), .{ .rel = "target/sub", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan, after));

    var mid: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer mid.deinit();
    try std.testing.expectEqualStrings("target/sub", judgeL0(plan, mid).?.missing);

    var wrong: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer wrong.deinit();
    try wrong.entries.append(wrong.arena.allocator(), .{ .rel = "target/sub", .kind = .symlink, .content = "/elsewhere" });
    try std.testing.expectEqualStrings("target/sub", judgeL0(plan, wrong).?.hybrid);

    var pre2: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre2.deinit();
    try pre2.entries.append(pre2.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    var post2: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post2.deinit();
    try post2.entries.append(post2.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    var plan2 = try classify(gpa, pre2, post2);
    defer plan2.deinit();
    try std.testing.expectEqual(@as(usize, 1), plan2.files.items.len);
    var d_ok: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer d_ok.deinit();
    try d_ok.entries.append(d_ok.arena.allocator(), .{ .rel = "d", .kind = .dir, .content = "" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL0(plan2, d_ok));
}

test "L1 judges a post-only symlink by its target, not existence alone (#122)" {
    const gpa = std.testing.allocator;
    var pre: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer pre.deinit();
    var post: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer post.deinit();
    try post.entries.append(post.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "../pkg/real" });
    var plan = try classify(gpa, pre, post);
    defer plan.deinit();

    var ok: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer ok.deinit();
    try ok.entries.append(ok.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "../pkg/real" });
    try std.testing.expectEqual(@as(?Violation, null), judgeL1(plan, pre, post, ok));

    var retargeted: Snapshot = .{ .arena = std.heap.ArenaAllocator.init(gpa), .entries = .empty };
    defer retargeted.deinit();
    try retargeted.entries.append(retargeted.arena.allocator(), .{ .rel = "farm/link", .kind = .symlink, .content = "/elsewhere" });
    try std.testing.expectEqualStrings("farm/link", judgeL1(plan, pre, post, retargeted).?.not_durable);
}

test "this file's public surface is the eight the facade re-exports (#491)" {
    // The four aliases above (`Snapshot`, `Entry`, `testSnapshot`, `scratchMatches`) are
    // private on purpose, and `engine.zig`'s facade walk cannot see it if one becomes
    // `pub`: it would find that name already re-exported from `snapshot.zig`, and the
    // identity check would compare the same declaration to itself. So the count is
    // checked here instead. `std.meta.declarations` lists public declarations only, so
    // this is exactly the surface the facade promises to mirror.
    //
    // A ninth public declaration is not a mistake by itself — it is a new name for the
    // facade to re-export, and this number moves with it.
    try std.testing.expectEqual(@as(usize, 8), std.meta.declarations(@This()).len);
}
