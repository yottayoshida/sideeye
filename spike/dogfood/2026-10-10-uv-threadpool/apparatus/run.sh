#!/bin/sh
# One define, end to end (#686), in a box of its own — a define's env.sh may write /etc/ld.so.preload
# (lingui's clock pin), which is global and must not ride on the next one:
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <out>:/out sideeye-uv-1010 sh /ap/run.sh <none|with> <target>
#
# none: the define without UV_THREADPOOL_SIZE, through `preflight` — the threads wall is met at the
#       recording, so preflight is enough to see it. A define the recording accepts is explored too,
#       because the wall can also stand in an explored world.
# with: the define with UV_THREADPOOL_SIZE=1 set by its env.sh AND declared in its toml's apparatus,
#       explored as 2026-10-09 follow-ups 3 explored it (the default mode, --oracle, --json).
set -u
side=${1:?usage: run.sh <none|with> <target>}; t=${2:?usage: run.sh <none|with> <target>}
d=/ap/defines/$side/$t
SE=$(cat /install.path)
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$side/$t; mkdir -p "$o"
{ "$SE" version; echo "engine path: $SE"; grep -E 'digest matches|sideeye ' /install.log; cat /versions.txt; echo "UV_THREADPOOL_SIZE=${UV_THREADPOOL_SIZE-<unset>}"; } > "$o/engine.txt"
seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "seed failed" > "$o/summary.txt"; exit 2; }; }
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or d.get("setup_error_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
explore() {
    seed
    "$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --work "$o/work-explore" --json "$o/explore.json" > "$o/explore.txt" 2>&1
    echo "explore exit $?: $(reason "$o/explore.json")" >> "$o/summary.txt"
}
: > "$o/summary.txt"
if [ "$side" = none ]; then
    seed
    "$SE" preflight --config "$d/sideeye.toml" --oracle /usr/bin/strace --work "$o/work-pre" > "$o/preflight.txt" 2>&1
    rc=$?
    echo "preflight exit $rc: $(grep -m1 -E '^(PREFLIGHT|UNKNOWN|SETUP ERROR)' "$o/preflight.txt" || echo -)" >> "$o/summary.txt"
    grep -q '^PREFLIGHT  recording accepted' "$o/preflight.txt" && explore
else
    explore
fi
cat "$o/summary.txt"
