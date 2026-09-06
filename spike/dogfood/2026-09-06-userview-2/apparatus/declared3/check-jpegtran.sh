#!/bin/sh
f=/work/st3/jt/a.jpg
[ -f "$f" ] || { echo "a.jpg が無い"; exit 1; }
out=$(djpeg -pnm "$f" 2>/dev/null | head -c 32) || {
  echo "a.jpg を djpeg が読めない（$(wc -c < "$f") bytes）"; exit 1; }
[ -n "$out" ] || { echo "a.jpg から画素が出てこない（$(wc -c < "$f") bytes）"; exit 1; }
echo "$out" | head -1 | grep -q "P" || { echo "a.jpg の展開結果が PNM でない"; exit 1; }
exit 0
