#!/bin/sh
# 2026-09-06-userview-2/apparatus/declared/check-ttf.sh, with the path moved: the font must
# still open in fontforge in every world.
f=/s/fontforge/ff/f.ttf
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fontforge -lang=ff -c "Open(\"$f\");" > /dev/null 2>&1 || {
  echo "f.ttf を fontforge が開けない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
