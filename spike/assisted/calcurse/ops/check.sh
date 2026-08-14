#!/bin/sh
# Assisted run (#118), calcurse P1 checker. Property (proposals.md P1): the
# bystander event survives any crash during a purge that targets only the
# other event — conservation through a full-file rewrite (the class where
# campaign 1 found topydo's counterexamples). File legs first, target last.
set -u
D=/tmp/assisted/calcurse/state/d
E=/tmp/assisted/calcurse/state/expected
CONF=/tmp/assisted/calcurse/conf
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
TAB=$(printf '\t')

fail() { echo "checker(calcurse-purge): $*"; exit 1; }

[ -d "$D" ] || fail "data dir is missing"
[ -d "$E" ] || fail "expected reference copy is missing from the recorded state"

# ---- I-C file legs: the bystander's apts line, exactly once; todo conserved ----
[ -f "$D/apts" ] || fail "I-C: apts is missing (it existed before the operation)"
g=$(grep -Fxc "09/02/2026 @ 10:00 -> 09/02/2026 @ 11:00|GraceStandup" "$D/apts")
[ "$g" -eq 1 ] || fail "I-C: expected exactly one GraceStandup apts line, got $g"
cmp -s "$E/todo" "$D/todo" || fail "I-C: todo differs from the recorded copy (or is missing)"

# ---- query leg (the target runs LAST; write-neutral over the data dir) ----
cp -R "$D" "$T/snap" || exit 2
qout=$(timeout 10 calcurse -D "$D" -C "$CONF" -Q --from 09/01/2026 --to 09/03/2026 < /dev/null 2>&1)
qrc=$?
[ "$qrc" -eq 0 ] || fail "I-Q: query exited $qrc: $qout"
m=$(printf '%s\n' "$qout" | grep -Fxc "${TAB}GraceStandup")
[ "$m" -eq 1 ] || fail "I-Q: expected exactly one anchored GraceStandup line, got $m: $qout"
diff -r "$T/snap" "$D" > /dev/null 2>&1 || fail "I-W: the query changed the data dir's bytes"

exit 0
