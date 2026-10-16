#!/bin/sh
# Control for leg a: the database can no longer be read, and recover.sh cannot repair it.
# The magic number is overwritten (offset 0): gdbmtool refuses to open it and
# recover refuses too. Legs b..e are then not judged ("-"), not failed.
# Built from the valid starting state (setup.sh) in $1; breaks leg a and no other.
set -eu
S=${1:?state directory}
"$(dirname "$0")/setup.sh" "$S"
printf "\377" | dd of="$S/db.gdbm" bs=1 seek=0 conv=notrunc 2>/dev/null
