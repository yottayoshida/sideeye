set -eu
rm -rf /s/sx && mkdir -p /s/sx/migrations && cd /s/sx
cat > migrations/20260101000000_orders.sql <<'SQL'
CREATE TABLE orders (id INTEGER PRIMARY KEY, status TEXT NOT NULL, cents INTEGER NOT NULL);
WITH RECURSIVE s(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM s WHERE x < 999) INSERT INTO orders SELECT x, 'new', x * 3 FROM s;
SQL
sqlx database create > /dev/null
sqlx migrate run --source /s/sx/migrations > /dev/null
cat > migrations/20260102000000_ship.sql <<'SQL'
ALTER TABLE orders ADD COLUMN shipped_at TEXT;
UPDATE orders SET status = 'shipped', shipped_at = '2026-10-25' WHERE id % 2 = 0;
CREATE INDEX orders_status ON orders(status);
SQL
install -m 755 /ap/defines/sqlx/check.sh /s/sx-check.sh
