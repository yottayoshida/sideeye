/* The unordered control (#687): the worker is created before anything is written and lives until
 * after the last write, and the two threads hand the state to each other through a condition
 * variable — so no creation and no exit falls between one writer's write and the other's. The main
 * thread writes `a`, the worker `b`, the main thread `c`; only then is the worker released and
 * joined. Its oracle capture must read as "a hand-over nothing orders". */
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const char *dir;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static int turn;

static void put(const char *name, const char *text) {
    char p[4096];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) _exit(2);
    if (write(fd, text, strlen(text)) != (ssize_t)strlen(text)) _exit(2);
    close(fd);
}

static void wait_for(int want) {
    pthread_mutex_lock(&mu);
    while (turn != want) pthread_cond_wait(&cv, &mu);
    pthread_mutex_unlock(&mu);
}

static void set_turn(int t) {
    pthread_mutex_lock(&mu);
    turn = t;
    pthread_cond_broadcast(&cv);
    pthread_mutex_unlock(&mu);
}

static void *worker(void *arg) {
    (void)arg;
    wait_for(1);
    put("b", "b\n");
    set_turn(2);
    wait_for(3); /* alive until the main thread's last write */
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    dir = argv[1];
    pthread_t t;
    if (pthread_create(&t, 0, worker, 0)) return 2;
    put("a", "a\n");
    set_turn(1);
    wait_for(2);
    put("c", "c\n");
    set_turn(3);
    if (pthread_join(t, 0)) return 2;
    return 0;
}
