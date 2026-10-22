//! ## Why the handler can re-issue without trapping itself
//!
//! The re-issue goes through `std.os.linux.syscall6`, whose sixth argument lands in the
//! register the kernel copies into `seccomp_data.args[5]` (`x5` on aarch64, `r9` on
//! x86_64 — read from std's `syscall6`, not assumed). The thunk puts `reissue_sentinel`
//! there and the filter allows any call already carrying it. No member of the trap set
//! takes six arguments, so the register is free — asserted at comptime in `install`
//! rather than left to the next person who adds a member.
//!
//! An instruction-pointer allowlist was measured first and rejected: seccomp filters are
//! inherited across `execve` and cannot be replaced, so a filter holding the *old*
//! image's thunk address makes the new image's handler recurse until the stack is gone
//! (measured: exit 139). A `MAP_FIXED` thunk was rejected for a worse reason — it
//! silently unmaps whatever already lives at that address, which on the far side of an
//! exec is the target's own memory, and `oracle.zig` treats `mmap` as read-only so no
//! witness would see it. An argument register is address-independent, so the sentinel
//! survives exec.
//!
//! The residual is a target that itself issues one of the trapped syscalls with the
//! sentinel already in its sixth argument register. That operation would be allowed
//! uncounted. `docs/report-schema.md` discloses it; the odds are 2^-64 per call, and the
//! oracle is the net for the case where it happens anyway.
//! A filter survives `execve` and cannot be replaced; a handler does not survive it. So
//! the image an exec puts in front of this one inherits the trap set with `SIGSYS` back
//! at its default, and dies at the first trapped call — which for a set containing every
//! `openat` is `ld.so` opening the program's libraries, before any constructor has run
//! (measured: exit 159, ADR 0052 decision 1).
//!
//! Two things close that, and both are load-bearing:
//!
//!   * `open` and `openat` are trapped **only when their flags say the call can change
//!     something** — the test `common.openIsWriteCapable` applies and the oracle's
//!     `isReadOnlyOpen` mirrors. A loader opens read-only, so it never trips the filter.
//!     `openat2` is the exception and is trapped unconditionally: its flags live in a
//!     struct, and a BPF program cannot follow a pointer. The handler re-reads the struct
//!     and records nothing for a read-only one, so the ACCOUNT is the same either way —
//!     what differs is that an `openat2`-using loader would still die across an exec.
//!     glibc's uses `openat` (measured), which is why this is a note and not a wall.
//!   * `installHandler` runs from `common.init` **in every mode**, before the shim's own
//!     trace open — the first write-capable open the new image makes. A process whose own
//!     mode is `wrappers` can still be standing in front of an inherited filter, and there
//!     the handler re-issues without recording (see `onSigsys`).
//!
//! A target that blocks `SIGSYS` re-opens the hole: with the signal blocked the kernel
//! ends the process rather than queueing it. Measured, and the mitigation is to interpose
//! the libc calls that can block it — the mask-setting calls, and `sigaction` for the mask
//! another signal's handler runs under. What reaches the kernel around libc is not covered;
//! "keeping the signal deliverable" below names it.
//! `copy_file_range` and `pwritev2` are not in the set: six arguments each, so neither has
//! a free register for the sentinel. `copy_file_range`'s wrapper simply keeps recording —
//! nothing else reaches that number. `pwritev2` cannot be handled that way, because glibc
//! falls back to a trapped number on a kernel that lacks it while issuing the real thing on
//! a kernel that has it, so neither counting it in the wrapper nor silencing the wrapper is
//! correct on both. Its wrapper records `.unsupported` in this mode and the engine refuses.
//!
//! A process running under a different syscall ABI (32-bit compat) is allowed through
//! uncounted: the filter cannot read `nr` in an ABI it does not know. The oracle sees
//! those operations and the comparison refuses, which is why this mode keeps an oracle
//! rather than dropping to `--allow-unverified` (ADR).

const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");
const contract = @import("contract");
const shim_build_options = @import("shim_build_options");

const linux = std.os.linux;
const SYS = linux.SYS;

pub const reissue_sentinel: u64 = 0x51DEE7E5CA11ED01;

extern "c" fn __errno_location() *c_int;

/// The flag test exists for `open` and `openat`. `openat2` has no `flag_arg` and is
/// trapped unconditionally — its flags are inside `struct open_how`, which classic BPF
/// cannot reach — and the handler re-reads them instead.
///
/// A filter that traps every `openat` kills the
/// image an `exec` puts in front of it — the loader opens its libraries before any
/// constructor has installed a handler, and an unhandled `SIGSYS` is fatal (ADR 0052
/// decision 1, measured again on 2026-09-11: exit 159). A loader opens them read-only, so
/// trapping only the write-capable opens leaves it alone — measured the same day, same
/// box: the same exec survives with this test in the filter, and a shell that writes
/// still dies of the trap, which is what says the filter was live.
///
/// The mask is the one `common.openIsWriteCapable` applies and the oracle's
/// `isReadOnlyOpen` mirrors textually: any access mode other than `O_RDONLY`, `O_CREAT`,
/// or `O_TRUNC`.
const Trap = struct {
    sys: SYS,
    flag_arg: ?usize = null,
    flag_mask: u32 = 0,
};

const RawTrap = struct {
    nr: u32,
    flag_arg: ?usize = null,
    flag_mask: u32 = 0,
};

fn rawSet(comptime set: []const Trap) []const RawTrap {
    comptime {
        var out: [set.len]RawTrap = undefined;
        for (set, 0..) |t, i| out[i] = .{
            .nr = @intCast(@backingInt(t.sys)),
            .flag_arg = t.flag_arg,
            .flag_mask = t.flag_mask,
        };
        const frozen = out;
        return &frozen;
    }
}

const o_accmode: u32 = 0o3;
const o_creat: u32 = 0o100;
const o_trunc: u32 = 0o1000;
const write_capable_mask: u32 = o_accmode | o_creat | o_trunc;

const trapped: []const Trap = switch (builtin.cpu.arch) {
    .aarch64 => &.{
        .{ .sys = .write },     .{ .sys = .pwrite64 },  .{ .sys = .writev },
        .{ .sys = .pwritev },   .{ .sys = .sendfile },  .{ .sys = .openat, .flag_arg = 2, .flag_mask = write_capable_mask },
        .{ .sys = .openat2 },   .{ .sys = .renameat },  .{ .sys = .renameat2 },
        .{ .sys = .unlinkat },  .{ .sys = .mkdirat },   .{ .sys = .linkat },
        .{ .sys = .symlinkat }, .{ .sys = .truncate },  .{ .sys = .ftruncate },
        .{ .sys = .fsync },     .{ .sys = .fdatasync },
    },
    .x86_64 => &.{
        .{ .sys = .write },     .{ .sys = .pwrite64 },  .{ .sys = .writev },
        .{ .sys = .pwritev },   .{ .sys = .sendfile },  .{ .sys = .openat, .flag_arg = 2, .flag_mask = write_capable_mask },
        .{ .sys = .openat2 },   .{ .sys = .renameat },  .{ .sys = .renameat2 },
        .{ .sys = .unlinkat },  .{ .sys = .mkdirat },   .{ .sys = .linkat },
        .{ .sys = .symlinkat }, .{ .sys = .truncate },  .{ .sys = .ftruncate },
        .{ .sys = .fsync },     .{ .sys = .fdatasync },
        // The legacy spellings glibc still issues on this architecture (the oracle's own
        // comment on `cwd` records measuring `rename`, `unlink` and `mkdir` here).
        .{ .sys = .open, .flag_arg = 1, .flag_mask = write_capable_mask },
        .{ .sys = .creat },     .{ .sys = .rename },    .{ .sys = .unlink },
        .{ .sys = .rmdir },     .{ .sys = .mkdir },     .{ .sys = .link },
        .{ .sys = .symlink },
    },
    else => &.{},
};

