/* Parent writes op1, forks a child that writes op2 and exits, waits, then writes op3.
   The shape item 3 calls the slice: one writer at a time, each child awaited. */
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
    char a[512], b[512], c[512];
    snprintf(a, sizeof a, "%s/a", dir);
    snprintf(b, sizeof b, "%s/b", dir);
    snprintf(c, sizeof c, "%s/c", dir);
    put(a, "1");
    pid_t p = fork();
    if (p == 0) { put(b, "2"); _exit(0); }
    int st = 0;
    if (waitpid(p, &st, 0) < 0) { perror("waitpid"); exit(1); }
    put(c, "3");
    return 0;
}
