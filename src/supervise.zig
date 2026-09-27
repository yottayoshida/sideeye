//! `--observe supervised` (#217, ADR 0089): the kill-point operations counted from outside the
//! target, with no shim loaded into it.
//!
//! Two halves, in two processes:
//!
//! - `filterExec` is `sideeye __filter-exec <fd> -- <operation…>`, the process the engine (or the
//!   oracle's strace) starts in place of the operation. It installs a seccomp filter whose action
//!   for every state-changing call is `SECCOMP_RET_USER_NOTIF`, sends the filter's listener and
//!   its own pid back over the socket it inherited, and execs the operation. The pid does not
//!   change across the exec, so the process the engine or strace started IS the subject, as it is
//!   under a shim — which is what lets `readTrace`, the oracle's reading and the world judgement
//!   stay as they are.
//! - `Session` is a thread in the engine. It takes the listener, and for each notification reads
//!   the call's paths out of the target (`process_vm_readv`, `/proc/<tid>/fd`, `/proc/<tid>/cwd`),
//!   decides scope and numbering by the shim's rules, writes the record to the run's trace in the
//!   shim's format, and answers `SECCOMP_USER_NOTIF_FLAG_CONTINUE` — or, at the crash point, does
//!   not answer at all and kills: the call is still suspended when the target dies, so it never
//!   runs, which is what "killed immediately before the k-th operation" means.
//!
//! Why a thread and not the wait loop: `posix.runChildImplWithOps` already carries every
//! mode's timeout and budget, and a listener polled there would change those paths for the
//! modes that have none. The thread starts before the spawn and is joined after it returns,
//! when every process of the run is dead, so the trace is complete before anything reads it.
//!
//! **The two witnesses stay two.** The engine counts through the kernel's notifications; the
//! oracle is strace, a different process watching the same run through ptrace, and the two
//! are independent of each other — which is the objection ADR 0052 decision 3 raised against
//! this design, answered by measurement (ADR 0089).
//!
//! Linux only, on aarch64 and x86_64; everything below that touches the kernel is inside
//! `impl`, which is a stub elsewhere so the engine still builds for macOS.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");

/// The argv[1] that makes this binary the filter installer rather than the engine.
pub const exec_arg = "__filter-exec";

/// `SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV` (Linux 5.19). Not in this toolchain's std.
///
/// Required, not an optimisation, and measured (2026-09-27, `~/.cctmp/notif217-*`): without it a
/// target that catches a signal while its call waits for this engine has the call restarted, and
/// the restart arrives as a second notification — three operations counted as four. With it, a
/// notification the engine has received waits through every non-fatal signal.
pub const wait_killable_recv: u32 = 1 << 5;

/// What the engine hands a session: the same values it would have put in a shim's environment.
pub const Config = struct {
    trace_path: []const u8,
    state_dir: []const u8,
    state_alt: []const u8,
    /// 0 for a run with no crash point (the recording run, the baseline).
    kill_at: u32,
    /// The run's cgroup as the kernel names it (`/proc/<pid>/cgroup`), "" when uncontained.
    run_cgroup: []const u8,
    /// The world's `cgroup.kill`, "" when there is none to write.
    kill_cgroup: []const u8,
};

pub const Error = error{ Unsupported, SpawnSetup, OutOfMemory };

pub const available = builtin.os.tag == .linux and
    (builtin.cpu.arch == .aarch64 or builtin.cpu.arch == .x86_64);

pub const impl = if (available) @import("supervise_linux.zig") else struct {
    pub const Session = struct {
        const Self = @This();
        pub fn start(_: std.mem.Allocator, _: Config) Error!*Self {
            return error.Unsupported;
        }
        pub fn childFd(_: *const Self) i32 {
            return -1;
        }
        pub fn finish(_: *Self) void {}
    };
    pub fn selfExe(_: std.mem.Allocator) ?[]const u8 {
        return null;
    }
    pub fn filterExec(_: []const [:0]const u8) noreturn {
        std.process.exit(126);
    }
    pub fn kernelSupports() bool {
        return false;
    }
};

