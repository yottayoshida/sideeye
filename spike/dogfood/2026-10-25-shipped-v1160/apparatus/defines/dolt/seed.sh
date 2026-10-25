set -eu
# dolt reads its user and metrics settings from $HOME/.dolt (env.sh's /s/aux/home).
mkdir -p "$HOME"
dolt config --global --add user.name seed > /dev/null 2>&1 || true
dolt config --global --add user.email seed@example.invalid > /dev/null 2>&1 || true
dolt config --global --add metrics.disabled true > /dev/null 2>&1 || true
rm -rf /s/dolt && mkdir -p /s/dolt && cd /s/dolt
dolt init > /dev/null
dolt sql -q "CREATE TABLE orders (id INT PRIMARY KEY, status VARCHAR(20), cents INT)"
dolt sql -q "INSERT INTO orders SELECT seq, 'new', seq * 3 FROM (WITH RECURSIVE s(seq) AS (SELECT 0 UNION ALL SELECT seq + 1 FROM s WHERE seq < 999) SELECT seq FROM s) t"
dolt add . && dolt commit -m seed > /dev/null
dolt sql -q "UPDATE orders SET status = 'shipped' WHERE id < 10"
dolt commit -am ship > /dev/null
install -m 755 /ap/defines/dolt/check.sh /s/dolt-check.sh
