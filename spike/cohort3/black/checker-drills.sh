#!/bin/sh
# Per-leg falsification of the cohort-3 black checker (the cohort rule:
# every leg red once, separately, ATTRIBUTED — the drill asserts the
# checker's message names the intended leg). States are fabricated with
# normal black runs plus targeted corruption — no kill, no crash, no
# engine. The checker and setup are spawned the way the engine spawns
# them: through the file's own exec bit, never `sh file`.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
B=/tmp/cohort3/black
FAILS=0

drill() { # name want(pass|fail) state-dir expected-fragment
    name=$1; want=$2; st=$3; frag=$4
    out=$(SIDEEYE_STATE_DIR="$st" "$OPS/check.sh" 2>&1); rc=$?
    if [ "$want" = pass ] && [ "$rc" -eq 0 ]; then
        echo "drill ok   $name: checker green as required"
    elif [ "$want" = fail ] && [ "$rc" -eq 1 ]; then
        case "$out" in
            *"$frag"*) echo "drill ok   $name: checker red in the intended leg — $out" ;;
            *) echo "drill FAIL $name: red, but in the WRONG leg (wanted '$frag') — $out"; FAILS=$((FAILS+1)) ;;
        esac
    else
        echo "drill FAIL $name: rc=$rc, wanted $want — $out"
        FAILS=$((FAILS+1))
    fi
}

echo "== black checker drills — $(black --version | tr '\n' ' ') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$B/drill-old" "$B/drill-new" "$B/drill-v" "$B/drill-empty" "$B/drill-e" "$B/drill-m"
"$OPS/setup.sh" > /dev/null 2>&1
export HOME="$B/home"

# green control, old side: the unformatted pre-state must pass (its AST
# is the frozen program's — leg E holds without any formatting)
cp -a "$B/state" "$B/drill-old"
drill "green-old" pass "$B/drill-old" ""

# green control, new side: a completed format (normal execution) must
# pass — this is the --safe shape measured live: black's output parses
# and its AST equals the frozen program's
cp -a "$B/state" "$B/drill-new"
black --no-cache "$B/drill-new/probe.py" > /dev/null 2>&1
drill "green-new" pass "$B/drill-new" ""
echo "the formatted bytes, as measured:"
cat "$B/drill-new/probe.py"

# leg V red: a mid-token truncation — the shape a PARTIAL write would
# leave (the engine-reachable tear for this fixture is the empty file,
# drilled below as E-red; this drill covers the parse-failure side)
cp -a "$B/drill-new" "$B/drill-v"
head -c 40 "$B/state/probe.py" > "$B/drill-v/probe.py"
drill "V-red-truncated" fail "$B/drill-v" "leg V"

# leg E red, the ENGINE-REACHABLE tear (probe strace: one O_TRUNC open
# + one write — the kill between them leaves an EMPTY file, which
# parses as an empty module and fails only the AST comparison)
cp -a "$B/drill-new" "$B/drill-empty"
: > "$B/drill-empty/probe.py"
drill "E-red-empty-file" fail "$B/drill-empty" "leg E"

# leg E red: valid Python, DIFFERENT program (one constant changed) —
# only the AST comparison can catch it
cp -a "$B/drill-new" "$B/drill-e"
cat > "$B/drill-e/probe.py" <<'EOF'
x=[1,2,3]
def f(a,b):
    return {'k':a+b,'l':[v   for v in x]}
y = f( 1 ,3 )
EOF
drill "E-red-different-program" fail "$B/drill-e" "leg E"

# guard red: the file is gone entirely
cp -a "$B/drill-old" "$B/drill-m"
rm "$B/drill-m/probe.py"
drill "guard-red-missing-file" fail "$B/drill-m" "missing from the state dir"

rm -rf "$B/drill-old" "$B/drill-new" "$B/drill-v" "$B/drill-empty" "$B/drill-e" "$B/drill-m"
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
