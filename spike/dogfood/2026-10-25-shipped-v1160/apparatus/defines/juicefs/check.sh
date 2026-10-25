#!/bin/sh
# After a crash anywhere inside `juicefs config`, JuiceFS itself still opens the volume: `juicefs
# status` on the metadata database exits 0 and names the volume with its UUID unchanged, and SQLite's
# integrity check passes on the file.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(juicefs): $*"; exit 1; }
[ -f "$d/jfs.db" ] || fail "jfs.db is missing"
r=$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("pragma integrity_check").fetchone()[0])' "$d/jfs.db" 2>&1) || fail "sqlite could not open jfs.db: $r"
[ "$r" = ok ] || fail "integrity_check: $r"
out=$(juicefs status "sqlite3://$d/jfs.db?_journal=DELETE" 2>/dev/null) || fail "juicefs status exited $?"
uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["Setting"]["UUID"])' /s/jfsaux/status-before.json)
printf '%s' "$out" | grep -q "\"$uuid\"" || fail "the volume UUID $uuid is gone from status"
printf '%s' "$out" | grep -q '"homevol"' || fail "the volume name is gone from status"
exit 0
