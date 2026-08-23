//! macOS symbol installation.
//!
//! dyld does not resolve by first-definition-wins the way `LD_PRELOAD` does. A library
//! declares pairs of (replacement, original) in a `__DATA,__interpose` section and dyld
//! rewrites calls that cross image boundaries.
//!
//! There is no `bindReal` here any more, and that absence is the point. Interposition
//! is live from the moment this library loads; a constructor runs much later. A pointer
//! table filled by that constructor is null for every call the system libraries make in
//! between — which is exactly what happened: `libxpc` reached the replacement before
//! `main`, found no original, and got -1 back. The replacements call the real functions
//! directly instead (see `darwin_libc.zig`).
//!
//! What is *not* available here is an unprivileged oracle (measured, #181,
//! spike/macos-oracle/): DTrace's syscall provider matches no probes under SIP even as
//! root, and `dtruss` — built on that provider — runs the target and exits 0 with no
//! syscall in its capture, which for an oracle is worse than a refusal. Of the
//! candidates measured there, only `fs_usage` produced an ordered, attributed,
//! full-path account of the survey's toy, and it requires root, which a distributable
//! default cannot demand. The engine's structural detectors carry completeness alone on
//! this platform, and a PASS requires the caller to say `--allow-unverified`.

const libc = @import("darwin_libc.zig");
const ops = @import("ops.zig");

const Interpose = extern struct {
    replacement: *const anyopaque,
    original: *const anyopaque,
};

fn entry(replacement: anytype, original: anytype) Interpose {
    return .{ .replacement = @ptrCast(replacement), .original = @ptrCast(original) };
}

/// `@intFromPtr` on a function address is not comptime-evaluable, so the table holds
/// pointers rather than integers.
export const sideeye_interposers linksection("__DATA,__interpose") = [_]Interpose{
    entry(&ops.open, libc.open),
    entry(&ops.openat, libc.openat),
    entry(&ops.creat, libc.creat),
    entry(&ops.write, libc.write),
    entry(&ops.pwrite, libc.pwrite),
    entry(&ops.writev, libc.writev),
    entry(&ops.rename, libc.rename),
    entry(&ops.renameat, libc.renameat),
    entry(&ops.unlink, libc.unlink),
    entry(&ops.unlinkat, libc.unlinkat),
    entry(&ops.remove, libc.remove),
    entry(&ops.link, libc.link),
    entry(&ops.linkat, libc.linkat),
    entry(&ops.symlink, libc.symlink),
    entry(&ops.symlinkat, libc.symlinkat),
    entry(&ops.fsync, libc.fsync),
    entry(&ops.close, libc.close),
    // stdio, at flush granularity (ADR 0005). No 64-bit variants or fflush_unlocked on
    // this platform; fdopen needs no wrapper (no syscall happens there).
    entry(&ops.fopen, libc.fopen),
    entry(&ops.freopen, libc.freopen),
    entry(&ops.fflush, libc.fflush),
    entry(&ops.fclose, libc.fclose),
    entry(&ops.fseek, libc.fseek),
    entry(&ops.fseeko, libc.fseeko),
    entry(&ops.rewind, libc.rewind),
    entry(&ops.fsetpos, libc.fsetpos),
    entry(&ops.ftruncate, libc.ftruncate),
    entry(&ops.truncate, libc.truncate),
    entry(&ops.mkdir, libc.mkdir),
    entry(&ops.mkdirat, libc.mkdirat),
    entry(&ops.rmdir, libc.rmdir),
    entry(&ops.fork, libc.fork),
    // The vfork replacement is frameless at the call — a guaranteed tail jump. See ops.zig.
    entry(&ops.vfork, libc.vfork),
    entry(&ops.execve, libc.execve),
    entry(&ops.execv, libc.execv),
    entry(&ops.execvp, libc.execvp),
    entry(&ops.posix_spawn, libc.posix_spawn),
    entry(&ops.posix_spawnp, libc.posix_spawnp),
    entry(&ops.pthread_create, libc.pthread_create),
    entry(&ops.setsid, libc.setsid),
    entry(&ops.setpgid, libc.setpgid),
};
