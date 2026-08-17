//! The single source of truth for everything the shim and the engine must agree on.
//!
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
/// v2 added `OpClass.unresolved`: the shim now records that it saw an operation whose
/// path it could not resolve, instead of dropping it. A v1 shim paired with a v2 engine
/// would look like a target that never had such an operation, which is the difference
/// between "nothing to report" and "something was not looked at".
/// v3 added `Record.pid` on every record, and split `.spawn` out of `.fork`. Several
/// processes append to one O_APPEND file, so without the pid "belongs to the previous
/// segment" decides nothing — and the difference between the subject's operation and a
/// child's is the difference between a crash point and a refusal.
/// v4 changed no bytes and no classes, but changed what the recorded set *means*: a
/// write-incapable open (ADR 0003) is no longer observed at all. A v3 trace contains
/// read-only opens that a v4 engine would number as crash points, so the pairing must
/// refuse loudly rather than drift — which is this field's documented purpose.
/// v5 widened the recorded set again (ADR 0005): stdio streams are observed at flush
/// granularity, so `.open`/`.write`/`.close` records now also come from
/// `fopen`/`fflush`/`fclose`. On Linux every affected run was UNKNOWN under v4, but a
/// macOS `--allow-unverified` run of a target that mixes stdio and raw writes could
/// hold a verdict whose reproduce line counts different operations under v5 — the
/// same class of meaning change that bumped v4.
/// v6 added `OpClass.link` (ADR 0006): `link`/`linkat` are now first-class kill points
/// rather than an unmodelled syscall the oracle refused. A v5 shim paired with a v6
/// engine would record no link where a link happened, which the version guard turns
/// into an explicit refusal instead of a positional divergence.
/// v7 changed no bytes and no classes: the shim now observes `remove(3)`, whose
/// internal unlink/rmdir never cross the PLT, by reimplementing its two-step through
/// the recorded wrappers. Removals made through it become `.unlink`/`.rmdir` records
/// (failed attempts included, recorded pre-call like every kill point), so a target
/// that removes state via remove gains addresses a v6 trace does not have — the same
/// class of meaning change that bumped v4 and v5.
/// v8: no descriptor number is exempt from observation. The shim's fd-addressed
/// wrappers previously skipped fd 0/1/2 (and the trace fd) unconditionally; a target
/// that dup2'd a state file onto a standard descriptor wrote invisibly — measured as
/// a false PASS on the oracle-less path. fd resolution is also three-valued now: a
/// proven socket/pipe/device is out of scope, but a path query that *fails* on a
/// regular file records `unresolved` instead of silently passing, and `st_nlink == 0`
/// marks unlinked files on macOS too. The countable operation set changed for
/// affected targets, which is what a version bump means here (same class as v5's
/// stdio and v7's remove).
/// v9 added `OpClass.symlink` (#122): `symlink`/`symlinkat` are now first-class kill
/// points rather than an unmodelled syscall the oracle refused — the same class of
/// change as v6's link, and the same reason to bump: a v8 shim paired with a v9
/// engine would record no symlink where one happened, which the version guard turns
/// into an explicit refusal instead of a positional divergence. Measured motivation:
/// the #118 assisted cohort's stow run refused on `symlinkat` (perl's symlink()
/// reaches the kernel as symlinkat), blocking symlink-farm targets as a class.
/// v10 makes a single-pid execve chain judgeable (#123): the shim's exec wrappers
/// carry the operation count across the image change (`env.seq_base`), the re-run
/// `init()` continues numbering from it, and `shim_ready`'s seq field — always 0
/// through v9 — now carries that base as the continuation evidence the engine
/// requires. No record class or byte shape changed, but the shim↔engine protocol
/// did: a v9 shim paired with a v10 engine would restart numbering after an exec
/// and the engine would read colliding sequence numbers as a judged world. The
/// version guard turns that pairing into an explicit refusal. Measured motivation:
/// the #118 cohort's pass run — a shell CLI whose first act is replacing itself
/// with its interpreter — was refused at that first exec.
pub const contract_version: u32 = 10;

