#!/bin/sh
# The checker's three controls for one define (#861's plan, D6), inside the box:
#   docker run ... sideeye-m1014 sh /ap/controls.sh <name>
# Prints one CONTROL line per state: the seeded state before the operation, the state the completed
# operation leaves, and one state per leg of the invariant, each broken by defines/<name>/legs.sh.
# The checker run is the toml's `check` string itself, so a checker edited without editing the toml
# cannot pass here.
set -u
t=${1:?usage: controls.sh <name>}
d=/ap/defines/$t
. /ap/env.sh; [ -f "$d/env.sh" ] && . "$d/env.sh"
eval "$(python3 - "$d/sideeye.toml" <<'PY'
import sys, tomllib, shlex
doc = tomllib.loads(open(sys.argv[1]).read())
dfn = doc["define"]; op = dfn["operation"]
argv = op if isinstance(op, list) else shlex.split(op)
print("STATE=%s" % shlex.quote(doc["world"]["state"]))
print("CHECK=%s" % shlex.quote(dfn["check"]))
print("CWD=%s" % shlex.quote(dfn.get("cwd", "/")))
print("OP=%s" % shlex.quote(" ".join(shlex.quote(a) for a in argv)))
PY
)"
export SIDEEYE_STATE_DIR="$STATE"
seed() { sh "$d/seed.sh" > /tmp/controls-seed.log 2>&1 || { echo "CONTROL $t seed-failed"; tail -5 /tmp/controls-seed.log; exit 2; }; }
operate() { ( cd "$CWD" && sh -c "$OP" ) > /tmp/controls-op.log 2>&1 || echo "CONTROL $t operation exited $? (not a control result): $(tail -c 300 /tmp/controls-op.log)"; }
check() { # <label>
    ( cd "$CWD" && sh -c "$CHECK" ) > "/tmp/controls-$1.log" 2>&1
    rc=$?
    echo "CONTROL $t $1 rc=$rc $(grep -o 'after recovery: .*' "/tmp/controls-$1.log" | tail -1)"
}
echo "CONTROL $t check=$CHECK"
seed; check pre
seed; operate; check done
. "$d/legs.sh"
for leg in $LEGS; do
    seed; operate; "break_$leg"; check "leg-$leg"
done