/// Read by both doors: `onSigsys` records only while it is set, and
/// `common.countedAtSyscall` answers on it so that every wrapper whose syscall is in the
/// set stays silent while it is. A process standing in front of a filter it did not
/// install has it false, and there the wrappers are the ones counting.
pub var armed: bool = false;

pub const Install = enum {
    armed,
    unsupported,
    failed,
};

// Byte offsets into `ucontext_t`, MEASURED on 2026-09-07 with a C program compiled
// against each platform's own <ucontext.h> and run on that platform, not derived from
// the struct definitions:
//
//   aarch64  sizeof=4560  uc_mcontext=176  +regs=8   -> regs[0]=184  regs[8]=248
//   x86_64   sizeof=968   uc_mcontext=40   +gregs=0  -> gregs[0]=40   RAX(13)=144
//
// Deriving them was tried first and got aarch64 wrong by 8 bytes: `struct sigcontext`
// carries a 16-aligned member, so `uc_mcontext` is padded from 168 to 176. A wrong
// offset here reads a neighbouring field as a file descriptor.
/// Byte offset of `si_syscall` inside `siginfo_t`, MEASURED the same way the register
/// offsets below were and found IDENTICAL on both platforms (2026-09-07):
///
///   aarch64  sizeof(siginfo_t)=128  si_call_addr=16  si_syscall=24  si_arch=28
///   x86_64   sizeof(siginfo_t)=128  si_call_addr=16  si_syscall=24  si_arch=28
const si_syscall_off: usize = 24;

/// **The handler must test this before it reads anything else**, and the reason is
/// specific rather than defensive. MEASURED the same way, on both platforms
/// (2026-09-11): `si_code` is at 8, `si_syscall` at 24 — and `si_value` is at 24 **too**.
/// `sigqueue(pid, SIGSYS, value)` therefore puts a number of the sender's choosing exactly
/// where this handler would read a syscall number, and the handler executes what it reads.
/// `kill(pid, SIGSYS)` lands a zero there, which on x86-64 is `read`. Neither is a trap of
/// ours and neither may be re-issued (review, P0).
const si_code_off: usize = 8;
const sys_seccomp: i32 = 1;

const Layout = struct {
    args: [6]usize,
    ret: usize,
};

const layout: ?Layout = switch (builtin.cpu.arch) {
    // x0..x5 are the arguments, x0 the result.
    .aarch64 => .{
        .args = .{ 184, 192, 200, 208, 216, 224 },
        .ret = 184,
    },
    // rdi, rsi, rdx, r10, r8, r9 are the arguments; rax is the result.
    // Indices from the platform's own <sys/ucontext.h>: RDI=8 RSI=9 RDX=12 R10=2
    // R8=0 R9=1 RAX=13, each 8 bytes wide from gregs[0] at 40.
    .x86_64 => .{
        .args = .{ 104, 112, 136, 56, 40, 48 },
        .ret = 144,
    },
    else => null,
};

fn regPtr(uc: *anyopaque, off: usize) *u64 {
    const base: [*]u8 = @ptrCast(uc);
    return @ptrCast(@alignCast(base + off));
}

const SockFilter = extern struct { code: u16, jt: u8, jf: u8, k: u32 };
const SockFprog = extern struct { len: u16, filter: [*]const SockFilter };

const BPF_LD_W_ABS: u16 = 0x20;
const BPF_JEQ_K: u16 = 0x15;
const BPF_RET_K: u16 = 0x06;
/// `BPF_JMP | BPF_JA`: the unconditional forward jump. Needed once the program has a
/// block per member — a member's block has to reach the shared tail, and seccomp's jumps
/// only go forward, so the tail is where ALLOW and TRAP live.
const BPF_JA: u16 = 0x05;
const BPF_AND_K: u16 = 0x54;

const data_off = struct {
    const nr: u32 = @offsetOf(linux.SECCOMP.data, "nr");
    const arch: u32 = @offsetOf(linux.SECCOMP.data, "arch");
    const arg5_lo: u32 = @offsetOf(linux.SECCOMP.data, "arg5");
    const arg5_hi: u32 = arg5_lo + 4;
    /// The low word of the nth argument. Only the low word is read: every flag this
    /// filter tests lives in the bottom 32 bits of its argument.
    const args_lo = [6]u32{
        @offsetOf(linux.SECCOMP.data, "arg0"),
        @offsetOf(linux.SECCOMP.data, "arg1"),
        @offsetOf(linux.SECCOMP.data, "arg2"),
        @offsetOf(linux.SECCOMP.data, "arg3"),
        @offsetOf(linux.SECCOMP.data, "arg4"),
        @offsetOf(linux.SECCOMP.data, "arg5"),
    };
};

const audit_64bit: u32 = 0x8000_0000;
const audit_le: u32 = 0x4000_0000;

const audit_arch: u32 = switch (builtin.cpu.arch) {
    .aarch64 => @backingInt(std.elf.EM.AARCH64) | audit_64bit | audit_le,
    .x86_64 => @backingInt(std.elf.EM.X86_64) | audit_64bit | audit_le,
    else => 0,
};

fn programLen(comptime set: []const RawTrap) usize {
    var n: usize = 3 + set.len + 1;
    for (set) |t| n += if (t.flag_arg != null) 4 else 1;
    return n + 4 + 2;
}

