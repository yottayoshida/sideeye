#!/bin/sh
# Round 2: probe-supervised.sh's FAIL replayed twice under --observe supervised, as run.sh's confirm
# replays a FAIL on the page's path. The seed runs before each replay.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro \
#     -v <transcripts/explore>:/out sideeye-fu5-1009 sh /ap/replay-supervised.sh <target>
set -u
t=${1:?usage: replay-supervised.sh <target>}
d=/ap/defines/$t
SE=$(cat /install.path)
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t
case_json=$(ls "$o/work-probe-supervised/cases/"*.json 2>/dev/null | head -1)
[ -n "$case_json" ] || { echo "no case under $o/work-probe-supervised/cases"; exit 2; }
for i in 1 2; do
    sh "$d/seed.sh" > "$o/seed-replay.log" 2>&1 || { echo "seed failed"; exit 2; }
    "$SE" replay "$case_json" --oracle /usr/bin/strace --observe supervised --work "$o/work-probe-replay$i" \
        --json "$o/probe-supervised.replay$i.json" > "$o/probe-supervised.replay$i.txt" 2>&1
    echo "replay $i exit $?: $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$o/probe-supervised.replay$i.json" 2>/dev/null)"
done | tee "$o/probe-supervised.replay.txt"
