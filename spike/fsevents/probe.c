/* A mode-driven ground truth for the FSEvents survey (#286).
 *
 * The #181 toy is not reused here. It performs open, write, rename, open,
 * write, unlink, mkdir, open, write — nine operations over five classes, all
 * of them succeeding. The comparison in src/oracle.zig carries ten classes
 * and, per shim/src/ops.zig, records every attempt *before* it runs, so a
 * failed call counts on both sides. A ground truth without fsync, truncate,
 * rmdir, link, symlink or a single failing call cannot say whether FSEvents
 * can reconstruct that sequence. This one covers them, one operation per run.
 *
 * Two subcommands, because the preparation for an operation is not part of
 * the measurement:
 *
 *   probe --setup DIR MODE   whatever must exist first; runs before the
 *                            watcher starts, and is deliberately silent
 *   probe --run   DIR MODE   the operation under test, and only that
 *
 * --run writes JSON Lines to stdout, one object per syscall attempted, with
 * the monotonic clock read either side of the call so an event can be placed
 * against it. rc and errno are recorded for every attempt including the
 * failures, since a failure that leaves no trace on disk is the cheapest
 * counterexample to the hypothesis that FSEvents can stand in for the oracle.
 *
 * --gap-ms inserts a pause between the syscalls of a multi-step mode. It is a
 * measurement parameter, not a workaround: coalescing is a function of how
 * close in time two operations are, so the gap is one of the axes being
 * varied. Zero is the default and the honest case.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
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

/* errno by name, because a transcript that says 2 makes the reader look it
 * up and a transcript that says ENOENT does not. Only the values these modes
 * can produce are listed; anything else is reported numerically. */
