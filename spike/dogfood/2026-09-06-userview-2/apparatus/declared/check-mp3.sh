#!/bin/sh
for n in a b c; do
  f="/work/st/m3/$n.mp3"
  [ -f "$f" ] || { echo "$n.mp3 が無い"; exit 1; }
  mid3v2 -l "$f" > /dev/null 2>&1 || {
    echo "$n.mp3 を mid3v2 が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  mid3v2 -l "$f" 2>/dev/null | grep -q 'keep' || {
    echo "$n.mp3 から元のタグ ORIG:keep が消えた"; exit 1; }
done
exit 0
