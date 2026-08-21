#!/bin/sh
# Drills: every probe predicate is seen red once against a synthetic input
# that violates exactly its condition (the repo rule for new guards; the
# positive control covers condition 5, this file covers the rest). Exit 0
# means every drill produced the expected red.
set -u
. "$(dirname "$0")/lib.sh"

WS=/tmp/probe-drills
rm -rf "$WS"; mkdir -p "$WS"
DRILL_FAILS=0
expect_red() { # name
    # The preceding verdict call bumped FAILS iff it went red.
    if [ "$FAILS" -gt "$_before" ]; then
        echo "drill ok   $1 went red as required"
    else
        echo "drill FAIL $1 stayed green against a violating input"
        DRILL_FAILS=$((DRILL_FAILS + 1))
    fi
}

note "probe-predicate drills — $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- drill 1: exit codes — a failing operation must go red ------------------
_before=$FAILS
false; rcA=$?; true; rcB=$?
[ "$rcA" -eq 0 ] && [ "$rcB" -eq 0 ] && ok=yes || ok=no
verdict "1-exit-codes" $ok "drill input: run A rc=$rcA (a failing operation), run B rc=$rcB"
expect_red "1-exit-codes"

# ---- drill 2: non-no-op — an operation that changes nothing must go red -----
_before=$FAILS
mkdir -p "$WS/pre" && printf 'x\n' > "$WS/pre/f"
cp -a "$WS/pre" "$WS/post"     # the "operation" changed nothing
if diff -r "$WS/pre" "$WS/post" > /dev/null 2>&1; then ok=no; else ok=yes; fi
verdict "2-non-noop" $ok "drill input: post-state identical to pre-state"
expect_red "2-non-noop"

# ---- drill 3: artifact count — one extra artifact must go red ---------------
_before=$FAILS
listing="probe extra-archive"   # a listing with an unexpected second artifact
[ "$listing" = "probe" ] && ok=yes || ok=no
verdict "3-artifact-count" $ok "drill input: listing '$listing' where exactly 'probe' was expected"
expect_red "3-artifact-count"

# ---- drill 4: round-trip — corrupted content must go red --------------------
_before=$FAILS
printf 'original bytes\n' > "$WS/want"
printf 'corrupted bytes\n' > "$WS/got"
if diff "$WS/want" "$WS/got" > /dev/null 2>&1; then ok=yes; else ok=no; fi
verdict "4-round-trip" $ok "drill input: extracted bytes differ from the source"
expect_red "4-round-trip"

# ---- drill 6: closure — an undeclared persistent write must go red ----------
_before=$FAILS
mkdir -p "$WS/undeclared" "$WS/state6"
run_strace "$WS/strace6.log" sh -c "echo persist > $WS/undeclared/leak.txt; echo ok > $WS/state6/inside.txt"
closure_check "$WS/strace6.log" "$WS/state6" /tmp/probe-drills/declared-nowhere/
expect_red "6-closure"

# ---- drill 6b (green control): the same check passes a closed run -----------
_before=$FAILS
mkdir -p "$WS/state6b"
run_strace "$WS/strace6b.log" sh -c "echo ok > $WS/state6b/inside.txt"
closure_check "$WS/strace6b.log" "$WS/state6b"
if [ "$FAILS" -gt "$_before" ]; then
    echo "drill FAIL 6b-closure-control went red on a run whose writes were all declared"
    DRILL_FAILS=$((DRILL_FAILS + 1))
else
    echo "drill ok   6b-closure-control stayed green on a closed run"
fi

note "drills failed: $DRILL_FAILS (probe-condition reds above are the drills working, counted separately)"
[ "$DRILL_FAILS" -eq 0 ] && exit 0 || exit 1
