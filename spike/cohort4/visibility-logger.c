/*
 * visibility-logger.c — the second witness for probe condition 8.
 *
 * Cargo cost two defines and two explores to discover that its manifest's
 * atomic rename never passes through libc (spike/cohort3/cargo-r2/
 * raw-rename-diagnosis.txt). The engine found it, correctly, at the
 * recording run of the second revision — by which point the slot was
 * spent. This library asks the same question at probe time, before a
 * define exists: for every state-directory mutation the kernel performed,
 * did the call pass through a function an LD_PRELOAD shim can interpose?
 *
 * It interposes the path- and descriptor-mutating entry points the shim
 * exports, and records each call as one line
 *
 *     <class> <path-or-fd>
 *
 * on the descriptor named by SIDEEYE_VISLOG (default: stderr). Classes
 * are the engine's OpClass names (src/contract.zig), so the comparison
 * against strace is class-to-class rather than name-to-name — glibc
 * routes open() to openat(2) and rename() to renameat(2), and a
 * name-level comparison would call that a bypass.
 *
 * The log is written with syscall(SYS_write) on purpose: this library
 * interposes write(), and logging through it would recurse.
 *
 * The interposed set is the shim's own exported set, restricted to the
 * state-mutating entry points - taken from `nm -D` on the built shim, not
 * from memory. That includes the stdio flush family (fclose, fflush,
 * fseek, rewind and their variants): a buffered write reaches the kernel
 * through an internal libc call no PLT interposer can see, which is why
 * the shim exports those functions and why a logger without them would
 * report a false wall on any target that writes through stdio (#39's
 * class). Those emit a `write`, which can only over-count - and the
 * descriptor classes are a floor check (kernel <= interposer), so
 * over-counting costs precision, never a missed bypass.
 *
 * Not a shim, not a judge: it never blocks, never kills, never inspects
 * state. It answers one question, and the probe transcript records it.
 */

#define _GNU_SOURCE
#define _LARGEFILE64_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

static int log_fd = -1;

static void vislog_init(void) {
    if (log_fd >= 0) return;
    const char *path = getenv("SIDEEYE_VISLOG");
    if (path && *path) {
        /* Raw open: this library interposes the libc ones. */
        long fd = syscall(SYS_openat, AT_FDCWD, path,
                          O_WRONLY | O_CREAT | O_APPEND, 0644);
        log_fd = (fd < 0) ? 2 : (int)fd;
    } else {
        log_fd = 2;
    }
}

static void emit(const char *cls, const char *detail) {
    char buf[4096];
    size_t n = 0;
    vislog_init();
    const char *parts[4] = {"LOGGER ", cls, " ", detail ? detail : "(null)"};
    for (int i = 0; i < 4; i++) {
        size_t len = strlen(parts[i]);
        if (n + len >= sizeof(buf) - 2) break;
        memcpy(buf + n, parts[i], len);
        n += len;
    }
    buf[n++] = '\n';
    (void)syscall(SYS_write, log_fd, buf, n);
}

/* Resolve the descriptor to a path so the descriptor classes can be
 * compared path by path, like the others. Comparing them by count was
 * measured to be worse than useless: this library's own writes to stdout
 * inflate the count until a raw in-root write can no longer stand out.
 * /proc is Linux-only, and so is this gate. */
static void emit_fd(const char *cls, int fd) {
    char link[64];
    char target[3072];
    if (fd >= 0) {
        snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link, target, sizeof(target) - 1);
        if (n > 0) {
            target[n] = 0;
            emit(cls, target);
            return;
        }
    }
    snprintf(target, sizeof(target), "fd=%d", fd);
    emit(cls, target);
}

#define REAL(sym) \
    static typeof(sym) *real_##sym; \
    if (!real_##sym) real_##sym = (typeof(sym) *)dlsym(RTLD_NEXT, #sym);

/* ---- open family -> class "open" ---------------------------------- */

int open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap);
    }
    REAL(open)
    emit("open", path);
    return real_open(path, flags, mode);
}

int open64(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap);
    }
    REAL(open64)
    emit("open", path);
    return real_open64(path, flags, mode);
}

int openat(int dirfd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap);
    }
    REAL(openat)
    emit("open", path);
    return real_openat(dirfd, path, flags, mode);
}

int creat(const char *path, mode_t mode) {
    REAL(creat)
    emit("open", path);
    return real_creat(path, mode);
}

FILE *fopen(const char *path, const char *mode) {
    REAL(fopen)
    emit("open", path);
    return real_fopen(path, mode);
}

FILE *freopen(const char *path, const char *mode, FILE *stream) {
    REAL(freopen)
    emit("open", path);
    return real_freopen(path, mode, stream);
}

/* ---- rename family ------------------------------------------------ */

int rename(const char *from, const char *to) {
    REAL(rename)
    emit("rename", to);
    return real_rename(from, to);
}

int renameat(int fromfd, const char *from, int tofd, const char *to) {
    REAL(renameat)
    emit("rename", to);
    return real_renameat(fromfd, from, tofd, to);
}

/* ---- unlink family ------------------------------------------------ */

