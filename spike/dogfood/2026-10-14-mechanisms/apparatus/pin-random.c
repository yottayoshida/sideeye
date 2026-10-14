/* A fixed byte stream for getrandom() and getentropy(), loaded through /etc/ld.so.preload and
 * declared in the define's apparatus (docs/apparatus.md, "hex digits": a pinned source).
 * KeePassXC draws a fresh salt and IV for every KDBX save, which is what refused it in cohort 2
 * (spike/cohort2/probes/recheck-keepassxc.txt); with this the second clean run writes what the
 * first did. Botan in Debian's KeePassXC reads /dev/urandom rather than calling getrandom()
 * (transcripts/lab-3.txt), so an open of either device is handed /opt/pin/urandom.bin, a fixed file,
 * read from its start by every process. Not a random number generator: never load it anywhere a secret is made. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stddef.h>
#include <string.h>
#include <sys/types.h>

static unsigned long long state = 0x5eed5eed5eed5eedULL;

static unsigned char next_byte(void) {
    state = state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (unsigned char)(state >> 56);
}

ssize_t getrandom(void *buf, size_t len, unsigned int flags) {
    (void)flags;
    unsigned char *p = buf;
    for (size_t i = 0; i < len; i++) p[i] = next_byte();
    return (ssize_t)len;
}

int getentropy(void *buf, size_t len) {
    if (len > 256) { errno = EIO; return -1; }
    getrandom(buf, len, 0);
    return 0;
}

static const char *pinned(const char *path) {
    if (path && (strcmp(path, "/dev/urandom") == 0 || strcmp(path, "/dev/random") == 0))
        return "/opt/pin/urandom.bin";
    return path;
}

#define PIN_OPEN(name, ...)                                                            \
    int name(const char *path, int flags, ...) {                                       \
        static int (*real)(const char *, int, ...);                                    \
        if (!real) real = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, #name);    \
        mode_t mode = 0;                                                               \
        if (flags & (O_CREAT | O_TMPFILE)) {                                           \
            va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);    \
        }                                                                              \
        return real(pinned(path), flags, mode);                                        \
    }
PIN_OPEN(open)
PIN_OPEN(open64)

#define PIN_OPENAT(name)                                                                       \
    int name(int dirfd, const char *path, int flags, ...) {                                    \
        static int (*real)(int, const char *, int, ...);                                       \
        if (!real) real = (int (*)(int, const char *, int, ...))dlsym(RTLD_NEXT, #name);       \
        mode_t mode = 0;                                                                       \
        if (flags & (O_CREAT | O_TMPFILE)) {                                                   \
            va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);            \
        }                                                                                      \
        return real(dirfd, pinned(path), flags, mode);                                         \
    }
PIN_OPENAT(openat)
PIN_OPENAT(openat64)
