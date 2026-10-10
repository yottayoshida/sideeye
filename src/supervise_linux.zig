//! The Linux half of `--observe supervised` (#217, ADR 0089). `supervise.zig` says what the mode
//! is; this file is how. Every rule about WHICH call counts, how its path is placed, and what is
//! written when it cannot be placed mirrors `shim/src/common.zig` and `shim/src/syscalls.zig`
//! — the shim's handler door — because the three observation modes are doors into one account
//! and a target's account must not depend on which one observed it. Where this file departs from
//! the shim it says so at the departure.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const supervise = @import("supervise.zig");
const image = @import("image.zig");
const engine_build_options = @import("engine_build_options");

const linux = std.os.linux;
const SYS = linux.SYS;
const SECCOMP = linux.SECCOMP;
const E = linux.E;

const Config = supervise.Config;
const Error = supervise.Error;

// --- constants the kernel ABI fixes (identical on aarch64 and x86_64) -------------------

const AT_FDCWD: i32 = -100;
const AT_REMOVEDIR: u32 = 0x200;
const O_ACCMODE: u32 = 0o3;
const O_CREAT: u32 = 0o100;
const O_TRUNC: u32 = 0o1000;
const write_capable_mask: u32 = O_ACCMODE | O_CREAT | O_TRUNC;
const RENAME_EXCHANGE: u32 = 1 << 1;
const RENAME_WHITEOUT: u32 = 1 << 2;
const CLONE_VFORK: u64 = 0x4000;
const CLONE_THREAD: u64 = 0x10000;
const PR_SET_NO_NEW_PRIVS: i32 = 38;

/// `AUDIT_ARCH_*` from <linux/audit.h>, written out: this toolchain's `linux.AUDIT.ARCH` does
/// not compile (it names an `elf.EM` member the same std does not have).
const audit_arch: u32 = switch (builtin.cpu.arch) {
    .aarch64 => 0xC00000B7,
    .x86_64 => 0xC000003E,
    else => @compileError("supervised observation is built for aarch64 and x86_64 only"),
};

/// The shim's predicate, spelled once more because the shim's copy lives in the preloaded
/// library: an open counts when it can write or can create/truncate.
fn openIsWriteCapable(flags: u32) bool {
    if ((flags & O_ACCMODE) != 0) return true;
    return (flags & (O_CREAT | O_TRUNC)) != 0;
}

// --- the filter --------------------------------------------------------------------------

const Watched = struct {
    sys: SYS,
    /// The argument holding open flags, for the calls that count only when write-capable
    /// (the loader's read-only opens must pass without a round trip to the engine).
    flag_arg: ?u3 = null,
};

/// Every kill-point spelling the shim's handler traps (`shim/src/syscalls.zig`), plus the two
/// six-argument calls that set could not hold — `copy_file_range` and `pwritev2`: nothing is
/// re-issued here, so nothing needs a free register — plus the calls that are not operations
/// but boundaries the account records (`close`, the exec and clone families, `setsid`,
/// `setpgid`).
const watched: []const Watched = switch (builtin.cpu.arch) {
    .aarch64 => &common_watched,
    .x86_64 => &(common_watched ++ [_]Watched{
        .{ .sys = .open, .flag_arg = 1 }, .{ .sys = .creat },   .{ .sys = .rename },
        .{ .sys = .unlink },              .{ .sys = .rmdir },   .{ .sys = .mkdir },
        .{ .sys = .link },                .{ .sys = .symlink }, .{ .sys = .fork },
        .{ .sys = .vfork },
    }),
    else => unreachable,
};

const common_watched = [_]Watched{
    .{ .sys = .write },           .{ .sys = .pwrite64 },              .{ .sys = .writev },
    .{ .sys = .pwritev },         .{ .sys = .pwritev2 },              .{ .sys = .sendfile },
    .{ .sys = .copy_file_range }, .{ .sys = .openat, .flag_arg = 2 }, .{ .sys = .openat2 },
    .{ .sys = .renameat },        .{ .sys = .renameat2 },             .{ .sys = .unlinkat },
    .{ .sys = .mkdirat },         .{ .sys = .linkat },                .{ .sys = .symlinkat },
    .{ .sys = .truncate },        .{ .sys = .ftruncate },             .{ .sys = .fsync },
    .{ .sys = .fdatasync },       .{ .sys = .close },                 .{ .sys = .execve },
    .{ .sys = .execveat },        .{ .sys = .clone },                 .{ .sys = .clone3 },
    .{ .sys = .setsid },          .{ .sys = .setpgid },
};

const off_nr: u32 = @offsetOf(SECCOMP.data, "nr");
const off_arch: u32 = @offsetOf(SECCOMP.data, "arch");
fn offArg(i: u3) u32 {
    return @offsetOf(SECCOMP.data, "arg0") + @as(u32, i) * 8;
}

const BPF = linux.BPF;
// Spelled here as the shim spells them (`shim/src/syscalls.zig`): this std has no `sock_filter`.
const SockFilter = extern struct { code: u16, jt: u8, jf: u8, k: u32 };
const SockFprog = extern struct { len: u16, filter: [*]const SockFilter };
fn stmt(code: u16, k: u32) SockFilter {
    return .{ .code = code, .jt = 0, .jf = 0, .k = k };
}
fn jump(code: u16, k: u32, jt: u8, jf: u8) SockFilter {
    return .{ .code = code, .jt = jt, .jf = jf, .k = k };
}

