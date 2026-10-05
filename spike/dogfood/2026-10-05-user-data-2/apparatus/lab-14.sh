#!/bin/sh
# Plain runs: xmake's global configuration.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
export XMAKE_ROOT=y XMAKE_GLOBALDIR=/lab/xm
x xmake g --network=private
sum /lab/xm; find /lab/xm -name '*.conf' -exec sh -c 'echo "== {}"; cat {}' \;
x xmake g --theme=plain
sum /lab/xm; find /lab/xm -name '*.conf' -exec sh -c 'echo "== {}"; cat {}' \;
