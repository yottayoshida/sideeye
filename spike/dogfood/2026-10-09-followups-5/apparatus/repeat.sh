#!/bin/sh
# Follow-ups 5: one define explored N times under --observe supervised, each in a box of its own, the
# verdict of each run tallied — 2026-10-02's tombi-repeat.sh measured how often 1.5.6 met the threads wall.
#   sh apparatus/repeat.sh <define> <n>
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
t=$1; n=$2; out="$run/transcripts/repeat/$t"; mkdir -p "$out"
i=1; while [ "$i" -le "$n" ]; do
  docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$out":/out sideeye-fu5-1009 sh -c '
    SE=$(cat /install.path); sh /ap/defines/'"$t"'/seed.sh > /dev/null 2>&1
    "$SE" explore --config /ap/defines/'"$t"'/sideeye.toml --oracle /usr/bin/strace --observe supervised \
      --work /tmp/w --json /out/run-'"$i"'.json > /out/run-'"$i"'.txt 2>&1
    python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d[\"verdict\"], d.get(\"unknown_reason\") or \"-\", d[\"violations\"], \"/\", d[\"explored\"])" /out/run-'"$i"'.json'
  i=$((i + 1))
done
