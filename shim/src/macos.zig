//! There is no `bindReal` here any more, and that absence is the point. Interposition
//! is live from the moment this library loads; a constructor runs much later. A pointer
//! table filled by that constructor is null for every call the system libraries make in
//! between — which is exactly what happened: `libxpc` reached the replacement before
//! `main`, found no original, and got -1 back. The replacements call the real functions
//! directly instead (see `darwin_libc.zig`).

const libc = @import("darwin_libc.zig");
const ops = @import("ops.zig");

const Interpose = extern struct {
    replacement: *const anyopaque,
    original: *const anyopaque,
};

fn entry(replacement: anytype, original: anytype) Interpose {
    return .{ .replacement = @ptrCast(replacement), .original = @ptrCast(original) };
}

export const sideeye_interposers linksection("__DATA,__interpose") = [_]Interpose{
    entry(&ops.open, libc.open),
    entry(&ops.openat, libc.openat),
    entry(&ops.creat, libc.creat),
    entry(&ops.write, libc.write),
    entry(&ops.pwrite, libc.pwrite),
    entry(&ops.writev, libc.writev),
    entry(&ops.pwritev, libc.pwritev),
    entry(&ops.rename, libc.rename),
    entry(&ops.renameat, libc.renameat),
    entry(&ops.renamex_np, libc.renamex_np),
    entry(&ops.renameatx_np, libc.renameatx_np),
    entry(&ops.clonefile, libc.clonefile),
    entry(&ops.clonefileat, libc.clonefileat),
    entry(&ops.fclonefileat, libc.fclonefileat),
    entry(&ops.exchangedata, libc.exchangedata),
    entry(&ops.mmap, libc.mmap),
    entry(&ops.mprotect, libc.mprotect),
    entry(&ops.setattrlist, libc.setattrlist),
    entry(&ops.fsetattrlist, libc.fsetattrlist),
    entry(&ops.setattrlistat, libc.setattrlistat),
    entry(&ops.open_dprotected_np, libc.open_dprotected_np),
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
    entry(&ops.fdatasync, libc.fdatasync),
    entry(&ops.fcntl, libc.fcntl),
    entry(&ops.close, libc.close),
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
    entry(&ops.mkstemp, libc.mkstemp),
    entry(&ops.mkostemp, libc.mkostemp),
    entry(&ops.mkstemps, libc.mkstemps),
    entry(&ops.mkostemps, libc.mkostemps),
    entry(&ops.mkdtemp, libc.mkdtemp),
    entry(&ops.fork, libc.fork),
    entry(&ops.vfork, libc.vfork),
    entry(&ops.execve, libc.execve),
    entry(&ops.execv, libc.execv),
    entry(&ops.execvp, libc.execvp),
    entry(&ops.posix_spawn, libc.posix_spawn),
    entry(&ops.posix_spawnp, libc.posix_spawnp),
    entry(&ops.pthread_create, libc.pthread_create),
    entry(&ops.pthread_join, libc.pthread_join),
    entry(&ops.pthread_detach, libc.pthread_detach),
    entry(&ops.setsid, libc.setsid),
    entry(&ops.setpgid, libc.setpgid),
};
