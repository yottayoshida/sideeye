#!/bin/sh
# Control for leg e: a later store survives while an earlier one is missing: k5=v5
# is present (with its right value) but k4 is not.
# Built from the valid starting state (setup.sh) in $1; breaks leg e and no other.
set -eu
S=${1:?state directory}
"$(dirname "$0")/setup.sh" "$S"
gdbmtool -N -q "$S/db.gdbm" store k5 v5