/// A call whose architecture is not the one this binary was built for (i386 compat, x32) is
/// allowed through unseen — the same rule the shim's filter keeps, and a wall ADR 0089 names.
const max_filter = 4 + watched.len * 5 + 1;
fn buildFilter(out: *[max_filter]SockFilter) []SockFilter {
    var n: usize = 0;
    out[n] = stmt(BPF.LD | BPF.W | BPF.ABS, off_arch);
    n += 1;
    out[n] = jump(BPF.JMP | BPF.JEQ | BPF.K, audit_arch, 1, 0);
    n += 1;
    out[n] = stmt(BPF.RET | BPF.K, SECCOMP.RET.ALLOW);
    n += 1;
    for (watched) |w| {
        const nr: u32 = @intCast(@intFromEnum(w.sys));
        out[n] = stmt(BPF.LD | BPF.W | BPF.ABS, off_nr);
        n += 1;
        if (w.flag_arg) |arg| {
            // nr == w? then load the flags; any write-capable bit notifies, none allows.
            out[n] = jump(BPF.JMP | BPF.JEQ | BPF.K, nr, 0, 4);
            n += 1;
            out[n] = stmt(BPF.LD | BPF.W | BPF.ABS, offArg(arg));
            n += 1;
            out[n] = jump(BPF.JMP | BPF.JSET | BPF.K, write_capable_mask, 0, 1);
            n += 1;
            out[n] = stmt(BPF.RET | BPF.K, SECCOMP.RET.USER_NOTIF);
            n += 1;
            out[n] = stmt(BPF.RET | BPF.K, SECCOMP.RET.ALLOW);
            n += 1;
        } else {
            out[n] = jump(BPF.JMP | BPF.JEQ | BPF.K, nr, 0, 1);
            n += 1;
            out[n] = stmt(BPF.RET | BPF.K, SECCOMP.RET.USER_NOTIF);
            n += 1;
        }
    }
    out[n] = stmt(BPF.RET | BPF.K, SECCOMP.RET.ALLOW);
    n += 1;
    return out[0..n];
}

/// Whether this kernel accepts the filter this mode installs — user notification with a
/// listener, and `WAIT_KILLABLE_RECV` — asked in a child that exits at once, so the engine
/// itself never carries a filter.
pub fn kernelSupports() bool {
    // The answer comes back over a pipe, not an exit status: an engine that inherited SIGCHLD
    // ignored has its children reaped by the kernel, and `waitpid` would then say ECHILD for a
    // kernel that supports the mode (review).
    var p: [2]i32 = undefined;
    if (linux.errno(linux.pipe2(&p, .{ .CLOEXEC = true })) != .SUCCESS) return false;
    const pid = linux.fork();
    if (linux.errno(pid) != .SUCCESS) {
        _ = linux.close(p[0]);
        _ = linux.close(p[1]);
        return false;
    }
    if (pid == 0) {
        _ = linux.close(p[0]);
        var ok: u8 = 'n';
        if (linux.errno(linux.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) == .SUCCESS) {
            // The question is whether the kernel takes a listener with these flags, not this
            // mode's filter: the probe notifies on `mknodat` alone, which this child never calls.
            // With the real filter the `write` below would wait for an answer nobody gives —
            // the first version of this pipe did exactly that and hung the engine (measured).
            const probe = [_]SockFilter{
                stmt(BPF.LD | BPF.W | BPF.ABS, off_nr),
                jump(BPF.JMP | BPF.JEQ | BPF.K, @intCast(@intFromEnum(SYS.mknodat)), 0, 1),
                stmt(BPF.RET | BPF.K, SECCOMP.RET.USER_NOTIF),
                stmt(BPF.RET | BPF.K, SECCOMP.RET.ALLOW),
            };
            const prog: SockFprog = .{ .len = probe.len, .filter = &probe };
            const rc = linux.seccomp(SECCOMP.SET_MODE_FILTER, SECCOMP.FILTER_FLAG.NEW_LISTENER | supervise.wait_killable_recv, &prog);
            if (linux.errno(rc) == .SUCCESS) ok = 'y';
        }
        _ = linux.write(p[1], @ptrCast(&ok), 1);
        linux.exit(0);
    }
    _ = linux.close(p[1]);
    var got: u8 = 0;
    var answered = false;
    while (true) {
        const r = linux.read(p[0], @ptrCast(&got), 1);
        if (linux.errno(r) == .INTR) continue;
        answered = linux.errno(r) == .SUCCESS and r == 1;
        break;
    }
    _ = linux.close(p[0]);
    var status: u32 = 0;
    _ = linux.waitpid(@intCast(pid), &status, 0);
    return answered and got == 'y';
}

// --- the installer: `sideeye __filter-exec <fd> -- <operation…>` --------------------------

fn die(code: u8, comptime fmt: []const u8, args: anytype) noreturn {
    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "sideeye: " ++ fmt ++ "\n", args) catch "sideeye: __filter-exec failed\n";
    _ = linux.write(2, msg.ptr, msg.len);
    linux.exit(code);
}

/// The operation's executable, resolved the way `execvp` resolves it — a name with a slash is
/// used as given, one without is looked up along `PATH` — BEFORE the filter goes in, so that the
/// one `execve` the filter sees from this process is the launch and not a probe of `PATH`
/// (review: a failed probe would otherwise read as an image change).
///
/// The search is `image.searchPath`, the same function the engine reads a bare name's image
/// with before the run (ADR 0090), so the file a refusal describes and the file this launches
/// come from one rule. No directory is passed: this process runs after the child's `chdir`, so a
/// relative component already resolves where the operation will run. The default list for an
/// unset `PATH` stays here: this is the caller that execs, so it is the one that has to choose.
fn resolveExecutable(name: [:0]const u8, out: *[image.search_path_max]u8) ?[*:0]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return name.ptr;
    const path_env = std.c.getenv("PATH") orelse "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    const found = image.searchPath(out, name, std.mem.span(path_env), null) orelse return null;
    return found.ptr;
}

