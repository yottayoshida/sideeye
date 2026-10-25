#!/bin/sh
# app.db whole (a journal left beside it is rolled back, as the next open would), and the history
# agrees with the schema: V2 recorded as a success with its column, its index and its 500 rows, or not
# recorded and none of them there. A failed V2 row is Flyway's own record of a failure, which its
# `repair` command exists for; it is reported, not accepted.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
ic=$(sqlite3 "$t/app.db" "PRAGMA integrity_check" 2>&1)
h=$(sqlite3 "$t/app.db" "SELECT group_concat(version || ':' || success, ',') FROM (SELECT version, success FROM flyway_schema_history ORDER BY installed_rank)" 2>&1)
c=$(sqlite3 "$t/app.db" "SELECT count(*) FROM pragma_table_info('orders') WHERE name = 'shipped_at'" 2>&1)
x=$(sqlite3 "$t/app.db" "SELECT count(*) FROM sqlite_master WHERE type = 'index' AND name = 'orders_status'" 2>&1)
r=$(sqlite3 "$t/app.db" "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" 2>&1)
rm -rf "$t"
[ "$ic" = ok ] || { echo "checker(flyway): integrity_check: $(echo "$ic" | head -2 | tr '\n' ' ')"; exit 1; }
case "$h|$c|$x|$r" in
  "1:1|0|0|1000|0|1498500"|"1:1,2:1|1|1|1000|500|1498500") ;;
  *) echo "checker(flyway): history|column|index|rows = $h|$c|$x|$r"; exit 1 ;;
esac
