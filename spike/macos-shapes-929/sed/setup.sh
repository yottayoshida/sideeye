#!/bin/sh
set -eu
printf 'name=demo\nport=8080\nhost=localhost\nmode=old\nretries=3\ntimeout=30\nlog=info\nowner=ops\n' > "$SIDEEYE_STATE_DIR/app.conf"
