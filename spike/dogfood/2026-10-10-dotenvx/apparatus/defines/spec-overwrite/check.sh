#!/bin/sh
# The lines the user wrote are still in the file, whichever of its old and new forms a world holds.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
nonempty_with Envfile DB_PASSWORD
exit $bad
