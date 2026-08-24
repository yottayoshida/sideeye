/* The mode-driven ground truth for the fs_usage survey (#286, route F1).
 *
 * Based on spike/fsevents/probe.c, which this survey's plan reuses, with the
 * additions that survey needs:
 *
 *   - P2's counterexample matrix: consecutive small writes, two fds
 *     interleaved, one large write, a zero-byte write, pwrite, writev, stdio,
 *     and the two ordering probes (write-then-rename, write-then-unlink).
 *   - P1's child probe: fork, the child writes, the parent waits.
 *   - TWO sentinels, start and end, both inside the state directory. One
 *     sentinel proves the observer was alive at one instant; only the pair
 *     brackets the window the operations ran in. A capture missing either is
 *     BROKEN, never a finding.
 *   - --pause-file PATH: block before the first operation until PATH exists,
 *     so an orchestrator can read this process's pid and aim an observer at
 *     it before anything happens.
 *
 * Subcommands, as before: --setup runs silently before any observer starts;
 * --run performs the operations under test and self-accounts as JSON Lines.
 * rc and errno are recorded for every attempt including failures; the exit
 * status says whether the mode behaved as its name promises (a fail-* mode
 * that succeeds is rc 5, not a measurement).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>

static long gap_ms = 0;
static unsigned seq = 0;

static uint64_t mono_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static void gap(void) {
    if (gap_ms <= 0) return;
    struct timespec ts = { gap_ms / 1000, (gap_ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static const char *errno_name(int e) {
    switch (e) {
    case 0:        return "";
    case ENOENT:   return "ENOENT";
    case EEXIST:   return "EEXIST";
    case EACCES:   return "EACCES";
    case ENOTDIR:  return "ENOTDIR";
    case EISDIR:   return "EISDIR";
    case ENOTEMPTY: return "ENOTEMPTY";
    case EPERM:    return "EPERM";
    default:       return "?";
    }
}

static void json_str(const char *s) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':  fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 0x20) printf("\\u%04x", *p);
            else putchar((char)*p);
        }
    }
    putchar('"');
}

static void say(const char *syscall, const char *class, const char *path,
                const char *path2, long rc, int err, uint64_t t0, uint64_t t1) {
    printf("{\"type\":\"op\",\"seq\":%u,\"pid\":%ld,\"syscall\":\"%s\","
           "\"class\":\"%s\",\"path\":",
           seq++, (long)getpid(), syscall, class);
    json_str(path);
    if (path2) { printf(",\"path2\":"); json_str(path2); }
    printf(",\"rc\":%ld,\"errno\":%d,\"errno_name\":\"%s\","
           "\"start_ns\":%llu,\"end_ns\":%llu}\n",
           rc, err, errno_name(err),
           (unsigned long long)t0, (unsigned long long)t1);
    fflush(stdout);
}

#define TIMED(call_expr, syscall_name, class_name, p1, p2)        \
    do {                                                          \
        uint64_t _t0 = mono_ns();                                 \
        errno = 0;                                                \
        long _rc = (long)(call_expr);                             \
        int _e = (_rc < 0) ? errno : 0;                           \
        uint64_t _t1 = mono_ns();                                 \
        last_rc = _rc;                                            \
        say(syscall_name, class_name, p1, p2, _rc, _e, _t0, _t1); \
    } while (0)

static long last_rc = 0;

static char P_TARGET[2048], P_TARGET2[2048], P_SUBDIR[2048], P_MISSING[2048],
           P_MISSING_DIR[2048], P_SENT_START[2048], P_SENT_END[2048],
           P_CHILD[2048];

static void build_path(char *out, size_t cap, const char *dir, const char *leaf) {
    int n = snprintf(out, cap, "%s/%s", dir, leaf);
    if (n < 0 || (size_t)n >= cap) {
        fprintf(stderr, "probe: path too long for %s/%s\n", dir, leaf);
        exit(4);
    }
}

static void build_paths(const char *dir) {
    build_path(P_TARGET,      sizeof P_TARGET,      dir, "target");
    build_path(P_TARGET2,     sizeof P_TARGET2,     dir, "target2");
    build_path(P_SUBDIR,      sizeof P_SUBDIR,      dir, "subdir");
    build_path(P_MISSING,     sizeof P_MISSING,     dir, "missing");
    build_path(P_MISSING_DIR, sizeof P_MISSING_DIR, dir, "missing-dir/leaf");
    build_path(P_SENT_START,  sizeof P_SENT_START,  dir, "sentinel-start");
    build_path(P_SENT_END,    sizeof P_SENT_END,    dir, "sentinel-end");
    build_path(P_CHILD,       sizeof P_CHILD,       dir, "child-file");
}

static int make_file(const char *path, size_t n) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    static const char filler[] = "0123456789abcdef";
    while (n > 0) {
        size_t chunk = n > sizeof filler - 1 ? sizeof filler - 1 : n;
        ssize_t w = write(fd, filler, chunk);
        if (w <= 0) { close(fd); return -1; }
        n -= (size_t)w;
    }
    return close(fd);
}

/* The liveness controls, both recorded as ordinary ops so they appear in the
 * shim's trace and in the observer's capture alike. */
