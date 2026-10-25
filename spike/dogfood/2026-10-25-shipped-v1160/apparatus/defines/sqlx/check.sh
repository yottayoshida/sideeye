#!/bin/sh
# app.db whole (a journal or WAL left beside it is recovered, as the next open would), and the
# migration table agrees with the schema: the second migration recorded as a success with its column,
# its index and its 500 rows, or not recorded and none of them there.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
ic=$(sqlite3 "$t/app.db" "PRAGMA integrity_check" 2>&1)
h=$(sqlite3 "$t/app.db" "SELECT group_concat(version || ':' || success, ',') FROM (SELECT version, success FROM _sqlx_migrations ORDER BY version)" 2>&1)
c=$(sqlite3 "$t/app.db" "SELECT count(*) FROM pragma_table_info('orders') WHERE name = 'shipped_at'" 2>&1)
x=$(sqlite3 "$t/app.db" "SELECT count(*) FROM sqlite_master WHERE type = 'index' AND name = 'orders_status'" 2>&1)
r=$(sqlite3 "$t/app.db" "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" 2>&1)
rm -rf "$t"
[ "$ic" = ok ] || { echo "checker(sqlx): integrity_check: $(echo "$ic" | head -2 | tr '\n' ' ')"; exit 1; }
case "$h|$c|$x|$r" in
  "20260101000000:1|0|0|1000|0|1498500"|"20260101000000:1,20260102000000:1|1|1|1000|500|1498500") ;;
  *) echo "checker(sqlx): migrations|column|index|rows = $h|$c|$x|$r"; exit 1 ;;
esac
