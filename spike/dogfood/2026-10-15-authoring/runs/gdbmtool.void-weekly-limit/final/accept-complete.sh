#!/bin/sh
# The completed state: the session ran to its end on the starting state.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
gdbmtool -N -q -m -f "$HERE/session.txt" "$DB"
