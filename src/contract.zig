//! Both sides import this file. There is deliberately no second definition anywhere:
//! a trace written by the shim and read by the engine passes through the *same*
//! encode/decode functions below. The worst failure mode of this product is
//! "missed an operation and still reported PASS", and a contract duplicated across
//! two components is one of the ways that happens — one side gets updated, the other
//! does not, and the mismatch is silent. Keeping it in one file makes that impossible
//! rather than merely detectable.
//!
//! Encoding rules (see DESIGN.md and the v0.1 plan):
//!   - explicit little-endian for every integer,
//!   - fixed-width integers, explicit tags, explicit lengths only,
//!   - never a raw struct: `@bitCast` reinterprets *logical* bits from Zig 0.17 on,
//!     which would silently change the byte layout across compiler versions.
//!   - no pointers, no native-sized types, no padding, no `dev_t`/`ino_t`.
//!
//! Nothing here allocates. The shim runs inside the target process and must not
//! touch the heap; the engine gets the same guarantee for free.

const std = @import("std");

/// Bumped whenever the trace format or the meaning of an `OpClass` changes.
/// The engine refuses a trace whose version differs (`contract_version_mismatch`),
/// because `contract.zig` is shared at *build* time — a stale shim binary paired
/// with a fresh engine is a real combination that must not be misread.
pub const contract_version: u32 = 19;

pub const magic = "SIDEEYE1";

pub const env = struct {
    pub const state_dir = "SIDEEYE_STATE_DIR";
    /// macOS resolves `/tmp` to `/private/tmp`. A target told its state is at
    /// `/tmp/x` passes `/tmp/x/key.json` to `unlink`, while `F_GETPATH` answers
    /// `/private/tmp/x/key.json` for the same file: one operation, two spellings, and
    /// a prefix test on either alone counts half of them. The engine hides this during
    pub const state_dir_alt = "SIDEEYE_STATE_DIR_ALT";
    pub const trace_path = "SIDEEYE_TRACE_PATH";
    pub const kill_at = "SIDEEYE_KILL_AT";
    /// Set by the engine on a world's spawn and nowhere else, because the engine is what
    /// puts the target in its own process group first (`src/posix.zig`). Killing one
    /// process is not a crash: a shell whose child died runs the next command, so a world
    /// armed at an awaited child's operation would carry operations from after the crash
    /// point it claims to have died at. Killing the group is.
    pub const kill_group = "SIDEEYE_KILL_GROUP";
    pub const seq_base = "SIDEEYE_SEQ_BASE";
    pub const before_constructor = "SIDEEYE_BEFORE_CONSTRUCTOR";
    pub const observe = "SIDEEYE_OBSERVE";
    pub const run_cgroup = "SIDEEYE_RUN_CGROUP";
    /// level below the run's (v17). Set on an explored world's spawn only, beside `kill_group`
    /// and for its reason: a world is the only run that is killed.
    pub const kill_cgroup = "SIDEEYE_KILL_CGROUP";
    pub const kill_aside = "SIDEEYE_KILL_ASIDE";
};

/// The exit-code contract from DESIGN.md §13. UNKNOWN is never 0: a caller that
/// wants to treat "could not judge" as success has to write that down itself.
pub const ExitCode = enum(u8) {
    pass = 0,
    fail = 1,
    unknown = 2,
    setup_error = 3,
};

/// Why an `.unresolved` record could not be placed, written by the shim into `aux`
/// and printed by the engine (#485).
/// compares them to anything. `aux` normally holds the other endpoint of a two-path
/// operation; using it for a reason here is the type pun ADR 0003 rejected for open
/// flags, and it is admissible only because `.unresolved` is a marker: the snapshot
/// walk drops markers before the name matching that would read `aux` as a path.
pub const ObserveMode = enum {
    wrappers,
    syscalls,
    supervised,

    pub fn parse(text: []const u8) ?ObserveMode {
        if (std.mem.eql(u8, text, "wrappers")) return .wrappers;
        if (std.mem.eql(u8, text, "syscalls")) return .syscalls;
        if (std.mem.eql(u8, text, "supervised")) return .supervised;
        return null;
    }

    pub fn name(self: ObserveMode) []const u8 {
        return @tagName(self);
    }
};

pub const observe_aux = struct {
    pub const armed = "observe:syscalls";
    pub const failed = "observe:syscalls-failed";
    pub const unsupported = "observe:syscalls-unsupported";
    pub const supervised = "observe:supervised";
};

pub const thread_aux = struct {
    pub const unknown = "?";

    pub const Started = struct { creator: u64, written: u32, ordinal: u32 };
    pub const Joined = struct { creator: u64, ordinal: u32 };

    pub const max_len = 20 + 1 + 10 + 1 + 10;

    pub fn started(buf: []u8, creator: u64, written: u32, ordinal: u32) EncodeError![]const u8 {
        return std.fmt.bufPrint(buf, "{d} {d} {d}", .{ creator, written, ordinal }) catch return error.BufferTooSmall;
    }

    pub fn joined(buf: []u8, creator: u64, ordinal: u32) EncodeError![]const u8 {
        return std.fmt.bufPrint(buf, "{d} {d}", .{ creator, ordinal }) catch return error.BufferTooSmall;
    }

    pub fn parseStarted(aux: []const u8) ?Started {
        var it = std.mem.splitScalar(u8, aux, ' ');
        const a = it.next() orelse return null;
        const b = it.next() orelse return null;
        const c = it.next() orelse return null;
        if (it.next() != null) return null;
        return .{
            .creator = std.fmt.parseUnsigned(u64, a, 10) catch return null,
            .written = std.fmt.parseUnsigned(u32, b, 10) catch return null,
            .ordinal = std.fmt.parseUnsigned(u32, c, 10) catch return null,
        };
    }

    pub fn parseJoined(aux: []const u8) ?Joined {
        var it = std.mem.splitScalar(u8, aux, ' ');
        const a = it.next() orelse return null;
        const b = it.next() orelse return null;
        if (it.next() != null) return null;
        return .{
            .creator = std.fmt.parseUnsigned(u64, a, 10) catch return null,
            .ordinal = std.fmt.parseUnsigned(u32, b, 10) catch return null,
        };
    }
};

test "thread_aux round-trips both spellings, and refuses the unknown mark and every other shape" {
    const t = std.testing;
    var buf: [thread_aux.max_len]u8 = undefined;
    const s1 = try thread_aux.started(&buf, 364, 23, 2);
    try t.expectEqualStrings("364 23 2", s1);
    const p1 = thread_aux.parseStarted(s1).?;
    try t.expectEqual(@as(u64, 364), p1.creator);
    try t.expectEqual(@as(u32, 23), p1.written);
    try t.expectEqual(@as(u32, 2), p1.ordinal);
    const s2 = try thread_aux.joined(&buf, 18446744073709551615, 4294967295);
    try t.expectEqualStrings("18446744073709551615 4294967295", s2);
    const p2 = thread_aux.parseJoined(s2).?;
    try t.expectEqual(@as(u64, 18446744073709551615), p2.creator);
    try t.expectEqual(@as(u32, 4294967295), p2.ordinal);
    var wide: [thread_aux.max_len]u8 = undefined;
    _ = try thread_aux.started(&wide, 18446744073709551615, 4294967295, 4294967295);
    try t.expectEqual(@as(?thread_aux.Started, null), thread_aux.parseStarted(thread_aux.unknown));
    try t.expectEqual(@as(?thread_aux.Joined, null), thread_aux.parseJoined(thread_aux.unknown));
    try t.expectEqual(@as(?thread_aux.Started, null), thread_aux.parseStarted("364 23"));
    try t.expectEqual(@as(?thread_aux.Joined, null), thread_aux.parseJoined("364 23 2"));
    try t.expectEqual(@as(?thread_aux.Started, null), thread_aux.parseStarted("364 x 2"));
    try t.expectEqual(@as(?thread_aux.Joined, null), thread_aux.parseJoined(""));
    try t.expectEqual(@as(?thread_aux.Joined, null), thread_aux.parseJoined(s1));
}

