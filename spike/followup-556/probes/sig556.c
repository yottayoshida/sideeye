/* #556 same-class probe: which doors take SIGSYS away from a process the shim is loaded
 * into. Each case runs in its own forked child so a death names the case.
 *   sig556 <state-dir> */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static void trapped_write(void) {
    int fd = open("/tmp/sig556-out.txt", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) { (void)write(fd, "x", 1); close(fd); }
}

static void on_usr1(int s) { (void)s; (void)write(2, "", 0); trapped_write(); }

/* door: libc sigaction resets SIGSYS (what CPython's vfork child does) */
static void c_libc_reset(void) {
    struct sigaction dfl; memset(&dfl, 0, sizeof dfl); dfl.sa_handler = SIG_DFL;
    sigaction(SIGSYS, &dfl, NULL);
    trapped_write();
}
/* door: raw rt_sigaction resets SIGSYS (glibc's posix_spawn child, a static runtime) */
static void c_raw_reset(void) {
    char k[64]; memset(k, 0, sizeof k);   /* handler 0 = SIG_DFL, flags 0, mask 0 */
    syscall(SYS_rt_sigaction, SIGSYS, k, NULL, 8);
    trapped_write();
}
/* door: libc sigprocmask blocks everything */
static void c_libc_block(void) {
    sigset_t all; sigfillset(&all); sigprocmask(SIG_BLOCK, &all, NULL);
    trapped_write();
}
/* door: raw rt_sigprocmask blocks everything (glibc's internal block-all) */
static void c_raw_block(void) {
    unsigned long all = ~0UL;
    syscall(SYS_rt_sigprocmask, SIG_BLOCK, &all, NULL, 8);
    trapped_write();
}
/* door: a handler for ANOTHER signal installed with a full sa_mask (libuv does this) */
static void c_samask_full(void) {
    struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = on_usr1;
    sigfillset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);
    raise(SIGUSR1);
}
/* control: the same handler with an empty sa_mask */
static void c_samask_empty(void) {
    struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = on_usr1;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGUSR1, &sa, NULL);
    raise(SIGUSR1);
}
/* control: nothing touched */
static void c_none(void) { trapped_write(); }

static void run(const char *tag, void (*f)(void)) {
    fflush(NULL);
    pid_t p = fork();
    if (p == 0) { f(); _exit(0); }
    int st;
    waitpid(p, &st, 0);
    if (WIFEXITED(st)) fprintf(stderr, "%s -> exited %d\n", tag, WEXITSTATUS(st));
    else fprintf(stderr, "%s -> killed by signal %d\n", tag, WTERMSIG(st));
}

static void spawn_addopen(void) {
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, "/tmp/sig556-spawn.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    char *argv[] = { "/bin/true", NULL };
    pid_t pid;
    int rc = posix_spawn(&pid, "/bin/true", &fa, NULL, argv, environ);
    if (rc) _exit(100 + rc);
    int st; waitpid(pid, &st, 0);
    _exit(WIFSIGNALED(st) ? 200 + WTERMSIG(st) : WEXITSTATUS(st));
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    run("control: nothing touched               ", c_none);
    run("libc sigaction(SIGSYS, SIG_DFL)        ", c_libc_reset);
    run("raw rt_sigaction(SIGSYS, SIG_DFL)      ", c_raw_reset);
    run("libc sigprocmask(SIG_BLOCK, all)       ", c_libc_block);
    run("raw rt_sigprocmask(SIG_BLOCK, all)     ", c_raw_block);
    run("SIGUSR1 handler, sa_mask full, writes  ", c_samask_full);
    run("SIGUSR1 handler, sa_mask empty, writes ", c_samask_empty);
    run("posix_spawn addopen O_WRONLY (exit 231 = child killed by 31)", spawn_addopen);
    char p[1024];
    snprintf(p, sizeof p, "%s/o.txt", argv[1]);
    FILE *f = fopen(p, "w");
    if (!f) return 1;
    fputs("x\n", f);
    fclose(f);
    return 0;
}
