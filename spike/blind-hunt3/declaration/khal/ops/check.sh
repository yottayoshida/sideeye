#!/bin/sh
# Campaign-3 Seal B artifact (ADR 0012 via ADR 0015/0016): the declared
# checker for khal 0.14.0, one dispatch per declared operation. Written
# BLIND: no trace of khal, no crash observation, no source, no bug tracker.
#
# Structure (ADR 0016 requirement 1, bought by the khard burn): FILE legs run
# first, the target runs LAST. A state that fails a file leg never reaches a
# khal invocation, and every failure message names its leg — the pin doubles
# as the no-execution proof. Every khal invocation below is a `search` query
# over a vdir whose bystander file the byte leg just proved golden; each
# query runs with a FRESH scratch HOME, so khal's ambient cache (outside the
# state root) is rebuilt cache-cold from the vdir every time, and the
# observed create-missing-vdir behavior stays out of reach (the vdir the
# sealed conf names is proven populated before any query).
#
# Injection seams, used by the red suite only (defaults are the sealed
# values; the engine invokes this checker with neither set):
#   CHECK_KHAL    binary the query legs run   (default /usr/local/bin/khal)
#   CHECK_TIMEOUT seconds before a query is a hang (default 10)
#
# Exit: 0 all legs hold / 1 a leg failed (message names the leg) /
#       2 environment (mktemp, missing sealed golden)
set -u

op=${1:?usage: check.sh <import|update|new>}
KHAL=${CHECK_KHAL:-/usr/local/bin/khal}
TMO=${CHECK_TIMEOUT:-10}
here=$(cd "$(dirname "$0")" && pwd)
S=/tmp/blind3/hunt/$op/state
conf=$here/khal-$op.conf
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker($op): $*"; exit 1; }

# ---- dispatch ----
case $op in
    import|update|new) : ;;
    *) fail "operation '$op' is not in the declared inventory" ;;
esac

# ---- environment ----
golden=$here/golden-grace-event.ics
[ -f "$golden" ] || { echo "checker($op): environment: sealed golden $golden is missing"; exit 2; }
[ -f "$conf" ]   || { echo "checker($op): environment: sealed conf $conf is missing"; exit 2; }

# ---- I-C: byte conservation of the bystander event file (file leg) ----
conserved=$S/cal/grace-fixed-uid-001.ics
[ -f "$conserved" ] || fail "I-C: conserved event file $conserved is missing"
cmp -s "$golden" "$conserved" || fail "I-C: conserved event file $conserved differs from its sealed golden"

# ---- query legs (the target runs, LAST). Snapshot first: I-W requires the
# queries to leave every byte of the vdir unchanged. ----
cp -R "$S/cal" "$T/snap" || exit 2

q() { # q <needle> -> qrc, qout; fresh HOME per invocation (cache-cold)
    QH=$(mktemp -d) || exit 2
    qout=$(HOME=$QH timeout "$TMO" "$KHAL" -c "$conf" search "$1" < /dev/null 2>&1)
    qrc=$?
    rm -rf "$QH"
}

# I-Q: bystander liveness through khal's own search. khal exits 0 even on no
# match (observed), so the exit code alone certifies nothing — the anchored
# full line carries the invariant (grep -Fxc: the exact observed line, whole
# line, fixed string).
q GraceStandup
[ "$qrc" -eq 0 ] || fail "I-Q: bystander query exited $qrc: $qout"
matches=$(printf '%s\n' "$qout" | grep -Fxc "02.09. 10:00-02.09. 11:00 GraceStandup")
[ "$matches" -eq 1 ] || fail "I-Q: expected exactly one anchored match line, got $matches: $qout"

# I-T: subject-query totality (import and update). A hang is the violation;
# no exit-code set is claimed (declaration: only 0 was ever observed, and
# observed-normal cannot ground a wider set).
if [ "$op" = import ] || [ "$op" = update ]; then
    QH=$(mktemp -d) || exit 2
    HOME=$QH timeout "$TMO" "$KHAL" -c "$conf" search AdaMeeting < /dev/null > /dev/null 2>&1
    trc=$?
    rm -rf "$QH"
    [ "$trc" -ne 124 ] || fail "I-T: subject query did not terminate within ${TMO}s"
fi

# I-W: the queries wrote nothing into the vdir.
diff -r "$T/snap" "$S/cal" > /dev/null 2>&1 || fail "I-W: a query changed the vdir's bytes"

exit 0
