#!/bin/sh
# Leg C only: p1.diff applied to a.txt by patch(1) behind quilt's back, no .pc at all.
# quilt lists nothing applied (A, and B and D have nothing to judge), the records are
# untouched (E); p1.diff is not applied and a.txt is not pristine.
set -eu
cd "${SIDEEYE_STATE_DIR:?}"
patch -s -p1 < patches/p1.diff