pub const cgroup_aux = struct {
    pub const held = "cgroup:held";
    pub const held_kill = "cgroup:held-kill";
    pub const outside = "cgroup:outside";
    pub const unreadable = "cgroup:unreadable";
    pub const kill_returned = "cgroup:kill-returned";
    pub const kill_alone = "cgroup:kill-alone";
};

pub const CgroupStanding = enum { held, outside, unknown };

pub const CgroupLine = struct {
    run: []const u8,
    col: usize = 0,
    v2: bool = true,
    path_len: usize = 0,
    within: bool = true,

    pub fn feed(self: *CgroupLine, b: u8) ?CgroupStanding {
        if (b == '\n') return self.endLine();
        defer self.col += 1;
        if (self.col < 3) {
            if (b != "0::"[self.col]) self.v2 = false;
            return null;
        }
        if (!self.v2) return null;
        const i = self.path_len;
        self.path_len += 1;
        if (i < self.run.len) {
            if (b != self.run[i]) self.within = false;
        } else if (i == self.run.len and self.run.len > 0) {
            if (self.run[self.run.len - 1] != '/' and b != '/') self.within = false;
        }
        return null;
    }

    fn endLine(self: *CgroupLine) ?CgroupStanding {
        const answer: ?CgroupStanding = if (self.v2 and self.col >= 3)
            (if (self.run.len > 0 and self.within and self.path_len >= self.run.len) .held else .outside)
        else
            null;
        self.* = .{ .run = self.run };
        return answer;
    }

    pub fn finish(self: *CgroupLine) CgroupStanding {
        return self.endLine() orelse .unknown;
    }
};

pub fn standingOf(text: []const u8, run: []const u8) CgroupStanding {
    var line: CgroupLine = .{ .run = run };
    for (text) |b| {
        if (line.feed(b)) |answer| return answer;
    }
    return line.finish();
}

test "a process is within the run's cgroup at it or below it, never beside it, wherever its line sits (v17, #559)" {
    try std.testing.expectEqual(CgroupStanding.held, standingOf("0::/sideeye-1-ab\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.held, standingOf("0::/sideeye-1-ab/inner\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.outside, standingOf("0::/sideeye-1-abc\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.outside, standingOf("0::/\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.held, standingOf("0::/any/thing\n", "/"));
    try std.testing.expectEqual(CgroupStanding.outside, standingOf("0::/sideeye-1-ab\n", ""));
    const hybrid = "12:memory:/sideeye-1-ab\n11:pids:/user.slice\n10:devices:/user.slice\n9:blkio:/user.slice\n" ++
        "8:cpu,cpuacct:/user.slice\n1:name=systemd:/user.slice/user-1000.slice/session-2.scope\n0::/sideeye-1-ab/w\n";
    try std.testing.expectEqual(CgroupStanding.held, standingOf(hybrid, "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.outside, standingOf("12:memory:/sideeye-1-ab\n0::/user.slice\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.held, standingOf("0::/sideeye-1-ab", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.unknown, standingOf("12:memory:/x\n", "/sideeye-1-ab"));
    try std.testing.expectEqual(CgroupStanding.unknown, standingOf("10::/sideeye-1-ab\n", "/sideeye-1-ab"));
}

pub const shared_map_refusal = struct {
    pub const writable = "mmap(PROT_WRITE|MAP_SHARED)";
    pub const made_writable = "mprotect(PROT_WRITE) on a shared mapping of a state file";
    pub const past_table = "mprotect(PROT_WRITE) after more shared mappings of state files than the shim tracks";
};

pub const unresolved_kind = struct {
    pub const unresolvable_path = "unresolvable-path";
    pub const fd_without_path = "fd-without-path";
    pub const unlinked_fd = "unlinked-fd";
    pub const link_by_descriptor = "link-by-descriptor";
    pub const trace_closed = "trace-closed-by-target";
    pub const count_read_failed = "count-read-failed";
    pub const thread_slots_exhausted = "thread-slots-exhausted";
    pub const before_constructor = "before-constructor";

    /// Derived, not counted by hand: a member added later can be longer than every member
    /// today, and a hand-written bound would then make `bufPrint` fall back and drop the
    /// descriptor silently — the exact loss the suffix exists to prevent. The operation
    /// name comes from `@tagName(OpClass)`, so its longest is derived too.
    pub const with_fd_max = blk: {
        var longest_kind: usize = 0;
        for (all) |k| {
            if (k.len > longest_kind) longest_kind = k.len;
        }
        var longest_op: usize = 0;
        for (@typeInfo(OpClass).@"enum".fields) |f| {
            if (f.name.len > longest_op) longest_op = f.name.len;
        }
        break :blk longest_kind + 1 + longest_op + 4 + 11;
    };

    pub const all = [_][]const u8{
        unresolvable_path,
        fd_without_path,
        unlinked_fd,
        link_by_descriptor,
        trace_closed,
        count_read_failed,
        before_constructor,
    };

    /// literals is a format the engine reads and nothing defines. Callers pass a buffer —
    /// returning a slice of a local would hand back memory that dies before the record is
    /// written — and a buffer too small keeps the kind and drops the descriptor, so a
    /// record says less rather than arriving half-written.
    pub fn withFd(buf: []u8, kind: []const u8, fd: c_int) []const u8 {
        return std.fmt.bufPrint(buf, "{s} fd:{d}", .{ kind, fd }) catch kind;
    }

    pub fn withOp(buf: []u8, kind: []const u8, op: OpClass, fd: c_int) []const u8 {
        return std.fmt.bufPrint(buf, "{s} {s} fd:{d}", .{ kind, @tagName(op), fd }) catch kind;
    }

    /// Returns the class only for `unlinked_fd`. `fd_without_path` is deliberately not
    /// read: there the path query itself failed, so where the descriptor pointed is
    /// unknown and a close on it cannot be said to be out of harm's way — ADR 0013's
    /// "a failed measurement never passes as a clean one", and `docs/cli.md`'s promise that
    /// a host without `statx` keeps refusing. It reaches this record from an unlinked
    /// descriptor too (`shim/src/common.zig` writes it before the `deleted` branch), which
    /// is exactly why the caller's question has to be about the recorded kind rather than
    /// about "an unlinked descriptor".
    ///
    /// **Parsed, not prefix-matched.** `trace_closed` is the string
    /// "trace-closed-by-target", which CONTAINS "close": a `startsWith` or a substring
    /// test reads it as a close and would exempt a record that names no operation at all.
    /// `class` is required because `aux` is not one field with one meaning: on a rename or
    /// a link it carries the operation's second path (`Op.aux`), and a target chooses
    /// those. Requiring `.unresolved` keeps a path named "unlinked-fd close fd:3" from
    /// being read as this vocabulary. **The one production caller reads inside the
    /// `.unresolved` arm of its own switch, so the gate is vacuous there** — it is here
    /// for the next caller, and the unit test is where it is exercised. Stated rather
    /// than left to look like a live check (review).
    pub fn opOfUnlinkedFd(class: OpClass, aux: []const u8) ?OpClass {
        if (class != .unresolved) return null;
        var it = std.mem.splitScalar(u8, aux, ' ');
        const kind = it.next() orelse return null;
        if (!std.mem.eql(u8, kind, unlinked_fd)) return null;
        const op = it.next() orelse return null;
        const fd = it.next() orelse return null;
        if (it.next() != null) return null;
        if (!std.mem.startsWith(u8, fd, "fd:")) return null;
        _ = std.fmt.parseInt(c_int, fd["fd:".len..], 10) catch return null;
        return std.meta.stringToEnum(OpClass, op);
    }
};

test "unplaceableRefuses is exactly `not close` today, and says so out loud" {
    const t = std.testing;
    inline for (@typeInfo(OpClass).@"enum".fields) |f| {
        const c: OpClass = @enumFromInt(f.value);
        try t.expectEqual(c != .close, c.unplaceableRefuses());
    }
}

test "opOfUnlinkedFd reads the operation, and every other shape refuses (#485's vocabulary)" {
    const t = std.testing;
    const U = unresolved_kind;

    try t.expectEqual(OpClass.close, U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:3").?);
    try t.expectEqual(OpClass.write, U.opOfUnlinkedFd(.unresolved, "unlinked-fd write fd:3").?);
    try t.expectEqual(OpClass.fsync, U.opOfUnlinkedFd(.unresolved, "unlinked-fd fsync fd:9").?);
    try t.expectEqual(OpClass.truncate, U.opOfUnlinkedFd(.unresolved, "unlinked-fd truncate fd:0").?);
    try t.expectEqual(OpClass.close, U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:-100").?);

    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, U.trace_closed));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "trace-closed-by-target fd:900"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, U.unresolvable_path));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "link-by-descriptor fd:-100"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, ""));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd fd:3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "fd-without-path close fd:3"));

    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close 3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:3 extra"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd nosuchop fd:3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fdclose fd:3"));

    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.rename, "unlinked-fd close fd:3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.close, "unlinked-fd close fd:3"));
}

