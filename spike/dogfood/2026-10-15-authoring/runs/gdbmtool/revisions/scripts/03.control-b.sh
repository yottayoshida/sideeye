#!/bin/sh
# Control for leg b: an original record is lost. k2 is deleted through gdbmtool, so the
# database stays readable and recover.sh has nothing to repair.
# Built from the valid starting state (setup.sh) in $1; breaks leg b and no other.
set -eu
S=${1:?state directory}
"$(dirname "$0")/setup.sh" "$S"
gdbmtool -N -q "$S/db.gdbm" delete k2
