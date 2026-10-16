#!/bin/sh
# Control for leg c: a new key holds a value the session never stored. k4 is stored
# as "v4x" (k4 alone, so the present new keys are still a prefix).
# Built from the valid starting state (setup.sh) in $1; breaks leg c and no other.
set -eu
S=${1:?state directory}
"$(dirname "$0")/setup.sh" "$S"
gdbmtool -N -q "$S/db.gdbm" store k4 v4x