test "unresolved_kind.withFd appends the descriptor, and its buffer fits every member (#485)" {
    const t = std.testing;
    var b: [unresolved_kind.with_fd_max]u8 = undefined;

    try t.expectEqualStrings("unlinked-fd fd:3", unresolved_kind.withFd(&b, unresolved_kind.unlinked_fd, 3));
    try t.expectEqualStrings("unlinked-fd close fd:3", unresolved_kind.withOp(&b, unresolved_kind.unlinked_fd, .close, 3));
    try t.expectEqualStrings("unlinked-fd write fd:3", unresolved_kind.withOp(&b, unresolved_kind.unlinked_fd, .write, 3));
    try t.expectEqualStrings("fd-without-path fd:0", unresolved_kind.withFd(&b, unresolved_kind.fd_without_path, 0));
    try t.expectEqualStrings("link-by-descriptor fd:7", unresolved_kind.withFd(&b, unresolved_kind.link_by_descriptor, 7));
    try t.expectEqualStrings("link-by-descriptor fd:-100", unresolved_kind.withFd(&b, unresolved_kind.link_by_descriptor, -100));

    try t.expectEqualStrings(
        "trace-closed-by-target fd:-2147483648",
        unresolved_kind.withFd(&b, unresolved_kind.trace_closed, -2147483648),
    );

    for (unresolved_kind.all) |k| {
        const rendered = unresolved_kind.withOp(&b, k, .write, -2147483648);
        try t.expect(std.mem.endsWith(u8, rendered, " write fd:-2147483648"));
    }

    var tiny: [4]u8 = undefined;
    try t.expectEqualStrings(
        unresolved_kind.unlinked_fd,
        unresolved_kind.withFd(&tiny, unresolved_kind.unlinked_fd, 3),
    );
}

pub const OpClass = enum(u16) {
    open = 1,
    write = 2,
    rename = 3,
    unlink = 4,
    fsync = 5,
    truncate = 6,
    mkdir = 7,
    rmdir = 8,
    link = 9,
    /// so it is a kill point and a mutation — the same nature as `link` (#122). Only
    /// the LINK PATH is the operation's address; the target string is content the
    /// subject chose, not a path this run touches, and it is deliberately not carried
    /// in `aux` — resolving or recording it would let a link whose content spells the
    /// state directory be mis-scoped (the oracle applies the same exclusion). This is
    /// therefore NOT a two-path operation: scope is decided from the link path alone.
    symlink = 10,

    // --- lifecycle ops: recorded, never a crash point ---
    close = 100,

    fork = 200,
    exec = 201,
    thread = 202,
    spawn = 203,
    detached = 204,

    thread_started = 205,
    thread_join = 206,
    thread_detach = 207,

    shim_ready = 900,
    kill_landed = 901,
    unresolved = 902,
    unsupported = 903,
    cgroup = 904,

    pub fn isKillPoint(self: OpClass) bool {
        return switch (self) {
            .open, .write, .rename, .unlink, .fsync, .truncate, .mkdir, .rmdir, .link, .symlink => true,
            else => false,
        };
    }

    pub fn isBoundary(self: OpClass) bool {
        return switch (self) {
            .fork, .exec, .thread, .spawn, .detached => true,
            else => false,
        };
    }

    pub fn isThreadSync(self: OpClass) bool {
        return switch (self) {
            .thread_started, .thread_join, .thread_detach => true,
            else => false,
        };
    }

    pub fn isMarker(self: OpClass) bool {
        return switch (self) {
            .shim_ready, .kill_landed, .unresolved, .unsupported, .cgroup => true,
            else => false,
        };
    }

    pub fn unplaceableRefuses(self: OpClass) bool {
        return self.isKillPoint() or self.isBoundary() or self.isMarker() or self.isThreadSync();
    }

    pub fn isMutation(self: OpClass) bool {
        return switch (self) {
            .write, .rename, .unlink, .truncate, .mkdir, .rmdir, .link, .symlink => true,
            else => false,
        };
    }

    pub fn isTwoPath(self: OpClass) bool {
        return self == .rename or self == .link;
    }

    pub fn name(self: OpClass) []const u8 {
        return @tagName(self);
    }

    pub fn fromInt(raw: u16) ?OpClass {
        inline for (@typeInfo(OpClass).@"enum".fields) |f| {
            if (f.value == raw) return @enumFromInt(raw);
        }
        return null;
    }
};

