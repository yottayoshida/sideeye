/*
 * The temp-name creators' *contract*, printed one line per case (#39).
 *
 * This toy is not run under sideeye. It exists to be run twice — once plain and once
 * with the shim loaded — so the two outputs can be diffed. The shim reimplements these
 * five functions rather than forwarding to them, and a reimplementation that gets the
 * contract wrong does not add an observation, it changes what the target does. That is
 * the same objection that keeps `dprintf` out of the shim, applied to the members that
 * are in it.
 *
 * The contract is NOT the same on the two platforms, which is why this exists at all
 * (measured 2026-08-31, both directions, in spike/libc-internal/RESULTS.md):
 *
 *   flags     glibc clears the access mode out of the caller's flags; Apple's libc
 *             rejects anything outside {O_APPEND, O_CLOEXEC, O_SHLOCK, O_EXLOCK} with
 *             EINVAL, O_RDWR included.
 *   template  glibc requires the last six characters before the suffix to be X and
 *             replaces exactly those; Apple replaces the whole trailing run however
 *             long, and no trailing X is legal there and means "use this name".
 *
 * Names are randomised, so the lines report the *shape* of the answer — the error
 * number, or which characters changed — never the name itself. Comparing names would
 * make every run differ from every other and the diff would say nothing.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *root;

/* How many times each template case is run before its shape is reported.
 *
 * One run is not enough, and finding that out is why this constant exists: the shape
 * marks a position as replaced when the character changed, and a replacement draws
 * from 62 letters — so a position filled with a literal 'X' looks untouched. On
 * `c.XXXXXXXX` under glibc that turned a correct run into a reported difference. A
 * position is marked replaced if it differed in ANY of the runs, which needs every
 * one of them to draw 'X' to stay wrong: 62^-REPEATS. */
#define REPEATS 8

/* Merge one observation into the shape: the original character where it has never
 * changed, '*' where it has. */
static void merge_shape(const char *before, const char *after, char *out, size_t n) {
    size_t i = 0;
    for (; before[i] && after[i] && i + 1 < n; i++)
        if (out[i] != '*') out[i] = (before[i] == after[i]) ? before[i] : '*';
    out[i] = '\0';
}

static void join(char *out, size_t n, const char *name) {
    snprintf(out, n, "%s/%s", root, name);
}

/* The flag cases report accept-or-refuse, and the refusal's number. The name's shape
 * is not the question here — it is the same template every time. */
static void t_flags(const char *label, int flags) {
    char t[512];
    join(t, sizeof(t), "f.XXXXXX");
    errno = 0;
    int fd = mkostemp(t, flags);
    if (fd < 0) {
        printf("  mkostemp %-12s -> errno %d\n", label, errno);
    } else {
        printf("  mkostemp %-12s -> ok\n", label);
        close(fd);
        unlink(t);
    }
}

static void t_stemps(const char *tmpl, int suffixlen) {
    char before[512], s[512];
    join(before, sizeof(before), tmpl);
    s[0] = '\0';
    const char *name = suffixlen < 0 ? "mkstemp" : "mkstemps";
    for (int r = 0; r < REPEATS; r++) {
        char t[512];
        snprintf(t, sizeof(t), "%s", before);
        errno = 0;
        int fd = (suffixlen < 0) ? mkstemp(t) : mkstemps(t, suffixlen);
        if (fd < 0) {
            printf("  %-9s %-14s s=%2d -> errno %d\n", name, tmpl, suffixlen, errno);
            return;
        }
        if (r == 0) snprintf(s, sizeof(s), "%s", before);
        merge_shape(before, t, s, sizeof(s));
        close(fd);
        unlink(t);
    }
    printf("  %-9s %-14s s=%2d -> ok %s\n", name, tmpl, suffixlen, s + strlen(root) + 1);
}

