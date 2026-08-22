/*
 * The same rotation as spike/toys/toy.c, written the way a C program that
 * wants an atomic replace usually writes it: mkstemp(3) for the temp file,
 * then write, then rename.
 *
 * The question this measures is #39's: mkstemp does not call open(2) through
 * the PLT — it opens inside libc, so an LD_PRELOAD interposer that replaces
 * `open` never sees it. Whether that is true, and what it costs, has no
 * recorded run in this repository ("Not yet measured", docs/target-classes.md).
 *
 * Two more members of the class are exercised beside it so the answer is not
 * one data point: dprintf(3) writes to a descriptor from inside libc, and
 * tmpfile(3) creates and unlinks one.
 */

#define _GNU_SOURCE
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

static void join_path(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", state_dir(), name);
}

/* The shape under test: mkstemp + write + fsync + rename. */
static int rotate_via_mkstemp(int value) {
    char tmpl[1024];
    char final_path[1024];
    char body[64];

    join_path(tmpl, sizeof(tmpl), "key.json.XXXXXX");
    join_path(final_path, sizeof(final_path), "key.json");

    int fd = mkstemp(tmpl);
    if (fd < 0) { perror("mkstemp"); return 1; }

    int n = snprintf(body, sizeof(body), "key=%d\n", value);
    if (write(fd, body, (size_t)n) != n) { perror("write"); return 1; }
    if (fsync(fd) != 0) { perror("fsync"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    if (rename(tmpl, final_path) != 0) { perror("rename"); return 1; }
    return 0;
}

/* dprintf writes from inside libc, to a descriptor the caller opened. */
static int append_via_dprintf(int value) {
    char path[1024];
    join_path(path, sizeof(path), "log.txt");
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) { perror("open log"); return 1; }
    if (dprintf(fd, "rotated to %d\n", value) < 0) { perror("dprintf"); return 1; }
    if (close(fd) != 0) { perror("close log"); return 1; }
    return 0;
}

/* tmpfile creates and unlinks inside libc; nothing should survive in-root,
 * but the calls are worth seeing (it honours TMPDIR). */
static int scratch_via_tmpfile(void) {
    FILE *f = tmpfile();
    if (!f) { perror("tmpfile"); return 1; }
    fputs("scratch\n", f);
    fclose(f);
    return 0;
}

static int cmd_init(void) {
    char path[1024];
    if (mkdir(state_dir(), 0755) != 0 && access(state_dir(), F_OK) != 0) {
        perror("mkdir state");
        return 1;
    }
    join_path(path, sizeof(path), "key.json");
    FILE *f = fopen(path, "w");
    if (!f) { perror("fopen init"); return 1; }
    fputs("key=1\n", f);
    fclose(f);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s init|rotate\n", argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) {
        if (rotate_via_mkstemp(2) != 0) return 1;
        if (append_via_dprintf(2) != 0) return 1;
        if (scratch_via_tmpfile() != 0) return 1;
        return 0;
    }
    fprintf(stderr, "unknown command\n");
    return 2;
}
