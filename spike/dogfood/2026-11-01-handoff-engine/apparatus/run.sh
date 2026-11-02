#!/bin/sh
# Every target and control, ten recording runs each, under the probe engine and then the shipped one.
#   SE=<dir holding bin/sideeye, bin/sideeye-testhandoffprobe, bin/trace-ops> OUT=<dir> sh run.sh
# The engine is built with: zig build -Dtarget=aarch64-linux-gnu -Dtest-handoff-probe=true -Dtrace-ops=true
set -u
here="$(cd "$(dirname "$0")" && pwd)"
ap="$here/../../2026-10-25-shipped-v1160/apparatus"
n=${N:-10}
for arm in probe plain; do
  for t in ctl-race ctl-condvar dolt grafana gogs gqlgen juicefs navidrome-restore etcdutl vmrestore; do
    docker run --rm --privileged --cgroupns=private --network none -v "$ap:/ap:ro" -v "$here:/hp:ro" \
      -v "${OUT:?}:/out" -v "${SE:?}:/se:ro" sideeye-gh1029 sh /hp/measure.sh "$arm" "$t" "$n"
  done
done
