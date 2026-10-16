#!/bin/sh
# A state only the recovery makes usable: one new key stored, then the first
# directory entry pointed past the end of the file, so gdbmtool cannot list the
# database until recover.sh rebuilds it (measured: "File seek error" before,
# all keys back after). Built by hand, not by a crash.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
err=$(gdbmtool -N -q "$DB" store n1 w1 2>&1); [ -z "$err" ] || { echo "$err" >&2; exit 1; }
dir=$(gdbmtool -N -q -r "$DB" header | awk '/directory start/ { print $4 }')
printf '\377\377\377\377' | dd of="$DB" bs=1 seek="$dir" conv=notrunc status=none
