#!/bin/sh
# The database: whole (integrity_check), and the migration table agrees with the table it records —
# the second migration is either recorded with its column and its 500 rows, or neither. The
# schema.rs: one of the two files a user's build could read, byte for byte.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
ic=$(sqlite3 "$t/app.db" "PRAGMA integrity_check" 2>&1)
v=$(sqlite3 "$t/app.db" "SELECT group_concat(version, ',') FROM (SELECT version FROM __diesel_schema_migrations ORDER BY version)" 2>&1)
cols=$(sqlite3 "$t/app.db" "SELECT count(*) FROM pragma_table_info('orders') WHERE name = 'shipped_at'" 2>&1)
rows=$(sqlite3 "$t/app.db" "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" 2>&1)
sb=1; cmp -s "$t/src/schema.rs" /s/.diesel-ref/before.rs && sb=0
sa=1; cmp -s "$t/src/schema.rs" /s/.diesel-ref/after.rs && sa=0
sz=$(wc -c < "$t/src/schema.rs" 2>/dev/null || echo missing)
rm -rf "$t"
[ "$ic" = ok ] || { echo "checker(diesel): integrity_check: $ic"; exit 1; }
case "$v|$cols|$rows" in
  "20260101000000|0|1000|0|1498500"|"20260101000000,20260102000000|1|1000|500|1498500") ;;
  *) echo "checker(diesel): migrations|column|rows = $v|$cols|$rows"; exit 1 ;;
esac
[ $sb -eq 0 ] || [ $sa -eq 0 ] || { echo "checker(diesel): src/schema.rs ($sz bytes) is neither the file before the migration nor the one after"; exit 1; }
