/*
 * Four rewrites of one file, for the rerun invariant:
 *   lock    takes key.lock with O_EXCL, rewrites key and drops the lock; a crash that leaves the
 *           lock makes the next run refuse, so it ends as neither a clean run does
 *   rename  writes key.tmp and renames it over key; the next run from any crash state finishes
 *   temp    the same through a mkstemp name, which a crash leaves behind and the next run ignores
 *   clock   writes the time into key, so no two runs end alike
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void path_of(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

static int put(int fd, const char *s) {
    size_t n = strlen(s);
    return write(fd, s, n) == (ssize_t)n ? 0 : -1;
}

static int write_named(const char *name, const char *content, int flags) {
    char p[4096];
    path_of(p, sizeof p, name);
    int fd = open(p, O_WRONLY | O_CREAT | flags, 0644);
    if (fd < 0) return -1;
    int rc = put(fd, content);
    fsync(fd);
    close(fd);
    return rc;
}

static int replace_with(const char *from_name, const char *content) {
    if (write_named(from_name, content, O_TRUNC) != 0) return 1;
    char from[4096], to[4096];
    path_of(from, sizeof from, from_name);
    path_of(to, sizeof to, "key");
    return rename(from, to) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 64;
    if (strcmp(argv[1], "init") == 0) {
        mkdir(state_dir(), 0755);
        return write_named("key", "v1\n", O_TRUNC) == 0 ? 0 : 1;
    }
    if (strcmp(argv[1], "lock") == 0) {
        if (write_named("key.lock", "held\n", O_EXCL) != 0) return 1;
        if (replace_with("key.tmp", "v2\n") != 0) return 1;
        char lock[4096];
        path_of(lock, sizeof lock, "key.lock");
        return unlink(lock) == 0 ? 0 : 1;
    }
    if (strcmp(argv[1], "rename") == 0) return replace_with("key.tmp", "v2\n");
    if (strcmp(argv[1], "temp") == 0) {
        char tmpl[4096];
        path_of(tmpl, sizeof tmpl, "key.XXXXXX");
        int fd = mkstemp(tmpl);
        if (fd < 0 || put(fd, "v2\n") != 0) return 1;
        fsync(fd);
        close(fd);
        char to[4096];
        path_of(to, sizeof to, "key");
        return rename(tmpl, to) == 0 ? 0 : 1;
    }
    if (strcmp(argv[1], "clock") == 0) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);
        char line[64];
        snprintf(line, sizeof line, "%lld.%09ld\n", (long long)ts.tv_sec, ts.tv_nsec);
        return replace_with("key.tmp", line);
    }
    return 64;
}
