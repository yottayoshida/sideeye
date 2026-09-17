#!/bin/sh
# A recovery for the toy's key rotation (#606, ADR 0072): the acceptance suite's stand-in for a
# tool that finishes an interrupted commit on its next start.
#
# It acts only on the crash-only shape — the new key written aside as key.json.tmp, the old
# key.json gone — and does nothing to any other state, which is what a real recovery does on a
# clean start: the recovery gate runs it on the completed state too, and its checker must accept
# what it leaves there.
set -u
s=${SIDEEYE_STATE_DIR:?recover-key.sh runs under sideeye, which sets SIDEEYE_STATE_DIR}
if [ ! -e "$s/key.json" ] && [ -e "$s/key.json.tmp" ]; then
    mv "$s/key.json.tmp" "$s/key.json"
fi
exit 0
