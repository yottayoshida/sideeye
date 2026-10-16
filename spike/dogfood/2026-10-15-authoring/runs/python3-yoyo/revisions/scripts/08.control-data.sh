#!/bin/sh
# Breaks leg c (data) and no other: from the valid start, yoyo applies 0002 alone (a state the
# operation may leave), then one row loses its backfill. Record and schema agree on 0002, and
# the next apply only has 0003's index to make.
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
cd "$S"
python3 -m yoyo apply --batch --database sqlite:///app.db -r 0002-add-body-len migrations
python3 -I -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.executescript(sys.argv[2]); c.close()' \
    "$S/app.db" "UPDATE notes SET body_len = NULL WHERE id = 42;"
