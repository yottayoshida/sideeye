#!/bin/sh
# Cohort-3 poetry revision-2 (P1) checker. Property (proposals.md P1):
# crash anywhere inside `poetry version patch`, and the project comes
# back through poetry's own documented path — the manifest parses
# (leg V, tomllib: user-authored primary data, no recovery), then
# `poetry check --lock` with poetry's documented recovery CHAIN run at
# most once per step if it is red (leg R: step 1 `poetry lock`, the
# command check's red prescribes when one is prescribed — for a
# config-invalid manifest nothing is prescribed and step 1 is still
# attempted as poetry's first documented lever; if step 1 fails,
# step 2 `poetry lock --regenerate`, the rebuild the command's own
# --help documents; the chain failing, or the re-check staying red, is
# the failure — the primary's chain ruling, inherited unchanged), then
# version coherence (leg N: the version is the old string or the new
# string, never a third thing). Every leg's rc is checked; a timeout's
# 124 is annotated inside the red it produces, and the apparatus
# reading (a red whose message names a timeout is apparatus, not
# verdict) is frozen in proposals.md. Ambient env is exported here so
# a standalone invocation matches the launcher.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
P=/tmp/cohort3/poetry-r2
export POETRY_CACHE_DIR="$P/pcache" POETRY_CONFIG_DIR="$P/pconfig"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export POETRY_VIRTUALENVS_CREATE=false
export HOME="$P/home"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(poetry-version): $*"; exit 1; }

[ -f "$S/pyproject.toml" ] || fail "pyproject.toml is missing from the state dir"
[ -f "$S/poetry.lock" ] || fail "poetry.lock is missing from the state dir"

# ---- leg V: the manifest parses — primary data, no recovery applies -------
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$S/pyproject.toml" 2> "$T/toml.err"
rc=$?
[ "$rc" -eq 0 ] || fail "leg V: pyproject.toml no longer parses as TOML: $(head -c 200 "$T/toml.err")"

# ---- leg R: poetry's reader, with its documented recovery chain -----------
timeout 120 poetry -C "$S" check --lock > "$T/check1" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "checker(poetry-version): check --lock red; recovery chain step 1 (poetry lock): $(head -c 200 "$T/check1")"
    timeout 300 poetry -C "$S" lock > "$T/relock" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "checker(poetry-version): step 1 failed (rc=$rc); step 2, the documented regenerate (poetry lock --regenerate): $(head -c 200 "$T/relock")"
        timeout 300 poetry -C "$S" lock --regenerate > "$T/regen" 2>&1
        rc=$?
        [ "$rc" -eq 0 ] || fail "leg R: the documented recovery chain failed — poetry lock, then poetry lock --regenerate (rc=$rc, 124/137 = timeout): $(head -c 200 "$T/regen")"
    fi
    timeout 120 poetry -C "$S" check --lock > "$T/check2" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || fail "leg R: the recovery chain ran but check --lock is still red (rc=$rc, 124 = timeout): $(head -c 200 "$T/check2")"
fi

# ---- leg N: the version is old-or-new, never a third thing ----------------
v=$(grep '^version = ' "$S/pyproject.toml")
case "$v" in
    'version = "0.1.0"'|'version = "0.1.1"') : ;;
    *) fail "leg N: the manifest's version line is '$v' — neither the old 0.1.0 nor the completed patch 0.1.1" ;;
esac

exit 0
