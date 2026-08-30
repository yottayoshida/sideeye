// toy_guarded.c — exercise the guarded-descriptor family so the shim's transcribed
// signatures are checked by running them, not by reading them (#299).
//
// Why this toy exists. `sys/guarded.h` is not in the SDK, so `darwin_libc.zig` declares
// these six from XNU's own header rather than from anything the compiler can verify. A
// wrong arity there does not fail to build: on arm64 macOS the variadic arguments go on
// the stack and the fixed ones in registers, so a mis-declared call reads a register the
// caller never wrote — the same failure `ops.zig`'s `open` comment records. The only way
// to find that is to call each one and look at what came back.
//
// It is deliberately not a crash-consistency target: no bug, no interesting ordering.
// It writes three bytes through three different guarded writers, then closes. The
// acceptance leg runs it twice — unshimmed, where every call must report success, and
// then through `explore`, where the engine must report six crash points. It does not
// read the trace; the crash-point count is the proxy, and it reaches five of the six
// calls (close is lifecycle and produces none).
//
//   usage: toy-guarded <path>
//   exit 0 all six calls succeeded, 1 one of them did not, 2 usage

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>

typedef uint64_t guardid_t;

// Declared here for the same reason the shim declares them: no public header does.
extern int guarded_open_np(const char *path, const guardid_t *guard,
                           unsigned int guardflags, int flags, ...);
extern int guarded_open_dprotected_np(const char *path, const guardid_t *guard,
                                      unsigned int guardflags, int flags,
                                      int dpclass, int dpflags, ...);
extern int guarded_close_np(int fd, const guardid_t *guard);
extern ssize_t guarded_write_np(int fd, const guardid_t *guard,
                                const void *buf, size_t nbyte);
extern ssize_t guarded_pwrite_np(int fd, const guardid_t *guard,
                                 const void *buf, size_t nbyte, off_t offset);
extern ssize_t guarded_writev_np(int fd, const guardid_t *guard,
                                 const struct iovec *iovp, int iovcnt);

// The guard value is arbitrary; what matters is that the same one is presented on every
// later call, since a mismatch is what the guard exists to trap.
// Measured, not assumed: the kernel refuses the call with EINVAL unless O_CLOEXEC is
// set, GUARD_DUP (which is GUARD_REQUIRED) is among the guard flags, no bit outside
// GUARD_ALL is set, and the guard value is non-zero. The first two are why this toy
// exists in the shape it does — a first version omitted O_CLOEXEC and every single
// combination came back EINVAL, which reads exactly like a wrong signature.
#define GUARD_ID       0x5EE0EE5EE0EE5EE0ull
#define GUARD_CLOSE    (1u << 0)
#define GUARD_DUP      (1u << 1)   /* GUARD_REQUIRED: the kernel demands this one */

static int fail(const char *what) {
    fprintf(stderr, "toy-guarded: %s: %s\n", what, strerror(errno));
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <path>\n", argv[0]);
        return 2;
    }
    const guardid_t guard = GUARD_ID;

    int fd = guarded_open_np(argv[1], &guard, GUARD_CLOSE | GUARD_DUP,
                             O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return fail("guarded_open_np");

    if (guarded_write_np(fd, &guard, "a", 1) != 1) return fail("guarded_write_np");
    if (guarded_pwrite_np(fd, &guard, "b", 1, 1) != 1) return fail("guarded_pwrite_np");

    struct iovec iov = { .iov_base = (void *)"c", .iov_len = 1 };
    if (guarded_writev_np(fd, &guard, &iov, 1) != 1) return fail("guarded_writev_np");

    if (guarded_close_np(fd, &guard) != 0) return fail("guarded_close_np");

    // The dprotected variant takes two more fixed arguments before the variadic mode,
    // which is the arity most likely to be transcribed wrong. Measured: dpclass 0
    // is EINVAL and 1..4 are accepted, for this call and for the unguarded
    // open_dprotected_np the shim already interposes.
    char second[1024];
    snprintf(second, sizeof second, "%s.dp", argv[1]);
    int dfd = guarded_open_dprotected_np(second, &guard, GUARD_CLOSE | GUARD_DUP,
                                         O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 1, 0, 0644);
    if (dfd < 0) return fail("guarded_open_dprotected_np");
    if (guarded_write_np(dfd, &guard, "d", 1) != 1) return fail("guarded_write_np(dp)");
    if (guarded_close_np(dfd, &guard) != 0) return fail("guarded_close_np(dp)");

    return 0;
}