pub const UnknownReason = enum {
    no_shim_marker,
    state_changed_without_ops,
    contract_version_mismatch,
    unsupported_syscall_observed,
    oracle_missed_operation,
    oracle_saw_phantom,
    child_process_detected,
    multiple_threads_detected,
    unresolvable_path,
    kill_did_not_land,
    child_wait_failed,
    /// What the refusal does NOT claim: that the child is gone. SIGKILL was sent, not
    /// observed delivered: the reap runs under a bounded grace, and a child in
    /// uninterruptible sleep — or one whose credentials the group signal cannot
    /// reach — is left behind as a stray for the quiescence check, so the path that
    /// exists to end a hang cannot itself hang. Setting the budget also resets
    /// SIGCHLD to its default disposition once for the whole run (the kill-safety
    /// basis: unreaped children stay zombies, pinning their pids), so every child of
    /// the run sees the same signal environment.
    child_timed_out,
    sequence_numbering_broken,
    completeness_not_verified,
    trace_too_large,
    trace_budget_exhausted,
    /// is why the late sites cannot borrow the early site's verdict. Whichever of the
    /// refusal's message forms applies, it applies on both sides of that split — so what
    /// differs between the two exits is the verdict alone, never the wording.
    state_file_too_large,
    state_tree_too_large,
    /// **Not every unreadable tree reaches this.** The walk skips a directory it cannot
    /// open (`engine/state_fs.zig`'s `opendir … orelse return`), so a tree that is unreadable that
    /// way snapshots as if the directory were empty. This member covers the failures the
    /// walk reports, not every failure it could in principle notice.
    state_unsnapshotable,
    state_rewrite_failed,
    trace_truncated,
    checker_not_falsified,
    marker_never_observed,
    case_no_longer_applies,
    recording_run_failed,
    oracle_saw_nothing,
    baseline_violates_invariant,
    baseline_run_failed,
    child_touched_state_dir,
    boundary_without_oracle,
    state_not_quiescent,
    state_changed_unaccounted,
    unsupported_state_entry,
    /// not run. The claim it supports is narrow — **the next world boundary that is
    /// reached**. A setup, recording or checker run that hangs never reaches one, and a
    /// launcher that dies between fork and the engine's first instruction is not seen
    /// (the baseline is then already the reaper's pid).
    parent_exited,
    /// records the ruling. A floor, not a guarantee: a crash point that names a judged path
    /// without changing it — a lock file opened for writing, a failed call — still counts.
    nothing_could_fail,
    checker_rejects_initial_state,

    pub fn name(self: UnknownReason) []const u8 {
        return @tagName(self);
    }
};

/// The set is closed by name from the release that carries it (`docs/contract-freeze.md`
/// surface 2): a member added later is the same break the page records for `unknown_reason`.
/// A site the rule cannot place is a reason to doubt the rule before adding a member.
pub const SetupErrorReason = enum {
    define_invalid,
    setup_failed,
    environment,
    platform_unsupported,
    internal,

    pub fn name(self: SetupErrorReason) []const u8 {
        return @tagName(self);
    }
};

/// **Closed by name from the release that carries it**, the rule `setup_error_reason`
/// follows (`docs/contract-freeze.md`, surface 2). A third closed set rather than a new
pub const RecoveryResult = enum {
    pass,
    fail,
    unknown,

    pub fn name(self: RecoveryResult) []const u8 {
        return @tagName(self);
    }
};

