#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static const char *state;

static int path_of(char *out, size_t n, const char *name) {
    return snprintf(out, n, "%s/%s", state, name) < (int)n ? 0 : -1;
}

static int write_to(const char *name, int flags, const char *bytes) {
    char p[4096];
    if (path_of(p, sizeof p, name) != 0) return -1;
    int fd = open(p, O_WRONLY | flags, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(bytes);
    if (write(fd, bytes, len) != (ssize_t)len) { close(fd); return -1; }
    return close(fd);
}

static int rename_to(const char *from, const char *to) {
    char a[4096], b[4096];
    if (path_of(a, sizeof a, from) != 0 || path_of(b, sizeof b, to) != 0) return -1;
    return rename(a, b);
}

static int make_dir(const char *name) {
    char p[4096];
    if (path_of(p, sizeof p, name) != 0) return -1;
    return mkdir(p, 0755) == 0 || errno == EEXIST ? 0 : -1;
}

static int remove_dir(const char *name) {
    char p[4096];
    if (path_of(p, sizeof p, name) != 0) return -1;
    return rmdir(p);
}

int main(int argc, char **argv) {
    state = getenv("TOY_STATE");
    if (!state || argc != 2) {
        fprintf(stderr, "usage: TOY_STATE=<dir> [TOY_ORDER_FLIP=1] toy-order init|pair|tmp|uuid|mixed|redir|mkexist\n");
        return 2;
    }
    const char *mode = argv[1];
    const char *f = getenv("TOY_ORDER_FLIP");
    const char *ka = getenv("SIDEEYE_KILL_AT");
    const int flip = f && strcmp(f, "1") == 0 && ka && *ka;
    const char *first = flip ? "beta" : "alpha";
    const char *second = flip ? "alpha" : "beta";
    const char *dir_first = flip ? "d2" : "d1";
    const char *dir_second = flip ? "d1" : "d2";
    const unsigned suffix = (unsigned)getpid() ^ (unsigned)time(NULL);
    char t1[64], t2[64];

    if (strcmp(mode, "init") == 0) {
        if (mkdir(state, 0755) != 0 && errno != EEXIST) return 2;
        if (write_to("alpha", O_CREAT | O_TRUNC, "old\n") || write_to("beta", O_CREAT | O_TRUNC, "old\n")) return 2;
        return make_dir("d1") || make_dir("d2") ? 2 : 0;
    }
    if (strcmp(mode, "pair") == 0)
        return write_to(first, O_TRUNC, "new\n") || write_to(second, O_TRUNC, "new\n") ? 2 : 0;
    if (strcmp(mode, "tmp") == 0) {
        snprintf(t1, sizeof t1, "%s.tmp", first);
        snprintf(t2, sizeof t2, "%s.tmp", second);
        if (write_to(t1, O_CREAT | O_TRUNC, "new\n") || write_to(t2, O_CREAT | O_TRUNC, "new\n")) return 2;
        return rename_to(t1, first) || rename_to(t2, second) ? 2 : 0;
    }
    if (strcmp(mode, "uuid") == 0) {
        snprintf(t1, sizeof t1, "alpha.%u.tmp", suffix);
        snprintf(t2, sizeof t2, "beta.%u.tmp", suffix);
        if (write_to(t1, O_CREAT | O_TRUNC, "new\n") || rename_to(t1, "alpha")) return 2;
        return write_to(t2, O_CREAT | O_TRUNC, "new\n") || rename_to(t2, "beta") ? 2 : 0;
    }
    if (strcmp(mode, "mixed") == 0) {
        snprintf(t2, sizeof t2, "beta.%u.tmp", suffix);
        if (!flip && write_to("alpha", O_TRUNC, "new\n")) return 2;
        if (write_to(t2, O_CREAT | O_TRUNC, "new\n") || rename_to(t2, "beta")) return 2;
        return flip && write_to("alpha", O_TRUNC, "new\n") ? 2 : 0;
    }
    if (strcmp(mode, "redir") == 0) {
        if (remove_dir("d1") || remove_dir("d2")) return 2;
        return make_dir(dir_first) || make_dir(dir_second) ? 2 : 0;
    }
    if (strcmp(mode, "mkexist") == 0) {
        if (make_dir(dir_first) || make_dir(dir_second)) return 2;
        return write_to("alpha", O_TRUNC, "new\n") ? 2 : 0;
    }
    return 2;
}
