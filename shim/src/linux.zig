//! Linux symbol installation.
//!
//! Under `LD_PRELOAD` the dynamic linker resolves a symbol to the first library that
//! defines it, so exporting these names means the target's calls land in `ops.zig`.
//! The real functions are reached through `dlsym(RTLD_NEXT, …)`, filled in by
//! `common.resolveAll()`.
//!
//! Several libc entry points are aliases that differ only in name — `open64` is `open`
//! on a 64-bit target, `pwrite64` is `pwrite`. They get the same replacement rather
//! than a wrapper each, so there is one body to keep correct.

const ops = @import("ops.zig");

comptime {
    @export(&ops.open, .{ .name = "open" });
    @export(&ops.open, .{ .name = "open64" });
    @export(&ops.openat, .{ .name = "openat" });
    @export(&ops.openat, .{ .name = "openat64" });
    @export(&ops.creat, .{ .name = "creat" });
    @export(&ops.creat, .{ .name = "creat64" });

    @export(&ops.write, .{ .name = "write" });
    @export(&ops.pwrite, .{ .name = "pwrite" });
    @export(&ops.pwrite, .{ .name = "pwrite64" });
    @export(&ops.writev, .{ .name = "writev" });

    @export(&ops.rename, .{ .name = "rename" });
    @export(&ops.renameat, .{ .name = "renameat" });

    @export(&ops.unlink, .{ .name = "unlink" });
    @export(&ops.unlinkat, .{ .name = "unlinkat" });

    @export(&ops.fsync, .{ .name = "fsync" });
    @export(&ops.fdatasync, .{ .name = "fdatasync" });

    @export(&ops.ftruncate, .{ .name = "ftruncate" });
    @export(&ops.ftruncate, .{ .name = "ftruncate64" });
    @export(&ops.truncate, .{ .name = "truncate" });
    @export(&ops.truncate, .{ .name = "truncate64" });

    @export(&ops.mkdir, .{ .name = "mkdir" });
    @export(&ops.mkdirat, .{ .name = "mkdirat" });
    @export(&ops.rmdir, .{ .name = "rmdir" });

    @export(&ops.close, .{ .name = "close" });

    @export(&ops.fork, .{ .name = "fork" });
    @export(&ops.vfork, .{ .name = "vfork" });
    @export(&ops.execve, .{ .name = "execve" });
    @export(&ops.execv, .{ .name = "execv" });
    @export(&ops.execvp, .{ .name = "execvp" });
    @export(&ops.posix_spawn, .{ .name = "posix_spawn" });
    @export(&ops.posix_spawnp, .{ .name = "posix_spawnp" });
    @export(&ops.pthread_create, .{ .name = "pthread_create" });
}