/// **Closed and payload-free**, so the sentence is a comptime string. `unknown()` is
/// `noreturn` and the promise is "every UNKNOWN carries it": a sentence assembled at run
/// time from an arena could fail to allocate exactly when the report is being written,
/// and a `[]const u8` payload could carry a flag that does not exist or target-chosen
/// bytes into text the MCP surface prints outside its marked region. Members that name
/// a flag name it in the tag and in the sentence, and a unit test holds every `--flag`
/// in every sentence to the help text.
pub const NextStep = enum {
    fix_define,
    pass_oracle,
    account_boundary,
    raise_world_timeout,
    class_wall,
    unwrap_or_class_wall,
    name_framework_interpreter,
    account_boundary_or_unwrap,
    check_shim,
    operation_not_an_image,
    rebuild_pair,
    re_record,
    environment,
    retry_then_report,
    narrow_state,
    unreadable_entry_appeared,
    quiesce,
    relaunch,
    observe_syscalls,
    observe_supervised,
    /// a reader sent to another mode needs to know the image it named is one no shim can enter. It opens
    /// on that reason, not on "Run the same command again", which the acceptance suite anchors to
    /// `observe_supervised` — and it says the file was read before the run, since a reading is
    observe_supervised_static_parent,
    syscalls_may_have_killed,
    declare_cwd,
    sideeye_defect,
    nothing_in_state,
    declare_check_or_marker,
    declare_check,
    run_then_expect_status,
    run_by_hand_signalled,
    second_run_diverged,
    scratch_or_twice,
    kill_not_landed,
    not_repeating,
    /// The opening words are kept: the dogfood entry gate sorts refusals by them.
    threads_limit,
    threads_supervised,
    non_system_build,

    const one_thread_switch = "A tool's own switch for running its file calls on one thread can move it past this — UV_THREADPOOL_SIZE=1 for Node, GOMAXPROCS=1 for Go: set it in the environment Sideeye runs in and declare it in the define's apparatus (env:UV_THREADPOOL_SIZE=1, for example); docs/apparatus.md lists the switches measured and the targets each did not move.";

    pub fn render(self: NextStep) []const u8 {
        return switch (self) {
            .fix_define => "Change the define: the detail above names the declaration this run contradicted, and nothing is judged until it holds.",
            .pass_oracle => "Re-run with --oracle <strace> on Linux or --oracle-fs-usage on macOS, or accept the weaker claim with --allow-unverified.",
            .account_boundary => "Re-run with --oracle <strace> on Linux, the witness that can account for the other process; on macOS a process boundary is refused by design, and --allow-unverified does not lift this refusal.",
            .account_boundary_or_unwrap => "Re-run with --oracle <strace> on Linux, the witness that can account for the other process — or, if the operation is a shell script wrapping another command, invoke that command as the operation instead; on macOS a process boundary is refused by design, and --allow-unverified does not lift this refusal.",
            .raise_world_timeout => "Raise --world-timeout, or find out what the operation waits on.",
            .class_wall => "This target does something Sideeye refuses by design: 'What the target has to be' in the README names each limit, and DESIGN.md gives the reason behind each refusal.",
            .unwrap_or_class_wall => "Check whether the operation is a shell script wrapping another command — if it is, invoke that command as the operation instead; the refusal itself is one the README's 'What the target has to be' names, with DESIGN.md giving the reason.",
            .name_framework_interpreter => "Make the interpreter the detail above names the operation's first word — followed by the #! line's options and the script, when the detail names them — and, when the detail names a __PYVENV_LAUNCHER__ value, set that variable to it in the environment Sideeye runs in (an apparatus entry env:__PYVENV_LAUNCHER__=<value> then stops a run without it as a SETUP ERROR; the variable reaches setup and the checker too): a framework Python's bin/python3 is a launcher that replaces itself with that interpreter where the shim cannot follow.",
            .check_shim => "Check that --shim names the interposition library from this build and that nothing strips the preload from the target's environment.",
            .operation_not_an_image => "What was read at operation is not something the loader inserts a library into. Point operation at an executable image; a #! script hands execution to its interpreter, which is what the insertion would have to reach.",
            .rebuild_pair => "Use the shim and the engine from the same build: --shim must name the library this binary shipped with.",
            .re_record => "Explore the define again under this build; the saved case does not apply here, and a fresh recording yields a fresh case.",
            .environment => "Fix what the detail above names in the environment, then re-run; the define itself is unchanged.",
            .retry_then_report => "Re-run once; if it happens again, file it with the report attached, because the detail cannot say whether the machine or Sideeye stopped short.",
            .unreadable_entry_appeared => "An entry this user cannot read appeared in the state during the run (a lock created with mode 0000 is the common case): re-run as a user that can read it, or point --state at a directory that leaves it outside.",
            .narrow_state => "Point --state at a smaller or shallower directory, or reduce what the operation writes there and how deep it nests; the ceiling the detail names is fixed in this build.",
            .quiesce => "Wait for whatever the target left running to finish, or stop it, so the state directory holds still; then re-run.",
            .relaunch => "Start the exploration from a process that stays alive for its whole duration; the one that launched this run has exited.",
            .observe_syscalls => "Run explore or preflight again with --observe syscalls, which counts most operations at the kernel boundary, including ones that do not pass through libc's interposed entry points — but that mode changes what some targets do, so first read the README entry under 'What the target has to be' that begins 'Under --observe syscalls, a process whose SIGSYS is blocked or reset', and 'What --observe syscalls does not see' in docs/report-schema.md; if the run then fails where it did not under the default mode, the mode may have killed a process or otherwise changed what the target does, which is not a reason to change the define.",
            .observe_supervised => "Run the same command again with --observe supervised (explore, preflight and replay all take it), which counts the operation's state-changing calls from outside the process, where no preloaded library has to reach it — it needs Linux 5.19 or later on aarch64 or x86_64 and a cgroup v2 the engine can create cgroups in, and the --observe entry in docs/cli.md names what it still refuses.",
            .observe_supervised_static_parent => "The file the operation names was read before the run as a statically linked image, which no shim can be loaded into: the shim records this run read came from a process the operation started, or from an image it replaced itself with, and what the operation did in its own image went unrecorded. Run the same command with --observe supervised (explore and preflight take it), which counts those calls from outside the process, where no preloaded library has to reach them — it needs Linux 5.19 or later on aarch64 or x86_64 and a cgroup v2 the engine can create cgroups in, and the --observe entry in docs/cli.md names what it still refuses.",
            .syscalls_may_have_killed => "Under --observe syscalls a run also ends this way when that mode killed a process or otherwise changed what the target does — the README entry under 'What the target has to be' that begins 'Under --observe syscalls, a process whose SIGSYS is blocked or reset' names the processes it kills — so run the operation once under the default mode and compare its exit status, its output and the state it leaves (running the checker on that state by hand) before changing the define, its checker, --expect-status or --marker.",
            .declare_cwd => "Add cwd = \".\" under [define]: the define declares none, so its commands ran in Sideeye's own directory rather than the toml's, and the detail names an argument, or a directory above one, that exists only under the toml's directory.",
            .sideeye_defect => "Nothing in the define fixes this: it is a defect in Sideeye. File it with the report attached.",
            .nothing_in_state => "The operation changed nothing in the state directory that the verdict judges (a change of ownership or permissions alone lands here too). If it should have, find where its store resolved: a define that declares no cwd runs its commands in Sideeye's own directory, and a relative argument resolves there — declare cwd, or point state at the store (docs/cli.md). An operation that is meant to change nothing has no crash point to test.",
            .declare_check_or_marker => "The built-in invariant judges only paths that exist both before and after the operation, and no crash point changed one, so nothing could have failed: declare a check that reads the state the target leaves (docs/checker-cookbook.md), or a marker for the success claim, which judges the files the operation created or removed.",
            .declare_check => "No crash point changed a path the built-in invariants judge, and no marker could judge the rest (none printed in a crash world, or nothing was created or removed outside scratch), so nothing could have failed: declare a check that reads the state the target leaves (docs/checker-cookbook.md).",
            .run_then_expect_status => "Run the operation once by hand, after the setup and in the directory the report names on its cwd line (command_cwd in the JSON), and read what it prints: if the exit status the detail names is how the tool reports success, declare it in the define with --expect-status (expected_status in a sideeye.toml); if it is a failure, fix what it printed — declaring a failure as success would have the failure judged.",
            .run_by_hand_signalled => "Run the operation once by hand, after the setup and in the directory the report names on its cwd line (command_cwd in the JSON), to see what stopped it: it ended without an exit status (the detail names the signal when there was one), which nothing a define declares accounts for — the README's limit 'A clean run exits its declared success status' is the one it stands at. On macOS, a SIGKILL as it starts can be the system refusing an image's signature.",
            .second_run_diverged => "The second run started from the state the restore rebuilt for it — the names, kinds, bytes and permission bits under --state (a directory with its owner's read, write and search bits added), not their owners, set-id or sticky bits, or timestamps — and ended differently. What the operation depends on is one of those, lies outside --state, or does not repeat (a lock, the clock). Run the operation twice by hand after the setup and compare; if what it needs lives in another directory, point --state at one that holds both.",
            .scratch_or_twice => "The path the detail names did not come back with the bytes the recording left, in a world nothing crashed. If those bytes are not what the verdict should judge (a cache, a log, a timestamp), declare the path scratch in the define (--scratch, or scratch in a sideeye.toml); sideeye preflight --twice names the paths two clean runs leave differently, before an exploration.",
            .kill_not_landed => "The world was armed to die in front of the operation the recording numbered, and no kill landed there, so the crash points cannot be trusted to name the same operations in every world. The restore rebuilds the names, kinds, bytes and permission bits under --state (a directory with its owner's read, write and search bits added) — not their owners, set-id or sticky bits, or timestamps, and nothing outside it (a cache kept beside the configuration, a lock) — so a tool that reads those can take another path; sideeye preflight --twice compares what two clean runs leave. If neither explains it, file it with the report attached.",
            .not_repeating => "The world reached the operation number it was given through other operations than the recording's, so the operation did not repeat itself from the state the restore rebuilt — the names, kinds, bytes and permission bits under --state (a directory with its owner's read, write and search bits added), not their owners, set-id or sticky bits, or timestamps, and nothing outside --state (a cache, a lock, the clock). sideeye preflight --twice compares what two clean runs leave, not the operations they perform.",
            .threads_limit => "Two threads of one process wrote the judged directory with nothing recorded ordering their writes. That is the limit the README states under 'What the target has to be': threads are judged where a creation or a join the shim saw orders their writes. " ++ one_thread_switch,
            .threads_supervised => "Two threads of one process wrote the judged directory, and under --observe supervised no join is recorded, nor which thread a creation made, so nothing orders their writes. " ++ one_thread_switch,
            .non_system_build => "The operation's image names a platform in its code directory, the marker Apple's own binaries carry, and macOS strips an inserted library from those; an ad-hoc re-signed copy did not start when that was measured. Make a build of the tool that is not part of macOS (Homebrew's, for example) the operation's first word.",
        };
    }
};

pub const max_path = 4096;

pub const Record = struct {
    op: OpClass,
    /// The exception is `shim_ready`, which carries the continuation base it was GIVEN
    /// (#123) rather than one it read: that announcement is the evidence a chain of
    /// observation survived an image change, and a value read from the trace would agree
    /// with the trace by construction and check nothing.
    seq: u32,
    /// a crash point and a refusal. The value is read live per record — a cached pid
    /// would be the parent's inside a forked child, which is precisely the case the
    /// field exists to distinguish.
    pid: u32,
    /// oracle's `Event.id` is. Read live per record, like `pid`. For a single-threaded
    /// process on Linux it equals `pid`; the engine never assumes that, because the
    /// question this field answers — did exactly one thread write the judged directory —
    /// is asked precisely of the runs where it does not hold.
    tid: u64,
    path: []const u8,
    aux: []const u8,
};