pub const Session = impl.Session;
pub const filterExec = impl.filterExec;
pub const kernelSupports = impl.kernelSupports;

/// The argv the engine spawns for a supervised operation: this binary as the filter installer,
/// the descriptor it inherits, and the operation. `self_exe` is `/proc/self/exe` resolved.
pub fn wrapArgv(arena: std.mem.Allocator, self_exe: []const u8, fd: i32, op_argv: []const []const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, op_argv.len + 4);
    out[0] = self_exe;
    out[1] = exec_arg;
    out[2] = try std.fmt.allocPrint(arena, "{d}", .{fd});
    out[3] = "--";
    @memcpy(out[4..], op_argv);
    return out;
}

test "the supervised argv is the filter installer, its descriptor, and the operation unchanged" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const got = try wrapArgv(arena_state.allocator(), "/opt/sideeye", 7, &.{ "timew", "undo" });
    try std.testing.expectEqual(@as(usize, 6), got.len);
    try std.testing.expectEqualStrings("/opt/sideeye", got[0]);
    try std.testing.expectEqualStrings(exec_arg, got[1]);
    try std.testing.expectEqualStrings("7", got[2]);
    try std.testing.expectEqualStrings("--", got[3]);
    try std.testing.expectEqualStrings("timew", got[4]);
    try std.testing.expectEqualStrings("undo", got[5]);
}

test {
    if (available) _ = @import("supervise_linux.zig");
}

/// One operation spawn's supervision: the session that counts it, and the argv that starts it
/// through the filter installer. For the other modes, no session and the operation's own argv.
/// The session writes the trace the shim would have written, at the path the shim would have been
/// told; `finish` is called after the spawn returns and before anything reads that trace.
pub const Spawn = struct {
    session: ?*Session,
    argv: []const []const u8,

    pub fn start(
        gpa: std.mem.Allocator,
        arena: std.mem.Allocator,
        observe: contract.ObserveMode,
        op_argv: []const []const u8,
        trace_path: []const u8,
        state_dir: []const u8,
        state_alt: []const u8,
        kill_at: u32,
        run_cgroup: []const u8,
        kill_cgroup: []const u8,
    ) StartError!Spawn {
        if (observe != .supervised) return .{ .session = null, .argv = op_argv };
        const self_exe = selfExe(arena) orelse return error.SelfExeUnreadable;
        const s = try Session.start(gpa, .{
            .trace_path = trace_path,
            .state_dir = state_dir,
            .state_alt = state_alt,
            .kill_at = kill_at,
            .run_cgroup = run_cgroup,
            .kill_cgroup = kill_cgroup,
        });
        const argv = wrapArgv(arena, self_exe, s.childFd(), op_argv) catch return error.OutOfMemory;
        return .{ .session = s, .argv = argv };
    }

    pub fn finish(self: Spawn) void {
        if (self.session) |s| s.finish();
    }
};

pub const StartError = Error || error{SelfExeUnreadable};

/// The setup-error sentence for a supervision that could not start.
pub fn startFailure(e: StartError) []const u8 {
    return switch (e) {
        error.SelfExeUnreadable => "--observe supervised: could not read /proc/self/exe to start the filter installer",
        error.OutOfMemory => "out of memory",
        error.Unsupported, error.SpawnSetup => "--observe supervised: could not start the supervising thread",
    };
}

/// The preload a spawn gets: the shim, or nothing under `--observe supervised`, which loads none.
pub fn preloadFor(observe: contract.ObserveMode, shim: []const u8) []const u8 {
    return if (observe == .supervised) "" else shim;
}

/// Who kept the account the oracle is compared with, for the sentences that name it.
pub fn observerName(observe: contract.ObserveMode) []const u8 {
    return if (observe == .supervised) "supervising engine" else "shim";
}

/// This binary's own path, for the filter installer argv: `/proc/self/exe` resolved.
pub fn selfExe(arena: std.mem.Allocator) ?[]const u8 {
    if (!available) return null;
    return impl.selfExe(arena);
}
