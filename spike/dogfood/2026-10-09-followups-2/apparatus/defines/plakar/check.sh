#!/bin/sh
# states/, packfiles/ and locks/ are scratch (content-addressed names that differ between two runs);
# this judges the repository through plakar itself: it lists the old two snapshots or the one kept,
# and checks clean.
. /ap/defines/plakar/env.sh
n=$(plakar at "$SIDEEYE_STATE_DIR" ls 2>/tmp/pl.err | grep -c '/s/plakar-in/data') || true
case "$n" in 1|2) ;; *) echo "plakar lists $n snapshots: $(head -1 /tmp/pl.err | cut -c1-120)"; exit 1 ;; esac
plakar at "$SIDEEYE_STATE_DIR" check > /tmp/pl-check.txt 2>&1 || { echo "plakar check fails: $(tail -1 /tmp/pl-check.txt | cut -c1-120)"; exit 1; }
exit 0