fn buildProgram(comptime arch_id: u32, comptime set: []const RawTrap) [programLen(set)]SockFilter {
    @setEvalBranchQuota(10000);
    const n = set.len;
    var insns: [programLen(set)]SockFilter = undefined;

    var block_at: [set.len]usize = undefined;
    var next = 3 + n + 1;
    for (set, 0..) |t, i| {
        block_at[i] = next;
        next += if (t.flag_arg != null) 4 else 1;
    }
    const sent = next; // the sentinel check
    const trap_i = sent + 4;
    const allow_i = trap_i + 1;

    insns[0] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arch };
    insns[1] = .{ .code = BPF_JEQ_K, .jt = 0, .jf = @intCast(allow_i - 1 - 1), .k = arch_id };
    insns[2] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.nr };
    for (set, 0..) |t, i| {
        const here = 3 + i;
        insns[here] = .{
            .code = BPF_JEQ_K,
            .jt = @intCast(block_at[i] - here - 1),
            .jf = 0,
            .k = t.nr,
        };
    }
    insns[3 + n] = .{ .code = BPF_JA, .jt = 0, .jf = 0, .k = @intCast(allow_i - (3 + n) - 1) };

    for (set, 0..) |t, i| {
        const b = block_at[i];
        if (t.flag_arg) |arg| {
            insns[b] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.args_lo[arg] };
            insns[b + 1] = .{ .code = BPF_AND_K, .jt = 0, .jf = 0, .k = t.flag_mask };
            insns[b + 2] = .{ .code = BPF_JEQ_K, .jt = @intCast(allow_i - (b + 2) - 1), .jf = 0, .k = 0 };
            insns[b + 3] = .{ .code = BPF_JA, .jt = 0, .jf = 0, .k = @intCast(sent - (b + 3) - 1) };
        } else {
            insns[b] = .{ .code = BPF_JA, .jt = 0, .jf = 0, .k = @intCast(sent - b - 1) };
        }
    }

    insns[sent] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arg5_lo };
    insns[sent + 1] = .{
        .code = BPF_JEQ_K,
        .jt = 0,
        .jf = @intCast(trap_i - (sent + 1) - 1),
        .k = @truncate(reissue_sentinel),
    };
    insns[sent + 2] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arg5_hi };
    insns[sent + 3] = .{
        .code = BPF_JEQ_K,
        .jt = @intCast(allow_i - (sent + 3) - 1),
        .jf = 0,
        .k = @truncate(reissue_sentinel >> 32),
    };
    insns[trap_i] = .{ .code = BPF_RET_K, .jt = 0, .jf = 0, .k = linux.SECCOMP.RET.TRAP };
    insns[allow_i] = .{ .code = BPF_RET_K, .jt = 0, .jf = 0, .k = linux.SECCOMP.RET.ALLOW };
    return insns;
}

const trapped_raw: []const RawTrap = rawSet(trapped);

const program = buildProgram(audit_arch, trapped_raw);

pub fn thunk(nr: u32, a0: u64, a1: u64, a2: u64, a3: u64, a4: u64) u64 {
    const r = linux.syscall6(@fromBackingInt(@intCast(nr)), a0, a1, a2, a3, a4, reissue_sentinel);
    // Clear the marker register before returning, or the NEXT syscall inherits it.
    //
    // This is not tidiness. The sixth argument register is caller-saved and nothing in
    // the C calling convention sets it for a three-argument call, so after this function
    // returns it still holds the marker — and the very next `write(2)` libc issues, with
    // no sixth argument of its own, arrives at the filter carrying it and is ALLOWED.
    // The shim's own trace writes go through this thunk, so that sequence is not rare: a
    // record is written, and the write it was recording about is then invisible.
    //
    // A separate `volatile` statement rather than one asm block: the register is an
    // input to `syscall6` above, and an operand that is also clobbered is not
    // expressible. Nothing between the two can issue a syscall — this function returns
    // immediately — and any value other than the marker is correct, so a compiler that
    // clobbers the register in between does the same job.
    switch (builtin.cpu.arch) {
        .aarch64 => asm volatile ("mov x5, xzr" ::: .{ .x5 = true }),
        .x86_64 => asm volatile ("xorq %%r9, %%r9" ::: .{ .r9 = true }),
        else => {},
    }
    return r;
}

/// The trace channel cannot go through libc's `write` in this mode: that syscall traps,
/// the handler records, and recording writes another record — recursion that ends in a
/// stack overflow rather than a refusal. This is the one call the sentinel exists for
/// besides the re-issue.
pub fn traceWrite(fd: i32, buf: [*]const u8, n: usize) isize {
    const r = thunk(@backingInt(SYS.write), @bitCast(@as(i64, fd)), @intFromPtr(buf), n, 0, 0);
    const signed: i64 = @bitCast(r);
    return @intCast(signed);
}

/// Called by `common.init()` before `active` is set, so nothing is recorded through a
/// half-installed filter.
///
/// Order matters and is not negotiable: the handler has to exist before the filter, or
/// the first trapped write kills the process with an unhandled `SIGSYS`; and
/// `PR_SET_NO_NEW_PRIVS` has to be set before `SET_MODE_FILTER`, which the kernel
/// otherwise refuses with `EACCES` for an unprivileged caller.
/// The handler, and nothing else — installed first thing in `init`, before anything this
/// library does that a filter could trap, and whatever mode this process is in.
///
/// A filter survives `execve`; a handler does not. So the image an exec puts in front of
/// this one inherits the trap set with `SIGSYS` back at its default, and its own
/// constructor then opens the trace file for writing — which the widened set traps.
/// Measured on 2026-09-11 in a preload probe of this design: with the handler installed
/// after that open, the `cat` an `sh -c` exec'd died of `SIGSYS` (exit 159); with it
/// installed first, both survived. That is why this is its own call, made before the
/// open, in every mode: a process whose own mode is `wrappers` can still be standing in
/// front of an inherited filter.
pub fn installHandler() void {
    if (builtin.os.tag != .linux) return;
    if (layout == null) return;

    var sa: linux.Sigaction = .{
        .handler = .{ .sigaction = onSigsys },
        .mask = linux.sigemptyset(),
        // `SA.ONSTACK` because a Go target's goroutine stacks are small and its threads
        // carry an alternate signal stack for exactly this; without it the handler runs on
        // whatever stack the trapped call was made from. A thread with no alternate stack
        // is unaffected — the flag then means nothing, and the handler runs where it would
        // have run anyway.
        .flags = linux.SA.SIGINFO | linux.SA.ONSTACK,
    };
    // Deliberately without `SA.NODEFER`. A nested trap means an assumption here is
    // wrong — and with SIGSYS blocked the kernel ends the process, which the engine
    // reads as a run that did not complete. Allowing re-entry instead would recurse
    // quietly, which is the worse of the two.
    // What makes it safe is not absence: the shim's trace channel goes through
    // `traceWrite`, which carries the re-issue sentinel, so the filter allows it. Nothing
    // else the handler reaches is in the set, and the trace write is in it but marked.
    _ = linux.sigaction(.SYS, &sa, null);
}

