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
 *
 * 2026-08-31: `rotate` is unchanged — it is what the 2026-08-22 transcript records —
 * and one subcommand per class member was added beside it, each writing through its
 * own final path so a divergence names the member that caused it. The shim now
 * reimplements the five creators (contract v13), so those five reach a verdict here;
 * `dprintf` and `tmpfile` are the deliberate non-members and stay measurable.
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

/* tmpfile creates and unlinks inside libc; nothing should survive in-root.
 *
 * The parenthesis here used to read "it honours TMPDIR". That was never measured and
 * it is false on glibc 2.36/aarch64: tmpfile reaches
 * `openat(AT_FDCWD, "/tmp", O_RDWR|O_EXCL|O_TMPFILE, 0600)`, which ignores TMPDIR and
 * creates no directory entry at all — so it cannot mutate a state root, and there is
 * no unlink either. Corrected 2026-08-31 with the run in spike/libc-internal/. */
static int scratch_via_tmpfile(void) {
    FILE *f = tmpfile();
    if (!f) { perror("tmpfile"); return 1; }
    fputs("scratch\n", f);
    fclose(f);
    return 0;
}

/* One subcommand per class member (#39, 2026-08-31), each writing through its OWN
 * final path. A single command exercising all of them cannot say which member a
 * divergence belongs to; separate runs can, and the run is what the record shows.
 *
 * Each of the four file creators performs the same atomic replace `rotate` does, so
 * the shape under measurement is the one a real C program writes. `mkdtemp` has no
 * atomic-replace form: it creates the directory and leaves it, which is what a
 * program using it does.
 */
static int replace_with(int fd, char *tmpl, const char *final_name) {
    char final_path[1024];
    if (fd < 0) { perror("create"); return 1; }
    if (write(fd, "key=2\n", 6) != 6) { perror("write"); return 1; }
    if (fsync(fd) != 0) { perror("fsync"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }
    join_path(final_path, sizeof(final_path), final_name);
    if (rename(tmpl, final_path) != 0) { perror("rename"); return 1; }
    return 0;
}

static int cmd_mkstemp(void) {
    char t[1024];
    join_path(t, sizeof(t), "m-mkstemp.XXXXXX");
    return replace_with(mkstemp(t), t, "m-mkstemp.json");
}

/* O_WRONLY is passed on purpose, and it is not decoration: the real mkostemp clears
 * the caller's access-mode bits (measured), so a replacement that ORs them in raw
 * builds access mode 3 and the create fails where libc's succeeds. Without this flag
 * the measurement leg would pass either way. */
static int cmd_mkostemp(void) {
    char t[1024];
    join_path(t, sizeof(t), "m-mkostemp.XXXXXX");
    return replace_with(mkostemp(t, O_WRONLY | O_CLOEXEC), t, "m-mkostemp.json");
}

static int cmd_mkstemps(void) {
    char t[1024];
    join_path(t, sizeof(t), "m-mkstemps.XXXXXX.tmp");
    return replace_with(mkstemps(t, 4), t, "m-mkstemps.json");
}

static int cmd_mkostemps(void) {
    char t[1024];
    join_path(t, sizeof(t), "m-mkostemps.XXXXXX.tmp");
    return replace_with(mkostemps(t, 4, O_WRONLY | O_CLOEXEC), t, "m-mkostemps.json");
}

static int cmd_mkdtemp(void) {
    char t[1024];
    join_path(t, sizeof(t), "m-mkdtemp.XXXXXX");
    if (mkdtemp(t) == NULL) { perror("mkdtemp"); return 1; }
    return 0;
}

/* The two members this change deliberately leaves as walls, kept runnable so the
 * record can show them still diverging in the same sitting as the five that no
 * longer do. Without them the check would have no negative control it did not
 * invent. */
static int cmd_dprintf(void) { return append_via_dprintf(2); }

static int cmd_tmpfile(void) { return scratch_via_tmpfile(); }

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
        fprintf(stderr,
                "usage: %s init|rotate"
                "|mkstemp|mkostemp|mkstemps|mkostemps|mkdtemp|dprintf|tmpfile\n",
                argv[0]);
        return 2;
    }
    if (strcmp(argv[1], "init") == 0) return cmd_init();
    if (strcmp(argv[1], "rotate") == 0) {
        if (rotate_via_mkstemp(2) != 0) return 1;
        if (append_via_dprintf(2) != 0) return 1;
        if (scratch_via_tmpfile() != 0) return 1;
        return 0;
    }
    if (strcmp(argv[1], "mkstemp") == 0) return cmd_mkstemp();
    if (strcmp(argv[1], "mkostemp") == 0) return cmd_mkostemp();
    if (strcmp(argv[1], "mkstemps") == 0) return cmd_mkstemps();
    if (strcmp(argv[1], "mkostemps") == 0) return cmd_mkostemps();
    if (strcmp(argv[1], "mkdtemp") == 0) return cmd_mkdtemp();
    if (strcmp(argv[1], "dprintf") == 0) return cmd_dprintf();
    if (strcmp(argv[1], "tmpfile") == 0) return cmd_tmpfile();
    fprintf(stderr, "unknown command\n");
    return 2;
}
