//! Write observation at the syscall boundary (`--observe syscalls`, Linux only).
//!
//! The interposed entry points in `ops.zig` see a write only when the target calls one
//! of them. Buffered stdio does not: `fwrite` past the buffer's capacity issues the
//! `write` from *inside* libc, and a raw `syscall(SYS_write, …)` never enters libc at
//! all. ADR 0005 chose flush granularity deliberately and listed those two shapes as
//! outside it; `docs/target-classes.md` records metaflac and fontforge refusing there.
//! This module is the second observation path, not a replacement: the default mode's
//! behaviour is untouched.
//!
//! A seccomp filter answers `SECCOMP_RET_TRAP` for the write family, the kernel raises
//! `SIGSYS` *without executing the call*, and the handler counts the operation through
//! the same `noteFd` the wrappers use before re-issuing the syscall itself.
//!
//! ## Why the handler can re-issue without trapping itself
//!
//! The re-issue goes through `std.os.linux.syscall6`, whose sixth argument lands in the
//! register the kernel copies into `seccomp_data.args[5]` (`x5` on aarch64, `r9` on
//! x86_64 — read from std's `syscall6`, not assumed). The thunk puts `reissue_sentinel`
//! there and the filter allows any call already carrying it. None of the four trapped
//! numbers takes six arguments, so the register is free.
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
//! The residual is a target that itself issues one of the four raw syscalls with the
//! sentinel already in its sixth argument register. That write would be allowed
//! uncounted. `docs/report-schema.md` discloses it; the odds are 2^-64 per call, and the
//! oracle is the net for the case where it happens anyway.
//!
//! ## What this mode does not see
//!
//! Only the write family is trapped. `openat`, `rename`, `unlink` and the rest stay with
//! the wrappers, because `docs/target-classes.md`'s stdio row records what is actually
//! missing for the stdio targets — "the shim recorded the `open` and no `write`" — and because a trap set
//! containing `openat` kills the process outright: the new image's `ld.so` opens
//! libraries before any constructor has installed a handler, and a `SIGSYS` with no
//! handler is fatal (measured: exit 159).
//!
//! `pwritev2` is trapped by nothing and is not counted either: it takes six arguments, so
//! it has no free register for the sentinel, and glibc falls back to a trapped number on a
//! kernel that lacks it while issuing the real thing on a kernel that has it — so neither
//! counting it in the wrapper nor silencing the wrapper is correct on both. Its wrapper
//! records `.unsupported` in this mode and the engine refuses the run.
//!
//! A process running under a different syscall ABI (32-bit compat) is allowed through
//! uncounted: the filter cannot read `nr` in an ABI it does not know. The oracle sees
//! those writes and the comparison refuses, which is why this mode keeps an oracle
//! rather than dropping to `--allow-unverified` (ADR).

const std = @import("std");
const builtin = @import("builtin");

const common = @import("common.zig");
const contract = @import("contract");
const shim_build_options = @import("shim_build_options");

const linux = std.os.linux;
const SYS = linux.SYS;

/// Left in the sixth argument register by `thunk`, recognised by the filter.
///
/// Spelled once here and read by nothing else: the filter builds its comparison from
/// this constant and the thunk passes this constant, so the two cannot drift apart.
pub const reissue_sentinel: u64 = 0x51DEE7E5CA11ED01;

/// glibc's `errno` accessor. Declared here rather than in `common.zig`'s shared `c`
/// block because that block is compiled for both platforms and this spelling is Linux's
/// (Darwin's is `__error`), and nothing outside this file needs it.
extern "c" fn __errno_location() *c_int;

/// The syscalls this mode counts. Every one takes at most four arguments, which is what
/// makes `args[5]` available for the sentinel — asserted below rather than trusted.
///
/// The numbers come from `std.os.linux.SYS`, which is per-architecture: a name absent on
/// the target architecture is a compile error here rather than a silently missing member
/// of a hand-written table. That is the whole reason for not writing the table.
const trapped = [_]SYS{ .write, .pwrite64, .writev, .pwritev };

/// True once the filter is installed, i.e. once the handler — not the wrappers — is the
/// thing that counts the write family.
pub var armed: bool = false;

