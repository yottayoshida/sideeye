/* #543's fixture: a thread whose creation the shim never records.
 *
 * The shim replaces `pthread_create` with its own `@export`ed symbol and writes a
 * `.thread` boundary record there (`shim/src/ops.zig`). A program that reaches libc's
 * `pthread_create` through a handle instead of through the symbol gets a completely
 * ordinary thread that the shim never saw created — which is what a raw `clone` also
 * produces, without a raw `clone`'s undefined behaviour. Rolling a `clone(2)` by hand
 * means the new thread shares the parent's TLS block unless CLONE_SETTLS is arranged, and
 * calling libc from such a thread is outside what glibc promises; ADR 0055 decision 1
 * declined `threadlocal` in the shim for that same reason, so a fixture that depends on it
 * would prove things about one glibc and one ordering rather than about the rule.
 *
 * `dlsym(RTLD_NEXT, "pthread_create")` does NOT work here. The next object after the
 * executable is the preloaded shim, so RTLD_NEXT hands back the shim's own symbol and the
 * thread is recorded after all. It has to be a handle on libc.
 *
 * What the shim still sees is every OPERATION the thread performs: its wrappers are
 * process-wide and each record carries the calling thread's id. So this fixture separates
 * the two halves that #543 is about — the creation is invisible, the writes are not.
 *
 *   init        seed the two files the modes below rewrite
 *   both-libc   the main thread rewrites one file, the unrecorded thread the other
 *               -> two writing threads, refused by the v16 rule from the trace alone
 *   child-only  ONLY the unrecorded thread writes
 *               -> one writing thread, judged, and the account has to say the shim's
 *                  thread count is a floor
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*pcreate_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);

static const char *state_dir(void) {
    const char *d = getenv("PROBE_STATE");
    if (!d || !*d) d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static int writefile(const char *name, const char *content) {
    char p[4096];
    snprintf(p, sizeof p, "%s/%s", state_dir(), name);
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror("open"); return 1; }
    if (write(fd, content, strlen(content)) != (ssize_t)strlen(content)) { perror("write"); return 1; }
    if (fsync(fd) != 0) { perror("fsync"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    return 0;
}

static void *worker(void *arg) {
    return writefile((const char *)arg, "worker\n") ? (void *)1 : NULL;
}

/* libc's own `pthread_create`, by handle. `libc.so.6` carries it from glibc 2.34; before
 * that it lived in `libpthread.so.0`. Both are tried and a failure is fatal rather than a
 * silent fall back to the interposed symbol — a fixture that quietly measures the wrong
 * thing is worse than one that does not run. */
static pcreate_fn libc_pthread_create(void) {
    static const char *soname[] = { "libc.so.6", "libpthread.so.0" };
    for (unsigned i = 0; i < sizeof soname / sizeof soname[0]; i++) {
        void *h = dlopen(soname[i], RTLD_LAZY | RTLD_NOLOAD);
        if (!h) h = dlopen(soname[i], RTLD_LAZY);
        if (!h) continue;
        pcreate_fn f = (pcreate_fn)dlsym(h, "pthread_create");
        if (f) return f;
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s init|both-libc|child-only\n", argv[0]);
        return 2;
    }
    const char *mode = argv[1];
    if (strcmp(mode, "init") == 0)
        return (writefile("a", "0\n") || writefile("b", "0\n")) ? 1 : 0;

    if (strcmp(mode, "both-libc") != 0 && strcmp(mode, "child-only") != 0) {
        fprintf(stderr, "unknown mode: %s\n", mode);
        return 2;
    }

    pcreate_fn create = libc_pthread_create();
    if (!create) { fprintf(stderr, "could not resolve libc pthread_create\n"); return 3; }

    /* The main thread writes first in both-libc, so a second writer is unambiguous. */
    if (strcmp(mode, "both-libc") == 0 && writefile("a", "main\n")) return 1;

    const char *target = (strcmp(mode, "both-libc") == 0) ? "b" : "a";
    pthread_t t;
    if (create(&t, NULL, worker, (void *)target) != 0) { fprintf(stderr, "pthread_create failed\n"); return 4; }
    void *rv = NULL;
    /* Joined through the ordinary symbol: the shim does not interpose `pthread_join`
     * (that is #539), so nothing is bypassed here and the thread is properly reaped. */
    if (pthread_join(t, &rv) != 0) { fprintf(stderr, "pthread_join failed\n"); return 5; }
    return rv == NULL ? 0 : 1;
}
