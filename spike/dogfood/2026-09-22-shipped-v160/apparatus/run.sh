#!/bin/sh
# One slate target, end to end, with the page's command (2026-09-22 shipped-v160 run).
#
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro -v <out>:/out \
#       sideeye-sv sh /ap/run.sh <target>
#
# explore is `docs/ci-quickstart.md`'s command — `--config`, `--oracle /usr/bin/strace`,
# `--json` — plus `--work` on the mounted /out, so the case and the evidence bundle outlive the
# container (the verdict-chain run's work directory died with its box, and neither replay nor
# `sideeye evidence` ever ran). No `--observe`: the default mode, as the page runs it.
#
#   FAIL     -> `sideeye replay` twice (same --oracle, same --observe) and `sideeye evidence`
#   UNKNOWN  -> if the next step names --observe syscalls, the explore is run once more with it,
#               and a FAIL there gets the same replay and evidence. Followed once, no more.
#   PASS     -> nothing more: evidence exists only for a FAIL.
#
# The seed runs before every engine invocation: replay restores the state the case recorded,
# but a define's cwd and anything outside --state are the seed's to rebuild.
set -u
t=${1:?usage: run.sh <target>}
d=/ap/defines/$t
SE=$(cat /install.path)
o=/out/$t; mkdir -p "$o"
seed() { sh "$d/seed.sh" > "$o/seed.log" 2>&1 || { echo "seed failed" >&2; exit 2; }; }

{ "$SE" version; echo "engine path: $SE"; echo "installer stdout: $(cat /install.path)"; grep -E 'digest matches|sideeye ' /install.log; } > "$o/engine.txt"

explore() { # <label> [extra flags]
    label=$1; shift
    seed
    "$SE" explore --config "$d/sideeye.toml" --oracle /usr/bin/strace "$@" \
        --work "$o/work-$label" --json "$o/$label.json" > "$o/$label.txt" 2>&1
    echo $?
}
reason() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$1" 2>/dev/null || echo "none -"; }
next_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("next_step") or "")' "$1" 2>/dev/null; }

confirm() { # <label> [extra flags]  — replay twice, then evidence
    label=$1; shift
    case_json=$(ls "$o/work-$label/cases/"*.json 2>/dev/null | head -1)
    [ -n "$case_json" ] || { echo "no case under $o/work-$label/cases" > "$o/$label.replay.txt"; return; }
    for i in 1 2; do
        seed
        "$SE" replay "$case_json" --oracle /usr/bin/strace "$@" --work "$o/work-$label-replay$i" \
            --json "$o/$label.replay$i.json" > "$o/$label.replay$i.txt" 2>&1
        echo "replay $i exit $?: $(reason "$o/$label.replay$i.json")" >> "$o/$label.replay.txt"
    done
    "$SE" evidence "$case_json" > "$o/$label.evidence.md" 2> "$o/$label.evidence.err"
    echo "evidence exit $?" >> "$o/$label.replay.txt"
}

rc=$(explore explore)
echo "explore exit $rc: $(reason "$o/explore.json")" | tee "$o/summary.txt"
case "$rc" in
    1) confirm explore ;;
    2)
        n=$(next_of "$o/explore.json")
        echo "next_step: $n" >> "$o/summary.txt"
        case "$n" in
            *"--observe syscalls"*)
                rc2=$(explore syscalls --observe syscalls)
                echo "explore --observe syscalls exit $rc2: $(reason "$o/syscalls.json")" | tee -a "$o/summary.txt"
                [ "$rc2" = 1 ] && confirm syscalls --observe syscalls ;;
        esac ;;
esac
cat "$o/summary.txt"; [ -f "$o/explore.replay.txt" ] && cat "$o/explore.replay.txt"; [ -f "$o/syscalls.replay.txt" ] && cat "$o/syscalls.replay.txt"
exit 0