pub fn install() Install {
    // The acceptance apparatus (`-Dtest-observe-fail`). The engine's refusal on an
    // announcement that does not say `armed` is unreachable otherwise: every machine the
    // suite runs on installs the filter, so without a shim that reports failure the check
    // is a guard nothing has ever falsified. A separately named artifact that plain
    // `zig build` never produces, the way `libsideeye_shim_testgap` is.
    if (shim_build_options.test_observe_fail) return .failed;
    if (builtin.os.tag != .linux) return .unsupported;
    if (layout == null) return .unsupported;

    comptime {
        // The sentinel's register is only free because nothing here uses it. A
        // six-argument member would take it and the filter would compare against the
        // member's own flags — which is why `copy_file_range` and `pwritev2` are not in
        // the set at all. Every name below was read off its own man page for the count;
        // the arm exists so a new member cannot join without someone doing that.
        for (trapped) |t| switch (t.sys) {
            .write,
            .pwrite64,
            .writev,
            .pwritev,
            .sendfile,
            .openat,
            .openat2,
            .renameat,
            .renameat2,
            .unlinkat,
            .mkdirat,
            .linkat,
            .symlinkat,
            .truncate,
            .ftruncate,
            .fsync,
            .fdatasync,
            => {},
            else => switch (builtin.cpu.arch) {
                .x86_64 => switch (t.sys) {
                    .open, .creat, .rename, .unlink, .rmdir, .mkdir, .link, .symlink => {},
                    else => @compileError("a trapped syscall must take at most five arguments: " ++
                        @tagName(t.sys) ++ " has to be checked before it joins the set"),
                },
                else => @compileError("a trapped syscall must take at most five arguments: " ++
                    @tagName(t.sys) ++ " has to be checked before it joins the set"),
            },
        };
    }

    installHandler();

    if (linux.prctl(@backingInt(linux.PR.SET_NO_NEW_PRIVS), 1, 0, 0, 0) != 0) return .failed;

    // `SECCOMP_FILTER_FLAG_TSYNC` since #753. This runs from the library constructor, and a
    // filter is inherited by every thread `clone` makes afterwards — but a thread can exist
    // before it: another library's constructor, run first, starts a pool, and since #753 its
    // `pthread_create` succeeds. Without the flag such a thread had no filter, while
    // `syscalls.armed` (process-wide) kept the wrappers silent for it, so its writes reached the
    // state through neither door. With it the kernel puts every thread under this filter, and
    // their no_new_privs with it, or answers with the id of one it cannot — which is a failure
    // here, not a success: only 0 means every thread took the filter.
    const prog: SockFprog = .{ .len = @intCast(program.len), .filter = &program };
    const rc = linux.syscall3(
        .seccomp,
        linux.SECCOMP.SET_MODE_FILTER,
        linux.SECCOMP.FILTER_FLAG.TSYNC,
        @intFromPtr(&prog),
    );
    if (rc != 0) return .failed;

    armed = true;
    return .armed;
}

// --- keeping the signal deliverable --------------------------------------------------
//
// A trap the target never receives ends the run. With `SIGSYS` back at its default the
// kernel kills the process; with `SIGSYS` BLOCKED it kills it too — the kernel resets the
// disposition rather than queueing a signal it forced (measured 2026-09-11,
// `go542/blocked.c`: the handler installed, the signal blocked, exit 159 all the same).
//
// A target closes both doors in the ordinary course of running, and the one this change
// exists for closes both. Go installs its own `SIGSYS` handler through libc `sigaction`
// (measured: a query, then a set with `SA_ONSTACK`), and mlr touches the signal through
// libc `pthread_sigmask` five times in one run while completing normally. So the four
// entry points below are interposed to keep the signal deliverable: each accepts the
// caller's request, answers success, and declines only the part that would take `SIGSYS`
// away.
//
// A handler for ANOTHER signal is a third way to block it. The kernel adds the handler's
// `sa_mask` to the blocked set for as long as the handler runs, so a handler installed
// with every signal in that mask — libuv installs its handlers that way — holds `SIGSYS`
// blocked while it runs, and a trapped call inside it ends the process (measured
// 2026-09-13 on main: a `SIGUSR1` handler installed with `sigfillset` died of signal 31 at
// its first trapped write, and node 20 was refused `recording_run_failed` for a
// `process.on('SIGUSR2')` handler that wrote a file). So `sigaction` also takes `SIGSYS`
// out of the `sa_mask` of a request for any other signal, and changes nothing else in it.
//
// They are installed in EVERY mode, like `installHandler` and for the same reason: a
// filter is inherited across `exec` and a process whose own mode is `wrappers` can be
// standing in front of one. Where no filter exists anywhere they change nothing a target
// can observe — nothing raises `SIGSYS`, and every query still reports the truth.
//
// The residual is every change to the signal state that does not reach these four symbols
// while `guard_signal` is set: `rt_sigaction` and `rt_sigprocmask` issued directly (a
// statically linked Go binary, a Go child between fork and exec), the C library's own
// internal calls and its other signal functions — glibc's `posix_spawn` child blocks every
// signal while a file action opens for writing, and dies of signal 31 (measured) — a mask
// given for the length of one call (`ppoll`, `sigsuspend`), a signal whose handler runs
// while this file's own handler does, which holds `SIGSYS` blocked, and the processes the
// flag is not set in: before `common.init` reaches `armGuards`, and a child that kept the
// shim but lost the state or observe variables. Arming clears nothing already in place,
// and `install` does not unblock a mask carried across `exec`. Trapping `rt_sigaction` and
// `rt_sigprocmask` in the filter is the step this comment used to propose; measured, it
// kills targets that run today, and ADR 0063 records why it was not taken.

/// Whether the four wrappers below actually decline anything, set by `common.init` when
/// this process's mode is `syscalls` — before the filter goes up, because a trap can
/// arrive the instant it does.
///
/// Unlike `installHandler`, which runs in every mode because a handler nothing raises is
/// unobservable, keeping a signal OUT of a blocked set is a change the target can see: a
/// critical section that blocks every signal would come back with one missing. So the
/// default mode declines nothing.
///
/// It is not untouched, and this flag is not what makes the difference: the four symbols
/// are exported in every mode, because a symbol cannot be exported conditionally, so a
/// default-mode target forwards its calls through these wrappers either way. `resolveGuards`
/// is what keeps that forward cheap and safe.
///
/// It is the MODE and not `armed`, deliberately. A process whose `install` failed while
/// its parent's filter was inherited has `armed` false and needs the guards most; its
/// mode is still `syscalls`, so this is the flag that covers it.
///
/// For the same reason it is **not lowered when `install` returns `.failed`**, although
/// review asked for exactly that and it would be one line. A failure is the case where an
/// inherited filter is most likely to be live — the likeliest way for `seccomp` to refuse
/// a second filter is that the stack of inherited ones has reached the kernel's limit —
/// and lowering the flag there would take the guards away at the one moment they are
/// holding the process up. What it costs in the other case, a process with no filter at
/// all, is a target whose `SIGSYS` requests are declined for the life of a run the engine
/// is already going to refuse on its announcement (`observe:syscalls-failed`), so nothing
/// is judged under it.
///
/// `armGuards` and not a plain assignment, because `installHandler` declines on an
/// architecture whose trap frame this file does not know — and there, declining the
/// target's `sigaction` as well would take its handler away and put nothing in its place,
/// leaving `SIGSYS` at the default that kills (review, P1). The two decisions are one.
pub var guard_signal: bool = false;

pub fn armGuards() void {
    guard_signal = builtin.os.tag == .linux and layout != null;
}

const sigsys_no: c_int = @backingInt(linux.SIG.SYS);

