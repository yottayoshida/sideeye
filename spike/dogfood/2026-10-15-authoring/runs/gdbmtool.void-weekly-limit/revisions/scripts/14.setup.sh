#!/bin/sh
# Builds the valid starting state: a GDBM database holding exactly three keys.
set -eu
S=${SIDEEYE_STATE_DIR:?}
rm -f "$S/db.gdbm"
err=$(gdbmtool -N -q -n "$S/db.gdbm" store k1 v1 \; store k2 v2 \; store k3 v3 2>&1)
[ -z "$err" ] || { echo "setup: $err" >&2; exit 1; }
