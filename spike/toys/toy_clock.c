/* pin:clock's fixture.
 *
 *   toy-clock init   <state>   old contents, and the real time setup ended, in $TOY_CLOCK_LOG
 *   toy-clock time   <state>   the real time first (a raw syscall, past any preload), then after
 *                              1.1 s the wall clock through five libc entry points, into the state
 *   toy-clock waits  <state>   after 1.5 s, each listed wait woken at 0.3 s and left to its 1 s
 *                              deadline; the outcome into the state, the time taken into the log
 *   toy-clock migrate <state>  two migrations, each a file kept with the time it was applied
 *   toy-clock rewait <state>   a 1 s deadline waited on again after broadcasts every 0.5 s for 3 s
 *
 * The sleeps put the pinned instant further back than any deadline: a pin that reads the clock
 * but does not translate a wait then sees every deadline already past.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <mqueue.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static const char *state, *logdir;

static double real_now(void) {
    struct timespec t;
    syscall(SYS_clock_gettime, CLOCK_REALTIME, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static double mono(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void sleep_s(double s) {
    struct timespec d = {(time_t)s, (long)((s - (time_t)s) * 1e9)};
    while (nanosleep(&d, &d) == -1 && errno == EINTR) {
    }
}

static void put(const char *dir, const char *name, const char *text, int append) {
    char path[4096], tmp[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    if (append) {
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0 || write(fd, text, strlen(text)) < 0) exit(2);
        close(fd);
        return;
    }
    snprintf(tmp, sizeof tmp, "%s/%s.tmp", dir, name);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0 || write(fd, text, strlen(text)) < 0) exit(2);
    fsync(fd);
    close(fd);
    if (rename(tmp, path) != 0) exit(2);
}

static void logf_(const char *name, const char *fmt, double v) {
    char line[256];
    snprintf(line, sizeof line, fmt, (long)getpid(), v);
    put(logdir, name, line, 1);
}

static struct timespec deadline(clockid_t clk, double after) {
    struct timespec t;
    clock_gettime(clk, &t);
    t.tv_sec += (time_t)after;
    return t;
}

static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t held = PTHREAD_MUTEX_INITIALIZER;
static pthread_rwlock_t rw = PTHREAD_RWLOCK_INITIALIZER;
static pthread_cond_t cv;
static sem_t sem;
static mqd_t mq = (mqd_t)-1;
static int ready, wake, broadcasts;
static const char *prim;
static pthread_barrier_t helper_has_it;

static int is(const char *a, const char *b) { return !strcmp(a, b); }
static int mutexish(const char *p) { return is(p, "mutex") || is(p, "mclock"); }
static int rwish(const char *p) { return is(p, "rwlock") || is(p, "rwwr") || is(p, "rwclock") || is(p, "rwclockwr"); }
static int semish(const char *p) { return is(p, "sem") || is(p, "sclock"); }
static int joinish(const char *p) { return is(p, "join") || is(p, "cjoin"); }
static int mqish(const char *p) { return is(p, "mq") || is(p, "mqsend"); }

static void *helper(void *arg) {
    (void)arg;
    if (mutexish(prim)) pthread_mutex_lock(&held);
    if (rwish(prim)) pthread_rwlock_wrlock(&rw);
    pthread_barrier_wait(&helper_has_it);
    if (broadcasts) {
        for (int i = 0; i < 6; i++) {
            sleep_s(0.5);
            pthread_mutex_lock(&m);
            pthread_cond_broadcast(&cv);
            pthread_mutex_unlock(&m);
        }
        return 0;
    }
    sleep_s(wake ? 0.3 : 1.2);
    char buf[8];
    if (mutexish(prim)) pthread_mutex_unlock(&held);
    else if (rwish(prim)) pthread_rwlock_unlock(&rw);
    else if (semish(prim)) sem_post(&sem);
    else if (is(prim, "mq")) mq_send(mq, "x", 1, 0);
    else if (is(prim, "mqsend")) mq_receive(mq, buf, sizeof buf, 0);
    else if (!joinish(prim)) {
        pthread_mutex_lock(&m);
        ready = 1;
        pthread_cond_signal(&cv);
        pthread_mutex_unlock(&m);
    }
    return 0;
}

static const char *one_wait(const char *p, int woken, double *took) {
    prim = p;
    wake = woken;
    ready = 0;
    pthread_condattr_t ca;
    pthread_condattr_init(&ca);
    clockid_t clk = CLOCK_REALTIME;
    if (is(p, "mcond")) {
        pthread_condattr_setclock(&ca, CLOCK_MONOTONIC);
        clk = CLOCK_MONOTONIC;
    }
    pthread_cond_init(&cv, &ca);
    sem_init(&sem, 0, 0);
    if (mqish(p)) {
        struct mq_attr a = {0, 1, 8, 0};
        char name[64];
        snprintf(name, sizeof name, "/toy-clock-%ld", (long)getpid());
        mq_unlink(name);
        mq = mq_open(name, O_RDWR | O_CREAT | O_EXCL, 0600, &a);
        mq_unlink(name);
        if (mq == (mqd_t)-1) return "unavailable";
        if (is(p, "mqsend")) mq_send(mq, "x", 1, 0);
    }
    pthread_barrier_init(&helper_has_it, 0, 2);
    pthread_t th;
    pthread_create(&th, 0, helper, 0);
    pthread_barrier_wait(&helper_has_it);
    struct timespec ts = deadline(clk, 1);
    int rc = 0;
    double t0 = mono();
    char buf[8];
    if (is(p, "cond") || is(p, "mcond") || is(p, "clockwait")) {
        pthread_mutex_lock(&m);
        while (!ready && rc != ETIMEDOUT)
            rc = is(p, "clockwait") ? pthread_cond_clockwait(&cv, &m, CLOCK_REALTIME, &ts) : pthread_cond_timedwait(&cv, &m, &ts);
        pthread_mutex_unlock(&m);
    } else if (semish(p)) {
        while ((rc = is(p, "sem") ? sem_timedwait(&sem, &ts) : sem_clockwait(&sem, CLOCK_REALTIME, &ts)) == -1 && errno == EINTR) {
        }
        rc = rc ? errno : 0;
    } else if (mutexish(p)) {
        rc = is(p, "mutex") ? pthread_mutex_timedlock(&held, &ts) : pthread_mutex_clocklock(&held, CLOCK_REALTIME, &ts);
        if (rc == 0) pthread_mutex_unlock(&held);
    } else if (rwish(p)) {
        rc = is(p, "rwlock")      ? pthread_rwlock_timedrdlock(&rw, &ts)
             : is(p, "rwwr")      ? pthread_rwlock_timedwrlock(&rw, &ts)
             : is(p, "rwclock")   ? pthread_rwlock_clockrdlock(&rw, CLOCK_REALTIME, &ts)
                                  : pthread_rwlock_clockwrlock(&rw, CLOCK_REALTIME, &ts);
        if (rc == 0) pthread_rwlock_unlock(&rw);
    } else if (is(p, "mq")) {
        rc = mq_timedreceive(mq, buf, sizeof buf, 0, &ts) < 0 ? errno : 0;
    } else if (is(p, "mqsend")) {
        rc = mq_timedsend(mq, "y", 1, 0, &ts) < 0 ? errno : 0;
    } else if (is(p, "nanosleep")) {
        rc = clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &ts, 0);
        if (rc == 0) rc = ETIMEDOUT;
    } else if (joinish(p)) {
        rc = is(p, "join") ? pthread_timedjoin_np(th, 0, &ts) : pthread_clockjoin_np(th, 0, CLOCK_REALTIME, &ts);
    }
    *took = mono() - t0;
    if (!joinish(p) || rc != 0) pthread_join(th, 0);
    if (mq != (mqd_t)-1) mq_close(mq), mq = (mqd_t)-1;
    pthread_barrier_destroy(&helper_has_it);
    pthread_cond_destroy(&cv);
    sem_destroy(&sem);
    return rc == ETIMEDOUT ? "timeout" : rc == 0 ? "woken" : "error";
}

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    state = argv[2];
    logdir = getenv("TOY_CLOCK_LOG");
    if (!logdir) return 64;
    if (!strcmp(argv[1], "init")) {
        put(state, "time.txt", "old\n", 0);
        put(state, "waits.txt", "old\n", 0);
        logf_("setup", "%ld %.9f\n", real_now());
        return 0;
    }
    if (!strcmp(argv[1], "time")) {
        logf_("opstart", "%ld %.9f\n", real_now());
        sleep_s(1.1);
        struct timespec a, b, e;
        struct timeval tv;
        clock_gettime(CLOCK_REALTIME, &a);
        clock_gettime(CLOCK_REALTIME_COARSE, &b);
        time_t t = time(0);
        gettimeofday(&tv, 0);
        timespec_get(&e, TIME_UTC);
        char text[512];
        snprintf(text, sizeof text,
                 "clock_gettime %ld.%09ld\ncoarse %ld.%09ld\ntime %ld\ngettimeofday %ld.%06ld\ntimespec_get %ld.%09ld\n",
                 (long)a.tv_sec, a.tv_nsec, (long)b.tv_sec, b.tv_nsec, (long)t, (long)tv.tv_sec, (long)tv.tv_usec,
                 (long)e.tv_sec, e.tv_nsec);
        put(state, "time.txt", text, 0);
        logf_("seen", "%ld %.9f\n", a.tv_sec + a.tv_nsec / 1e9);
        return 0;
    }
    if (!strcmp(argv[1], "waits")) {
        static const char *prims[] = {"cond", "mcond", "clockwait", "sem", "sclock", "mutex", "mclock", "rwlock", "rwwr",
                                      "rwclock", "rwclockwr", "mq", "mqsend", "join", "cjoin", "nanosleep"};
        char text[4096] = "", line[128];
        sleep_s(1.5);
        for (size_t i = 0; i < sizeof prims / sizeof *prims; i++) {
            for (int woken = 1; woken >= 0; woken--) {
                if (woken && !strcmp(prims[i], "nanosleep")) continue;
                double took;
                const char *r = one_wait(prims[i], woken, &took);
                snprintf(line, sizeof line, "%s %s %s\n", prims[i], woken ? "woken-at-0.3" : "deadline-1", r);
                strcat(text, line);
                char lname[64];
                snprintf(lname, sizeof lname, "%%ld %s %s %%.3f\n", prims[i], woken ? "woken-at-0.3" : "deadline-1");
                logf_("waits", lname, took);
            }
        }
        put(state, "waits.txt", text, 0);
        return 0;
    }
    if (!strcmp(argv[1], "migrate")) {
        for (int k = 1; k <= 2; k++) {
            char name[32], path[4096], text[64];
            snprintf(name, sizeof name, "m%d.txt", k);
            snprintf(path, sizeof path, "%s/%s", state, name);
            if (access(path, F_OK) == 0) continue;
            struct timespec now;
            clock_gettime(CLOCK_REALTIME, &now);
            snprintf(text, sizeof text, "applied %ld.%09ld\n", (long)now.tv_sec, now.tv_nsec);
            put(state, name, text, 0);
        }
        return 0;
    }
    if (!strcmp(argv[1], "rewait")) {
        prim = "cond";
        broadcasts = 1;
        pthread_cond_init(&cv, 0);
        pthread_barrier_init(&helper_has_it, 0, 2);
        pthread_t th;
        pthread_create(&th, 0, helper, 0);
        pthread_barrier_wait(&helper_has_it);
        struct timespec ts = deadline(CLOCK_REALTIME, 1);
        double t0 = mono();
        int rc = 0;
        pthread_mutex_lock(&m);
        while (rc != ETIMEDOUT) rc = pthread_cond_timedwait(&cv, &m, &ts);
        pthread_mutex_unlock(&m);
        logf_("rewait", "%ld %.3f\n", mono() - t0);
        pthread_join(th, 0);
        put(state, "waits.txt", "rewait timeout\n", 0);
        return 0;
    }
    return 64;
}
