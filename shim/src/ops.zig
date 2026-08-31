//! The replacement functions, shared by both platforms.
//!
//! Every one does the same two things: note the operation, then forward to the real
//! function through `common.call*`. Those wrappers are where the platforms differ —
//! Linux goes through a `dlsym`-filled table, macOS calls the original directly — and
//! keeping that difference in one place means a fix to path handling or ordering cannot
//! land on one platform and miss the other.
//!
//! How these get installed differs too: `linux.zig` exports the symbols for
//! `LD_PRELOAD` to resolve, `macos.zig` lists them in a `__DATA,__interpose` table.

const std = @import("std");
const builtin = @import("builtin");
const contract = @import("contract");
const common = @import("common.zig");

const AT_FDCWD = common.AT_FDCWD;

// --- kill-point ops: open family -------------------------------------------------

/// `open` and `openat` are the only variadic entry points, and the right declaration
/// differs by platform — not as a preference, but because each ABI makes the other
/// form wrong.
///
/// On arm64 macOS variadic arguments go on the stack while fixed ones go in registers,
/// so a fixed-arity declaration reads `mode` from a register the caller never wrote.
/// On Linux the two agree, and Zig refuses `@cVaStart` for that target outright
/// ("disabled due to miscompilations") — its own statement about that ABI.
// A write-incapable open is not observed at all (ADR 0003): it cannot change state, so
// the world killed immediately before it is byte-identical to the world killed at the
// next address — the same treatment as a path outside the state directory. The oracle
// applies the matching predicate textually and skips the same opens.
const open_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        // Reading it when O_CREAT is absent would consume something never pushed.
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, path);
        return common.callOpen(path, flags, mode);
    }
} else struct {
    pub fn f(path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, path);
        return common.callOpen(path, flags, mode);
    }
};
pub const open = open_impl.f;

const openat_impl = if (builtin.os.tag == .macos) struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, ...) callconv(.c) c_int {
        var ap = @cVaStart();
        defer @cVaEnd(&ap);
        const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
        if (common.openIsWriteCapable(flags)) common.note1(.open, dirfd, path);
        return common.callOpenat(dirfd, path, flags, mode);
    }
} else struct {
    pub fn f(dirfd: c_int, path: [*:0]const u8, flags: c_int, mode: c_uint) callconv(.c) c_int {
        if (common.openIsWriteCapable(flags)) common.note1(.open, dirfd, path);
        return common.callOpenat(dirfd, path, flags, mode);
    }
};
pub const openat = openat_impl.f;

pub fn creat(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    // creat is always write-capable: it implies O_CREAT|O_WRONLY|O_TRUNC.
    common.note1(.open, AT_FDCWD, path);
    return common.callCreat(path, mode);
}

// --- kill-point ops: write family ------------------------------------------------

pub fn write(fd: c_int, buf: [*]const u8, count: usize) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callWrite(fd, buf, count);
}

pub fn pwrite(fd: c_int, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callPwrite(fd, buf, count, offset);
}

pub fn writev(fd: c_int, iov: *const anyopaque, iovcnt: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callWritev(fd, iov, iovcnt);
}

pub fn pwritev(fd: c_int, iov: *const anyopaque, iovcnt: c_int, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callPwritev(fd, iov, iovcnt, offset);
}

pub fn pwritev2(fd: c_int, iov: *const anyopaque, iovcnt: c_int, offset: i64, flags: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callPwritev2(fd, iov, iovcnt, offset, flags);
}

// --- kill-point ops: the kernel's copy primitives (#244) --------------------------

/// The destination descriptor is the third argument, not the first — the one place in
/// this file where the written descriptor is not `fd`. `src/oracle.zig`'s
/// `fd_write_args` carries the same fact for the other observer; both must agree or
/// the copy is counted on one side only.
pub fn copy_file_range(fd_in: c_int, off_in: ?*i64, fd_out: c_int, off_out: ?*i64, len: usize, flags: c_uint) callconv(.c) isize {
    common.noteFd(.write, fd_out);
    return common.callCopyFileRange(fd_in, off_in, fd_out, off_out, len, flags);
}

/// `sendfile(out_fd, in_fd, …)` on Linux: the destination is already first, which is
/// why it needs no `fd_write_args` entry. macOS spells a different call with the
/// arguments the other way round and a socket destination, so this wrapper is
/// installed on Linux only.
pub fn sendfile(out_fd: c_int, in_fd: c_int, offset: ?*i64, count: usize) callconv(.c) isize {
    common.noteFd(.write, out_fd);
    return common.callSendfile(out_fd, in_fd, offset, count);
}

// --- kill-point ops: rename ------------------------------------------------------

pub fn rename(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, AT_FDCWD, old, AT_FDCWD, new);
    return common.callRename(old, new);
}

pub fn renameat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.rename, olddirfd, old, newdirfd, new);
    return common.callRenameat(olddirfd, old, newdirfd, new);
}