pub fn filterExec(argv: []const [:0]const u8) noreturn {
    // argv: <self> __filter-exec <fd> -- <operation…>
    if (argv.len < 5 or !std.mem.eql(u8, argv[3], "--"))
        die(126, "__filter-exec: usage: __filter-exec <fd> -- <operation...>", .{});
    const fd = std.fmt.parseInt(i32, argv[2], 10) catch die(126, "__filter-exec: not a descriptor: {s}", .{argv[2]});
    const op = argv[4..];

    var path_buf: [image.search_path_max]u8 = undefined;
    const exe = resolveExecutable(op[0], &path_buf) orelse
        die(127, "__filter-exec: {s}: not found on PATH", .{op[0]});

    const argv_z = std.heap.page_allocator.alloc(?[*:0]const u8, op.len + 1) catch die(126, "__filter-exec: out of memory", .{});
    for (op, 0..) |a, i| argv_z[i] = a.ptr;
    argv_z[op.len] = null;

    if (linux.errno(linux.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) != .SUCCESS)
        die(126, "__filter-exec: prctl(PR_SET_NO_NEW_PRIVS) was refused", .{});
    var prog_buf: [max_filter]SockFilter = undefined;
    const f = buildFilter(&prog_buf);
    const prog: SockFprog = .{ .len = @intCast(f.len), .filter = f.ptr };
    const lrc = linux.seccomp(SECCOMP.SET_MODE_FILTER, SECCOMP.FILTER_FLAG.NEW_LISTENER | supervise.wait_killable_recv, &prog);
    if (linux.errno(lrc) != .SUCCESS)
        die(126, "__filter-exec: seccomp(SECCOMP_FILTER_FLAG_NEW_LISTENER|WAIT_KILLABLE_RECV) was refused, errno {d}", .{@intFromEnum(linux.errno(lrc))});
    const listener: i32 = @intCast(lrc);

    // The listener travels with this process's pid, which is the subject's: the engine's
    // records carry it, and a group kill is addressed to it.
    const pid: i32 = linux.getpid();
    var payload: [4]u8 = undefined;
    std.mem.writeInt(i32, &payload, pid, .little);
    if (!sendFd(fd, listener, &payload)) die(126, "__filter-exec: could not hand the listener to the engine", .{});
    // Closed through the filter: the engine holds the listener by now and answers these.
    _ = linux.close(listener);
    _ = linux.close(fd);

    const rc = linux.execve(exe, @ptrCast(argv_z.ptr), @ptrCast(std.c.environ));
    // execvp's own fallback: a file without an interpreter line runs under /bin/sh (review).
    if (linux.errno(rc) == .NOEXEC) {
        const sh_argv = std.heap.page_allocator.alloc(?[*:0]const u8, op.len + 2) catch die(126, "__filter-exec: out of memory", .{});
        sh_argv[0] = "/bin/sh";
        sh_argv[1] = exe;
        for (op[1..], 0..) |a, i| sh_argv[i + 2] = a.ptr;
        sh_argv[op.len + 1] = null;
        const rc2 = linux.execve("/bin/sh", @ptrCast(sh_argv.ptr), @ptrCast(std.c.environ));
        die(127, "__filter-exec: exec /bin/sh {s} failed, errno {d}", .{ op[0], @intFromEnum(linux.errno(rc2)) });
    }
    die(127, "__filter-exec: exec {s} failed, errno {d}", .{ op[0], @intFromEnum(linux.errno(rc)) });
}

const Cmsg = extern struct {
    len: usize,
    level: i32,
    type: i32,
    fd: i32,
    pad: i32 = 0,
};

fn sendFd(sock: i32, fd: i32, payload: []const u8) bool {
    var cm: Cmsg = .{ .len = @offsetOf(Cmsg, "fd") + @sizeOf(i32), .level = linux.SOL.SOCKET, .type = linux.SCM.RIGHTS, .fd = fd };
    const iov = [_]std.posix.iovec_const{.{ .base = payload.ptr, .len = payload.len }};
    const msg: linux.msghdr_const = .{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &cm,
        .controllen = @sizeOf(Cmsg),
        .flags = 0,
    };
    while (true) {
        const rc = linux.sendmsg(sock, &msg, 0);
        switch (linux.errno(rc)) {
            .SUCCESS => return rc == payload.len,
            .INTR => continue,
            else => return false,
        }
    }
}

/// The listener and the subject's pid, or null when the socket closed with nothing sent (the
/// installer failed, or never ran).
fn recvFd(sock: i32, pid: *i32) ?i32 {
    var payload: [4]u8 = undefined;
    var cm: Cmsg = .{ .len = 0, .level = 0, .type = 0, .fd = -1 };
    var iov = [_]std.posix.iovec{.{ .base = &payload, .len = payload.len }};
    var msg: linux.msghdr = .{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &cm,
        .controllen = @sizeOf(Cmsg),
        .flags = 0,
    };
    while (true) {
        const rc = linux.recvmsg(sock, &msg, linux.MSG.CMSG_CLOEXEC);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc != payload.len) return null;
                if (cm.level != linux.SOL.SOCKET or cm.type != linux.SCM.RIGHTS or cm.fd < 0) return null;
                pid.* = std.mem.readInt(i32, &payload, .little);
                return cm.fd;
            },
            .INTR => continue,
            else => return null,
        }
    }
}

// --- the engine's side --------------------------------------------------------------------

pub const Session = struct {
    gpa: std.mem.Allocator,
    cfg: Config,
    /// [0] is the engine's end (close-on-exec); [1] is the child's, inherited by the spawn.
    sock: [2]i32,
    thread: std.Thread,
    stop: std.atomic.Value(bool) = .init(false),

    pub fn start(gpa: std.mem.Allocator, cfg: Config) Error!*Session {
        const self = gpa.create(Session) catch return error.OutOfMemory;
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .cfg = undefined, .sock = .{ -1, -1 }, .thread = undefined };
        self.cfg = .{
            .trace_path = gpa.dupe(u8, cfg.trace_path) catch return error.OutOfMemory,
            .state_dir = gpa.dupe(u8, cfg.state_dir) catch return error.OutOfMemory,
            .state_alt = gpa.dupe(u8, cfg.state_alt) catch return error.OutOfMemory,
            .kill_at = cfg.kill_at,
            .run_cgroup = gpa.dupe(u8, cfg.run_cgroup) catch return error.OutOfMemory,
            .kill_cgroup = gpa.dupe(u8, cfg.kill_cgroup) catch return error.OutOfMemory,
        };
        var fds: [2]i32 = undefined;
        if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0, &fds)) != .SUCCESS)
            return error.SpawnSetup;
        // The child's end must survive the exec into strace or the installer.
        if (linux.errno(linux.fcntl(fds[1], linux.F.SETFD, 0)) != .SUCCESS) {
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
            return error.SpawnSetup;
        }
        self.sock = fds;
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch {
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
            return error.SpawnSetup;
        };
        return self;
    }

    pub fn childFd(self: *const Session) i32 {
        return self.sock[1];
    }

    /// After the spawn returned, when every process of the run is gone: closing the child's
    /// end lets a session that never received a listener see end-of-file, and the stop flag
    /// ends a loop whose listener has not yet hung up.
    pub fn finish(self: *Session) void {
        _ = linux.close(self.sock[1]);
        self.stop.store(true, .release);
        self.thread.join();
        _ = linux.close(self.sock[0]);
        const gpa = self.gpa;
        gpa.free(self.cfg.trace_path);
        gpa.free(self.cfg.state_dir);
        gpa.free(self.cfg.state_alt);
        gpa.free(self.cfg.run_cgroup);
        gpa.free(self.cfg.kill_cgroup);
        gpa.destroy(self);
    }

    fn stopping(self: *const Session) bool {
        return self.stop.load(.acquire);
    }
};