pub const Install = enum {
    /// The filter is in place; the handler counts writes.
    armed,
    /// This build cannot install a filter at all (not Linux, or an architecture whose
    /// register layout is not known here). Distinct from `failed`: nothing went wrong.
    unsupported,
    /// The kernel refused. The engine turns this into a setup error rather than a
    /// verdict — `docs/report-schema.md`'s `unknown_reason` set is closed, and
    /// "the shim is the right version but could not install its filter" has no member
    /// in it (`docs/contract-freeze.md`, surface 2).
    failed,
};

// --- register layout ---------------------------------------------------------------
//
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
///
/// Read at an offset because this toolchain's `std.os.linux.siginfo_t` has no SIGSYS
/// member in its field union.
const si_syscall_off: usize = 24;

const Layout = struct {
    /// The six argument registers, in syscall order.
    args: [6]usize,
    /// Where the return value has to be written for the target to see it.
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

// --- the filter --------------------------------------------------------------------

const SockFilter = extern struct { code: u16, jt: u8, jf: u8, k: u32 };
const SockFprog = extern struct { len: u16, filter: [*]const SockFilter };

const BPF_LD_W_ABS: u16 = 0x20;
const BPF_JEQ_K: u16 = 0x15;
const BPF_RET_K: u16 = 0x06;

/// `seccomp_data` field offsets, from `std.os.linux.SECCOMP.data`'s own layout rather
/// than a comment: nr, arch, instruction_pointer, then six 64-bit arguments.
const data_off = struct {
    const nr: u32 = @offsetOf(linux.SECCOMP.data, "nr");
    const arch: u32 = @offsetOf(linux.SECCOMP.data, "arch");
    const arg5_lo: u32 = @offsetOf(linux.SECCOMP.data, "arg5");
    const arg5_hi: u32 = arg5_lo + 4;
};

/// `AUDIT_ARCH_*` — the machine type with the width and endianness bits, exactly as
/// `linux/audit.h` composes it.
///
/// Built here rather than read from `std.os.linux.AUDIT.ARCH` because naming any member
/// of that enum forces the whole of it to be analysed, and this toolchain's copy does
/// not compile: `FRV = toAudit(.FRV, 0)` names an `elf.EM` member that does not exist
/// (zig 0.16.0, measured — the shim failed to cross-compile for Linux on it). Composing
/// from the two `elf.EM` members actually needed touches nothing broken, and the test at
/// the end of this file pins both results against the header's values.
const audit_64bit: u32 = 0x8000_0000;
const audit_le: u32 = 0x4000_0000;

const audit_arch: u32 = switch (builtin.cpu.arch) {
    .aarch64 => @intFromEnum(std.elf.EM.AARCH64) | audit_64bit | audit_le,
    .x86_64 => @intFromEnum(std.elf.EM.X86_64) | audit_64bit | audit_le,
    else => 0,
};

/// Built at comptime from `trapped`, so adding a syscall to the set cannot leave a
/// jump offset behind. A hand-written program was the first draft and its offsets were
/// wrong for a five-member set.
///
/// Shape (n + 10 instructions for an n-member set — the two trailing returns are
/// separate slots, which is the arithmetic the first draft got wrong):
///   arch != ours          -> ALLOW   (an ABI whose `nr` we cannot read)
///   nr not in `trapped`   -> ALLOW
///   args[5] == sentinel   -> ALLOW   (our own re-issue)
///   otherwise             -> TRAP
fn buildProgram(comptime arch_id: u32, comptime set: []const u32) [set.len + 10]SockFilter {
    const n = set.len;
    var insns: [n + 10]SockFilter = undefined;
    const allow_i = n + 3; // the ALLOW that ends the nr chain
    const check = n + 4; // `ld [arg5_lo]`
    const trap_i = n + 9;

    insns[0] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arch };
    insns[1] = .{ .code = BPF_JEQ_K, .jt = 0, .jf = allow_i - 2, .k = arch_id };
    insns[2] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.nr };
    for (set, 0..) |nr, i| {
        const here = 3 + i;
        insns[here] = .{
            .code = BPF_JEQ_K,
            .jt = @intCast(check - here - 1),
            .jf = 0,
            .k = nr,
        };
    }
    insns[allow_i] = .{ .code = BPF_RET_K, .jt = 0, .jf = 0, .k = linux.SECCOMP.RET.ALLOW };
    insns[check] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arg5_lo };
    insns[check + 1] = .{
        .code = BPF_JEQ_K,
        .jt = 0,
        .jf = @intCast(trap_i - (check + 1) - 1),
        .k = @truncate(reissue_sentinel),
    };
    insns[check + 2] = .{ .code = BPF_LD_W_ABS, .jt = 0, .jf = 0, .k = data_off.arg5_hi };
    insns[check + 3] = .{
        .code = BPF_JEQ_K,
        .jt = 0,
        .jf = @intCast(trap_i - (check + 3) - 1),
        .k = @truncate(reissue_sentinel >> 32),
    };
    insns[check + 4] = .{ .code = BPF_RET_K, .jt = 0, .jf = 0, .k = linux.SECCOMP.RET.ALLOW };
    insns[trap_i] = .{ .code = BPF_RET_K, .jt = 0, .jf = 0, .k = linux.SECCOMP.RET.TRAP };
    return insns;
}

