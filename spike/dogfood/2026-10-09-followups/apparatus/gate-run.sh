#!/bin/sh
# Host side: the entry gate over every define — the unpinned ones in one box (gate.sh), each pinned
# one in a box of its own.
#   sh apparatus/gate-run.sh > transcripts/entry-candidates.txt
here="$(cd "$(dirname "$0")" && pwd)"
unpinned=""; pinned=""
for t in ${*:-$(ls "$here/defines")}; do
  if grep -q ld.so.preload "$here/defines/$t/env.sh" 2>/dev/null; then pinned="$pinned $t"; else unpinned="$unpinned $t"; fi
done
[ -n "$unpinned" ] && sh "$here/gate.sh" $unpinned
for t in $pinned; do sh "$here/gate.sh" $t; done