/// `renameat2`'s flags decide what it means, the way `unlinkat`'s `AT_REMOVEDIR`
/// does above (#256). `RENAME_NOREPLACE` is a plain rename that refuses to clobber,
/// so it records as one. `RENAME_EXCHANGE` swaps two files and `RENAME_WHITEOUT`
/// leaves a whiteout inode — effects the snapshot/restore model does not reproduce,
/// so neither is recorded as a `.rename`. The oracle refuses them by flag name
/// (`renameat2(RENAME_EXCHANGE)`), which is what the operator reads; recording a
/// `.rename` here as well would put a phantom on the shim's side of an account that
/// is already going to refuse.
pub fn renameat2(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8, flags: c_uint) callconv(.c) c_int {
    if (flags & (common.RENAME_EXCHANGE | common.RENAME_WHITEOUT) == 0)
        common.note2(.rename, olddirfd, old, newdirfd, new);
    return common.callRenameat2(olddirfd, old, newdirfd, new, flags);
}

// --- The macOS family (v12, #333) ------------------------------------------------
//
// Everything below is installed by macos.zig only. Linux never exports these names,
// and the call helpers answer ENOSYS if a future mistake changes that.
//
// The clone family records a `.write` on the DESTINATION, one record: a clone is one
// atomic syscall after which a name holds content, and its source is copy-on-write —
// unchanged — so scope reads the destination alone (the same reasoning ADR 0023
// applied to `copy_file_range`, whose written descriptor is not argument 0 either).
// The record is an attempt, like every record this file writes: `clonefile` fails
// when its destination exists, callers (Rust std, `copyfile(COPYFILE_CLONE)`) then
// fall back to plain writes, and the failed attempt's crash point is a state-twin of
// its successor — same state, same judgment (measured; the CI leg pins it).

pub fn clonefile(src: [*:0]const u8, dst: [*:0]const u8, flags: u32) callconv(.c) c_int {
    common.note1(.write, AT_FDCWD, dst);
    return common.callClonefile(src, dst, flags);
}

pub fn clonefileat(src_dirfd: c_int, src: [*:0]const u8, dst_dirfd: c_int, dst: [*:0]const u8, flags: u32) callconv(.c) c_int {
    common.note1(.write, dst_dirfd, dst);
    return common.callClonefileat(src_dirfd, src, dst_dirfd, dst, flags);
}

/// Argument 0 is the SOURCE FILE's descriptor, not a dirfd — the destination is
/// argument 2, relative to the dirfd in argument 1. Handing `srcfd` to `note1` would
/// not fail loudly: `fdKind` answers `path_backed` for a regular file and the record
/// would name a path under the source file. The CI leg drives exactly that swap.
pub fn fclonefileat(srcfd: c_int, dst_dirfd: c_int, dst: [*:0]const u8, flags: u32) callconv(.c) c_int {
    common.note1(.write, dst_dirfd, dst);
    return common.callFclonefileat(srcfd, dst_dirfd, dst, flags);
}

// The rename extensions. `RENAME_EXCL` (0x4) declines to clobber — `RENAME_NOREPLACE`'s
// relative, a plain rename, recorded. `RENAME_SWAP` (0x2) exchanges two files
// atomically, which the restore model cannot reproduce; on Linux the ORACLE refuses
// its relative (`renameat2(RENAME_EXCHANGE)`), scope-gated, and this platform has no
// oracle — so the shim itself writes the scope-gated refusal record. The numeric
// values collide with Linux's pair while the meanings do not (common.zig's constants
// carry the warning).

pub fn renamex_np(old: [*:0]const u8, new: [*:0]const u8, flags: c_uint) callconv(.c) c_int {
    if (flags & common.DARWIN_RENAME_SWAP != 0)
        common.noteUnsupportedInScope2("renamex_np(RENAME_SWAP)", AT_FDCWD, old, AT_FDCWD, new)
    else
        common.note2(.rename, AT_FDCWD, old, AT_FDCWD, new);
    return common.callRenamexNp(old, new, flags);
}

pub fn renameatx_np(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8, flags: c_uint) callconv(.c) c_int {
    if (flags & common.DARWIN_RENAME_SWAP != 0)
        common.noteUnsupportedInScope2("renameatx_np(RENAME_SWAP)", olddirfd, old, newdirfd, new)
    else
        common.note2(.rename, olddirfd, old, newdirfd, new);
    return common.callRenameatxNp(olddirfd, old, newdirfd, new, flags);
}

/// Always the refusal: there is no flag under which an atomic contents swap fits the
/// model. Scope-gated like the rest — swapping two files outside the state directory
/// is none of this tool's business.
pub fn exchangedata(p1: [*:0]const u8, p2: [*:0]const u8, opts: c_uint) callconv(.c) c_int {
    common.noteUnsupportedInScope2("exchangedata", AT_FDCWD, p1, AT_FDCWD, p2);
    return common.callExchangedata(p1, p2, opts);
}

/// The one bit that turns a metadata call into a rename. `struct attrlist` is
/// fixed-layout: `bitmapcount` u16, `reserved` u16, then `commonattr` u32 at offset 4.
/// Everything else this family sets (xattrs, ACLs, times) falls under the report's
/// standing "metadata is not observable" declaration and records nothing.
fn attrlistRenames(al: *anyopaque) bool {
    const b: [*]const u8 = @ptrCast(al);
    const common_attr = std.mem.bytesToValue(u32, b[4..8]);
    return common_attr & common.ATTR_CMN_NAME != 0;
}

