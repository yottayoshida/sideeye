#!/bin/sh
# Cohort-3 probe: poetry (PROTOCOL.md "Probe plans", target 4).
# Engine-free: normal executions only. State root: the project directory
# (pyproject.toml + poetry.lock). `add --lock` mutates exactly those two
# files. Keyring is nulled (fully-qualified backend name); cache and
# config are per-run ambient. Raw strace log lands in $PROBE_OUT.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-poetry
OUT=${PROBE_OUT:-$WS}
rm -rf "$WS"; mkdir -p "$WS/pre/proj" "$WS/deppkg/deppkg"

note "poetry probe — $(poetry --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- fixtures, byte-for-byte from the frozen plan --------------------------
cat > "$WS/pre/proj/pyproject.toml" <<'EOF'
[project]
name = "app"
version = "0.1.0"
requires-python = ">=3.13"

[tool.poetry]
package-mode = false
EOF
cat > "$WS/deppkg/pyproject.toml" <<'EOF'
[project]
name = "deppkg"
version = "0.1.0"
requires-python = ">=3.13"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"
EOF
: > "$WS/deppkg/deppkg/__init__.py"

export HOME="$WS/home"; mkdir -p "$HOME"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
note "condition 7 — ambient: POETRY_CACHE_DIR and POETRY_CONFIG_DIR are created FRESH PER RUN (the reset); HOME=<WS>/home fresh and shown after the runs; PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring throughout. The dep package fixture lives outside the state root at <WS>/deppkg and is never mutated (asserted below)."

# Pre-state completion: the lockfile, generated at setup in the pre-state
# copy itself (the plan freezes "a poetry.lock generated at setup").
mkdir -p "$WS/pcache-setup" "$WS/pconfig-setup"
( cd "$WS/pre/proj" && POETRY_CACHE_DIR="$WS/pcache-setup" POETRY_CONFIG_DIR="$WS/pconfig-setup" poetry lock ) > /dev/null 2>&1
echo "setup: poetry lock rc=$?"
ls "$WS/pre/proj"

