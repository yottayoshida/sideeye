/*
 * A target with exactly ONE kill point inside the state root: the papis shape.
 *
 * Why this file exists rather than `spike/toys/toy.c`. The interior gate is red when the
 * operation has fewer than two in-root kill points (selection rule 15: "a single atomic
 * mutation is a contrast measurement, not a criterion-1 slot"). `toy.c` cannot show that
 * red — `spike/cohort4/preflight-selftest.txt` measures it at
 * `INTERIOR kill points inside the state root: 4 (fsync=1, open=1, rename=1, write=1)`,
 * which is green. A gate whose red has never been seen says nothing about what it passed,
 * so the red leg needs a target that is genuinely one operation.
 *
 * `rotate` builds the new file OUTSIDE the root and moves it in with one `rename`. That
 * is the whole mutation: there is no world between "old key intact" and "new key in
 * place", which is exactly what makes it a contrast case rather than a candidate.
 *
 * Everything is routed through libc on purpose — this toy must be VISIBLE (the
 * visibility gate green) while being interior-red, so that a red from the gate set can
 * be attributed to one gate rather than to the target being opaque in general.
 *
 * Environment:
 *   TOY_STATE   the state directory (default ./state)
 *
 * Usage: toy_single_op init | rotate
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *s = getenv("TOY_STATE");
    return (s && *s) ? s : "./state";
}

/* The staging path is a SIBLING of the root, never inside it: a temporary file written
 * inside the root would itself be in-root operations and the count would stop being 1. */
static void staging_path(char *buf, size_t n, const char *root) {
    snprintf(buf, n, "%s.staging", root);
}

static int write_file(const char *path, const char *text) {
    FILE *f = fopen(path, "w");
    if (!f) return -1;
    if (fputs(text, f) == EOF) { fclose(f); return -1; }
    return fclose(f) == 0 ? 0 : -1;
}

int main(int argc, char **argv) {
    const char *root = state_dir();
    char key[4096], staging[4096];

    if (argc < 2) { fprintf(stderr, "usage: %s init|rotate\n", argv[0]); return 2; }
    snprintf(key, sizeof key, "%s/key", root);
    staging_path(staging, sizeof staging, root);

    if (strcmp(argv[1], "init") == 0) {
        if (mkdir(root, 0755) != 0 && access(root, F_OK) != 0) {
            perror("mkdir"); return 1;
        }
        if (write_file(key, "key-0\n") != 0) { perror("write key"); return 1; }
        return 0;
    }

    if (strcmp(argv[1], "rotate") == 0) {
        /* Outside the root: not a kill point the gate counts. */
        if (write_file(staging, "key-1\n") != 0) { perror("write staging"); return 1; }
        /* The one and only in-root operation. */
        if (rename(staging, key) != 0) { perror("rename"); return 1; }
        return 0;
    }

    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return 2;
}
