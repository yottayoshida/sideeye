#!/bin/sh
# setup.sh <git>
set -eu
git=$1
r=$SIDEEYE_STATE_DIR/repo
mkdir -p "$r"
export GIT_AUTHOR_NAME=sideeye GIT_AUTHOR_EMAIL=sideeye@example.invalid
export GIT_COMMITTER_NAME=sideeye GIT_COMMITTER_EMAIL=sideeye@example.invalid
export GIT_CONFIG_NOSYSTEM=1 HOME=$SIDEEYE_STATE_DIR/.home
mkdir -p "$HOME"
"$git" -C "$r" init -q -b main
"$git" -C "$r" config gc.auto 0
"$git" -C "$r" config maintenance.auto false
i=1
while [ "$i" -le 12 ]; do
    printf 'file %d\nline two of %d\n' "$i" "$i" > "$r/f$i.txt"
    "$git" -C "$r" add "f$i.txt"
    GIT_AUTHOR_DATE="2026-01-01T00:00:${i}Z" GIT_COMMITTER_DATE="2026-01-01T00:00:${i}Z" \
        "$git" -C "$r" commit -q -m "commit $i"
    i=$((i + 1))
done
