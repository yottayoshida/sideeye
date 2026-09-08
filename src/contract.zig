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
/// v11 widens the countable operation set (#244, #256), the same class of change as
/// v5's stdio, v6's link, v7's remove and v9's symlink. The shim now exports the
/// vectored positional writes (`pwritev`/`pwritev2` and their LFS aliases), the
/// flag-checked `renameat2`, and the kernel copy primitives (`copy_file_range`,
/// `sendfile`); the oracle has classified most of these since v0.1, so what changed
/// is which side sees them, and therefore how many operations a run has. A v10 shim
/// under a v11 engine would record no write where a `pwritev` happened, and every
/// crash-point address after it would name a different operation — the version guard
/// turns that pairing into an explicit refusal instead of a silent divergence.
/// macOS widens too, by two: `pwritev` (which exists there) and `fdatasync` (which
/// the oracle has always classified and the Linux shim has always exported, while the
/// interpose table on this side did not list it). That platform has no oracle to
/// refuse what the shim misses, so the same pairing hazard is worse there rather than
/// milder — a v10 shim under a v11 engine records no write where either happened.
///
/// Measured motivation: a target writing through `pwritev` refused with
/// `oracle_missed_operation`, and one copying through `copy_file_range` with
/// `unsupported_syscall_observed` — the second being the wall that
/// `spike/cohort4/himalaya-r2` was built to work around.
///
/// v12 closes the clone family on macOS (#333) — `clonefile`/`clonefileat`/
/// `fclonefileat` record a `.write` on their destination, and `renamex_np`/
/// `renameatx_np` join `rename` under the same flag discipline `renameat2` has on
/// Linux — plus the new `.unsupported` marker, which is how the macOS shim refuses
/// what it can see but not model (`RENAME_SWAP`, `exchangedata`): on Linux that
/// refusal comes from the oracle, and this platform has no oracle to issue it.
/// Measured motivation: a clone was invisible to both observers — zero operations
/// recorded while a real file appeared with real content — and with any other
/// recorded MUTATION present the run **PASSed** (the zero-ops guard counts
/// mutations, so a mere open or fsync beside the clone kept the refusal); Rust
/// std's `fs::copy` reaches `fclonefileat` first on this platform, so the silent
/// route was the common one, not the exotic one.
/// v13 closes the temp-name creators on both platforms (#39) — `mkstemp`,
/// `mkostemp`, `mkstemps`, `mkostemps` and `mkdtemp` now record the create they
/// perform, because the shim performs it: each replacement reimplements the
/// documented sequence through the recorded wrappers rather than forwarding, which is
/// what `remove` has done since v7 and for the same reason (the inner call never
/// crosses the PLT). No new op class and no new `unknown_reason`: the attempts record
/// as `.open` and `.mkdir`, which both observers already classify. The version moves
/// because the account of an unchanged target does — a target using the canonical C
/// atomic-replace idiom gains crash points it did not have — and crash-point
/// numbering does not carry across versions.
/// v14 adds a second observation path (`--observe syscalls`). A seccomp filter answers
/// `SECCOMP_RET_TRAP` for `write`/`pwrite64`/`writev`/`pwritev` and the shim's SIGSYS
/// handler counts each one through the same `noteFd` the wrappers use, so a write that
/// leaves libc's *inside* — `fwrite` past the buffer, a raw `syscall(SYS_write, …)` —
/// becomes a countable operation. The default mode is unchanged and this bump is not
/// about it: the version moves because the countable operation set of an unchanged
/// target moves under the new mode, which is the same reason v5 (stdio at flush
/// granularity) and v13 (the temp-name creators) moved, and crash-point numbering does
/// not carry across versions. `shim_ready`'s `aux` — empty through v13 — now carries the
/// filter's installation result (`observe_aux`), so a run cannot claim syscall-layer
/// observation that never got installed. Measured motivation: metaflac and fontforge,
/// both recorded in `docs/target-classes.md` as refusing with `oracle_missed_operation`
/// because the shim recorded the `open` and no `write`.
/// v15 makes `seq` an address in the RUN rather than in the process (#123's remaining
/// half). Through v14 every shim instance counted its own in-scope operations from its
/// own `seq`, so a parent and a child each held a number 1 and `SIDEEYE_KILL_AT=3` named
/// no single operation — the measured defect ADR 0002's Context records, and the reason a
/// child touching the judged directory has been refused since v3. The shim now takes its
/// number from the trace itself: the highest `seq` any process has written, plus one.
/// Nothing about a record's byte shape changed and a single-process run numbers exactly
/// as it did, but the shim↔engine protocol did: a v14 shim under a v15 engine would
/// number per process where the engine now tolerates a second writer, and two operations
/// would answer to one address. The version guard turns that pairing into an explicit
/// refusal. `env.seq_base` moves with it — it carried the process's own count across an
/// exec and now carries the run's — and `shim_ready` still announces the value it was
/// given rather than one read from the trace, because that announcement is the evidence
/// #123's chain check compares against. Measured motivation: `pass mv`, whose dangerous
/// operations (the rename, the remove) run in awaited children and were therefore never
/// addressed at all (`spike/assisted/pass/explore-v10-transcript.txt`).
pub const contract_version: u32 = 15;

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
    /// Whether the shim may take the whole process group down with it (v15).
    ///
    /// Set by the engine on a world's spawn and nowhere else, because the engine is what
    /// puts the target in its own process group first (`src/posix.zig`). Killing one
    /// process is not a crash: a shell whose child died runs the next command, so a world
    /// armed at an awaited child's operation would carry operations from after the crash
    /// point it claims to have died at. Killing the group is.
    ///
    /// **It is a flag rather than the shim's own judgement because the shim cannot make
    /// one.** `getpgrp() == getpid()` is true for the subject and false for every child,
    /// and a child that fell back to killing only itself would leave the shell running —
    /// the exact thing this exists to prevent. What differs is not the process, it is how
    /// the run was started, and only the starter knows. Measured: without this, the
    /// `reproduce` line the report prints — which an operator types into a shell that has
    /// done no `setpgid` — killed the acceptance suite's own shell (SIGKILL, exit 137,
    /// at the leg that runs that line).
    pub const kill_group = "SIDEEYE_KILL_GROUP";
    /// Operation count carried across a self-exec (#123): the shim's exec wrappers
    /// set it for the subject only (never for a forked or vfork'd child), the
    /// re-run `init()` continues numbering from it, and `shim_ready` re-announces
    /// it as its seq. Absent means a fresh start — which after an exec record is
    /// exactly the broken-chain evidence the engine refuses on.
    pub const seq_base = "SIDEEYE_SEQ_BASE";
    /// Which observation path to use — one of `ObserveMode`'s names. Absent means
    /// `wrappers`, so a shim carried into a process by an engine that never set it
    /// behaves exactly as v13 did.
    pub const observe = "SIDEEYE_OBSERVE";
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
/// Why an `.unresolved` record could not be placed, written by the shim into `aux`
/// and printed by the engine (#485).
///
/// Here rather than as literals on the shim side for ADR 0006's reason: the two
/// observers must agree on a shared property, and a typo in one of five call sites
/// would otherwise be silent — the engine passes the bytes through, so nothing
/// compares them to anything. `aux` normally holds the other endpoint of a two-path
/// operation; using it for a reason here is the type pun ADR 0003 rejected for open
/// flags, and it is admissible only because `.unresolved` is a marker: the snapshot
/// walk drops markers before the name matching that would read `aux` as a path.
///
/// Not an enum, and not frozen: `contract_version` is unchanged, so an engine can
/// meet a record written by an older shim with an empty `aux`, and a closed set
/// would have to admit that case anyway. These are the values the current shim
/// writes, named so both sides spell them the same way.
/// Which observation path counts the write family.
///
/// A flag rather than a replacement: `wrappers` is the default and its behaviour is
/// byte-for-byte what v13 did. See ADR (0052) for why the syscall path is not the
/// default and why its trap set stops at the write family.
pub const ObserveMode = enum {
    /// libc entry points, interposed. Buffered stdio is observed at flush granularity
    /// (ADR 0005); writes issued inside libc, and raw syscalls, are not observed.
    wrappers,
    /// The syscall boundary, for the write family only. Everything else — `openat`,
    /// `rename`, `unlink`, `fsync`, `copy_file_range`, `sendfile` — is still observed at
    /// the libc entry points in this mode. `pwritev2` is the exception in the other
    /// direction: it cannot be trapped and cannot be counted correctly on both kernels,
    /// so it is refused (`unsupported_syscall_observed`) rather than counted.
    syscalls,

    pub fn parse(text: []const u8) ?ObserveMode {
        if (std.mem.eql(u8, text, "wrappers")) return .wrappers;
        if (std.mem.eql(u8, text, "syscalls")) return .syscalls;
        return null;
    }

    pub fn name(self: ObserveMode) []const u8 {
        return @tagName(self);
    }
};

