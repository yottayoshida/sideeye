#!/bin/sh
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
out=$(duckdb "$t/shop.duckdb" -csv -noheader -c "SELECT count(*), count(*) FILTER (WHERE status = 'shipped'), sum(cents) FROM orders" < /dev/null 2>&1); rc=$?
rm -rf "$t"
[ $rc -eq 0 ] || { echo "checker(duckdb): the database does not open: $(echo "$out" | head -2 | tr '\n' ' ')"; exit 1; }
case "$out" in
  "1000,0,1498500"|"1000,10,1498500") exit 0 ;;
  *) echo "checker(duckdb): rows, shipped, cents = $out (want 1000 and 0 or 10, and 1498500)"; exit 1 ;;
esac