/// Wait on one descriptor. Returns its revents, 0 on timeout.
fn pollOne(fd: i32, timeout_ms: i32) u16 {
    var p = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
    const rc = linux.poll(&p, 1, timeout_ms);
    if (linux.errno(rc) != .SUCCESS) return 0;
    if (rc == 0) return 0;
    return @bitCast(p[0].revents);
}

fn monotonicMs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / std.time.ns_per_ms;
}

fn run(self: *Session) void {
    var primary: i32 = 0;
    const listener = while (true) {
        const ev = pollOne(self.sock[0], 50);
        if (ev != 0) break recvFd(self.sock[0], &primary) orelse return;
        if (self.stopping()) return;
    };
    defer _ = linux.close(listener);

    // A trace that cannot be opened leaves nothing to record into, but the listener is held
    // now and every watched call of the target waits on it: the loop below still answers, so
    // the target runs to its end and the engine refuses the run for the missing account rather
    // than hanging on it (review).
    var tracer: ?Tracer = Tracer.open(self.cfg, primary);
    defer if (tracer) |*t| t.close();
    if (tracer) |*t| t.announce(primary, primary);

    var req: SECCOMP.notif = undefined;
    var stop_at: ?u64 = null;
    while (true) {
        // Bounded after the stop, by time and not by idleness: a survivor outside both the
        // cgroup and the group could keep notifying faster than any idle timeout (review).
        if (self.stopping()) {
            const now = monotonicMs();
            if (stop_at == null) stop_at = now;
            if (now - stop_at.? > 1000) return;
        }
        const ev = pollOne(listener, 50);
        if (ev == 0) continue;
        if (ev & linux.POLL.IN == 0) return; // POLLHUP: no task left under the filter
        req = std.mem.zeroes(SECCOMP.notif);
        const rc = linux.ioctl(listener, SECCOMP.IOCTL_NOTIF.RECV, @intFromPtr(&req));
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            // Withdrawn before it reached us: the task died, or a signal took the call back
            // before RECV. Anything else is retried, not returned on — returning would leave
            // the target's next watched call waiting on a listener nobody reads (review).
            else => continue,
        }
        const answer: Answer = if (tracer) |*t| t.handle(listener, &req) else .@"continue";
        // Only in `sideeye-testsupervisedelay` (#217): hold the received call before answering,
        // so a signal the target receives meanwhile lands in the window WAIT_KILLABLE_RECV is for.
        if (engine_build_options.supervise_reply_delay_ms != 0) {
            const ts: linux.timespec = .{ .sec = 0, .nsec = @as(isize, engine_build_options.supervise_reply_delay_ms) * std.time.ns_per_ms };
            _ = linux.nanosleep(&ts, null);
        }
        if (answer == .@"continue") {
            var resp: SECCOMP.notif_resp = .{ .id = req.id, .val = 0, .@"error" = 0, .flags = SECCOMP.USER_NOTIF_FLAG_CONTINUE };
            // SEND takes an interruptible lock; an EINTR there leaves the call waiting forever
            // (WAIT_KILLABLE_RECV), so it is sent again. ENOENT is a call already gone (review).
            while (true) {
                const src = linux.ioctl(listener, SECCOMP.IOCTL_NOTIF.SEND, @intFromPtr(&resp));
                if (linux.errno(src) != .INTR) break;
            }
        }
    }
}

const Answer = enum { @"continue", withheld };

