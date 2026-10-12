#!/bin/sh
# Keep what 2026-10-02 committed of an explore's work directory — the case file a replay reads,
# as transcripts/explore/<t>/case-<label>.json — and move the rest out of the tree. A work
# directory holds the state snapshots: up to 30 MB for doing, and talosctl's carry the client keys
# its seed generated in the box.
#
#   sh keep-cases.sh <explore dir> <destination outside the repository>
set -eu
src=$1; dst=$2
n=0
for w in "$src"/*/work-*; do
    [ -d "$w" ] || continue
    t=$(basename "$(dirname "$w")"); lab=${w##*/work-}
    for c in "$w"/cases/*.json; do
        [ -f "$c" ] || continue
        cp "$c" "$src/$t/case-$lab.json"; n=$((n + 1))
    done
    mkdir -p "$dst/$t"
    mv "$w" "$dst/$t/"
done
echo "cases kept: $n; work directories moved to $dst"
