#!/bin/sh
# grafana.db whole (a journal left beside it is rolled back, as the next open would), every migration
# still logged, every table there, one admin, and the admin's password either the old or the new one.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
ic=$(sqlite3 "$t/grafana.db" "PRAGMA integrity_check" 2>&1)
got=$(sqlite3 "$t/grafana.db" "SELECT count(*) FROM migration_log; SELECT count(*) FROM sqlite_master WHERE type = 'table'" 2>&1 | tr '\n' ' ')
u=$(sqlite3 "$t/grafana.db" "SELECT count(*) FROM user WHERE login = 'admin'" 2>&1)
pw=$(sqlite3 "$t/grafana.db" "SELECT password FROM user WHERE login = 'admin'" 2>&1)
rm -rf "$t"
[ "$ic" = ok ] || { echo "checker(grafana): integrity_check: $(echo "$ic" | head -2 | tr '\n' ' ')"; exit 1; }
[ "$got" = "$(cat /s/.grafana-expect)" ] || { echo "checker(grafana): migrations tables = $got, want $(cat /s/.grafana-expect)"; exit 1; }
[ "$u" = 1 ] || { echo "checker(grafana): admin users = $u"; exit 1; }
grep -qxF -- "$pw" /s/.grafana-pw || { echo "checker(grafana): the admin's password hash is neither the old one nor the new one"; exit 1; }
