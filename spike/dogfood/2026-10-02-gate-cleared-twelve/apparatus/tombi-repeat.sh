#!/bin/sh
# tombi cleared the 2026-09-28 gate (preflight under supervised, 3 operations) and its first
# explore here refused multiple_threads_detected. How often: the gate's preflight twenty times and
# the explore twenty times, the same seed before each. One line per run.
SE=$(cat /install.path); d=/ap/defines/tombi-r1
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
tombi --version; "$SE" version
for i in $(seq 1 20); do
    sh "$d/seed.sh"
    "$SE" preflight --state /s/tombi/proj --operation "/opt/bin/tombi format --offline a.toml" --cwd /s/tombi/proj \
        --twice --oracle /usr/bin/strace --observe supervised > /out/preflight$i.txt 2>&1
    echo "preflight $i exit $?: $(sed -n '1p' /out/preflight$i.txt)"
done
for i in $(seq 1 20); do
    sh "$d/seed.sh"
    "$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --observe supervised \
        --work /out/work$i --json /out/explore$i.json > /out/explore$i.txt 2>&1
    echo "explore $i exit $?: $(reason /out/explore$i.json) | $(grep -o 'tid [0-9]* performed [a-z]*([^)]*) and tid [0-9]* performed [a-z]*([^)]*)' /out/explore$i.txt | head -1)"
done