const trapped_numbers = blk: {
    var out: [trapped.len]u32 = undefined;
    for (trapped, 0..) |sys, i| out[i] = @intFromEnum(sys);
    break :blk out;
};

const program = buildProgram(audit_arch, &trapped_numbers);

// --- the thunk ---------------------------------------------------------------------

/// Re-issue a syscall so that the filter lets it through.
///
/// `syscall6`'s sixth argument is the sentinel's slot; the caller never passes a real
/// sixth argument because no trapped syscall has one.
pub fn thunk(nr: u32, a0: u64, a1: u64, a2: u64, a3: u64, a4: u64) u64 {
    const r = linux.syscall6(@enumFromInt(nr), a0, a1, a2, a3, a4, reissue_sentinel);
    // Clear the marker register before returning, or the NEXT syscall inherits it.
    //
    // This is not tidiness. The sixth argument register is caller-saved and nothing in
    // the C calling convention sets it for a three-argument call, so after this function
    // returns it still holds the marker — and the very next `write(2)` libc issues, with
    // no sixth argument of its own, arrives at the filter carrying it and is ALLOWED.
    // The shim's own trace writes go through this thunk, so that sequence is not rare: a
    // record is written, and the write it was recording about is then invisible.
    //
    // Measured in CI, which is where it surfaced: on x86_64 every syscalls-mode
    // acceptance leg failed while the same legs passed on aarch64, and the divergence
    // named exactly one missing operation — the direct `write(2)` in the toy's
    // `write_file`, issued immediately after the shim had recorded the `open` through
    // this thunk. The register survives on one architecture's allocation and not the
    // other's, which is why a local aarch64 run could not see it.
    //
    // It also corrects what `docs/report-schema.md` disclosed: the collision was
    // described as 2^-64 per call, and while that is the odds of a TARGET holding the
    // marker by chance, the shim was producing the collision itself, systematically.
    // Zeroing here is what makes the disclosed figure the true one.
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

/// A `write` the shim itself performs, issued so the handler never sees it.
///
/// The trace channel cannot go through libc's `write` in this mode: that syscall traps,
/// the handler records, and recording writes another record — recursion that ends in a
/// stack overflow rather than a refusal. This is the one call the sentinel exists for
/// besides the re-issue.
pub fn traceWrite(fd: i32, buf: [*]const u8, n: usize) isize {
    const r = thunk(@intFromEnum(SYS.write), @bitCast(@as(i64, fd)), @intFromPtr(buf), n, 0, 0);
    const signed: i64 = @bitCast(r);
    return @intCast(signed);
}

// --- installation ------------------------------------------------------------------

/// Called by `common.init()` before `active` is set, so nothing is recorded through a
/// half-installed filter.
///
/// Order matters and is not negotiable: the handler has to exist before the filter, or
/// the first trapped write kills the process with an unhandled `SIGSYS`; and
/// `PR_SET_NO_NEW_PRIVS` has to be set before `SET_MODE_FILTER`, which the kernel
/// otherwise refuses with `EACCES` for an unprivileged caller.
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
        // member's own flags.
        for (trapped) |sys| switch (sys) {
            .write, .pwrite64, .writev, .pwritev => {},
            else => @compileError("a trapped syscall must take at most four arguments: " ++
                @tagName(sys) ++ " has to be checked before it joins the set"),
        };
    }

    var sa: linux.Sigaction = .{
        .handler = .{ .sigaction = onSigsys },
        .mask = linux.sigemptyset(),
        .flags = linux.SA.SIGINFO,
    };
    // Deliberately without `SA.NODEFER`. Nothing the handler calls is in the trap set,
    // so a nested trap means an assumption here is wrong — and with SIGSYS blocked the
    // kernel ends the process, which the engine reads as a run that did not complete.
    // Allowing re-entry instead would recurse quietly.
    // A failure below leaves this handler installed with no filter behind it. Left that
    // way deliberately: the engine refuses the run on the announcement, so the process is
    // going nowhere, and restoring the previous disposition would mean storing it and
    // putting the restore on a path that has no observable effect (review, P2).
    if (linux.sigaction(.SYS, &sa, null) != 0) return .failed;

    if (linux.prctl(@intFromEnum(linux.PR.SET_NO_NEW_PRIVS), 1, 0, 0, 0) != 0) return .failed;

    // No `SECCOMP_FILTER_FLAG_TSYNC`, and it is not a gap: this runs from the library
    // constructor, before the target has created any thread, and a filter is inherited by
    // every thread `clone` makes afterwards. Named here so a later reader does not read
    // its absence as an oversight (review, P2).
    const prog: SockFprog = .{ .len = @intCast(program.len), .filter = &program };
    const rc = linux.syscall3(
        .seccomp,
        linux.SECCOMP.SET_MODE_FILTER,
        0,
        @intFromPtr(&prog),
    );
    if (linux.errno(rc) != .SUCCESS) return .failed;

    armed = true;
    return .armed;
}

