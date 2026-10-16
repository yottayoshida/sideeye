#!/bin/sh
# Builds the valid starting state in $SIDEEYE_STATE_DIR: app.db with 0001 applied by yoyo
# itself, and migrations/ holding all three migrations, two of them pending.
set -eu
S=${SIDEEYE_STATE_DIR:?}
D=$(cd "$(dirname "$0")" && pwd)
cd "$S"
rm -rf app.db app.db-journal migrations
mkdir migrations
cp "$D/0001-create-notes.sql" migrations/
python3 -m yoyo apply --batch --database sqlite:///app.db migrations
cp "$D/0002-add-body-len.sql" "$D/0003-index-body-len.sql" migrations/
