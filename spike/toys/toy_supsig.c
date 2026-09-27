/*
 * --observe supervised under signals (#217, ADR 0089).
 *
 * A target that catches SIGUSR1 with SA_RESTART -- the disposition Go's runtime gives the
 * signal it preempts goroutines with -- while a second thread keeps sending it. Some of the
 * main thread's state-changing calls are therefore interrupted while they wait for the
 * supervising engine: before the engine received the notification (the kernel withdraws it
 * and strace prints `= ? ERESTARTSYS` and the restarted call), or after it (which
 * SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV makes wait). Either way each call is one operation,
 * and the engine and the oracle must agree on 80 of them: 20 rounds of open, write, fsync,
 * rename. Only the main thread writes the state directory.
 *
 *   toy-supsig init     create the state file
 *   toy-supsig rotate   the 20 rounds, under the signal storm
 *
 * Environment: TOY_STATE, the state directory.
 */
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile int stop, caught;

static void on_usr1(int s) { (void)s; caught++; }

static void *storm(void *arg) {
    pid_t me = getpid();
    (void)arg;
    while (!stop) { kill(me, SIGUSR1); usleep(50); }
    return 0;
}

int main(int argc, char **argv) {
    const char *st = getenv("TOY_STATE");
    char tmp[512], dst[512];
    if (!st || argc < 2) return 2;
    snprintf(tmp, sizeof tmp, "%s/f.tmp", st);
    snprintf(dst, sizeof dst, "%s/f", st);
    if (!strcmp(argv[1], "init")) {
        int fd = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, "0\n", 2) != 2) return 1;
        close(fd);
        return 0;
    }
    if (strcmp(argv[1], "rotate")) return 2;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGUSR1, &sa, 0);
    pthread_t t;
    pthread_create(&t, 0, storm, 0);
    for (int i = 0; i < 20; i++) {
        int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0 || write(fd, "x\n", 2) != 2) return 1;
        fsync(fd);
        close(fd);
        if (rename(tmp, dst)) return 1;
    }
    stop = 1;
    pthread_join(t, 0);
    printf("signals caught: %d\n", caught);
    return 0;
}
