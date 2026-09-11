//! Observation at the syscall boundary (`--observe syscalls`, Linux only).
//!
//! The interposed entry points in `ops.zig` see an operation only when the target calls
//! one of them. Buffered stdio does not: `fwrite` past the buffer's capacity issues the
//! `write` from *inside* libc, and a raw `syscall(SYS_write, …)` never enters libc at
//! all. ADR 0005 chose flush granularity deliberately and listed those two shapes as
//! outside it; `docs/target-classes.md` records metaflac and fontforge refusing there.
//! A runtime that issues its syscalls directly — Go's, which reaches the kernel without
//! libc for everything but the handful of calls cgo routes through it — is the same shape
//! one layer up: every one of its writes, renames and unlinks is invisible to a wrapper.
//! This module is the second observation path, not a replacement. The default mode
//! declines nothing and records nothing through it, but it is not untouched: the `SIGSYS`
//! handler is installed in every mode, and the four signal entry points below are exported
//! in every mode and forward there (see `installHandler` and `resolveGuards`).
//!
//! A seccomp filter answers `SECCOMP_RET_TRAP` for the trap set, the kernel raises
//! `SIGSYS` *without executing the call*, and the handler counts the operation through
//! the same `noteFd` / `note1` / `note2` the wrappers use before re-issuing the syscall
//! itself.
//!
//! `syscalls.armed` decides which of the two doors counts: the handler records only while
//! it is set, and each wrapper whose syscall is in the set stays silent while it is set
//! (`common.countedAtSyscall`). One operation therefore reaches the account once, whether
//! it arrived through libc or not.
//!
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
//!
//! ## Why an unhandled `SIGSYS` does not end the run
//!
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
//! the mask-setting calls.
//!
//! ## What this mode does not see
//!
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

/// Left in the sixth argument register by `thunk`, recognised by the filter.
///
/// Spelled once here and read by nothing else: the filter builds its comparison from
/// this constant and the thunk passes this constant, so the two cannot drift apart.
pub const reissue_sentinel: u64 = 0x51DEE7E5CA11ED01;

/// glibc's `errno` accessor. Declared here rather than in `common.zig`'s shared `c`
/// block because that block is compiled for both platforms and this spelling is Linux's
/// (Darwin's is `__error`), and nothing outside this file needs it.
extern "c" fn __errno_location() *c_int;

/// One member of the trap set: a syscall number, and optionally the argument whose flags
/// decide whether this call can change anything.
///
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
    /// Index of the flags argument, when this member is trapped conditionally.
    flag_arg: ?usize = null,
    flag_mask: u32 = 0,
};

/// The same member with its number resolved. The filter is built from these: a program is
/// arithmetic over numbers, and the tests below need to describe one architecture's numbers
/// while running on another's, which naming `SYS` members cannot do (an `x86_64` number is
/// not a tag of the `aarch64` enum).
const RawTrap = struct {
    nr: u32,
    flag_arg: ?usize = null,
    flag_mask: u32 = 0,
};

