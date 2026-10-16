#!/bin/sh
# Leg a (usable) only: the database is left unwritable, so recover.sh and the next
# read-write session cannot open it, while every read-only read still sees the
# valid starting data.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
chmod 0444 "$DB"
