#!/bin/sh
# Breaks leg d (next run) and no other: from the valid start, a trigger that aborts every
# UPDATE of notes, so 0002's backfill fails and the next apply exits non-zero. Record, tables,
# columns, indexes and rows are the start's; leg b does not read triggers (INVARIANT.md).
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
python3 -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(sys.argv[2]); c.close()' \
    "$S/app.db" "CREATE TRIGGER notes_frozen BEFORE UPDATE ON notes BEGIN SELECT RAISE(ABORT, 'notes are frozen'); END;"
