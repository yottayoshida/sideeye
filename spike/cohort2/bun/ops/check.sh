#!/bin/sh
# Cohort-2 bun define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `bun add`, and the project triple (package.json,
# lockfile, node_modules) is old-or-new-or-repairable: the documented
# recovery is re-running the install, and after it the exact new state
# holds. Every bun output's rc is checked explicitly.
set -u
D=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
B=/tmp/cohort2/bun
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(bun-add): $*"; exit 1; }

[ -f "$D/package.json" ] || fail "package.json is missing from the state dir"
[ -f "$B/dep-1.0.0.tgz" ] || fail "the dependency tarball is missing (setup writes it)"

assert_new_state() { # label
    _l=$1
    grep -q '"probe-dep"' "$D/package.json" || fail "$_l: package.json lost the dependency entry"
    [ -f "$D/bun.lock" ] || fail "$_l: the lockfile is missing"
    cmp -s "$D/node_modules/probe-dep/package.json" "$B/deppkg/package/package.json" || fail "$_l: installed package.json differs from the tarball's"
    cmp -s "$D/node_modules/probe-dep/index.js" "$B/deppkg/package/index.js" || fail "$_l: installed index.js differs from the tarball's"
}

# ---- leg T: classify the crashed state; a torn MEMBER is the violation ----
# The triple may disagree across files (the crash landed between writes —
# the repairable middle the property allows), but any single file must be
# readable and internally whole where the contract says it is atomic:
# package.json must parse whenever it exists.
python3 - "$D/package.json" <<'PYEOF' || fail "leg T: package.json does not parse — a torn manifest survived the crash"
import json, sys
json.load(open(sys.argv[1]))
PYEOF

# ---- leg R: the documented recovery — re-run the install ----
( cd "$D" && HOME="$B/ambient/home" BUN_INSTALL_CACHE_DIR="$B/ambient/cache" \
  TMPDIR="$B/ambient/tmp" timeout 120 bun add "$B/dep-1.0.0.tgz" ) > "$T/rerun" 2>&1
rc=$?
[ "$rc" -eq 0 ] || fail "leg R: the documented recovery (re-running bun add) exited $rc (124 = timeout): $(tail -c 200 "$T/rerun")"

# ---- leg N: after recovery, the exact new state holds ----
assert_new_state "leg N"

exit 0
