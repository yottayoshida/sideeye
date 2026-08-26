/* The planted mutation for the veto's sensitivity leg (#293).
 *
 * H2 asks whether FSEvents can veto a mutation the shim never reported. Testing
 * that needs a mutation the shim provably does not report, and "provably" is the
 * whole difficulty: if the planted operation turns out to be visible after all,
 * a silent capture cannot be told from a capture of something the shim already
 * saw, and the leg proves nothing in either direction.
 *
 * clonefile(2) is the one used here. At the time of the survey it was a libc
 * entry point that creates a file and was not in the shim's interpose table
 * (then 40 symbols; copyfile, clonefile, renamex_np and removefile were not
 * among them). That table is read rather than trusted: survey.sh runs this
 * probe under the shim first and refuses the leg if the cloned path appears in
 * the trace.
 *
 * SUPERSEDED as a live probe by trace contract v12 (#333): the shim now
 * interposes clonefile, clonefileat and fclonefileat, so this probe's planted
 * mutation IS recorded and survey.sh's L7a precondition refuses — by design,
 * with its own "pick another mutation" message. The recorded 15/15 sensitivity
 * result (RESULTS.md) was measured under v11 and stands as taken, on its date;
 * re-running the leg needs a mutation the v12 shim still cannot see (the
 * mmap/msync class), which is filed with #293 rather than rebuilt here. The
 * same supersession happened to cohort 4's no-accel-copy.so one contract
 * version earlier — an apparatus built on a wall outliving the wall.
 *
 * Three files land in the state directory:
 *
 *   seen-by-shim.txt   open+write+close. The control: the shim must record it,
 *                      which is what makes "the shim ran at all" observable.
 *   clone-src.txt      open+write+close, then the source of the clone.
 *   clone-dst.txt      created by clonefile alone. The planted mutation.
 *
 * Emitted as JSON Lines on stdout in the same shape probe.c uses, so judge.py
 * reads both without a second loader. The sentinel is a separate mutation whose
 * event proves delivery worked in this capture; without it an empty capture and
 * a broken watcher look identical, which this survey has already produced once.
 */
#include <sys/clonefile.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void emit_op(const char *syscall_name, const char *path, int rc) {
    printf("{\"type\":\"op\",\"syscall\":\"%s\",\"path\":\"%s\",\"rc\":%d}\n",
           syscall_name, path, rc);
}

static int write_file(const char *path, const char *bytes) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    size_t n = strlen(bytes);
    if (write(fd, bytes, n) != (ssize_t)n) { close(fd); return -1; }
    return close(fd);
}

int main(int argc, char **argv) {
    if (argc != 3 || strcmp(argv[1], "--run") != 0) {
        fprintf(stderr, "usage: bypass --run <state-dir>\n");
        return 2;
    }
    const char *state = argv[2];
    char seen[PATH_MAX], src[PATH_MAX], dst[PATH_MAX], sentinel[PATH_MAX];
    snprintf(seen,     sizeof seen,     "%s/seen-by-shim.txt", state);
    snprintf(src,      sizeof src,      "%s/clone-src.txt",    state);
    snprintf(dst,      sizeof dst,      "%s/clone-dst.txt",    state);
    snprintf(sentinel, sizeof sentinel, "%s/sentinel.txt",     state);

    if (write_file(seen, "control\n") != 0) {
        fprintf(stderr, "bypass: could not write the control file: %s\n", strerror(errno));
        return 1;
    }
    emit_op("open", seen, 0);

    if (write_file(src, "source\n") != 0) {
        fprintf(stderr, "bypass: could not write the clone source: %s\n", strerror(errno));
        return 1;
    }
    emit_op("open", src, 0);

    /* The planted mutation. Deliberately NOT emitted as an op: judge.py takes
     * the op list as the set of paths the shim's account covers, and the point
     * of this file is that this path is outside it. It is announced under its
     * own record type so the judge can name it without inferring. */
    if (clonefile(src, dst, 0) != 0) {
        fprintf(stderr, "bypass: clonefile failed: %s\n", strerror(errno));
        return 1;
    }
    printf("{\"type\":\"planted\",\"syscall\":\"clonefile\",\"path\":\"%s\",\"rc\":0}\n", dst);

    if (write_file(sentinel, "sentinel\n") != 0) {
        fprintf(stderr, "bypass: could not write the sentinel: %s\n", strerror(errno));
        return 1;
    }
    printf("{\"type\":\"sentinel\",\"path\":\"%s\",\"rc\":0}\n", sentinel);
    fflush(stdout);
    return 0;
}
