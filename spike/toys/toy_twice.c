/* Succeeds on its first run and fails on every one after it.
 *
 * Exists for one acceptance leg: `preflight --twice` has to apply to its SECOND
 * observation the same gates the first passed, and the only way to see that from
 * outside is a target whose second run ends abnormally while the first did not. An
 * implementation that spawned run B, snapshotted, and diffed — without checking how
 * run B ended — would compare the wreckage of a failure against a successful run and
 * report it as a repeatability split, or as agreement. Neither is honest.
 *
 * Two things about the shape, both learned by getting them wrong first:
 *
 *   - The counter lives OUTSIDE the state root, named by TOY_TWICE_COUNTER. Anything
 *     inside would be rebuilt by `engine.restore` between the two observations, and
 *     both runs would take the same branch.
 *   - The writes happen in this process through stdio. A shell script that spawned a
 *     real target as a child refused as `child_touched_state_dir` (correctly: a child
 *     writing the state has no unique crash address), and one that used its own
 *     redirections refused as `state_changed_without_ops`. Neither reached run B,
 *     which is the thing under test.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* open/write/fsync/close, the way toy.c writes — not stdio.
 *
 * The first version used fopen/fprintf and the recording run refused with
 * state_changed_without_ops: the tree moved while nothing was counted. Whatever the
 * cause, the fix is not to widen the shim for a test fixture — it is for the fixture
 * to write the way the toys the suite already trusts do. */
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

int main(int argc, char **argv) {
    /* TOY_STATE, the spelling toy.c uses — not SIDEEYE_STATE_DIR. The engine exports
     * both to the operation, but --setup runs with a narrower set and the first
     * version of this toy died there with "SIDEEYE_STATE_DIR is required". */
    const char *state = getenv("TOY_STATE");
    if (!state) {
        fprintf(stderr, "toy-twice: TOY_STATE is required\n");
        return 2;
    }
    char path[4096];
    if (snprintf(path, sizeof path, "%s/f.txt", state) >= (int)sizeof path) return 2;

    /* `init` is the --setup half: the file has to exist in the PRE snapshot, or the
     * operation only ever creates it and there is nothing for L0 to judge — which is
     * how the first version of this toy ended up refused as state_changed_without_ops
     * before the second run was ever reached. */
    /* A file name holding a newline. Under TOY_TWICE_HOSTILE_NAME the operation
     * rewrites it with different bytes every run, so it lands in the split report —
     * where those bytes must be defanged rather than allowed to forge a line. */
    char hostile[4096];
    if (snprintf(hostile, sizeof hostile, "%s/a\nb", state) >= (int)sizeof hostile) return 2;
    const int hostile_mode = getenv("TOY_TWICE_HOSTILE_NAME") != NULL;

    if (argc > 1 && strcmp(argv[1], "init") == 0) {
        if (mkdir(state, 0755) != 0 && errno != EEXIST) return 2;
        if (write_file(path, "initial\n") != 0) return 2;
        if (hostile_mode && write_file(hostile, "initial\n") != 0) return 2;
        return 0;
    }

    const char *counter = getenv("TOY_TWICE_COUNTER");
    if (!counter) {
        fprintf(stderr, "toy-twice: TOY_TWICE_COUNTER is required\n");
        return 2;
    }

    long n = 0;
    FILE *c = fopen(counter, "r");
    if (c) {
        if (fscanf(c, "%ld", &n) != 1) n = 0;
        fclose(c);
    }
    n++;
    char nbuf[32];
    snprintf(nbuf, sizeof nbuf, "%ld\n", n);
    /* The counter is outside the state root, so how it is written does not matter to
     * the recording — but it is written the same way for one less difference. */
    if (write_file(counter, nbuf) != 0) return 2;

    /* The state write is unconditional and identical every run: if this toy ever
     * reaches a comparison, the two post-states agree. What differs is the exit
     * status, so a leg that reports a "split" here is naming the wrong thing. */
    if (write_file(path, "written\n") != 0) return 2;

    /* Under TOY_TWICE_EXTRA_ON_SECOND only the second run creates this file.
     *
     * That is the one direction `classify` structurally cannot report and the reason
     * `diffSnapshots` exists — and it is the only kind whose path is borrowed from the
     * SECOND snapshot rather than the first. A review found the engine returning those
     * borrowed paths after freeing the snapshot that owned them (segfault, reproduced);
     * every leg written before that review went through `content_differs`, which
     * borrows from the first snapshot and survives. This mode is the leg that would
     * have caught it. */
    if (getenv("TOY_TWICE_EXTRA_ON_SECOND") && n >= 2) {
        char extra[4096];
        if (snprintf(extra, sizeof extra, "%s/only-in-second.txt", state) >= (int)sizeof extra) return 2;
        if (write_file(extra, "second\n") != 0) return 2;
        return 0;
    }

    if (hostile_mode) {
        /* Different bytes every run, so this path is what the comparison reports. The
         * exit status stays 0 here: this mode is about the report's rendering, not
         * about the run-B gate the counter drives. */
        char buf[32];
        snprintf(buf, sizeof buf, "run %ld\n", n);
        if (write_file(hostile, buf) != 0) return 2;
        return 0;
    }

    return n >= 2 ? 7 : 0;
}
