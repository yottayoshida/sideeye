#!/bin/sh
# The v0.1 acceptance checks, run for real rather than reasoned about.
#
# Check 1 — inside the supported boundary, judge correctly:
#   the buggy toy FAILs, naming the crash point between unlink and rename;
#   the corrected toy PASSes and claims explored == N+1.
#
# Check 2 — outside it, never report PASS:
#   four out-of-bounds targets all exit 2, and each names a *different* detector.
#   The last part is what stops "always answer UNKNOWN" and "one ldd check for
#   everything" from passing: the reasons have to come from distinct branches.
set -u

ROOT=${SIDEEYE_ROOT:-/work}
SIDEEYE=$ROOT/zig-out/bin/sideeye
SHIM=$ROOT/zig-out/lib/libsideeye_shim.so
OUT=$ROOT/spike/out

fails=0
reasons=""

# Every case runs with an oracle. PASS without one is refused by design — see the
# completeness_not_verified case below — so a suite that omitted it would only ever be
# exercising the FAIL and UNKNOWN paths.
run_case() {
    name=$1; toy=$2; want_exit=$3; want_text=$4
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    output=$("$SIDEEYE" explore \
        --state /tmp/acc/state \
        --setup "$toy init" \
        --operation "$toy rotate" \
        --shim "$SHIM" \
        --work /tmp/acc/work \
        --oracle /usr/bin/strace 2>&1)
    rc=$?

    if [ "$rc" != "$want_exit" ]; then
        echo "FAIL $name: exit $rc, wanted $want_exit"
        echo "$output" | sed 's/^/     | /'
        fails=$((fails + 1))
        return
    fi
    if ! echo "$output" | grep -q "$want_text"; then
        echo "FAIL $name: output did not contain '$want_text'"
        echo "$output" | sed 's/^/     | /'
        fails=$((fails + 1))
        return
    fi
    echo "ok   $name (exit $rc)"

    # Collect the detector name for the disjointness check below.
    if [ "$rc" = "2" ]; then
        r=$(echo "$output" | head -1 | awk '{print $2}')
        reasons="$reasons $r"
    fi
}

echo "=========== check 1: inside the boundary ==========="
run_case "toy-bug FAILs"       "$OUT/toy-bug"   1 "crash point 5 of 5"
run_case "  ...names the window" "$OUT/toy-bug" 1 "after  unlink"
run_case "  ...and the next op"  "$OUT/toy-bug" 1 "before rename"
run_case "toy-fixed PASSes"    "$OUT/toy-fixed" 0 "crash worlds satisfied"

# Checked as a relation rather than a fixed number. The first version asserted
# "crash points 5 + 1", which is the buggy toy's count — the corrected one performs no
# unlink and so has four. A hard-coded expectation would keep needing adjustment and
# would pass for the wrong reason if a count ever changed by accident.
echo "     checking explored == N + 1 ..."
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
n=$(echo "$o" | grep -o 'crash points [0-9]*' | awk '{print $3}')
e=$(echo "$o" | grep -o 'explored [0-9]*' | awk '{print $2}')
if [ -n "$n" ] && [ -n "$e" ] && [ "$e" = "$((n + 1))" ]; then
    echo "ok     ...explored ($e) == N ($n) + 1"
else
    echo "FAIL   explored=$e N=$n — the report does not account for every crash point"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2: outside the boundary ==========="
# With an oracle present the oracle speaks first, because it can name the operation
# that went unseen rather than only observing that something moved.
run_case "toy-raw is UNKNOWN"    "$OUT/toy-raw"    2 "oracle_missed_operation"
run_case "toy-static is UNKNOWN" "$OUT/toy-static" 2 "no_shim_marker"

# And the oracle-independent layer has to work on its own, because macOS may not have
# an oracle at all. Same target, no --oracle: a different detector must catch it.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-raw init" --operation "$OUT/toy-raw rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "state_changed_without_ops"; then
    echo "ok   toy-raw is caught without an oracle too (exit 2)"
    reasons="$reasons state_changed_without_ops"
else
    echo "FAIL structural detector without oracle: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The case the structural detectors cannot see on their own: one ordinary libc write
