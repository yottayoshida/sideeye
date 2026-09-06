#!/bin/sh
f=/work/st2/ft/f.ttf
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fonttools ttx -q -o /dev/null "$f" > /dev/null 2>&1 || {
  echo "f.ttf を fonttools が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
