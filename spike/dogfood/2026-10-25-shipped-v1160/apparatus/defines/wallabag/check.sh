#!/bin/sh
# After a crash anywhere inside `wallabag:import`, the database is one SQLite and wallabag can open, and
# the six articles the user had before are all there: SQLite's integrity check passes, and wallabag's
# own `wallabag:export` writes all six titles out.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(wallabag): $*"; exit 1; }
[ -f "$d/wallabag.sqlite" ] || fail "wallabag.sqlite is missing"
r=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("pragma integrity_check").fetchone()[0])' "$d/wallabag.sqlite" 2>&1) || fail "sqlite could not open the database: $r"
[ "$r" = ok ] || fail "integrity_check: $r"
out=$(cd /opt/wallabag && php bin/console wallabag:export wallabag /tmp/wb-check-export.json --env=prod -n 2>&1) || fail "wallabag:export exited $?: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"
for i in 0 1 2 3 4 5; do grep -q "\"Saved article $i\"" /tmp/wb-check-export.json || fail "article $i is gone"; done
exit 0