pub fn setattrlist(path: [*:0]const u8, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: c_ulong) callconv(.c) c_int {
    if (attrlistRenames(al))
        common.noteUnsupportedInScope2("setattrlist(ATTR_CMN_NAME)", AT_FDCWD, path, AT_FDCWD, null);
    return common.callSetattrlist(path, al, buf, n, opts);
}

pub fn fsetattrlist(fd: c_int, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: c_ulong) callconv(.c) c_int {
    if (attrlistRenames(al))
        common.noteUnsupportedInScopeFd("fsetattrlist(ATTR_CMN_NAME)", fd);
    return common.callFsetattrlist(fd, al, buf, n, opts);
}

pub fn setattrlistat(dirfd: c_int, path: [*:0]const u8, al: *anyopaque, buf: ?*anyopaque, n: usize, opts: u32) callconv(.c) c_int {
    if (attrlistRenames(al))
        common.noteUnsupportedInScope2("setattrlistat(ATTR_CMN_NAME)", dirfd, path, dirfd, null);
    return common.callSetattrlistat(dirfd, path, al, buf, n, opts);
}

/// The open variant libcopyfile imports beside plain `open`: the same flag word in
/// argument 1, two protection arguments in between, mode variadic — read only when
/// O_CREAT asks for it, exactly as the `open` wrapper above does.
pub fn open_dprotected_np(path: [*:0]const u8, flags: c_int, class: c_int, dpflags: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
    if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, path);
    return common.callOpenDprotectedNp(path, flags, class, dpflags, mode);
}

/// The guarded-descriptor family (#299). `/usr/lib/libsqlite3.dylib` imports FIVE of
/// the six — every one but `guarded_writev_np` — and not weakly (measured with
/// `dyld_info -imports`, with a positive control: `libobjc.A.dylib` shows a weak row,
/// so an absent marker means something). The sixth is here because the unit is the
/// family: interposing the opens and leaving a writer out would make the account
/// silent about writes on a descriptor it did report. Until now the shim saw none: a
/// guarded open created a file the account never mentioned, and with any other recorded
/// mutation present the run PASSed. That is the #333 shape one family over — and worse
/// on the default path, where the shim is the only observer there is.
///
/// Each notes what its unguarded twin notes. The guard changes who may touch the
/// descriptor, not what the call does to the file.
pub fn guarded_open_np(path: [*:0]const u8, guard: *const u64, gflags: c_uint, flags: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
    if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, path);
    return common.callGuardedOpenNp(path, guard, gflags, flags, mode);
}

pub fn guarded_open_dprotected_np(path: [*:0]const u8, guard: *const u64, gflags: c_uint, flags: c_int, class: c_int, dpflags: c_int, ...) callconv(.c) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    const mode: c_uint = if (flags & common.O_CREAT != 0) @cVaArg(&ap, c_uint) else 0;
    if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, path);
    return common.callGuardedOpenDprotectedNp(path, guard, gflags, flags, class, dpflags, mode);
}

pub fn guarded_write_np(fd: c_int, guard: *const u64, buf: [*]const u8, count: usize) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callGuardedWriteNp(fd, guard, buf, count);
}

pub fn guarded_pwrite_np(fd: c_int, guard: *const u64, buf: [*]const u8, count: usize, offset: i64) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callGuardedPwriteNp(fd, guard, buf, count, offset);
}

pub fn guarded_writev_np(fd: c_int, guard: *const u64, iov: *const anyopaque, iovcnt: c_int) callconv(.c) isize {
    common.noteFd(.write, fd);
    return common.callGuardedWritevNp(fd, guard, iov, iovcnt);
}

/// Not a state change, and here for two reasons that are not about state. `classOf`
/// maps it to `.close`, so the promise this check makes requires it. And it has to
/// reach `noteTraceClose`, which is how the shim notices a target retiring the trace
/// descriptor itself — SQLite closes guarded descriptors with this and *cannot* fall
/// back to `close`, because the guard fires. (There is no descriptor ledger to keep
/// in step: `noteFd` asks the kernel where a descriptor points every time.)
pub fn guarded_close_np(fd: c_int, guard: *const u64) callconv(.c) c_int {
    common.noteFd(.close, fd);
    common.noteTraceClose(fd);
    return common.callGuardedCloseNp(fd, guard);
}

// --- kill-point ops: unlink ------------------------------------------------------

pub fn unlink(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.unlink, AT_FDCWD, path);
    return common.callUnlink(path);
}

pub fn unlinkat(dirfd: c_int, path: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    // AT_REMOVEDIR makes this an rmdir; report it as what it does. The constant differs
    // between platforms, which is why it is not spelled inline here.
    const op: contract.OpClass = if (flags & common.AT_REMOVEDIR != 0) .rmdir else .unlink;
    common.note1(op, dirfd, path);
    return common.callUnlinkat(dirfd, path, flags);
}