/// The run's account, as the shim would have written it.
const Tracer = struct {
    cfg: Config,
    fd: i32,
    primary: i32,
    seq: u32,
    /// The installer's own `execve` into the operation is the launch, not an image change.
    launched: bool = false,
    /// Once the crash point's kill is sent nothing is answered or recorded again: the tasks
    /// still in flight are dying, and a call of theirs let through now would land after the
    /// crash point the world claims to have stopped at.
    killed: bool = false,
    rec_buf: [contract.max_record_len]u8 = undefined,
    path_a: [contract.max_path]u8 = undefined,
    path_b: [contract.max_path]u8 = undefined,
    raw_a: [contract.max_path]u8 = undefined,
    raw_b: [contract.max_path]u8 = undefined,
    base_buf: [contract.max_path]u8 = undefined,
    canon_a: [contract.max_path]u8 = undefined,
    canon_b: [contract.max_path]u8 = undefined,

    fn open(cfg: Config, primary: i32) ?Tracer {
        var pbuf: [contract.max_path + 1]u8 = undefined;
        const p = std.fmt.bufPrintZ(&pbuf, "{s}", .{cfg.trace_path}) catch return null;
        // Non-blocking and held to a regular file, as the shim holds its own trace (#492, #400):
        // a FIFO planted at the name would otherwise block this open, and with it the target.
        const flags: linux.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true };
        const rc = linux.open(p.ptr, flags, 0o600);
        if (linux.errno(rc) != .SUCCESS) return null;
        const fd: i32 = @intCast(rc);
        var sx: linux.Statx = undefined;
        if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true }, &sx)) != .SUCCESS or
            sx.mode & linux.S.IFMT != linux.S.IFREG)
        {
            _ = linux.close(fd);
            return null;
        }
        // Numbered from 0, as every shim of the run is: the engine pins SIDEEYE_SEQ_BASE empty.
        var t: Tracer = .{ .cfg = cfg, .fd = fd, .primary = primary, .seq = 0 };
        const end = linux.lseek(fd, 0, linux.SEEK.END);
        if (linux.errno(end) == .SUCCESS and end == 0) {
            var head: [contract.header_len]u8 = undefined;
            const n = contract.encodeHeader(&head) catch return null;
            t.writeAll(head[0..n]);
        }
        return t;
    }

    fn close(self: *Tracer) void {
        _ = linux.close(self.fd);
    }

    fn writeAll(self: *Tracer, bytes: []const u8) void {
        var off: usize = 0;
        while (off < bytes.len) {
            const rc = linux.write(self.fd, bytes[off..].ptr, bytes.len - off);
            switch (linux.errno(rc)) {
                .SUCCESS => {
                    if (rc == 0) return;
                    off += rc;
                },
                .INTR => continue,
                else => return,
            }
        }
    }

    fn record(self: *Tracer, op: contract.OpClass, s: u32, pid: i32, tid: i32, path: []const u8, aux: []const u8) void {
        const n = contract.encodeRecord(&self.rec_buf, .{
            .op = op,
            .seq = s,
            .pid = @bitCast(pid),
            .tid = @intCast(tid),
            .path = path,
            .aux = aux,
        }) catch return;
        self.writeAll(self.rec_buf[0..n]);
    }

    /// `shim_ready` for an image, then — in a contained run — where that process stands against
    /// the run's cgroup, which the engine's `containment.holds` counts one of per announcement.
    fn announce(self: *Tracer, pid: i32, tid: i32) void {
        self.record(.shim_ready, self.seq, pid, tid, self.cfg.state_dir, contract.observe_aux.supervised);
        if (self.cfg.run_cgroup.len == 0) return;
        const aux = switch (self.standing(pid)) {
            .held => if (self.cfg.kill_cgroup.len > 0) contract.cgroup_aux.held_kill else contract.cgroup_aux.held,
            .outside => contract.cgroup_aux.outside,
            .unknown => contract.cgroup_aux.unreadable,
        };
        self.record(.cgroup, 0, pid, tid, self.cfg.state_dir, aux);
    }

    fn standing(self: *Tracer, pid: i32) contract.CgroupStanding {
        var pbuf: [64]u8 = undefined;
        const p = std.fmt.bufPrintZ(&pbuf, "/proc/{d}/cgroup", .{pid}) catch return .unknown;
        var text: [4096]u8 = undefined;
        const t = readSmall(p, &text) orelse return .unknown;
        return contract.standingOf(t, self.cfg.run_cgroup);
    }

    /// A boundary, and — as the shim does at one — the cgroup asked again, said when not held.
    fn boundary(self: *Tracer, op: contract.OpClass, pid: i32, tid: i32) void {
        self.record(op, 0, pid, tid, "", "");
        if (self.cfg.run_cgroup.len == 0) return;
        const aux: ?[]const u8 = switch (self.standing(pid)) {
            .held => null,
            .outside => contract.cgroup_aux.outside,
            .unknown => contract.cgroup_aux.unreadable,
        };
        if (aux) |a| self.record(.cgroup, 0, pid, tid, self.cfg.state_dir, a);
    }

    fn handle(self: *Tracer, listener: i32, req: *const SECCOMP.notif) Answer {
        if (self.killed) return .withheld;
        const tid: i32 = @bitCast(req.pid);
        const pid = tgidOf(tid) orelse {
            // A task that is gone makes no call; one that is still there and cannot be read is
            // an operation seen and not placed, which is recorded, not dropped (review).
            var id = req.id;
            if (linux.errno(linux.ioctl(listener, SECCOMP.IOCTL_NOTIF.ID_VALID, @intFromPtr(&id))) == .SUCCESS)
                self.record(.unresolved, 0, self.primary, tid, "", contract.unresolved_kind.unresolvable_path);
            return .@"continue";
        };
        const a = [6]u64{ req.data.arg0, req.data.arg1, req.data.arg2, req.data.arg3, req.data.arg4, req.data.arg5 };
        const sys: SYS = @enumFromInt(req.data.nr);
        var ctx: Call = .{ .t = self, .listener = listener, .id = req.id, .pid = pid, .tid = tid };
        return ctx.dispatch(sys, a);
    }

    fn canonical(self: *Tracer, out: []u8, path: []const u8) []const u8 {
        const alt = self.cfg.state_alt;
        const sd = self.cfg.state_dir;
        if (alt.len == 0) return path;
        if (contract.isInsideDir(path, sd)) return path;
        if (!contract.isInsideDir(path, alt)) return path;
        const tail = path[alt.len..];
        if (sd.len + tail.len > out.len) return path;
        @memcpy(out[0..sd.len], sd);
        @memcpy(out[sd.len..][0..tail.len], tail);
        return out[0 .. sd.len + tail.len];
    }

    fn inState(self: *Tracer, path: []const u8) bool {
        if (contract.isInsideDir(path, self.cfg.state_dir)) return true;
        return self.cfg.state_alt.len != 0 and contract.isInsideDir(path, self.cfg.state_alt);
    }

    /// The shim's `observe`: scope, numbering, the crash point, and the record.
    fn observe(self: *Tracer, op: contract.OpClass, pid: i32, tid: i32, raw_path: []const u8, raw_aux: []const u8) Answer {
        const path = self.canonical(&self.canon_a, raw_path);
        const aux = self.canonical(&self.canon_b, raw_aux);
        var s: u32 = 0;
        if (op.isKillPoint()) {
            const in_scope = contract.isInsideDir(path, self.cfg.state_dir) or
                (op.isTwoPath() and aux.len > 0 and contract.isInsideDir(aux, self.cfg.state_dir));
            if (!in_scope) return .@"continue";
            self.seq += 1;
            s = self.seq;
            if (self.cfg.kill_at != 0 and s == self.cfg.kill_at) {
                self.record(.kill_landed, s, pid, tid, path, aux);
                self.kill(s, pid, tid, path);
                return .withheld;
            }
        } else if (op == .close) {
            if (!contract.isInsideDir(path, self.cfg.state_dir)) return .@"continue";
        }
        self.record(op, s, pid, tid, path, aux);
        return .@"continue";
    }

    /// The crash point. The call that reached it is still suspended — this function does not
    /// answer it — so it never runs. The cgroup's `cgroup.kill` first where the world has one
    /// (it reaches a process however it left the group), then the subject's process group. The
    /// engine stands outside the cgroup, so unlike the shim there is nothing to step aside
    /// from. A `cgroup.kill` that could not be written is said before the group kill, as the
    /// shim says it, so the engine refuses the world rather than trust a short kill.
    fn kill(self: *Tracer, s: u32, pid: i32, tid: i32, path: []const u8) void {
        self.killed = true;
        if (self.cfg.kill_cgroup.len > 0) {
            var kbuf: [contract.max_path + 1]u8 = undefined;
            const wrote = blk: {
                const kp = std.fmt.bufPrintZ(&kbuf, "{s}", .{self.cfg.kill_cgroup}) catch break :blk false;
                const rc = linux.open(kp.ptr, .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
                if (linux.errno(rc) != .SUCCESS) break :blk false;
                const kfd: i32 = @intCast(rc);
                defer _ = linux.close(kfd);
                const w = linux.write(kfd, "1", 1);
                break :blk linux.errno(w) == .SUCCESS and w == 1;
            };
            if (!wrote) self.record(.cgroup, s, pid, tid, path, contract.cgroup_aux.kill_returned);
        }
        _ = linux.kill(-self.primary, linux.SIG.KILL);
    }
};

