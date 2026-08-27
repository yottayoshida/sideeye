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
# Since ADR 0027 the manifest (audit.tsv) is the trust root for ROW CONTENT
# while the snapshot below stays the trust root for the POPULATION, and the page's
# table is generated from it, so this gate also checks row shape, the surface
# and class enumerations, the class-dependent disposition rule, and that the
# page is a byte-identical render. Syntax alone passes a table where every row
# says "none", every class is C and every resolution is empty — measured in
# review — so each predicate has its own negative fixture in the mutation set.
#
#   sh spike/freeze-audit/check-freeze-audit.sh          # the gate
#   sh spike/freeze-audit/check-freeze-audit.sh --live   # drift against the tracker
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
# The snapshot is this gate's trust root for the population — which issues belong
# in the table, as against audit.tsv which owns what each row says. A re-sweep
# replaces the file and
# this name together. Nothing machine-checks the snapshot itself — that is
# commit review's job, and the page says so.
SNAPSHOT="$ROOT/spike/freeze-audit/snapshot-2026-08-18.tsv"
PAGE="$ROOT/docs/freeze-audit.md"

MANIFEST="$ROOT/spike/freeze-audit/audit.tsv"
# One temp directory with a trap rather than several mktemp calls: a second
# mktemp failing leaked the first, an unchecked mktemp let an unset variable
# reach a redirection, and a signal leaked everything (R1 P2-1, reproduced).
TMP=$(mktemp -d) || { echo "FAIL: cannot create a temp directory"; exit 1; }
# Cleanup is non-recursive on purpose: `rm -rf` on a directory is intercepted
# by this developer's own guard tooling, which left the temp directory behind
# AND printed into this script's output. Measured while fixing R1 P2-1 — the
# fix for one problem introduced another on the machine the script is meant to
# be run by hand on.
cleanup_TMP() { rm -f "$TMP"/* 2>/dev/null; rmdir "$TMP" 2>/dev/null; }
trap cleanup_TMP EXIT HUP INT TERM
[ -s "$SNAPSHOT" ] || { echo "FAIL: snapshot missing or empty: $SNAPSHOT"; exit 1; }
[ -s "$PAGE" ] || { echo "FAIL: page missing or empty: $PAGE"; exit 1; }
[ -s "$MANIFEST" ] || { echo "FAIL: manifest missing or empty: $MANIFEST"; exit 1; }

# --- --live: what the gate could never see by itself -------------------------
# The default gate compares the page against a committed snapshot, so it cannot
# notice that the snapshot itself has aged. This mode asks the tracker. It lives
# here rather than in CI for the same reason the gate does — it needs the
# network — which is precisely why it can reach the tracker at all.
#
# Every query carries --limit and asserts the count is strictly below it:
# `gh issue list` defaults to 30, exactly its page size, so a truncated result
# is indistinguishable from a complete one and a snapshot and a table derived
# from the same truncated query agree perfectly. Captured 2026-08-27 in
# capture-2026-08-27-limit-truncation.json: the unlimited form returned 30 and
# the limited form 55, at one instant. The unlimited number does not move with
# the tracker, which is what makes it unusable as a count.
if [ "${1-}" = "--live" ]; then
    command -v gh > /dev/null 2>&1 || { echo "FAIL: --live needs gh on PATH"; exit 1; }
    LIMIT=1000
    # Sorted lexically, not numerically: comm compares against LC_COLLATE order
    # and numerically-sorted input makes it report numbers as both added and
    # removed. Measured on the first run of this mode — five issues appeared in
    # both lists at once, which is how the mistake announced itself.
    # Two steps, not a pipeline: sh reports the status of a pipeline's LAST
    # command, so `| sort` hid a failing gh entirely and the script carried on
    # with an empty set — which would have reported every snapshot issue as
    # closed and exited 3 instead of 1 (R1 P1-1, reproduced against a broken
    # api.github.com).
    raw="$TMP/live.raw"
    gh issue list --state open --limit "$LIMIT" --json number --jq '.[].number' > "$raw" \
        || { echo "FAIL: the tracker query failed"; exit 1; }
    live=$(LC_ALL=C sort "$raw") || { echo "FAIL: sorting the tracker result failed"; exit 1; }
    live_count=$(printf '%s\n' "$live" | grep -c .)
    if [ "$live_count" -ge "$LIMIT" ]; then
        echo "FAIL: the tracker query returned $live_count at --limit $LIMIT — possibly truncated, raise the limit"
        exit 1
    fi
    snap=$(cut -f1 "$SNAPSHOT" | tr -d '#' | LC_ALL=C sort)
    snap_count=$(printf '%s\n' "$snap" | grep -c .)
    sf="$TMP/snap" && lf="$TMP/live"
    printf '%s\n' "$snap" > "$sf" || { echo "FAIL: cannot write $sf"; exit 1; }
    printf '%s\n' "$live" > "$lf" || { echo "FAIL: cannot write $lf"; exit 1; }
    # comm's own status is checked before its output is counted, for the same
    # reason the gh pipeline was split.
    comm -13 "$sf" "$lf" > "$TMP/added" || { echo "FAIL: comm failed"; exit 1; }
    comm -23 "$sf" "$lf" > "$TMP/gone" || { echo "FAIL: comm failed"; exit 1; }
    added=$(grep -c . "$TMP/added" || true)
    gone=$(grep -c . "$TMP/gone" || true)
    echo "snapshot: $snap_count issues ($(basename "$SNAPSHOT"))"
    echo "tracker:  $live_count open, queried at $(date -u +%Y-%m-%dT%H:%M:%SZ) with --limit $LIMIT"
    if [ "$added" = "0" ] && [ "$gone" = "0" ]; then
        echo "ok   no drift: the snapshot is the tracker's open set"
        exit 0
    fi
    echo "DRIFT: $added open issue(s) absent from the snapshot, $gone snapshot issue(s) no longer open"
    [ "$added" = "0" ] || { echo "  absent from the snapshot:"; sort -n "$TMP/added" | sed 's/^/#/' | tr '\n' ' '; echo; }
    [ "$gone" = "0" ] || { echo "  in the snapshot, not open:"; sort -n "$TMP/gone" | sed 's/^/#/' | tr '\n' ' '; echo; }
    echo "exit 3 — drift is not a gate failure (that is exit 1); it is the audit noticing its own age"
    exit 3
fi

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
    wf="$TMP/want.table" && gf="$TMP/got.table"
    printf '%s\n' "$want" > "$wf" && printf '%s\n' "$got" > "$gf"
    diff "$wf" "$gf" | sed 's/^/  /'
    exit 1
fi

# The self-falsification leg: delete the page's first classification row and
# require the same judgment to fail. The tampered copy must differ from the
# page by exactly that one row, or the falsification proves nothing.
first_row=$(grep -nE '^\| #[0-9]+' "$PAGE" | head -1 | cut -d: -f1)
[ -n "$first_row" ] || { echo "FAIL: no classification rows found on the page"; exit 1; }
tampered="$TMP/tampered"
sed "${first_row}d" "$PAGE" > "$tampered"
tampered_count=$(table_numbers "$tampered" | grep -c .)
if [ "$tampered_count" -ne $((want_count - 1)) ]; then
    echo "FAIL: the tampered copy did not lose exactly one row (has $tampered_count, wanted $((want_count - 1)))"
    exit 1
fi
if [ "$want" = "$(table_numbers "$tampered")" ]; then
    echo "FAIL: the tampered copy (one row deleted) was judged complete — the gate is blind"
    exit 1
fi

# --- the manifest owns row content, so it is checked directly ----------------
# Every non-comment, non-header line is a data line and must validate. The
# first version filtered to rows whose first field was numeric, which the
# renderer does not do — a row numbered "oops" was rendered as #oops and seen
# by nothing (R1 P1-4).
badnum=$(awk -F'\t' '!/^#/ && NF > 0 && $1 != "number" && $1 !~ /^[0-9]+$/ {print $1}' "$MANIFEST")
[ -z "$badnum" ] || { echo "FAIL: manifest rows with a non-numeric issue number: $badnum"; exit 1; }
mrows=$(awk -F'\t' '!/^#/ && NF > 0 && $1 != "number"' "$MANIFEST")
mcount=$(printf '%s\n' "$mrows" | grep -c .)
[ "$mcount" -gt 0 ] || { echo "FAIL: the manifest yielded no rows"; exit 1; }

manifest_numbers=$(printf '%s\n' "$mrows" | cut -f1 | sed 's/^/#/' | sort -u)
if [ "$want" != "$manifest_numbers" ]; then
    echo "FAIL: the manifest and the snapshot disagree (< snapshot, > manifest):"
    wf="$TMP/want.manifest" && mf="$TMP/got.manifest"
    printf '%s\n' "$want" > "$wf" && printf '%s\n' "$manifest_numbers" > "$mf"
    diff "$wf" "$mf" | sed 's/^/  /'
    exit 1
fi

dupes=$(printf '%s\n' "$mrows" | cut -f1 | sort | uniq -d | grep -c . || true)
[ "$dupes" = "0" ] || { echo "FAIL: the manifest repeats $dupes issue number(s)"; exit 1; }

# Row shape and the two enumerations, plus the class-dependent disposition rule
# taken from the page's own class definitions rather than invented: class A is
# the one prose cannot retire (fix, demote, narrow), B is fix or document, C is
# fix, defer or tracked.
#
# What this does NOT check, said here because the page states an invariant that
# sounds stronger: it validates the disposition WORD, not that the adjudication
# was executed. An A row saying `narrow` with no rationale, or `fix` before the
# fix lands, passes. Execution is a human-reviewed assertion carried by the
# manifest's rationale column; the gate holds the form, review holds the claim
# (R1 P1-2).
printf '%s\n' "$mrows" | awk -F'\t' '
    BEGIN {
        split("config-format report-schema exit-codes replay-compatibility mcp-surface none", s, " ")
        for (i in s) surf[s[i]] = 1
        allowed["A"] = " fix demote narrow measured-already-fixed "
        allowed["B"] = " fix document "
        allowed["C"] = " fix defer tracked "   # the page names all three
    }
    {
        n = $1
        if (NF != 8) { printf "FAIL: #%s has %d columns, wanted 8\n", n, NF; bad = 1; next }
        if (!($4 in surf)) { printf "FAIL: #%s surface %s is not one of the five or none\n", n, $4; bad = 1 }
        if ($5 == "")     { printf "FAIL: #%s has an empty surface_reason\n", n; bad = 1 }
        if ($3 == "")     { printf "FAIL: #%s has an empty what_it_is\n", n; bad = 1 }
        if ($6 != "A" && $6 != "B" && $6 != "C") { printf "FAIL: #%s class %s is not A, B or C\n", n, $6; bad = 1; next }
        if (index(allowed[$6], " " $7 " ") == 0) {
            printf "FAIL: #%s class %s cannot resolve by %s (allowed:%s)\n", n, $6, $7, allowed[$6]
            bad = 1
        }
    }
    END { if (bad) exit 1 }
' || exit 1

# The page's table must be a fresh render of the manifest, byte for byte. Set
# equality is what the old gate checked and it cannot see a cell being rewritten.
sh "$ROOT/spike/freeze-audit/render-audit.sh" --check || exit 1

echo "ok: the table covers all $want_count snapshot issues, the manifest matches it row for row with every enum and disposition rule held, and the gate goes red on a one-row-deleted copy"
