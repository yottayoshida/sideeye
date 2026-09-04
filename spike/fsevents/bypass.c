/* The planted mutation for the veto's sensitivity leg (#293, #344).
 *
 * H2 asks whether FSEvents can veto a mutation the shim never reported. Testing
 * that needs a mutation the shim provably does not report, and "provably" is the
 * whole difficulty: if the planted operation turns out to be visible after all,
 * a silent capture cannot be told from a capture of something the shim already
 * saw, and the leg proves nothing in either direction.
 *
 * It used to be clonefile(2), chosen because the shim did not interpose it. Trace
 * contract v12 (#333) added the clone family, so that probe's mutation became
 * visible and survey.sh's L7a refused the leg by design. The recorded 15/15
 * sensitivity result (RESULTS.md) was measured under v11 and stands as taken, on
 * its date. The same supersession happened to cohort 4's no-accel-copy.so one
 * contract version earlier — an apparatus built on a wall outliving the wall.
 *
 * The mutation now is an mmap store flushed with msync (#344). The shim does not
 * interpose msync and could not usefully: the store is a memory write with no
 * syscall behind it, and `spike/check-macos-coverage.py` records that as the
 * reason rather than an oversight.
 *
 * WHAT CHANGED IN WHAT L7a CAN CLAIM. A file must be opened before it can be
 * mapped, and the shim records that open. So the leg can no longer ask whether
 * the planted path appears in the trace — it does. It asks instead what the
 * trace says ABOUT the path: an `open`, and no operation that would account for
 * the bytes the file now holds. Reading that needs the ops, not the strings,
 * which is why survey.sh goes through `trace-ops` (built from contract.zig's own
 * decoder) rather than through `strings`.
 *
 * The mapped file is created and sized BY THE CALLER, before this program starts.
 * ftruncate is interposed, so sizing it here would put a `.truncate` for this path
 * in the trace and the predicate above could never hold. Measured: with the file
 * pre-sized, the trace carries exactly `open` and `close` for it; adding an
 * ordinary pwrite to this program puts `write` there too.
 *
 * Three files land in the state directory:
 *
 *   seen-by-shim.txt   open+write+close. The control: the shim must record it,
 *                      which is what makes "the shim ran at all" observable.
 *   store-src.txt      open+write+close. A second recorded file, so the trace
 *                      names more than one thing the shim does see.
 *   store-dst.txt      pre-created by the caller; mutated here through a mapping.
 *                      The planted mutation.
 *
 * Emitted as JSON Lines on stdout in the same shape probe.c uses, so judge.py
 * reads both without a second loader. The sentinel is a separate mutation whose
 * event proves delivery worked in this capture; without it an empty capture and
 * a broken watcher look identical, which this survey has already produced once.
 */
#include <sys/mman.h>
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

/* One page: the caller creates the file at exactly this size. */
#define MAP_LEN 4096

int main(int argc, char **argv) {
    /* `--map-only` maps the target read-only and stores nothing. It exists because the
     * event this probe's mutation produces turns out NOT to be produced by the mutation
     * (#344): measured on macOS 15.3.1, a run that maps and stores, a run that maps and
     * does not store, and a run that maps PROT_READ so a store is impossible all yield
     * an event naming the target in 3 of 3; a run that opens and closes without mapping
     * yields none in 3 of 3. The event attributes to the mapping.
     *
     * survey.sh drives this mode as L7d, so the fact is measured on every run of the
     * survey rather than recorded once in prose and left to rot. */
    int map_only = 0;
    if (argc == 4 && strcmp(argv[3], "--map-only") == 0) map_only = 1;
    if ((argc != 3 && !map_only) || strcmp(argv[1], "--run") != 0) {
        fprintf(stderr, "usage: bypass --run <state-dir> [--map-only]\n");
        return 2;
    }
    const char *state = argv[2];
    char seen[PATH_MAX], src[PATH_MAX], dst[PATH_MAX], sentinel[PATH_MAX];
    snprintf(seen,     sizeof seen,     "%s/seen-by-shim.txt", state);
    snprintf(src,      sizeof src,      "%s/store-src.txt",    state);
    snprintf(dst,      sizeof dst,      "%s/store-dst.txt",    state);
    snprintf(sentinel, sizeof sentinel, "%s/sentinel.txt",     state);

    if (write_file(seen, "control\n") != 0) {
        fprintf(stderr, "bypass: could not write the control file: %s\n", strerror(errno));
        return 1;
    }
    emit_op("open", seen, 0);

    if (write_file(src, "source\n") != 0) {
        fprintf(stderr, "bypass: could not write the store source: %s\n", strerror(errno));
        return 1;
    }
    emit_op("open", src, 0);

    /* The planted mutation. Deliberately NOT emitted as an op: judge.py takes
     * the op list as the set of paths the shim's account covers, and the point
     * of this file is that this path is outside it. It is announced under its
     * own record type so the judge can name it without inferring.
     *
     * No ftruncate: the caller sized the file. See the header — sizing it here
     * would record a `.truncate` for this path and L7a's predicate could not hold. */
    {
        int fd = open(dst, O_RDWR);
        if (fd < 0) {
            fprintf(stderr, "bypass: could not open the pre-created mapping target %s: %s\n",
                    dst, strerror(errno));
            return 1;
        }
        void *p = mmap(NULL, MAP_LEN, map_only ? PROT_READ : (PROT_READ | PROT_WRITE),
                       MAP_SHARED, fd, 0);
        if (p == MAP_FAILED) {
            fprintf(stderr, "bypass: mmap failed: %s\n", strerror(errno));
            close(fd);
            return 1;
        }
        if (!map_only) {
            memcpy(p, "mmap-store-mutation\n", 20);
            if (msync(p, MAP_LEN, MS_SYNC) != 0) {
                fprintf(stderr, "bypass: msync failed: %s\n", strerror(errno));
                munmap(p, MAP_LEN);
                close(fd);
                return 1;
            }
        }
        munmap(p, MAP_LEN);
        close(fd);
    }
    if (map_only)
        printf("{\"type\":\"mapped-not-stored\",\"path\":\"%s\",\"rc\":0}\n", dst);
    else
        printf("{\"type\":\"planted\",\"syscall\":\"mmap+msync\",\"path\":\"%s\",\"rc\":0}\n", dst);

    if (write_file(sentinel, "sentinel\n") != 0) {
        fprintf(stderr, "bypass: could not write the sentinel: %s\n", strerror(errno));
        return 1;
    }
    printf("{\"type\":\"sentinel\",\"path\":\"%s\",\"rc\":0}\n", sentinel);
    fflush(stdout);
    return 0;
}