pub const magic = "SIDEEYE1";

/// Environment variables the engine sets and the shim reads.
pub const env = struct {
    /// Absolute path of the directory whose contents define the target's state.
    /// Operations outside it are not counted.
    pub const state_dir = "SIDEEYE_STATE_DIR";
    /// A second spelling of the same directory, when the caller named it through a
    /// symlink. Operations under either spelling are counted, and both are recorded
    /// under the canonical one.
    ///
    /// macOS resolves `/tmp` to `/private/tmp`. A target told its state is at
    /// `/tmp/x` passes `/tmp/x/key.json` to `unlink`, while `F_GETPATH` answers
    /// `/private/tmp/x/key.json` for the same file: one operation, two spellings, and
    /// a prefix test on either alone counts half of them. The engine hides this during
    /// exploration by handing the target the resolved path, which is why it surfaced
    /// only in the `reproduce` line — where the target finds its state its own way.
    pub const state_dir_alt = "SIDEEYE_STATE_DIR_ALT";
    /// Absolute path the shim appends its trace to.
    pub const trace_path = "SIDEEYE_TRACE_PATH";
    /// 1-based index of the kill-point op to die immediately before.
    /// Absent or 0 means the recording run: observe everything, kill nothing.
    pub const kill_at = "SIDEEYE_KILL_AT";
    /// Operation count carried across a self-exec (#123): the shim's exec wrappers
    /// set it for the subject only (never for a forked or vfork'd child), the
    /// re-run `init()` continues numbering from it, and `shim_ready` re-announces
    /// it as its seq. Absent means a fresh start — which after an exec record is
    /// exactly the broken-chain evidence the engine refuses on.
    pub const seq_base = "SIDEEYE_SEQ_BASE";
};

/// The exit-code contract from DESIGN.md §13. UNKNOWN is never 0: a caller that
/// wants to treat "could not judge" as success has to write that down itself.
pub const ExitCode = enum(u8) {
    pass = 0,
    fail = 1,
    unknown = 2,
    setup_error = 3,
};

