#!/bin/sh
# Per-leg falsification of the cohort-3 poetry-r2 checker (every leg —
# and every branch of leg R's recovery chain — red or heal once,
# separately, ATTRIBUTED by a branch-specific fragment). The chain is
# the primary's, inherited; its branches are re-rehearsed here in this
# define's own state because branch rehearsal is per-define (a copied
# chain is not a rehearsed chain). States are fabricated with normal
# poetry runs plus file surgery — no kill, no crash, no engine.
# Spawned through exec bits.
set -u
OPS=$(cd "$(dirname "$0")/ops" && pwd)
P=/tmp/cohort3/poetry-r2
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

echo "== poetry-r2 checker drills — $(poetry --version 2>/dev/null | tr -d '\n') — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIRS="$P/d-old $P/d-new $P/d-ha $P/d-hb $P/d-em $P/d-pr $P/d-tm $P/d-n"
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

# green control, new side: a completed patch (rc checked; the bumped line printed)
cp -a "$P/state" "$P/d-new"
poetry -C "$P/d-new" version patch > /dev/null 2>&1
arc=$?
echo "poetry version patch rc=$arc (must be 0 for green-new to mean what it claims)"
[ "$arc" -eq 0 ] || { echo "drill FAIL green-new: poetry version patch itself failed (rc=$arc)"; FAILS=$((FAILS+1)); }
drill "green-new" pass "$P/d-new" ""
echo "the version line the patch recorded:"
grep -n '^version' "$P/d-new/pyproject.toml"

# GREEN-WITH-RECOVERY, step 1: a stale lock (dependencies key inserted
# by surgery) must heal through the prescription; the required evidence
# is check's own prescription text, verbatim. Engine-unreachable for
# this operation (it never touches the lock) — rehearsed because
# branch rehearsal is per-define, not per-copied-code.
cp -a "$P/state" "$P/d-ha"
sed -i 's|^requires-python = ">=3.13"$|requires-python = ">=3.13"\ndependencies = []|' "$P/d-ha/pyproject.toml"
drill "green-heal-A-prescription" pass "$P/d-ha" 'Run `poetry lock` to fix the lock file'

# GREEN-WITH-RECOVERY, step 2: an empty lock — step 1 fails with the
# self-prescribing error and the documented regenerate heals. Also
# engine-unreachable here; same rehearsal rule.
cp -a "$P/state" "$P/d-hb"
: > "$P/d-hb/poetry.lock"
drill "green-heal-B-empty-lock" pass "$P/d-hb" 'Regenerate the lock file with the `poetry lock` command'

# leg R red, chain branch: the EMPTY manifest — THE declared candidate
# world of this revision (kill between the truncating open and the
# single write). Parses as empty TOML (leg V green), config invalid,
# whole chain fails.
cp -a "$P/d-new" "$P/d-em"
: > "$P/d-em/pyproject.toml"
drill "R-red-chain-empty-manifest" fail "$P/d-em" "the documented recovery chain failed"

# leg R red, persistent branch: chain step 1 succeeds yet check stays
# red (missing-README surgery; the primary's P1-1 lesson, re-rehearsed
# in this define's state).
cp -a "$P/d-old" "$P/d-pr"
sed -i 's|^version = "0.1.0"$|version = "0.1.0"\nreadme = "MISSING.md"|' "$P/d-pr/pyproject.toml"
drill "R-red-persistent-still-red" fail "$P/d-pr" "still red"

# leg V red: the torn manifest — primary data, no recovery
cp -a "$P/d-new" "$P/d-tm"
head -c 60 "$P/d-new/pyproject.toml" > "$P/d-tm/pyproject.toml"
drill "V-red-torn-manifest" fail "$P/d-tm" "leg V"

# leg N red: a third version string in valid TOML
cp -a "$P/d-new" "$P/d-n"
sed -i 's|^version = "0.1.1"$|version = "0.2.0"|' "$P/d-n/pyproject.toml"
drill "N-red-third-version" fail "$P/d-n" "leg N"

# guard red: the lockfile is gone entirely
rm "$P/d-n/poetry.lock"
drill "guard-red-missing-lock" fail "$P/d-n" "poetry.lock is missing"

rm -rf $DIRS
echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