fn rawSet(comptime set: []const Trap) []const RawTrap {
    comptime {
        var out: [set.len]RawTrap = undefined;
        for (set, 0..) |t, i| out[i] = .{
            .nr = @intCast(@intFromEnum(t.sys)),
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

/// The syscalls this mode counts: every operation `contract.OpClass.isKillPoint` admits,
/// in the spellings the target's architecture has, plus the write family this mode started
/// with. Two are deliberately absent — `copy_file_range` and `pwritev2` take six arguments,
/// so the sentinel's register is not free for them (`docs/report-schema.md` discloses both).
///
/// Every member takes at most five arguments, which is what makes `args[5]` available for
/// the sentinel — asserted in `install` rather than trusted.
///
/// The numbers come from `std.os.linux.SYS`, which is per-architecture: a name absent on
/// the target architecture is a compile error here rather than a silently missing member
/// of a hand-written table. That is the whole reason for not writing the table — and the
/// reason the legacy spellings below sit behind a comptime branch: `.open`, `.rename` and
/// the rest do not exist on aarch64.
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

/// True once the filter is installed, i.e. once the handler — not the wrappers — is the
/// thing that counts the trapped operations.
///
/// Read by both doors: `onSigsys` records only while it is set, and
/// `common.countedAtSyscall` answers on it so that every wrapper whose syscall is in the
/// set stays silent while it is. A process standing in front of a filter it did not
/// install has it false, and there the wrappers are the ones counting.
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

/// Byte offset of `si_code`, and the value the kernel writes there for a seccomp trap.
///
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
/// `BPF_JMP | BPF_JA`: the unconditional forward jump. Needed once the program has a
/// block per member — a member's block has to reach the shared tail, and seccomp's jumps
/// only go forward, so the tail is where ALLOW and TRAP live.
const BPF_JA: u16 = 0x05;
/// `BPF_ALU | BPF_AND | BPF_K`: masks the accumulator, which is how the open family's
/// flags argument is tested without reading memory the filter cannot reach.
const BPF_AND_K: u16 = 0x54;

/// `seccomp_data` field offsets, from `std.os.linux.SECCOMP.data`'s own layout rather
/// than a comment: nr, arch, instruction_pointer, then six 64-bit arguments.
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

/// How many instructions `buildProgram` emits for a set. Written as its own function so
/// the array's size and the offsets below are computed from the same arithmetic.
fn programLen(comptime set: []const RawTrap) usize {
    // arch load, arch compare, nr load, one compare per member, the "no member matched"
    // jump, each member's block, the sentinel's four, and the two returns.
    var n: usize = 3 + set.len + 1;
    for (set) |t| n += if (t.flag_arg != null) 4 else 1;
    return n + 4 + 2;
}

/// Built at comptime from `trapped`, so adding a syscall to the set cannot leave a
/// jump offset behind. A hand-written program was the first draft and its offsets were
/// wrong for a five-member set; a later version sized its array one instruction short and
/// put ALLOW and TRAP in the same slot, which trapped the handler's own re-issue.
///
/// Shape — every jump goes forward, because seccomp's do:
///   arch != ours                      -> ALLOW   (an ABI whose `nr` we cannot read)
///   nr not in `trapped`               -> ALLOW
///   nr in `trapped`                   -> that member's block
///     a member with a flag test:      flags & mask == 0 -> ALLOW   (a read-only open)
///     otherwise                       -> the sentinel check
///   args[5] == sentinel               -> ALLOW   (our own re-issue)
///   otherwise                         -> TRAP
fn buildProgram(comptime arch_id: u32, comptime set: []const RawTrap) [programLen(set)]SockFilter {
    @setEvalBranchQuota(10000);
    const n = set.len;
    var insns: [programLen(set)]SockFilter = undefined;

    // Where each member's block starts, and where the shared tail does.
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
            // Nothing of the mask set: a call that cannot change anything. Allowed, and
            // this is what keeps a loader's read-only opens out of the trap.
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

/// The set with its numbers resolved, once, at comptime: `rawSet` builds a comptime array
/// and cannot hand it back from a call made at run time.
const trapped_raw: []const RawTrap = rawSet(trapped);

const program = buildProgram(audit_arch, trapped_raw);

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
    //
    // The premise was re-measured when the set widened (#542), by reading what the
    // handler issues between a trap and its re-issue in a capture of `toy-raw raw-all`,
    // 20 traps: `lseek`, `pread64`, `statx`, `readlinkat` — and `write`, 19 times. That
    // last one IS in the trap set, and the earlier spelling of this comment ("nothing the
    // handler calls is in the trap set") was therefore wrong rather than merely dated.
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
            // At most five arguments: renameat2 and linkat have five, the rest fewer.
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
                // The legacy spellings, which exist on this architecture only.
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

    // `init` has already done this, before its own trace open; calling it again costs one
    // syscall and makes this function correct when read on its own. A failure below leaves
    // the handler installed with no filter behind it. Left that way deliberately: the
    // engine refuses the run on the announcement, so the process is going nowhere, and
    // restoring the previous disposition would mean storing it and putting the restore on
    // a path that has no observable effect (review, P2).
    installHandler();

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
// They are installed in EVERY mode, like `installHandler` and for the same reason: a
// filter is inherited across `exec` and a process whose own mode is `wrappers` can be
// standing in front of one. Where no filter exists anywhere they change nothing a target
// can observe — nothing raises `SIGSYS`, and every query still reports the truth.
//
// The residual is a target that reaches `rt_sigaction` or `rt_sigprocmask` without libc;
// a statically linked Go binary is the case to expect. Interposition cannot see those.
// The filter could trap `rt_sigaction` — four arguments, so the sentinel's register is
// free — and that is the step to take if a target needs it; `docs/report-schema.md`
// discloses the gap meanwhile.

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

/// `SIGSYS` as a plain number, for comparison against a libc `signum` argument.
const sigsys_no: c_int = @intFromEnum(linux.SIG.SYS);

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
///
/// A miss is memoised too, as `.missing`: `dlsym` walks the link map, and a symbol absent
/// once is absent every time, so retrying it on every call would put that walk on a path
/// that is supposed to cost a load (review, P2).
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

/// Put `SIGSYS` back in this thread's deliverable set, whatever the call just before did.
///
/// std's `rt_sigprocmask` over a set built with std's own helpers, so nothing in this
/// path depends on how the C library spells `sigset_t` — the kernel's is the one std
/// knows, and it passes the size the kernel wants. The caller's own set is never copied:
/// it goes to the library's function untouched, and this undoes one bit of the result.
///
/// `SIGSYS` is blocked on this thread between the two calls. Nothing can trap in that
/// gap: the thread is inside these two calls, and neither the library function nor
/// `rt_sigprocmask` is in the trap set.
fn unblockSigsys() void {
    var set = linux.sigemptyset();
    linux.sigaddset(&set, .SYS);
    _ = linux.sigprocmask(linux.SIG.UNBLOCK, &set, null);
}

/// `act` and `oldact` stay opaque: the request is forwarded pointer-for-pointer, so this
/// wrapper never needs to know what the C library's `struct sigaction` looks like.
pub fn sigaction(signum: c_int, act: ?*const anyopaque, oldact: ?*anyopaque) callconv(.c) c_int {
    const f = nextSymbol(SigactionFn, "sigaction", &real_sigaction) orelse return -1;
    if (!guard_signal or signum != sigsys_no or act == null) return f(signum, act, oldact);
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

// --- the handler -------------------------------------------------------------------

/// A pointer argument, read as the path it is. The handler runs in the target's own
/// address space, so the pointer the kernel refused is still the target's own.
fn pathOf(v: u64) [*:0]const u8 {
    return @ptrFromInt(v);
}

/// A descriptor or `AT_FDCWD` argument, which the kernel passes sign-extended.
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
    const sys: SYS = @enumFromInt(nr);
    switch (builtin.cpu.arch) {
        .x86_64 => switch (sys) {
            // The legacy spellings glibc still issues on this architecture.
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

/// One trapped call.
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
    if (code != sys_seccomp) {
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
        return;
    }

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
// write, pwrite64, writev, pwritev on x86_64, and openat with the open family's flag test.
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

    // Every member of the set traps when the sentinel is absent — a member with a flag
    // test only when its flags say the call can change something.
    for (test_set) |t| {
        // O_WRONLY where the member has a flag test, and the filter reads it from that
        // member's own argument.
        try std.testing.expectEqual(T, simulate(&prog, frameFor(t, test_arch, 1, 0)));
        // …and is allowed once the thunk has marked it.
        try std.testing.expectEqual(
            A,
            simulate(&prog, frameFor(t, test_arch, 1, reissue_sentinel)),
        );
    }

    // A sentinel that matches only one half must not pass: the two halves are compared
    // separately, and a program that jumped to ALLOW after the low word would let any
    // call whose sixth register happened to hold that word through uncounted.
    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff)));
    try std.testing.expectEqual(T, simulate(&prog, frame(1, test_arch, reissue_sentinel & 0xffff_ffff_0000_0000)));

    // Outside the set: `fsync` is not in this test's set, and `read` is in no set.
    try std.testing.expectEqual(A, simulate(&prog, frame(74, test_arch, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frame(0, test_arch, 0)));

    // A syscall ABI the filter cannot read `nr` in is allowed rather than trapped, and
    // the oracle is what accounts for it (ADR).
    try std.testing.expectEqual(A, simulate(&prog, frame(1, 0x4000_0003, 0)));
}

test "an open's flags decide whether it is trapped" {
    // The whole reason a widened trap set does not kill the image an exec puts in front of
    // it: a loader opens its libraries read-only, and a read-only open is allowed without
    // a handler anywhere. Measured on the real filter too (BUILDLOG 2026-09-11).
    const prog = buildProgram(test_arch, &test_set);
    const T = linux.SECCOMP.RET.TRAP;
    const A = linux.SECCOMP.RET.ALLOW;
    const openat = 257;

    // O_RDONLY, and O_RDONLY with flags outside the mask (O_CLOEXEC, O_DIRECTORY): allowed.
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0o2000000, 0)));
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 0o200000, 0)));
    // Each bit of the mask on its own: O_WRONLY, O_RDWR, O_CREAT, O_TRUNC.
    for ([_]u64{ 1, 2, 0o100, 0o1000 }) |f|
        try std.testing.expectEqual(T, simulate(&prog, frameFlags(openat, test_arch, f, 0)));
    // The invalid access mode (both low bits) counts as write-capable on both sides.
    try std.testing.expectEqual(T, simulate(&prog, frameFlags(openat, test_arch, 3, 0)));
    // A write-capable open the handler re-issues is allowed, like any other member's.
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 1, reissue_sentinel)));
    // Only the low word of the flags argument is read; a high half cannot smuggle a trap.
    try std.testing.expectEqual(A, simulate(&prog, frameFlags(openat, test_arch, 1 << 32, 0)));
}

test "the trap set's length does not move the jump targets" {
    // The offsets are arithmetic on the set's length and on where each member's block
    // starts, so a one-member and a many-member program have to behave the same for their
    // own members. This is the check the hand-written program failed.
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
        // A member with a flag test, read-only: allowed, and the others are unaffected
        // because their frame carries nothing in that argument either way.
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
        // Every member with a flag test lets its read-only form through.
        if (t.flag_arg != null)
            try std.testing.expectEqual(
                linux.SECCOMP.RET.ALLOW,
                simulate(&program, frameFor(t, audit_arch, 0, 0)),
            );
    }
    // `read` is in no set on either architecture.
    const read_nr: i32 = @intCast(@intFromEnum(SYS.read));
    try std.testing.expectEqual(linux.SECCOMP.RET.ALLOW, simulate(&program, frame(read_nr, audit_arch, 0)));
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
