#!/bin/sh
# The split checker for the poetry-shrunk regression (#231, ADR 0020): the
# declared invariant covers ONLY primary.txt — old content or new content,
# never anything else. derived.txt is deliberately outside the declaration,
# the way poetry's lock (healable through the tool's own chain) was outside
# the wound: its mid-write world must be an L0-only observation the checker
# stays green on, so the overall earliest and the claim exhibit diverge.
#
# Runs after a restart, in a fresh process. Exit 0 = invariant holds. The
# falsification gate is satisfied because it junk-overwrites every file,
# primary.txt included, and junk is neither the old nor the new content.
#
# Environment:
#   TOY_STATE  state directory
set -u

: "${TOY_STATE:?check-split.sh needs TOY_STATE}"

p="$TOY_STATE/primary.txt"
[ -f "$p" ] || { echo "primary.txt is missing" >&2; exit 1; }
content=$(cat "$p")
case "$content" in
    "primary-old"|"primary-new") exit 0 ;;
    *)
        echo "primary.txt holds neither the old nor the new content" >&2
        exit 1
        ;;
esac
