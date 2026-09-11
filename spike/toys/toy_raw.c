/*
 * The same rotation, issued through syscall(2) instead of the libc wrappers.
 *
 * LD_PRELOAD replaces symbols; this binary never calls the symbols being replaced,
 * so the shim sees nothing at all. That is the point: from inside, an empty trace
 * looks exactly like a target that performed no file operations. Sideeye must not
 * read that as "nothing happened, therefore PASS" — the recording run's oracle and
 * the engine's state_changed_without_ops detector both exist for this binary.
 *
 * Since #542 it is also the fixture for the other direction. Under `--observe syscalls`
 * the filter traps every kill point, so this binary — which reaches libc for none of
 * them — is seen in full, and the `raw-all` subcommand issues ONE OF EVERY trapped name
 * so that each arm of the handler's dispatch is exercised against the oracle reading the
 * same run. A wrong class, a missed record or a wrapper that records what the handler
 * already counted all end the same way: the two accounts stop matching position by
 * position and the run refuses instead of reaching a verdict.
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <unistd.h>

#define KEY_NAME "key.json"
#define TMP_NAME "key.json.tmp"

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

static int raw_write_file(const char *path, const char *content) {
    long fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    size_t off = 0;
    while (off < len) {
        long w = syscall(SYS_write, (int)fd, content + off, len - off);
        if (w <= 0) { syscall(SYS_close, (int)fd); return -1; }
        off += (size_t)w;
    }
    syscall(SYS_fsync, (int)fd);
    syscall(SYS_close, (int)fd);
    return 0;
}

static int cmd_init(void) {
    syscall(SYS_mkdirat, AT_FDCWD, state_dir(), 0755);
    char key[4096];
    join_path(key, sizeof key, KEY_NAME);
    return raw_write_file(key, "key=1\n") == 0 ? 0 : 1;
}

static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, KEY_NAME);
    join_path(tmp, sizeof tmp, TMP_NAME);

    if (raw_write_file(tmp, "key=2\n") != 0) return 1;
    syscall(SYS_unlinkat, AT_FDCWD, key, 0);
    if (syscall(SYS_renameat, AT_FDCWD, tmp, AT_FDCWD, key) != 0) return 1;
    return 0;
}

/* One of every syscall `--observe syscalls` traps, issued raw.
 *
 * The order is the one the names force: a directory before what goes in it, a file
 * before the link to it, the removals last. Every call is checked only for the pair
 * that must not be wrong — a failure here would leave the sequence issuing calls
 * against paths that do not exist, and the run would then be measuring the wrong
 * thing quietly. Nothing is retried: a failed attempt counts on both sides, so the
 * accounts stay matched either way, and the check script is what notices.
 *
 * `openat2` may answer ENOSYS on a kernel older than 5.6. That is not a hole in this
 * fixture: seccomp runs BEFORE the kernel decides, so the call is trapped and recorded
 * on both sides regardless, and only the file it would have made is missing. The check
 * script must therefore not require it.
 */
struct toy_open_how {
    uint64_t flags;
    uint64_t mode;
    uint64_t resolve;
};

