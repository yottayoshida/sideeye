/* toy_evidence.c — the shapes the evidence bundle's impact columns have to tell apart (#607).
 *
 * One image, five modes, because the point of the fixture set is that the columns DISAGREE
 * across it: a renderer that hard-codes any one answer has to fail at least two of these.
 * Five separate toys would have made that property invisible.
 *
 * Every mode writes into $SIDEEYE_STATE_DIR. The window in the first three is the ordinary
 * one — the file is opened for truncation and the write is a separate operation — which is
 * the shape seven of the 2026-09-16 targets had.
 *
 *   truncate   README.md exists and holds bytes; truncate, then write.
 *              -> pre_existing yes, old bytes elsewhere NO
 *   backup     the same, after copying README.md to README.bak first.
 *              -> pre_existing yes, old bytes elsewhere YES (at README.bak)
 *   empty      README.md exists and is EMPTY, DATA.txt exists and is not; both are
 *              truncated and rewritten, README.md first. The built-in invariant cannot go
 *              red on README.md — its crashed content equals its pre content — so the
 *              earliest failing world is DATA.txt's, and README.md rides along in the
 *              consequence table as the row whose survival question has no answer.
 *              -> README.md: pre_existing yes, old bytes elsewhere UNKNOWN (empty bytes
 *                 match every empty file, so `yes` would mean nothing)
 *   scratch    the same window, on cache/data, which the define declares scratch.
 *              -> declared_scratch YES on that row
 *   twofile    a.txt and b.txt each written atomically (temp + rename), in that order.
 *              -> the built-in invariant holds in every world (each file is pre or post),
 *                 so a FAIL here is the checker's alone: checker_failed YES with no path
 *                 named by the built-in layer.
 *
 *   evilname   the same window, on a file whose NAME holds newlines and an ESC. A Unix file
 *              name may contain both, and the bundle is a document with headings: without
 *              the text-side defang a name forges sections in it. Measured 2026-09-17 —
 *              before the fix a crafted name rendered its own `## Severity` heading.
 *
 * A sixth shape needs no mode of its own: `truncate` with a checker that reads MARKER.txt
 * instead of README.md is L0-red and checker-green, which is the row that must not imply
 * application-level loss.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void path_of(char *out, size_t n, const char *root, const char *rel) {
    snprintf(out, n, "%s/%s", root, rel);
}

/* Truncate then write, as two operations with a crash point between them. */
static int truncate_then_write(const char *p, const char *text) {
    FILE *f = fopen(p, "wb"); /* truncates */
    if (!f) return 1;
    fputs(text, f);
    return fclose(f) == 0 ? 0 : 1;
}

static int copy_file(const char *from, const char *to) {
    FILE *s = fopen(from, "rb");
    if (!s) return 1;
    FILE *d = fopen(to, "wb");
    if (!d) { fclose(s); return 1; }
    int c, rc = 0;
    while ((c = fgetc(s)) != EOF)
        if (fputc(c, d) == EOF) { rc = 1; break; }
    if (fclose(d) != 0) rc = 1;
    fclose(s);
    return rc;
}

/* temp + rename: the shape the built-in invariant accepts in every world. */
static int atomic_write(const char *root, const char *rel, const char *text) {
    char tmp[4096], dst[4096];
    snprintf(tmp, sizeof tmp, "%s/%s.tmp", root, rel);
    path_of(dst, sizeof dst, root, rel);
    FILE *f = fopen(tmp, "wb");
    if (!f) return 1;
    fputs(text, f);
    if (fclose(f) != 0) return 1;
    return rename(tmp, dst) == 0 ? 0 : 1;
}

int main(void) {
    const char *root = getenv("SIDEEYE_STATE_DIR");
    const char *mode = getenv("EV_MODE");
    if (!root || !mode) {
        fprintf(stderr, "toy_evidence: SIDEEYE_STATE_DIR and EV_MODE are required\n");
        return 2;
    }
    char p[4096], q[4096];

    if (strcmp(mode, "truncate") == 0) {
        path_of(p, sizeof p, root, "README.md");
        return truncate_then_write(p, "Rewritten\n");
    }
    if (strcmp(mode, "empty") == 0) {
        path_of(p, sizeof p, root, "README.md");
        if (truncate_then_write(p, "Rewritten\n") != 0) return 1;
        path_of(q, sizeof q, root, "DATA.txt");
        return truncate_then_write(q, "Rewritten\n");
    }
    if (strcmp(mode, "backup") == 0) {
        path_of(p, sizeof p, root, "README.md");
        path_of(q, sizeof q, root, "README.bak");
        if (copy_file(p, q) != 0) return 1;
        return truncate_then_write(p, "Rewritten\n");
    }
    if (strcmp(mode, "evilname") == 0) {
        /* The newline is followed by "## " so the name forges a SECTION, not just a line
           break: the check downstream compares the rendered document's heading set, and a
           name whose newlines land mid-sentence leaves that set alone. Measured — the first
           version of this fixture was "ev\nil\033[31m.md", and removing the text-side
           defang left the check green. No severity word here on purpose: a target's own
           bytes containing one is not Sideeye ranking anything, and the check must not
           confuse the two. */
        path_of(p, sizeof p, root, "ev\n## Forged\n\033[31m.md");
        return truncate_then_write(p, "Rewritten\n");
    }
    if (strcmp(mode, "scratch") == 0) {
        path_of(p, sizeof p, root, "cache/data");
        return truncate_then_write(p, "Rewritten\n");
    }
    if (strcmp(mode, "twofile") == 0) {
        /* Both atomic, so no single file is ever torn; what a crash between them breaks is
           the relation the checker declares, which is the only layer that can see it. */
        if (atomic_write(root, "a.txt", "gen2\n") != 0) return 1;
        return atomic_write(root, "b.txt", "gen2\n");
    }
    fprintf(stderr, "toy_evidence: unknown EV_MODE %s\n", mode);
    return 2;
}
