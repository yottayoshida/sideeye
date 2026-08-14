#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the declared checker for
# abook 0.6.1, one dispatch per declared operation. Written BLIND: no trace of
# abook, no crash observation, no source, no bug tracker.
#
# Structure bought by the khard burn: FILE legs run first, the target runs
# LAST. A state that fails a file leg never reaches an abook invocation, and
# every failure message names its leg — a red case's pinned message is
# thereby also proof of which leg fired and that no later leg ran. Every
# abook invocation below is a query (abook(1): "search the addressbook") over
# a store the byte leg just proved equal to a sealed golden — except import's
# outfile, whose post-crash state is exactly the declared I-T territory
# (declaration.md).
#
# Injection seams, used by the red suite only (defaults are the sealed
# values; the engine invokes this checker with neither set):
#   CHECK_ABOOK   binary the query legs run   (default /usr/bin/abook)
#   CHECK_TIMEOUT seconds before a query is a hang (default 10)
#
# Exit: 0 all legs hold / 1 a leg failed (message names the leg) /
#       2 environment (mktemp, missing sealed golden)
set -u

op=${1:?usage: check.sh <import|export|refused>}
ABOOK=${CHECK_ABOOK:-/usr/bin/abook}
TMO=${CHECK_TIMEOUT:-10}
here=$(cd "$(dirname "$0")" && pwd)
S=/tmp/blind2/hunt/$op/state
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
tab=$(printf '\t')

fail() { echo "checker($op): $*"; exit 1; }

# ---- dispatch ----
case $op in
    import)         golden=$here/golden-grace.addressbook; conserved=$S/keep/addressbook ;;
    export|refused) golden=$here/golden-pair.addressbook;  conserved=$S/book/addressbook ;;
    *) fail "operation '$op' is not in the declared inventory" ;;
esac

# ---- environment (a missing sealed golden is apparatus breakage, not a
# target verdict) ----
[ -f "$golden" ] || { echo "checker($op): environment: sealed golden $golden is missing"; exit 2; }

# ---- I-C: byte conservation (file leg; the target does not run) ----
[ -f "$conserved" ] || fail "I-C: conserved store $conserved is missing"
cmp -s "$golden" "$conserved" || fail "I-C: conserved store $conserved differs from its sealed golden"

# ---- I-Q: bystander liveness (query leg — the first point the target runs,
# over a store the byte leg just proved golden) ----
cp "$conserved" "$T/c.before" || exit 2
qout=$(timeout "$TMO" "$ABOOK" --datafile "$conserved" --mutt-query grace@example.com < /dev/null 2>&1)
qrc=$?
[ "$qrc" -eq 0 ] || fail "I-Q: bystander query exited $qrc: $qout"
matches=$(printf '%s\n' "$qout" | grep -c "^grace@example.com${tab}Grace Hopper${tab}")
[ "$matches" -eq 1 ] || fail "I-Q: expected exactly one anchored match line, got $matches: $qout"
cmp -s "$T/c.before" "$conserved" || fail "I-Q: the query changed the conserved store's bytes"

# ---- I-T: query totality on the import outfile (import only). The outfile
# may be absent or partial after a crash; the declared property is the
# interface — terminate, exit in {0,1}, write nothing — not the shape. ----
if [ "$op" = import ]; then
    book=$S/book/addressbook
    had=0
    if [ -e "$book" ]; then had=1; cp "$book" "$T/b.before" || exit 2; fi
    tout=$(timeout "$TMO" "$ABOOK" --datafile "$book" --mutt-query ada@example.com < /dev/null 2>&1)
    trc=$?
    case $trc in
        0|1) : ;;
        *) fail "I-T: outfile query exited $trc, outside the documented {0,1}: $tout" ;;
    esac
    if [ "$had" -eq 1 ]; then
        cmp -s "$T/b.before" "$book" || fail "I-T: the query changed the outfile's bytes"
    elif [ -e "$book" ]; then
        fail "I-T: the query created the outfile"
    fi
fi

exit 0
