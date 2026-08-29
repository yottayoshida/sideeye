#!/bin/sh
# The freeze audit's gate. Two tables on docs/freeze-audit.md are generated from
# spike/freeze-audit/audit.tsv (ADR 0027); what moved on a frozen surface is
# recorded in surface-changes.tsv and measured by surface-drift.sh (ADR 0028).
# This script holds the FORM of all of it, and says plainly what it does not hold.
#
#   sh spike/freeze-audit/check-freeze-audit.sh          # the gate, offline
#   sh spike/freeze-audit/check-freeze-audit.sh --live   # state against the tracker
#
# Check-12 shape: the gate proves it can go red on every run by judging a tampered
# copy of the page. The tampered copy is generated HERE, at run time, from the real
# page — a committed fixture rots silently after a re-sweep, and an absent fixture
# must never read as a passed falsification (both measured in review).
#
# WHAT THIS GATE DOES NOT CHECK, stated because the page states invariants that
# sound stronger:
#   - It validates a disposition WORD, not that the adjudication was executed. An
#     A row saying `narrow` with nothing behind it passes. Execution is a
#     human-reviewed assertion carried by the rationale column.
#   - It holds the ENUMERATED half of each frozen surface (see surface-drift.sh's
#     three rungs). The behavioural clauses — which call site returns which exit
#     code, a field's meaning, the input schemas, the isError rule — are read, not
#     measured. #273 moved the exit-code surface in this window while the ExitCode
#     enum stayed byte-identical, so this is a measured limit, not a theoretical one.
#   - An active row's surface entry is a FORECAST. Nothing here can check a
#     forecast; only the next sweep's measurement can.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

# The snapshot is this gate's trust root for the POPULATION — which issues belong
# in the tables. A re-sweep replaces the file and this name together.
SNAPSHOT="$ROOT/spike/freeze-audit/snapshot-2026-08-29.tsv"
# The raw acquisition is the trust root for the ACCOUNTING — the window's open set,
# what closed inside it, and every count on the page. Before this sweep those
# numbers came from a transcript and could not be recomputed by a reader.
RAW="$ROOT/spike/freeze-audit/capture-2026-08-29-raw.json"
MANIFEST="$ROOT/spike/freeze-audit/audit.tsv"
CHANGES="$ROOT/spike/freeze-audit/surface-changes.tsv"
PAGE="$ROOT/docs/freeze-audit.md"
DECLARATION="docs/contract-freeze.md"
# The revision of the normative declaration this sweep's readings were taken
# against. Pinned because the declaration MOVED three times inside the 08-18..08-27
# window (the additive allowance, the exit-code rewrite, the surface-4 correction);
# in the 2026-08-27..08-29 window it is byte-identical (rung 1 of
# surface-drift-2026-08-29.txt), so the fourth sweep reads the same yardstick the
# third did. A sweep that does not say which yardstick it used has not said what
# it measured.
DECLARATION_PIN="b7902d641b95cfea4150790b9948ea1d5b4c844f"
# The window this sweep covers. Its opening is the commit that installed the
# snapshot being replaced (33049a9, the third sweep): the snapshot and the
# declaration it was read against are one trust root.
WINDOW_OPENS="2026-08-27T05:54:56Z"

