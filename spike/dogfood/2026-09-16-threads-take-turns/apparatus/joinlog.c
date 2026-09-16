/* LD_PRELOAD probe: log pthread_create (creator tid, new tid via a trampoline), pthread_join,
 * pthread_detach, and every open of a path holding "library.db", with the calling tid. One
 * line per event on fd 2, prefixed by a global sequence number. No Sideeye involved. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static int seq;
static pid_t tid(void) { return (pid_t)syscall(SYS_gettid); }
static void logf_(const char *fmt, ...) {
    char b[512]; int n = snprintf(b, sizeof b, "JL %04d tid=%d ", __sync_add_and_fetch(&seq, 1), tid());
    va_list ap; va_start(ap, fmt); n += vsnprintf(b + n, sizeof b - n, fmt, ap); va_end(ap);
    if (n < (int)sizeof b - 1) b[n++] = '\n';
    write(2, b, n);
}
struct start { void *(*fn)(void *); void *arg; pid_t creator; };
static void *tramp(void *p) {
    struct start s = *(struct start *)p; free(p);
    logf_("started creator=%d self=%lx", s.creator, (unsigned long)pthread_self());
    return s.fn(s.arg);
}
int pthread_create(pthread_t *t, const pthread_attr_t *a, void *(*fn)(void *), void *arg) {
    static int (*real)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    if (!real) real = dlsym(RTLD_NEXT, "pthread_create");
    struct start *s = malloc(sizeof *s); s->fn = fn; s->arg = arg; s->creator = tid();
    int rc = real(t, a, tramp, s);
    logf_("create rc=%d new=%lx", rc, rc == 0 ? (unsigned long)*t : 0UL);
    if (rc != 0) free(s);
    return rc;
}
int pthread_join(pthread_t t, void **r) {
    static int (*real)(pthread_t, void **);
    if (!real) real = dlsym(RTLD_NEXT, "pthread_join");
    logf_("join-enter target=%lx", (unsigned long)t);
    int rc = real(t, r);
    logf_("join-return target=%lx rc=%d", (unsigned long)t, rc);
    return rc;
}
int pthread_detach(pthread_t t) {
    static int (*real)(pthread_t);
    if (!real) real = dlsym(RTLD_NEXT, "pthread_detach");
    int rc = real(t);
    logf_("detach target=%lx rc=%d", (unsigned long)t, rc);
    return rc;
}
static char watched[4096];
static const char *match_;
static int is_db(const char *path) {
    if (!match_) { const char *e = getenv("JL_MATCH"); match_ = e && *e ? e : "library.db"; }
    return path && strstr(path, match_) != NULL;
}
int mkdir(const char *path, mode_t m) { static int (*real)(const char *, mode_t); if (!real) real = dlsym(RTLD_NEXT, "mkdir"); int rc = real(path, m); if (is_db(path)) logf_("mkdir %s rc=%d", path, rc); return rc; }
int rename(const char *a, const char *b) { static int (*real)(const char *, const char *); if (!real) real = dlsym(RTLD_NEXT, "rename"); int rc = real(a, b); if (is_db(a) || is_db(b)) logf_("rename %s -> %s rc=%d", a, b, rc); return rc; }
int symlink(const char *a, const char *b) { static int (*real)(const char *, const char *); if (!real) real = dlsym(RTLD_NEXT, "symlink"); int rc = real(a, b); if (is_db(b)) logf_("symlink %s rc=%d", b, rc); return rc; }
static void note_fd(const char *who, const char *path, int flags, int fd) {
    if (!is_db(path)) return;
    logf_("%s %s flags=0x%x write=%d fd=%d", who, path, flags, (flags & (O_WRONLY | O_RDWR)) != 0, fd);
    if (fd >= 0 && fd < 4096) watched[fd] = 1;
}
ssize_t write(int fd, const void *b, size_t n) {
    static ssize_t (*real)(int, const void *, size_t); if (!real) real = dlsym(RTLD_NEXT, "write");
    if (fd >= 0 && fd < 4096 && watched[fd]) logf_("write fd=%d n=%zu", fd, n);
    return real(fd, b, n);
}
ssize_t pwrite64(int fd, const void *b, size_t n, off_t off) {
    static ssize_t (*real)(int, const void *, size_t, off_t); if (!real) real = dlsym(RTLD_NEXT, "pwrite64");
    if (fd >= 0 && fd < 4096 && watched[fd]) logf_("pwrite64 fd=%d n=%zu off=%ld", fd, n, (long)off);
    return real(fd, b, n, off);
}
int fsync(int fd) { static int (*real)(int); if (!real) real = dlsym(RTLD_NEXT, "fsync"); if (fd >= 0 && fd < 4096 && watched[fd]) logf_("fsync fd=%d", fd); return real(fd); }
int fdatasync(int fd) { static int (*real)(int); if (!real) real = dlsym(RTLD_NEXT, "fdatasync"); if (fd >= 0 && fd < 4096 && watched[fd]) logf_("fdatasync fd=%d", fd); return real(fd); }
int close(int fd) { static int (*real)(int); if (!real) real = dlsym(RTLD_NEXT, "close"); if (fd >= 0 && fd < 4096 && watched[fd]) { logf_("close fd=%d", fd); watched[fd] = 0; } return real(fd); }
int unlink(const char *path) { static int (*real)(const char *); if (!real) real = dlsym(RTLD_NEXT, "unlink"); if (is_db(path)) logf_("unlink %s", path); return real(path); }
#define OPEN_WRAPPER(NAME) \
int NAME(const char *path, int flags, ...) { \
    static int (*real)(const char *, int, ...); if (!real) real = dlsym(RTLD_NEXT, #NAME); \
    mode_t m = 0; if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); } \
    int fd = real(path, flags, m); note_fd(#NAME, path, flags, fd); return fd; }
OPEN_WRAPPER(open)
OPEN_WRAPPER(open64)
#define OPENAT_WRAPPER(NAME) \
int NAME(int dirfd, const char *path, int flags, ...) { \
    static int (*real)(int, const char *, int, ...); if (!real) real = dlsym(RTLD_NEXT, #NAME); \
    mode_t m = 0; if (flags & O_CREAT) { va_list ap; va_start(ap, flags); m = va_arg(ap, int); va_end(ap); } \
    int fd = real(dirfd, path, flags, m); note_fd(#NAME, path, flags, fd); return fd; }
OPENAT_WRAPPER(openat)
OPENAT_WRAPPER(openat64)
