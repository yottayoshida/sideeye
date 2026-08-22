#!/bin/sh
# Cohort-3 poetry define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `poetry add --lock`, and the project comes back
# through poetry's own documented path — the manifest parses (leg V,
# tomllib: the manifest is primary data with no recovery), then
# `poetry check --lock` with the tool's OWN prescribed recovery run
# exactly once if it is red (leg R: `poetry lock`, the command the
# error message itself names; the prescription failing, or the re-check
# staying red, is the failure), then dependency-set coherence (leg T)
# and fixture conservation (leg C). The undocumented manual deletion of
# the lockfile is not a recovery. Every leg's rc is checked (a
# timeout's 124 must never read as an answer). Runs with the same
# ambient env the operation used.
set -u
S=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
P=/tmp/cohort3/poetry
export POETRY_CACHE_DIR="$P/pcache" POETRY_CONFIG_DIR="$P/pconfig"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export POETRY_VIRTUALENVS_CREATE=false
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(poetry-add): $*"; exit 1; }

[ -f "$S/pyproject.toml" ] || fail "pyproject.toml is missing from the state dir"
[ -f "$S/poetry.lock" ] || fail "poetry.lock is missing from the state dir"

# ---- leg V: the manifest parses — primary data, no recovery applies -------
python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$S/pyproject.toml" 2> "$T/toml.err"
rc=$?
[ "$rc" -eq 0 ] || fail "leg V: pyproject.toml no longer parses as TOML: $(head -c 200 "$T/toml.err")"

# ---- leg R: poetry's reader, with its own prescribed recovery -------------
timeout 120 poetry -C "$S" check --lock > "$T/check1" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    [ "$rc" -ne 124 ] || fail "leg R: poetry check --lock timed out"
    echo "checker(poetry-add): check --lock red; running the prescribed recovery (poetry lock): $(head -c 160 "$T/check1")"
    timeout 300 poetry -C "$S" lock > "$T/relock" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || fail "leg R: the prescribed recovery (poetry lock) failed (rc=$rc, 124/137 = timeout): $(head -c 200 "$T/relock")"
    timeout 120 poetry -C "$S" check --lock > "$T/check2" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || fail "leg R: the prescribed recovery ran but check --lock is still red (rc=$rc): $(head -c 200 "$T/check2")"
fi

# ---- leg T: the dependency set is old-or-new, never a third thing ---------
n=$(grep -c 'deppkg' "$S/pyproject.toml")
case "$n" in
    0|1) : ;;
    *) fail "leg T: the manifest names deppkg $n times — neither the old state nor the completed add" ;;
esac

# ---- leg C: conservation of the outside-root fixture ----------------------
printf '[project]\nname = "deppkg"\nversion = "0.1.0"\nrequires-python = ">=3.13"\n\n[build-system]\nrequires = ["poetry-core"]\nbuild-backend = "poetry.core.masonry.api"\n' | cmp -s - "$P/deppkg/pyproject.toml" || fail "leg C: the dependency fixture's pyproject.toml changed"
printf '' | cmp -s - "$P/deppkg/deppkg/__init__.py" || fail "leg C: the dependency fixture's __init__.py changed"

exit 0
