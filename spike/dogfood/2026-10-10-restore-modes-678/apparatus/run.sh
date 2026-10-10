#!/bin/sh
# One target on the build under test (#678):
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <zig-out>:/se:ro -v <out>:/out sideeye-rm678 sh /ap/run.sh <target>
#
# The 2026-10-03 run met these at `preflight --twice` (recording_run_failed: the second run started
# from 0644 where the first had the setup's 0755 or 0600), so that is run first, as that run ran it.
# Then `explore --config` with `--oracle /usr/bin/strace` and `--json`, as docs/ci-quickstart.md
# writes it, in the default mode, and its next step followed once when it names a mode.
set -u
t=${1:?usage: run.sh <target>}
d=/ap/defines/$t
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
. /ap/env.sh
o=/out/$t; mkdir -p "$o"
{ "$SE" version; echo "engine sha256: $(sha256sum "$SE" | cut -c1-64)"; cat /versions.txt; } > "$o/engine.txt" 2>&1
conf() { python3 -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb")); print(d[sys.argv[2]][sys.argv[3]])' "$d/sideeye.toml" "$1" "$2"; }

twice() { # <label> [extra flags] — a static image is asked again under supervised, as 2026-10-03 did
    label=$1; shift
    sh "$d/seed.sh" > "$o/seed-$label.log" 2>&1 || { echo "$t: seed failed" >&2; exit 1; }
    ls -l "$(conf world state)" > "$o/$label-before.ls" 2>&1
    "$SE" preflight --state "$(conf world state)" --operation "$(conf define operation)" --cwd "$(conf define cwd)" \
        --twice --shim "$SHIM" --oracle /usr/bin/strace "$@" > "$o/$label.txt" 2>&1
    echo "$?" > "$o/$label.rc"
    ls -l "$(conf world state)" > "$o/$label-after.ls" 2>&1
}
twice twice
grep -q '^next .*--observe supervised' "$o/twice.txt" && twice twice-supervised --observe supervised

explore() { # <label> [extra flags]
    label=$1; shift
    sh "$d/seed.sh" > "$o/seed-$label.log" 2>&1 || { echo "$t $label: seed failed" >&2; return 1; }
    rm -rf "/tmp/work-$label"
    "$SE" explore --config "$d/sideeye.toml" --shim "$SHIM" --oracle /usr/bin/strace \
        --work "/tmp/work-$label" --json "$o/$label.json" "$@" > "$o/$label.txt" 2>&1
    echo "$?" > "$o/$label.rc"
}
explore default
step=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("next_step") or "")' "$o/default.json" 2>/dev/null)
case "$step" in
    *"--observe supervised"*) explore followed --observe supervised ;;
    *"--observe syscalls"*)   explore followed --observe syscalls ;;
esac
python3 - "$o" "$t" <<'PY'
import json, os, sys
o, t = sys.argv[1], sys.argv[2]
for label in ("twice", "twice-supervised"):
    p = os.path.join(o, label + ".txt")
    if not os.path.exists(p):
        continue
    tw = open(p).read().splitlines()
    print(f"{t} preflight {label}: rc={open(os.path.join(o, label + '.rc')).read().strip()} | {tw[0] if tw else ''}")
for label in ("default", "followed"):
    p = os.path.join(o, label + ".json")
    if not os.path.exists(p):
        continue
    d = json.load(open(p))
    e = d.get("earliest") or {}
    print(f"{t} {label}: {d.get('verdict')} {d.get('unknown_reason') or ''} explored={d.get('explored')} "
          f"crash_points={d.get('crash_points')} earliest={e.get('crash_point')} | next: {(d.get('next_step') or '')[:100]}")
PY
