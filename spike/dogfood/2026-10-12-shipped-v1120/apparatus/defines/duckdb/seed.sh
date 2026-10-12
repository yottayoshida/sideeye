set -eu
rm -rf /s/duck && mkdir -p /s/duck
duckdb /s/duck/shop.duckdb -c "CREATE TABLE orders AS SELECT range AS id, 'new' AS status, range * 3 AS cents FROM range(1000); CHECKPOINT;" < /dev/null
install -m 755 /ap/defines/duckdb/check.sh /s/duck-check.sh
