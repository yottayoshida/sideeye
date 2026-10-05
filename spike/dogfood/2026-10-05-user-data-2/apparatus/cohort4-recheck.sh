#!/bin/sh
# Every name the screen read fresh, searched again in cohort 4's own documents — the ledger fresh.sh
# does not read. Found after the explores: ffsubsync is a cohort-4 candidate rejected on rule 5
# (spike/cohort4/CANDIDATES-REJECTED.md), and fresh.sh had called it fresh.
#   sh apparatus/cohort4-recheck.sh <file of names, one per line>
here="$(cd "$(dirname "$0")" && pwd)"; c4="$here/../../../cohort4"
while read -r n; do
  [ -n "$n" ] || continue
  h=""
  for f in "$c4"/CANDIDATES-REJECTED.md "$c4"/SCOUT-ROWS.md "$c4"/SCOUT-ROWS-SLOT2.md "$c4"/PREP.md "$c4"/PROTOCOL.md "$c4"/PROTOCOL-DRAFT.md "$c4"/rule11-*.txt; do
    [ -f "$f" ] || continue
    if grep -q -i -F -- "$n" "$f"; then h="$h $(basename "$f"):$(grep -n -i -F -m1 -- "$n" "$f" | cut -d: -f1)"; fi
  done
  [ -n "$h" ] && echo "$n:$h"
done < "$1"
echo "cohort4-recheck: done"
