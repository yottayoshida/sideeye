#!/bin/sh
# The valid starting state: a GDBM database holding exactly three records,
# k1=v1 k2=v2 k3=v3, written by gdbmtool itself. The state directory is
# $SIDEEYE_STATE_DIR, or $1 when a control builds a state of its own.
set -eu
S=${1:-${SIDEEYE_STATE_DIR:?}}
mkdir -p "$S"
rm -rf "$S"/* "$S"/.[!.]* 2>/dev/null || true
err=$(gdbmtool -N -q -n "$S/db.gdbm" store k1 v1 \; store k2 v2 \; store k3 v3 2>&1 >/dev/null)
# gdbmtool exits 0 even when a command fails; its stderr is the only signal.
[ -z "$err" ] || { echo "setup: gdbmtool said: $err" >&2; exit 1; }
