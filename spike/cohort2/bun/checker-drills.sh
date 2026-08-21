#!/bin/sh
# Per-leg falsification of the bun-add checker: greens as controls, each
# red against an input violating exactly its leg. Normal executions and
# synthetic corruption of copies only — no kill, no engine.
set -u
here=$(cd "$(dirname "$0")" && pwd)
OPS="$here/ops"
B=/tmp/cohort2/bun
FAILS=0
want() { if [ "$3" = "$2" ]; then echo "drill ok   $1 (rc=$3)"; else echo "drill FAIL $1 (rc=$3, wanted $2)"; FAILS=$((FAILS+1)); fi; }

echo "== bun-add checker drills — bun $(bun --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# green 1: the pre-state (rolled-back shape; recovery installs and lands new)
"$OPS/setup.sh" > /dev/null 2>&1
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "green-old-state" 0 $?

# green 2: the post-state (baseline shape; recovery is a no-op re-add)
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "green-new-state" 0 $?

# red T: a torn manifest (package.json truncated mid-write)
"$OPS/setup.sh" > /dev/null 2>&1
printf '{ "name": "probe-proj", "vers' > "$B/state/package.json"
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-T" 1 $?

# red R: the recovery cannot run (the tarball vanished)
"$OPS/setup.sh" > /dev/null 2>&1
rm -f "$B/dep-1.0.0.tgz"
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-R-precondition" 1 $?

# red N: recovery succeeds but the installed bytes differ from the tarball
# (a poisoned cache ships wrong content); built by re-tarring different
# bytes under the same name and pre-seeding node_modules from it
"$OPS/setup.sh" > /dev/null 2>&1
printf 'module.exports = "evil";\n' > "$B/deppkg/package/index.js"
tar -czf "$B/dep-1.0.0.tgz" -C "$B/deppkg" package
( cd "$B/state" && HOME="$B/ambient/home" BUN_INSTALL_CACHE_DIR="$B/ambient/cache" TMPDIR="$B/ambient/tmp" timeout 120 bun add "$B/dep-1.0.0.tgz" > /dev/null 2>&1 )
printf 'module.exports = "probe-dep";\n' > "$B/deppkg/package/index.js"
tar -czf "$B/dep-1.0.0.tgz" -C "$B/deppkg" package
# the cache still holds the evil bytes under the same version, so the
# re-run installs them and leg N's byte comparison must refuse
SIDEEYE_STATE_DIR="$B/state" "$OPS/check.sh"; want "red-leg-N" 1 $?

echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
