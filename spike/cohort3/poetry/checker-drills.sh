#!/bin/sh
# Per-leg falsification of the cohort-3 poetry checker (every leg — and
# every branch of leg R's recovery chain — red once, separately,
# ATTRIBUTED by a branch-specific fragment), plus the drills this
# target uniquely needs: the GREEN-WITH-RECOVERY controls. State A must
# heal through the prescription (`poetry lock`) and states B/C must
# heal through the documented regenerate (`poetry lock --regenerate`),
# each ending green with the transcript carrying the chain step that
# did the healing — a checker that never ran the chain cannot fake
# these greens. Distinguishing "came back through poetry's documented
# chain" from "nothing documented brings it back" is the entire
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
            *"$frag"*)
                echo "drill ok   $name: checker green as required"
                if [ -n "$frag" ]; then
                    echo "  the transcript line carrying the required evidence:"
                    printf '%s\n' "$out" | grep -F "$frag" | sed 's/^/  | /'
                fi ;;
            *) echo "drill FAIL $name: green but WITHOUT the required evidence line '$frag' — $out"; FAILS=$((FAILS+1)) ;;
        esac
    elif [ "$want" = fail ] && [ "$rc" -eq 1 ]; then
        case "$out" in
            *"$frag"*)
                echo "drill ok   $name: checker red in the intended branch; full checker output:"
                printf '%s\n' "$out" | sed 's/^/  | /' ;;
            *) echo "drill FAIL $name: red, but in the WRONG branch (wanted '$frag') — $out"; FAILS=$((FAILS+1)) ;;
        esac
    else
        echo "drill FAIL $name: rc=$rc, wanted $want — $out"
        FAILS=$((FAILS+1))
    fi
}

echo "== poetry checker drills — $(poetry --version 2>/dev/null | tr -d '\n') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIRS="$P/d-old $P/d-new $P/d-heal $P/d-hb $P/d-hc $P/d-em $P/d-pr $P/d-tm $P/d-t $P/d-m"
rm -rf $DIRS
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

# GREEN-WITH-RECOVERY, step 1: state A (new lock + old manifest) must
# heal through the prescription. The required evidence is check's own
# prescription text, verbatim, carried into the transcript by the
# step-1 line — so the committed record holds the sentence the finding
# narrative rests on.
cp -a "$P/d-old" "$P/d-heal"
cp "$P/d-new/poetry.lock" "$P/d-heal/poetry.lock"
drill "green-heal-A-prescription" pass "$P/d-heal" 'Run `poetry lock` to fix the lock file'

# GREEN-WITH-RECOVERY, step 2: state B (empty lock) — step 1 fails
# with the self-prescribing error (upstream pins the failure as
# intended) and the documented regenerate heals. The required evidence
# is the self-prescription verbatim: it can only appear inside the
# step-2 line's excerpt of step 1's failure, so green plus this
# fragment proves the failure text AND that the chain continued.
cp -a "$P/d-old" "$P/d-hb"
: > "$P/d-hb/poetry.lock"
drill "green-heal-B-empty-lock" pass "$P/d-hb" 'Regenerate the lock file with the `poetry lock` command'

# GREEN-WITH-RECOVERY, step 2: state C (torn lock, mid-entry) — same
# chain, same healing step.
cp -a "$P/d-old" "$P/d-hc"
head -c 200 "$P/d-new/poetry.lock" > "$P/d-hc/poetry.lock"
drill "green-heal-C-torn-lock" pass "$P/d-hc" "step 2, the documented regenerate"

# leg R red, chain branch: state D, the EMPTY manifest — parses as
# empty TOML (leg V green), the configuration is invalid, and the
# whole documented chain fails (declared in proposals: this state
# lands in R, not V — and it is the candidate shape)
cp -a "$P/d-new" "$P/d-em"
: > "$P/d-em/pyproject.toml"
drill "R-red-chain-empty-manifest" fail "$P/d-em" "the documented recovery chain failed"

# leg R red, persistent branch: chain step 1 succeeds yet check stays
# red — fabricated by declaring a README file that does not exist
# (check red, `poetry lock` rc 0, re-check red). This is the branch a
# real recovered-but-still-broken world would land in; it must be
# rehearsed before a FAIL can rest on it.
cp -a "$P/d-old" "$P/d-pr"
sed -i 's|^version = "0.1.0"$|version = "0.1.0"\nreadme = "MISSING.md"|' "$P/d-pr/pyproject.toml"
drill "R-red-persistent-still-red" fail "$P/d-pr" "still red"

# leg V red: state E, the torn manifest — primary data, no recovery
cp -a "$P/d-new" "$P/d-tm"
head -c 60 "$P/d-new/pyproject.toml" > "$P/d-tm/pyproject.toml"
drill "V-red-torn-manifest" fail "$P/d-tm" "leg V"

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

rm -rf $DIRS
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
