#!/bin/sh
# B-group launcher (#84 sweep): one uniform protocol for every
# mechanically-selected target that reached the define stage. The define is
# three committed files under defines-b/<target>/: setup.sh (seeds state,
# reading the engine-provided $TOY_STATE), op.sh (the one representative
# state-changing operation, same contract), and optional env.sh (sourced
# here; target-specific environment such as a scratch HOME — committed, so
# the trial is reproducible). Judge config is L0-only by design — no
# checker — plus the strict oracle; the preflight leg records the funnel
# instrument's answer (#77) beside the real verdict. preflight has no
# machine-readable form (src/main.zig names #84 for that; still open), so
# its text output and exit code are the record.
#
# Usage: bgroup.sh <target> <artifact-dir>
set -u
t=${1:?target}; art=${2:?artifact dir}
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
defs=/work/spike/unknown-rate/defines-b/$t
[ -x "$defs/setup.sh" ] && [ -x "$defs/op.sh" ] || {
    echo "bgroup.sh: $t has no executable setup.sh/op.sh under $defs" >&2; exit 3; }
mkdir -p "$art" || exit 3
[ -f "$defs/env.sh" ] && . "$defs/env.sh"

proot=/tmp/bgroup-pre/$t
root=/tmp/bgroup/$t
if [ -e "$proot" ] || [ -e "$root" ]; then
    echo "bgroup.sh: state root already exists — fresh container required" >&2; exit 3
fi

# Funnel instrument first, in its own root (preflight performs one observed
# run; its exit is 0 accepted / 2 refused).
mkdir -p "$proot/state" || exit 3
"$SIDEEYE" preflight --state "$proot/state" --setup "$defs/setup.sh" \
    --operation "$defs/op.sh" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$proot/work" > "$art/preflight.txt" 2>&1
echo "preflight exit=$?" >> "$art/preflight.txt"

# The measurement.
mkdir -p "$root/state" || exit 3
"$SIDEEYE" explore --state "$root/state" --setup "$defs/setup.sh" \
    --operation "$defs/op.sh" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "bgroup/$t exit=$rc"
exit $rc
