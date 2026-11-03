#!/bin/sh
# Every subject, ten explorations each, in both oracle modes, with the engine at $SE/bin/sideeye.
#   SE=<dir> CTL=<dir holding ctl-race-loop, ctl-race-once, ctl-turns> OUT=<dir> sh run.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
ap="$here/../../2026-10-25-shipped-v1160/apparatus"
n=${N:-10}
for mode in no-oracle oracle; do
  for t in ctl-race-loop ctl-race-once ctl-turns etcdutl grafana gogs gqlgen; do
    docker run --rm --privileged --cgroupns=private --network none -v "$ap:/ap:ro" -v "$here:/hp:ro" \
      -v "${OUT:?}:/out" -v "${SE:?}:/se:ro" -v "${CTL:?}:/c:ro" sideeye-gh1029 sh /hp/measure.sh "$mode" "$t" "$n"
  done
done
