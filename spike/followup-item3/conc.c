/* Two children forked before either is awaited: both write, spans overlap.
   The negative control — this must stay refused. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <string.h>

static void put(const char *p, const char *s) {
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror("open"); exit(1); }
    if (write(fd, s, strlen(s)) < 0) { perror("write"); exit(1); }
    close(fd);
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "/w/state";
    char x[512], y[512];
    snprintf(x, sizeof x, "%s/x", dir);
    snprintf(y, sizeof y, "%s/y", dir);
    pid_t p1 = fork();
    if (p1 == 0) { usleep(20000); put(x, "x"); _exit(0); }
    pid_t p2 = fork();
    if (p2 == 0) { usleep(20000); put(y, "y"); _exit(0); }
    int st = 0;
    waitpid(p1, &st, 0);
    waitpid(p2, &st, 0);
    return 0;
}
