#!/bin/sh
# Leg E only: a line added to the description of p2.diff, above its diff. The patch
# still applies the same change, nothing is applied (A, B, C, D hold); the record
# is no longer the bytes the setup wrote.
set -eu
cd "${SIDEEYE_STATE_DIR:?}"
{ printf 'Reviewed.\n'; cat patches/p2.diff; } > p2.new
mv p2.new patches/p2.diff
