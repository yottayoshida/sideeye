#!/bin/sh
# Plain runs: firebase-tools' local settings.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
x firebase experiments:list
x firebase experiments:enable webframeworks
sum /s/aux/home/.config/configstore; cat /s/aux/home/.config/configstore/firebase-tools.json 2>/dev/null | head -20
x firebase experiments:disable webframeworks
sum /s/aux/home/.config/configstore
