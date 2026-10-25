#!/bin/sh
# Read the way the next user reads: tursodb opens a copy (recovering a WAL left behind), then
# SQLite's own integrity_check on what that open left.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
out=$(tursodb -q -m list "$t/shop.db" "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" < /dev/null 2>&1); rc=$?
ic=$(sqlite3 "$t/shop.db" "PRAGMA integrity_check" 2>&1)
rm -rf "$t"
[ $rc -eq 0 ] || { echo "checker(tursodb): does not open: $(echo "$out" | head -2 | tr '\n' ' ')"; exit 1; }
[ "$ic" = ok ] || { echo "checker(tursodb): integrity_check: $(echo "$ic" | head -2 | tr '\n' ' ')"; exit 1; }
case "$out" in
  "1000|0|1498500"|"1000|500|1499000") exit 0 ;;
  *) echo "checker(tursodb): rows, shipped, cents = $out (want 1000|0|1498500 or 1000|500|1499000)"; exit 1 ;;
esac
