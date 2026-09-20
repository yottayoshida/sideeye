/* The scale benchmark's target (#621, ADR 0081): N crash points, constant judged state.
 *
 *   toy-scale init         build the pre-state: one file
 *   toy-scale rotate <N>   perform N create-write-unlink cycles on one temporary path
 *
 * **N is an argument, not an environment variable**, so the parameter is readable from the
 * command that ran the cell rather than from an ambient setting nothing records. (An earlier
 * version of this comment said it lands in the report's `operation` field. **The report has no
 * such field** — the guarantee that the benchmark records the engine's count and not the
 * request comes from the two separate columns in its row.)
 *
 * **Why temporaries.** The point of this toy is to move ONE axis. A target that writes N
 * files grows the judged state with N, and then a rising per-world cost cannot be told from a
 * rising state size — the conflation #621 names outright ("so `worlds` and `state bytes` are
 * not conflated"). Measured while designing this: the N-files shape cost about six times more
 * per world, all of it the tree. A path in neither snapshot is ignored by the built-in
 * invariants ("L0 accepts a leftover temporary file"), so the judged set stays at one file
 * however large N is, the run PASSes, and no case is saved to vary the cost.
 *
 * The state-size axis is supplied separately, by padding the operation never touches — the
 * shape `spike/explore-cost/measure.sh` already uses.
 *
 * **Deterministic**: no clock, no pid, no randomness, and the bytes written depend only on
 * the loop index. Two runs leave identical state, which is what `preflight --twice` asks of a
 * target and what a benchmark needs if repetitions are to be comparable.
 *
 * Measured on the drafting machine: crash points come out at exactly 3N (an open, a write and
 * an unlink per cycle) for N of 1, 2, 5, 10, 34, 100, 200 and 334. The harness records what
 * the engine reports; this comment is the expectation, not the source of the number.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

/* The same variable the other toys read, and the one sideeye exports to its children pointed
 * at the resolved [world] state. */
static const char *state_dir(void) {
    const char *s = getenv("TOY_STATE");
    return s ? s : "./state";
}

int main(int argc, char **argv) {
    char keep[4096], tmp[4096];
    if (argc < 2) {
        fprintf(stderr, "usage: %s init | %s rotate <cycles>\n", argv[0], argv[0]);
        return 2;
    }
    if (snprintf(keep, sizeof keep, "%s/keep.json", state_dir()) >= (int) sizeof keep) return 2;
    if (snprintf(tmp, sizeof tmp, "%s/scratch.tmp", state_dir()) >= (int) sizeof tmp) return 2;

    if (strcmp(argv[1], "init") == 0) {
        if (mkdir(state_dir(), 0755) != 0 && access(state_dir(), F_OK) != 0) return 1;
        FILE *f = fopen(keep, "w");
        if (!f) return 1;
        /* The one judged file. Its content never changes, so every world's comparison is the
         * same work: the benchmark measures the engine's orchestration, not a growing diff. */
        if (fprintf(f, "kept\n") < 0) { fclose(f); return 1; }
        return fclose(f) == 0 ? 0 : 1;
    }

    if (strcmp(argv[1], "rotate") != 0) {
        fprintf(stderr, "%s: unknown command %s\n", argv[0], argv[1]);
        return 2;
    }
    /* Refused rather than defaulted: a benchmark cell that forgot to say how many cycles it
     * wanted would otherwise record a row for a run nobody asked for. */
    if (argc < 3) {
        fprintf(stderr, "%s rotate: give the number of cycles\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    long cycles = strtol(argv[2], &end, 10);
    if (end == argv[2] || *end != '\0' || cycles < 0) {
        fprintf(stderr, "%s rotate: not a count: %s\n", argv[0], argv[2]);
        return 2;
    }

    for (long i = 0; i < cycles; i++) {
        FILE *f = fopen(tmp, "w");
        if (!f) return 1;
        if (fprintf(f, "cycle=%ld\n", i) < 0) { fclose(f); return 1; }
        if (fclose(f) != 0) return 1;
        if (unlink(tmp) != 0) return 1;
    }
    return 0;
}
