#!/bin/sh
# Leg d (nothing else) only: a key neither the starting state nor the session has.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
err=$(gdbmtool -N -q "$DB" store zz x 2>&1); [ -z "$err" ] || { echo "$err" >&2; exit 1; }
