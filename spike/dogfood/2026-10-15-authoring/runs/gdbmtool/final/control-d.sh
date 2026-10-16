#!/bin/sh
# Control for leg d: a key the session never stored appears: k7=v7.
# Built from the valid starting state (setup.sh) in $1; breaks leg d and no other.
set -eu
S=${1:?state directory}
"$(dirname "$0")/setup.sh" "$S"
gdbmtool -N -q "$S/db.gdbm" store k7 v7
