#!/bin/sh
# Assisted run (#118), devtodo P1 checker. Property (proposals.md P1):
# removing one note conserves the other through the XML rewrite. File legs
# first (including an XML well-formedness parse that never runs the
# target), the target's own listing last.
set -u
export TERM=vt100
DB=/tmp/assisted/devtodo/state/.todo
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(devtodo-remove): $*"; exit 1; }

[ -f "$DB" ] || fail "the .todo database is missing (it existed before the operation)"

# ---- file legs ----
# grep -o | wc -l counts OCCURRENCES; grep -c counts lines and would call
# two GraceNotes on one line "1" (R1 finding 9).
g=$(grep -o "GraceNote" "$DB" | wc -l | tr -d ' ')
[ "$g" -eq 1 ] || fail "I-C: expected exactly one GraceNote in the XML, got $g"
python3 -c "import xml.etree.ElementTree as ET; ET.parse('$DB')" 2>/dev/null \
    || fail "I-F: the database is not well-formed XML"

# ---- query leg (the target runs LAST; write-neutral) ----
cp "$DB" "$T/snap" || exit 2
qout=$(timeout 10 devtodo --database "$DB" -A < /dev/null 2>/dev/null)
qrc=$?
[ "$qrc" -eq 0 ] || fail "I-Q: listing exited $qrc"
printf '%s\n' "$qout" | grep -q "GraceNote" || fail "I-Q: the bystander is missing from the target's own listing"
cmp -s "$T/snap" "$DB" || fail "I-W: the listing changed the database's bytes"

exit 0
