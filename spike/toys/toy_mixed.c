/*
 * Half through libc, half around it.
 *
 * This is the target that defeats the structural detectors on its own. It performs one
 * ordinary libc operation — which the shim sees, so `mutation_count` is non-zero and
 * `state_changed_without_ops` stays quiet — and then writes the actual key through a
 * raw syscall, which the shim cannot see at all. The resulting trace is short but not
 * empty, and looks like a complete account of a small operation.
 *
 * Only the oracle catches this, which is why PASS requires one.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

/* Ordinary libc: fully visible to the shim. */
static int libc_write_file(const char *path, const char *content) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    if (write(fd, content, len) != (ssize_t)len) { close(fd); return -1; }
    close(fd);
    return 0;
}

/* Straight to the kernel: invisible to the shim. */
static int raw_write_file(const char *path, const char *content) {
    long fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    syscall(SYS_write, (int)fd, content, len);
    syscall(SYS_close, (int)fd);
    return 0;
}

static int cmd_init(void) {
    if (mkdir(state_dir(), 0755) != 0 && errno != EEXIST) return 1;
    char key[4096], marker[4096];
    join_path(key, sizeof key, "key.json");
    join_path(marker, sizeof marker, "marker.txt");
    if (libc_write_file(marker, "v=1\n") != 0) return 1;
    return libc_write_file(key, "key=1\n") == 0 ? 0 : 1;
}

static int cmd_rotate(void) {
    char key[4096], marker[4096];
    join_path(key, sizeof key, "key.json");
    join_path(marker, sizeof marker, "marker.txt");

    /* Seen by the shim: something was mutated. */
    if (libc_write_file(marker, "v=2\n") != 0) return 1;

    /* Not seen by the shim: the key changes behind its back. */
    if (raw_write_file(key, "key=2\n") != 0) return 1;
    return 0;
}

static int cmd_doctor(void) {
    struct stat st;
    printf(stat(state_dir(), &st) == 0 && S_ISDIR(st.st_mode) ? "healthy\n" : "unhealthy\n");
    return 0;
}

static int cmd_load_key(void) {
    char path[4096], buf[256];
    join_path(path, sizeof path, "key.json");
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 1;
    ssize_t r = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (r <= 0) return 1;
    buf[r] = '\0';
    return strncmp(buf, "key=", 4) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) return cmd_rotate();
    if (strcmp(argv[1], "doctor") == 0) return cmd_doctor();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    return 2;
}
