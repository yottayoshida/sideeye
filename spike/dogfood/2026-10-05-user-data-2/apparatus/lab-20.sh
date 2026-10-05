#!/bin/sh
# Plain runs: turbo's telemetry setting.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
f=$(readlink -f "$(command -v turbo)"); echo "turbo -> $f"; file -L "$f"; find / -path /proc -prune -o -name 'turbo' -type f -print 2>/dev/null | head; 
x turbo telemetry status
x turbo telemetry disable
find /s/aux -path '*turbo*' -type f -exec sh -c 'echo "== {}"; cat {}' \;
x turbo telemetry enable
find /s/aux -path '*turbo*' -type f -exec sha256sum {} \;
