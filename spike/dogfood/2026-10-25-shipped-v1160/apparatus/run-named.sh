#!/bin/sh
# One target explored under a mode the page's next step did not name (2026-10-09 follow-ups' modes.sh,
# reduced to one mode): run.sh's explore, replay twice and evidence, with the flags given.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro -v <out>:/out \
#       sideeye-sv1025-s<N> sh /ap/run-named.sh <target> <label> [flags ...]
set -u
t=${1:?}; label=${2:?}; shift 2
d=/ap/defines/$t
SE=$(cat /install.path)
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "seed failed" >&2; exit 2; }; }
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
{ "$SE" version; echo "engine path: $SE"; grep -E 'digest matches|sideeye ' /install.log; } > "$o/engine.txt"
seed
"$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace "$@" --work "$o/work-$label" --json "$o/$label.json" > "$o/$label.txt" 2>&1
rc=$?
echo "explore $label ($*) exit $rc: $(reason "$o/$label.json")" | tee "$o/summary-$label.txt"
if [ "$rc" = 1 ]; then
    case_json=$(ls "$o/work-$label/cases/"*.json 2>/dev/null | head -1)
    if [ -n "$case_json" ]; then
        for i in 1 2; do
            seed
            "$SE" replay "$case_json" --oracle /usr/bin/strace "$@" --work "$o/work-$label-replay$i" \
                --json "$o/$label.replay$i.json" > "$o/$label.replay$i.txt" 2>&1
            echo "replay $i exit $?: $(reason "$o/$label.replay$i.json")" >> "$o/$label.replay.txt"
        done
        "$SE" evidence "$case_json" > "$o/$label.evidence.md" 2> "$o/$label.evidence.err"
        echo "evidence exit $?" >> "$o/$label.replay.txt"
        cat "$o/$label.replay.txt"
    fi
fi
exit 0
