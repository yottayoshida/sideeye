#!/bin/sh
# What a user runs after a crash, before using the database again: gdbmtool's own
# `recover` (gdbm_recover), which checks the database and rebuilds it when it finds it
# broken. gdbmtool exits 0 even when a command fails, so success here is the line
# "Recovery succeeded." with nothing on stderr.
set -u
DB=${SIDEEYE_STATE_DIR:?}/db.gdbm
# `recover` on a missing file creates an empty database and reports success; a user
# recovers a database that exists, so a missing one is a failed recovery, not a new db.
[ -f "$DB" ] || { echo "recover: $DB is missing" >&2; exit 1; }
err=$(mktemp) || exit 1
out=$(gdbmtool -N -q "$DB" recover summary 2>"$err")
msg=$(cat "$err"); rm -f "$err"
echo "recover: $(printf '%s' "$out" | tr '\n' ' ')"
[ -z "$msg" ] || { echo "recover: $msg" >&2; exit 1; }
printf '%s\n' "$out" | grep -qx 'Recovery succeeded.' || exit 1
exit 0
