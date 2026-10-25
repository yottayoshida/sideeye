set -eu
# The database every migration has created, made once per box by the same command (its first run
# creates grafana.db), then copied before each run. The admin's password hash is recorded for the
# password the seed set and for the one the operation sets (made on a copy), so the checker can tell
# either from a torn row.
mk_ini() {
    cat > "$1/grafana.ini" <<INI
[paths]
data = $1/data
logs = /s/aux/grafana-logs
plugins = /s/aux/grafana-plugins
[analytics]
reporting_enabled = false
check_for_updates = false
check_for_plugin_updates = false
INI
}
g=/usr/share/grafana/bin/grafana
mkdir -p /s/aux/grafana-logs /s/aux/grafana-plugins
if [ ! -f /s/.grafana-expect ]; then
    mkdir -p /s/.grafana-pristine/data
    mk_ini /s/.grafana-pristine
    $g cli --homepath /usr/share/grafana --config /s/.grafana-pristine/grafana.ini admin reset-admin-password first > /s/.grafana-seed.log 2>&1
    sqlite3 /s/.grafana-pristine/data/grafana.db "SELECT count(*) FROM migration_log; SELECT count(*) FROM sqlite_master WHERE type = 'table'" | tr '\n' ' ' > /s/.grafana-expect
    sqlite3 /s/.grafana-pristine/data/grafana.db "SELECT password FROM user WHERE login = 'admin'" > /s/.grafana-pw
    mkdir -p /s/.grafana-after && cp -a /s/.grafana-pristine/data /s/.grafana-after/data && mk_ini /s/.grafana-after
    $g cli --homepath /usr/share/grafana --config /s/.grafana-after/grafana.ini admin reset-admin-password second >> /s/.grafana-seed.log 2>&1
    sqlite3 /s/.grafana-after/data/grafana.db "SELECT password FROM user WHERE login = 'admin'" >> /s/.grafana-pw
fi
rm -rf /s/grafana && mkdir -p /s/grafana && cp -a /s/.grafana-pristine/data /s/grafana/data
mk_ini /s/grafana
install -m 755 /ap/defines/grafana/check.sh /s/grafana-check.sh
