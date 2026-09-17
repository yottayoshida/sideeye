#!/bin/sh
# The recovery checker paired with recover-key.sh (#606): the key the recovery left loads.
set -u
: "${TOY:?check-recovered-key.sh needs TOY to point at the binary under test}"
s=${SIDEEYE_STATE_DIR:?}
TOY_STATE="$s" "$TOY" load-key >/dev/null 2>&1 || { echo "the recovered key does not load" >&2; exit 1; }
exit 0