static const char *errno_name(int e) {
    switch (e) {
    case 0:       return "";
    case ENOENT:  return "ENOENT";
    case EEXIST:  return "EEXIST";
    case EACCES:  return "EACCES";
    case ENOTDIR: return "ENOTDIR";
    case EISDIR:  return "EISDIR";
    case ENOTEMPTY: return "ENOTEMPTY";
    case EPERM:   return "EPERM";
    default:      return "?";
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

/* One line per attempt. `class` is the OpClass name src/contract.zig would
 * give this call, so the judge can line the two accounts up without knowing
 * anything about syscall spelling. */
static void say(const char *syscall, const char *class, const char *path,
                const char *path2, int rc, int err, uint64_t t0, uint64_t t1) {
    printf("{\"type\":\"op\",\"seq\":%u,\"syscall\":\"%s\",\"class\":\"%s\",\"path\":",
           seq++, syscall, class);
    json_str(path);
    if (path2) { printf(",\"path2\":"); json_str(path2); }
    printf(",\"rc\":%d,\"errno\":%d,\"errno_name\":\"%s\","
           "\"start_ns\":%llu,\"end_ns\":%llu}\n",
           rc, err, errno_name(err),
           (unsigned long long)t0, (unsigned long long)t1);
    fflush(stdout);
}

#define TIMED(call_expr, syscall_name, class_name, p1, p2)      \
    do {                                                        \
        uint64_t _t0 = mono_ns();                               \
        errno = 0;                                              \
        int _rc = (call_expr);                                  \
        int _e = (_rc < 0) ? errno : 0;                         \
        uint64_t _t1 = mono_ns();                               \
        last_rc = _rc;                                          \
        say(syscall_name, class_name, p1, p2, _rc, _e, _t0, _t1); \
    } while (0)

static char P_TARGET[1024], P_TARGET2[1024], P_SUBDIR[1024], P_MISSING[1024],
           P_MISSING_DIR[1024], P_SENTINEL[1024];

/* A truncated path would silently measure a different file. */
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
    build_path(P_SENTINEL,    sizeof P_SENTINEL,    dir, "sentinel");
}

/* The liveness control, inside the run it certifies.
 *
 * A mode whose operation produces no event yields a capture that is empty of
 * that operation. So does a run where delivery simply did not work: this
 * survey has already produced one of those (latency 1.0 against a settle
 * shorter than the latency, five times out of five, reported as zero events
 * until the settle was raised). L0 cannot rule it out for a later run,
 * because L0 is a different stream at a different time.
 *
 * So every --run ends by creating one file whose event MUST arrive. If it
 * does not, the capture proves nothing and the judge reports BROKEN rather
 * than reading the silence as a finding. */
static void sentinel(void) {
    uint64_t t0 = mono_ns();
    errno = 0;
    int fd = open(P_SENTINEL, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int e = (fd < 0) ? errno : 0;
    if (fd >= 0) close(fd);
    printf("{\"type\":\"sentinel\",\"path\":");
    json_str(P_SENTINEL);
    printf(",\"rc\":%d,\"errno\":%d,\"start_ns\":%llu,\"end_ns\":%llu}\n",
           fd < 0 ? -1 : 0, e, (unsigned long long)t0,
           (unsigned long long)mono_ns());
    fflush(stdout);
}

/* Create `path` holding `n` bytes. Used by --setup only, so it is silent. */
static int make_file(const char *path, size_t n) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return -1;
    static const char filler[] = "0123456789abcdef";
    while (n > 0) {
        size_t chunk = n > sizeof filler - 1 ? sizeof filler - 1 : n;
        ssize_t w = write(fd, filler, chunk);
        if (w <= 0) { close(fd); return -1; }   /* short write counts what it wrote */
        n -= (size_t)w;
    }
    return close(fd);
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
    if (!strcmp(mode, "fail-open"))       return 0;
    if (!strcmp(mode, "fail-unlink"))     return 0;
    if (!strcmp(mode, "fail-rename"))     return 0;
    if (!strcmp(mode, "fail-mkdir"))      return mkdir(P_SUBDIR, 0755);
    if (!strcmp(mode, "fail-link"))       return 0;
    if (!strcmp(mode, "fail-truncate"))   return 0;
    if (!strcmp(mode, "fail-rmdir"))      return 0;
    fprintf(stderr, "probe: unknown mode for --setup: %s\n", mode);
    return -1;
}

/* Whether the operation under test did what the mode says it should. The exit
 * status carries it, so a mode that silently starts behaving differently (a
 * fail-* mode that begins to succeed, say) stops the run instead of quietly
 * measuring another experiment. */
static int expected_ok(const char *mode, int rc) {
    int wants_failure = (strncmp(mode, "fail-", 5) == 0);
    int failed = (rc < 0);
    return wants_failure == failed;
}

static int last_rc = 0;

static int do_run(const char *mode) {
    int fd;

    if (!strcmp(mode, "create")) {
        uint64_t t0 = mono_ns();
        errno = 0;
        fd = open(P_TARGET, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int e = (fd < 0) ? errno : 0;
        last_rc = (fd < 0) ? -1 : 0;
        say("open", "open", P_TARGET, NULL, fd < 0 ? -1 : 0, e, t0, mono_ns());
        if (fd >= 0) close(fd);
        return 0;
    }
    if (!strcmp(mode, "write") || !strcmp(mode, "fsync")) {
        uint64_t t0 = mono_ns();
        errno = 0;
        fd = open(P_TARGET, O_WRONLY, 0644);
        int e = (fd < 0) ? errno : 0;
        last_rc = (fd < 0) ? -1 : 0;
        say("open", "open", P_TARGET, NULL, fd < 0 ? -1 : 0, e, t0, mono_ns());
        if (fd < 0) return -1;
        gap();
        t0 = mono_ns();
        errno = 0;
        ssize_t w = write(fd, "payload", 7);
        e = (w < 0) ? errno : 0;
        last_rc = (w < 0) ? -1 : 0;
        say("write", "write", P_TARGET, NULL, (int)w, e, t0, mono_ns());
        if (!strcmp(mode, "fsync")) {
            gap();
            TIMED(fsync(fd), "fsync", "fsync", P_TARGET, NULL);
        }
        close(fd);
        return 0;
    }
    /* Same size: the bytes on disk do not change, so any event at all is a
     * report of an operation rather than of a difference. */
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

    /* The failures. Each one is recorded by the shim as an attempt of its
     * class, so the oracle must produce a matching entry or the two accounts
     * desync (shim/src/ops.zig). None of them changes the filesystem. */
    if (!strcmp(mode, "fail-open")) {
        uint64_t t0 = mono_ns();
        errno = 0;
        fd = open(P_MISSING_DIR, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int e = (fd < 0) ? errno : 0;
        last_rc = (fd < 0) ? -1 : 0;
        say("open", "open", P_MISSING_DIR, NULL, fd < 0 ? -1 : 0, e, t0, mono_ns());
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
    const char *what = NULL, *dir = NULL, *mode = NULL;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--gap-ms") && i + 1 < argc) gap_ms = atol(argv[++i]);
        else if (!strcmp(argv[i], "--setup") || !strcmp(argv[i], "--run")) what = argv[i] + 2;
        else if (!dir) dir = argv[i];
        else if (!mode) mode = argv[i];
        else { fprintf(stderr, "probe: unexpected argument %s\n", argv[i]); return 2; }
    }
    if (!what || !dir || !mode) {
        fprintf(stderr,
            "usage: probe --setup|--run DIR MODE [--gap-ms N]\n"
            "modes: create write fsync truncate-same truncate-shrink rename unlink\n"
            "       mkdir rmdir link symlink\n"
            "       fail-open fail-unlink fail-rename fail-mkdir fail-rmdir\n"
            "       fail-link fail-truncate\n");
        return 2;
    }
    build_paths(dir);
    if (!strcmp(what, "setup")) return do_setup(mode) == 0 ? 0 : 3;
    if (do_run(mode) != 0) return 3;
    sentinel();
    if (!expected_ok(mode, last_rc)) {
        fprintf(stderr, "probe: mode %s did not behave as its name says "
                        "(rc=%d)\n", mode, last_rc);
        return 5;
    }
    return 0;
}
