#!/bin/sh
a=/work/st2/ar/a.tar
[ -f "$a" ] || { echo "a.tar が無い"; exit 1; }
list=$(bsdtar -tf "$a" 2>/dev/null) || {
  echo "a.tar を bsdtar が読めない（$(wc -c < "$a") bytes）"; exit 1; }
for n in f1.txt f2.txt; do
  echo "$list" | grep -qx "$n" || {
    echo "a.tar から元のエントリ $n が消えた"; exit 1; }
done
exit 0
