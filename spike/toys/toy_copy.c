/*
 * The rotation performed by the kernel's copy primitives.
 *
 * `copy_file_range` is what Rust's `fs::copy` and CPython's `shutil` reach for first,
 * and it is the syscall whose refusal is the reason `spike/cohort4/himalaya-r2`
 * exists. This toy calls it directly, so the leg driving it does not depend on any
 * language runtime's internal choice of primitive (#244).
 *
 * Two directions matter and the toy can do both, because the engine must answer
 * differently for each:
 *   rotate      — destination inside the state directory: a write that counts
 *   read-out    — source inside, destination outside: nothing in the state changes
 * The second is why the in-scope decision cannot read argument 0: for
 * copy_file_range the destination is argument 2.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *d = getenv("TOY_STATE");
    return (d && *d) ? d : "./state";
}

/* Where the out-of-state end of a copy lives, so the leg can point it anywhere. */
static const char *outside_dir(void) {
    const char *d = getenv("TOY_OUTSIDE");
    return (d && *d) ? d : "/tmp";
}

static void join_path(char *out, size_t n, const char *dir, const char *name) {
    snprintf(out, n, "%s/%s", dir, name);
}

static int write_plain(const char *path, const char *content) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    if (write(fd, content, (size_t)len) != (ssize_t)len) { close(fd); return -1; }
    if (fsync(fd) != 0) { close(fd); return -1; }
    close(fd);
    return 0;
}

/*
 * One copy_file_range call, source to destination. Returns -1 with errno intact when
 * the kernel or a preloaded library refuses, so the caller can report which.
 */
static int copy_range(const char *src, const char *dst) {
    int in = open(src, O_RDONLY);
    if (in < 0) return -1;
    struct stat st;
    if (fstat(in, &st) != 0) { close(in); return -1; }
    int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { close(in); return -1; }

    size_t remaining = (size_t)st.st_size;
    while (remaining > 0) {
        ssize_t n = copy_file_range(in, NULL, out, NULL, remaining, 0);
        if (n <= 0) {
            int saved = errno;
            close(in);
            close(out);
            errno = saved;
            return -1;
        }
        remaining -= (size_t)n;
    }
    if (fsync(out) != 0) { close(in); close(out); return -1; }
    close(in);
    close(out);
    return 0;
}

static int cmd_init(void) {
    if (mkdir(state_dir(), 0755) != 0 && errno != EEXIST) return 1;
    char key[4096], src[4096];
    join_path(key, sizeof key, state_dir(), "key.json");
    join_path(src, sizeof src, outside_dir(), "toy-copy-source.txt");
    if (write_plain(key, "key=1\n") != 0) return 1;
    /* The copy source lives outside the state directory, so rotate's copy crosses in. */
    return write_plain(src, "key=2\n") == 0 ? 0 : 1;
}

/* Destination inside the state directory: the operation the engine must count. */
static int cmd_rotate(void) {
    char key[4096], src[4096];
    join_path(key, sizeof key, state_dir(), "key.json");
    join_path(src, sizeof src, outside_dir(), "toy-copy-source.txt");
    if (copy_range(src, key) != 0) {
        fprintf(stderr, "copy_file_range failed: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}

/* Source inside, destination outside: the state is only read. */
static int cmd_read_out(void) {
    char key[4096], dst[4096];
    join_path(key, sizeof key, state_dir(), "key.json");
    join_path(dst, sizeof dst, outside_dir(), "toy-copy-readout.txt");
    if (copy_range(key, dst) != 0) {
        fprintf(stderr, "copy_file_range failed: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}

static int cmd_load_key(void) {
    char path[4096], buf[256];
    join_path(path, sizeof path, state_dir(), "key.json");
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
    if (strcmp(argv[1], "read-out") == 0) return cmd_read_out();
    if (strcmp(argv[1], "load-key") == 0) return cmd_load_key();
    return 2;
}