/// One notification being handled: where to read its arguments, and the id that says whether
/// what was read still belongs to it.
const Call = struct {
    t: *Tracer,
    listener: i32,
    id: u64,
    pid: i32,
    tid: i32,

    /// The notification is still pending — so the memory just read was the calling task's, and
    /// its descriptors are the ones the call named. Asked after every read of the target, the
    /// way seccomp_unotify(2) asks it of a supervisor.
    fn stillValid(self: *const Call) bool {
        var id = self.id;
        const rc = linux.ioctl(self.listener, SECCOMP.IOCTL_NOTIF.ID_VALID, @intFromPtr(&id));
        return linux.errno(rc) == .SUCCESS;
    }

    fn unresolved(self: *Call, path: []const u8, kind: []const u8) Answer {
        self.t.record(.unresolved, 0, self.pid, self.tid, path, kind);
        return .@"continue";
    }

    fn dispatch(self: *Call, sys: SYS, a: [6]u64) Answer {
        switch (builtin.cpu.arch) {
            .x86_64 => switch (sys) {
                .open, .creat => return self.note1(.open, AT_FDCWD, a[0]),
                .rename => return self.note2(.rename, AT_FDCWD, a[0], AT_FDCWD, a[1]),
                .unlink => return self.note1(.unlink, AT_FDCWD, a[0]),
                .rmdir => return self.note1(.rmdir, AT_FDCWD, a[0]),
                .mkdir => return self.note1(.mkdir, AT_FDCWD, a[0]),
                .link => return self.note2(.link, AT_FDCWD, a[0], AT_FDCWD, a[1]),
                .symlink => return self.note1(.symlink, AT_FDCWD, a[1]),
                .fork => return self.boundary(.fork),
                .vfork => return self.boundary(.spawn),
                else => {},
            },
            else => {},
        }
        return switch (sys) {
            .write, .pwrite64, .writev, .pwritev, .pwritev2, .sendfile => self.noteFd(.write, fdOf(a[0])),
            // The destination is the third argument (`ops.zig`'s wrapper reads the same one).
            .copy_file_range => self.noteFd(.write, fdOf(a[2])),
            .fsync, .fdatasync => self.noteFd(.fsync, fdOf(a[0])),
            .ftruncate => self.noteFd(.truncate, fdOf(a[0])),
            .truncate => self.note1(.truncate, AT_FDCWD, a[0]),
            .openat => self.note1(.open, fdOf(a[0]), a[1]),
            .openat2 => blk: {
                if (a[3] < 8) break :blk .@"continue";
                var how: [8]u8 = undefined;
                if (!readMem(self.tid, a[2], &how) or !self.stillValid()) break :blk .@"continue";
                const flags: u64 = std.mem.readInt(u64, &how, .little);
                if (!openIsWriteCapable(@truncate(flags))) break :blk .@"continue";
                break :blk self.note1(.open, fdOf(a[0]), a[1]);
            },
            .renameat => self.note2(.rename, fdOf(a[0]), a[1], fdOf(a[2]), a[3]),
            .renameat2 => blk: {
                // The wrapper's reading: a plain rename records as one, the two flags that make
                // it something else record nothing (the oracle refuses them by name).
                const flags: u32 = @truncate(a[4]);
                if (flags & (RENAME_EXCHANGE | RENAME_WHITEOUT) != 0) break :blk .@"continue";
                break :blk self.note2(.rename, fdOf(a[0]), a[1], fdOf(a[2]), a[3]);
            },
            .unlinkat => if (@as(u32, @truncate(a[2])) & AT_REMOVEDIR != 0)
                self.note1(.rmdir, fdOf(a[0]), a[1])
            else
                self.note1(.unlink, fdOf(a[0]), a[1]),
            .mkdirat => self.note1(.mkdir, fdOf(a[0]), a[1]),
            .linkat => blk: {
                var first: [1]u8 = undefined;
                if (!readMem(self.tid, a[1], &first) or !self.stillValid())
                    break :blk self.unresolved("", contract.unresolved_kind.unresolvable_path);
                if (first[0] == 0) {
                    var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
                    break :blk self.unresolved("", contract.unresolved_kind.withFd(&b, contract.unresolved_kind.link_by_descriptor, fdOf(a[0])));
                }
                break :blk self.note2(.link, fdOf(a[0]), a[1], fdOf(a[2]), a[3]);
            },
            .symlinkat => self.note1(.symlink, fdOf(a[1]), a[2]),
            .close => self.noteClose(fdOf(a[0])),
            .execve, .execveat => self.exec(),
            .clone => self.boundary(cloneClass(a[0])),
            .clone3 => blk: {
                var fl: [8]u8 = undefined;
                if (!readMem(self.tid, a[0], &fl)) break :blk self.boundary(.fork);
                break :blk self.boundary(cloneClass(std.mem.readInt(u64, &fl, .little)));
            },
            .setsid, .setpgid => self.boundary(.detached),
            else => .@"continue",
        };
    }

    fn boundary(self: *Call, op: contract.OpClass) Answer {
        self.t.boundary(op, self.pid, self.tid);
        return .@"continue";
    }

    /// The first `execve` of the subject is the installer becoming the operation: the image the
    /// engine announced when it took the listener. Every later one is an image change, recorded
    /// as the shim records it — `.exec` in the old image, then the new image's `shim_ready`
    /// carrying the count — written before the call runs, since nothing is told of its success.
    /// An exec that then fails leaves one announcement too many, which the account counts and
    /// no verdict reads (review).
    fn exec(self: *Call) Answer {
        if (self.pid == self.t.primary and !self.t.launched) {
            self.t.launched = true;
            return .@"continue";
        }
        self.t.boundary(.exec, self.pid, self.tid);
        self.t.announce(self.pid, self.tid);
        return .@"continue";
    }

    fn noteClose(self: *Call, fd: i32) Answer {
        if (fd < 0) return .@"continue";
        var deleted = false;
        switch (fdKind(self.tid, fd, &deleted)) {
            .non_path, .unresolvable => return .@"continue",
            .path_backed => {},
        }
        var link_deleted = false;
        const p = fdPath(&self.t.path_a, self.tid, fd, &link_deleted) orelse return .@"continue";
        if (!self.stillValid()) return .@"continue";
        return self.t.observe(.close, self.pid, self.tid, p, "");
    }

    fn noteFd(self: *Call, op: contract.OpClass, fd: i32) Answer {
        if (fd < 0) return .@"continue";
        var deleted = false;
        var b: [contract.unresolved_kind.with_fd_max]u8 = undefined;
        switch (fdKind(self.tid, fd, &deleted)) {
            .non_path => return .@"continue",
            .unresolvable => return self.unresolved("", contract.unresolved_kind.withOp(&b, contract.unresolved_kind.fd_without_path, op, fd)),
            .path_backed => {},
        }
        var link_deleted = false;
        const resolved = fdPath(&self.t.path_a, self.tid, fd, &link_deleted) orelse
            return self.unresolved("", contract.unresolved_kind.withOp(&b, contract.unresolved_kind.fd_without_path, op, fd));
        if (!self.stillValid()) return .@"continue";
        if (!self.t.inState(resolved)) return .@"continue";
        if (deleted or link_deleted)
            return self.unresolved(resolved, contract.unresolved_kind.withOp(&b, contract.unresolved_kind.unlinked_fd, op, fd));
        return self.t.observe(op, self.pid, self.tid, resolved, "");
    }

    fn note1(self: *Call, op: contract.OpClass, dirfd: i32, addr: u64) Answer {
        const raw = readCString(self.tid, addr, &self.t.raw_a) orelse
            return self.unresolved("", contract.unresolved_kind.unresolvable_path);
        var unresolvable = false;
        const resolved = self.resolveAt(&self.t.path_a, dirfd, raw, &unresolvable) orelse {
            if (unresolvable) return self.unresolved(raw, contract.unresolved_kind.unresolvable_path);
            return .@"continue";
        };
        if (!self.stillValid()) return .@"continue";
        return self.t.observe(op, self.pid, self.tid, resolved, "");
    }

    fn note2(self: *Call, op: contract.OpClass, dirfd: i32, addr: u64, adirfd: i32, aaddr: u64) Answer {
        const raw = readCString(self.tid, addr, &self.t.raw_a) orelse
            return self.unresolved("", contract.unresolved_kind.unresolvable_path);
        const araw = readCString(self.tid, aaddr, &self.t.raw_b) orelse
            return self.unresolved("", contract.unresolved_kind.unresolvable_path);
        var unresolvable = false;
        const resolved = self.resolveAt(&self.t.path_a, dirfd, raw, &unresolvable) orelse {
            if (unresolvable) return self.unresolved(raw, contract.unresolved_kind.unresolvable_path);
            return .@"continue";
        };
        const aresolved = self.resolveAt(&self.t.path_b, adirfd, araw, &unresolvable) orelse {
            if (unresolvable) return self.unresolved(araw, contract.unresolved_kind.unresolvable_path);
            return .@"continue";
        };
        if (!self.stillValid()) return .@"continue";
        return self.t.observe(op, self.pid, self.tid, resolved, aresolved);
    }

    /// The shim's `resolveAt`, reading the base from `/proc/<tid>` instead of from its own
    /// process: absolute paths normalised against `/`, `AT_FDCWD` against the task's working
    /// directory, a descriptor against what it names — a proven non-directory is not ours, a
    /// directory whose path cannot be read, or that has been unlinked inside the state
    /// directory, cannot be placed.
    fn resolveAt(self: *Call, out: []u8, dirfd: i32, p: []const u8, unresolvable: *bool) ?[]const u8 {
        unresolvable.* = false;
        if (p.len == 0) return null;
        if (p[0] == '/') return contract.normalizePath(out, "/", p) catch {
            unresolvable.* = true;
            return null;
        };
        const base = if (dirfd == AT_FDCWD) blk: {
            var lbuf: [64]u8 = undefined;
            const link = std.fmt.bufPrintZ(&lbuf, "/proc/{d}/cwd", .{self.tid}) catch {
                unresolvable.* = true;
                return null;
            };
            var deleted = false;
            const b = readLinkAt(link, &self.t.base_buf, &deleted) orelse {
                unresolvable.* = true;
                return null;
            };
            if (deleted) {
                unresolvable.* = true;
                return null;
            }
            break :blk b;
        } else blk: {
            var base_deleted = false;
            switch (fdKind(self.tid, dirfd, &base_deleted)) {
                .non_path => return null,
                .unresolvable => {
                    unresolvable.* = true;
                    return null;
                },
                .path_backed => {},
            }
            var link_deleted = false;
            const b = fdPath(&self.t.base_buf, self.tid, dirfd, &link_deleted) orelse {
                unresolvable.* = true;
                return null;
            };
            if (base_deleted or link_deleted) {
                unresolvable.* = self.t.inState(b);
                return null;
            }
            break :blk b;
        };
        return contract.normalizePath(out, base, p) catch {
            unresolvable.* = true;
            return null;
        };
    }
};

