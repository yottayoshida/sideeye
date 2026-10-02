#!/bin/sh
# One target under each of the three observation modes the released v1.7.0 has, asked for by
# name — not the page's path (`run.sh` is that): the default (`wrappers`), `--observe syscalls`
# and `--observe supervised`. One explore per mode, the same seed before each; a FAIL is
# replayed twice in its own mode. One line per mode, read back from the engine's JSON.
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <out>:/out sideeye-uj170 sh /ap/modes.sh <target>
#
# The question is which walls stand in v1.7.0 and in which mode, for targets an earlier engine
# refused. A refusal here is a result, not a failure of the script; the script exits 0 unless
# the seed fails.
set -u
t=${1:?usage: modes.sh <target>}
d=/ap/defines/$t
SE=$(cat /install.path)
. /ap/env.sh   # the 2026-09-16 drivers' environment; see env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"   # what that target's own runner exported, if anything; see defines/<t>/ORIGIN.md
o=/out/$t/modes; mkdir -p "$o"
seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "$t: seed failed: $(tail -1 "$o/seed.log")"; exit 2; }; }
line() { # <json> : verdict, reason, oracle, worlds
    python3 - "$1" <<'EOF' 2>/dev/null || echo "no-json - - -"
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("verdict"), d.get("unknown_reason") or d.get("setup_error_reason") or "-",
      "oracle_verified=%s" % d.get("oracle_verified"),
      "crash_points=%s" % (d.get("crash_points") if d.get("crash_points") is not None else "-"))
EOF
}

{ "$SE" version; echo "engine path: $SE"; grep -E 'digest matches|sideeye ' /install.log; } > "$o/engine.txt"
op=$(sed -n 's/^operation *= *"\(.*\)"$/\1/p' "$d/sideeye.toml")
first=${op%% *}
bin=$(command -v "$first" 2>/dev/null || echo "$first")
echo "$t: operation: $op"
echo "$t: image: $bin: $(file -bL "$bin" 2>/dev/null | cut -c1-110)"

for m in wrappers syscalls supervised; do
    seed
    "$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace --observe "$m" \
        --work "$o/work-$m" --json "$o/$m.json" > "$o/$m.txt" 2>&1
    rc=$?
    echo "$t: $m: exit $rc: $(line "$o/$m.json")" | tee -a "$o/summary.txt"
    if [ "$rc" = 1 ]; then
        case_json=$(ls "$o/work-$m/cases/"*.json 2>/dev/null | head -1)
        if [ -n "$case_json" ]; then
            for i in 1 2; do
                seed
                "$SE" replay "$case_json" --oracle /usr/bin/strace --observe "$m" --work "$o/work-$m-replay$i" \
                    --json "$o/$m.replay$i.json" > "$o/$m.replay$i.txt" 2>&1
                echo "$t: $m: replay $i exit $?: $(line "$o/$m.replay$i.json")" | tee -a "$o/summary.txt"
            done
            "$SE" evidence "$case_json" > "$o/$m.evidence.md" 2> "$o/$m.evidence.err"
        else
            echo "$t: $m: FAIL with no case under work-$m/cases" | tee -a "$o/summary.txt"
        fi
    fi
done
exit 0
