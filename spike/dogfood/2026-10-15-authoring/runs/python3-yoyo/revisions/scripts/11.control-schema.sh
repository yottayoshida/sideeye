#!/bin/sh
# Breaks leg b (schema) and no other: from the valid start, an index on notes that no migration
# makes. The record is 0001, the rows are whole, and 0002 and 0003 still apply over it.
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
python3 -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(sys.argv[2]); c.close()' \
    "$S/app.db" "CREATE INDEX idx_extra ON notes (body);"
