#!/bin/sh
# Host side: each define on each version in a box of its own.
#   sh apparatus/explore.sh <define> [...]      (both versions)
#   V="2.34.2" sh apparatus/explore.sh <define> (one)
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/explore"
for t in "$@"; do for v in ${V:-2.32.4 2.34.2}; do
  echo "=== $t $v $(date -u +%FT%TZ)"
  docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/explore":/out sideeye-dx1010 sh /ap/run.sh "$t" "$v"
done; done
