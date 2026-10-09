#!/bin/sh
# Host side: each target explored in a box of its own (run.sh, the 2026-10-02 copy), so a pinned
# define's /etc/ld.so.preload never rides on the next one.
#   sh apparatus/explore.sh <name> [...]
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/explore"
for t in "$@"; do
  echo "=== $t $(date -u +%FT%TZ)"
  docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/explore":/out sideeye-fu4-1009 sh /ap/run.sh "$t"
done