run_once() { # suffix
    sfx=$1
    cp -a "$WS/pre/proj" "$WS/proj$sfx"
    mkdir -p "$WS/pcache-$sfx" "$WS/pconfig-$sfx"
    echo "reset: proj$sfx is a fresh copy of the pre-state; pcache-$sfx and pconfig-$sfx are fresh"
    ( cd "$WS/proj$sfx" && POETRY_CACHE_DIR="$WS/pcache-$sfx" POETRY_CONFIG_DIR="$WS/pconfig-$sfx" poetry add --lock ../deppkg ) 2>&1
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

if diff -r "$WS/pre/proj" "$WS/projA" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "the state root after run A differs from the pre-state"

grep -q 'deppkg' "$WS/projA/pyproject.toml" && m=yes || m=no
grep -q 'deppkg' "$WS/projA/poetry.lock" && l=yes || l=no
[ "$m" = yes ] && [ "$l" = yes ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "pyproject.toml names deppkg ($m) and poetry.lock names deppkg ($l)"
echo "the manifest's dependency lines after run A:"
grep -n 'deppkg' "$WS/projA/pyproject.toml"

( cd "$WS/projA" && POETRY_CACHE_DIR="$WS/pcache-A" POETRY_CONFIG_DIR="$WS/pconfig-A" poetry check --lock ) > /dev/null 2>&1; crc=$?
printf '' | cmp -s - "$WS/deppkg/deppkg/__init__.py" && fix=intact || fix=changed
[ "$crc" -eq 0 ] && [ "$fix" = intact ] && ok=yes || ok=no
verdict "4-round-trip" $ok "poetry check --lock exits 0 (rc=$crc; the tool's own oracle) and the fixture is unmutated ($fix)"
echo "the lock's deppkg entry, as measured:"
grep -n -A2 'name = "deppkg"' "$WS/projA/poetry.lock" | head -6

note "diff -r of the two state roots:"
diff -r "$WS/projA" "$WS/projB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart leave byte-identical state roots (diff rc=$drc)"

note "strace pass (fresh copy; raw log kept as poetry.strace)"
cp -a "$WS/pre/proj" "$WS/projS"
mkdir -p "$WS/pcache-S" "$WS/pconfig-S"
( cd "$WS/projS" && POETRY_CACHE_DIR="$WS/pcache-S" POETRY_CONFIG_DIR="$WS/pconfig-S" run_strace "$WS/strace.log" poetry add --lock ../deppkg ) > /dev/null 2>&1
echo "strace'd run rc=$?"
cp "$WS/strace.log" "$OUT/poetry.strace" 2>/dev/null || true
note "mutating paths (successful only, deduped):"
closure_paths "$WS/strace.log" "$WS/unattr-count" | sort -u | sed "s|$WS|WS|"
echo "unattributed count: $(cat "$WS/unattr-count" 2>/dev/null || echo '?')"
# Declared: the state root, the per-run cache/config (client state,
# condition 7), HOME, /tmp scratch — and the dep fixture is read, not
# written (any write there fails this check).
closure_check "$WS/strace.log" "$WS/projS" "$WS/pcache-S" "$WS/pconfig-S" "$WS/home" /tmp/
note "thread creations (successful CLONE_THREAD):"
thread_counts "$WS/strace.log"

note "condition 7 evidence — the fixture is unmutated (both files); HOME and per-run cache after run A:"
printf '' | cmp -s - "$WS/deppkg/deppkg/__init__.py" && echo "deppkg/deppkg/__init__.py: unchanged (empty)" || echo "deppkg/deppkg/__init__.py: CHANGED"
printf '[project]\nname = "deppkg"\nversion = "0.1.0"\nrequires-python = ">=3.13"\n\n[build-system]\nrequires = ["poetry-core"]\nbuild-backend = "poetry.core.masonry.api"\n' | cmp -s - "$WS/deppkg/pyproject.toml" && echo "deppkg/pyproject.toml: unchanged" || echo "deppkg/pyproject.toml: CHANGED"
find "$HOME" -type f | sed "s|$WS|WS|" | sort
echo "(HOME files above, if any); pcache-A contents:"
find "$WS/pcache-A" -type f | sed "s|$WS|WS|" | sort | head -10

# ---- shim-visibility forecast: the virtualenv machinery --------------------
# The engine refuses observed threads. The strace above shows poetry
# creating a virtualenv under the cache even for `add --lock` (its seeder
# spawns threads) plus python-discovery forks. POETRY_VIRTUALENVS_CREATE
# is poetry's documented off switch; this measures what it removes.
note "clone forecast per configuration (fresh pre-state copy and fresh ambient each):"
for cfg in default no-virtualenvs; do
    cp -a "$WS/pre/proj" "$WS/projF"
    mkdir -p "$WS/pcache-F" "$WS/pconfig-F"
    if [ "$cfg" = default ]; then
        ( cd "$WS/projF" && POETRY_CACHE_DIR="$WS/pcache-F" POETRY_CONFIG_DIR="$WS/pconfig-F" strace -f -o "$WS/forecast.log" -e trace=clone,clone3 poetry add --lock ../deppkg ) > /dev/null 2>&1
    else
        ( cd "$WS/projF" && POETRY_VIRTUALENVS_CREATE=false POETRY_CACHE_DIR="$WS/pcache-F" POETRY_CONFIG_DIR="$WS/pconfig-F" strace -f -o "$WS/forecast.log" -e trace=clone,clone3 poetry add --lock ../deppkg ) > /dev/null 2>&1
    fi
    echo "  $cfg: threads=$(thread_counts "$WS/forecast.log"), clone lines total=$(grep -c 'clone' "$WS/forecast.log")"
    rm -rf "$WS/projF" "$WS/forecast.log" "$WS/pcache-F" "$WS/pconfig-F"
done

note "conditions failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
