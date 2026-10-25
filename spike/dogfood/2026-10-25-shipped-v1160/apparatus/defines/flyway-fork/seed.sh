set -eu
rm -rf /s/fw && mkdir -p /s/fw/sql && cd /s/fw
cat > sql/V1__orders.sql <<'SQL'
CREATE TABLE orders (id INTEGER PRIMARY KEY, status TEXT NOT NULL, cents INTEGER NOT NULL);
WITH RECURSIVE s(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM s WHERE x < 999) INSERT INTO orders SELECT x, 'new', x * 3 FROM s;
SQL
flyway -url=jdbc:sqlite:/s/fw/app.db -locations=filesystem:/s/fw/sql migrate > /dev/null
cat > sql/V2__ship.sql <<'SQL'
ALTER TABLE orders ADD COLUMN shipped_at TEXT;
UPDATE orders SET status = 'shipped', shipped_at = '2026-10-25' WHERE id % 2 = 0;
CREATE INDEX orders_status ON orders(status);
SQL
install -m 755 /ap/defines/flyway/check.sh /s/fw-check.sh
