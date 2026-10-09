#!/bin/sh
# a.pdf is scratch (a fresh document ID in every run, the clock pinned or not); this judges it instead:
# hexapdf itself must read it, with the old 3 pages or the 2 that `modify -i 1-2` keeps.
f="$SIDEEYE_STATE_DIR/a.pdf"
out=$(hexapdf info "$f" 2>&1) || { echo "hexapdf cannot read a.pdf: $(echo "$out" | head -1 | cut -c1-120)"; exit 1; }
n=$(echo "$out" | awk -F: '/^Pages/{gsub(/ /,"",$2); print $2}')
case "$n" in 2|3) exit 0 ;; esac
echo "a.pdf has '$n' pages, neither the old 3 nor the new 2"; exit 1