/// What `shim_ready`'s `aux` says about the syscall-layer filter (v14).
///
/// Empty means `wrappers`: the field carried nothing through v13, so an empty `aux` from
/// a v14 shim is the default mode and not an absence of information. The engine refuses
/// a `--observe syscalls` run whose announcement does not say `armed`, which is what
/// stops a report from claiming an observation path that was never installed.
pub const observe_aux = struct {
    /// The filter is in place; the handler counts the write family.
    pub const armed = "observe:syscalls";
    /// The kernel refused the filter or the handler could not be installed.
    pub const failed = "observe:syscalls-failed";
    /// This build cannot install one at all — not Linux, or an architecture whose trap
    /// frame layout the shim does not know.
    pub const unsupported = "observe:syscalls-unsupported";
};

pub const unresolved_kind = struct {
    /// The path could not be resolved at all (`resolveAt` failed).
    pub const unresolvable_path = "unresolvable-path";
    /// A descriptor whose file could not be read back to a path.
    pub const fd_without_path = "fd-without-path";
    /// An operation through a descriptor whose file was unlinked while it was open —
    /// the `perl -i` shape.
    ///
    /// **Any operation, not only a write.** The branch that records it is keyed on the
    /// descriptor's link count, and `close`, `fsync` and `truncate` reach it as readily as
    /// `write` does — `perl -i` performs the close itself. This constant was
    /// `write-after-unlink` for one commit (#485), which made the report say "write" about
    /// a close; `withOp` is how the operation is named instead of assumed.
    pub const unlinked_fd = "unlinked-fd";
    /// A link whose source is a descriptor: its old path is empty (ADR 0006).
    pub const link_by_descriptor = "link-by-descriptor";
    /// The target closed the trace channel; nothing was named.
    pub const trace_closed = "trace-closed-by-target";
    /// The shim could not read the trace back to find the run's highest sequence number,
    /// so it could not tell which position in the run this operation holds (v15).
    ///
    /// Recorded rather than guessed for the reason every kind here exists: numbering from
    /// a stale local count would give the operation an address that belongs to another one.
    /// A torn record at the end of the trace is NOT this — that is an operation still being
    /// written, and the read stops there and tries again on the next one.
    pub const count_read_failed = "count-read-failed";

    /// The longest a kind can be once `withFd` or `withOp` has appended to it.
    ///
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
        // kind + " " + op + " fd:" + the widest c_int ("-2147483648").
        break :blk longest_kind + 1 + longest_op + 4 + 11;
    };

    /// Every member, so the bound above is derived from the set rather than from whichever
    /// member the author of a size happened to look at. A kind added without a line here
    /// keeps working — it just stops contributing to the bound, which a test catches.
    pub const all = [_][]const u8{
        unresolvable_path,
        fd_without_path,
        unlinked_fd,
        link_by_descriptor,
        trace_closed,
        count_read_failed,
    };

    /// A kind with the descriptor the operation went through appended (#485).
    ///
    /// The grammar lives here rather than at the shim's call sites for the reason the
    /// vocabulary does (ADR 0003's narrowing): a suffix spelled three times in shim
    /// literals is a format the engine reads and nothing defines. Callers pass a buffer —
    /// returning a slice of a local would hand back memory that dies before the record is
    /// written — and a buffer too small keeps the kind and drops the descriptor, so a
    /// record says less rather than arriving half-written.
    ///
    /// **Not always a file descriptor.** `AT_FDCWD` (-100 on Linux, -2 on macOS) reaches
    /// `linkat`'s empty-path branch like any other value and is recorded as passed:
    /// the number in the report is the caller's own argument, which is what an operator
    /// matches against their code.
    pub fn withFd(buf: []u8, kind: []const u8, fd: c_int) []const u8 {
        return std.fmt.bufPrint(buf, "{s} fd:{d}", .{ kind, fd }) catch kind;
    }

    /// `withFd` for the kinds that also know which operation was attempted (#485 asks for
    /// the operation class, the descriptor and the last resolved name; this is what makes
    /// the first of the three true rather than assumed by the kind's name).
    pub fn withOp(buf: []u8, kind: []const u8, op: OpClass, fd: c_int) []const u8 {
        return std.fmt.bufPrint(buf, "{s} {s} fd:{d}", .{ kind, @tagName(op), fd }) catch kind;
    }

    /// The reader for what `withOp` wrote, answering the one question the engine asks of
    /// an unplaceable record: which operation was it, if this is the kind whose
    /// descriptor is known to have pointed at a real file in the judged directory?
    ///
    /// Returns the class only for `unlinked_fd`. `fd_without_path` is deliberately not
    /// read: there the path query itself failed, so where the descriptor pointed is
    /// unknown and a close on it cannot be said to be out of harm's way — ADR 0013's
    /// "a failed measurement never passes as a clean one", and `README.md`'s promise that
    /// a host without `statx` keeps refusing. It reaches this record from an unlinked
    /// descriptor too (`shim/src/common.zig` writes it before the `deleted` branch), which
    /// is exactly why the caller's question has to be about the recorded kind rather than
    /// about "an unlinked descriptor".
    ///
    /// **Parsed, not prefix-matched.** `trace_closed` is the string
    /// "trace-closed-by-target", which CONTAINS "close": a `startsWith` or a substring
    /// test reads it as a close and would exempt a record that names no operation at all.
    /// So: exactly three space-separated tokens, the first equal to `unlinked_fd`, the
    /// second a tag name of this enum, the third a well-formed `fd:<int>`. Anything else
    /// returns null, which the caller treats as "refuses".
    ///
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
    // Every member of the enum, so a new class cannot be added without this failing or
    // being thought about. The claim in the doc comment is the assertion.
    inline for (@typeInfo(OpClass).@"enum".fields) |f| {
        const c: OpClass = @enumFromInt(f.value);
        try t.expectEqual(c != .close, c.unplaceableRefuses());
    }
}

