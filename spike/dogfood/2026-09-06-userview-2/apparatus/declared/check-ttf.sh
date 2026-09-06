#!/bin/sh
f=/work/st/ff/f.ttf
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fontforge -lang=ff -c "Open(\"$f\");" > /dev/null 2>&1 || {
  echo "f.ttf を fontforge が開けない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
