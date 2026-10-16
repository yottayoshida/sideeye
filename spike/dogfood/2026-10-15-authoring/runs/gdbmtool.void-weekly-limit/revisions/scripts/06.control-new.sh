#!/bin/sh
# Leg c (new) only: n1, one of the keys the session stores, holds a value the
# session never wrote.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
err=$(gdbmtool -N -q "$DB" store n1 wrong 2>&1); [ -z "$err" ] || { echo "$err" >&2; exit 1; }
