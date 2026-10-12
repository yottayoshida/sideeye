#!/bin/sh
# Cohort 2's P1 property with this run's paths (the 2026-09-16 crossed-walls checker): after a
# crash anywhere inside `bun add`, package.json parses and still holds what its owner wrote, and
# re-running the install - the documented recovery - reaches the new state.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(bun): $*"; exit 1; }
[ -f "$d/package.json" ] || fail "package.json is missing"
python3 - "$d/package.json" <<'PY' || fail "package.json does not parse, or lost its scripts - a torn manifest survived the crash"
import json, sys
m = json.load(open(sys.argv[1]))
assert m.get("scripts", {}).get("build", "").startswith("bun build")
PY
( cd "$d" && bun add /s/bunaux/dep-1.0.0.tgz ) > /tmp/bun-rerun.txt 2>&1 || fail "re-running bun add exited $?: $(tail -c 200 /tmp/bun-rerun.txt)"
grep -q '"probe-dep"' "$d/package.json" || fail "after the re-run, package.json has no probe-dep"
exit 0
