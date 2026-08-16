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
# The operation comes in one of two committed spellings, and the difference
# is measured (BUILDLOG 2026-08-16): op.txt is one static command line the
# engine spawns directly — the preferred form, used whenever the documented
# invocation fits the engine's space-split contract; op.sh is the ADR 0007
# fallback for invocations that cannot be spelled that way (an argument
# carrying a space, a stdin redirect). A zero-prior-op script wrapper is an
# exec chain the v10 observation rules refuse structurally — so for op.sh
# targets that refusal, if it comes, is the trial's honest verdict: the
# define budget could not spell the target inside the contract.
#
# Usage: bgroup.sh <target> <artifact-dir>
set -u
t=${1:?target}; art=${2:?artifact dir}
SIDEEYE=${SIDEEYE:-/work/zig-out/bin/sideeye}
SHIM=${SHIM:-/work/zig-out/lib/libsideeye_shim.so}
defs=/work/spike/unknown-rate/defines-b/$t
[ -x "$defs/setup.sh" ] || { echo "bgroup.sh: $t has no executable setup.sh" >&2; exit 3; }
# op.txt is a template: the literal token $TOY_STATE stands for the state
# directory, expanded here per leg (preflight and explore use different
# roots) — the same name the engine itself exports to setup/op children.
optpl=""
if [ -f "$defs/op.txt" ]; then
    [ "$(grep -c . "$defs/op.txt")" = 1 ] || {
        echo "bgroup.sh: $t op.txt must be exactly one non-empty line" >&2; exit 3; }
    optpl=$(head -n 1 "$defs/op.txt")
    [ -n "$optpl" ] || { echo "bgroup.sh: $t op.txt is empty" >&2; exit 3; }
elif [ ! -x "$defs/op.sh" ]; then
    echo "bgroup.sh: $t has neither op.txt nor executable op.sh" >&2; exit 3
fi
op_for() {
    if [ -n "$optpl" ]; then
        printf '%s' "$optpl" | sed "s|\$TOY_STATE|$1|g"
    else
        printf '%s' "$defs/op.sh"
    fi
}
mkdir -p "$art" || exit 3
# Uniform scratch HOME: dotfile writes (hnb's ~/.hnbrc, and whatever a
# fresh target invents) land outside the repo and outside the judged state.
export HOME=/tmp/bgroup-home/$t
mkdir -p "$HOME" || exit 3
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
    --operation "$(op_for "$proot/state")" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$proot/work" > "$art/preflight.txt" 2>&1
echo "preflight exit=$?" >> "$art/preflight.txt"

# The measurement.
mkdir -p "$root/state" || exit 3
"$SIDEEYE" explore --state "$root/state" --setup "$defs/setup.sh" \
    --operation "$(op_for "$root/state")" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$root/work" --json "$art/report.json" \
    > "$art/transcript.txt" 2>&1
rc=$?
echo "bgroup/$t exit=$rc"
exit $rc
