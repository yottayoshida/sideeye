/*
 * A minimal stateful CLI, in the shape sideeye is meant to interrogate.
 *
 * Build twice from this one file:
 *   -DBUGGY=1  -> rotate deletes the current key before renaming the new one in,
 *                 so a crash inside that window leaves no key at all.
 *   (default)  -> rotate renames over the current key, which is atomic.
 *
 * `doctor` is deliberately shallow: it reports health from the existence of the
 * state directory and never checks whether the key can actually be read. That is
 * the self-contradiction check.sh cross-examines — the diagnostic says healthy
 * while the thing it is diagnosing is unusable.
 *
 * Environment:
 *   TOY_STATE   state directory (default ./state)
 *   TOY_FORK    if set, fork a trivial child before rotating (boundary case)
 *   TOY_THREAD  if set, create and join a trivial thread before rotating
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define KEY_NAME "key.json"
#define TMP_NAME "key.json.tmp"

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

static int write_file(const char *path, const char *content) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(fd, content + off, len - off);
        if (w <= 0) { close(fd); return -1; }
        off += (size_t)w;
    }
    if (fsync(fd) != 0) { close(fd); return -1; }
    if (close(fd) != 0) return -1;
    return 0;
}

static int read_key(char *buf, size_t n) {
    char path[4096];
    join_path(path, sizeof path, KEY_NAME);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    ssize_t r = read(fd, buf, n - 1);
    close(fd);
    if (r <= 0) return -1;
    buf[r] = '\0';
    return 0;
}

static void *noop_thread(void *arg) {
    (void)arg;
    return NULL;
}

/* Optional boundary behaviour, requested through the environment so one binary
 * can play both the supported and the unsupported target. */
static void maybe_leave_the_supported_region(void) {
    if (getenv("TOY_FORK")) {
        pid_t p = fork();
        if (p == 0) _exit(0);
        if (p > 0) { int st; waitpid(p, &st, 0); }
    }
    if (getenv("TOY_THREAD")) {
        pthread_t t;
        if (pthread_create(&t, NULL, noop_thread, NULL) == 0) pthread_join(t, NULL);
    }
}

static int cmd_init(void) {
    if (mkdir(state_dir(), 0755) != 0 && errno != EEXIST) return 1;
    char key[4096];
    join_path(key, sizeof key, KEY_NAME);
    return write_file(key, "key=1\n") == 0 ? 0 : 1;
}

static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, KEY_NAME);
    join_path(tmp, sizeof tmp, TMP_NAME);

    maybe_leave_the_supported_region();

    if (write_file(tmp, "key=2\n") != 0) return 1;

#ifdef BUGGY
    /* The window: between these two calls there is no key on disk at all. */
    if (unlink(key) != 0 && errno != ENOENT) return 1;
#endif

    if (rename(tmp, key) != 0) return 1;
    return 0;
}

/* Reports health from the directory alone. Never opens the key. */
static int cmd_doctor(void) {
    struct stat st;
    if (stat(state_dir(), &st) == 0 && S_ISDIR(st.st_mode)) {
        printf("healthy\n");
        return 0;
    }
    printf("unhealthy\n");
    return 0;
}

static int cmd_load_key(void) {
    char buf[256];
    if (read_key(buf, sizeof buf) != 0) return 1;
    if (strncmp(buf, "key=", 4) != 0) return 1;
    printf("%s", buf);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s init|rotate|doctor|load-key\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) return cmd_rotate();
    if (strcmp(argv[1], "doctor") == 0) return cmd_doctor();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return 2;
}