pub const header_len = magic.len + 4;

/// Largest byte length a single record can occupy. The shim builds a record in a
/// stack buffer of this size and writes it with one `write(2)`, so a trace never
/// contains a half-written record even if the process dies mid-run.
pub const max_record_len = 2 + 4 + 4 + 8 + 4 + max_path + 4 + max_path;

pub const EncodeError = error{ BufferTooSmall, PathTooLong };

pub fn encodeHeader(buf: []u8) EncodeError!usize {
    if (buf.len < header_len) return error.BufferTooSmall;
    @memcpy(buf[0..magic.len], magic);
    std.mem.writeInt(u32, buf[magic.len..][0..4], contract_version, .little);
    return header_len;
}

pub fn encodeRecord(buf: []u8, rec: Record) EncodeError!usize {
    if (rec.path.len > max_path or rec.aux.len > max_path) return error.PathTooLong;
    const needed = 2 + 4 + 4 + 8 + 4 + rec.path.len + 4 + rec.aux.len;
    if (buf.len < needed) return error.BufferTooSmall;

    var i: usize = 0;
    std.mem.writeInt(u16, buf[i..][0..2], @intFromEnum(rec.op), .little);
    i += 2;
    std.mem.writeInt(u32, buf[i..][0..4], rec.seq, .little);
    i += 4;
    std.mem.writeInt(u32, buf[i..][0..4], rec.pid, .little);
    i += 4;
    std.mem.writeInt(u64, buf[i..][0..8], rec.tid, .little);
    i += 8;
    std.mem.writeInt(u32, buf[i..][0..4], @intCast(rec.path.len), .little);
    i += 4;
    @memcpy(buf[i..][0..rec.path.len], rec.path);
    i += rec.path.len;
    std.mem.writeInt(u32, buf[i..][0..4], @intCast(rec.aux.len), .little);
    i += 4;
    @memcpy(buf[i..][0..rec.aux.len], rec.aux);
    i += rec.aux.len;
    return i;
}

pub const DecodeError = error{ Truncated, BadMagic, VersionMismatch, BadOpClass, PathTooLong };

pub fn decodeHeader(bytes: []const u8) DecodeError!usize {
    if (bytes.len < header_len) return error.Truncated;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.BadMagic;
    const version = std.mem.readInt(u32, bytes[magic.len..][0..4], .little);
    if (version != contract_version) return error.VersionMismatch;
    return header_len;
}

pub const Decoded = struct {
    rec: Record,
    consumed: usize,
};

/// Borrows from `bytes`; the returned slices stay valid as long as the buffer does.
pub fn decodeRecord(bytes: []const u8) DecodeError!Decoded {
    if (bytes.len < 22) return error.Truncated;
    var i: usize = 0;

    const raw_op = std.mem.readInt(u16, bytes[i..][0..2], .little);
    i += 2;
    const op = OpClass.fromInt(raw_op) orelse return error.BadOpClass;

    const seq = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;

    const pid = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;

    const tid = std.mem.readInt(u64, bytes[i..][0..8], .little);
    i += 8;

    const path_len = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;
    if (path_len > max_path) return error.PathTooLong;
    if (bytes.len < i + path_len + 4) return error.Truncated;
    const path = bytes[i..][0..path_len];
    i += path_len;

    const aux_len = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;
    if (aux_len > max_path) return error.PathTooLong;
    if (bytes.len < i + aux_len) return error.Truncated;
    const aux = bytes[i..][0..aux_len];
    i += aux_len;

    return .{
        .rec = .{ .op = op, .seq = seq, .pid = pid, .tid = tid, .path = path, .aux = aux },
        .consumed = i,
    };
}

/// A plain prefix test would put `/tmp/state2` inside `/tmp/state`, which would make
/// the engine count operations belonging to an unrelated directory — and, worse,
/// miscount the ones belonging to the real one. Both paths are expected to be
/// absolute and already normalised by the caller.
pub fn isInsideDir(path: []const u8, dir: []const u8) bool {
    const d = std.mem.trimEnd(u8, dir, "/");
    if (d.len == 0) return path.len > 0 and path[0] == '/';
    if (!std.mem.startsWith(u8, path, d)) return false;
    if (path.len == d.len) return true;
    return path[d.len] == '/';
}

/// Inside and strictly deeper (#266): equality is excluded. The confinement this
/// serves treats `dir` as a range whose contents are sacrificial — a path EQUAL to
/// the range would make the range itself the sacrificial directory, which for a
/// workspace root is the accident the check exists to refuse. `dir` of "/" still
/// answers true for any other absolute path; the caller refuses that range outright
/// (a range that confines nothing is a misconfiguration, not a wide range).
pub fn isStrictlyInsideDir(path: []const u8, dir: []const u8) bool {
    const d = std.mem.trimEnd(u8, dir, "/");
    // Both sides are trimmed: "/ws/" and "/ws" are the same directory, and trimming
    // only `dir` would let a trailing slash on `path` defeat the equality exclusion
    // this function exists for (isStrictlyInsideDir("/ws/", "/ws") must be false).
    // Production callers pass realpath output, which never carries one — this guards
    // the next caller who does not.
    const p = std.mem.trimEnd(u8, path, "/");
    return isInsideDir(p, d) and p.len > d.len;
}

test "isStrictlyInsideDir excludes equality and component-prefix lookalikes" {
    const t = std.testing;
    try t.expect(isStrictlyInsideDir("/ws/state", "/ws"));
    try t.expect(isStrictlyInsideDir("/ws/a/b", "/ws"));
    try t.expect(!isStrictlyInsideDir("/ws", "/ws"));
    try t.expect(!isStrictlyInsideDir("/wsother", "/ws"));
    try t.expect(!isStrictlyInsideDir("/elsewhere", "/ws"));
    try t.expect(isStrictlyInsideDir("/ws/state", "/ws/"));
    try t.expect(!isStrictlyInsideDir("/ws", "/ws/"));
    try t.expect(!isStrictlyInsideDir("/ws/", "/ws"));
    try t.expect(!isStrictlyInsideDir("/ws/", "/ws/"));
    try t.expect(isStrictlyInsideDir("/anything", "/"));
}

pub const max_components = 256;

pub const NormalizeError = error{ BufferTooSmall, NotAbsolute, TooDeep };