test "opOfUnlinkedFd reads the operation, and every other shape refuses (#485's vocabulary)" {
    const t = std.testing;
    const U = unresolved_kind;

    // The positive cases: what the shim actually writes.
    try t.expectEqual(OpClass.close, U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:3").?);
    try t.expectEqual(OpClass.write, U.opOfUnlinkedFd(.unresolved, "unlinked-fd write fd:3").?);
    try t.expectEqual(OpClass.fsync, U.opOfUnlinkedFd(.unresolved, "unlinked-fd fsync fd:9").?);
    try t.expectEqual(OpClass.truncate, U.opOfUnlinkedFd(.unresolved, "unlinked-fd truncate fd:0").?);
    // AT_FDCWD reaches withOp's `{d}` like any other value.
    try t.expectEqual(OpClass.close, U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:-100").?);

    // The negative cases, written before the reader had a caller. Each one is a shape the
    // shim or an older shim really produces, and each must come back null so the caller
    // refuses.
    //
    // `trace_closed` contains the substring "close" — the whole reason this is a parse.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, U.trace_closed));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "trace-closed-by-target fd:900"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, U.unresolvable_path));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "link-by-descriptor fd:-100"));
    // A v13-or-older shim records no reason at all; `docs/report-schema.md` promises the
    // engine says so rather than guessing.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, ""));
    // The kind without an operation: `withFd`'s spelling, which the unlinked-fd branch no
    // longer writes but an older shim did.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd fd:3"));
    // The other kind that an unlinked descriptor reaches. Refuses by kind, not by class.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "fd-without-path close fd:3"));

    // Malformed tails and extra tokens.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close 3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd close fd:3 extra"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fd nosuchop fd:3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.unresolved, "unlinked-fdclose fd:3"));

    // The class gate: the same string on a record whose `aux` means a second path.
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.rename, "unlinked-fd close fd:3"));
    try t.expectEqual(@as(?OpClass, null), U.opOfUnlinkedFd(.close, "unlinked-fd close fd:3"));
}

