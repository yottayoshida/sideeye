#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("SIDEEYE_STATE_DIR");
    if (!d || !*d) d = getenv("TOY_STATE");
    return d && *d ? d : "./state";
}

static char *at(char *out, const char *name) {
    snprintf(out, 4096, "%s/%s", state_dir(), name);
    return out;
}

static int put(const char *name, const char *content) {
    char p[4096];
    int fd = open(at(p, name), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t n = strlen(content);
    if (write(fd, content, n) != (ssize_t)n || fsync(fd) != 0) { close(fd); return -1; }
    return close(fd);
}

static int unrecorded_put(const char *name, const char *content) {
    char p[4096];
    long fd = syscall(SYS_openat, AT_FDCWD, at(p, name), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    syscall(SYS_write, (int)fd, content, strlen(content));
    return (int)syscall(SYS_close, (int)fd);
}

static int unrecorded_unlink(const char *name) {
    char p[4096];
    return (int)syscall(SYS_unlinkat, AT_FDCWD, at(p, name), 0);
}

static int mk(const char *name) {
    char p[4096];
    return mkdir(at(p, name), 0755);
}

static int mv(const char *from, const char *to) {
    char a[4096], b[4096];
    return rename(at(a, from), at(b, to));
}

static int rm(const char *name) {
    char p[4096];
    return unlink(at(p, name));
}

static int rd(const char *name) {
    char p[4096];
    return rmdir(at(p, name));
}

static int holds(const char *name, const char *want) {
    char p[4096], buf[64];
    int fd = open(at(p, name), O_RDONLY);
    if (fd < 0) return 0;
    ssize_t n = read(fd, buf, sizeof buf);
    close(fd);
    return n == (ssize_t)strlen(want) && memcmp(buf, want, (size_t)n) == 0;
}

static int exists(const char *name) {
    char p[4096];
    struct stat st;
    return lstat(at(p, name), &st) == 0;
}

int main(int argc, char **argv) {
    const char *m = argc > 1 ? argv[1] : "";
    if (!strcmp(m, "init-publish")) return put("keep", "K");
    if (!strcmp(m, "init-swap")) return mk("cur") || put("cur/x", "X");
    if (!strcmp(m, "init-enotempty")) return mk("b") || put("b/x", "OLD");
    if (!strcmp(m, "publish")) return mk("gen.tmp") || put("gen.tmp/data", "D") || mv("gen.tmp", "gen");
    if (!strcmp(m, "swap"))
        return mk("new") || put("new/y", "Y") || mv("cur", "old") || mv("new", "cur") || rm("old/x") || rd("old");
    if (!strcmp(m, "ctl-rewrite")) return mv("cur", "old") || mk("cur") || unrecorded_put("old/x", "EVIL");
    if (!strcmp(m, "ctl-delete")) return mv("cur", "old") || unrecorded_unlink("old/x");
    if (!strcmp(m, "ctl-enotempty")) {
        if (mk("a") || put("a/x", "NEW")) return 1;
        if (mv("a", "b") == 0 || (errno != ENOTEMPTY && errno != EEXIST)) return 1;
        return rm("a/x") || rd("a") || unrecorded_put("b/x", "EVIL");
    }
    if (!strcmp(m, "check-publish")) return !holds("keep", "K") || (exists("gen") && !holds("gen/data", "D"));
    if (!strcmp(m, "check-swap")) return holds("cur/x", "X") == holds("cur/y", "Y");
    fprintf(stderr, "usage: toy-dirswap init-publish|init-swap|init-enotempty|publish|swap|"
                    "ctl-rewrite|ctl-delete|ctl-enotempty|check-publish|check-swap (got %s)\n", m);
    return 2;
}