/// This never touches the filesystem, for two reasons. The shim calls it from inside an
/// interposed function on paths that do not exist yet — a rename target, a file about to
/// be created — where `realpath(3)` returns nothing useful. And performing I/O from
/// inside an interposed call invites re-entrancy: the resolution itself would be observed
/// and counted.
///
/// The trade-off is that a symlink in the middle of the path is not followed, so the
/// normalised path can name a different file than the kernel will open. v0.1 treats
/// symlinked state directories as out of bounds rather than pretending otherwise.
pub fn normalizePath(out: []u8, base: []const u8, path: []const u8) NormalizeError![]const u8 {
    const is_abs = path.len > 0 and path[0] == '/';
    if (!is_abs and (base.len == 0 or base[0] != '/')) return error.NotAbsolute;

    var depth: usize = 0;

    if (out.len < 1) return error.BufferTooSmall;
    out[0] = '/';
    var len: usize = 1;

    const parts = [_][]const u8{
        if (is_abs) path else base,
        if (is_abs) "" else path,
    };

    for (parts) |part| {
        var it = std.mem.splitScalar(u8, part, '/');
        while (it.next()) |comp| {
            if (comp.len == 0 or std.mem.eql(u8, comp, ".")) continue;
            if (std.mem.eql(u8, comp, "..")) {
                if (depth > 0) {
                    depth -= 1;
                    const sep = std.mem.lastIndexOfScalar(u8, out[0..len], '/').?;
                    len = if (sep == 0) 1 else sep;
                }
                continue;
            }
            if (depth >= max_components) return error.TooDeep;
            if (len > 1) {
                if (len + 1 > out.len) return error.BufferTooSmall;
                out[len] = '/';
                len += 1;
            }
            depth += 1;
            if (len + comp.len > out.len) return error.BufferTooSmall;
            @memcpy(out[len..][0..comp.len], comp);
            len += comp.len;
        }
    }

    return out[0..len];
}

test "normalizePath resolves relative paths against the base" {
    var buf: [max_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/work/state/key.json",
        try normalizePath(&buf, "/work/state", "key.json"),
    );
    try std.testing.expectEqualStrings(
        "/work/state/key.json",
        try normalizePath(&buf, "/work/state/", "key.json"),
    );
}

test "normalizePath ignores the base for absolute paths" {
    var buf: [max_path]u8 = undefined;
    try std.testing.expectEqualStrings(
        "/etc/passwd",
        try normalizePath(&buf, "/work/state", "/etc/passwd"),
    );
}

test "normalizePath removes dot and parent components" {
    var buf: [max_path]u8 = undefined;
    try std.testing.expectEqualStrings("/a/c", try normalizePath(&buf, "/", "/a/b/../c"));
    try std.testing.expectEqualStrings("/a", try normalizePath(&buf, "/", "/a/./"));
    try std.testing.expectEqualStrings("/", try normalizePath(&buf, "/", "/a/.."));
    try std.testing.expectEqualStrings("/", try normalizePath(&buf, "/", "/a/../.."));
    try std.testing.expectEqualStrings("/b", try normalizePath(&buf, "/a", "../b"));
}

test "normalizePath collapses repeated separators" {
    var buf: [max_path]u8 = undefined;
    try std.testing.expectEqualStrings("/a/b", try normalizePath(&buf, "/", "//a///b//"));
}

test "normalizePath escaping the state dir is visible to the containment test" {
    var buf: [max_path]u8 = undefined;
    const escaped = try normalizePath(&buf, "/work", "state/../elsewhere/f");
    try std.testing.expectEqualStrings("/work/elsewhere/f", escaped);
    try std.testing.expect(!isInsideDir(escaped, "/work/state"));

    const inside = try normalizePath(&buf, "/work", "state/./sub/../key.json");
    try std.testing.expectEqualStrings("/work/state/key.json", inside);
    try std.testing.expect(isInsideDir(inside, "/work/state"));
}

fn normalizePathWithStarts(out: []u8, base: []const u8, path: []const u8) NormalizeError![]const u8 {
    const is_abs = path.len > 0 and path[0] == '/';
    if (!is_abs and (base.len == 0 or base[0] != '/')) return error.NotAbsolute;
    var starts: [max_components]usize = undefined;
    var depth: usize = 0;
    if (out.len < 1) return error.BufferTooSmall;
    out[0] = '/';
    var len: usize = 1;
    const parts = [_][]const u8{ if (is_abs) path else base, if (is_abs) "" else path };
    for (parts) |part| {
        var it = std.mem.splitScalar(u8, part, '/');
        while (it.next()) |comp| {
            if (comp.len == 0 or std.mem.eql(u8, comp, ".")) continue;
            if (std.mem.eql(u8, comp, "..")) {
                if (depth > 0) {
                    depth -= 1;
                    len = starts[depth];
                    if (len > 1) len -= 1;
                }
                continue;
            }
            if (depth >= max_components) return error.TooDeep;
            if (len > 1) {
                if (len + 1 > out.len) return error.BufferTooSmall;
                out[len] = '/';
                len += 1;
            }
            starts[depth] = len;
            depth += 1;
            if (len + comp.len > out.len) return error.BufferTooSmall;
            @memcpy(out[len..][0..comp.len], comp);
            len += comp.len;
        }
    }
    return out[0..len];
}

test "normalizePath answers exactly as the array-of-starts version did (#555)" {
    const alphabet = [_][]const u8{ "", ".", "..", "a", "bb", "c", ".." };
    const bases = [_][]const u8{ "/", "/w", "/w/state/sub" };
    var pbuf: [64]u8 = undefined;
    var idx = [_]usize{0} ** 6;
    var checked: usize = 0;
    while (true) {
        for (1..7) |n| {
            var plen: usize = 0;
            for (idx[0..n], 0..) |k, j| {
                if (j > 0) {
                    pbuf[plen] = '/';
                    plen += 1;
                }
                @memcpy(pbuf[plen..][0..alphabet[k].len], alphabet[k]);
                plen += alphabet[k].len;
            }
            const rel = pbuf[0..plen];
            var abuf: [65]u8 = undefined;
            abuf[0] = '/';
            @memcpy(abuf[1..][0..plen], rel);
            const abs = abuf[0 .. plen + 1];
            for ([_]usize{ 64, 5 }) |cap| {
                for (bases) |b| {
                    for ([_][]const u8{ rel, abs }) |p| {
                        var o1: [64]u8 = undefined;
                        var o2: [64]u8 = undefined;
                        const r1 = normalizePath(o1[0..cap], b, p);
                        const r2 = normalizePathWithStarts(o2[0..cap], b, p);
                        if (r2) |want| {
                            try std.testing.expectEqualStrings(want, try r1);
                        } else |err| {
                            try std.testing.expectError(err, r1);
                        }
                        checked += 1;
                    }
                }
            }
        }
        var d: usize = 0;
        while (d < idx.len) : (d += 1) {
            idx[d] += 1;
            if (idx[d] < alphabet.len) break;
            idx[d] = 0;
        }
        if (d == idx.len) break;
    }
    try std.testing.expect(checked > 100_000);
}

test "normalizePath still refuses the 257th component" {
    var p: [2 * (max_components + 1)]u8 = undefined;
    for (0..max_components + 1) |i| {
        p[2 * i] = 'x';
        p[2 * i + 1] = '/';
    }
    var buf: [max_path]u8 = undefined;
    try std.testing.expectError(error.TooDeep, normalizePath(&buf, "/", p[0..]));
    _ = try normalizePath(&buf, "/", p[0 .. 2 * max_components]);
}

test "normalizePath refuses a relative path with no absolute base" {
    var buf: [max_path]u8 = undefined;
    try std.testing.expectError(error.NotAbsolute, normalizePath(&buf, "relative", "key.json"));
    try std.testing.expectError(error.NotAbsolute, normalizePath(&buf, "", "key.json"));
}

test "normalizePath reports a buffer that cannot hold the result" {
    var small: [4]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, normalizePath(&small, "/", "/abcdefgh"));
}

