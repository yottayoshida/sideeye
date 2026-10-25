#!/bin/sh
# keep-cases.sh for one set's targets only, so the four sets sharing transcripts/explore do not move
# each other's work directories while those are still being written.
#   sh keep-cases-set.sh <explore dir> <destination outside the repository> <target> [...]
set -eu
src=$1; dst=$2; shift 2
n=0
for t in "$@"; do
    for w in "$src/$t"/work-*; do
        [ -d "$w" ] || continue
        lab=${w##*/work-}
        for c in "$w"/cases/*.json; do
            [ -f "$c" ] || continue
            cp "$c" "$src/$t/case-$lab.json"; n=$((n + 1))
        done
        mkdir -p "$dst/$t"
        mv "$w" "$dst/$t/"
    done
done
echo "cases kept: $n; work directories moved to $dst"