const SigactionFn = *const fn (c_int, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int;
const SignalFn = *const fn (c_int, ?*const anyopaque) callconv(.c) ?*const anyopaque;
const MaskFn = *const fn (c_int, ?*const anyopaque, ?*anyopaque) callconv(.c) c_int;

var real_sigaction: Resolved(SigactionFn) = .unresolved;
var real_signal: Resolved(SignalFn) = .unresolved;
var real_sigprocmask: Resolved(MaskFn) = .unresolved;
var real_pthread_sigmask: Resolved(MaskFn) = .unresolved;

/// Resolve all four, from `common.init`, before the target can reach any of them.
///
/// The lazy form is still there below and is still needed — these symbols are exported
/// from the moment the library is loaded, so another preloaded library's constructor
/// calling `sigaction` arrives before this shim's own constructor does — but it must not
/// be the ordinary path. **`dlsym` is not async-signal-safe and `signal`/`sigprocmask`
/// are**: a target calling one of those from inside a signal handler would have met the
/// loader's lock here and could have deadlocked on it, in a process that had never asked
/// for `--observe syscalls` (review, P1). After this runs the wrappers do a load and a
/// null test, which is what a forwarding wrapper costs and no more.
pub fn resolveGuards() void {
    if (builtin.os.tag != .linux) return;
    _ = nextSymbol(SigactionFn, "sigaction", &real_sigaction);
    _ = nextSymbol(SignalFn, "signal", &real_signal);
    _ = nextSymbol(MaskFn, "sigprocmask", &real_sigprocmask);
    _ = nextSymbol(MaskFn, "pthread_sigmask", &real_pthread_sigmask);
}

/// One symbol, memoised. Reached from `resolveGuards` at startup and — only in the window
/// before it runs — from a wrapper. Two threads racing write the same pointer.
fn nextSymbol(comptime T: type, name: [*:0]const u8, slot: *Resolved(T)) ?T {
    switch (slot.*) {
        .unresolved => {},
        .missing => return null,
        .found => |f| return f,
    }
    const p = common.c.dlsym(common.rtld_next, name) orelse {
        slot.* = .missing;
        return null;
    };
    const f: T = @ptrCast(@alignCast(p));
    slot.* = .{ .found = f };
    return f;
}

fn Resolved(comptime T: type) type {
    return union(enum) { unresolved, missing, found: T };
}

/// `SIGSYS` is blocked on this thread between the two calls. Nothing can trap in that
/// gap: the thread is inside these two calls, and neither the library function nor
/// `rt_sigprocmask` is in the trap set.
fn unblockSigsys() void {
    var set = linux.sigemptyset();
    linux.sigaddset(&set, .SYS);
    _ = linux.sigprocmask(linux.SIG.UNBLOCK, &set, null);
}

comptime {
    if (layout != null and (@sizeOf(std.c.Sigaction) != 152 or
        @offsetOf(std.c.Sigaction, "mask") != 8 or @sizeOf(std.c.sigset_t) != 128 or
        @offsetOf(std.c.Sigaction, "flags") != 136))
        @compileError("std.c.Sigaction is no longer glibc's measured struct sigaction");
}

const sigsys_word: usize = @intCast(@divTrunc(sigsys_no - 1, @bitSizeOf(c_ulong)));
const sigsys_bit: c_ulong = @as(c_ulong, 1) << @intCast(@mod(sigsys_no - 1, @bitSizeOf(c_ulong)));

/// Copied byte for byte rather than cast: the caller's struct has whatever alignment the
/// caller gave it, and the caller's own struct is never written.
fn withoutSigsys(act: *const anyopaque) ?std.c.Sigaction {
    var copy: std.c.Sigaction = undefined;
    @memcpy(std.mem.asBytes(&copy), @as([*]const u8, @ptrCast(act)));
    if (copy.mask[sigsys_word] & sigsys_bit == 0) return null;
    copy.mask[sigsys_word] &= ~sigsys_bit;
    return copy;
}

/// The copy lives in this frame, never on the heap: `sigaction` may be called from a
/// signal handler. `oldact` is still the library's answer, so a target that later queries
/// a handler installed this way reads its mask back without `SIGSYS`.
pub fn sigaction(signum: c_int, act: ?*const anyopaque, oldact: ?*anyopaque) callconv(.c) c_int {
    const f = nextSymbol(SigactionFn, "sigaction", &real_sigaction) orelse return -1;
    if (!guard_signal or act == null) return f(signum, act, oldact);
    if (signum != sigsys_no) {
        const trimmed = withoutSigsys(act.?) orelse return f(signum, act, oldact);
        return f(signum, &trimmed, oldact);
    }
    // The query half is answered by the library, so `oldact` describes the handler that
    // is really installed — including the `SA_SIGINFO` flag that says how to call it, for
    // a caller that means to chain. Only the set half is dropped.
    if (oldact) |o| _ = f(signum, null, o);
    return 0;
}

pub fn signal(signum: c_int, handler: ?*const anyopaque) callconv(.c) ?*const anyopaque {
    const f = nextSymbol(SignalFn, "signal", &real_signal) orelse
        return @ptrFromInt(std.math.maxInt(usize)); // SIG_ERR
    if (!guard_signal or signum != sigsys_no) return f(signum, handler);
    // `SIG_DFL` — what the target would have found here in a run without this shim, and
    // the only safe answer in this shape. The truthful one is not available: `signal`
    // returns a bare function pointer with no flag word beside it, and the handler really
    // installed takes three arguments, so a caller invoking the returned pointer the way
    // `signal` promises would read two arguments nobody pushed.
    return null;
}

fn maskGuard(f_opt: ?MaskFn, how: c_int, set: ?*const anyopaque, oldset: ?*anyopaque) c_int {
    const f = f_opt orelse return -1;
    const rc = f(how, set, oldset);
    // Only a request that could have added `SIGSYS`, and only one the library accepted:
    // undoing a refused call would change a mask the caller still believes it has.
    // `sigprocmask` reports failure as -1 and `pthread_sigmask` as a positive errno, so
    // the test is for success rather than against a value.
    if (guard_signal and rc == 0 and set != null and how != linux.SIG.UNBLOCK) unblockSigsys();
    return rc;
}

pub fn sigprocmask(how: c_int, set: ?*const anyopaque, oldset: ?*anyopaque) callconv(.c) c_int {
    return maskGuard(nextSymbol(MaskFn, "sigprocmask", &real_sigprocmask), how, set, oldset);
}

pub fn pthread_sigmask(how: c_int, set: ?*const anyopaque, oldset: ?*anyopaque) callconv(.c) c_int {
    return maskGuard(nextSymbol(MaskFn, "pthread_sigmask", &real_pthread_sigmask), how, set, oldset);
}

fn pathOf(v: u64) [*:0]const u8 {
    return @ptrFromInt(v);
}

fn fdOf(v: u64) c_int {
    return @truncate(@as(i64, @bitCast(v)));
}

/// What a trapped call records. Every arm mirrors the wrapper in `ops.zig` that records
/// the same call — the same class, the same scope, the same special cases — because the
/// two are doors into one account and a target may arrive through either. An arm that
/// drifts from its wrapper shows up as an oracle divergence, not as a wrong class.
///
/// The open family arrives here only when the filter's flag test admitted it (a
/// write-capable open), so no arm re-tests the flags — except `openat2`, whose flags live
/// in a struct the filter cannot read.
fn record(nr: u32, a: [6]u64) void {
    const sys: SYS = @fromBackingInt(@intCast(nr));
    switch (builtin.cpu.arch) {
        .x86_64 => switch (sys) {
            .open, .creat => common.note1FromTrap(.open, common.AT_FDCWD, pathOf(a[0])),
            .rename => common.note2FromTrap(.rename, common.AT_FDCWD, pathOf(a[0]), common.AT_FDCWD, pathOf(a[1])),
            .unlink => common.note1FromTrap(.unlink, common.AT_FDCWD, pathOf(a[0])),
            .rmdir => common.note1FromTrap(.rmdir, common.AT_FDCWD, pathOf(a[0])),
            .mkdir => common.note1FromTrap(.mkdir, common.AT_FDCWD, pathOf(a[0])),
            .link => common.note2FromTrap(.link, common.AT_FDCWD, pathOf(a[0]), common.AT_FDCWD, pathOf(a[1])),
            // Only the link path is the operation's address (contract v9): the target
            // string is content the subject chose.
            .symlink => common.note1FromTrap(.symlink, common.AT_FDCWD, pathOf(a[1])),
            else => recordPortable(sys, a),
        },
        else => recordPortable(sys, a),
    }
}

fn recordPortable(sys: SYS, a: [6]u64) void {
    switch (sys) {
        // The descriptor is the first argument of each: for `sendfile` that is `out_fd`,
        // the one being written (`ops.zig` reads the same argument).
        .write, .pwrite64, .writev, .pwritev, .sendfile => common.noteFdFromTrap(.write, fdOf(a[0])),
        .fsync, .fdatasync => common.noteFdFromTrap(.fsync, fdOf(a[0])),
        .ftruncate => common.noteFdFromTrap(.truncate, fdOf(a[0])),
        .truncate => common.note1FromTrap(.truncate, common.AT_FDCWD, pathOf(a[0])),
        .openat => common.note1FromTrap(.open, fdOf(a[0]), pathOf(a[1])),
        .openat2 => {
            // `struct open_how`'s first field is the flags, and `a[3]` is the size the
            // caller passed. A struct too short to hold them is a call the kernel will
            // refuse anyway, and nothing is recorded for it.
            if (a[3] >= 8) {
                const p: [*]const u8 = @ptrFromInt(a[2]);
                const flags: u64 = std.mem.readInt(u64, p[0..8], .little);
                if (common.openIsWriteCapable(@bitCast(@as(u32, @truncate(flags)))))
                    common.note1FromTrap(.open, fdOf(a[0]), pathOf(a[1]));
            }
        },
        .renameat => common.note2FromTrap(.rename, fdOf(a[0]), pathOf(a[1]), fdOf(a[2]), pathOf(a[3])),
        .renameat2 => {
            // The wrapper's reading exactly (#256): a plain rename records as one, and the
            // two flags that make it something else record NOTHING. An earlier version of
            // this arm recorded `.unsupported` for those two, which is arguably the better
            // answer — it refuses without needing an oracle — but it is not the wrapper's,
            // and a target's account would then depend on which mode observed it. The two
            // doors agree or the promise that both modes reach the same verdict is false
            // (review, P2). The oracle refuses these by flag name in either mode.
            const flags: c_int = @bitCast(@as(u32, @truncate(a[4])));
            if (flags & (common.RENAME_EXCHANGE | common.RENAME_WHITEOUT) == 0)
                common.note2FromTrap(.rename, fdOf(a[0]), pathOf(a[1]), fdOf(a[2]), pathOf(a[3]));
        },
        .unlinkat => {
            const flags: c_int = @bitCast(@as(u32, @truncate(a[2])));
            if (flags & common.AT_REMOVEDIR != 0)
                common.note1FromTrap(.rmdir, fdOf(a[0]), pathOf(a[1]))
            else
                common.note1FromTrap(.unlink, fdOf(a[0]), pathOf(a[1]));
        },
        .mkdirat => common.note1FromTrap(.mkdir, fdOf(a[0]), pathOf(a[1])),
        .linkat => {
            // `AT_EMPTY_PATH` links the descriptor itself; the old path names nothing to
            // resolve, so the operation is recorded as unplaceable, as the wrapper does.
            const old = pathOf(a[1]);
            if (old[0] == 0)
                common.noteLinkByDescriptorFromTrap(fdOf(a[0]))
            else
                common.note2FromTrap(.link, fdOf(a[0]), old, fdOf(a[2]), pathOf(a[3]));
        },
        .symlinkat => common.note1FromTrap(.symlink, fdOf(a[1]), pathOf(a[2])),
        // A number the filter trapped and this switch does not know is a set and a
        // dispatch that have drifted apart. Recording nothing is the fail-closed half:
        // the oracle sees the call and the comparison refuses.
        else => {},
    }
}

// Not written inside onSigsys: a Debug build gives every local of a function its slot in the
// one frame, so this rare branch's sigaction and signal set would sit on the target thread's
// stack at every trap.
fn reraiseAtDefault() void {
    var dfl: linux.Sigaction = .{
        .handler = .{ .handler = linux.SIG.DFL },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    _ = linux.sigaction(.SYS, &dfl, null);
    var set = linux.sigemptyset();
    linux.sigaddset(&set, .SYS);
    _ = linux.sigprocmask(linux.SIG.UNBLOCK, &set, null);
    _ = linux.kill(linux.getpid(), .SYS);
}

fn onSigsys(_: linux.SIG, info: *const linux.siginfo_t, uc_opaque: ?*anyopaque) callconv(.c) void {
    const l = layout orelse return;
    const uc = uc_opaque orelse return;

    const info_bytes: [*]const u8 = @ptrCast(info);

    // Ours, or somebody else's? Only a seccomp trap carries a syscall number in this
    // `siginfo_t`, and only a seccomp trap is a call this handler may re-issue. Anything
    // else — `kill`, `raise`, `sigqueue` — is the target's own signal arriving at a
    // handler the target did not ask for, and the sender chooses what sits where the
    // number would be (see `si_code_off`).
    //
    // What to do with it is not "return": returning swallows a signal the process would
    // have died from, which is a change to the target as surely as executing the wrong
    // syscall is. So the disposition goes back to the default and the signal is raised
    // again — what would have happened with no shim loaded. The handler is gone
    // afterwards, which costs nothing: the process is on its way out. One place
    // this does not hold: a pid namespace's init (PID 1) ignores a signal it has no
    // handler for, so there the `kill` below is discarded and execution resumes with the
    // disposition left at the default — and under `--observe syscalls` the next trap ends
    // the process instead.
    const code = std.mem.readInt(i32, info_bytes[si_code_off..][0..4], .little);
    if (code != sys_seccomp) return reraiseAtDefault();

    const nr: u32 = @bitCast(std.mem.readInt(i32, info_bytes[si_syscall_off..][0..4], .little));
    var a: [6]u64 = undefined;
    for (l.args, 0..) |off, i| a[i] = regPtr(uc, off).*;

    // `errno` belongs to the target, and `noteFd` reaches `statx` and `readlinkat` through
    // the C library, both of which write it. The libc wrapper the target called sets it
    // only when the syscall FAILS, so on the ordinary success path a clobbered value would
    // simply stay there and be visible to a caller that reads it afterwards (review, P2).
    // Only our own filter's traps are ours to count. A process standing in front of a
    // filter it inherited without installing one — an exec that dropped the environment,
    // or somebody else's sandbox — still needs the call re-issued so that it survives,
    // but there the wrappers are the ones counting (`countedAtSyscall` answers on
    // the same flag), and recording here as well would count the operation twice.
    if (armed) {
        const errno_slot = __errno_location();
        const saved_errno = errno_slot.*;
        record(nr, a);
        errno_slot.* = saved_errno;
    }

    regPtr(uc, l.ret).* = thunk(nr, a[0], a[1], a[2], a[3], a[4]);
}

fn simulate(prog: []const SockFilter, d: linux.SECCOMP.data) u32 {
    const bytes: [*]const u8 = @ptrCast(&d);
    var acc: u32 = 0;
    var pc: usize = 0;
    var steps: usize = 0;
    while (steps < 128) : (steps += 1) {
        const in = prog[pc];
        switch (in.code) {
            BPF_LD_W_ABS => {
                acc = std.mem.readInt(u32, bytes[in.k..][0..4], .little);
                pc += 1;
            },
            BPF_JEQ_K => {
                pc += 1 + @as(usize, if (acc == in.k) in.jt else in.jf);
            },
            BPF_JA => pc += 1 + in.k,
            BPF_AND_K => {
                acc &= in.k;
                pc += 1;
            },
            BPF_RET_K => return in.k,
            else => unreachable,
        }
    }
    unreachable; // a program that neither returns nor terminates would hang the kernel
}

const test_arch: u32 = 0xC000_003E; // AUDIT_ARCH_X86_64, chosen so the test is host-independent
const test_set = [_]RawTrap{
    .{ .nr = 1 },
    .{ .nr = 18 },
    .{ .nr = 20 },
    .{ .nr = 296 },
    .{ .nr = 257, .flag_arg = 2, .flag_mask = write_capable_mask },
};

fn frame(nr: i32, arch: u32, arg5: u64) linux.SECCOMP.data {
    return frameFlags(nr, arch, 0, arg5);
}

/// A frame whose flags sit in the argument this member's test reads — `openat`'s third,
/// the legacy `open`'s second. Putting them always in the third is a test that says a
/// member is trapped when the filter never looked at what it set (caught here, red).
fn frameFor(t: RawTrap, arch: u32, flags: u64, arg5: u64) linux.SECCOMP.data {
    var d = frame(@intCast(t.nr), arch, arg5);
    if (t.flag_arg) |i| switch (i) {
        0 => d.arg0 = flags,
        1 => d.arg1 = flags,
        2 => d.arg2 = flags,
        3 => d.arg3 = flags,
        4 => d.arg4 = flags,
        else => unreachable,
    };
    return d;
}

fn frameFlags(nr: i32, arch: u32, arg2: u64, arg5: u64) linux.SECCOMP.data {
    return .{
        .nr = nr,
        .arch = arch,
        .instruction_pointer = 0,
        .arg0 = 3,
        .arg1 = 0,
        .arg2 = arg2,
        .arg3 = 0,
        .arg4 = 0,
        .arg5 = arg5,
    };
}

test "the filter traps an unmarked write and allows the handler's re-issue" {
    const prog = buildProgram(test_arch, &test_set);
    const T = linux.SECCOMP.RET.TRAP;
    const A = linux.SECCOMP.RET.ALLOW;

    for (test_set) |t| {
        try std.testing.expectEqual(T, simulate(&prog, frameFor(t, test_arch, 1, 0)));
        try std.testing.expectEqual(
            A,
            simulate(&prog, frameFor(t, test_arch, 1, reissue_sentinel)),
        );
    }

    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff)));
    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff_0000_0000)));

    try std.testing.expectEqual(A, simulate(&prog, frame(74, test_arch, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frame(0, test_arch, 0)));

    try std.testing.expectEqual(A, simulate(&prog, frame(1, 0x4000_0003, 0)));
}

