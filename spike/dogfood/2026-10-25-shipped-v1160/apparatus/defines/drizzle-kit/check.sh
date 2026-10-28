#!/bin/sh
# After a crash anywhere in the migration, the database opens, passes SQLite's integrity check and
# still holds the 120 notes the app wrote; and running the same migrate again (the documented way to
# finish one) succeeds and leaves the schema the second migration describes.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(drizzle-kit): $*"; exit 1; }
python3 - "$d/app.db" <<'PY' || fail "the database is unreadable, fails integrity_check or lost notes"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
assert c.execute("pragma integrity_check").fetchone()[0] == "ok"
assert c.execute("select count(*) from notes").fetchone()[0] == 120
PY
( cd /s/dz && UV_THREADPOOL_SIZE=1 node node_modules/drizzle-kit/bin.cjs migrate --config drizzle.config.ts ) > /tmp/dz-rerun.txt 2>&1 || fail "re-running migrate exited $?: $(tail -c 300 /tmp/dz-rerun.txt)"
python3 - "$d/app.db" <<'PY' || fail "after the re-run the schema or the data migration is not what 0001 describes"
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
assert c.execute("select count(*) from notes where archived = 1").fetchone()[0] == 40
assert c.execute("select count(*) from tags").fetchone()[0] == 120
PY
exit 0
