#!/bin/sh
# In the box: one target under one mode, with the released v1.17.0 mounted at /se.
#   run.sh <name> <define> <mode>
# The define's record is mounted at /ap, as its own runner mounted it, so the paths its
# toml names (/ap/defines/<t>/check.sh) resolve unchanged.
set -u
t=$1; def=$2; mode=$3
d=/ap/defines/$def
SE=/se/sideeye
[ -f /ap/env.sh ] && . /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
"$SE" version > "$o/engine.txt" 2>&1
uname -m >> "$o/engine.txt"
sh "$d/seed.sh" > "$o/seed-$mode.log" 2>&1 || { echo "$t $mode: seed failed"; exit 2; }
"$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --observe "$mode" \
    --work "$o/work-$mode" --json "$o/$mode.json" > "$o/$mode.txt" 2>&1
rc=$?
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sys.argv[2], sys.argv[3], "exit", sys.argv[4], d.get("verdict"), d.get("unknown_reason") or "-", "explored", d.get("explored"), "crash_points", d.get("crash_points"))' "$o/$mode.json" "$t" "$mode" "$rc" 2>/dev/null || echo "$t $mode exit $rc (no JSON)"