/// Four categories, and the rule that anything outside them forces UNKNOWN.
///
/// The categories exist because "the set of supported operations" alone cannot
/// describe `close`: it must be recorded (it is real, and the oracle will see it)
/// yet must never become a crash point, since SIGKILL closes descriptors anyway —
/// dying just before `close` and just after it leave the same state behind.
pub const OpClass = enum(u16) {
    // --- kill-point ops: recorded, eligible as crash points ---
    open = 1,
    write = 2,
    rename = 3,
    unlink = 4,
    fsync = 5,
    truncate = 6,
    mkdir = 7,
    rmdir = 8,
    /// A second name for an existing inode (`link`/`linkat`). Creating it changes the
    /// tree, so it is a kill point and a mutation; the crashed world can lack the new
    /// name. Restore reproduces the two names as independent files of equal content —
    /// inode identity and `nlink` are outside the model (ADR 0006).
    link = 9,
    /// A symbolic link (`symlink`/`symlinkat`). Creating one writes a directory entry,
    /// so it is a kill point and a mutation — the same nature as `link` (#122). Only
    /// the LINK PATH is the operation's address; the target string is content the
    /// subject chose, not a path this run touches, and it is deliberately not carried
    /// in `aux` — resolving or recording it would let a link whose content spells the
    /// state directory be mis-scoped (the oracle applies the same exclusion). This is
    /// therefore NOT a two-path operation: scope is decided from the link path alone.
    symlink = 10,

    // --- lifecycle ops: recorded, never a crash point ---
    close = 100,

    // --- boundary detectors ---
    //
    // Since v3 these no longer force UNKNOWN by themselves. A fork- or spawn-boundary is
    // tolerable when an oracle can account for every other process (none of them touched
    // the state directory); exec, thread and detached stay refusals. The *classification*
    // still matters even where the verdict is the same: `posix_spawn` was recorded as
    // `.fork` through v2, which was harmless while both were refused and becomes a hole
    // the moment one of them is not.
    fork = 200,
    exec = 201,
    thread = 202,
    /// A new process *and* a new image (`posix_spawn`/`posix_spawnp`).
    spawn = 203,
    /// The target (or one of its children) left the process group (`setsid`/`setpgid`).
    /// The engine's containment is the group kill; a process that escapes the group is
    /// one the engine can no longer claim to have stopped, so this is recorded to be
    /// refused rather than silently outrun.
    detached = 204,

    // --- markers written by the shim itself, never by the target ---
    /// Written once when the shim finishes initialising. Its *absence* is how the
    /// engine learns the shim never loaded at all (static linking, hardened runtime,
    /// injection disabled) instead of concluding "the target performed no operations".
    shim_ready = 900,
    /// Written immediately before `raise(SIGKILL)`. This is the landing evidence:
    /// proof that the process died where the engine asked it to, rather than the
    /// engine assuming so because it set the variable.
    kill_landed = 901,
    /// The shim saw an operation but could not work out which path it referred to —
    /// an unlinked descriptor, an `O_TMPFILE` handle, a `/proc/self/fd` link that no
    /// longer resolves. Recorded rather than dropped: an operation nobody could place
    /// is not the same as an operation that did not happen, and only the first of those
    /// is compatible with reporting PASS.
    unresolved = 902,

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

    pub fn isMarker(self: OpClass) bool {
        return switch (self) {
            .shim_ready, .kill_landed, .unresolved => true,
            else => false,
        };
    }

    /// Operations that can change what is left on disk.
    ///
    /// `open` is deliberately excluded even though `O_CREAT` creates a file. The
    /// engine uses this predicate for the `state_changed_without_ops` detector —
    /// "the state directory changed but we counted no mutation" means we missed
    /// something. Excluding `open` makes that test *stricter*, not looser: a target
    /// that only ever opened files, yet changed the state, is exactly the kind of
    /// blind spot worth catching. `fsync` is excluded for the same reason it is not
    /// a verdict input — under a process crash the OS survives, so a completed write
    /// is already visible whether or not it was synced.
    pub fn isMutation(self: OpClass) bool {
        return switch (self) {
            .write, .rename, .unlink, .truncate, .mkdir, .rmdir, .link, .symlink => true,
            else => false,
        };
    }

    /// Operations that name two paths (`rename`, `link`). They touch the state directory
    /// when *either* endpoint is inside it, and both observers must agree on that — so
    /// the property lives here, in the shared contract, rather than as a hardcoded list
    /// on each side (ADR 0006).
    pub fn isTwoPath(self: OpClass) bool {
        return self == .rename or self == .link;
    }

    pub fn name(self: OpClass) []const u8 {
        return switch (self) {
            .open => "open",
            .write => "write",
            .rename => "rename",
            .unlink => "unlink",
            .fsync => "fsync",
            .truncate => "truncate",
            .mkdir => "mkdir",
            .rmdir => "rmdir",
            .link => "link",
            .symlink => "symlink",
            .close => "close",
            .fork => "fork",
            .exec => "exec",
            .thread => "thread",
            .spawn => "spawn",
            .detached => "detached",
            .shim_ready => "shim_ready",
            .kill_landed => "kill_landed",
            .unresolved => "unresolved",
        };
    }

    pub fn fromInt(raw: u16) ?OpClass {
        inline for (@typeInfo(OpClass).@"enum".fields) |f| {
            if (f.value == raw) return @enumFromInt(raw);
        }
        return null;
    }
};

