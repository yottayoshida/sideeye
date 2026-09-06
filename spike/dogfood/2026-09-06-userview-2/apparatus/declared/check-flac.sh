#!/bin/sh
for n in a b c; do
  f="/work/st/fl/$n.flac"
  [ -f "$f" ] || { echo "$n.flac が無い"; exit 1; }
  metaflac --list "$f" > /dev/null 2>&1 || {
    echo "$n.flac を metaflac が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  metaflac --export-tags-to=- "$f" 2>/dev/null | grep -q '^ORIG=keep$' || {
    echo "$n.flac から元のタグ ORIG=keep が消えた"; exit 1; }
done
exit 0
