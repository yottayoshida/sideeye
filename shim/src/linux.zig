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
    // The vectored positional writes (#256). The oracle has classified these since
    // v0.1; only the export was missing, so a target using them was seen by one
    // observer and not the other. The `64` spellings are glibc's LFS aliases, taken
    // for the same reason `pwrite64` is above — a `_FILE_OFFSET_BITS=64` build
    // resolves to them and would otherwise walk straight past the shim.
    @export(&ops.pwritev, .{ .name = "pwritev" });
    @export(&ops.pwritev, .{ .name = "pwritev64" });
    @export(&ops.pwritev2, .{ .name = "pwritev2" });
    @export(&ops.pwritev2, .{ .name = "pwritev64v2" });

    // The kernel's copy primitives (#244). Linux only: macOS has no
    // `copy_file_range`, and its `sendfile` is a different call (file to socket,
    // arguments the other way round) that cannot write into a state directory.
    @export(&ops.copy_file_range, .{ .name = "copy_file_range" });
    @export(&ops.sendfile, .{ .name = "sendfile" });
    @export(&ops.sendfile, .{ .name = "sendfile64" });

    @export(&ops.rename, .{ .name = "rename" });
    @export(&ops.renameat, .{ .name = "renameat" });
    @export(&ops.renameat2, .{ .name = "renameat2" });

    @export(&ops.unlink, .{ .name = "unlink" });
    @export(&ops.unlinkat, .{ .name = "unlinkat" });
    @export(&ops.remove, .{ .name = "remove" });

    @export(&ops.link, .{ .name = "link" });
    @export(&ops.linkat, .{ .name = "linkat" });

    @export(&ops.symlink, .{ .name = "symlink" });
    @export(&ops.symlinkat, .{ .name = "symlinkat" });

    @export(&ops.fsync, .{ .name = "fsync" });
    @export(&ops.fdatasync, .{ .name = "fdatasync" });

    @export(&ops.ftruncate, .{ .name = "ftruncate" });
    @export(&ops.ftruncate, .{ .name = "ftruncate64" });
    @export(&ops.truncate, .{ .name = "truncate" });
    @export(&ops.truncate, .{ .name = "truncate64" });

    @export(&ops.mkdir, .{ .name = "mkdir" });
    @export(&ops.mkdirat, .{ .name = "mkdirat" });
    @export(&ops.rmdir, .{ .name = "rmdir" });

    // The temp-name creators (#39). Their creating call happens inside libc and never
    // reaches the wrappers above, so the replacements build it themselves. The `64`
    // spellings are glibc's LFS aliases — measured present as weak symbols at the same
    // addresses as the base names — taken for the same reason `pwrite64` is.
    @export(&ops.mkstemp, .{ .name = "mkstemp" });
    @export(&ops.mkstemp, .{ .name = "mkstemp64" });
    @export(&ops.mkostemp, .{ .name = "mkostemp" });
    @export(&ops.mkostemp, .{ .name = "mkostemp64" });
    @export(&ops.mkstemps, .{ .name = "mkstemps" });
    @export(&ops.mkstemps, .{ .name = "mkstemps64" });
    @export(&ops.mkostemps, .{ .name = "mkostemps" });
    @export(&ops.mkostemps, .{ .name = "mkostemps64" });
    @export(&ops.mkdtemp, .{ .name = "mkdtemp" });

    @export(&ops.close, .{ .name = "close" });

    // stdio, at flush granularity (ADR 0005). fdopen needs no wrapper: no syscall
    // happens there, and the descriptor's open was recorded by the raw wrappers.
    @export(&ops.fopen, .{ .name = "fopen" });
    @export(&ops.fopen64, .{ .name = "fopen64" });
    @export(&ops.freopen, .{ .name = "freopen" });
    @export(&ops.freopen64, .{ .name = "freopen64" });
    @export(&ops.fflush, .{ .name = "fflush" });
    @export(&ops.fflush_unlocked, .{ .name = "fflush_unlocked" });
    @export(&ops.fclose, .{ .name = "fclose" });
    // Repositioning flushes a dirty stream; the seek family are flush points too.
    @export(&ops.fseek, .{ .name = "fseek" });
    @export(&ops.fseeko, .{ .name = "fseeko" });
    @export(&ops.fseeko64, .{ .name = "fseeko64" });
    @export(&ops.rewind, .{ .name = "rewind" });
    @export(&ops.fsetpos, .{ .name = "fsetpos" });
    @export(&ops.fsetpos64, .{ .name = "fsetpos64" });

    @export(&ops.fork, .{ .name = "fork" });
    // `vfork` is the one replacement that must be frameless at the moment of the call;
    // its wrapper tail-jumps to the real function. See ops.zig for the measurements.
    @export(&ops.vfork, .{ .name = "vfork" });
    @export(&ops.execve, .{ .name = "execve" });
    @export(&ops.execv, .{ .name = "execv" });
    @export(&ops.execvp, .{ .name = "execvp" });
    @export(&ops.posix_spawn, .{ .name = "posix_spawn" });
    @export(&ops.posix_spawnp, .{ .name = "posix_spawnp" });
    @export(&ops.pthread_create, .{ .name = "pthread_create" });
    @export(&ops.setsid, .{ .name = "setsid" });
    @export(&ops.setpgid, .{ .name = "setpgid" });
}
