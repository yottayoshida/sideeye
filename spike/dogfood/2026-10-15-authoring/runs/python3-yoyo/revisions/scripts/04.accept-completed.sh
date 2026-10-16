#!/bin/sh
# A state check.sh must accept: the operation run to completion over the valid start.
set -eu
S=${SIDEEYE_STATE_DIR:?}; D=$(cd "$(dirname "$0")" && pwd)
"$D/setup.sh" > /dev/null
cd "$S"
python3 -m yoyo apply --batch --database sqlite:///app.db migrations
