#!/bin/sh
# One target, the page's path, on the build under test (#685):
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <zig-out>:/se:ro -v <out>:/out sideeye-sp685 sh /ap/run.sh <target>
#
# `explore --config` with `--oracle /usr/bin/strace` and `--json`, as docs/ci-quickstart.md writes it,
# in the default mode. Then the next step is followed once, by what it names: a step naming
# `--observe supervised` runs the explore again with that flag, one naming `--observe syscalls` with
# that one. Nothing else is followed. The box is privileged with its own cgroup namespace because
# `--observe supervised` needs a cgroup v2 the engine can create cgroups in (ADR 0089).
set -u
t=${1:?usage: run.sh <target>}
d=/ap/defines/$t
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
. /ap/env.sh
[ -f "$d/env.sh" ] && . "$d/env.sh"
o=/out/$t; mkdir -p "$o"
{ "$SE" version; cat /versions.txt; } > "$o/engine.txt" 2>&1

explore() { # <label> [extra flags]
    label=$1; shift
    sh "$d/seed.sh" > "$o/seed-$label.log" 2>&1 || { echo "$t $label: seed failed" >&2; return 1; }
    rm -rf "/tmp/work-$label"
    "$SE" explore --config "$d/sideeye.toml" --shim "$SHIM" --oracle /usr/bin/strace \
        --work "/tmp/work-$label" --json "$o/$label.json" "$@" > "$o/$label.txt" 2>&1
    echo "$?" > "$o/$label.rc"
}
step_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("next_step") or "")' "$1" 2>/dev/null; }

explore default
step=$(step_of "$o/default.json")
case "$step" in
    *"--observe supervised"*) explore followed --observe supervised ;;
    *"--observe syscalls"*)   explore followed --observe syscalls ;;
esac
python3 - "$o" "$t" <<'PY'
import json, os, sys
o, t = sys.argv[1], sys.argv[2]
for label in ("default", "followed"):
    p = os.path.join(o, label + ".json")
    if not os.path.exists(p):
        continue
    d = json.load(open(p))
    e = d.get("earliest") or {}
    print(f"{t} {label}: {d.get('verdict')} {d.get('unknown_reason') or ''} "
          f"explored={d.get('explored')} crash_points={d.get('crash_points')} earliest={e.get('crash_point')} "
          f"| next: {(d.get('next_step') or '')[:120]}")
PY
