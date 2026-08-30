/* A child the shim cannot see, writing into the judged directory (#405).
 *
 * The parent writes one file through libc so the recording is not empty — that is what
 * keeps `state_changed_without_ops` quiet, and why the run reached PASS before this
 * detector existed. The child is created with a raw syscall, so no interposed wrapper
 * records the boundary, and writes through raw syscalls, so no wrapper records the
 * write either. Nothing in the trace names `from-raw-child`; the snapshot difference
 * does. That gap is the whole fixture.
 *
 * Portability, measured rather than assumed:
 *   - `SYS_fork` does not exist on aarch64 Linux, which has only `clone`. Both spellings
 *     are here and the toy takes whichever the platform defines.
 *   - On arm64 macOS a raw fork returns the pid in BOTH processes, and libc caches
 *     `getpid()` without invalidating it on the raw path — so the obvious `r == 0` test
 *     never fires and the child writes nothing at all (measured: the naive version was
 *     a silent no-op). `syscall(SYS_getpid)` is the only discriminator that works, and
 *     it works on Linux too.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(SYS_fork)
#define RAW_FORK() syscall(SYS_fork)
#elif defined(SYS_clone)
#include <signal.h>
#define RAW_FORK() syscall(SYS_clone, (unsigned long)SIGCHLD, (unsigned long)0, (unsigned long)0, (unsigned long)0, (unsigned long)0)
#else
#error "no raw process-creation syscall on this platform"
#endif

/* The same split, for the same reason, one syscall over. aarch64 Linux has no `SYS_open`
 * — only `SYS_openat` — so the fixture that reasoned carefully about `SYS_fork` there
 * would have failed to compile two lines later. Caught by review reading the header's
 * portability claim against the body rather than against the platforms CI happens to
 * run (x86-64 Linux and macOS, both of which define `SYS_open`). */
#if defined(SYS_open)
#define RAW_OPEN(p, fl, md) syscall(SYS_open, (p), (fl), (md))
#else
#include <fcntl.h>
#define RAW_OPEN(p, fl, md) syscall(SYS_openat, AT_FDCWD, (p), (fl), (md))
#endif

int main(void) {
    const char *d = getenv("TOY_STATE");
    if (!d) d = getenv("PROBE_STATE");
    if (!d) d = "./state";
    char pp[1024], cp[1024];
    snprintf(pp, sizeof(pp), "%s/from-parent", d);
    snprintf(cp, sizeof(cp), "%s/from-raw-child", d);

    int fd = open(pp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "p\n", 2) != 2) { perror("write"); return 1; }
    close(fd);

    long before = syscall(SYS_getpid);
    long r = RAW_FORK();
    if (r < 0) { fprintf(stderr, "raw fork failed\n"); return 3; }
    if (syscall(SYS_getpid) != before) {
        long c = RAW_OPEN(cp, O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (c >= 0) { syscall(SYS_write, c, "c\n", 2); syscall(SYS_close, c); }
        syscall(SYS_exit, 0);
        _exit(0);
    }
    int st;
    waitpid((pid_t)r, &st, 0);
    return 0;
}
