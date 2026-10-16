#!/bin/sh
# Leg b (old) only: k2, a key the database held before the operation, is gone.
# Written by gdbmtool itself, so the file stays well formed and recover.sh has
# nothing to heal.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
err=$(gdbmtool -N -q "$DB" delete k2 2>&1); [ -z "$err" ] || { echo "$err" >&2; exit 1; }
