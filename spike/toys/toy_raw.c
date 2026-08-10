/*
 * The same rotation, issued through syscall(2) instead of the libc wrappers.
 *
 * LD_PRELOAD replaces symbols; this binary never calls the symbols being replaced,
 * so the shim sees nothing at all. That is the point: from inside, an empty trace
 * looks exactly like a target that performed no file operations. Sideeye must not
 * read that as "nothing happened, therefore PASS" — the recording run's oracle and
 * the engine's state_changed_without_ops detector both exist for this binary.
 */

#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
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

static int raw_write_file(const char *path, const char *content) {
    long fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t len = strlen(content);
    size_t off = 0;
    while (off < len) {
        long w = syscall(SYS_write, (int)fd, content + off, len - off);
        if (w <= 0) { syscall(SYS_close, (int)fd); return -1; }
        off += (size_t)w;
    }
    syscall(SYS_fsync, (int)fd);
    syscall(SYS_close, (int)fd);
    return 0;
}

static int cmd_init(void) {
    syscall(SYS_mkdirat, AT_FDCWD, state_dir(), 0755);
    char key[4096];
    join_path(key, sizeof key, KEY_NAME);
    return raw_write_file(key, "key=1\n") == 0 ? 0 : 1;
}

static int cmd_rotate(void) {
    char key[4096], tmp[4096];
    join_path(key, sizeof key, KEY_NAME);
    join_path(tmp, sizeof tmp, TMP_NAME);

    if (raw_write_file(tmp, "key=2\n") != 0) return 1;
    syscall(SYS_unlinkat, AT_FDCWD, key, 0);
    if (syscall(SYS_renameat, AT_FDCWD, tmp, AT_FDCWD, key) != 0) return 1;
    return 0;
}

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
    char path[4096], buf[256];
    join_path(path, sizeof path, KEY_NAME);
    long fd = syscall(SYS_openat, AT_FDCWD, path, O_RDONLY, 0);
    if (fd < 0) return 1;
    long r = syscall(SYS_read, (int)fd, buf, sizeof buf - 1);
    syscall(SYS_close, (int)fd);
    if (r <= 0) return 1;
    buf[r] = '\0';
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
    return 2;
}