test "unresolved_kind.withFd appends the descriptor, and its buffer fits every member (#485)" {
    const t = std.testing;
    var b: [unresolved_kind.with_fd_max]u8 = undefined;

    try t.expectEqualStrings("unlinked-fd fd:3", unresolved_kind.withFd(&b, unresolved_kind.unlinked_fd, 3));
    // The operation-bearing form, which is what the unlinked-fd branch actually writes.
    try t.expectEqualStrings("unlinked-fd close fd:3", unresolved_kind.withOp(&b, unresolved_kind.unlinked_fd, .close, 3));
    try t.expectEqualStrings("unlinked-fd write fd:3", unresolved_kind.withOp(&b, unresolved_kind.unlinked_fd, .write, 3));
    try t.expectEqualStrings("fd-without-path fd:0", unresolved_kind.withFd(&b, unresolved_kind.fd_without_path, 0));
    try t.expectEqualStrings("link-by-descriptor fd:7", unresolved_kind.withFd(&b, unresolved_kind.link_by_descriptor, 7));
    // `AT_FDCWD`, which `linkat` does reach.
    try t.expectEqualStrings("link-by-descriptor fd:-100", unresolved_kind.withFd(&b, unresolved_kind.link_by_descriptor, -100));

    // The declared bound holds for the longest member with the widest `c_int`. Asserted
    // by rendering it: a size computed from the wrong member would leave this one
    // truncated back to the bare kind, which is exactly the silent loss `with_fd_max`
    // exists to make unreachable.
    try t.expectEqualStrings(
        "trace-closed-by-target fd:-2147483648",
        unresolved_kind.withFd(&b, unresolved_kind.trace_closed, -2147483648),
    );

    // Every member, against the widest operation and the widest `c_int`: the bound is
    // derived, and this is what makes the derivation observable rather than argued. A
    // member added without a line in `all` shows up here as a truncated rendering.
    for (unresolved_kind.all) |k| {
        const rendered = unresolved_kind.withOp(&b, k, .write, -2147483648);
        try t.expect(std.mem.endsWith(u8, rendered, " write fd:-2147483648"));
    }

    // Too small a buffer keeps the kind rather than emitting a half-written one.
    var tiny: [4]u8 = undefined;
    try t.expectEqualStrings(
        unresolved_kind.unlinked_fd,
        unresolved_kind.withFd(&tiny, unresolved_kind.unlinked_fd, 3),
    );
}

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
    /// The shim saw an operation it can name and place but not model (v12): a
    /// `RENAME_SWAP`, an `exchangedata` — mutations the restore model cannot
    /// reproduce. On Linux the oracle issues this refusal
    /// (`unsupported_syscall_observed`, by flag name); macOS has no oracle, so the
    /// refusal has to originate in the only observer the platform has. The record's
    /// path field carries the syscall-and-flag spelling, not a path — the same string
    /// the Linux refusal shows — and the shim writes it only when the operation's
    /// paths resolve inside the state directory, because the oracle's refusal is
    /// scope-gated too and an out-of-scope swap is none of this tool's business.
    unsupported = 903,

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
            .shim_ready, .kill_landed, .unresolved, .unsupported => true,
            else => false,
        };
    }

    /// Whether an operation of this class, recorded as unplaceable, refuses the run.
    ///
    /// The refusal exists because an operation that cannot be placed cannot be given a
    /// crash point — `main.zig`'s own message says "so it cannot be placed among the
    /// crash points". `close` is the one class for which that reasoning does not apply:
    /// ADR 0003 §2 excludes it from both class sequences ("`close` is neither a kill
    /// point nor a mutation"), so no crash point was ever going to be computed from it,
    /// and the bytes on disk are the same either side of it. The macOS oracle's reader
    /// has skipped close lines outright since #406, the change that created that reader
    /// (`fsusage.zig`, the `.close` arm of
    /// the descriptor bookkeeping, which `continue`s before the unresolvable checks).
    ///
    /// Written as three predicates rather than `!= .close` on purpose. The property is
    /// the class's, not the name's: anything that changes state is a kill point by
    /// construction (a mutation is a kill point — the `isMutation` ⊆ `isKillPoint`
    /// invariant below pins that), so a future state-changing class refuses here without
    /// anyone remembering to add it. Boundary and marker classes stay refusing because
    /// nothing measured says they can arrive on this path at all; letting them through
    /// would be exempting a shape no measurement covers. Today the three together are
    /// equal to `!= .close` — every other class is a kill point, a boundary or a
    /// marker — and that equality is asserted in the test below so a drift is loud.
    pub fn unplaceableRefuses(self: OpClass) bool {
        return self.isKillPoint() or self.isBoundary() or self.isMarker();
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

    /// The class's own tag, the way `UnknownReason.name` in this file already does it
    /// (#280). This was a hand-written switch of twenty arms, every one of them spelling
    /// its own tag -- measured: twenty members, twenty arms, zero differences -- while
    /// `src/main.zig` printed `@tagName(op.class)` directly in divergence detail. Two
    /// spellings of one thing in one output, kept in step by nothing. The wire format is
    /// `@intFromEnum`, so nothing frozen reads this; what it does reach, besides the
    /// report, is the landing context written into a saved case, which is why the arms
    /// were compared to their tags one by one before the switch was removed rather than
    /// after.
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
    /// A child ran but its exit status could never be read: the wait was interrupted
    /// repeatedly, or failed permanently (#264). Distinct from `kill_did_not_land`,
    /// which is what this used to be reported as — `waitpid` writes `status` only on
    /// success, so a discarded failure left the zero it was initialised with and a
    /// killed world decoded as `exited 0`. That is the wrong reason twice over: it
    /// names the kill when the kill was never observed either way.
    ///
    /// UNKNOWN rather than SETUP_ERROR wherever exploration has begun. Exit 3 means the
    /// define did not run (DESIGN §"exit codes"), and by the recording run onward that
    /// is no longer true — the same distinction `recording_run_failed` already draws.
    child_wait_failed,
    /// A world's operation was still running when its `--world-timeout` budget expired,
    /// as measured by a final successful observation after the deadline, and was sent
    /// SIGKILL (#263).
    /// The message names the budget, because the operator can move it — the rule
    /// `state_file_too_large`, `state_tree_too_large` and `state_rewrite_failed` all
    /// ship under. Off by default: no budget, no member, not one bit of changed
    /// behaviour.
    ///
    /// The name is deliberately wider than today's mechanism. Only the world
    /// operation's spawn carries a budget — a recording run, a setup command or a
    /// checker that hangs still hangs, and the flag's help text says so — but this set
    /// freezes at 1.0 while the mechanism does not, so a member named for worlds would
    /// become a lie the day a 1.x release budgets the recording run, with no new name
    /// available until 2.0. `child_*` is the family it joins.
    ///
    /// What the refusal does NOT claim: that the child is gone. SIGKILL was sent, not
    /// observed delivered: the reap runs under a bounded grace, and a child in
    /// uninterruptible sleep — or one whose credentials the group signal cannot
    /// reach — is left behind as a stray for the quiescence check, so the path that
    /// exists to end a hang cannot itself hang. Setting the budget also resets
    /// SIGCHLD to its default disposition once for the whole run (the kill-safety
    /// basis: unreaped children stay zombies, pinning their pids), so every child of
    /// the run sees the same signal environment.
    /// The timed-out world is not counted in `explored`, like every refusal raised
    /// inside the world loop — which inherits, rather than resolves, the standing gap
    /// between that counter's name ("worlds actually run") and a world that ran only
    /// to be refused. MCP callers cannot set the budget today; the wiring is 1.x work
    /// and touches no frozen surface.
    child_timed_out,
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
    /// The trace was larger than the engine will read (#324). The reader's side of the
    /// pair `trace_truncated` names the writer's: there the shim stopped mid-record,
    /// here the shim's account is complete and the engine declined to hold it. Kept
    /// apart because collapsing them loses which side stopped — and because the cap's
    /// natural collapse, an empty TraceInfo, reads as `no_shim_marker`, which is a
    /// third thing again (the shim never started). UNKNOWN rather than SETUP_ERROR:
    /// every read site is at or past the recording run, where exit 3's "the define
    /// did not run" is no longer true — the line `child_wait_failed` draws above.
    /// (This said "both" while there were three of them; #377 counted.)
    trace_too_large,
    /// The trace reads outstanding at once reached the engine's whole-trace ceiling
    /// (#377, ADR 0033). **Not a synonym for `trace_too_large`**, and kept apart for the
    /// reason `state_tree_too_large` is kept apart from `state_file_too_large`: there the
    /// refusal names one oversized file and an operator can go find it, here every trace
    /// involved may be comfortably small and what ran out is the sum. Collapsing the two
    /// would send that operator looking for a large file that does not exist.
    ///
    /// UNKNOWN rather than SETUP_ERROR for the same reason `trace_too_large` is: every
    /// trace read is at or past the recording run, where exit 3's "the define did not
    /// run" is no longer true.
    ///
    /// **Added after the v1.0 tag**, the second member to be. `docs/contract-freeze.md`
    /// carries the amendment; the previous one is not a precedent this leans on, because
    /// that amendment says so in as many words — this is its own owner ruling.
    trace_budget_exhausted,
    /// A state file was larger than the snapshot will read (#265), at a snapshot taken
    /// at or past the recording run (#330). The initial snapshot hits the same cap and
    /// stays SETUP_ERROR: it runs before anything of the define does, so exit 3's "the
    /// define did not run" is true there and false here. A target that writes a big
    /// file during its own operation reaches this without doing anything wrong, which
    /// is why the late sites cannot borrow the early site's verdict. Whichever of the
    /// refusal's message forms applies, it applies on both sides of that split — so what
    /// differs between the two exits is the verdict alone, never the wording.
    state_file_too_large,
    /// Holding the state tree in memory reached the snapshot's ceiling (#323), at a
    /// snapshot taken at or past the recording run. The initial snapshot hits the same
    /// ceiling and stays SETUP_ERROR, the split `state_file_too_large` above describes.
    ///
    /// **Its own member rather than a share of `state_file_too_large`**, because a caller
    /// reading that one goes looking for a single oversized file and there is none: every
    /// file here can be comfortably under the per-file cap. And **not a share of
    /// `state_unsnapshotable`** either — that member is the residue for failures with no
    /// limit behind them, and this one has a limit the operator can act on, which is the
    /// line `snapshotDetail` already draws when it decides which refusals report a number.
    ///
    /// What the message counts is what the walk had read when the ceiling broke, not what
    /// the tree holds; `engine.TreeTooLargeDiag` records why continuing the walk to learn
    /// the real figures was rejected.
    state_tree_too_large,
    /// The state tree could not be snapshotted at all, at a snapshot taken at or past the
    /// recording run (#351). The sibling of `state_file_too_large`: that one names a file,
    /// its size and a limit the operator can act on, this one covers the walk's other
    /// reported failures — every one except `OutOfMemory`, which stays SETUP_ERROR (see
    /// below), and `TreeTooLarge`, which has a limit of its own and so took a member of
    /// its own (#323; this sentence said "every one except `OutOfMemory`" until then, and
    /// the member above is what made it false). Kept apart from the cap for the reason
    /// `trace_too_large` and
    /// `trace_truncated` are — collapsing them would lose which happened.
    ///
    /// **One member, five kinds of cause**, which the message separates because the closed
    /// set does not: a tree deeper than the walk descends, or a path whose whole spelling
    /// reaches the limit the snapshot can hold (the operator's tree); a file or link that
    /// could not be read, or an entry that could not be classified as file, directory or
    /// symlink (the environment); and an entry list that came out unsorted or duplicated —
    /// that last one is a defect in sideeye, not in the state tree, and its message says
    /// so rather than sending the operator to inspect their files.
    ///
    /// **`OutOfMemory` is deliberately NOT here**: `spawnFailure` states the rule that
    /// allocation failures are environment problems in either phase, and a snapshot that
    /// exits 2 for OOM while the `classify` on that same snapshot exits 3 would put the
    /// seam one statement wide. It stays SETUP_ERROR.
    ///
    /// **Not every unreadable tree reaches this.** The walk skips a directory it cannot
    /// open (`engine/state_fs.zig`'s `opendir … orelse return`), so a tree that is unreadable that
    /// way snapshots as if the directory were empty. This member covers the failures the
    /// walk reports, not every failure it could in principle notice.
    state_unsnapshotable,
    /// The engine could not rewrite the state tree it recorded: the restore that opens
    /// every world (delete the tree, rebuild it from the snapshot), the falsification
    /// probe's restore, or that probe's deliberate corruption. Either way the run can
    /// no longer judge anything, for two different reasons the message separates: a
    /// failed RESTORE means no world can be given its starting tree, and a failed
    /// CORRUPTION means the checker was never shown failing over a broken store, so
    /// nothing it later accepts can be trusted (worlds never start from the corrupted
    /// tree — it exists only to test the checker).
    ///
    /// The write-side sibling of `state_unsnapshotable`: that one is the walk failing
    /// to READ the tree, this one is the engine failing to put it back. Named
    /// "rewrite", not "restore", deliberately — the probe corrupts immediately after a
    /// restore that SUCCEEDED, so a member named for restore would claim the opposite
    /// of what the engine had just demonstrated. One member, three sites; the message
    /// names which rewrite failed, the shape #351 established (the closed set stays
    /// coarse, the message separates).
    ///
    /// **Not every failed rewrite reaches this.** Replay's `--fresh-state` emptying
    /// runs before the define, where SETUP_ERROR is the honest answer, and it stays
    /// there: the phase decides, not the operation (#330's discipline, third
    /// application after `spawnFailure` and the snapshot refusals).
    state_rewrite_failed,
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
    /// crash-consistency counterexample, and reporting one as "N of N explored worlds
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
    /// The judged state changed at a path that no recorded operation names. The
    /// general form of `state_changed_without_ops`, which asks the same question of the
    /// whole run and therefore goes silent as soon as one operation is recorded: a
    /// target whose libc write is seen and whose raw write is not looks exactly like one
    /// that was fully observed (#405, measured on the shipped 1.0.0 — a raw-forked
    /// child's file sat in the judged directory under a PASS).
    ///
    /// Distinct from `state_changed_without_ops` by more than resolution: that name
    /// says operations were counted and there were none, which is false here. Distinct
    /// from `oracle_missed_operation`, which names the syscall a second witness saw the
    /// shim miss; this one has no second witness and names the path instead.
    ///
    /// **Added after the v1.0 tag** — the first member to be, and a break of the freeze
    /// declaration rather than an exception inside it. `docs/contract-freeze.md` carries
    /// the amendment and the reason.
    state_changed_unaccounted,
    /// A state-directory entry is neither a regular file, a directory nor a symlink —
    /// a FIFO, a socket, a device. `restore` cannot recreate such an entry, so every
    /// explored world would run against a tree the recording run never had, and the
    /// crash points were derived from the recording run (#5). Refusing is the honest
    /// answer; recreating the common cases later would be an additive relaxation.
    unsupported_state_entry,
    /// The process that launched this exploration is gone (#269). Opt-in through
    /// `--stop-when-orphaned`: the engine records `getppid()` once at process start and
    /// refuses to begin another world once it changes — parentage only changes when the
    /// parent dies. The MCP adapter passes the flag on every self-exec'd explore and
    /// replay, because an agent host restarts MCP servers as ordinary lifecycle, and an
    /// orphaned explore otherwise keeps killing processes and rewriting its state
    /// directory with nobody left to report to.
    ///
    /// A flag rather than a channel that carries the parent's pid. Argv is per-invocation
    /// and is not inherited, where an environment variable is both: the engine hands the
    /// target its own environment on the non-minimal path, so a pid passed that way
    /// reaches processes nobody set it for, and a stale copy refuses runs it was never
    /// about (measured, both).
    ///
    /// UNKNOWN, not SETUP_ERROR: exploration had begun, and exit 3 means the define did
    /// not run. The claim it supports is narrow — **the next world boundary that is
    /// reached**. A setup, recording or checker run that hangs never reaches one, and a
    /// launcher that dies between fork and the engine's first instruction is not seen
    /// (the baseline is then already the reaper's pid).
    parent_exited,

    pub fn name(self: UnknownReason) []const u8 {
        return @tagName(self);
    }
};