// --- the handler -------------------------------------------------------------------

/// One trapped write.
///
/// The counting, the scope decision, the path resolution and the kill all belong to
/// `noteFd`, exactly as they do for an interposed call — this function's whole job is to
/// read the descriptor out of the trap frame, hand it over, and then perform the call
/// the kernel refused. Everything `noteFd` reaches for (`statx`, `readlinkat`, `fcntl`,
/// `getpid`, the trace write through `traceWrite`) is outside the trap set or carries
/// the sentinel, so nothing here re-enters.
///
/// `noteFd` runs BEFORE the re-issue for the same reason the wrappers record before
/// calling through (ADR 0036): the k-th operation has to be stopped, and an operation
/// counted after the bytes have landed cannot be.
///
/// **The syscall number comes from `siginfo`, not from a register.** The first version
/// read it from the trap frame — `x8` on aarch64, `RAX` on x86_64 — and review pointed
/// out that those two are not the same kind of place. `x8` is an argument register the
/// kernel does not write, so it still holds the number; `RAX` is where the *result* goes,
/// and on x86_64 a syscall that is not executed leaves `-ENOSYS` there before the signal
/// frame is built. Measured on aarch64: `si_syscall` and `x8` agree, both hold `write`.
/// **x86_64 could not be measured here** — the only x86_64 environment available is an
/// emulated container, and it refuses `seccomp(SET_MODE_FILTER)` with `EINVAL` — so CI is
/// the first execution of this code on that platform. `si_syscall` is the channel seccomp
/// fills for exactly this purpose and is ABI-stable, which makes the question moot rather
/// than answered: there is no reason to depend on a register whose contents at delivery
/// this machine cannot check.
fn onSigsys(_: linux.SIG, info: *const linux.siginfo_t, uc_opaque: ?*anyopaque) callconv(.c) void {
    const l = layout orelse return;
    const uc = uc_opaque orelse return;

    const info_bytes: [*]const u8 = @ptrCast(info);
    const nr: u32 = @bitCast(std.mem.readInt(i32, info_bytes[si_syscall_off..][0..4], .little));
    var a: [6]u64 = undefined;
    for (l.args, 0..) |off, i| a[i] = regPtr(uc, off).*;

    // The descriptor is the first argument of all four trapped calls. If that ever
    // stops being true, the comptime check in `install()` is where it is caught.
    const fd: i32 = @truncate(@as(i64, @bitCast(a[0])));

    // `errno` belongs to the target, and `noteFd` reaches `statx` and `readlinkat` through
    // the C library, both of which write it. The libc wrapper the target called sets it
    // only when the syscall FAILS, so on the ordinary success path a clobbered value would
    // simply stay there and be visible to a caller that reads it afterwards (review, P2).
    const errno_slot = __errno_location();
    const saved_errno = errno_slot.*;
    common.noteFd(.write, fd);
    errno_slot.* = saved_errno;

    regPtr(uc, l.ret).* = thunk(nr, a[0], a[1], a[2], a[3], a[4]);
}

// --- tests -------------------------------------------------------------------------