/// remove(3) is unlink-then-rmdir *inside* libc, and neither inner call crosses the
/// PLT (the timewarrior wall — its AtomicFile cleanup removes every registered temp
/// name at exit, created or not). Interposing it and forwarding to the real remove
/// would keep the shim blind, so the wrapper reimplements the documented two-step
/// through the wrappers above: each attempt is recorded before it runs, which is both
/// the kill-point convention and the attempt-by-attempt account strace hands the
/// oracle — a failed attempt counts on both sides or the two accounts desync. The
/// fall-through errno is each platform's own: glibc retries a directory on EISDIR,
/// Apple's BSD libc on EPERM — faithful to what the replaced function did, including
/// the EPERM-on-a-protected-file wart.
pub fn remove(path: [*:0]const u8) callconv(.c) c_int {
    const r = unlink(path);
    if (r == 0) return r;
    const fall_through: c_int = if (builtin.os.tag == .macos) 1 else 21; // EPERM : EISDIR
    if (std.c._errno().* != fall_through) return r;
    return rmdir(path);
}

// --- kill-point ops: the temp-name creators (#39) ---------------------------------
//
// `mkstemp` and its three variants open from inside libc, and `mkdtemp` makes its
// directory from inside libc; neither inner call crosses the PLT, so a shim that
// replaces only `open` and `mkdir` records nothing for them. Measured twice: on
// 2026-08-22 (`spike/cohort4/mkstemp-class.txt`) and again for this change. Forwarding
// to the real function would keep the shim blind, so — the same discipline as `remove`
// above — each wrapper reimplements the documented sequence through the recorded
// wrappers, one recorded attempt per name tried, which is the attempt-by-attempt
// account strace hands the oracle.
//
// What the real ones issue, measured on glibc 2.36/aarch64 rather than recalled:
// every member of the mkstemp family issues exactly
// `openat(AT_FDCWD, path, O_RDWR|O_CREAT|O_EXCL, 0600)` — plus the caller's extra
// flags for the `mkostemp*` pair — and `mkdtemp` issues
// `mkdirat(AT_FDCWD, path, 0700)`. Both spellings arrive here through `callOpen` and
// `callMkdir`, which reach the same kernel entry points.
//
// Two members of the same class are deliberately NOT here, and the record says why:
//
//   `dprintf`/`vdprintf` — glibc splits a large write at 8192 bytes (measured, same
//   run). A wrapper writing once would delete a crash point the real program has;
//   one that split would hard-code an undocumented libc constant that differs by
//   platform. They stay a wall.
//
//   `tmpfile` — **and here the two platforms disagree about whether it is even a
//   member.** glibc reaches it through `openat(AT_FDCWD, "/tmp", O_TMPFILE)`
//   (measured), which creates no directory entry anywhere and ignores TMPDIR, so on
//   Linux it cannot mutate a state directory. Apple's honours TMPDIR and creates a
//   real named file it then unlinks (measured with `F_GETPATH`: nlink 0, path inside
//   the directory TMPDIR named), so on macOS it IS a member and IS a wall. Taking it
//   would mean choosing one of the two behaviours for both, which is the thing this
//   file refuses to do.

// **The two platforms disagree about both halves of this contract**, measured on
// 2026-08-31 rather than read, because a wrapper that reproduces one of them on both
// does not add an observation — it changes what the target does.
//
//   flags     glibc CLEARS the access mode out of the caller's flags:
//             `mkostemp(t, O_WRONLY|O_APPEND)` reaches the kernel as
//             `O_RDWR|O_CREAT|O_EXCL|O_APPEND`. Apple's REJECTS anything outside
//             {O_APPEND, O_CLOEXEC, O_SHLOCK, O_EXLOCK} with EINVAL — **`O_RDWR`
//             included** — so "mask the access mode" is not a portable fix, it is
//             the glibc rule wearing a portable name.
//
//   template  glibc requires the last six characters before the suffix to be `X` and
//             replaces exactly those six; a longer run keeps its leading X's
//             (`c.XXXXXXXX` → `c.XXrZr5DH`) and anything shorter is EINVAL. Apple
//             replaces the WHOLE trailing run however long (`b.XXXXX` → `b.mPwbp`,
//             `c.XXXXXXXX` → `c.M9gSd4XP`), and a template with no trailing X is not
//             an error there — it is used literally (`d.XXXXXXn` comes back
//             unchanged, `e.noX` becomes `e.noj`).

const is_darwin = builtin.os.tag == .macos;

const temp_letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

/// glibc's TMP_MAX, and the ceiling on Darwin too. The bound only decides how long a
/// *collision* is retried; O_EXCL and mkdir's own exclusivity are what make a
/// collision a retry rather than a wrong answer, exactly as they do in libc.
const temp_attempts: u32 = 62 * 62 * 62;

/// Flags `mkostemp`/`mkostemps` accept on Darwin. Values read from the SDK header and
/// confirmed by running each one: `O_APPEND` 0x8, `O_CLOEXEC` 0x1000000,
/// `O_SHLOCK` 0x10, `O_EXLOCK` 0x20.
const darwin_ostemp_flags: c_int = 0x8 | 0x1000000 | 0x10 | 0x20;

var temp_seq: u64 = 0;

/// The run of `X`s a replacement is allowed to fill. `len` may be zero, which is legal
/// on Darwin and means the template is used as it stands.
const TempSlot = struct { at: [*]u8, len: usize };