static void sentinel(const char *path, const char *label) {
    uint64_t t0 = mono_ns();
    errno = 0;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int e = (fd < 0) ? errno : 0;
    if (fd >= 0) { (void)!write(fd, label, strlen(label)); close(fd); }
    printf("{\"type\":\"sentinel\",\"which\":\"%s\",\"pid\":%ld,\"path\":",
           label, (long)getpid());
    json_str(path);
    printf(",\"rc\":%d,\"errno\":%d,\"start_ns\":%llu,\"end_ns\":%llu}\n",
           fd < 0 ? -1 : 0, e, (unsigned long long)t0,
           (unsigned long long)mono_ns());
    fflush(stdout);
}

static int do_setup(const char *mode) {
    if (!strcmp(mode, "create"))          return 0;
    if (!strcmp(mode, "write"))           return make_file(P_TARGET, 16);
    if (!strcmp(mode, "fsync"))           return make_file(P_TARGET, 16);
    if (!strcmp(mode, "truncate-same"))   return make_file(P_TARGET, 16);
    if (!strcmp(mode, "truncate-shrink")) return make_file(P_TARGET, 16);
    if (!strcmp(mode, "rename"))          return make_file(P_TARGET, 16);
    if (!strcmp(mode, "unlink"))          return make_file(P_TARGET, 16);
    if (!strcmp(mode, "mkdir"))           return 0;
    if (!strcmp(mode, "rmdir"))           return mkdir(P_SUBDIR, 0755);
    if (!strcmp(mode, "link"))            return make_file(P_TARGET, 16);
    if (!strcmp(mode, "symlink"))         return 0;
    if (!strcmp(mode, "writes-small"))    return make_file(P_TARGET, 0);
    if (!strcmp(mode, "writes-two-fd")) {
        if (make_file(P_TARGET, 0) != 0) return -1;
        return make_file(P_TARGET2, 0);
    }
    if (!strcmp(mode, "write-large"))     return make_file(P_TARGET, 0);
    if (!strcmp(mode, "write-zero"))      return make_file(P_TARGET, 16);
    if (!strcmp(mode, "pwrite"))          return make_file(P_TARGET, 16);
    if (!strcmp(mode, "writev"))          return make_file(P_TARGET, 0);
    if (!strcmp(mode, "stdio"))           return 0;
    if (!strcmp(mode, "write-rename"))    return 0;
    if (!strcmp(mode, "write-unlink"))    return 0;
    if (!strcmp(mode, "child-write"))     return 0;
    if (!strncmp(mode, "fail-", 5)) {
        if (!strcmp(mode, "fail-mkdir")) return mkdir(P_SUBDIR, 0755);
        return 0;
    }
    fprintf(stderr, "probe: unknown mode for --setup: %s\n", mode);
    return -1;
}

static int expected_ok(const char *mode, long rc) {
    int wants_failure = (strncmp(mode, "fail-", 5) == 0);
    return wants_failure == (rc < 0);
}

static int open_timed(const char *path, int flags, const char *label) {
    uint64_t t0 = mono_ns();
    errno = 0;
    int fd = open(path, flags, 0644);
    int e = (fd < 0) ? errno : 0;
    last_rc = (fd < 0) ? -1 : 0;
    say(label, "open", path, NULL, fd < 0 ? -1 : 0, e, t0, mono_ns());
    return fd;
}

