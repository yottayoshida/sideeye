#!/bin/sh
# Leg A only: p2.diff applied by quilt alone, p1.diff not, the series unchanged.
# b.txt is p2's result and .pc/p2.diff holds its backup (B and D hold), a.txt is
# pristine with p1 unapplied (C holds), the series bytes are restored (E holds);
# what quilt lists as applied, [p2.diff], is not a prefix of [p1.diff p2.diff].
set -eu
cd "${SIDEEYE_STATE_DIR:?}"
cp patches/series series.keep
echo p2.diff > patches/series
quilt push >/dev/null
cat series.keep > patches/series
rm series.keep