/// A classic-BPF interpreter covering exactly the four opcodes `buildProgram` emits.
///
/// The filter's jump offsets are computed at comptime from the trap set's length, and
/// reading them back is not a check. The first version of `buildProgram` sized its array
/// one instruction short, which put the final ALLOW and the final TRAP at the same index
/// — the TRAP was written second, so it won, and the handler's own re-issue was trapped
/// as well: recursion, not a refusal. Nothing about the code looked wrong. This test
/// found it on the first run, which is the argument for simulating the program rather
/// than reading it.
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
            BPF_RET_K => return in.k,
            else => unreachable,
        }
    }
    unreachable; // a program that neither returns nor terminates would hang the kernel
}

const test_arch: u32 = 0xC000_003E; // AUDIT_ARCH_X86_64, chosen so the test is host-independent
const test_set = [_]u32{ 1, 18, 20, 296 }; // write, pwrite64, writev, pwritev on x86_64

fn frame(nr: i32, arch: u32, arg5: u64) linux.SECCOMP.data {
    return .{
        .nr = nr,
        .arch = arch,
        .instruction_pointer = 0,
        .arg0 = 3,
        .arg1 = 0,
        .arg2 = 0,
        .arg3 = 0,
        .arg4 = 0,
        .arg5 = arg5,
    };
}

test "the filter traps an unmarked write and allows the handler's re-issue" {
    const prog = buildProgram(test_arch, &test_set);
    const T = linux.SECCOMP.RET.TRAP;
    const A = linux.SECCOMP.RET.ALLOW;

    // Every member of the set traps when the sentinel is absent.
    for (test_set) |nr| {
        try std.testing.expectEqual(T, simulate(&prog, frame(@intCast(nr), test_arch, 0)));
        // …and is allowed once the thunk has marked it.
        try std.testing.expectEqual(
            A,
            simulate(&prog, frame(@intCast(nr), test_arch, reissue_sentinel)),
        );
    }

    // A sentinel that matches only one half must not pass: the two halves are compared
    // separately, and a program that jumped to ALLOW after the low word would let any
    // call whose sixth register happened to hold that word through uncounted.
    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff)));
    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff_0000_0000)));

    // Outside the set: openat and fsync are the wrappers' business in this mode.
    try std.testing.expectEqual(A, simulate(&prog, frame(257, test_arch, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frame(74, test_arch, 0)));

    // A syscall ABI the filter cannot read `nr` in is allowed rather than trapped, and
    // the oracle is what accounts for it (ADR).
    try std.testing.expectEqual(A, simulate(&prog, frame(1, 0x4000_0003, 0)));
}

test "the trap set's length does not move the jump targets" {
    // The offsets are arithmetic on the set's length, so a one-member and a
    // six-member program have to behave the same for their own members. This is the
    // check the hand-written program failed.
    const one = buildProgram(test_arch, &[_]u32{1});
    try std.testing.expectEqual(linux.SECCOMP.RET.TRAP, simulate(&one, frame(1, test_arch, 0)));
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&one, frame(18, test_arch, 0)));

    const six = buildProgram(test_arch, &[_]u32{ 1, 18, 20, 296, 328, 285 });
    for ([_]u32{ 1, 18, 20, 296, 328, 285 }) |nr|
        try std.testing.expectEqual(linux.SECCOMP.RET.TRAP, simulate(&six, frame(@intCast(nr), test_arch, 0)));
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&six, frame(257, test_arch, 0)));
}

test "AUDIT_ARCH values match the header's" {
    // `linux/audit.h`: AUDIT_ARCH_AARCH64 0xc00000b7, AUDIT_ARCH_X86_64 0xc000003e.
    // Composed from `elf.EM` here, so this pins the composition, not a copy of itself.
    try std.testing.expectEqual(
        @as(u32, 0xC000_00B7),
        @intFromEnum(std.elf.EM.AARCH64) | audit_64bit | audit_le,
    );
    try std.testing.expectEqual(
        @as(u32, 0xC000_003E),
        @intFromEnum(std.elf.EM.X86_64) | audit_64bit | audit_le,
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
            // RAX is not an argument register, so the result offset must differ from all
            // six — the slip this catches is pasting an argument offset into `ret`.
            for (l.args) |a| try std.testing.expect(a != l.ret);
            // Every offset lands on an 8-byte `greg` boundary from `gregs[0]` at 40.
            for (l.args) |a| try std.testing.expectEqual(@as(usize, 0), (a - 40) % 8);
            try std.testing.expectEqual(@as(usize, 0), (l.ret - 40) % 8);
        },
        else => unreachable, // `layout` is null for every other architecture
    }
}
