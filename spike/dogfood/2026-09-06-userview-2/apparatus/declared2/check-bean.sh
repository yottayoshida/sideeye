#!/bin/sh
f=/work/st2/bc/l.beancount
[ -f "$f" ] || { echo "l.beancount が無い"; exit 1; }
bean-check "$f" > /dev/null 2>&1 || {
  echo "l.beancount を bean-check が通せない（$(wc -c < "$f") bytes）"; exit 1; }
for t in lunch coffee; do
  grep -q "\"$t\"" "$f" || { echo "元の取引 $t が消えた"; exit 1; }
done
exit 0