/// What the operator does next about a refusal (#274). Every UNKNOWN carries one — the
/// report's `next_step` field and the text report's `next` line are the same sentence,
/// rendered once — and `main.zig`'s `unknown()` takes it as a required argument, so a
/// refusal without a next step does not compile.
///
/// **A member is an action, not a reason.** The first design was one sentence per
/// `unknown_reason`, and review counted why that cannot be right: the reasons are 34 and
/// the sites that raise them are 85, and one reason routinely bundles causes with
/// different remedies — `state_unsnapshotable` covers a tree that is too deep, a file that
/// cannot be read and an entry list this engine mis-sorted, and the operator does three
/// different things about those. So the choice is made where the cause is known, at the
/// site (or in the disposition helper the site reads from), and this enum only names the
/// actions the sites can choose between. When two sites raising the same reason need
/// different actions, they pick different members; when no member fits, the site adds
/// one and `render` refuses to compile until it has a sentence.
///
/// **Closed and payload-free**, so the sentence is a comptime string. `unknown()` is
/// `noreturn` and the promise is "every UNKNOWN carries it": a sentence assembled at run
/// time from an arena could fail to allocate exactly when the report is being written,
/// and a `[]const u8` payload could carry a flag that does not exist or target-chosen
/// bytes into text the MCP surface prints outside its marked region. Members that name
/// a flag name it in the tag and in the sentence, and a unit test holds every `--flag`
/// in every sentence to the help text.
///
/// The sentences follow ADR 0030's line for refusals: what to do, never why it happened
/// — the `message` beside it reports the observation, and "this class is refused by
/// design" is a fact about Sideeye, not a diagnosis of the target.
pub const NextStep = enum {
    /// The define declares something this run contradicted — a checker that accepted a
    /// corrupted store, a marker that never appeared, an exit status that was not the
    /// declared one, a baseline whose checker or success marker failed there. A baseline
    /// whose bytes did not repeat is not the define's to fix and goes to `class_wall`
    /// (#199).
    fix_define,
    /// A would-be PASS with no completeness witness: the weaker claim is available too.
    pass_oracle,
    /// A process boundary nothing could account for. Not `pass_oracle`: `--allow-unverified`
    /// does not lift this refusal, and on macOS the boundary is refused under the fs_usage
    /// oracle as well — so the sentence names only the one thing that works (review).
    account_boundary,
    /// A world outlived its `--world-timeout` budget.
    raise_world_timeout,
    /// The target does something Sideeye refuses by design: static linking, threads,
    /// other processes on the state, a syscall the restore model cannot reproduce, an
    /// entry kind the snapshot does not hold, a write that does not repeat byte-for-byte
    /// across two clean runs (the README's "Byte-repeatable writes", measured by
    /// `preflight --twice`).
    class_wall,
    /// A boundary refusal in the recording run, where the operation may be a `#!` wrapper
    /// rather than a target of the refused class (#506).
    ///
    /// **The sentence does not branch, and that is the whole of it.** The first version read
    /// "if the operation is a shell script … if it is not …", which cuts off exactly the
    /// population the second half exists for: the published wall for *"Shell CLIs over helper
    /// processes"* (pass) is raised here, and those targets **are** shell scripts, so the
    /// exclusive branch handed them advice that does not apply and took away the entrance to
    /// the README. Nothing here is detected, so the wrapped case, the genuine class and a
    /// target that reached the site through threads all read the same words: a question to
    /// check, then a clause that is true regardless of the answer.
    ///
    /// It says "invoke that command as the operation" rather than naming a flag. `--operation`
    /// is one string and `splitArgs` tokenises it on spaces with no quoting — which is why a
    /// wrapper gets written — and the argv form lives in a `sideeye.toml`, which `preflight`
    /// does not take. Naming either would point at a shape one of the two commands cannot
    /// carry.
    ///
    /// **Five sites carry it, and they are two reasons seen by two observers.** The shim
    /// notices a foreign kill point only in a child that loaded it; a static child, or one
    /// that drops the preload, is seen by the oracle instead — so `child_touched_state_dir`
    /// is raised from two places and both need this step. The same split runs through
    /// `child_process_detected`.
    ///
    /// The detached case (setsid/setpgid) does **not** carry it, **and the honest reason is
    /// the scope ruling, not a property.** The first draft said recommending an argv there
    /// would be false for that population — true of the sentence as it then read, and not of
    /// this one, which only asks. But the same is then true of the oracle-block site, whose
    /// population is threads, `CLONE_FS`, `unshare` and a non-primary setsid: a wrapper
    /// produces none of those either, so the question is answered "no" at both. One is in and
    /// one is out because the owner fixed the scope at five, and #506 records that rather than
    /// dressing it as a distinction.
    unwrap_or_class_wall,
    /// `boundary_without_oracle` in the recording run, where the boundary may be the
    /// operation's own wrapper (#506, owner's scope ruling extending the five).
    ///
    /// Two actions, because two things are true at once: an oracle would let this run be
    /// judged, and a wrapper is a boundary that did not have to exist. Neither is detected,
    /// and the oracle half stays first because it is the one that works whatever the cause.
    account_boundary_or_unwrap,
    /// The image is dynamically linked and the marker still never appeared: the shim is
    /// the thing to look at.
    check_shim,
    /// The file `operation` names was read and could not be recognised as an executable
    /// image, so the insertion the run relies on had nothing to go into. Not `class_wall`:
    /// the limit is on how the define spells this one command, not on what the target
    /// under test is, and the README section that sentence names enumerates the latter.
    /// Not `fix_define`: nothing the define declared was contradicted (#481, #482).
    operation_not_an_image,
    /// Shim and engine speak different trace contracts.
    rebuild_pair,
    /// A saved case that this recording no longer matches.
    re_record,
    /// Something outside both the define and Sideeye that the detail names: permissions,
    /// disk, the oracle binary, a directory that moved.
    environment,
    /// A failure the detail cannot attribute — a trace cut short mid-record, a wait that
    /// kept being interrupted. Once may be the machine; twice is worth reporting.
    retry_then_report,
    /// A ceiling the operator can move by giving Sideeye less to hold.
    narrow_state,
    /// The state directory was still changing after the run was contained.
    quiesce,
    /// The process that launched the exploration went away.
    relaunch,
    /// Nothing the operator changes fixes this; it is Sideeye's.
    sideeye_defect,

    pub fn render(self: NextStep) []const u8 {
        return switch (self) {
            .fix_define => "Change the define: the detail above names the declaration this run contradicted, and nothing is judged until it holds.",
            .pass_oracle => "Re-run with --oracle <strace> on Linux or --oracle-fs-usage on macOS, or accept the weaker claim with --allow-unverified.",
            .account_boundary => "Re-run with --oracle <strace> on Linux, the witness that can account for the other process; on macOS a process boundary is refused by design, and --allow-unverified does not lift this refusal.",
            .account_boundary_or_unwrap => "Re-run with --oracle <strace> on Linux, the witness that can account for the other process — or, if the operation is a shell script wrapping another command, invoke that command as the operation instead; on macOS a process boundary is refused by design, and --allow-unverified does not lift this refusal.",
            .raise_world_timeout => "Raise --world-timeout, or find out what the operation waits on.",
            .class_wall => "This target does something Sideeye refuses by design: 'What the target has to be' in the README names each limit, and DESIGN.md gives the reason behind each refusal.",
            .unwrap_or_class_wall => "Check whether the operation is a shell script wrapping another command — if it is, invoke that command as the operation instead; the refusal itself is one the README's 'What the target has to be' names, with DESIGN.md giving the reason.",
            .check_shim => "Check that --shim names the interposition library from this build and that nothing strips the preload from the target's environment.",
            .operation_not_an_image => "What was read at operation is not something the loader inserts a library into. Point operation at an executable image; a #! script hands execution to its interpreter, which is what the insertion would have to reach.",
            .rebuild_pair => "Use the shim and the engine from the same build: --shim must name the library this binary shipped with.",
            .re_record => "Explore the define again under this build; the saved case does not apply here, and a fresh recording yields a fresh case.",
            .environment => "Fix what the detail above names in the environment, then re-run; the define itself is unchanged.",
            .retry_then_report => "Re-run once; if it happens again, file it with the report attached, because the detail cannot say whether the machine or Sideeye stopped short.",
            .narrow_state => "Point --state at a smaller or shallower directory, or reduce what the operation writes there and how deep it nests; the ceiling the detail names is fixed in this build.",
            .quiesce => "Wait for whatever the target left running to finish, or stop it, so the state directory holds still; then re-run.",
            .relaunch => "Start the exploration from a process that stays alive for its whole duration; the one that launched this run has exited.",
            .sideeye_defect => "Nothing in the define fixes this: it is a defect in Sideeye. File it with the report attached.",
        };
    }
};