fn cloneClass(flags: u64) contract.OpClass {
    if (flags & CLONE_THREAD != 0) return .thread;
    if (flags & CLONE_VFORK != 0) return .spawn;
    return .fork;
}

/// A descriptor or `AT_FDCWD` argument, which the kernel passes sign-extended.
fn fdOf(v: u64) i32 {
    return @truncate(@as(i64, @bitCast(v)));
}

// --- reading the target ---------------------------------------------------------------------

fn tgidOf(tid: i32) ?i32 {
    var pbuf: [64]u8 = undefined;
    const p = std.fmt.bufPrintZ(&pbuf, "/proc/{d}/status", .{tid}) catch return null;
    var text: [2048]u8 = undefined;
    const t = readSmall(p, &text) orelse return null;
    const at = std.mem.indexOf(u8, t, "\nTgid:") orelse return null;
    var rest = t[at + 6 ..];
    rest = std.mem.trimStart(u8, rest, " \t");
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    return std.fmt.parseInt(i32, rest[0..end], 10) catch null;
}

fn readSmall(path: [*:0]const u8, out: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var n: usize = 0;
    while (n < out.len) {
        const r = linux.read(fd, out[n..].ptr, out.len - n);
        switch (linux.errno(r)) {
            .SUCCESS => {
                if (r == 0) break;
                n += r;
            },
            .INTR => continue,
            else => return null,
        }
    }
    return out[0..n];
}

