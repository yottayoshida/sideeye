#!/bin/sh
# The lines the user wrote are still in the file, whichever of its old and new forms a world holds.
cd "$SIDEEYE_STATE_DIR" || exit 1
. /ap/defines/lib/values.sh
contains /s/xdg/git/attributes '*.png binary'
contains /s/xdg/git/attributes '*.lockb binary diff=lockb'
exit $bad
