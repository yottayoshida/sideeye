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
//! full-path account of the survey's toy, and it requires root — which a distributable
//! default cannot demand, but a caller can choose to pay: `--oracle-fs-usage` runs it
//! beside the recording and compares (ADR 0031). Without that flag the engine's
//! structural detectors carry completeness alone on this platform, and a PASS requires
//! the caller to say `--allow-unverified`.

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
    // One of #256's two macOS members: `pwritev` exists here (11.0+), `pwritev2`
    // does not, and `renameat2` is Linux's spelling of a call macOS names
    // `renameatx_np`. The other is `fdatasync`, below. Without an oracle on this
    // platform, a write the shim cannot see is invisible to everything, which is why
    // each of the two is worth taking on its own.
    entry(&ops.pwritev, libc.pwritev),
    entry(&ops.rename, libc.rename),
    entry(&ops.renameat, libc.renameat),
    // The rename extensions (v12). `renameatx_np` was NAMED in the comment above as
    // Linux `renameat2`'s macOS spelling when #256 closed the Linux half — named and
    // not taken, which is #333's shape in one line. `RENAME_EXCL` records as a plain
    // rename; `RENAME_SWAP` writes the scope-gated refusal the oracle would have
    // issued on Linux, because here there is no oracle to issue it.
    entry(&ops.renamex_np, libc.renamex_np),
    entry(&ops.renameatx_np, libc.renameatx_np),
    // The clone family (v12, #333): three separate kernel stubs, none covering the
    // others. Rust std's fs::copy reaches fclonefileat first; copyfile(COPYFILE_CLONE)
    // reaches clonefileat. Measured invisible before this table row: zero operations
    // recorded while a real file appeared with real content — and with any other
    // recorded mutation present, the run PASSed.
    entry(&ops.clonefile, libc.clonefile),
    entry(&ops.clonefileat, libc.clonefileat),
    entry(&ops.fclonefileat, libc.fclonefileat),
    // Refused in scope, never counted: an atomic contents swap has no place in the
    // restore model on either platform.
    entry(&ops.exchangedata, libc.exchangedata),
    // Metadata writers, except that ATTR_CMN_NAME renames — the one bit that turns
    // these into mutations of the tree the verdict reads.
    entry(&ops.setattrlist, libc.setattrlist),
    entry(&ops.fsetattrlist, libc.fsetattrlist),
    entry(&ops.setattrlistat, libc.setattrlistat),
    // The open variant libcopyfile imports beside plain open.
    entry(&ops.open_dprotected_np, libc.open_dprotected_np),
    // The guarded family (#299): SQLite's writers, invisible to this shim until now.
    entry(&ops.guarded_open_np, libc.guarded_open_np),
    entry(&ops.guarded_open_dprotected_np, libc.guarded_open_dprotected_np),
    entry(&ops.guarded_write_np, libc.guarded_write_np),
    entry(&ops.guarded_pwrite_np, libc.guarded_pwrite_np),
    entry(&ops.guarded_writev_np, libc.guarded_writev_np),
    entry(&ops.guarded_close_np, libc.guarded_close_np),
    entry(&ops.unlink, libc.unlink),
    entry(&ops.unlinkat, libc.unlinkat),
    entry(&ops.remove, libc.remove),
    entry(&ops.link, libc.link),
    entry(&ops.linkat, libc.linkat),
    entry(&ops.symlink, libc.symlink),
    entry(&ops.symlinkat, libc.symlinkat),
    entry(&ops.fsync, libc.fsync),
    // `fdatasync` was missing here while the oracle classified it and Linux exported
    // it — the same gap #256 closed on the other side, on the platform where it
    // costs more (no oracle to refuse what the shim cannot see).
    entry(&ops.fdatasync, libc.fdatasync),
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
    // The temp-name creators (#39). This is the edge dyld DOES rewrite — a target
    // calling libc directly — not the one it does not (libSystem calling its own
    // export, ADR 0005 and ADR 0034). So the same replacement closes the wall on both
    // platforms, which is why the reimplementation lives in ops.zig rather than in a
    // Linux-only branch.
    entry(&ops.mkstemp, libc.mkstemp),
    entry(&ops.mkostemp, libc.mkostemp),
    entry(&ops.mkstemps, libc.mkstemps),
    entry(&ops.mkostemps, libc.mkostemps),
    entry(&ops.mkdtemp, libc.mkdtemp),
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
