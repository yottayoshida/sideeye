#!/bin/sh
# The valid starting state: k1 k2 k3, nothing else.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
S=${SIDEEYE_STATE_DIR:?}; DB=$S/db.gdbm
"$HERE/setup.sh"
