#!/bin/sh
# Drills for cohort 4's two added predicates: each is seen red once against
# an input that violates exactly its condition, and green once against one
# that does not. Same rule and same shape as cohort 2's run-drills.sh,
# whose predicates this harness sources in place rather than copying.
#
# Conditions 1-7 are not re-drilled here: they are cohort 2's lines, and
# their drills belong to that harness. This file covers 8 and 9 only.
#
# Exit 0 means every drill produced the expected colour.
set -u
. "$(dirname "$0")/../../cohort2/probes/lib.sh"
. "$(dirname "$0")/lib.sh"

WS=${WS:-/tmp/c4-drills}
rm -rf "$WS"; mkdir -p "$WS"
TOYS="$(dirname "$0")/../../toys"
DRILL_FAILS=0

need() {
    command -v "$1" >/dev/null 2>&1 ||
        { echo "BROKEN $1 not installed — the drills cannot run"; exit 2; }
}
need cc
need strace
need python3

expect() { # name expected-colour
    if [ "$2" = red ]; then
        if [ "$FAILS" -gt "$_before" ]; then
            echo "drill ok   $1 went red as required"
        else
            echo "drill FAIL $1 stayed green against a violating input"
            DRILL_FAILS=$((DRILL_FAILS + 1))
        fi
    else
        if [ "$FAILS" -eq "$_before" ]; then
            echo "drill ok   $1 stayed green as required"
        else
            echo "drill FAIL $1 went red against a conforming input"
            DRILL_FAILS=$((DRILL_FAILS + 1))
        fi
    fi
    echo ""
}

cc -o "$WS/toy" "$TOYS/toy.c" || { echo "BROKEN toy.c did not compile"; exit 2; }
cc -o "$WS/toy_raw" "$TOYS/toy_raw.c" || { echo "BROKEN toy_raw.c did not compile"; exit 2; }

# ---- condition 8 ----------------------------------------------------------
note "drill 8a — libc-routed writes must leave condition 8 green"
mkdir -p "$WS/libc/state"
TOY_STATE="$WS/libc/state" "$WS/toy" init > /dev/null 2>&1
_before=$FAILS
PROBE_OUT="$WS/libc" condition8_visibility "$WS/libc/state" -- \
    env "TOY_STATE=$WS/libc/state" "$WS/toy" rotate
expect "8a (libc-routed)" green

note "drill 8b — raw-syscall writes must turn condition 8 red"
mkdir -p "$WS/raw/state"
TOY_STATE="$WS/raw/state" "$WS/toy_raw" init > /dev/null 2>&1
_before=$FAILS
PROBE_OUT="$WS/raw" condition8_visibility "$WS/raw/state" -- \
    env "TOY_STATE=$WS/raw/state" "$WS/toy_raw" rotate
expect "8b (raw syscalls)" red

note "drill 8c — a gate that cannot run must turn condition 8 red, not skip it"
_before=$FAILS
PREFLIGHT="$WS/no-such-gate.sh" condition8_visibility "$WS/libc/state" -- true
expect "8c (gate missing)" red

# ---- condition 9 ----------------------------------------------------------
note "drill 9a — an operation with an interior must be counted, not refused"
mkdir -p "$WS/libc2/state"
cp -a "$WS/libc/state/." "$WS/libc2/state/" 2>/dev/null || true
_before=$FAILS
PROBE_OUT="$WS/libc2" condition9_interior "$WS/libc2/state" -- \
    env "TOY_STATE=$WS/libc2/state" "$WS/toy" rotate
expect "9a (has an interior)" green

note "drill 9b — a gate that cannot run must turn condition 9 red, not skip it"
_before=$FAILS
PREFLIGHT="$WS/no-such-gate.sh" condition9_interior "$WS/libc/state" -- true
expect "9b (gate missing)" red

echo "== drills failed: $DRILL_FAILS of 5"
[ "$DRILL_FAILS" -eq 0 ] || exit 1
exit 0