/// Why a run could not be judged. Each value corresponds one-to-one with a distinct
/// branch in the code, so a report naming two different reasons is evidence that two
/// different detectors actually fired — not that someone wrote two different strings.
pub const UnknownReason = enum {
    no_shim_marker,
    state_changed_without_ops,
    contract_version_mismatch,
    unsupported_syscall_observed,
    /// The oracle saw a state-directory operation the shim did not record. Distinct
    /// from `state_changed_without_ops`: that one notices the state moved while nothing
    /// was counted, this one names the specific operation that went unseen.
    oracle_missed_operation,
    /// The shim recorded an operation the oracle never saw — over-counting, which
    /// shifts every later crash point by one.
    oracle_saw_phantom,
    child_process_detected,
    multiple_threads_detected,
    unresolvable_path,
    kill_did_not_land,
    /// The subject's kill-point records and its highest sequence number disagree —
    /// the numbering has gaps or duplicates. A restarted counter after an
    /// unobserved image change is exactly a duplicate (#123), and every address
    /// computed from such a trace may name a different operation than the one that
    /// ran. prefixHash catches gaps but not duplicates; this catches both.
    sequence_numbering_broken,
    /// No oracle was available, so the shim's account of what happened could not be
    /// checked against anything. Without it, a target that bypasses libc looks exactly
    /// like one that touched no files — and the structural detectors only catch that
    /// when the *whole* operation bypassed libc, not when part of it did.
    completeness_not_verified,
    /// The trace ended mid-record. Everything after that point is unknown, including
    /// how many operations there were.
    trace_truncated,
    /// A deliberately corrupted state did not make the checker fail, so the checker is
    /// not testing what it claims to test. Every PASS it would go on to produce would
    /// be a statement about nothing (DESIGN §14-13).
    checker_not_falsified,
    /// A success marker was declared but never appeared in the recording run's own
    /// stdout — the run that completes normally. A marker the clean run cannot produce
    /// is a misconfiguration or an unobservable claim, and letting it stand would turn
    /// every L1 obligation vacuous while the report still said PASS (ADR 0008). A
    /// crash world killed before the marker is not this: there the conditional simply
    /// does not apply, which is the normal shape of a post-success invariant.
    marker_never_observed,
    /// A saved case was replayed against code whose recording no longer matches the
    /// case's landing context — the operation count, the class sequence up to the
    /// crash point, or the classes around it changed. Killing at the recorded index
    /// would verify a different point than the counterexample named, so the replay
    /// refuses rather than answer about the wrong world (ADR 0009, DESIGN §13).
    case_no_longer_applies,
    /// The recording run did not complete normally. Its trace describes a partial
    /// execution, so the crash points derived from it address an operation sequence the
    /// target does not actually perform.
    recording_run_failed,
    /// The oracle produced no output at all. Reporting agreement between two empty
    /// views is agreement about nothing.
    oracle_saw_nothing,
    /// The invariant failed in the world that was never crashed. Whatever is wrong is
    /// wrong without any help from sideeye: either the checker rejects a state the
    /// operation produces normally, or the operation is broken on its own. Neither is a
    /// crash-consistency counterexample, and reporting one as "N of N crash worlds
    /// violated" would attribute to crashing something that happens without it.
    baseline_violates_invariant,
    /// The baseline world — the one run to completion without a kill — did not end the
    /// way the recording run did. It is the same command over the same restored state,
    /// so a different outcome means the restored state is not the state that was
    /// recorded, and every verdict drawn from the other worlds rests on that state.
    baseline_run_failed,
    /// A process other than the subject performed an operation on the state directory.
    /// Crash points are numbered per process, so such an operation has no unique
    /// address — and a verdict that silently attributed it to the subject would be a
    /// statement about a program that does not exist.
    child_touched_state_dir,
    /// The target crossed a process boundary and no oracle was available to account for
    /// what the other processes did. The shim can only see processes that load it;
    /// tolerating a boundary on that evidence alone would treat "was not seen" as
    /// "did nothing", which is the confusion this tool exists to refuse.
    boundary_without_oracle,
    /// Two snapshots of the state directory, taken back to back after the run was
    /// contained, disagreed: something was still writing. Whatever the verdict would
    /// have been, it would have described a moment nobody chose.
    state_not_quiescent,
    /// A state-directory entry is neither a regular file, a directory nor a symlink —
    /// a FIFO, a socket, a device. `restore` cannot recreate such an entry, so every
    /// explored world would run against a tree the recording run never had, and the
    /// crash points were derived from the recording run (#5). Refusing is the honest
    /// answer; recreating the common cases later would be an additive relaxation.
    unsupported_state_entry,

    pub fn name(self: UnknownReason) []const u8 {
        return @tagName(self);
    }
};

