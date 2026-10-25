set -eu
rm -rf /s/app /s/.diesel-ref && mkdir -p /s/app/src /s/app/migrations/2026-01-01-000000_create_orders && cd /s/app
printf '[print_schema]\nfile = "src/schema.rs"\n' > diesel.toml
cat > migrations/2026-01-01-000000_create_orders/up.sql <<'SQL'
CREATE TABLE orders (id INTEGER PRIMARY KEY NOT NULL, status TEXT NOT NULL, cents INTEGER NOT NULL);
WITH RECURSIVE s(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM s WHERE x < 999) INSERT INTO orders SELECT x, 'new', x * 3 FROM s;
SQL
echo 'DROP TABLE orders;' > migrations/2026-01-01-000000_create_orders/down.sql
DATABASE_URL=/s/app/app.db diesel setup > /dev/null
DATABASE_URL=/s/app/app.db diesel print-schema > src/schema.rs
m=migrations/2026-01-02-000000_add_shipped_at; mkdir -p $m
cat > $m/up.sql <<'SQL'
ALTER TABLE orders ADD COLUMN shipped_at TEXT;
UPDATE orders SET status = 'shipped', shipped_at = '2026-10-25' WHERE id % 2 = 0;
CREATE INDEX orders_status ON orders(status);
SQL
echo 'DROP INDEX orders_status; ALTER TABLE orders DROP COLUMN shipped_at;' > $m/down.sql
# The two schema.rs a reader may find: the one before the migration, and the one diesel writes after
# it (made on a copy, so the run itself starts from the pending state).
mkdir -p /s/.diesel-ref; cp src/schema.rs /s/.diesel-ref/before.rs
cp -a /s/app /s/.diesel-ref/app
(cd /s/.diesel-ref/app && DATABASE_URL=/s/.diesel-ref/app/app.db diesel migration run > /dev/null && cp src/schema.rs /s/.diesel-ref/after.rs)
install -m 755 /ap/defines/diesel/check.sh /s/diesel-check.sh