static int do_run(const char *mode) {
    int fd, fd2;

    if (!strcmp(mode, "create")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_CREAT | O_TRUNC, "open");
        if (fd >= 0) close(fd);
        return 0;
    }
    if (!strcmp(mode, "write") || !strcmp(mode, "fsync")) {
        fd = open_timed(P_TARGET, O_WRONLY, "open");
        if (fd < 0) return -1;
        gap();
        TIMED(write(fd, "payload", 7), "write", "write", P_TARGET, NULL);
        if (!strcmp(mode, "fsync")) {
            gap();
            TIMED(fsync(fd), "fsync", "fsync", P_TARGET, NULL);
        }
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "truncate-same")) {
        TIMED(truncate(P_TARGET, 16), "truncate", "truncate", P_TARGET, NULL);
        return 0;
    }
    if (!strcmp(mode, "truncate-shrink")) {
        TIMED(truncate(P_TARGET, 4), "truncate", "truncate", P_TARGET, NULL);
        return 0;
    }
    if (!strcmp(mode, "rename")) {
        TIMED(rename(P_TARGET, P_TARGET2), "rename", "rename", P_TARGET, P_TARGET2);
        return 0;
    }
    if (!strcmp(mode, "unlink")) {
        TIMED(unlink(P_TARGET), "unlink", "unlink", P_TARGET, NULL);
        return 0;
    }
    if (!strcmp(mode, "mkdir")) {
        TIMED(mkdir(P_SUBDIR, 0755), "mkdir", "mkdir", P_SUBDIR, NULL);
        return 0;
    }
    if (!strcmp(mode, "rmdir")) {
        TIMED(rmdir(P_SUBDIR), "rmdir", "rmdir", P_SUBDIR, NULL);
        return 0;
    }
    if (!strcmp(mode, "link")) {
        TIMED(link(P_TARGET, P_TARGET2), "link", "link", P_TARGET, P_TARGET2);
        return 0;
    }
    if (!strcmp(mode, "symlink")) {
        TIMED(symlink("target", P_TARGET2), "symlink", "symlink", P_TARGET2, NULL);
        return 0;
    }

    /* --- P2: the write-granularity counterexample matrix --- */
    if (!strcmp(mode, "writes-small")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_APPEND, "open");
        if (fd < 0) return -1;
        for (int i = 0; i < 3; i++) {
            gap();
            TIMED(write(fd, "chunk-x", 7), "write", "write", P_TARGET, NULL);
        }
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "writes-two-fd")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_APPEND, "open");
        fd2 = open_timed(P_TARGET2, O_WRONLY | O_APPEND, "open");
        if (fd < 0 || fd2 < 0) return -1;
        for (int i = 0; i < 2; i++) {
            gap();
            TIMED(write(fd, "AAAAAAA", 7), "write", "write", P_TARGET, NULL);
            gap();
            TIMED(write(fd2, "BBBBBBB", 7), "write", "write", P_TARGET2, NULL);
        }
        close(fd); close(fd2);
        return 0;
    }
    if (!strcmp(mode, "write-large")) {
        fd = open_timed(P_TARGET, O_WRONLY, "open");
        if (fd < 0) return -1;
        static char big[4 * 1024 * 1024];
        memset(big, 'L', sizeof big);
        gap();
        TIMED(write(fd, big, sizeof big), "write", "write", P_TARGET, NULL);
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "write-zero")) {
        fd = open_timed(P_TARGET, O_WRONLY, "open");
        if (fd < 0) return -1;
        gap();
        TIMED(write(fd, "", 0), "write", "write", P_TARGET, NULL);
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "pwrite")) {
        fd = open_timed(P_TARGET, O_WRONLY, "open");
        if (fd < 0) return -1;
        gap();
        TIMED(pwrite(fd, "PWRITTEN", 8, 0), "pwrite", "write", P_TARGET, NULL);
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "writev")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_APPEND, "open");
        if (fd < 0) return -1;
        struct iovec iov[2] = {
            { .iov_base = (void *)"vec-one", .iov_len = 7 },
            { .iov_base = (void *)"vec-two", .iov_len = 7 },
        };
        gap();
        TIMED(writev(fd, iov, 2), "writev", "write", P_TARGET, NULL);
        close(fd);
        return 0;
    }
    if (!strcmp(mode, "stdio")) {
        /* Through the FILE* layer: the shim interposes it, and whether the
         * observer sees one write or several is exactly the question. */
        uint64_t t0 = mono_ns();
        errno = 0;
        FILE *f = fopen(P_TARGET, "w");
        int e = f ? 0 : errno;
        last_rc = f ? 0 : -1;
        say("fopen", "open", P_TARGET, NULL, f ? 0 : -1, e, t0, mono_ns());
        if (!f) return -1;
        gap();
        TIMED(fprintf(f, "stdio-payload"), "fprintf", "write", P_TARGET, NULL);
        gap();
        TIMED(fflush(f), "fflush", "write", P_TARGET, NULL);
        fclose(f);
        return 0;
    }
    if (!strcmp(mode, "write-rename")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_CREAT | O_TRUNC, "open");
        if (fd < 0) return -1;
        gap();
        TIMED(write(fd, "ordered", 7), "write", "write", P_TARGET, NULL);
        close(fd);
        gap();
        TIMED(rename(P_TARGET, P_TARGET2), "rename", "rename", P_TARGET, P_TARGET2);
        return 0;
    }
    if (!strcmp(mode, "write-unlink")) {
        fd = open_timed(P_TARGET, O_WRONLY | O_CREAT | O_TRUNC, "open");
        if (fd < 0) return -1;
        gap();
        TIMED(write(fd, "doomed!", 7), "write", "write", P_TARGET, NULL);
        close(fd);
        gap();
        TIMED(unlink(P_TARGET), "unlink", "unlink", P_TARGET, NULL);
        return 0;
    }

    /* --- P1: does an observer aimed at the parent see the child? --- */
    if (!strcmp(mode, "child-write")) {
        uint64_t t0 = mono_ns();
        pid_t child = fork();
        if (child == 0) {
            int cfd = open(P_CHILD, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (cfd >= 0) { (void)!write(cfd, "from-child", 10); close(cfd); }
            _exit(cfd >= 0 ? 0 : 1);
        }
        int status = -1;
        waitpid(child, &status, 0);
        last_rc = (child > 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : -1;
        say("fork+child-write", "child", P_CHILD, NULL, last_rc, 0, t0, mono_ns());
        return 0;
    }

    /* --- P4: the failures --- */
    if (!strcmp(mode, "fail-open")) {
        fd = open_timed(P_MISSING_DIR, O_WRONLY | O_CREAT | O_TRUNC, "open");
        if (fd >= 0) close(fd);
        return 0;
    }
    if (!strcmp(mode, "fail-unlink")) {
        TIMED(unlink(P_MISSING), "unlink", "unlink", P_MISSING, NULL);
        return 0;
    }
    if (!strcmp(mode, "fail-rename")) {
        TIMED(rename(P_MISSING, P_TARGET2), "rename", "rename", P_MISSING, P_TARGET2);
        return 0;
    }
    if (!strcmp(mode, "fail-mkdir")) {
        TIMED(mkdir(P_SUBDIR, 0755), "mkdir", "mkdir", P_SUBDIR, NULL);
        return 0;
    }
    if (!strcmp(mode, "fail-rmdir")) {
        TIMED(rmdir(P_MISSING), "rmdir", "rmdir", P_MISSING, NULL);
        return 0;
    }
    if (!strcmp(mode, "fail-link")) {
        TIMED(link(P_MISSING, P_TARGET2), "link", "link", P_MISSING, P_TARGET2);
        return 0;
    }
    if (!strcmp(mode, "fail-truncate")) {
        TIMED(truncate(P_MISSING, 4), "truncate", "truncate", P_MISSING, NULL);
        return 0;
    }

    fprintf(stderr, "probe: unknown mode for --run: %s\n", mode);
    return -1;
}

int main(int argc, char **argv) {
    const char *what = NULL, *dir = NULL, *mode = NULL, *pause_file = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--gap-ms") && i + 1 < argc) gap_ms = atol(argv[++i]);
        else if (!strcmp(argv[i], "--pause-file") && i + 1 < argc) pause_file = argv[++i];
        else if (!strcmp(argv[i], "--setup") || !strcmp(argv[i], "--run")) what = argv[i] + 2;
        else if (!dir) dir = argv[i];
        else if (!mode) mode = argv[i];
        else { fprintf(stderr, "probe: unexpected argument %s\n", argv[i]); return 2; }
    }
    if (!what || !dir || !mode) {
        fprintf(stderr,
            "usage: probe --setup|--run DIR MODE [--gap-ms N] [--pause-file P]\n"
            "modes: create write fsync truncate-same truncate-shrink rename unlink\n"
            "       mkdir rmdir link symlink\n"
            "       writes-small writes-two-fd write-large write-zero pwrite writev\n"
            "       stdio write-rename write-unlink child-write\n"
            "       fail-open fail-unlink fail-rename fail-mkdir fail-rmdir\n"
            "       fail-link fail-truncate\n");
        return 2;
    }
    build_paths(dir);
    if (!strcmp(what, "setup")) return do_setup(mode) == 0 ? 0 : 3;

    /* Announce pid AND main-thread id first. fs_usage's trailing number is a
     * thread id, not a pid (fs_usage(1), PROCESS NAME); whether that id equals
     * what pthread_threadid_np reports is exactly the attribution question, so
     * the probe states its own so the judge can try the mapping. */
    uint64_t tid = 0;
#ifdef __APPLE__
    pthread_threadid_np(NULL, &tid);
#endif
    printf("{\"type\":\"hello\",\"pid\":%ld,\"tid\":%llu,\"mode\":\"%s\"}\n",
           (long)getpid(), (unsigned long long)tid, mode);
    fflush(stdout);
    if (pause_file) {
        for (int i = 0; i < 600; i++) {           /* 60s bound, no busy spin */
            struct stat st;
            if (stat(pause_file, &st) == 0) break;
            struct timespec ts = { 0, 100000000L };
            nanosleep(&ts, NULL);
        }
    }
    sentinel(P_SENT_START, "start");
    if (do_run(mode) != 0) return 3;
    long op_rc = last_rc;
    sentinel(P_SENT_END, "end");
    if (!expected_ok(mode, op_rc)) {
        fprintf(stderr, "probe: mode %s did not behave as its name says (rc=%ld)\n",
                mode, op_rc);
        return 5;
    }
    return 0;
}
