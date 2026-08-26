/*
 * The same rotation, written through the vectored positional calls.
 *
 * `pwritev` and `pwritev2` are ordinary glibc symbols — no weak lookup, no raw
 * syscall, nothing behind the PLT. The oracle has classified them as writes since
 * v0.1 (`src/oracle.zig`); the shim simply never exported them, so a target that
 * writes this way is seen by one observer and not the other. On Linux that is an
 * honest `oracle_missed_operation`; on macOS, where no oracle exists, the write is
 * invisible to everything (#256).
 *
 * The state file's contents are asserted by the acceptance leg, not just the
 * verdict: a wrapper with the arguments in the wrong order records the operation
 * correctly and still writes the wrong bytes.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

/* Two iovecs, so a wrapper that mishandles the vector writes visibly wrong bytes. */
static int pwritev_file(const char *path, const char *head, const char *tail) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    struct iovec iov[2];
    iov[0].iov_base = (void *)head;
    iov[0].iov_len = strlen(head);
    iov[1].iov_base = (void *)tail;
    iov[1].iov_len = strlen(tail);
    ssize_t want = (ssize_t)(iov[0].iov_len + iov[1].iov_len);
    ssize_t got = pwritev(fd, iov, 2, 0);
    if (got != want) { close(fd); return -1; }
    if (fsync(fd) != 0) { close(fd); return -1; }
    close(fd);
    return 0;
}

static int cmd_init(void) {
    if (mkdir(state_dir(), 0755) != 0 && errno != EEXIST) return 1;
    char key[4096];
    join_path(key, sizeof key, "key.json");
    return pwritev_file(key, "key=", "1\n") == 0 ? 0 : 1;
}

/*
 * The same delete-before-rename window as the C toy, with the new content written
 * through pwritev. Whether this FAILs is not the point of the leg that drives it —
 * what matters is that the operation is counted at all.
 */
static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, "key.json");
    join_path(tmp, sizeof tmp, "key.json.tmp");

    if (pwritev_file(tmp, "key=", "2\n") != 0) return 1;
    if (unlink(key) != 0 && errno != ENOENT) return 1;
    if (rename(tmp, key) != 0) return 1;
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
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    return 2;
}
