#!/bin/sh
# Host side: each target explored in a box of its own (run.sh, the 2026-10-02 copy), so a pinned
# define's /etc/ld.so.preload never rides on the next one.
#   sh apparatus/explore.sh <name> [...]
# Copied from 2026-10-12 shipped-v1120 with one change: the sha256 of SELECTION.md, and one over every
# file under defines/, are printed and written into each target's output first, so every explore
# shows it ran against the committed slate and the committed checkers (#861).
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/explore"
sel=$(shasum -a 256 "$run/SELECTION.md" | cut -d' ' -f1) || exit 2
defs=$(cd "$here" && find defines -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
for t in "$@"; do
  echo "=== $t $(date -u +%FT%TZ) SELECTION.md sha256 $sel defines sha256 $defs"
  mkdir -p "$run/transcripts/explore/$t" && printf 'SELECTION.md %s\ndefines %s\n' "$sel" "$defs" > "$run/transcripts/explore/$t/selection.sha256"
  docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/explore":/out sideeye-m1014 sh /ap/run.sh "$t"
done