pub const max_path = 4096;

pub const Record = struct {
    op: OpClass,
    /// 1-based position among kill-point ops inside the state directory — **in the run,
    /// not in the writing process** (v15). Through v14 each shim instance counted from
    /// its own copy, so a parent and a child both held a 1 and no crash point had a
    /// unique address; the number now comes from the trace's own highest value plus one,
    /// which makes it a position in one sequence however many processes wrote it.
    /// Zero for lifecycle ops, boundary detectors and markers.
    ///
    /// The exception is `shim_ready`, which carries the continuation base it was GIVEN
    /// (#123) rather than one it read: that announcement is the evidence a chain of
    /// observation survived an image change, and a value read from the trace would agree
    /// with the trace by construction and check nothing.
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
    // The ordinary case, and the two accidents #266 refuses: state equal to the
    // range, and a sibling whose name merely extends the range's last component.
    try t.expect(isStrictlyInsideDir("/ws/state", "/ws"));
    try t.expect(isStrictlyInsideDir("/ws/a/b", "/ws"));
    try t.expect(!isStrictlyInsideDir("/ws", "/ws"));
    try t.expect(!isStrictlyInsideDir("/wsother", "/ws"));
    try t.expect(!isStrictlyInsideDir("/elsewhere", "/ws"));
    // Trailing-slash spelling of the same range changes nothing — on either side:
    // a slash on `path` must not smuggle the range itself past the equality
    // exclusion (security review, Minor-2).
    try t.expect(isStrictlyInsideDir("/ws/state", "/ws/"));
    try t.expect(!isStrictlyInsideDir("/ws", "/ws/"));
    try t.expect(!isStrictlyInsideDir("/ws/", "/ws"));
    try t.expect(!isStrictlyInsideDir("/ws/", "/ws/"));
    // "/" as a range answers true for everything else — the caller must refuse it
    // before asking (documented above); this pins that the predicate alone is not
    // the refusal.
    try t.expect(isStrictlyInsideDir("/anything", "/"));
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