/// Bytes of the target's memory at `addr`. False when any of them could not be read.
fn readMem(tid: i32, addr: u64, out: []u8) bool {
    var local = [_]std.posix.iovec{.{ .base = out.ptr, .len = out.len }};
    var remote = [_]std.posix.iovec_const{.{ .base = @ptrFromInt(addr), .len = out.len }};
    const rc = linux.process_vm_readv(tid, &local, &remote, 0);
    return linux.errno(rc) == .SUCCESS and rc == out.len;
}

/// A NUL-terminated string from the target, read a page at a time so a string that ends just
/// before an unmapped page is still read. Null when it cannot be read or does not end within
/// `out`.
fn readCString(tid: i32, addr: u64, out: []u8) ?[]const u8 {
    if (addr == 0) return null;
    const page: u64 = 4096;
    var have: usize = 0;
    var at = addr;
    while (have < out.len) {
        const to_page: usize = @intCast(page - (at % page));
        const want = @min(to_page, out.len - have);
        var local = [_]std.posix.iovec{.{ .base = out[have..].ptr, .len = want }};
        var remote = [_]std.posix.iovec_const{.{ .base = @ptrFromInt(at), .len = want }};
        const rc = linux.process_vm_readv(tid, &local, &remote, 0);
        if (linux.errno(rc) != .SUCCESS or rc == 0) return null;
        if (std.mem.indexOfScalar(u8, out[have .. have + rc], 0)) |z| return out[0 .. have + z];
        have += rc;
        at += rc;
    }
    return null;
}

const FdKind = enum { path_backed, non_path, unresolvable };

/// `fdKind` from the shim, asked of `/proc/<tid>/fd/<fd>` — which `statx` follows to the open
/// file, so a socket answers as a socket and an unlinked file with a link count of 0. A number
/// the task has no descriptor at is the shim's EBADF: nothing to place.
fn fdKind(tid: i32, fd: i32, deleted: *bool) FdKind {
    var pbuf: [64]u8 = undefined;
    const p = std.fmt.bufPrintZ(&pbuf, "/proc/{d}/fd/{d}", .{ tid, fd }) catch return .unresolvable;
    var sx: linux.Statx = undefined;
    const rc = linux.statx(AT_FDCWD, p.ptr, 0, .{ .TYPE = true, .NLINK = true }, &sx);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        .NOENT => return .non_path,
        else => return .unresolvable,
    }
    const m: u32 = sx.mode & linux.S.IFMT;
    if (m == linux.S.IFSOCK or m == linux.S.IFIFO or m == linux.S.IFCHR or m == linux.S.IFBLK) return .non_path;
    if (m == 0 or m == linux.S.IFLNK) return .non_path;
    if (m == linux.S.IFREG or m == linux.S.IFDIR) {
        if (sx.nlink == 0) deleted.* = true;
        return .path_backed;
    }
    return .unresolvable;
}

const deleted_suffix = " (deleted)";

fn fdPath(out: []u8, tid: i32, fd: i32, deleted: *bool) ?[]const u8 {
    var pbuf: [64]u8 = undefined;
    const p = std.fmt.bufPrintZ(&pbuf, "/proc/{d}/fd/{d}", .{ tid, fd }) catch return null;
    return readLinkAt(p, out, deleted);
}

fn readLinkAt(link: [*:0]const u8, out: []u8, deleted: *bool) ?[]const u8 {
    deleted.* = false;
    const rc = linux.readlink(link, out.ptr, out.len);
    if (linux.errno(rc) != .SUCCESS or rc == 0 or rc >= out.len) return null;
    var raw = out[0..rc];
    if (raw[0] != '/') return null;
    if (std.mem.endsWith(u8, raw, deleted_suffix)) {
        deleted.* = true;
        raw = raw[0 .. raw.len - deleted_suffix.len];
    }
    return raw;
}

// --- tests ------------------------------------------------------------------------------------

test "the filter notifies every watched call and allows the rest, on this architecture only" {
    var buf: [max_filter]SockFilter = undefined;
    const f = buildFilter(&buf);
    try std.testing.expect(f.len <= max_filter);
    try std.testing.expectEqual(SECCOMP.RET.ALLOW, f[f.len - 1].k);
    // The arch check comes first and a foreign arch jumps to ALLOW.
    try std.testing.expectEqual(off_arch, f[0].k);
    try std.testing.expectEqual(audit_arch, f[1].k);
}

test "clone's flags decide the boundary: a thread, a vfork-style spawn, or a fork" {
    try std.testing.expectEqual(contract.OpClass.thread, cloneClass(CLONE_THREAD | 0x100));
    try std.testing.expectEqual(contract.OpClass.spawn, cloneClass(CLONE_VFORK | 0x100));
    try std.testing.expectEqual(contract.OpClass.fork, cloneClass(0x11));
}

test "the write-capability predicate matches the shim's" {
    try std.testing.expect(!openIsWriteCapable(0));
    try std.testing.expect(openIsWriteCapable(1));
    try std.testing.expect(openIsWriteCapable(2));
    try std.testing.expect(openIsWriteCapable(O_CREAT));
    try std.testing.expect(openIsWriteCapable(O_TRUNC));
    try std.testing.expect(!openIsWriteCapable(0o2000)); // O_APPEND alone
}

pub fn selfExe(arena: std.mem.Allocator) ?[]const u8 {
    var buf: [contract.max_path]u8 = undefined;
    const rc = linux.readlink("/proc/self/exe", &buf, buf.len);
    if (linux.errno(rc) != .SUCCESS or rc == 0 or rc >= buf.len) return null;
    return arena.dupe(u8, buf[0..rc]) catch null;
}
