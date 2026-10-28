#!/bin/sh
set -u
f=$SIDEEYE_STATE_DIR/prefs.plist
/usr/bin/plutil -lint -s "$f" || { echo "prefs.plist is not a valid property list" >&2; exit 1; }
v=$(/usr/bin/plutil -extract name raw "$f" 2>/dev/null) || { echo "prefs.plist has no name" >&2; exit 1; }
[ "$v" = sideeye-shapes ] || { echo "name is $v" >&2; exit 1; }