static void t_dtemp(const char *tmpl) {
    char before[512], s[512];
    join(before, sizeof(before), tmpl);
    s[0] = '\0';
    for (int r = 0; r < REPEATS; r++) {
        char t[512];
        snprintf(t, sizeof(t), "%s", before);
        errno = 0;
        if (mkdtemp(t) == NULL) {
            printf("  mkdtemp   %-14s      -> errno %d\n", tmpl, errno);
            return;
        }
        if (r == 0) snprintf(s, sizeof(s), "%s", before);
        merge_shape(before, t, s, sizeof(s));
        rmdir(t);
    }
    printf("  mkdtemp   %-14s      -> ok %s\n", tmpl, s + strlen(root) + 1);
}

/* The positive control, and it goes to STDERR on purpose.
 *
 * The diff compares stdout, and a comparison of two runs cannot tell whether the shim
 * was loaded at all: delete every temp entry from the interpose table and both runs
 * reach the real libc, agree, and the check goes green having measured nothing. So the
 * run reports which image `mkstemp` resolves into — the caller asserts that the plain
 * run names libc and the shimmed run names the shim — and that assertion is on a
 * channel the diff does not read, because the two runs are SUPPOSED to differ here. */
static void report_image(void) {
    Dl_info info;
    if (dladdr((void *)(uintptr_t)mkstemp, &info) && info.dli_fname) {
        const char *slash = strrchr(info.dli_fname, '/');
        fprintf(stderr, "resolved mkstemp in %s\n", slash ? slash + 1 : info.dli_fname);
    } else {
        fprintf(stderr, "resolved mkstemp in (dladdr failed)\n");
    }
}

/* A failure that is NOT EEXIST: the loop must return it rather than retry. A directory
 * with no write bit gives EACCES on both platforms. Exercised here because the ADR
 * claims this branch is covered by the differential, and until this case existed it
 * was covered by reading the code. The EEXIST retry itself is still not exercised —
 * forcing a collision needs the candidate space filled, which is 62^6 for a normal
 * template — and the ADR says so rather than implying otherwise. */
static void t_denied(void) {
    char dir[512], t[600];
    snprintf(dir, sizeof(dir), "%s/denied", root);
    if (mkdir(dir, 0500) != 0) { printf("  denied dir     -> setup failed\n"); return; }
    snprintf(t, sizeof(t), "%s/x.XXXXXX", dir);
    errno = 0;
    int fd = mkstemp(t);
    if (fd < 0) printf("  mkstemp   in a read-only dir -> errno %d\n", errno);
    else { printf("  mkstemp   in a read-only dir -> ok (unexpected)\n"); close(fd); unlink(t); }
    rmdir(dir);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <writable directory>\n", argv[0]);
        return 2;
    }
    root = argv[1];
    report_image();

    printf("flags:\n");
    t_flags("none", 0);
    t_flags("O_APPEND", O_APPEND);
    t_flags("O_CLOEXEC", O_CLOEXEC);
#ifdef O_SHLOCK
    t_flags("O_SHLOCK", O_SHLOCK);
    t_flags("O_EXLOCK", O_EXLOCK);
#endif
    t_flags("O_WRONLY", O_WRONLY);
    t_flags("O_RDWR", O_RDWR);
    t_flags("O_TRUNC", O_TRUNC);
    t_flags("O_NONBLOCK", O_NONBLOCK);

    printf("templates:\n");
    t_stemps("a.XXXXXX", -1);
    t_stemps("b.XXXXX", -1);
    t_stemps("c.XXXXXXXX", -1);
    t_stemps("d.XXXXXXn", -1);
    t_stemps("e.noX", -1);
    t_stemps("f.XXXXXX.sfx", 4);
    t_stemps("g.XXX.sfx", 4);
    t_stemps("h.XXXXXXXX.sfx", 4);
    t_stemps("i.plain.sfx", 4);
    t_stemps("j.XXXXXX", 99);
    t_stemps("k.XXXXXX", 0); /* suffixlen 0: the mkstemps spelling of mkstemp */
    t_dtemp("l.XXXXXX");
    t_dtemp("m.XXXXX");
    t_dtemp("n.XXXXXXXX");
    t_dtemp("o.noX");
    t_denied();
    return 0;
}