int unlink(const char *path) {
    REAL(unlink)
    emit("unlink", path);
    return real_unlink(path);
}

int unlinkat(int dirfd, const char *path, int flags) {
    REAL(unlinkat)
    emit(flags & AT_REMOVEDIR ? "rmdir" : "unlink", path);
    return real_unlinkat(dirfd, path, flags);
}

int remove(const char *path) {
    REAL(remove)
    emit("unlink", path);
    return real_remove(path);
}

/* ---- directory family --------------------------------------------- */

int mkdir(const char *path, mode_t mode) {
    REAL(mkdir)
    emit("mkdir", path);
    return real_mkdir(path, mode);
}

int mkdirat(int dirfd, const char *path, mode_t mode) {
    REAL(mkdirat)
    emit("mkdir", path);
    return real_mkdirat(dirfd, path, mode);
}

int rmdir(const char *path) {
    REAL(rmdir)
    emit("rmdir", path);
    return real_rmdir(path);
}

/* ---- link family --------------------------------------------------- */

int link(const char *from, const char *to) {
    REAL(link)
    emit("link", to);
    return real_link(from, to);
}

int linkat(int fromfd, const char *from, int tofd, const char *to, int flags) {
    REAL(linkat)
    emit("link", to);
    return real_linkat(fromfd, from, tofd, to, flags);
}

int symlink(const char *target, const char *path) {
    REAL(symlink)
    emit("symlink", path);
    return real_symlink(target, path);
}

int symlinkat(const char *target, int dirfd, const char *path) {
    REAL(symlinkat)
    emit("symlink", path);
    return real_symlinkat(target, dirfd, path);
}

/* ---- truncate family ----------------------------------------------- */

int truncate(const char *path, off_t length) {
    REAL(truncate)
    emit("truncate", path);
    return real_truncate(path, length);
}

int ftruncate(int fd, off_t length) {
    REAL(ftruncate)
    emit_fd("truncate", fd);
    return real_ftruncate(fd, length);
}

/* ---- write and durability ------------------------------------------ */

ssize_t write(int fd, const void *buf, size_t count) {
    REAL(write)
    emit_fd("write", fd);
    return real_write(fd, buf, count);
}

ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset) {
    REAL(pwrite)
    emit_fd("write", fd);
    return real_pwrite(fd, buf, count, offset);
}

ssize_t writev(int fd, const struct iovec *iov, int iovcnt) {
    REAL(writev)
    emit_fd("write", fd);
    return real_writev(fd, iov, iovcnt);
}

int fsync(int fd) {
    REAL(fsync)
    emit_fd("fsync", fd);
    return real_fsync(fd);
}

int fdatasync(int fd) {
    REAL(fdatasync)
    emit_fd("fsync", fd);
    return real_fdatasync(fd);
}

/* ---- large-file variants: distinct symbols the shim also exports ---- */

int creat64(const char *path, mode_t mode) {
    REAL(creat64)
    emit("open", path);
    return real_creat64(path, mode);
}

FILE *fopen64(const char *path, const char *mode) {
    REAL(fopen64)
    emit("open", path);
    return real_fopen64(path, mode);
}

FILE *freopen64(const char *path, const char *mode, FILE *stream) {
    REAL(freopen64)
    emit("open", path);
    return real_freopen64(path, mode, stream);
}

ssize_t pwrite64(int fd, const void *buf, size_t count, off64_t offset) {
    REAL(pwrite64)
    emit_fd("write", fd);
    return real_pwrite64(fd, buf, count, offset);
}

int ftruncate64(int fd, off64_t length) {
    REAL(ftruncate64)
    emit_fd("truncate", fd);
    return real_ftruncate64(fd, length);
}

int truncate64(const char *path, off64_t length) {
    REAL(truncate64)
    emit("truncate", path);
    return real_truncate64(path, length);
}

/* ---- the stdio flush family -----------------------------------------
 * Buffered bytes reach the kernel from inside libc, past any PLT. The
 * shim exports these for that reason (#39); so does this logger.
 */

static void emit_stream(const char *cls, FILE *stream) {
    int fd = stream ? fileno(stream) : -1;
    emit_fd(cls, fd);
}

int fclose(FILE *stream) {
    REAL(fclose)
    emit_stream("write", stream);
    return real_fclose(stream);
}

int fflush(FILE *stream) {
    REAL(fflush)
    emit_stream("write", stream);
    return real_fflush(stream);
}

int fflush_unlocked(FILE *stream) {
    REAL(fflush_unlocked)
    emit_stream("write", stream);
    return real_fflush_unlocked(stream);
}

int fseek(FILE *stream, long offset, int whence) {
    REAL(fseek)
    emit_stream("write", stream);
    return real_fseek(stream, offset, whence);
}

int fseeko(FILE *stream, off_t offset, int whence) {
    REAL(fseeko)
    emit_stream("write", stream);
    return real_fseeko(stream, offset, whence);
}

int fsetpos(FILE *stream, const fpos_t *pos) {
    REAL(fsetpos)
    emit_stream("write", stream);
    return real_fsetpos(stream, pos);
}

void rewind(FILE *stream) {
    REAL(rewind)
    emit_stream("write", stream);
    real_rewind(stream);
}
