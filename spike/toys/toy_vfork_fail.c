/* A boundary the shim records and the oracle cannot see, because there is nothing to
 * see: `vfork` fails, so no child ever exists.
 *
 * The shim's vfork wrapper records `.fork` BEFORE the call — it must, there is no frame
 * afterwards to record from (shim/src/ops.zig) — so a failed vfork leaves a boundary
 * record with no process behind it. `strace -f` follows children and finds none, so its
 * account has zero other pids. The two witnesses then disagree, and until #405's report
 * half the account resolved the disagreement by asserting `single process`.
 *
 * RLIMIT_NPROC=0 is what makes the vfork fail, and it only bites an unprivileged user:
 * measured root-exempt in a container, where the vfork succeeded and the toy said so.
 * The toy always exits its declared success status and reports which branch it took
 * through PROBE_OUTCOME, because the thing under measurement is the account, not the
 * verdict — a leg that read the outcome off the exit code could not tell a failed vfork
 * from a toy that never ran.
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>

int main(void) {
    const char *d = getenv("PROBE_STATE");
    if (!d) d = "./state";
    const char *o = getenv("PROBE_OUTCOME");
    char p[1024];
    snprintf(p, sizeof(p), "%s/a.txt", d);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, "x\n", 2) != 2) { perror("write"); return 1; }
    close(fd);

    struct rlimit rl = { 0, 0 };
    int sr = setrlimit(RLIMIT_NPROC, &rl);
    pid_t c = vfork();
    if (c == 0) _exit(0);
    const char *what = (sr != 0) ? "setrlimit-failed" : (c >= 0 ? "vfork-succeeded" : "vfork-failed");
    if (o) {
        FILE *f = fopen(o, "w");
        if (f) { fprintf(f, "%s\n", what); fclose(f); }
    }
    return 0;
}
