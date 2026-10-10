/* The ordered control (#687): every hand-over between the two writing threads is ordered by a
 * creation or an exit. The main thread writes `a`, then creates a worker that writes `b`, joins it
 * (the worker has exited), and writes `c`. Under --observe supervised this still refuses
 * multiple_threads_detected — that mode records no join — and its oracle capture must read as
 * "every hand-over ordered". */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char *dir;

static void put(const char *name, const char *text) {
    char p[4096];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) _exit(2);
    if (write(fd, text, strlen(text)) != (ssize_t)strlen(text)) _exit(2);
    close(fd);
}

static void *worker(void *arg) {
    (void)arg;
    put("b", "b\n");
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    dir = argv[1];
    put("a", "a\n");
    pthread_t t;
    if (pthread_create(&t, 0, worker, 0)) return 2;
    if (pthread_join(t, 0)) return 2;
    put("c", "c\n");
    return 0;
}
