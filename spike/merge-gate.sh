#!/bin/sh
# merge-gate.sh — print one verdict line for "may this PR be merged", and
# refuse when the evidence for a merge does not exist.
#
# Written after three merges went out wrong in two cohorts, each one a
# different way of reading "no failures" out of nothing:
#
#   #184  merged with the review fix still unstaged — the commit was cut
#         before the last edit, so the merged tree lacked the fix.
#   #194  merged with a red gate: watch, count and merge were chained in
#         one command, so the count was never a decision.
#   #216  merged on "no checks reported": 0 pass, 0 fail, 0 pending, read
#         as "nothing failed". Zero checks is absence of evidence.
#
# The gate therefore requires all of:
#   * at least one successful check (a zero denominator refuses)
#   * no failing check, no pending check
#   * a clean working tree
#   * origin/<head branch> (or HEAD) equal to the PR's head SHA
#
# Usage:
#   sh spike/merge-gate.sh <pr-number> [owner/repo]
#   sh spike/merge-gate.sh --selftest     # falsify the predicate offline
#
# Output is one line beginning PASS, REFUSE or BROKEN, every count with
# its denominator. Exit 0 PASS, 1 REFUSE, 2 the gate could not measure —
# never merge on a 2 either.
#
# Deliberately NOT a merge command: chaining the wait to the merge is
# exactly how #194 happened. Read the line, then decide, then merge.
set -u

CLASSIFY_PY='
import json, sys

try:
    rollup = json.load(sys.stdin)
except Exception as exc:
    print("BROKEN unparseable rollup: %s" % exc)
    sys.exit(0)

if rollup is None:
    rollup = []

success = failure = pending = other = 0
for c in rollup:
    # CheckRun carries status/conclusion; StatusContext carries state.
    state = (c.get("conclusion") or c.get("state") or "").upper()
    status = (c.get("status") or "").upper()
    if status in ("QUEUED", "IN_PROGRESS", "WAITING", "PENDING", "REQUESTED"):
        pending += 1
    elif state in ("SUCCESS", "NEUTRAL", "SKIPPED"):
        success += 1
    elif state in ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT",
                   "ACTION_REQUIRED", "STARTUP_FAILURE"):
        failure += 1
    elif state in ("PENDING", "EXPECTED", ""):
        pending += 1
    else:
        other += 1

total = len(rollup)
reasons = []
if total == 0:
    reasons.append("no checks reported (0 of 0) - absence of evidence")
if failure:
    reasons.append("failing %d of %d" % (failure, total))
if pending:
    reasons.append("pending %d of %d" % (pending, total))
if other:
    reasons.append("unclassified %d of %d" % (other, total))
if total and success == 0 and not reasons:
    reasons.append("no successful check among %d" % total)

verdict = "PASS" if not reasons else "REFUSE"
print("%s checks success=%d/%d failure=%d/%d pending=%d/%d other=%d/%d%s" % (
    verdict, success, total, failure, total, pending, total, other, total,
    "" if not reasons else " | " + "; ".join(reasons)))
'

# Both the live path and --selftest go through this function: a self-test
# that exercises a copy proves nothing about the gate (#65's class).
classify() {
    python3 -c "$CLASSIFY_PY"
}

selftest() {
    fails=0
    total=0
    check() { # label expected payload
        total=$((total + 1))
        got=$(printf '%s' "$3" | classify)
        case "$got" in
            "$2"*) echo "  ok      $1 -> ${got%% *}" ;;
            *)     echo "  FAILED  $1 -> $got (expected $2)"
                   fails=$((fails + 1)) ;;
        esac
    }
    echo "== merge-gate self-test: the predicate, falsified against itself"
    check "empty rollup (#216)"    REFUSE '[]'
    check "one failure (#194)"     REFUSE '[{"status":"COMPLETED","conclusion":"FAILURE"},{"status":"COMPLETED","conclusion":"SUCCESS"}]'
    check "still running"          REFUSE '[{"status":"IN_PROGRESS","conclusion":null}]'
    check "legacy pending context" REFUSE '[{"state":"PENDING"}]'
    check "null rollup"            REFUSE 'null'
    check "malformed json"         BROKEN 'not json at all'
    check "all green"              PASS   '[{"status":"COMPLETED","conclusion":"SUCCESS"},{"status":"COMPLETED","conclusion":"SKIPPED"}]'
    echo "== self-test failures: $fails of $total"
    [ "$fails" -eq 0 ] || return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "" | -h | --help)
        awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
        exit 2 ;;
esac

pr=$1
repo_arg=""
[ $# -ge 2 ] && repo_arg="--repo $2"

command -v gh >/dev/null 2>&1 ||
    { echo "BROKEN gh not installed - the gate cannot measure"; exit 2; }
command -v python3 >/dev/null 2>&1 ||
    { echo "BROKEN python3 not installed - the gate cannot measure"; exit 2; }

# Exit status first, always: a pipe's status is not the command's, which
# is how a failed `docker build | tail` was read as a success.
meta=$(gh pr view "$pr" $repo_arg --json state,headRefName,headRefOid 2>&1)
rc=$?
[ $rc -eq 0 ] || { echo "BROKEN gh pr view rc=$rc: $meta"; exit 2; }

rollup=$(gh pr view "$pr" $repo_arg --json statusCheckRollup -q '.statusCheckRollup' 2>&1)
rc=$?
[ $rc -eq 0 ] || { echo "BROKEN gh statusCheckRollup rc=$rc: $rollup"; exit 2; }

line=$(printf '%s' "$rollup" | classify)
case "$line" in BROKEN*) echo "$line"; exit 2 ;; esac

field() { printf '%s' "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
state=$(field state)
head_ref=$(field headRefName)
head_oid=$(field headRefOid)

problems=""
[ "$state" = "OPEN" ] || problems="$problems; pr state is $state"

# #184, from the tree side: the commit must be cut after the last edit.
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "$dirty" = "0" ] ||
    problems="$problems; working tree dirty ($dirty path(s))"

# #184, from the remote side: what is on the PR must be what is here.
local_oid=$(git rev-parse "origin/$head_ref" 2>/dev/null ||
            git rev-parse HEAD 2>/dev/null || echo none)
[ "$local_oid" = "$head_oid" ] ||
    problems="$problems; local $local_oid != pr head $head_oid"

if [ -n "$problems" ]; then
    printf 'REFUSE pr #%s %s | tree/head%s\n' "$pr" "${line#* }" "$problems"
    exit 1
fi

printf '%s pr #%s %s | tree clean, head %s\n' \
    "${line%% *}" "$pr" "${line#* }" "$head_oid"
case "$line" in PASS*) exit 0 ;; *) exit 1 ;; esac
