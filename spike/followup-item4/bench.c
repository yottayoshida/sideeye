/* What one interposed call costs under the v16 shim against the v15 shim: open+close on
 * a path outside the state directory, N times, under LD_PRELOAD with the shim active. The
 * v16 shim adds a gettid() and a scan of up to 64 slots to every interposed call; the v15
 * shim reads one global. Nothing here is in scope, so the trace is not written to — the
 * measurement is the guard's cost, not the record's. */
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    long n = argc > 1 ? atol(argv[1]) : 100000;
    for (long i = 0; i < n; i++) {
        int fd = open("/dev/null", O_RDONLY);
        if (fd >= 0) close(fd);
    }
    return 0;
}