test "header round-trips" {
    var buf: [header_len]u8 = undefined;
    const n = try encodeHeader(&buf);
    try std.testing.expectEqual(header_len, n);
    try std.testing.expectEqual(header_len, try decodeHeader(buf[0..n]));
}

test "header rejects a foreign magic" {
    var buf: [header_len]u8 = undefined;
    _ = try encodeHeader(&buf);
    buf[0] = 'X';
    try std.testing.expectError(error.BadMagic, decodeHeader(&buf));
}

test "header rejects a different contract version" {
    var buf: [header_len]u8 = undefined;
    _ = try encodeHeader(&buf);
    std.mem.writeInt(u32, buf[magic.len..][0..4], contract_version + 1, .little);
    try std.testing.expectError(error.VersionMismatch, decodeHeader(&buf));
}

test "record round-trips including the two-path form" {
    var buf: [512]u8 = undefined;
    const written = try encodeRecord(&buf, .{
        .op = .rename,
        .seq = 7,
        .pid = 4242,
        .tid = 4242,
        .path = "/s/key.json.tmp",
        .aux = "/s/key.json",
    });
    const got = try decodeRecord(buf[0..written]);
    try std.testing.expectEqual(written, got.consumed);
    try std.testing.expectEqual(OpClass.rename, got.rec.op);
    try std.testing.expectEqual(@as(u32, 7), got.rec.seq);
    try std.testing.expectEqual(@as(u32, 4242), got.rec.pid);
    try std.testing.expectEqual(@as(u64, 4242), got.rec.tid);
    try std.testing.expectEqualStrings("/s/key.json.tmp", got.rec.path);
    try std.testing.expectEqualStrings("/s/key.json", got.rec.aux);
}

test "a thread id wider than a pid survives the round trip (v16)" {
    var buf: [512]u8 = undefined;
    const written = try encodeRecord(&buf, .{
        .op = .write,
        .seq = 1,
        .pid = 7,
        .tid = 0x1_0000_0000_2a,
        .path = "/s/a",
        .aux = "",
    });
    const got = try decodeRecord(buf[0..written]);
    try std.testing.expectEqual(@as(u64, 0x1_0000_0000_2a), got.rec.tid);
    try std.testing.expectEqual(@as(u32, 7), got.rec.pid);
}

test "records decode back to back" {
    var buf: [512]u8 = undefined;
    var i: usize = 0;
    i += try encodeRecord(buf[i..], .{ .op = .shim_ready, .seq = 0, .pid = 10, .tid = 10, .path = "", .aux = "" });
    i += try encodeRecord(buf[i..], .{ .op = .write, .seq = 1, .pid = 10, .tid = 10, .path = "/s/a", .aux = "" });
    i += try encodeRecord(buf[i..], .{ .op = .unlink, .seq = 2, .pid = 11, .tid = 11, .path = "/s/b", .aux = "" });

    var off: usize = 0;
    const first = try decodeRecord(buf[off..i]);
    try std.testing.expectEqual(OpClass.shim_ready, first.rec.op);
    off += first.consumed;
    const second = try decodeRecord(buf[off..i]);
    try std.testing.expectEqual(OpClass.write, second.rec.op);
    try std.testing.expectEqualStrings("/s/a", second.rec.path);
    try std.testing.expectEqual(@as(u32, 10), second.rec.pid);
    off += second.consumed;
    const third = try decodeRecord(buf[off..i]);
    try std.testing.expectEqual(OpClass.unlink, third.rec.op);
    try std.testing.expectEqual(@as(u32, 11), third.rec.pid);
    off += third.consumed;
    try std.testing.expectEqual(i, off);
}

test "a truncated record is reported, not silently accepted" {
    var buf: [512]u8 = undefined;
    const written = try encodeRecord(&buf, .{ .op = .write, .seq = 1, .pid = 1, .tid = 1, .path = "/s/a", .aux = "" });
    try std.testing.expectError(error.Truncated, decodeRecord(buf[0 .. written - 1]));
}

test "an unknown op class is rejected rather than guessed" {
    var buf: [64]u8 = undefined;
    _ = try encodeRecord(&buf, .{ .op = .write, .seq = 1, .pid = 1, .tid = 1, .path = "", .aux = "" });
    std.mem.writeInt(u16, buf[0..2], 4242, .little);
    try std.testing.expectError(error.BadOpClass, decodeRecord(&buf));
}

test "the encoding is little-endian regardless of host" {
    var buf: [64]u8 = undefined;
    _ = try encodeRecord(&buf, .{ .op = .write, .seq = 0x01020304, .pid = 0x0a0b0c0d, .tid = 0x0a0b0c0d, .path = "", .aux = "" });
    try std.testing.expectEqual(@as(u8, 2), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x04), buf[2]);
    try std.testing.expectEqual(@as(u8, 0x03), buf[3]);
    try std.testing.expectEqual(@as(u8, 0x02), buf[4]);
    try std.testing.expectEqual(@as(u8, 0x01), buf[5]);
    try std.testing.expectEqual(@as(u8, 0x0d), buf[6]);
    try std.testing.expectEqual(@as(u8, 0x0c), buf[7]);
    try std.testing.expectEqual(@as(u8, 0x0b), buf[8]);
    try std.testing.expectEqual(@as(u8, 0x0a), buf[9]);
}

test "op categories are disjoint and cover every value" {
    inline for (@typeInfo(OpClass).@"enum".fields) |f| {
        const op: OpClass = @enumFromInt(f.value);
        var categories: usize = 0;
        if (op.isKillPoint()) categories += 1;
        if (op.isBoundary()) categories += 1;
        if (op.isMarker()) categories += 1;
        if (op.isThreadSync()) categories += 1;
        if (op == .close) categories += 1; // the lifecycle category has exactly one member
        try std.testing.expectEqual(@as(usize, 1), categories);
    }
}

test "mutations are a strict subset of kill-point ops" {
    inline for (@typeInfo(OpClass).@"enum".fields) |f| {
        const op: OpClass = @enumFromInt(f.value);
        if (op.isMutation()) try std.testing.expect(op.isKillPoint());
    }
    try std.testing.expect(!OpClass.open.isMutation());
    try std.testing.expect(OpClass.open.isKillPoint());
}

test "fromInt rejects values that are not op classes" {
    try std.testing.expectEqual(OpClass.write, OpClass.fromInt(2).?);
    try std.testing.expectEqual(@as(?OpClass, null), OpClass.fromInt(3333));
}

test "directory containment compares whole components" {
    try std.testing.expect(isInsideDir("/tmp/state/key.json", "/tmp/state"));
    try std.testing.expect(isInsideDir("/tmp/state", "/tmp/state"));
    try std.testing.expect(isInsideDir("/tmp/state/", "/tmp/state"));
    try std.testing.expect(!isInsideDir("/tmp/state2/key.json", "/tmp/state"));
    try std.testing.expect(!isInsideDir("/tmp/other", "/tmp/state"));
    try std.testing.expect(isInsideDir("/tmp/state/key.json", "/tmp/state/"));
    try std.testing.expect(!isInsideDir("/tmp/state2/key.json", "/tmp/state/"));
    try std.testing.expect(isInsideDir("/tmp/anything", "/"));
    try std.testing.expect(isInsideDir("/", "/"));
}
