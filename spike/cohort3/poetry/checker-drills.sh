#!/bin/sh
# Per-leg falsification of the cohort-3 poetry checker (every leg red
# once, separately, ATTRIBUTED), plus the drill this target uniquely
# needs: the GREEN-WITH-RECOVERY control — the between-writes crash
# state must heal through poetry's own prescription and end green,
# because distinguishing "the documented recovery worked" (state A)
# from "the documented recovery failed" (states B/C) is the entire
# property. States are fabricated with normal poetry runs plus file
# surgery — no kill, no crash, no engine. Spawned through exec bits.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
P=/tmp/cohort3/poetry
FAILS=0

drill() { # name want(pass|fail) state-dir expected-fragment
    name=$1; want=$2; st=$3; frag=$4
    out=$(SIDEEYE_STATE_DIR="$st" "$OPS/check.sh" 2>&1); rc=$?
    if [ "$want" = pass ] && [ "$rc" -eq 0 ]; then
        case "$out" in
            *"$frag"*) echo "drill ok   $name: checker green as required${frag:+ (and the transcript carries: $frag)}" ;;
            *) echo "drill FAIL $name: green but WITHOUT the required evidence line '$frag' — $out"; FAILS=$((FAILS+1)) ;;
        esac
    elif [ "$want" = fail ] && [ "$rc" -eq 1 ]; then
        case "$out" in
            *"$frag"*) echo "drill ok   $name: checker red in the intended leg — $(echo "$out" | tail -1)" ;;
            *) echo "drill FAIL $name: red, but in the WRONG leg (wanted '$frag') — $out"; FAILS=$((FAILS+1)) ;;
        esac
    else
        echo "drill FAIL $name: rc=$rc, wanted $want — $out"
        FAILS=$((FAILS+1))
    fi
}

echo "== poetry checker drills — $(poetry --version 2>/dev/null | tr -d '\n') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$P/d-old" "$P/d-new" "$P/d-heal" "$P/d-el" "$P/d-tl" "$P/d-tm" "$P/d-em" "$P/d-t" "$P/d-m"
export POETRY_CACHE_DIR="$P/pcache" POETRY_CONFIG_DIR="$P/pconfig"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export POETRY_VIRTUALENVS_CREATE=false
export HOME="$P/home"
"$OPS/setup.sh" > /dev/null 2>&1
echo "setup rc=$? (poetry lock under the launcher's env)"

# green control, old side
cp -a "$P/state" "$P/d-old"
drill "green-old" pass "$P/d-old" ""

# green control, new side: a completed add (rc checked; recorded line printed)
cp -a "$P/state" "$P/d-new"
poetry -C "$P/d-new" add --lock "$P/deppkg" > /dev/null 2>&1
arc=$?
echo "poetry add rc=$arc (must be 0 for green-new to mean what it claims)"
[ "$arc" -eq 0 ] || { echo "drill FAIL green-new: poetry add itself failed (rc=$arc)"; FAILS=$((FAILS+1)); }
drill "green-new" pass "$P/d-new" ""
echo "the dependency entry the absolute-path add recorded:"
grep -n 'deppkg' "$P/d-new/pyproject.toml"

# GREEN-WITH-RECOVERY: state A (new lock + old manifest) must heal
# through the prescription and end green — the transcript must carry
# the recovery line, or a checker that never ran the recovery could
# fake this green
cp -a "$P/d-old" "$P/d-heal"
cp "$P/d-new/poetry.lock" "$P/d-heal/poetry.lock"
drill "green-heal-A" pass "$P/d-heal" "running the prescribed recovery"

# leg R red: state B, the empty lock — the prescription fails
cp -a "$P/d-old" "$P/d-el"
: > "$P/d-el/poetry.lock"
drill "R-red-empty-lock" fail "$P/d-el" "leg R"

# leg R red: state C, the torn lock — the prescription fails
cp -a "$P/d-old" "$P/d-tl"
head -c 200 "$P/d-new/poetry.lock" > "$P/d-tl/poetry.lock"
drill "R-red-torn-lock" fail "$P/d-tl" "leg R"

# leg V red: state E, the torn manifest — primary data, no recovery
cp -a "$P/d-new" "$P/d-tm"
head -c 60 "$P/d-new/pyproject.toml" > "$P/d-tm/pyproject.toml"
drill "V-red-torn-manifest" fail "$P/d-tm" "leg V"

# leg R red: state D, the EMPTY manifest — parses as empty TOML (leg V
# green), the configuration is invalid, and the attempted prescription
# fails (declared in proposals: this state lands in R, not V)
cp -a "$P/d-new" "$P/d-em"
: > "$P/d-em/pyproject.toml"
drill "R-red-empty-manifest" fail "$P/d-em" "leg R"

# leg T red: deppkg named on two lines in valid TOML
cp -a "$P/d-new" "$P/d-t"
printf '\n# deppkg named again on its own line\n' >> "$P/d-t/pyproject.toml"
drill "T-red-named-twice" fail "$P/d-t" "leg T"

# leg C red: the outside-root fixture mutated
cp -a "$P/d-new" "$P/d-m"
printf 'x' >> "$P/deppkg/deppkg/__init__.py"
drill "C-red-fixture-mutated" fail "$P/d-m" "leg C"
: > "$P/deppkg/deppkg/__init__.py"

# guard red: the lockfile is gone entirely
rm "$P/d-m/poetry.lock"
drill "guard-red-missing-lock" fail "$P/d-m" "poetry.lock is missing"

rm -rf "$P/d-old" "$P/d-new" "$P/d-heal" "$P/d-el" "$P/d-tl" "$P/d-tm" "$P/d-em" "$P/d-t" "$P/d-m"
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
