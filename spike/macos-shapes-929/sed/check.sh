#!/bin/sh
set -u
f=$SIDEEYE_STATE_DIR/app.conf
old='name=demo
port=8080
host=localhost
mode=old
retries=3
timeout=30
log=info
owner=ops'
new=$(printf '%s\n' "$old" | sed 's/^mode=old$/mode=new/')
got=$(cat "$f" 2>/dev/null) || { echo "app.conf is missing" >&2; exit 1; }
[ "$got" = "$old" ] || [ "$got" = "$new" ] || { echo "app.conf is neither the old content nor the new" >&2; exit 1; }