/// Fill the slot with a name unlikely to collide.
///
/// Deliberately not `arc4random_buf`: it reached glibc only in 2.36 and this
/// repository pins no glibc floor (#161), so depending on it would narrow where the
/// shim loads. Deliberately not `std.crypto.random`: it does not exist in the Zig this
/// builds with. And deliberately **not the address of a stack variable**, which the
/// first version mixed in — glibc's own `tempname.c` avoids address entropy precisely
/// because the result is published as a filename, and six characters derived from a
/// stack address narrow the ASLR search for anyone who can read the directory. The
/// mix is time, pid and a counter, which is what libc did before `getrandom`: the pid
/// separates a forked child (which inherits both the counter and the layout), the
/// counter separates calls within a process, and the clock separates runs.
fn fillTempName(slot: TempSlot) void {
    if (slot.len == 0) return;
    temp_seq +%= 1;
    var x: u64 = @bitCast(common.c.time(null));
    x ^= @as(u64, @bitCast(@as(i64, common.c.getpid()))) *% 0x9E3779B97F4A7C15;
    x ^= temp_seq *% 0xBF58476D1CE4E5B9;
    for (0..slot.len) |i| {
        x ^= x >> 30;
        x *%= 0xBF58476D1CE4E5B9;
        x ^= x >> 27;
        x *%= 0x94D049BB133111EB;
        x ^= x >> 31;
        slot.at[i] = temp_letters[@intCast(x % temp_letters.len)];
    }
}

/// The caller's extra flags as the real function would take them, or null for EINVAL.
fn tempFlags(extra: c_int) ?c_int {
    if (is_darwin) {
        if (extra & ~darwin_ostemp_flags != 0) return null;
        return extra;
    }
    return extra & ~common.O_ACCMODE;
}

/// The `X` run this platform's libc would fill, or null for EINVAL.
fn tempSlot(template: [*:0]u8, suffixlen: c_int) ?TempSlot {
    if (suffixlen < 0) return null;
    const suffix: usize = @intCast(suffixlen);
    const len = std.mem.len(template);
    if (len < suffix) return null;
    const end = len - suffix;
    if (is_darwin) {
        var n: usize = 0;
        while (n < end and template[end - 1 - n] == 'X') n += 1;
        return .{ .at = template + (end - n), .len = n };
    }
    if (end < 6) return null;
    for (0..6) |i| if (template[end - 6 + i] != 'X') return null;
    return .{ .at = template + (end - 6), .len = 6 };
}

/// How many names there are to try. A short run has fewer than TMP_MAX candidates and
/// an empty one has exactly the template itself, so retrying either to the ceiling
/// would spin on names already refused.
fn tempAttempts(n: usize) u32 {
    if (n == 0) return 1;
    if (n >= 3) return temp_attempts;
    var space: u32 = 1;
    for (0..n) |_| space *= 62;
    return space;
}

/// EEXIST and EINVAL are 17 and 22 on both platforms (checked, not recalled — the
/// pair `remove` had to branch on, EISDIR/EPERM, is the reminder that agreement is
/// not the rule here).
const EEXIST: c_int = 17;
const EINVAL: c_int = 22;

fn mkstempImpl(template: [*:0]u8, suffixlen: c_int, extra_flags: c_int) c_int {
    const extra = tempFlags(extra_flags) orelse {
        std.c._errno().* = EINVAL;
        return -1;
    };
    const slot = tempSlot(template, suffixlen) orelse {
        std.c._errno().* = EINVAL;
        return -1;
    };
    const flags = common.O_RDWR | common.O_CREAT | common.O_EXCL | extra;
    for (0..tempAttempts(slot.len)) |_| {
        fillTempName(slot);
        // Recorded the way `open` records it, and before the call like every kill
        // point: a failed attempt counts on both sides or the accounts desync.
        if (common.openIsWriteCapable(flags)) common.note1(.open, AT_FDCWD, template);
        const fd = common.callOpen(template, flags, 0o600);
        if (fd >= 0) return fd;
        if (std.c._errno().* != EEXIST) return -1;
    }
    std.c._errno().* = EEXIST;
    return -1;
}

pub fn mkstemp(template: [*:0]u8) callconv(.c) c_int {
    return mkstempImpl(template, 0, 0);
}

pub fn mkostemp(template: [*:0]u8, flags: c_int) callconv(.c) c_int {
    return mkstempImpl(template, 0, flags);
}

pub fn mkstemps(template: [*:0]u8, suffixlen: c_int) callconv(.c) c_int {
    return mkstempImpl(template, suffixlen, 0);
}

pub fn mkostemps(template: [*:0]u8, suffixlen: c_int, flags: c_int) callconv(.c) c_int {
    return mkstempImpl(template, suffixlen, flags);
}

pub fn mkdtemp(template: [*:0]u8) callconv(.c) ?[*:0]u8 {
    const slot = tempSlot(template, 0) orelse {
        std.c._errno().* = EINVAL;
        return null;
    };
    for (0..tempAttempts(slot.len)) |_| {
        fillTempName(slot);
        common.note1(.mkdir, AT_FDCWD, template);
        if (common.callMkdir(template, 0o700) == 0) return template;
        if (std.c._errno().* != EEXIST) return null;
    }
    std.c._errno().* = EEXIST;
    return null;
}

// --- kill-point ops: link --------------------------------------------------------
//
// A second name for an inode changes the tree, so link is a kill point and a mutation
// (ADR 0006). Recorded before the call like every kill point, and with the same old,new
// orientation as rename (path = old, aux = new); scope is "either endpoint inside the
// state directory", decided in observe, so the record order carries no correctness
// weight of its own.

