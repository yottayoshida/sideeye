#!/bin/sh
# From the host: each target in its own box, the captures under ../transcripts/raw-v2 (not committed:
# arm 2 carries every byte written), the judgements beside them, read here: the reader imports
# 2026-10-10's order.py, which the box does not mount.
#   sh run.sh <N> <target ...>
set -u
here="$(cd "$(dirname "$0")" && pwd)"
n=$1; shift
mkdir -p "$here/../transcripts/raw-v2" "$here/../transcripts/v2"
for t in "$@"; do
  docker run --rm --network none -v "$here/../../2026-10-25-shipped-v1160/apparatus:/ap:ro" -v "$here:/hp:ro" \
    -v "$here/../transcripts/raw-v2:/out" sideeye-gh1029 sh /hp/measure.sh "$t" "$n"
  r="$here/../transcripts/raw-v2/$t"
  eval "$(grep -E '^(state|scratch)=' "$r/define.txt" | sed 's/^/def_/')"
  python3 -I "$here/handoff.py" judge "$def_state" "$def_scratch" "$r/arm1" "$r/arm2" | tee "$here/../transcripts/v2/$t.judge.json"
done
