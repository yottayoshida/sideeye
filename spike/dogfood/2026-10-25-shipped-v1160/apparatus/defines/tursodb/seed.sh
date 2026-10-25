set -eu
rm -rf /s/turso && mkdir -p /s/turso && cd /s/turso
tursodb -q -v syscall shop.db "CREATE TABLE orders (id INTEGER PRIMARY KEY, status TEXT, cents INTEGER)" < /dev/null
tursodb -q -v syscall shop.db "WITH RECURSIVE s(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM s WHERE x < 999) INSERT INTO orders SELECT x, 'new', x * 3 FROM s" < /dev/null
install -m 755 /ap/defines/tursodb/check.sh /s/turso-check.sh