# (so something *was* counted as mutated) followed by a raw syscall that changes the
# key behind the shim's back. state_changed_without_ops stays quiet here.
run_case "toy-mixed is UNKNOWN"  "$OUT/toy-mixed"  2 "oracle_missed_operation"

TOY_FORK=1 export TOY_FORK
run_case "fork is UNKNOWN"       "$OUT/toy-bug"    2 "child_process_detected"
unset TOY_FORK
TOY_THREAD=1 export TOY_THREAD
run_case "thread is UNKNOWN"     "$OUT/toy-bug"    2 "multiple_threads_detected"
unset TOY_THREAD

echo ""
echo "=========== check 2c: the oracle fires on its own ==========="
# toy-raw is caught by the structural detector even without an oracle, so running it
# *with* one is how the oracle path itself gets shown to work rather than assumed to.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-raw init" --operation "$OUT/toy-raw rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "oracle_missed_operation"; then
    echo "ok   the oracle names the missed operation (exit 2)"
else
    echo "FAIL oracle path: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# On a supported target the two views must agree — and the report must say how much was
# examined. "agreed" over zero inspected lines would read the same as never looking.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
scanned=$(echo "$o" | grep -o '[0-9]* syscall lines examined' | cut -d' ' -f1)
if echo "$o" | grep -q "agreed on 6 operations" && [ "${scanned:-0}" -gt 10 ]; then
    echo "ok   the oracle agreed on 6 operations over $scanned examined lines"
else
    echo "FAIL oracle agreement: scanned=${scanned:-0}"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2d: PASS is refused without an oracle ==========="
# The corrected toy is genuinely correct, so this is the one place where the *only*
# thing standing between the run and a PASS is the completeness requirement.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "completeness_not_verified"; then
    echo "ok   a target that would otherwise PASS is UNKNOWN without an oracle"
    reasons="$reasons completeness_not_verified"
else
    echo "FAIL no-oracle PASS suppression: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2e: restore does not follow a symlink out of the tree ==========="
# restore() deletes the state tree once per world. A link inside it pointing outside
# must be removed as a link, never descended into.
rm -rf /tmp/outside /tmp/acc && mkdir -p /tmp/outside /tmp/acc/state
echo "precious" > /tmp/outside/keepme.txt
TOY_STATE=/tmp/acc/state "$OUT/toy-bug" init >/dev/null 2>&1
ln -s /tmp/outside /tmp/acc/state/link
"$SIDEEYE" explore --state /tmp/acc/state \
    --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
if [ -f /tmp/outside/keepme.txt ]; then
    echo "ok   the file outside the state directory survived"
else
    echo "FAIL restore followed the symlink and deleted outside the root"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2b: the reasons are distinct ==========="
distinct=$(echo "$reasons" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
total=$(echo "$reasons" | tr ' ' '\n' | grep -v '^$' | wc -l | tr -d ' ')
echo "detectors fired: $reasons"
echo "distinct: $distinct of $total"
# A single always-UNKNOWN path would give 1 no matter how many cases ran.
if [ "$distinct" -lt 5 ]; then
    echo "FAIL: expected at least five distinct detectors, got $distinct"
    fails=$((fails + 1))
else
    echo "ok   $distinct different detectors fired"
fi

echo ""
echo "=========== check 3: determinism across repeated runs ==========="
first=""
same=0
i=1
while [ $i -le 3 ]; do
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$("$SIDEEYE" explore --state /tmp/acc/state \
        --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
        --shim "$SHIM" --work /tmp/acc/work 2>&1)
    if [ -z "$first" ]; then first=$o; same=1; else
        [ "$o" = "$first" ] && same=$((same + 1))
    fi
    i=$((i + 1))
done
echo "$same/3 runs produced identical reports"
[ "$same" = "3" ] || { echo "FAIL: reports differed between runs"; fails=$((fails + 1)); }

echo ""
if [ "$fails" = "0" ]; then
    echo "ALL ACCEPTANCE CHECKS PASSED"
    exit 0
fi
echo "$fails ACCEPTANCE CHECK(S) FAILED"
exit 1
