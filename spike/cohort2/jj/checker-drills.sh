#!/bin/sh
# Per-leg falsification of the jj-commit checker: greens as controls, each
# red against an input violating exactly its leg. Normal executions and
# synthetic corruption of copies only — no kill, no engine.
set -u
here=$(cd "$(dirname "$0")" && pwd)
OPS="$here/ops"
export JJ_USER=probe JJ_EMAIL=probe@example.invalid
export JJ_TIMESTAMP=2026-01-01T00:00:00+00:00 JJ_OP_TIMESTAMP=2026-01-01T00:00:00+00:00
export JJ_RANDOMNESS_SEED=42 JJ_OP_HOSTNAME=probe-host JJ_OP_USERNAME=probe-user
export JJ_TZ_OFFSET_MINS=0
export HOME=/tmp/cohort2/jj/home
mkdir -p "$HOME"
FAILS=0
want() { if [ "$3" = "$2" ]; then echo "drill ok   $1 (rc=$3)"; else echo "drill FAIL $1 (rc=$3, wanted $2)"; FAILS=$((FAILS+1)); fi; }

echo "== jj-commit checker drills — $(jj --version) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# green 1: the pre-state (rolled-back shape)
"$OPS/setup.sh" > /dev/null 2>&1
SIDEEYE_STATE_DIR=/tmp/cohort2/jj/repo "$OPS/check.sh"; want "green-old-state" 0 $?

# green 2: the post-state (baseline shape)
( cd /tmp/cohort2/jj/repo && jj commit -m probe > /dev/null 2>&1 )
SIDEEYE_STATE_DIR=/tmp/cohort2/jj/repo "$OPS/check.sh"; want "green-new-state" 0 $?

# red V: an unreadable repository (op store gutted)
cp -a /tmp/cohort2/jj/repo /tmp/drill-v
rm -rf /tmp/drill-v/.jj/repo/op_store
SIDEEYE_STATE_DIR=/tmp/drill-v "$OPS/check.sh"; want "red-leg-V" 1 $?

# red T: a third description list (an extra commit)
cp -a /tmp/cohort2/jj/repo /tmp/drill-t
( cd /tmp/drill-t && printf 'third\n' > alpha && jj commit -m third > /dev/null 2>&1 )
SIDEEYE_STATE_DIR=/tmp/drill-t "$OPS/check.sh"; want "red-leg-T" 1 $?

# red C: a valid repo whose initial bytes differ
rm -rf /tmp/drill-c && mkdir -p /tmp/drill-c && ( cd /tmp/drill-c && jj git init > /dev/null 2>&1 && git config core.logAllRefUpdates false && rm -rf .git/logs && printf 'different bytes\n' > alpha && jj commit -m initial > /dev/null 2>&1 && printf 'x\n' > alpha )
SIDEEYE_STATE_DIR=/tmp/drill-c "$OPS/check.sh"; want "red-leg-C" 1 $?

echo "== drills failed: $FAILS"
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