pub fn link(old: [*:0]const u8, new: [*:0]const u8) callconv(.c) c_int {
    common.note2(.link, AT_FDCWD, old, AT_FDCWD, new);
    return common.callLink(old, new);
}

pub fn linkat(olddirfd: c_int, old: [*:0]const u8, newdirfd: c_int, new: [*:0]const u8, flags: c_int) callconv(.c) c_int {
    // AT_EMPTY_PATH links the descriptor `olddirfd` itself; the old path is empty and
    // names nothing to resolve, so the operation is recorded as unplaceable.
    if (old[0] == 0) {
        common.noteLinkByDescriptor();
    } else {
        common.note2(.link, olddirfd, old, newdirfd, new);
    }
    return common.callLinkat(olddirfd, old, newdirfd, new, flags);
}

// --- kill-point ops: symlink -------------------------------------------------------
//
// Creating a symbolic link writes a directory entry, so it is a kill point and a
// mutation — the same nature as link (#122, contract v9). Only the LINK PATH is
// resolved and recorded; the target string is content the subject chose, not a path
// this run touches, and resolving it would let a link whose content spells the state
// directory be mis-scoped. The oracle applies the same exclusion textually
// (src/oracle.zig's path table lists only the link-path argument for both forms).

pub fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) callconv(.c) c_int {
    common.note1(.symlink, AT_FDCWD, linkpath);
    return common.callSymlink(target, linkpath);
}

pub fn symlinkat(target: [*:0]const u8, newdirfd: c_int, linkpath: [*:0]const u8) callconv(.c) c_int {
    common.note1(.symlink, newdirfd, linkpath);
    return common.callSymlinkat(target, newdirfd, linkpath);
}

// --- kill-point ops: sync and truncate -------------------------------------------

pub fn fsync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    return common.callFsync(fd);
}

pub fn fdatasync(fd: c_int) callconv(.c) c_int {
    common.noteFd(.fsync, fd);
    return common.callFdatasync(fd);
}

pub fn ftruncate(fd: c_int, length: i64) callconv(.c) c_int {
    common.noteFd(.truncate, fd);
    return common.callFtruncate(fd, length);
}

pub fn truncate(path: [*:0]const u8, length: i64) callconv(.c) c_int {
    common.note1(.truncate, AT_FDCWD, path);
    return common.callTruncate(path, length);
}

// --- kill-point ops: directories -------------------------------------------------

pub fn mkdir(path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, AT_FDCWD, path);
    return common.callMkdir(path, mode);
}

pub fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: c_uint) callconv(.c) c_int {
    common.note1(.mkdir, dirfd, path);
    return common.callMkdirat(dirfd, path, mode);
}

pub fn rmdir(path: [*:0]const u8) callconv(.c) c_int {
    common.note1(.rmdir, AT_FDCWD, path);
    return common.callRmdir(path);
}

// --- lifecycle -------------------------------------------------------------------

pub fn close(fd: c_int) callconv(.c) c_int {
    // Recorded before the call: afterwards the descriptor no longer resolves to a path.
    common.noteFd(.close, fd);
    // The target may be retiring the shim's own trace descriptor; that has to be
    // noticed while the descriptor still works (see noteTraceClose).
    common.noteTraceClose(fd);
    return common.callClose(fd);
}

// --- stdio, at flush granularity (ADR 0005) ----------------------------------------
//
// Libc-internal calls never cross the PLT, so interposing `write` says nothing about
// `fprintf` — measured as the whole of taskwarrior's data writes and the two operations
// that cost git its run (#30). These wrappers observe the one place where stdio
// granularity and syscall granularity coincide: the flush of pending bytes, which is
// normally exactly one write(2), because a buffer cannot hold more than its own size.
//
// What bypasses the flush path — a large fwrite going direct, an overflow flush inside
// fprintf, fflush(NULL), the exit-time cleanup of never-closed streams — is deliberately
// unrecorded. Where an oracle exists those writes surface as a divergence and the run
// refuses, exactly as it did before this file knew stdio existed; the class just got
// much smaller. Recording happens before the call, like every wrapper here, so a kill
// lands *before* the flush and the crash world loses the unflushed buffer — which is
// what a real crash loses.

