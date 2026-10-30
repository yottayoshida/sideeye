/* The control #987's measurement must refuse: two threads, released together, each write their own
 * eight bytes to the same offset of one file fifty times, yielding between writes, with nothing ordering
 * them. Three writes each left the same thread last in 20 runs of 20; fifty with a yield, 17 and 3. */
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <unistd.h>

static int fd;
static pthread_barrier_t go;

static void *writer(void *arg) {
    const char *text = arg;
    pthread_barrier_wait(&go);
    for (int i = 0; i < 50; i++) {
        if (pwrite(fd, text, 8, 0) != 8) _exit(2);
        sched_yield();
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    char p[4096];
    snprintf(p, sizeof p, "%s/r", argv[1]);
    fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return 2;
    pthread_barrier_init(&go, 0, 2);
    pthread_t a, b;
    if (pthread_create(&a, 0, writer, "AAAAAAAA") || pthread_create(&b, 0, writer, "BBBBBBBB")) return 2;
    pthread_join(a, 0);
    pthread_join(b, 0);
    return close(fd) != 0;
}
