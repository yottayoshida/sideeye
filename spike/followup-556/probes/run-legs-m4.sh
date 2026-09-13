#!/bin/sh
set -u
echo "######## unit tests, mut556d"; /t/syscalls-test-mut556d 2>&1 | grep -v "\.\.\.OK$" | tail -6
SIDEEYE=/b/m4/sideeye SHIM=/b/m4/libsideeye_shim.so OUT=/t/out
echo "==================== m4   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
fails=0
. /t/legs556.sh
echo "fails=$fails"
echo "---- the toy's own exit under the M4 shim, preloaded directly (no engine)"
mkdir -p /tmp/m4s && TOY_STATE=/tmp/m4s LD_PRELOAD=$SHIM SIDEEYE_STATE_DIR=/tmp/m4s SIDEEYE_TRACE_PATH=/tmp/m4s.trace SIDEEYE_OBSERVE=syscalls /t/out/toy-raw samask; echo "toy-raw samask rc=$?"
