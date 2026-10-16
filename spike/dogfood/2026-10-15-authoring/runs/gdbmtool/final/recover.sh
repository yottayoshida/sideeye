#!/bin/sh
# What a user runs after a crashed gdbmtool session, before using the database again.
#
# GDBM's documented path for a structurally damaged database is gdbm_recover,
# reached from the shell as gdbmtool's `recover` command (listed by `gdbmtool help`;
# the GDBM manual, "Recovering structural integrity"). A user notices the damage
# when reading fails, so: read the whole database once; if gdbmtool complains,
# run `recover`. gdbmtool exits 0 whether or not a command failed, so its stderr
# is the only signal (friction.tsv).
#
# State directory: $SIDEEYE_STATE_DIR, or $1.
set -u
S=${1:-${SIDEEYE_STATE_DIR:?}}
DB=$S/db.gdbm

# Nothing to recover from: a missing database is the checker's to reject. Do not
# let gdbmtool's default open mode (wrcreat) create an empty one here.
[ -f "$DB" ] || exit 0

probe=$(timeout 30 gdbmtool -N -q -r "$DB" list 2>&1 >/dev/null)
[ -z "$probe" ] && exit 0

echo "recover.sh: read failed ($probe); running gdbmtool recover" >&2
timeout 60 gdbmtool -N -q "$DB" recover summary >&2
exit 0