pub fn fopen(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*common.FILE {
    if (common.stdioActive() and common.modeIsWriteCapable(mode))
        common.note1(.open, AT_FDCWD, path);
    return common.callFopen(path, mode);
}

pub fn fopen64(path: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*common.FILE {
    if (common.stdioActive() and common.modeIsWriteCapable(mode))
        common.note1(.open, AT_FDCWD, path);
    return common.callFopen64(path, mode);
}

pub fn fflush(stream: ?*common.FILE) callconv(.c) c_int {
    // fflush(NULL) flushes every open stream and nothing can enumerate them; it stays
    // unrecorded and lands in the oracle's net (ADR 0005).
    if (stream) |s| common.noteStdioFlush(s);
    return common.callFflush(stream);
}

pub fn fflush_unlocked(stream: ?*common.FILE) callconv(.c) c_int {
    if (stream) |s| common.noteStdioFlush(s);
    return common.callFflushUnlocked(stream);
}

pub fn fclose(stream: *common.FILE) callconv(.c) c_int {
    // The pending write first, then the close — the order of the syscalls fclose is
    // about to issue. Both resolved before the call: afterwards the descriptor is gone.
    common.noteStdioFlush(stream);
    common.noteStdioClose(stream);
    // Unconditional, unlike the stdio notes above: fdopen(N) + fclose retires the
    // descriptor whether or not stdio observation is armed.
    common.noteTraceClose(common.c.fileno(stream));
    return common.callFclose(stream);
}

// freopen issues [flush-write, close, open]. Recording all three and only then calling
// the real function would let a kill aimed at the `.open` land before *any* of them —
// a world whose address claims the write and close already happened (review finding).
// So the wrapper flushes explicitly first: record `.write`, perform the real fflush,
// then record `.close` and `.open`, then call freopen — whose own flush is now empty.
// The oracle's sequence is unchanged, and every address is honest: a kill at `.close`
// or `.open` lands with the flush durable, and dying before or after the actual
// close(2) leaves the same bytes on disk (ADR 0003), so the remaining gap is
// disk-neutral. freopen(NULL, …) reopens the same file through a path this wrapper
// cannot see; that open stays unrecorded and falls into the oracle's net (ADR 0005).
fn freopenCommon(comptime call64: bool, path: ?[*:0]const u8, mode: [*:0]const u8, stream: *common.FILE) ?*common.FILE {
    if (common.stdioHasPending(stream)) {
        common.noteStdioFlush(stream);
        _ = common.callFflush(stream);
    }
    common.noteStdioClose(stream);
    common.noteTraceClose(common.c.fileno(stream));
    if (path) |p| {
        if (common.stdioActive() and common.modeIsWriteCapable(mode))
            common.note1(.open, AT_FDCWD, p);
    }
    return if (call64) common.callFreopen64(path, mode, stream) else common.callFreopen(path, mode, stream);
}

pub fn freopen(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *common.FILE) callconv(.c) ?*common.FILE {
    return freopenCommon(false, path, mode, stream);
}

pub fn freopen64(path: ?[*:0]const u8, mode: [*:0]const u8, stream: *common.FILE) callconv(.c) ?*common.FILE {
    return freopenCommon(true, path, mode, stream);
}

// Repositioning a dirty stream flushes it as a side effect — libc issues the write
// internally before moving the position. Measured on the second real target:
// taskwarrior updates pending.data through an "r+" stream and its data write reaches
// the disk inside an fseek, not inside any fflush. Same rule as everywhere above:
// record iff bytes are pending, before the call.

pub fn fseek(stream: *common.FILE, off: c_long, whence: c_int) callconv(.c) c_int {
    common.noteStdioFlush(stream);
    return common.callFseek(stream, off, whence);
}

pub fn fseeko(stream: *common.FILE, off: i64, whence: c_int) callconv(.c) c_int {
    common.noteStdioFlush(stream);
    return common.callFseeko(stream, off, whence);
}

pub fn fseeko64(stream: *common.FILE, off: i64, whence: c_int) callconv(.c) c_int {
    common.noteStdioFlush(stream);
    return common.callFseeko64(stream, off, whence);
}

pub fn rewind(stream: *common.FILE) callconv(.c) void {
    common.noteStdioFlush(stream);
    return common.callRewind(stream);
}

pub fn fsetpos(stream: *common.FILE, pos: *const anyopaque) callconv(.c) c_int {
    common.noteStdioFlush(stream);
    return common.callFsetpos(stream, pos);
}

pub fn fsetpos64(stream: *common.FILE, pos: *const anyopaque) callconv(.c) c_int {
    common.noteStdioFlush(stream);
    return common.callFsetpos64(stream, pos);
}

// --- boundary detectors ----------------------------------------------------------
//
// These do not make the operation fail; they record that the run crossed a process
// boundary. Whether that is tolerable is the engine's decision, not this file's.
//
// Recorded *after* the call succeeds, except where noted. The old pre-call records
// meant a failed fork — no child anywhere — read exactly like a real one, and the
// difference between those is the difference between a refusal and a verdict.
//
// `clone`, `clone3` and a raw `syscall(SYS_clone, …)` bypass this file entirely.
// That gap is why the recording run is compared against an external oracle where one
// exists, and why the engine carries detectors that do not depend on interposition.

pub fn fork() callconv(.c) c_int {
    const rc = common.callFork();
    // Parent only. The child's rc is 0 and its operations carry its own pid; recording
    // the boundary twice would claim two forks happened.
    if (rc > 0) common.noteBoundary(.fork);
    return rc;
}

/// The one wrapper that must not have a stack frame at the moment it calls the real
/// function — enforced by the `.always_tail` below, which is a compile error on any
/// target where the backend cannot guarantee it.
///
/// A `vfork` child runs on the parent's stack while the parent is suspended, and the call
/// returns twice. An ordinary wrapper's frame spans that double return: the child pops
/// the frame on its way back to the target, runs, and overwrites the memory it occupied —
/// including the saved frame pointer and return address the *parent's* return path will
/// restore. Measured, with the control that settles where the fault is:
///
///   vfork+exec of /bin/true, glibc 2.36 aarch64:   exit 0   without the shim
///                                                  exit 127 with an ordinary wrapper
///                                                  exit 127 with the shim loaded but
///                                                           *inactive* (recording nothing)
///
/// The inactive case is the proof: no recording happened, so the corruption is the frame
/// itself. The parent resumed through clobbered saved registers into the child's branch
/// and exited 127 with no output — silently wrong control flow, not a crash. sideeye then
/// blamed the corpse: `recording_run_failed`, for a death it caused. glibc's own `vfork`
/// is hand-written frameless assembly for exactly this reason.
///
/// The shim needs nothing *after* vfork returns, so the frame does not need to exist:
/// record the boundary first (an ordinary call, safely before the fork), then tail-jump.
/// At the jump the stack is exactly as if the target had called `vfork` directly, and
/// both returns land in the target without touching this function again.
///
/// Why the other process-creating wrappers do not need this: a `fork` child runs on a
/// *copy* of the stack, and glibc's `posix_spawn` gives its `CLONE_VM|CLONE_VFORK` child
/// a freshly mmap'd stack — measured as the reason spawn survived an ordinary wrapper
/// while vfork did not. Only `vfork` shares the parent's.
pub fn vfork() callconv(.c) c_int {
    // The one boundary still recorded before the call: there is no frame afterwards to
    // record from. The cost is that a failed vfork leaves a fork record with no child —
    // the engine reads that as a boundary and refuses, which errs toward UNKNOWN.
    common.noteBoundary(.fork);
    const real_vfork = common.realVfork() orelse return -1;
    return @call(.always_tail, real_vfork, .{});
}

// Exec keeps the pre-call record: on success there is no "after" in the same image to
// record from, and on failure the extra record errs toward refusal. The subject also
// carries its operation count into the new image (#123) — see callExecveSeqCarry and
// execSeqCarrySet for who may carry and why the storage is what it is.
pub fn execve(path: [*:0]const u8, argv: [*]const ?[*:0]const u8, envp: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    return common.callExecveSeqCarry(path, argv, envp);
}

pub fn execv(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const carried = common.execSeqCarrySet();
    const rc = common.callExecv(path, argv);
    if (carried) {
        // Faithful errno, same discipline as `remove`: the unset between the failed
        // exec and the return must not overwrite what exec set (POSIX allows
        // unsetenv to touch errno; glibc/aarch64 measured not to, musl and darwin
        // unmeasured — so it is saved rather than assumed).
        const saved = std.c._errno().*;
        common.execSeqCarryUnset();
        std.c._errno().* = saved;
    }
    return rc;
}

pub fn execvp(file: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.c) c_int {
    common.noteBoundary(.exec);
    const carried = common.execSeqCarrySet();
    const rc = common.callExecvp(file, argv);
    if (carried) {
        const saved = std.c._errno().*;
        common.execSeqCarryUnset();
        std.c._errno().* = saved;
    }
    return rc;
}

// Through v2 these recorded `.fork`, which is wrong in kind: the child is a new process
// *and* a new image. The misclassification was harmless while both were refused, and
// stops being harmless the moment the engine treats them differently.
pub fn posix_spawn(
    pid: ?*anyopaque,
    path: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    const rc = common.callPosixSpawn(pid, path, file_actions, attrp, argv, envp);
    if (rc == 0) common.noteBoundary(.spawn);
    return rc;
}

pub fn posix_spawnp(
    pid: ?*anyopaque,
    file: [*:0]const u8,
    file_actions: ?*const anyopaque,
    attrp: ?*const anyopaque,
    argv: [*]const ?[*:0]const u8,
    envp: [*]const ?[*:0]const u8,
) callconv(.c) c_int {
    const rc = common.callPosixSpawnp(pid, file, file_actions, attrp, argv, envp);
    if (rc == 0) common.noteBoundary(.spawn);
    return rc;
}

pub fn pthread_create(
    thread: *anyopaque,
    attr: ?*const anyopaque,
    start_routine: *const anyopaque,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    const rc = common.callPthreadCreate(thread, attr, start_routine, arg);
    if (rc == 0) common.noteBoundary(.thread);
    return rc;
}

// --- containment escapes -----------------------------------------------------------
//
// The engine confines the target by putting it in its own process group and killing the
// group. A process that leaves the group is one the engine can no longer claim to have
// stopped — so the departure itself is recorded, and the engine refuses rather than
// pretends.

pub fn setsid() callconv(.c) c_int {
    const rc = common.callSetsid();
    // setsid fails for a process that is already a group leader, and the engine makes
    // the direct child exactly that — so a successful setsid can only have come from a
    // descendant, which is precisely the process that just escaped.
    if (rc >= 0) common.noteBoundary(.detached);
    return rc;
}

pub fn setpgid(pid: c_int, pgid: c_int) callconv(.c) c_int {
    // A call that changes nothing is not an escape. The direct child is already its
    // own group leader (the engine made it so), and a target calling setpgid(0, 0) in
    // that position — shells do — must not be refused for it. The same courtesy goes
    // to a call aimed at another process: only a group that actually changed counts.
    const subject = if (pid == 0) common.c.getpid() else pid;
    const before = common.c.getpgid(subject);
    const rc = common.callSetpgid(pid, pgid);
    if (rc == 0 and common.c.getpgid(subject) != before)
        common.noteBoundary(.detached);
    return rc;
}
