#!/bin/sh
# Cohort-3 positive control (PROTOCOL "The probe gate": the one substitution
# from cohort 2). A synthetic operation writes wall-clock bytes into its
# state root and goes through the SAME determinism predicate as the targets
# — and must split. A probe harness that has never flagged anything proves
# nothing about the probes it passed. The operation is synthetic on purpose
# (cohort 2's designated control, unpinned `borg create`, is not in this
# image); only the operation differs — the predicate path is identical.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"

WS=/tmp/probe-positive
rm -rf "$WS"; mkdir -p "$WS/pre/root"
printf 'fixed pre-state byte\n' > "$WS/pre/root/base"

note "positive control (synthetic wall-clock write) — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_once() { # suffix
    cp -a "$WS/pre/root" "$WS/root$1"
    echo "reset: root$1 is a fresh copy of the pre-state"
    date +%s%N > "$WS/root$1/stamp"
}

note "run A"; run_once A; rcA=$?
sleep 2
note "run B (>=2s later)"; run_once B; rcB=$?

[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "run A rc=$rcA, run B rc=$rcB (success convention: 0)"

note "diff -r of the two state roots (the control expects a SPLIT):"
before_det=$FAILS
diff -r "$WS/rootA" "$WS/rootB"; drc=$?
[ "$drc" -eq 0 ] && ok=yes || ok=no
verdict "5-determinism" $ok "two runs >=2s apart byte-identical (diff rc=$drc)"

# The gate is the DETERMINISM verdict specifically, not any red: a broken
# harness (a failed copy, a diff rc=2 on missing dirs) must not print
# "control ok" (R1: the any-FAILS form was fail-open). diff rc must also
# be exactly 1 — a comparison error is not a split.
if [ "$FAILS" -gt "$before_det" ] && [ "$drc" -eq 1 ] && [ "$before_det" -eq 0 ]; then
    echo "control ok: the determinism predicate split on a wall-clock write (the FAIL above is the control working; every other condition green)"
    exit 0
fi
echo "control FAIL: the determinism predicate did not split cleanly (pre-determinism FAILS=$before_det, diff rc=$drc) — no probe verdict may be accepted"
exit 1