pub const max_path = 4096;

pub const Record = struct {
    op: OpClass,
    /// 1-based position among kill-point ops inside the state directory.
    /// Zero for lifecycle ops, boundary detectors and markers.
    seq: u32,
    /// The process that performed the operation. Several processes append to one
    /// O_APPEND trace, and which one an operation belongs to is the difference between
    /// a crash point and a refusal. The value is read live per record — a cached pid
    /// would be the parent's inside a forked child, which is precisely the case the
    /// field exists to distinguish.
    pid: u32,
    path: []const u8,
    /// Second path for two-path operations (`rename`), empty otherwise.
    aux: []const u8,
};

pub const header_len = magic.len + 4;

/// Largest byte length a single record can occupy. The shim builds a record in a
/// stack buffer of this size and writes it with one `write(2)`, so a trace never
/// contains a half-written record even if the process dies mid-run.
pub const max_record_len = 2 + 4 + 4 + 4 + max_path + 4 + max_path;

pub const EncodeError = error{ BufferTooSmall, PathTooLong };

pub fn encodeHeader(buf: []u8) EncodeError!usize {
    if (buf.len < header_len) return error.BufferTooSmall;
    @memcpy(buf[0..magic.len], magic);
    std.mem.writeInt(u32, buf[magic.len..][0..4], contract_version, .little);
    return header_len;
}

pub fn encodeRecord(buf: []u8, rec: Record) EncodeError!usize {
    if (rec.path.len > max_path or rec.aux.len > max_path) return error.PathTooLong;
    const needed = 2 + 4 + 4 + 4 + rec.path.len + 4 + rec.aux.len;
    if (buf.len < needed) return error.BufferTooSmall;

    var i: usize = 0;
    std.mem.writeInt(u16, buf[i..][0..2], @intFromEnum(rec.op), .little);
    i += 2;
    std.mem.writeInt(u32, buf[i..][0..4], rec.seq, .little);
    i += 4;
    std.mem.writeInt(u32, buf[i..][0..4], rec.pid, .little);
    i += 4;
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
    if (bytes.len < 14) return error.Truncated;
    var i: usize = 0;

    const raw_op = std.mem.readInt(u16, bytes[i..][0..2], .little);
    i += 2;
    const op = OpClass.fromInt(raw_op) orelse return error.BadOpClass;

    const seq = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;

    const pid = std.mem.readInt(u32, bytes[i..][0..4], .little);
    i += 4;

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
        .rec = .{ .op = op, .seq = seq, .pid = pid, .path = path, .aux = aux },
        .consumed = i,
    };
}

/// True when `path` is inside `dir`, comparing whole path components.
///
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

pub const max_components = 256;

pub const NormalizeError = error{ BufferTooSmall, NotAbsolute, TooDeep };

/// Resolve `path` against `base` and remove `.` and `..` lexically, writing the result
/// into `out`.
///
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

    // Offsets where each surviving component starts, so `..` can pop one.
    var starts: [max_components]usize = undefined;
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
                    len = starts[depth];
                    if (len > 1) len -= 1; // also drop the separator written before it
                }
                // At the root, `..` is the root. Matches how the kernel resolves it.
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
    // The pair matters: a target that opens "state/../elsewhere/f" must not be counted
    // as touching the state directory just because the literal path starts with it.
    var buf: [max_path]u8 = undefined;
    const escaped = try normalizePath(&buf, "/work", "state/../elsewhere/f");
    try std.testing.expectEqualStrings("/work/elsewhere/f", escaped);
    try std.testing.expect(!isInsideDir(escaped, "/work/state"));

    const inside = try normalizePath(&buf, "/work", "state/./sub/../key.json");
    try std.testing.expectEqualStrings("/work/state/key.json", inside);
    try std.testing.expect(isInsideDir(inside, "/work/state"));
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
        .path = "/s/key.json.tmp",
        .aux = "/s/key.json",
    });
    const got = try decodeRecord(buf[0..written]);
    try std.testing.expectEqual(written, got.consumed);
    try std.testing.expectEqual(OpClass.rename, got.rec.op);
    try std.testing.expectEqual(@as(u32, 7), got.rec.seq);
    try std.testing.expectEqual(@as(u32, 4242), got.rec.pid);
    try std.testing.expectEqualStrings("/s/key.json.tmp", got.rec.path);
    try std.testing.expectEqualStrings("/s/key.json", got.rec.aux);
}

