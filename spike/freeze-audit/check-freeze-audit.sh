#!/bin/sh
# The freeze audit's completeness gate: the classification table on
# docs/freeze-audit.md must cover exactly the issue set in the committed
# snapshot — no recalled rows, no silently dropped ones. Check-12 shape:
# the gate proves it can go red on every run by judging a tampered copy of
# the page. The tampered copy is generated HERE, at run time, from the real
# page (its first classification row deleted) — a committed fixture would
# rot silently after a re-sweep, and an absent fixture must never read as
# a passed falsification (both were measured in review, R1 P1-1/P2-4).
#
#   sh spike/freeze-audit/check-freeze-audit.sh
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# The snapshot is this gate's trust root; a re-sweep replaces the file and
# this name together. Nothing machine-checks the snapshot itself — that is
# commit review's job, and the page says so.
SNAPSHOT="$ROOT/spike/freeze-audit/snapshot-2026-08-18.tsv"
PAGE="$ROOT/docs/freeze-audit.md"

[ -s "$SNAPSHOT" ] || { echo "FAIL: snapshot missing or empty: $SNAPSHOT"; exit 1; }
[ -s "$PAGE" ] || { echo "FAIL: page missing or empty: $PAGE"; exit 1; }

want=$(cut -f1 "$SNAPSHOT" | sort -u)
want_count=$(printf '%s\n' "$want" | grep -c .)
[ "$want_count" -gt 0 ] || { echo "FAIL: the snapshot yielded no issue numbers"; exit 1; }

table_numbers() {
    # Classification rows are the lines beginning `| #N`. Prose mentions of
    # #N never match this anchor (measured in review).
    grep -oE '^\| #[0-9]+' "$1" | grep -oE '#[0-9]+' | sort -u
}

got=$(table_numbers "$PAGE")
if [ "$want" != "$got" ]; then
    echo "FAIL: the classification table and the snapshot disagree (< snapshot, > table):"
    wf=$(mktemp) && gf=$(mktemp)
    printf '%s\n' "$want" > "$wf" && printf '%s\n' "$got" > "$gf"
    diff "$wf" "$gf" | sed 's/^/  /'
    rm -f "$wf" "$gf"
    exit 1
fi

# The self-falsification leg: delete the page's first classification row and
# require the same judgment to fail. The tampered copy must differ from the
# page by exactly that one row, or the falsification proves nothing.
first_row=$(grep -nE '^\| #[0-9]+' "$PAGE" | head -1 | cut -d: -f1)
[ -n "$first_row" ] || { echo "FAIL: no classification rows found on the page"; exit 1; }
tampered=$(mktemp)
sed "${first_row}d" "$PAGE" > "$tampered"
tampered_count=$(table_numbers "$tampered" | grep -c .)
if [ "$tampered_count" -ne $((want_count - 1)) ]; then
    echo "FAIL: the tampered copy did not lose exactly one row (has $tampered_count, wanted $((want_count - 1)))"
    rm -f "$tampered"
    exit 1
fi
if [ "$want" = "$(table_numbers "$tampered")" ]; then
    echo "FAIL: the tampered copy (one row deleted) was judged complete — the gate is blind"
    rm -f "$tampered"
    exit 1
fi
rm -f "$tampered"

echo "ok: the table covers all $want_count snapshot issues, and the gate goes red on a one-row-deleted copy"
