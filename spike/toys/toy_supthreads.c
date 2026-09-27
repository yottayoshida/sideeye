/*
 * --observe supervised's thread wall (#217, ADR 0089).
 *
 * Two threads write the state directory, one after the other: the main thread writes `a`,
 * creates a thread that writes `b`, and joins it. Under a shim the creation and the join are
 * recorded (contract v18) and order the two writers, so the run is judged. Under
 * --observe supervised no thread-order record exists -- they are read inside pthread_create
 * and pthread_join, which only a shim sees -- so the second writer is unordered and the run
 * refuses multiple_threads_detected rather than judge an order it cannot establish.
 *
 *   toy-supthreads init     create the state directory's files
 *   toy-supthreads rotate   the two writes
 *
 * Environment: TOY_STATE, the state directory.
 */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char base[480];

static int put(const char *name) {
    char p[512];
    snprintf(p, sizeof p, "%s/%s", base, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 || write(fd, "x\n", 2) != 2) return 1;
    return close(fd);
}

static void *second(void *arg) { (void)arg; put("b"); return 0; }

int main(int argc, char **argv) {
    const char *st = getenv("TOY_STATE");
    if (!st || argc < 2) return 2;
    snprintf(base, sizeof base, "%s", st);
    if (!strcmp(argv[1], "init")) return put("a") | put("b");
    if (strcmp(argv[1], "rotate")) return 2;
    if (put("a")) return 1;
    pthread_t t;
    pthread_create(&t, 0, second, 0);
    pthread_join(t, 0);
    return 0;
}
