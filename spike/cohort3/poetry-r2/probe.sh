#!/bin/sh
# Cohort-3 poetry revision 2 probe (engine-free: normal executions
# only). The operation changes from the primary's `add --lock` to
# `version patch`, so the probe evidence is re-established for the new
# operation: same seven-condition harness as the primaries
# (cohort2/probes/lib.sh predicates), state root = the project
# directory (pyproject.toml + poetry.lock), no dependency fixture (the
# operation takes none). The revision's reason and the owner approval
# are recorded in proposals.md.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-poetry-r2
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS/pre/proj"

note "poetry-r2 probe — $(poetry --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixture, byte-for-byte the primary's frozen manifest ------------------
cat > "$WS/pre/proj/pyproject.toml" <<'EOF'
[project]
name = "app"
version = "0.1.0"
requires-python = ">=3.13"

[tool.poetry]
package-mode = false
EOF

export HOME="$WS/home"; mkdir -p "$HOME"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
note "condition 7 — ambient: POETRY_CACHE_DIR and POETRY_CONFIG_DIR are created FRESH PER RUN (the reset); HOME=<WS>/home fresh and shown after the runs; PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring throughout. No outside-root fixture exists for this operation."

# Pre-state completion: the lockfile, generated at setup (the primary's
# rule, unchanged).
mkdir -p "$WS/pcache-setup" "$WS/pconfig-setup"
( cd "$WS/pre/proj" && POETRY_CACHE_DIR="$WS/pcache-setup" POETRY_CONFIG_DIR="$WS/pconfig-setup" poetry lock ) > /dev/null 2>&1
echo "setup: poetry lock rc=$?"
ls "$WS/pre/proj"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/pre/proj" "$WS/proj$sfx"
    mkdir -p "$WS/pcache-$sfx" "$WS/pconfig-$sfx"
    echo "reset: proj$sfx is a fresh copy of the pre-state; pcache-$sfx and pconfig-$sfx are fresh"
    ( cd "$WS/proj$sfx" && POETRY_CACHE_DIR="$WS/pcache-$sfx" POETRY_CONFIG_DIR="$WS/pconfig-$sfx" poetry version patch ) 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pre/proj" "$WS/projA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the state root after run A differs from the pre-state"

grep -q '^version = "0.1.1"$' "$WS/projA/pyproject.toml" && m=yes || m=no
cmp -s "$WS/pre/proj/poetry.lock" "$WS/projA/poetry.lock" && l=yes || l=no
[ "$m" = yes ] && [ "$l" = yes ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "pyproject.toml carries version 0.1.1 ($m) and poetry.lock is byte-identical to the pre-state ($l — the operation does not touch it)"
echo "the manifest's version line after run A:"
grep -n '^version' "$WS/projA/pyproject.toml"

vrd=$( cd "$WS/projA" && POETRY_CACHE_DIR="$WS/pcache-A" POETRY_CONFIG_DIR="$WS/pconfig-A" poetry version --short 2>/dev/null )
( cd "$WS/projA" && POETRY_CACHE_DIR="$WS/pcache-A" POETRY_CONFIG_DIR="$WS/pconfig-A" poetry check --lock ) > /dev/null 2>&1; crc=$?
[ "$vrd" = "0.1.1" ] && [ "$crc" -eq 0 ] && ok=yes || ok=no
verdict "4-round-trip" $ok "poetry version --short reads back 0.1.1 (got: $vrd) and poetry check --lock exits 0 (rc=$crc — the bumped version does not stale the lock)"

note "diff -r of the two state roots:"
diff -r "$WS/projA" "$WS/projB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as poetry-r2.strace)"
cp -a "$WS/pre/proj" "$WS/projS"
mkdir -p "$WS/pcache-S" "$WS/pconfig-S"
( cd "$WS/projS" && POETRY_CACHE_DIR="$WS/pcache-S" POETRY_CONFIG_DIR="$WS/pconfig-S" run_strace "$WS/strace.log" poetry version patch ) > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/poetry-r2.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
closure_check "$WS/strace.log" "$WS/projS" "$WS/pcache-S" "$WS/pconfig-S" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "state-root write shape (the syscalls that decide the crash worlds):"
grep "projS" "$WS/strace.log" | grep -E "openat.*(O_WRONLY|O_TRUNC)|renameat|unlinkat" | grep -v "= -1" | sed "s|$WS|WS|"

note "clone forecast under the define's configuration (venv creation off, fresh pre-state and ambient):"
cp -a "$WS/pre/proj" "$WS/projF"
mkdir -p "$WS/pcache-F" "$WS/pconfig-F"
( cd "$WS/projF" && POETRY_VIRTUALENVS_CREATE=false POETRY_CACHE_DIR="$WS/pcache-F" POETRY_CONFIG_DIR="$WS/pconfig-F" strace -f -o "$WS/forecast.log" -e trace=clone,clone3 poetry version patch ) > /dev/null 2>&1
echo "  no-virtualenvs: threads=$(thread_counts "$WS/forecast.log"), clone lines total=$(grep -c 'clone' "$WS/forecast.log")"

note "condition 7 evidence — HOME and per-run cache after run A:"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(HOME files above, if any); pcache-A contents:"
find "$WS/pcache-A" -type f | sed "s|$WS|WS|" | sort | head -10

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
