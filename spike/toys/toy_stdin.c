/* #263's fixture: every command the engine runs starts with its stdin at end-of-file.
 *
 * One binary, three roles (`setup`, `op`, `check`), so a single define drives every
 * spawn wrapper a define's commands reach — `runChild` (setup, checker),
 * `runChildCapture` (the recording run), `runChildCaptureWorld` (each explored world)
 * and `runChildCaptureAll` (the falsification probe). Each role FIRST drains fd 0 to
 * EOF and only then does its work: under an inherited terminal or an open pipe the
 * read blocks forever, so a wrapper that still inherits shows up as a hang, not as a
 * wrong answer. Single process, no fork (a shell one-liner would be a child the boundary
 * detectors would refuse), libc I/O only.
 *
 * The operation is write-tmp-then-rename, toy-fixed's own crash-consistent shape: the
 * scratch file is in neither snapshot and the rename is atomic, so every crash world
 * satisfies the built-in invariant and the leg can expect PASS. The checker accepts
 * either committed content and rejects anything else, so the falsification probe's
 * corrupted store turns it red. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void drain_stdin(void) {
    char buf[256];
    ssize_t n;
    while ((n = read(0, buf, sizeof buf)) > 0) {}
    if (n < 0) _exit(4); /* EBADF here is the CLOEXEC-on-fd-0 trap, not EOF */
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    const char *dir = getenv("TOY_STATE");
    if (!dir) return 3;
    drain_stdin();
    char fin[512], tmp[512];
    snprintf(fin, sizeof fin, "%s/f", dir);
    snprintf(tmp, sizeof tmp, "%s/f.tmp", dir);
    if (strcmp(argv[1], "setup") == 0) {
        FILE *f = fopen(fin, "w");
        if (!f) return 1;
        fputs("v1\n", f);
        fclose(f);
        return 0;
    }
    if (strcmp(argv[1], "op") == 0) {
        FILE *f = fopen(tmp, "w");
        if (!f) return 1;
        fputs("v2\n", f);
        fclose(f);
        if (rename(tmp, fin) != 0) return 1;
        return 0;
    }
    if (strcmp(argv[1], "check") == 0) {
        FILE *f = fopen(fin, "r");
        if (!f) return 1;
        char line[16] = {0};
        if (!fgets(line, sizeof line, f)) { fclose(f); return 1; }
        fclose(f);
        return (strcmp(line, "v1\n") == 0 || strcmp(line, "v2\n") == 0) ? 0 : 1;
    }
    return 2;
}
