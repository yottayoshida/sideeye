#!/bin/sh
# 2026-10-09 follow-ups 3's keep-cases.sh, one level deeper: this run's explores sit under
# transcripts/explore/<define>/<version>/. The case file a replay reads is kept as
# case-<label>.json beside the report; the rest of each work directory (the state snapshots, the
# traces) moves out of the tree.
#
#   sh keep-cases.sh <explore dir> <destination outside the repository>
set -eu
src=$1; dst=$2
n=0
for w in "$src"/*/*/work-*; do
    [ -d "$w" ] || continue
    v=$(basename "$(dirname "$w")"); t=$(basename "$(dirname "$(dirname "$w")")"); lab=${w##*/work-}
    for c in "$w"/cases/*.json; do
        [ -f "$c" ] || continue
        cp "$c" "$src/$t/$v/case-$lab.json"; n=$((n + 1))
    done
    mkdir -p "$dst/$t/$v"
    mv "$w" "$dst/$t/$v/"
done
echo "cases kept: $n; work directories moved to $dst"
