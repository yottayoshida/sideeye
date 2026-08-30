/* toy-symlink — a target whose judged tree holds an interior symlink, and whose
 * operation goes through it.
 *
 * Exists for one regression. The per-path reconciliation (#405, ADR 0032) joins the
 * paths the shim recorded against the differences the snapshot found. The shim
 * normalises path arguments lexically, so an operation on `cur/f` under `cur -> v1` is
 * recorded as `cur/f`; the snapshot never follows a link and holds the difference at
 * `v1/f`. The first revision compared those two spellings directly and refused a run
 * nothing was wrong with — measured: PASS exit 0 on the shipped 1.0.0, UNKNOWN exit 2
 * with `state_changed_unaccounted` naming `v1/f` on the first build of the detector,
 * and a control on the same file spelled directly still passing.
 *
 * `current -> release-N` is a mainstream layout, and GNU Stow — on this project's own
 * list of targets — is a symlink farm. The shape is not exotic.
 *
 * Nothing here is a crash-consistency bug: this toy is expected to PASS, and its whole
 * job is to be a run the tool must not refuse.
 *
 * Subcommands: `init` builds the tree and the link; `rotate` unlinks through it.
 * Environment: TOY_STATE — the judged directory.
 */

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *state_dir(void) {
    const char *s = getenv("TOY_STATE");
    return s ? s : ".";
}

int main(int argc, char **argv) {
    char p[2048], t[2048];
    const char *d = state_dir();

    if (argc < 2) {
        fprintf(stderr, "usage: toy-symlink init|rotate\n");
        return 2;
    }

    if (strcmp(argv[1], "init") == 0) {
        snprintf(p, sizeof(p), "%s/v1", d);
        if (mkdir(p, 0755) != 0) { perror("mkdir"); return 1; }
        snprintf(p, sizeof(p), "%s/v1/f", d);
        int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (fd < 0) { perror("open"); return 1; }
        if (write(fd, "old", 3) != 3) { perror("write"); return 1; }
        close(fd);
        /* An absolute target, which is what a generation-swapping tool writes. The
         * relative spelling is covered by the engine's unit tests; both go through the
         * same substitution. */
        snprintf(t, sizeof(t), "%s/v1", d);
        snprintf(p, sizeof(p), "%s/cur", d);
        if (symlink(t, p) != 0) { perror("symlink"); return 1; }
        return 0;
    }

    if (strcmp(argv[1], "rotate") == 0) {
        snprintf(p, sizeof(p), "%s/cur/f", d);
        if (unlink(p) != 0) { perror("unlink"); return 1; }
        return 0;
    }

    /* The mirror shape, and the second regression the substitution caused. `rotate`
     * operates THROUGH the link and the difference lands at `v1/f`; `swap` operates on
     * the link ITSELF and the difference lands at `cur`. A join that substitutes and then
     * compares only the result rewrites this record's `cur` to `v1` and leaves the
     * difference named by nobody — measured, PASS to UNKNOWN, after the fix for `rotate`
     * went in. Building the new link beside the old one and renaming it over is how a
     * generation swap is done atomically. */
    if (strcmp(argv[1], "swap") == 0) {
        snprintf(t, sizeof(t), "%s/v2", d);
        if (mkdir(t, 0755) != 0) { perror("mkdir"); return 1; }
        snprintf(p, sizeof(p), "%s/cur.tmp", d);
        if (symlink(t, p) != 0) { perror("symlink"); return 1; }
        snprintf(t, sizeof(t), "%s/cur", d);
        if (rename(p, t) != 0) { perror("rename"); return 1; }
        return 0;
    }

    fprintf(stderr, "toy-symlink: unknown subcommand %s\n", argv[1]);
    return 2;
}
