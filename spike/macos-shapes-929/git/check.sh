#!/bin/sh
# check.sh <git>
set -u
git=$1
r=$SIDEEYE_STATE_DIR/repo
export HOME=$SIDEEYE_STATE_DIR/.home GIT_CONFIG_NOSYSTEM=1
"$git" -C "$r" fsck --full >/dev/null 2>&1 || { echo "git fsck --full fails" >&2; exit 1; }
n=$("$git" -C "$r" rev-list --count HEAD 2>/dev/null) || { echo "no HEAD" >&2; exit 1; }
[ "$n" = 12 ] || { echo "$n commits, wanted 12" >&2; exit 1; }
