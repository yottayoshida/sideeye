const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const posix = @import("posix.zig");

pub const exec_arg = "__filter-exec";

/// Required, not an optimisation, and measured (2026-09-27, `~/.cctmp/notif217-*`): without it a
/// target that catches a signal while its call waits for this engine has the call restarted, and
/// the restart arrives as a second notification — three operations counted as four. With it, a
/// notification the engine has received waits through every non-fatal signal.
pub const wait_killable_recv: u32 = 1 << 5;

pub const Config = struct {
    trace_path: []const u8,
    state_dir: []const u8,
    state_alt: []const u8,
    kill_at: u32,
    run_cgroup: []const u8,
    kill_cgroup: []const u8,
};

pub const Error = error{ Unsupported, SpawnSetup, OutOfMemory };

pub const Handover = enum(u8) { arrived, refused, absent };

pub fn handoverFailure(h: Handover, term: posix.Term, comptime whose: []const u8) ?[]const u8 {
    const code = switch (term) {
        .exited => |c| c,
        else => return null,
    };
    if (code != 126) return null;
    return switch (h) {
        .arrived => null,
        .refused => "--observe supervised: " ++ whose ++ " never started its operation: the engine could not complete the hand-over of the seccomp listener the filter installer sent, and the installer exited 126 instead",
        .absent => "--observe supervised: " ++ whose ++ " exited 126 before its operation started — the engine's fork stub or the filter installer stopped first, and no seccomp listener reached the engine. A line on the engine's standard error names the call that failed, unless it was the installer's hand-over itself, which it cannot report: once its filter is in, a write of its own would wait on the listener it failed to hand over",
    };
}

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
        pub fn finish(_: *Self) Handover {
            return .absent;
        }
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

    pub fn finish(self: Spawn) Handover {
        return if (self.session) |s| s.finish() else .arrived;
    }
};

pub const StartError = Error || error{SelfExeUnreadable};

pub fn startFailure(e: StartError) []const u8 {
    return switch (e) {
        error.SelfExeUnreadable => "--observe supervised: could not read /proc/self/exe to start the filter installer",
        error.OutOfMemory => "out of memory",
        error.Unsupported, error.SpawnSetup => "--observe supervised: could not start the supervising thread",
    };
}

pub fn preloadFor(observe: contract.ObserveMode, shim: []const u8) []const u8 {
    return if (observe == .supervised) "" else shim;
}

pub fn observerName(observe: contract.ObserveMode) []const u8 {
    return if (observe == .supervised) "supervising engine" else "shim";
}

pub fn selfExe(arena: std.mem.Allocator) ?[]const u8 {
    if (!available) return null;
    return impl.selfExe(arena);
}

test "a run is refused for the hand-over only when the listener did not arrive and the installer's 126 ended it" {
    const exited126: posix.Term = .{ .exited = 126 };
    try std.testing.expect(handoverFailure(.arrived, exited126, "the run") == null);
    try std.testing.expect(std.mem.indexOf(u8, handoverFailure(.absent, exited126, "the run").?, "the run exited 126 before its operation started") != null);
    try std.testing.expect(std.mem.indexOf(u8, handoverFailure(.refused, exited126, "a world's run").?, "a world's run never started its operation") != null);
    try std.testing.expect(handoverFailure(.absent, .{ .exited = 127 }, "the run") == null);
    try std.testing.expect(handoverFailure(.refused, .{ .signaled = 9 }, "the run") == null);
}