test "an open's flags decide whether it is trapped" {
    const prog = buildProgram(test_arch, &test_set);
    const T = linux.SECCOMP.RET.TRAP;
    const A = linux.SECCOMP.RET.ALLOW;
    const openat = 257;

    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0o2000000, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0o200000, 0)));
    for ([_]u64{ 1, 2, 0o100, 0o1000 }) |f|
        try std.testing.expectEqual(T, simulate(&prog, frameFlags(openat, test_arch, f, 0)));
    try std.testing.expectEqual(T, simulate(&prog, frameFlags(openat, test_arch, 3, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 1, reissue_sentinel)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 1 << 32, 0)));
}

test "the trap set's length does not move the jump targets" {
    const one = [_]RawTrap{.{ .nr = 1 }};
    const one_prog = buildProgram(test_arch, &one);
    try std.testing.expectEqual(linux.SECCOMP.RET.TRAP, simulate(&one_prog, frame(1, test_arch, 0)));
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&one_prog, frame(18, test_arch, 0)));

    // Six members with two flag tests among them, and the flag tests not last: a block's
    // length moves every block after it, which is the arithmetic that breaks first.
    const six = [_]RawTrap{
        .{ .nr = 1 },
        .{ .nr = 257, .flag_arg = 2, .flag_mask = write_capable_mask },
        .{ .nr = 18 },
        .{ .nr = 2, .flag_arg = 1, .flag_mask = write_capable_mask },
        .{ .nr = 296 },
        .{ .nr = 285 },
    };
    const six_prog = buildProgram(test_arch, &six);
    for (six) |t| {
        try std.testing.expectEqual(
            linux.SECCOMP.RET.TRAP,
            simulate(&six_prog, frameFor(t, test_arch, 1, 0)),
        );
        try std.testing.expectEqual(
            linux.SECCOMP.RET.ALLOW,
            simulate(&six_prog, frameFor(t, test_arch, 1, reissue_sentinel)),
        );
        if (t.flag_arg != null)
            try std.testing.expectEqual(
                linux.SECCOMP.RET.ALLOW,
                simulate(&six_prog, frameFor(t, test_arch, 0, 0)),
            );
    }
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&six_prog, frame(74, test_arch, 0)));
}

