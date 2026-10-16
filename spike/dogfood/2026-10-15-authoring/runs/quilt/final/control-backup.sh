#!/bin/sh
# Leg D only: both patches pushed by quilt, then the backup quilt keeps of a.txt
# (.pc/p1.diff/a.txt) overwritten. The list (A), the working files (B, C) and the
# records (E) are as after a clean push; a forced pop no longer restores a.txt.
set -eu
cd "${SIDEEYE_STATE_DIR:?}"
quilt push -a >/dev/null
printf 'not the original\n' > .pc/p1.diff/a.txt
