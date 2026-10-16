#!/bin/sh
# Leg B only: both patches pushed by quilt, then b.txt put back to its pristine
# bytes by hand. quilt still lists both as applied (A), nothing is unapplied (C),
# .pc/p2.diff/b.txt still holds the original so a forced pop restores it (D), the
# records are untouched (E); p2.diff is listed as applied and b.txt is not its result.
set -eu
cd "${SIDEEYE_STATE_DIR:?}"
quilt push -a >/dev/null
cp .pc/p2.diff/b.txt b.txt
