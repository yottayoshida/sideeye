#!/bin/sh
# Runs every accept-*.sh and control-*.sh in a fresh state directory of its own, then check.sh
# over what it built. Expected: each accept-* check exit 0; each control-* check exit 1 with
# only its own leg red. The output is the transcript (controls.txt).
set -u
D=$(cd "$(dirname "$0")" && pwd)
for f in "$D"/accept-*.sh "$D"/control-*.sh; do
    n=$(basename "$f" .sh)
    SIDEEYE_STATE_DIR=$(mktemp -d /tmp/yoyo-ctl-$n.XXXXXX); export SIDEEYE_STATE_DIR
    echo "== $n"
    "$f" > /tmp/yoyo-ctl-build.txt 2>&1; echo "   build exit: $?"
    sed 's/^/   build: /' /tmp/yoyo-ctl-build.txt
    "$D/check.sh" > /tmp/yoyo-ctl-check.txt 2>&1; rc=$?
    sed 's/^/   check: /' /tmp/yoyo-ctl-check.txt
    echo "   check exit: $rc"
    rm -rf "$SIDEEYE_STATE_DIR"
done
