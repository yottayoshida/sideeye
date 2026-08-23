/* no-accel-copy.so: declared apparatus for himalaya-r2 (see the toml).
 *
 * Answers the accelerated copy primitives in USERSPACE, so no syscall is
 * made and the tracer has nothing to observe. That is the whole delta
 * from r1, which used a seccomp profile: seccomp makes the syscall FAIL,
 * and the oracle refuses on a syscall it does not model whether or not
 * the call succeeded (oracle.zig's changesPersistentState reads the name,
 * never the return value). An ENOSYS from the kernel is still an
 * observation; an ENOSYS from here is not a syscall at all.
 *
 * Reachable because Rust std looks these up as weak symbols precisely so
 * LD_PRELOAD can interpose them (#244, and std's own comment). The bytes
 * on disk are identical either way: fs::copy falls back to its read/write
 * loop, which is what the shim exports and the oracle models.
 *
 * Loaded through /etc/ld.so.preload, not LD_PRELOAD: the engine owns
 * LD_PRELOAD for its shim. Unlike the pid pin, which broke strace's own
 * child management, this defines only the three copy primitives, and
 * strace was measured healthy under it.
 *
 * Build: cc -shared -fPIC -o no-accel-copy.so no-accel-copy.c
 */
#define _GNU_SOURCE
#include <errno.h>
#include <sys/types.h>
#include <stddef.h>

ssize_t copy_file_range(int fd_in, long *off_in, int fd_out, long *off_out,
                        size_t len, unsigned int flags) {
    (void)fd_in; (void)off_in; (void)fd_out; (void)off_out; (void)len; (void)flags;
    errno = ENOSYS;
    return -1;
}

ssize_t sendfile(int out_fd, int in_fd, long *offset, size_t count) {
    (void)out_fd; (void)in_fd; (void)offset; (void)count;
    errno = ENOSYS;
    return -1;
}

ssize_t sendfile64(int out_fd, int in_fd, long long *offset, size_t count) {
    (void)out_fd; (void)in_fd; (void)offset; (void)count;
    errno = ENOSYS;
    return -1;
}
