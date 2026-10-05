#!/bin/sh
# Host side: plain.sh over every define, a pinned one (its env.sh writes /etc/ld.so.preload) in a box
# of its own so the preload never rides on the next.
#   sh apparatus/plain-all.sh > transcripts/plain-runs.txt
here="$(cd "$(dirname "$0")" && pwd)"
unpinned=""; pinned=""
for t in $(ls "$here/defines"); do
  if grep -q ld.so.preload "$here/defines/$t/env.sh" 2>/dev/null; then pinned="$pinned $t"; else unpinned="$unpinned $t"; fi
done
docker run --rm --network none -v "$here":/ap:ro sideeye-ud1005 sh /ap/plain.sh $unpinned
for t in $pinned; do docker run --rm --network none -v "$here":/ap:ro sideeye-ud1005 sh /ap/plain.sh $t; done
