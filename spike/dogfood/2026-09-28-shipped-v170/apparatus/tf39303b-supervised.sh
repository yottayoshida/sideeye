#!/bin/sh
# tf39303-supervised.sh with the define named by its first argument (default: terraform), for the
# 2026-10-02 re-measurement of hashicorp/terraform#39303 after it was rewritten. Explored with
# --observe supervised, then replayed twice. Same seed before every engine invocation.
set -u
d=/ap/defines/${1:-terraform}; SE=$(cat /install.path); o=/out
seed() { sh "$d/seed.sh" > /dev/null 2>&1 || { echo "seed failed"; exit 2; }; }
terraform version | head -1; "$SE" version
seed
echo "seed: $(wc -c < /s/terraform/proj/main.tf) bytes"
"$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --observe supervised \
    --work "$o/work" --json "$o/explore.json" > "$o/explore.txt" 2>&1
echo "explore exit $?"
python3 -c 'import json; d=json.load(open("/out/explore.json")); print(d.get("verdict"), d.get("unknown_reason") or "-", "crash points:", d.get("crash_points") or d.get("points_explored") or "?")'
case_json=$(ls "$o/work/cases/"*.json 2>/dev/null | head -1)
[ -n "$case_json" ] || { echo "no case"; exit 0; }
for i in 1 2; do
    seed
    "$SE" replay "$case_json" --oracle /usr/bin/strace --observe supervised --work "$o/replay$i" \
        --json "$o/replay$i.json" > "$o/replay$i.txt" 2>&1
    echo "replay $i exit $?"
done