static int raw_all(void) {
    char a[4096], b[4096], b2[4096], b3[4096], c[4096], d[4096], e[4096], f[4096];
    join_path(a, sizeof a, "a");
    join_path(b, sizeof b, "b");
    join_path(b2, sizeof b2, "b2");
    join_path(b3, sizeof b3, "b3");
    join_path(c, sizeof c, "c");
    join_path(d, sizeof d, "d");
    join_path(e, sizeof e, "e");
    join_path(f, sizeof f, "f");

    if (syscall(SYS_mkdirat, AT_FDCWD, d, 0755) != 0) return 1;

    long fd = syscall(SYS_openat, AT_FDCWD, a, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;
    if (syscall(SYS_write, (int)fd, "w", 1) != 1) return 1;
    if (syscall(SYS_pwrite64, (int)fd, "p", 1, (off_t)1) != 1) return 1;
    struct iovec v = {.iov_base = (void *)"v", .iov_len = 1};
    if (syscall(SYS_writev, (int)fd, &v, 1) != 1) return 1;
    /* The kernel splits pwritev's offset into two words, low then high. */
    if (syscall(SYS_pwritev, (int)fd, &v, 1, (unsigned long)3, (unsigned long)0) != 1) return 1;
    syscall(SYS_ftruncate, (int)fd, (off_t)4);
    syscall(SYS_fsync, (int)fd);
    syscall(SYS_fdatasync, (int)fd);
    syscall(SYS_close, (int)fd);

    syscall(SYS_truncate, a, (off_t)3);
    syscall(SYS_linkat, AT_FDCWD, a, AT_FDCWD, b, 0);
    syscall(SYS_symlinkat, "a", AT_FDCWD, c);
    syscall(SYS_renameat, AT_FDCWD, b, AT_FDCWD, b2);
#ifdef SYS_renameat2
    syscall(SYS_renameat2, AT_FDCWD, b2, AT_FDCWD, b3, 0);
#else
    syscall(SYS_renameat, AT_FDCWD, b2, AT_FDCWD, b3);
#endif
    syscall(SYS_unlinkat, AT_FDCWD, b3, 0);
    syscall(SYS_unlinkat, AT_FDCWD, c, 0);
    syscall(SYS_unlinkat, AT_FDCWD, d, AT_REMOVEDIR);

    /* sendfile's destination is its FIRST argument; the source is opened read-only, so
     * neither observer counts that open (ADR 0003). */
    long dst = syscall(SYS_openat, AT_FDCWD, e, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    long src = syscall(SYS_openat, AT_FDCWD, a, O_RDONLY, 0);
    if (dst >= 0 && src >= 0) syscall(SYS_sendfile, (int)dst, (int)src, NULL, (size_t)3);
    if (src >= 0) syscall(SYS_close, (int)src);
    if (dst >= 0) syscall(SYS_close, (int)dst);

#ifdef SYS_openat2
    struct toy_open_how how = {.flags = O_WRONLY | O_CREAT | O_TRUNC, .mode = 0644, .resolve = 0};
    long o2 = syscall(SYS_openat2, AT_FDCWD, f, &how, sizeof how);
    if (o2 >= 0) syscall(SYS_close, (int)o2);
#endif

    /* The spellings that exist as syscalls on x86-64 only. aarch64 has no number for
     * them at all, which is why each is compiled in on its own `#ifdef` rather than
     * behind one architecture test: the header is the thing that knows. */
    char g[4096], g2[4096], h[4096], i[4096], j[4096], k[4096];
    join_path(g, sizeof g, "g");
    join_path(g2, sizeof g2, "g2");
    join_path(h, sizeof h, "h");
    join_path(i, sizeof i, "i");
    join_path(j, sizeof j, "j");
    join_path(k, sizeof k, "k");
#ifdef SYS_open
    long gfd = syscall(SYS_open, g, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (gfd >= 0) syscall(SYS_close, (int)gfd);
#endif
#ifdef SYS_creat
    long hfd = syscall(SYS_creat, h, 0644);
    if (hfd >= 0) syscall(SYS_close, (int)hfd);
#endif
#ifdef SYS_rename
    syscall(SYS_rename, g, g2);
#endif
#ifdef SYS_link
    syscall(SYS_link, g2, i);
#endif
#ifdef SYS_symlink
    syscall(SYS_symlink, "g2", j);
#endif
#ifdef SYS_mkdir
    syscall(SYS_mkdir, k, 0755);
#endif
#ifdef SYS_rmdir
    syscall(SYS_rmdir, k);
#endif
#ifdef SYS_unlink
    syscall(SYS_unlink, i);
    syscall(SYS_unlink, j);
    syscall(SYS_unlink, g2);
    syscall(SYS_unlink, h);
#endif
    return 0;
}

/* A SIGSYS that is not a seccomp trap, sent by the target to itself.
 *
 * The shim installs a `SIGSYS` handler, and that handler reads a syscall number out of
 * the `siginfo_t` and RE-ISSUES it. Only a seccomp trap puts a syscall number there.
 * MEASURED on both platforms, 2026-09-11: `si_code` is at offset 8, `si_syscall` at 24 —
 * and `si_value` is at 24 as well. So `sigqueue(pid, SIGSYS, value)` puts a number of the
 * sender's choosing exactly where the handler would read one, and `kill(pid, SIGSYS)`
 * puts a zero there, which on x86-64 is `read`.
 *
 * Seen red before the check existed: with the handler not testing `si_code`, this
 * subcommand printed "sigqueue: Success" and exited 2 — the handler had executed the
 * number in `si_value` and written its result into the register `sigqueue`'s own return
 * value comes from, so a failed call read as a successful one and the process carried on.
 * With the test in place, and without the shim at all, the process dies of `SIGSYS`
 * (exit 159) — which is the point: what the shim does with a signal that is not its own
 * is what would have happened if it were not there.
 *
 * Exit 0 here means the process SURVIVED, which is the failure. The acceptance leg reads
 * the signal, not this status.
 */
static int cmd_foreign_sigsys(void) {
    union sigval v;
    /* `getpid` is the most harmless thing a mistaken re-issue could run, and it is the
     * number the earlier measurement used. The point is the re-issue, not the call. */
#if defined(__x86_64__)
    v.sival_int = 39;
#else
    v.sival_int = 172;
#endif
    if (sigqueue(getpid(), SIGSYS, v) != 0) return 2;
    printf("survived a sigqueue(SIGSYS): something answered a signal that was not a trap\n");
    return 0;
}

/* A target that blocks SIGSYS and then writes raw.
 *
 * Measured on 2026-09-11 before this was written: a seccomp TRAP on a thread with SIGSYS
 * BLOCKED does not reach the handler at all — the kernel resets the disposition rather
 * than queueing a signal it forced, and the process dies with "Bad system call" (exit
 * 159). So a target that blocks it takes `--observe syscalls` with it, and the hazard
 * predates the widened trap set: `write` alone was enough.
 *
 * The shim answers by interposing both doors to the mask and keeping SIGSYS out of the
 * blocked set. This subcommand is what says so: it asks for exactly that, through both
 * doors, and then issues calls that can only be counted if the signal still arrives. A
 * run that reaches a verdict is the measurement; a run that dies at 159 is the shim
 * having stopped doing it.
 *
 * What this does NOT cover, and cannot: a target reaching `rt_sigprocmask` without libc.
 * Interposition does not see that, and the process dies rather than refusing, so there is
 * no verdict to assert on. `docs/report-schema.md` carries it as a disclosed limit.
 */
static int cmd_blocked(void) {
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, SIGSYS);
    /* Both doors: `sigprocmask` is the portable one, `pthread_sigmask` the one a Go
     * runtime reaches through libc (measured on mlr: five calls touching SIGSYS in one
     * run). glibc has carried both in libc proper since 2.34. */
    if (sigprocmask(SIG_BLOCK, &set, NULL) != 0) return 1;
    if (pthread_sigmask(SIG_BLOCK, &set, NULL) != 0) return 1;

    char p[4096];
    join_path(p, sizeof p, "blocked");
    long fd = syscall(SYS_openat, AT_FDCWD, p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 1;
    if (syscall(SYS_write, (int)fd, "b", 1) != 1) return 1;
    syscall(SYS_fsync, (int)fd);
    syscall(SYS_close, (int)fd);
    return 0;
}

static int cmd_doctor(void) {
    struct stat st;
    if (stat(state_dir(), &st) == 0 && S_ISDIR(st.st_mode)) {
        printf("healthy\n");
        return 0;
    }
    printf("unhealthy\n");
    return 0;
}

static int cmd_load_key(void) {
    char path[4096], buf[256];
    join_path(path, sizeof path, KEY_NAME);
    long fd = syscall(SYS_openat, AT_FDCWD, path, O_RDONLY, 0);
    if (fd < 0) return 1;
    long r = syscall(SYS_read, (int)fd, buf, sizeof buf - 1);
    syscall(SYS_close, (int)fd);
    if (r <= 0) return 1;
    buf[r] = '\0';
    if (strncmp(buf, "key=", 4) != 0) return 1;
    printf("%s", buf);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s init|rotate|raw-all|blocked|foreign-sigsys|doctor|load-key\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) return cmd_rotate();
    if (strcmp(argv[1], "raw-all") == 0) return raw_all();
    if (strcmp(argv[1], "blocked") == 0) return cmd_blocked();
    if (strcmp(argv[1], "foreign-sigsys") == 0) return cmd_foreign_sigsys();
    if (strcmp(argv[1], "doctor") == 0) return cmd_doctor();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    return 2;
}