TMP=$(mktemp -d) || { echo "FAIL: cannot create a temp directory"; exit 1; }
# Cleanup is non-recursive on purpose: `rm -rf` on a directory is intercepted by
# this developer's own guard tooling, which left the directory behind AND printed
# into this script's output.
cleanup_TMP() { rm -f "$TMP"/* 2>/dev/null; rmdir "$TMP" 2>/dev/null; }
trap cleanup_TMP EXIT HUP INT TERM

for f in "$SNAPSHOT" "$RAW" "$MANIFEST" "$CHANGES" "$PAGE"; do
    [ -s "$f" ] || { echo "FAIL: missing or empty: $f"; exit 1; }
done
command -v python3 > /dev/null 2>&1 || { echo "FAIL: this gate needs python3 to read the raw capture"; exit 1; }

# Manifest rows, once. Every non-comment non-header line is a data line: an earlier
# version filtered to rows whose first field was numeric, which the renderer does
# not do, so a row numbered "oops" rendered as #oops and was seen by nothing.
mrows="$TMP/mrows"
awk -F'\t' '!/^#/ && NF > 0 && $1 != "number"' "$MANIFEST" > "$mrows"
mcount=$(grep -c . "$mrows" || true)
[ "$mcount" -gt 0 ] || { echo "FAIL: the manifest yielded no rows"; exit 1; }

active_nums="$TMP/active" ; resolved_nums="$TMP/resolved"
awk -F'\t' '$2 == "active"   {print $1}' "$mrows" | LC_ALL=C sort > "$active_nums"
awk -F'\t' '$2 == "resolved" {print $1}' "$mrows" | LC_ALL=C sort > "$resolved_nums"
snap_nums="$TMP/snap"
cut -f1 "$SNAPSHOT" | tr -d '#' | LC_ALL=C sort > "$snap_nums"
snap_count=$(grep -c . "$snap_nums" || true)
[ "$snap_count" -gt 0 ] || { echo "FAIL: the snapshot yielded no issue numbers"; exit 1; }

# --- --live: state, against the tracker --------------------------------------
# The default gate is offline and cannot see that the snapshot has aged. This mode
# asks the tracker. It lives here rather than in CI for the same reason the gate
# does — it needs the network — which is precisely why it can reach the tracker.
#
# THE PREDICATE CHANGED IN THIS SWEEP, and the reason is measured. It used to be
# "the snapshot IS the tracker's open set". A sweep closes its own obligation
# issue, so that equality breaks the moment a sweep lands: #86 closed at
# 2026-08-18T04:06:58Z, one second after the snapshot commit at 04:06:57Z, and the
# predicate has been false ever since. It could only ever have held for an instant,
# which makes "run it green before the tag" unachievable rather than strict.
#
# The predicate now: every snapshot issue the tracker still shows open has an
# ACTIVE row, and every snapshot issue the tracker shows closed has a RESOLVED
# row. That is what "the page has caught up with the tracker" means, and it
# survives a sweep closing its own issues. Drift outside the snapshot — issues
# filed since — is reported the same way as before.
if [ "${1-}" = "--live" ]; then
    command -v gh > /dev/null 2>&1 || { echo "FAIL: --live needs gh on PATH"; exit 1; }
    LIMIT=1000
    # Two steps, not a pipeline: sh reports the status of a pipeline's LAST
    # command, so `| sort` hid a failing gh entirely and the script carried on with
    # an empty set — which would have reported every snapshot issue as closed.
    raw="$TMP/live.raw"
    gh issue list --state open --limit "$LIMIT" --json number --jq '.[].number' > "$raw" \
        || { echo "FAIL: the tracker query failed"; exit 1; }
    # Sorted lexically, not numerically: comm compares against LC_COLLATE order,
    # and numerically-sorted input made it report five numbers as both added and
    # removed on this mode's first run.
    live="$TMP/live"
    LC_ALL=C sort "$raw" > "$live" || { echo "FAIL: sorting the tracker result failed"; exit 1; }
    live_count=$(grep -c . "$live" || true)
    if [ "$live_count" -ge "$LIMIT" ]; then
        echo "FAIL: the tracker query returned $live_count at --limit $LIMIT — possibly truncated, raise the limit"
        exit 1
    fi
    echo "snapshot: $snap_count issues ($(basename "$SNAPSHOT"))"
    echo "tracker:  $live_count open, queried at $(date -u +%Y-%m-%dT%H:%M:%SZ) with --limit $LIMIT"

    comm -12 "$snap_nums" "$live" > "$TMP/snap_open"   || { echo "FAIL: comm failed"; exit 1; }
    comm -23 "$snap_nums" "$live" > "$TMP/snap_closed" || { echo "FAIL: comm failed"; exit 1; }
    comm -23 "$TMP/snap_open"   "$active_nums"   > "$TMP/open_not_active"     || { echo "FAIL: comm failed"; exit 1; }
    comm -23 "$TMP/snap_closed" "$resolved_nums" > "$TMP/closed_not_resolved" || { echo "FAIL: comm failed"; exit 1; }
    comm -13 "$snap_nums" "$live" > "$TMP/added" || { echo "FAIL: comm failed"; exit 1; }
    bad_open=$(grep -c . "$TMP/open_not_active" || true)
    bad_closed=$(grep -c . "$TMP/closed_not_resolved" || true)
    added=$(grep -c . "$TMP/added" || true)

    status=0
    if [ "$bad_open" != "0" ]; then
        echo "DRIFT: $bad_open snapshot issue(s) still open with no ACTIVE row:"
        sort -n "$TMP/open_not_active" | sed 's/^/#/' | tr '\n' ' '; echo
        status=3
    fi
    if [ "$bad_closed" != "0" ]; then
        echo "DRIFT: $bad_closed snapshot issue(s) now closed with no RESOLVED row:"
        sort -n "$TMP/closed_not_resolved" | sed 's/^/#/' | tr '\n' ' '; echo
        status=3
    fi
    if [ "$added" != "0" ]; then
        echo "DRIFT: $added open issue(s) filed since the snapshot and not in it:"
        sort -n "$TMP/added" | sed 's/^/#/' | tr '\n' ' '; echo
        status=3
    fi
    if [ "$status" = "0" ]; then
        echo "ok   no drift: every snapshot issue still open has an active row, every one now closed has a resolved row, and nothing has been filed since"
        exit 0
    fi
    echo "exit 3 — drift is not a gate failure (that is exit 1); it is the audit noticing its own age"
    exit 3
fi

# --- leg 1: the yardstick this sweep read ------------------------------------
decl_now=$(git -C "$ROOT" rev-parse "HEAD:$DECLARATION" 2>/dev/null) \
    || { echo "FAIL: cannot read $DECLARATION at HEAD"; exit 1; }
if [ "$decl_now" != "$DECLARATION_PIN" ]; then
    echo "FAIL: $DECLARATION has moved since this sweep read it"
    echo "  pinned: $DECLARATION_PIN"
    echo "  HEAD:   $decl_now"
    echo "  The declaration moved three times inside the window this sweep audits, so a"
    echo "  reading taken against another revision is a reading of another promise."
    echo "  Re-read the surfaces, then update DECLARATION_PIN in the same commit."
    exit 1
fi

# --- leg 2: population — every snapshot issue has exactly one row ------------
all_nums="$TMP/all"
cut -f1 "$mrows" | LC_ALL=C sort > "$all_nums"
comm -23 "$snap_nums" "$all_nums" > "$TMP/missing" || { echo "FAIL: comm failed"; exit 1; }
missing=$(grep -c . "$TMP/missing" || true)
if [ "$missing" != "0" ]; then
    echo "FAIL: $missing snapshot issue(s) have no manifest row:"
    sort -n "$TMP/missing" | sed 's/^/  #/'
    exit 1
fi
badnum=$(awk -F'\t' '$1 !~ /^[0-9]+$/ {print $1}' "$mrows")
[ -z "$badnum" ] || { echo "FAIL: manifest rows with a non-numeric issue number: $badnum"; exit 1; }
dupes=$(cut -f1 "$mrows" | LC_ALL=C sort | uniq -d | grep -c . || true)
[ "$dupes" = "0" ] || { echo "FAIL: the manifest repeats $dupes issue number(s)"; exit 1; }

# --- leg 3: row shape, the enumerations, the class-dependent disposition rule --
# Class A is the restricted one because it is the class the page says prose cannot
# retire. B, C and D share a wider set; D adds `contain` (the exposure is bounded
# by a stated operational precondition rather than removed). Migrating the
# seventeen historical rows is what showed the earlier set had been written from
# the thirteen active rows alone: it had no room for `document` on a class-C row,
# for `measured-already-fixed` outside class A, or for a duplicate.
awk -F'\t' '
    BEGIN {
        split("config-format report-schema exit-codes replay-compatibility mcp-surface none", s, " ")
        for (i in s) surf[s[i]] = 1
        # after-1.0 is deliberately ABSENT from class A. Scheduling a
        # PASS-overclaim gap out of the release is the outcome class A forbids, so
        # accepting it there would let the one clause with teeth be satisfied by a
        # calendar rather than by a fix, a demotion or a narrowing.
        allowed["A"] = " fix demote narrow measured-already-fixed duplicate "
        allowed["B"] = " fix document defer tracked after-1.0 measured-already-fixed duplicate "
        allowed["C"] = " fix document defer tracked after-1.0 measured-already-fixed duplicate "
        allowed["D"] = " fix contain document defer tracked after-1.0 measured-already-fixed duplicate "
    }
    {
        n = $1
        if (NF != 9) { printf "FAIL: #%s has %d columns, wanted 9\n", n, NF; bad = 1; next }
        if ($2 != "active" && $2 != "resolved") { printf "FAIL: #%s state %s is not active or resolved\n", n, $2; bad = 1; next }
        # Every field is required to be non-empty BEFORE any enumeration is applied.
        # A split of an empty string yields zero elements, so an empty
        # classification axis walked straight through the enum loops below and a
        # snapshot issue could sit in the table with no forecast at all.
        for (c = 1; c <= 9; c++) if ($c == "") { printf "FAIL: #%s column %d is empty\n", n, c; bad = 1 }
        if ($3 == "") next
        if ($2 == "active") {
            if ($5 != "-") { printf "FAIL: #%s is active but carries change ids (%s) — a forecast is not a measurement\n", n, $5; bad = 1 }
            if ($4 == "" || $4 == "-") { printf "FAIL: #%s is active with no surface forecast\n", n; bad = 1 }
            else {
                if (split($4, fc, " ") == 0) { printf "FAIL: #%s forecast is blank\n", n; bad = 1 }
                for (i in fc) if (!(fc[i] in surf)) { printf "FAIL: #%s forecast %s is not one of the five or none\n", n, fc[i]; bad = 1 }
            }
        } else {
            if ($4 != "-") { printf "FAIL: #%s is resolved but carries a forecast (%s) — its surface entry is measured\n", n, $4; bad = 1 }
            if ($5 == "" || $5 == "-") { printf "FAIL: #%s is resolved with no surface measurement entry\n", n; bad = 1 }
            else if ($5 != "none" && $5 != "not-measured") {
                if (split($5, ids, " ") == 0) { printf "FAIL: #%s change ids are blank\n", n; bad = 1 }
                for (i in ids) if (ids[i] !~ /^sc-[0-9][0-9]$/) { printf "FAIL: #%s change id %s is malformed\n", n, ids[i]; bad = 1 }
            }
        }
        # The renderer prepends the disposition in bold, so a rationale that opens
        # with its own disposition renders it twice. Four migrated rows did, and
        # byte-equality between page and render could not see it because both
        # sides were doubled; it surfaced from a secret scan reading the diff.
        if ($9 ~ ("^[*][*]" $8 "[*][*]")) {
            printf "FAIL: #%s rationale repeats its own disposition (%s) — the renderer already prepends it\n", n, $8
            bad = 1
        }
        if (!($7 in allowed)) { printf "FAIL: #%s class %s is not A, B, C or D\n", n, $7; bad = 1; next }
        if (index(allowed[$7], " " $8 " ") == 0) {
            printf "FAIL: #%s class %s cannot resolve by %s (allowed:%s)\n", n, $7, $8, allowed[$7]
            bad = 1
        }
    }
    END { if (bad) exit 1 }
' "$mrows" || exit 1

# --- leg 4: referential integrity between the two ledgers --------------------
crows="$TMP/crows"
awk -F'\t' '!/^#/ && NF > 0 && $1 != "change_id"' "$CHANGES" > "$crows"
ccount=$(grep -c . "$crows" || true)
[ "$ccount" -gt 0 ] || { echo "FAIL: surface-changes.tsv yielded no rows"; exit 1; }
# The change ledger's own semantics, not just its column count. The first version
# checked ten columns, unique ids and referential integrity, and nothing else — so
# `legality`, the axis this sweep introduced to say whether a movement was
# permitted, could hold any string or be blank and still pass (review P1-6).
awk -F'\t' '
    BEGIN {
        split("config-format report-schema exit-codes replay-compatibility mcp-surface", s, " ")
        for (i in s) surf[s[i]] = 1
        split("add remove bump semantic", k, " ")
        for (i in k) kind[k[i]] = 1
        split("pre-tag-required additive-allowed declared-not-a-break declaration-amended", l, " ")
        for (i in l) leg[l[i]] = 1
    }
    {
        id = $1
        if (NF != 10) { printf "FAIL: change %s has %d columns, wanted 10\n", id, NF; bad = 1; next }
        if (id !~ /^sc-[0-9][0-9]$/) { printf "FAIL: change id %s is malformed\n", id; bad = 1 }
        for (c = 1; c <= 10; c++) if ($c == "") { printf "FAIL: change %s column %d is empty\n", id, c; bad = 1 }
        if (!($2 in surf)) { printf "FAIL: change %s surface %s is not one of the five\n", id, $2; bad = 1 }
        if (!($4 in kind)) { printf "FAIL: change %s kind %s is not add, remove, bump or semantic\n", id, $4; bad = 1 }
        if (!($9 in leg))  { printf "FAIL: change %s legality %s is not one of the four recorded readings\n", id, $9; bad = 1 }
        if ($7 !~ /^[0-9a-f]{7,40}$/) { printf "FAIL: change %s commit %s is not a sha\n", id, $7; bad = 1 }
        if ($8 != "-" && $8 !~ /^[0-9]+( [0-9]+)*$/) { printf "FAIL: change %s issues %s is not a space-separated number list or -\n", id, $8; bad = 1 }
        if (length($10) < 40) { printf "FAIL: change %s evidence is %d characters — too short to carry a reading\n", id, length($10); bad = 1 }
    }
    END { if (bad) exit 1 }
' "$crows" || exit 1
# Every commit named must exist in this repository: a sha-shaped string is not a sha.
while read -r c; do
    git -C "$ROOT" cat-file -e "${c}^{commit}" 2>/dev/null \
        || { echo "FAIL: surface-changes.tsv names commit $c, which is not in this repository"; exit 1; }
done <<EOF
$(cut -f7 "$crows" | LC_ALL=C sort -u)
EOF
cut -f1 "$crows" | LC_ALL=C sort > "$TMP/change_ids"
dupc=$(cut -f1 "$crows" | LC_ALL=C sort | uniq -d | grep -c . || true)
[ "$dupc" = "0" ] || { echo "FAIL: surface-changes.tsv repeats a change_id"; exit 1; }
awk -F'\t' '$2 == "resolved" && $5 != "none" && $5 != "not-measured" { for (i = 1; i <= split($5, a, " "); i++) print a[i] }' "$mrows" \
    | LC_ALL=C sort -u > "$TMP/referenced"
comm -23 "$TMP/referenced" "$TMP/change_ids" > "$TMP/dangling" || { echo "FAIL: comm failed"; exit 1; }
dangling=$(grep -c . "$TMP/dangling" || true)
[ "$dangling" = "0" ] || { echo "FAIL: manifest rows reference change ids that do not exist: $(tr '\n' ' ' < "$TMP/dangling")"; exit 1; }
# The reverse direction, which is the one that catches a change recorded and then
# orphaned: every change must be reachable from a row, unless it names no causing
# issue at all (sc-13 is such a change — a correction made in passing, where
# attributing it to the issue that rode the same commit would be association).
awk -F'\t' '$8 != "-" {print $1}' "$crows" | LC_ALL=C sort > "$TMP/changes_with_issues"
comm -23 "$TMP/changes_with_issues" "$TMP/referenced" > "$TMP/orphans" || { echo "FAIL: comm failed"; exit 1; }
orphans=$(grep -c . "$TMP/orphans" || true)
[ "$orphans" = "0" ] || { echo "FAIL: changes name a causing issue but no row references them: $(tr '\n' ' ' < "$TMP/orphans")"; exit 1; }

# --- leg 5: the measured closed set must equal what the ledger records --------
# The one part of surface 2 the additive allowance does not cover, so the sharpest
# thing the enumerated diff measures. Recomputed here rather than trusted from the
# drift script's prose, and the base extraction is asserted non-empty first: a diff
# against an empty set is indistinguishable from a total rewrite, which is how the
# first run of this measurement reported "29 members added" when five had been.
#
# TWO COMPARISONS, not one, and they mean different things. The measurement was
# taken against a specific revision of src/contract.zig, pinned below. Comparing
# base -> pin against the ledger is an invariant that reproduces forever. Comparing
# pin -> HEAD asks a different question — did a frozen surface move AFTER this
# sweep? — and that is drift, not malformation, so it exits 3 like population
# drift rather than 1. The first version of this leg compared base -> HEAD and
# would have gone red with exit 1 the moment the next closed-set member landed,
# reporting a stale audit as a broken one. It also closes a hole this page
# otherwise only described: a surface can move without any issue changing state,
# which `--live` cannot see because it only asks about issues.
# The revisions this sweep measured, one per file that defines an enumerated set.
# Each is a blob sha rather than a commit: a blob is what the extraction actually
# read, and it survives history rewrites of everything else.
PIN_config="c5fa9f6cf6abef5471cf215fddfa59f6094743cc"       # src/config.zig
PIN_contract="02c0cfad41c45b1b1ffde4004f2b0034a895eb5a"     # src/contract.zig (read by the fourth sweep, 2026-08-29; first moved with sc-14..sc-17)
PIN_mcp="10f025316fd5190ef59aaea1a7219a46895d8c4a"          # src/mcp.zig
PIN_schema="7c177179a92ba12049969f3e32f22cd22c51fd34"       # docs/report-schema.md

# The enumerated-set definitions are shared with surface-drift.sh rather than
# copied: two copies of six extractions, hand-synced, would let the gate and the
# drift report disagree about what a surface IS while each stayed internally
# consistent. Anything NOT extracted there is rung-3 residue and the page says so;
# this leg covers exactly those sets and claims nothing wider (review P1-1: the
# first version diffed only unknown_reason while the page claimed "the enumerated
# half of each frozen surface", so an ExitCode renumbering passed).
. "$ROOT/spike/freeze-audit/surface-sets.sh"
extract_set() {  # extract_set <set-name> <blob>
    git -C "$ROOT" cat-file -p "$2" 2>/dev/null | extract_surface_set "$1"
}

# set_name  path  pinned-blob
SETS="unknown_reason:src/contract.zig:$PIN_contract
exit_codes:src/contract.zig:$PIN_contract
contract_version:src/contract.zig:$PIN_contract
config_keys:src/config.zig:$PIN_config
mcp_tools:src/mcp.zig:$PIN_mcp
schema_fields:docs/report-schema.md:$PIN_schema"

surface_drift=0
: > "$TMP/drift_report"
printf '%s\n' "$SETS" | while IFS=: read -r setname path pin; do
    [ -n "$setname" ] || continue
    git -C "$ROOT" cat-file -e "$pin" 2>/dev/null \
        || { echo "FAIL: the pinned $path blob $pin is not in this repository"; exit 1; }
    hb=$(git -C "$ROOT" rev-parse "HEAD:$path" 2>/dev/null) \
        || { echo "FAIL: cannot resolve $path at HEAD"; exit 1; }
    extract_set "$setname" "$pin" > "$TMP/s_pin"  || exit 1
    extract_set "$setname" "$hb"  > "$TMP/s_head" || exit 1
    # BOTH sides asserted non-empty. The first version asserted only the base, so
    # breaking the extractor on the head side reported every element as removed and
    # still exited 0 (review P1-4).
    for side in s_pin s_head; do
        n=$(grep -c . "$TMP/$side" || true)
        [ "$n" -gt 0 ] || { echo "FAIL: $setname extracted EMPTY from $side — refusing to compare"; exit 1; }
    done
    if ! cmp -s "$TMP/s_pin" "$TMP/s_head"; then
        {
            printf '  %s (%s):\n' "$setname" "$path"
            comm -13 "$TMP/s_pin" "$TMP/s_head" | sed 's/^/      added:   /'
            comm -23 "$TMP/s_pin" "$TMP/s_head" | sed 's/^/      removed: /'
        } >> "$TMP/drift_report"
    fi
done || exit 1
[ ! -s "$TMP/drift_report" ] || surface_drift=1

# The one invariant that reproduces forever: over the sweep's own window, the
# measured closed-set additions must be exactly what the ledger records.
# 8feae88 is the LEDGER's origin (the commit that installed the 2026-08-18
# snapshot, where surface-changes.tsv starts counting), not the current window's
# base: the ledger is cumulative across sweeps, so this invariant keeps covering
# every recorded closed-set addition rather than only the newest window's.
base_contract=$(git -C "$ROOT" rev-parse '8feae88:src/contract.zig' 2>/dev/null) \
    || { echo "FAIL: cannot resolve src/contract.zig at the ledger's origin"; exit 1; }
extract_set unknown_reason "$base_contract" > "$TMP/enum_base"
extract_set unknown_reason "$PIN_contract"  > "$TMP/enum_pin"
for f in enum_base enum_pin; do
    n=$(grep -c . "$TMP/$f" || true)
    [ "$n" -gt 0 ] || { echo "FAIL: the closed set extracted EMPTY from $f — refusing to compare"; exit 1; }
done
comm -13 "$TMP/enum_base" "$TMP/enum_pin" | sed 's|^|unknown_reason/|' | LC_ALL=C sort > "$TMP/enum_added"
awk -F'\t' '$3 ~ /^unknown_reason\// {print $3}' "$crows" | LC_ALL=C sort > "$TMP/ledger_added"
if ! cmp -s "$TMP/enum_added" "$TMP/ledger_added"; then
    echo "FAIL: over this sweep's own window the measured closed-set additions and"
    echo "      surface-changes.tsv disagree (< measured, > ledger):"
    diff "$TMP/enum_added" "$TMP/ledger_added" | sed 's/^/  /'
    exit 1
fi
measured_added=$(grep -c . "$TMP/enum_added" || true)

# --- leg 6: the window's accounting, recomputed from the committed capture ----
python3 - "$RAW" "$WINDOW_OPENS" "$snap_nums" "$resolved_nums" "$active_nums" <<'PY' || exit 1
import json, sys
raw, w0, snapf, resf, actf = sys.argv[1:6]
d = json.load(open(raw))
# Recompute the truncation facts; do not trust the capture's own boolean. Truncation
# is this audit's originating defect, so a self-reported flag is a claim, not
# evidence: a capture asserting limit=100, returned=152, returned_below_limit=true
# passed the first version of this leg (review P1-7).
rows = d["issues"]
limit, returned = d.get("limit"), d.get("returned")
if not isinstance(limit, int) or not isinstance(returned, int):
    print("FAIL: the capture does not record an integer limit and returned count"); sys.exit(1)
if len(rows) != returned:
    print(f"FAIL: the capture says returned={returned} but carries {len(rows)} issues"); sys.exit(1)
if returned >= limit:
    print(f"FAIL: the capture returned {returned} at limit {limit} — it may be truncated"); sys.exit(1)
if d.get("returned_below_limit") is not True:
    print("FAIL: the capture does not assert it was below its query limit"); sys.exit(1)
cmd = d.get("command", "")
if f"--limit {limit}" not in cmd:
    print(f"FAIL: the recorded command does not carry --limit {limit}: {cmd!r}"); sys.exit(1)
res = {l.strip() for l in open(resf) if l.strip()}
snap = {l.strip() for l in open(snapf) if l.strip()}
# Every issue opened AND closed inside the window must have a resolved row. A
# final-state capture cannot see these at all, which is why the page has this rule;
# this sweep's set is 38 where the previous sweep's was four.
window_closed = {str(r["number"]) for r in rows
                 if r["state"] == "CLOSED" and r["createdAt"] > w0 and r["closedAt"] and r["closedAt"] > w0}
missing = sorted(window_closed - res, key=int)
if missing:
    print(f"FAIL: {len(missing)} issue(s) opened and closed inside the window have no resolved row: "
          + " ".join("#" + m for m in missing)); sys.exit(1)
# The snapshot must be exactly the capture's open set: it was generated from it, so
# a disagreement means one of the two was hand-edited afterwards.
cap_open = {str(r["number"]) for r in rows if r["state"] == "OPEN"}
if cap_open != snap:
    only_cap = sorted(cap_open - snap, key=int); only_snap = sorted(snap - cap_open, key=int)
    print("FAIL: the snapshot is not the committed capture's open set")
    if only_cap:  print("  open in the capture, absent from the snapshot: " + " ".join("#"+x for x in only_cap))
    if only_snap: print("  in the snapshot, not open in the capture:      " + " ".join("#"+x for x in only_snap))
    sys.exit(1)
# Nothing already open when the window opened may be missing from the snapshot.
# That is the completeness property the previous snapshot was never checked for.
# The claim is bounded by this capture, which is what makes it checkable at all.
pre = {str(r["number"]) for r in rows if r["createdAt"] < w0 and r["state"] == "OPEN"}
gap = sorted(pre - snap, key=int)
if gap:
    print("FAIL: issues open since before the window are absent from the snapshot: "
          + " ".join("#"+g for g in gap)); sys.exit(1)
print(f"     window accounting: {len(window_closed)} issues filed and closed inside it, all with resolved rows;")
print(f"     snapshot is the committed capture's open set ({len(snap)}), with nothing pre-dating the window missing")
PY

# --- leg 7: the page is a fresh render of the manifest, both blocks -----------
sh "$ROOT/spike/freeze-audit/render-audit.sh" --check || exit 1

# --- leg 8: the self-falsification ------------------------------------------
table_numbers() { grep -oE '^\| #[0-9]+' "$1" | grep -oE '[0-9]+' | LC_ALL=C sort -u; }
active_count=$(grep -c . "$active_nums" || true)
page_active=$(table_numbers "$PAGE" | grep -c . || true)
if [ "$page_active" != "$active_count" ]; then
    echo "FAIL: the page shows $page_active active rows, the manifest has $active_count"
    exit 1
fi
first_row=$(grep -nE '^\| #[0-9]+' "$PAGE" | head -1 | cut -d: -f1)
[ -n "$first_row" ] || { echo "FAIL: no active classification rows found on the page"; exit 1; }
tampered="$TMP/tampered"
sed "${first_row}d" "$PAGE" > "$tampered"
tampered_count=$(table_numbers "$tampered" | grep -c . || true)
if [ "$tampered_count" -ne $((active_count - 1)) ]; then
    echo "FAIL: the tampered copy did not lose exactly one row (has $tampered_count, wanted $((active_count - 1)))"
    exit 1
fi
if [ "$(table_numbers "$tampered")" = "$(cat "$active_nums")" ]; then
    echo "FAIL: the tampered copy (one row deleted) was judged complete — the gate is blind"
    exit 1
fi
# And the judgment that must reject it is THE REAL ONE. The first version checked
# the tampered copy with a different predicate — row count and number set — so a
# mutation that made `render-audit.sh --check` always succeed left this
# falsification green: it proved that sed had deleted a line, not that the gate
# would refuse the result (review P1-8).
if sh "$ROOT/spike/freeze-audit/render-audit.sh" --check "$tampered" > /dev/null 2>&1; then
    echo "FAIL: the render check ACCEPTED a page with one active row deleted — the gate is blind"
    exit 1
fi

resolved_count=$(grep -c . "$resolved_nums" || true)

# Reported after every other leg has passed, so a stale audit never masks a
# malformed one. Exit 3 is the same code population drift uses: the audit noticing
# its own age, not a gate failure.
if [ "$surface_drift" = "1" ]; then
    echo "ok: $mcount rows ($active_count active, $resolved_count resolved) cover the $snap_count snapshot issues,"
    echo "    and everything this sweep measured still agrees with what it recorded."
    echo ""
    echo "DRIFT: an enumerated frozen surface has moved since this sweep measured it."
    cat "$TMP/drift_report"
    echo "  No issue needs to have changed state for this to happen, which is why"
    echo "  --live cannot see it: --live asks about issues, this asks about surfaces."
    echo "  Re-sweep, or extend surface-changes.tsv and move the pin in the same commit."
    echo "exit 3 — drift is not a gate failure (that is exit 1)"
    exit 3
fi

echo "ok: $mcount rows ($active_count active, $resolved_count resolved) cover the $snap_count snapshot issues;"
echo "    both tables are byte-identical renders of the manifest; every enum, the class-dependent"
echo "    disposition rule and both ledger directions hold; the $measured_added measured closed-set"
echo "    additions match surface-changes.tsv; the declaration is at the revision this sweep read;"
echo "    and the gate goes red on a one-row-deleted copy."