test "the built-in program is the one this architecture's set describes" {
    // The program the shim actually installs, simulated: every member traps unmarked and
    // passes marked, and a syscall outside the set is allowed. `trapped` is empty on an
    // architecture without a layout, and then there is nothing to check.
    if (trapped.len == 0) return error.SkipZigTest;
    for (trapped_raw) |t| {
        try std.testing.expectEqual(
            linux.SECCOMP.RET.TRAP,
            simulate(&program, frameFor(t, audit_arch, 1, 0)),
        );
        try std.testing.expectEqual(
            linux.SECCOMP.RET.ALLOW,
            simulate(&program, frameFor(t, audit_arch, 1, reissue_sentinel)),
        );
        if (t.flag_arg != null)
            try std.testing.expectEqual(
                linux.SECCOMP.RET.ALLOW,
                simulate(&program, frameFor(t, audit_arch, 0, 0)),
            );
    }
    const read_nr: i32 = @intCast(@backingInt(SYS.read));
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&program, frame(read_nr, audit_arch, 0)));
}

test "AUDIT_ARCH values match the header's" {
    // Composed from `elf.EM` here, so this pins the composition, not a copy of itself.
    try std.testing.expectEqual(
        @as(u32, 0xC000_00B7),
        @backingInt(std.elf.EM.AARCH64) | audit_64bit | audit_le,
    );
    try std.testing.expectEqual(
        @as(u32, 0xC000_003E),
        @backingInt(std.elf.EM.X86_64) | audit_64bit | audit_le,
    );
}

