#!/bin/sh
# One target explored in a mode its refusal did not name (run.sh follows only the mode a next step
# names), then, on a FAIL, replayed twice in that mode and its evidence written — run.sh's confirm.
#   docker run ... sh /ap/run-mode.sh <target> <label> [extra flags, e.g. --observe supervised]
set -u
t=${1:?}; label=${2:?}; shift 2
d=/ap/defines/$t; SE=$(cat /install.path)
. /ap/env.sh; [ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "seed failed" >&2; exit 2; }; }
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
{ "$SE" version; grep -E 'digest matches|sideeye ' /install.log; } > "$o/engine.txt"
seed
"$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace "$@" --work "$o/work-$label" --json "$o/$label.json" > "$o/$label.txt" 2>&1
rc=$?
echo "explore $* exit $rc: $(reason "$o/$label.json")" | tee "$o/summary-$label.txt"
if [ "$rc" = 1 ]; then
    for c in "$o/work-$label"/cases/*.json; do
        n=$(basename "$c" .json)
        for i in 1 2; do
            seed
            "$SE" replay "$c" --oracle /usr/bin/strace "$@" --work "$o/work-$label-$n-replay$i" --json "$o/$label.$n.replay$i.json" > "$o/$label.$n.replay$i.txt" 2>&1
            echo "case $n replay $i exit $?: $(reason "$o/$label.$n.replay$i.json")" | tee -a "$o/summary-$label.txt"
        done
        "$SE" evidence "$c" > "$o/$label.$n.evidence.md" 2> "$o/$label.$n.evidence.err"
        echo "case $n evidence exit $?" | tee -a "$o/summary-$label.txt"
    done
fi
