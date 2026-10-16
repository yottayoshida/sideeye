#!/bin/sh
# Breaks leg a (record) and no other: from the valid start, yoyo's own `mark` records 0003 as
# applied while 0002 is not. The schema is still 0001's (a shape b accepts when the record is
# not one of the three), the rows are whole, and the next apply runs 0002 and lists all three.
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
cd "$S"
python3 -m yoyo mark --batch --database sqlite:///app.db -m 0003 migrations