test "the trap frame's offsets keep the shape a transcription slip would break" {
    // The absolute offsets are measured (see `layout`), so what is checkable here is the
    // shape, not the values. This test read `l.nr` until the number moved to `siginfo`
    // and then did not compile — and nothing said so for a while, because the file it
    // lives in was not a test root and its tests were not being collected. It is in
    // `build.zig`'s `test_sources` now, which is what makes this run at all.
    const l = layout orelse return error.SkipZigTest;

    // Six argument registers, and each platform's own spelling of where the result goes.
    // Stated per platform rather than as one rule, because the two ABIs disagree: on
    // aarch64 the six arguments are consecutive and the result shares the first one's
    // register (x0), while on x86_64 they are scattered across gregs and the result is
    // RAX, which is none of them.
    switch (builtin.cpu.arch) {
        .aarch64 => {
            for (1..6) |i| try std.testing.expectEqual(l.args[i - 1] + 8, l.args[i]);
            try std.testing.expectEqual(l.args[0], l.ret);
        },
        .x86_64 => {
            for (l.args) |a| try std.testing.expect(a != l.ret);
            for (l.args) |a| try std.testing.expectEqual(@as(usize, 0), (a - 40) % 8);
            try std.testing.expectEqual(@as(usize, 0), (l.ret - 40) % 8);
        },
        else => unreachable, // `layout` is null for every other architecture
    }
}

/// glibc's own set functions, so `withoutSigsys` is held against the C library's reading
/// of a mask rather than against this file's arithmetic.
const test_libc = struct {
    extern "c" fn sigfillset(set: ?*std.c.sigset_t) c_int;
    extern "c" fn sigismember(set: ?*const std.c.sigset_t, signo: c_int) c_int;
};

test "a sa_mask holding SIGSYS comes back without it, and nothing else in the request moves" {
    if (layout == null or builtin.abi != .gnu) return error.SkipZigTest;

    var act = std.mem.zeroes(std.c.Sigaction);
    act.handler.sigaction = @ptrFromInt(0x1000);
    act.flags = 0x0800_0004; // SA_ONSTACK | SA_SIGINFO
    act.restorer = @ptrFromInt(0x2000);
    try std.testing.expectEqual(@as(c_int, 0), test_libc.sigfillset(&act.mask));
    try std.testing.expectEqual(@as(c_int, 1), test_libc.sigismember(&act.mask, sigsys_no));

    const out = withoutSigsys(&act) orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(@as(c_int, 0), test_libc.sigismember(&out.mask, sigsys_no));
    try std.testing.expectEqual(@as(u8, 0x40), std.mem.asBytes(&act)[11] ^ std.mem.asBytes(&out)[11]);
    try std.testing.expectEqual(act.mask[0] & ~sigsys_bit, out.mask[0]);
    try std.testing.expectEqualSlices(c_ulong, act.mask[1..], out.mask[1..]);
    try std.testing.expectEqual(act.handler.sigaction, out.handler.sigaction);
    try std.testing.expectEqual(act.flags, out.flags);
    try std.testing.expectEqual(act.restorer, out.restorer);
}

test "a sa_mask without SIGSYS is forwarded as the caller's own" {
    if (layout == null or builtin.abi != .gnu) return error.SkipZigTest;

    // Every bit but SIGSYS's, so a test one bit off in either direction finds one set.
    var act = std.mem.zeroes(std.c.Sigaction);
    @memset(&act.mask, std.math.maxInt(c_ulong));
    act.mask[sigsys_word] &= ~sigsys_bit;
    try std.testing.expectEqual(@as(c_int, 0), test_libc.sigismember(&act.mask, sigsys_no));

    try std.testing.expect(withoutSigsys(&act) == null);
}

const test_forward = struct {
    var ptr: ?*const anyopaque = null;
    var seen: std.c.Sigaction = undefined;
    fn fake(signum: c_int, act: ?*const anyopaque, oldact: ?*anyopaque) callconv(.c) c_int {
        _ = signum;
        _ = oldact;
        ptr = act;
        if (act) |a| @memcpy(std.mem.asBytes(&seen), @as([*]const u8, @ptrCast(a)));
        return 0;
    }
};

test "sigaction hands the caller's request on as written unless the guards are up and its sa_mask holds SIGSYS" {
    if (layout == null or builtin.abi != .gnu) return error.SkipZigTest;
    // The wrapper itself, not `withoutSigsys`: which pointer reaches the C library is decided
    // at its branches, and the default mode's promise is one of them.
    const saved_real = real_sigaction;
    const saved_guard = guard_signal;
    defer {
        real_sigaction = saved_real;
        guard_signal = saved_guard;
    }
    real_sigaction = .{ .found = &test_forward.fake };
    const usr1: c_int = @backingInt(linux.SIG.USR1);
    const usr2: c_int = @backingInt(linux.SIG.USR2);

    var full = std.mem.zeroes(std.c.Sigaction);
    try std.testing.expectEqual(@as(c_int, 0), test_libc.sigfillset(&full.mask));

    guard_signal = false;
    try std.testing.expectEqual(@as(c_int, 0), sigaction(usr1, &full, null));
    try std.testing.expect(test_forward.ptr.? == @as(*const anyopaque, &full));
    try std.testing.expectEqual(@as(c_int, 1), test_libc.sigismember(&test_forward.seen.mask, sigsys_no));

    guard_signal = true;
    try std.testing.expectEqual(@as(c_int, 0), sigaction(usr1, &full, null));
    try std.testing.expect(test_forward.ptr.? != @as(*const anyopaque, &full));
    try std.testing.expectEqual(@as(c_int, 0), test_libc.sigismember(&test_forward.seen.mask, sigsys_no));
    try std.testing.expectEqual(@as(c_int, 1), test_libc.sigismember(&test_forward.seen.mask, usr2));
    try std.testing.expectEqual(@as(c_int, 1), test_libc.sigismember(&full.mask, sigsys_no));

    var partial = full;
    partial.mask[sigsys_word] &= ~sigsys_bit;
    try std.testing.expectEqual(@as(c_int, 0), sigaction(usr1, &partial, null));
    try std.testing.expect(test_forward.ptr.? == @as(*const anyopaque, &partial));
}