test "records decode back to back" {
    var buf: [512]u8 = undefined;
    var i: usize = 0;
    i += try encodeRecord(buf[i..], .{ .op = .shim_ready, .seq = 0, .pid = 10, .path = "", .aux = "" });
    i += try encodeRecord(buf[i..], .{ .op = .write, .seq = 1, .pid = 10, .path = "/s/a", .aux = "" });
    i += try encodeRecord(buf[i..], .{ .op = .unlink, .seq = 2, .pid = 11, .path = "/s/b", .aux = "" });

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
    const written = try encodeRecord(&buf, .{ .op = .write, .seq = 1, .pid = 1, .path = "/s/a", .aux = "" });
    try std.testing.expectError(error.Truncated, decodeRecord(buf[0 .. written - 1]));
}

test "an unknown op class is rejected rather than guessed" {
    var buf: [64]u8 = undefined;
    _ = try encodeRecord(&buf, .{ .op = .write, .seq = 1, .pid = 1, .path = "", .aux = "" });
    std.mem.writeInt(u16, buf[0..2], 4242, .little);
    try std.testing.expectError(error.BadOpClass, decodeRecord(&buf));
}

test "the encoding is little-endian regardless of host" {
    var buf: [64]u8 = undefined;
    _ = try encodeRecord(&buf, .{ .op = .write, .seq = 0x01020304, .pid = 0x0a0b0c0d, .path = "", .aux = "" });
    // op class 2 = write, as two little-endian bytes
    try std.testing.expectEqual(@as(u8, 2), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[1]);
    // seq, least significant byte first
    try std.testing.expectEqual(@as(u8, 0x04), buf[2]);
    try std.testing.expectEqual(@as(u8, 0x03), buf[3]);
    try std.testing.expectEqual(@as(u8, 0x02), buf[4]);
    try std.testing.expectEqual(@as(u8, 0x01), buf[5]);
    // pid, immediately after seq
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
        if (op == .close) categories += 1; // the lifecycle category has exactly one member
        try std.testing.expectEqual(@as(usize, 1), categories);
    }
}

test "mutations are a strict subset of kill-point ops" {
    inline for (@typeInfo(OpClass).@"enum".fields) |f| {
        const op: OpClass = @enumFromInt(f.value);
        if (op.isMutation()) try std.testing.expect(op.isKillPoint());
    }
    // open is observable but not treated as a mutation: excluding it makes
    // state_changed_without_ops stricter, so assert it stays excluded.
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
    // the case a plain prefix test gets wrong
    try std.testing.expect(!isInsideDir("/tmp/state2/key.json", "/tmp/state"));
    try std.testing.expect(!isInsideDir("/tmp/other", "/tmp/state"));
    // a trailing slash on the directory must not change the answer
    try std.testing.expect(isInsideDir("/tmp/state/key.json", "/tmp/state/"));
    try std.testing.expect(!isInsideDir("/tmp/state2/key.json", "/tmp/state/"));
    // a root directory contains every absolute path — the case a hand-rolled
    // `path[dir.len] == '/'` test gets wrong, because the character after "/" in
    // "/tmp" is 't' (review finding against the --work containment vet)
    try std.testing.expect(isInsideDir("/tmp/anything", "/"));
    try std.testing.expect(isInsideDir("/", "/"));
}
