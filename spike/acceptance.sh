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

# The suite has to reach its own verdict.
#
# It once did not: a stray `set -e` added with a new check meant the next expected
# non-zero exit ended the script immediately, after its last *passing* line, with no
# failure message. The exit code was 1, which is what a failing suite looks like, so the
# only clue was the missing summary. A run that stops early now says so out loud.
reached_end=0
trap '[ "$reached_end" = 1 ] || echo "ACCEPTANCE SUITE ENDED EARLY — no verdict was reached" >&2' EXIT

ROOT=${SIDEEYE_ROOT:-/work}
SIDEEYE=$ROOT/zig-out/bin/sideeye
SHIM=$ROOT/zig-out/lib/libsideeye_shim.so
OUT=$ROOT/spike/out

fails=0
reasons=""

# The binary has to run at all before any verdict means anything.
#
# `zig-out` holds one platform's build at a time, so a `zig build` for the host silently
# replaces the Linux cross-build this suite needs. When that happens every case fails for
# the same reason and the summary says "36 acceptance checks failed" — which reads like a
# regression in the tool rather than a stale artifact. Asked directly, once, the answer is
# one line. This is the difference between "measured and it broke" and "could not measure".
if ! "$SIDEEYE" 2>&1 | grep -q "^sideeye "; then
    echo "CANNOT RUN: $SIDEEYE did not print its usage banner." >&2
    echo "  built for this platform? try: zig build -Dtarget=aarch64-linux-gnu" >&2
    "$SIDEEYE" 2>&1 | head -2 | sed 's/^/  | /' >&2
    exit 1
fi

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
echo "=========== check 1b: the L2 checker judges the same worlds ==========="
# check.sh cross-examines `doctor` against reality: it fails when the diagnostic claims
# health while the key cannot be read. That is the DESIGN §12 example, and it should
# fail in the same world L0 does.
TOY=$OUT/toy-bug
export TOY
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "atomicity, and the checker"; then
    echo "ok   both invariants failed in the same world (exit 1)"
else
    echo "FAIL L2 on the buggy toy: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

TOY=$OUT/toy-fixed
export TOY
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "falsified before the run"; then
    echo "ok   the corrected toy passes, with the checker falsified first"
else
    echo "FAIL L2 on the corrected toy: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# A checker that cannot fail must not be trusted. /bin/true is the purest form of that.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check /bin/true \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "checker_not_falsified"; then
    echo "ok   a checker that always succeeds is refused (exit 2)"
    reasons="$reasons checker_not_falsified"
else
    echo "FAIL unfalsifiable checker: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
unset TOY

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
echo "=========== check 2g: the weaker claim is available, and says so ==========="
# macOS has no oracle sideeye can use — dtruss is DTrace-based and SIP refuses it — so
# there has to be a way to accept PASS without one. It must be asked for explicitly and
# it must be visible in the report, otherwise the two kinds of PASS are indistinguishable.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "NOT VERIFIED"; then
    echo "ok   --allow-unverified passes and the report labels the claim"
else
    echo "FAIL allow-unverified: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The buggy toy must still FAIL under the same flag: a weaker completeness claim does
# not weaken a counterexample that is sitting right there.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
    echo "ok   a real counterexample still FAILs under the weaker claim"
else
    echo "FAIL allow-unverified should not suppress FAIL: exit $rc"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2f: the zero-operation path is guarded too ==========="
# `doctor` only reads, so no crash points are recorded. That early-PASS branch sits before
# the exploration loop, and an operation count of zero is exactly the shape a target
# takes when the shim could not see it — so it needs the same completeness requirement.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug doctor" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "completeness_not_verified"; then
    echo "ok   zero observed operations without an oracle is UNKNOWN"
else
    echo "FAIL zero-op path: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# With an oracle the same run is a legitimate PASS: nothing happened, and that is known.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug doctor" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "no state-directory operations"; then
    echo "ok   the same run passes once an oracle confirms it"
else
    echo "FAIL zero-op with oracle: exit $rc"
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
echo "=========== check 2h: the remaining verdict paths fire ==========="
# PRD's v0.1 acceptance requires every verdict path to be falsified once — "a gate whose
# failure paths were never seen firing is not a gate". UNKNOWN is covered above by seven
# detectors; SETUP ERROR and the recording-run check were not, until now.

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state --operation "$OUT/toy-bug rotate" \
    --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
rc=$?
if [ "$rc" = "3" ]; then
    echo "ok   a missing --shim is SETUP ERROR (exit 3)"
else
    echo "FAIL missing --shim: exit $rc, wanted 3"
    fails=$((fails + 1))
fi

# An operation that fails immediately used to reach PASS: it wrote its shim_ready
# marker, recorded nothing, changed nothing, and every structural detector stayed quiet.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug no-such-command" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "recording_run_failed"; then
    echo "ok   an operation that exits non-zero is UNKNOWN, not PASS"
    reasons="$reasons recording_run_failed"
else
    echo "FAIL failing operation: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2i: the machine-readable report ==========="
# DESIGN §13: JSON for the caller, text for the reader, identical content.
#
# Read with a real parser, not with grep. The first version of this check extracted
# fields with `tr | grep -o | cut`, which succeeds on a document truncated anywhere after
# the field it wants — precisely the output a short write produces. A check for malformed
# reports that passes on malformed reports is not a check.
if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL python3 is required to parse the report; refusing to fall back to grep"
    fails=$((fails + 1))
fi

field() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d=d[k] if isinstance(d,dict) else None
print(d)' "$1" "$2" 2>/dev/null; }

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/report.json >/dev/null 2>&1

if [ ! -f /tmp/acc/report.json ]; then
    echo "FAIL no JSON report written"
    fails=$((fails + 1))
else
    # The text report says "crash point 5 of 5"; the JSON must agree, or the two forms
    # are not the same report in two shapes.
    v=$(field /tmp/acc/report.json verdict)
    cp_=$(field /tmp/acc/report.json earliest.crash_point)
    ex=$(field /tmp/acc/report.json explored)
    if [ "$v" = "FAIL" ] && [ "$cp_" = "5" ] && [ "$ex" = "6" ]; then
        echo "ok   JSON parses and agrees with the text report (FAIL, crash point 5, explored 6)"
    else
        echo "FAIL JSON disagrees or does not parse: verdict=$v crash_point=$cp_ explored=$ex"
        fails=$((fails + 1))
    fi
fi

# UNKNOWN has to reach the JSON too: it is the verdict a CI caller is most likely to be
# branching on, and it exits from deep inside the run rather than at the end.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-raw init" --operation "$OUT/toy-raw rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/unknown.json >/dev/null 2>&1
r=$(field /tmp/acc/unknown.json unknown_reason)
if [ "$r" = "oracle_missed_operation" ]; then
    echo "ok   UNKNOWN reaches the JSON report, naming the detector"
else
    echo "FAIL UNKNOWN JSON: reason=${r:-none}"
    fails=$((fails + 1))
fi

# The counts have to be the run's own, not zeroes.
#
# Which UNKNOWN is asked matters. The one above is raised by the oracle comparison, which
# happens before the crash points are counted, so its `crash_points: 0` is true. The
# checker falsification runs after counting and before exploring, so it is the case that
# distinguishes "had not counted yet" from "counted and reported zero anyway" — the
# writer used to hardcode both to zero and only the second is a lie.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check /bin/true \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/counted.json >/dev/null 2>&1
cpu=$(field /tmp/acc/counted.json crash_points)
cnote=$(field /tmp/acc/counted.json checker)
creason=$(field /tmp/acc/counted.json unknown_reason)
if [ "$creason" = "checker_not_falsified" ] && [ -n "$cpu" ] && [ "$cpu" != "0" ]; then
    echo "ok   UNKNOWN JSON carries the counts the run had reached ($cpu crash points)"
else
    echo "FAIL UNKNOWN JSON counts: reason=$creason crash_points=$cpu"
    fails=$((fails + 1))
fi
# And the document must not argue with itself: a checker was configured, and the reason
# says it failed falsification. "none configured" beside that is two facts that cannot
# both hold.
case "$cnote" in
    "none configured")
        echo "FAIL JSON says no checker was configured beside checker_not_falsified"
        fails=$((fails + 1))
        ;;
    *)
        echo "ok   the JSON agrees with itself about the checker ($cnote)"
        ;;
esac

# A run that exits before writing must not leave the previous run's verdict behind.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/stale.json >/dev/null 2>&1
before=$(field /tmp/acc/stale.json verdict)
"$SIDEEYE" explore --json /tmp/acc/stale.json --no-such-flag x >/dev/null 2>&1
after=$(field /tmp/acc/stale.json verdict)
if [ "$before" = "FAIL" ] && [ "$after" = "SETUP_ERROR" ]; then
    echo "ok   a setup error replaces the previous verdict instead of leaving it"
else
    echo "FAIL stale report: before=$before after=$after (wanted FAIL then SETUP_ERROR)"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2j: the printed reproduce line reproduces ==========="
# The line was wrong twice, and both times the report looked right. It omitted the state
# directory; that was fixed without running the result, which left the trace path
# missing — and without it the shim returns from init() before arming, so the command
# runs to completion and changes nothing. Reading it is not enough. This runs it.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
line=$(echo "$o" | grep '^reproduce' | sed 's/^reproduce  *//; s/ <operation>$//')
if [ -z "$line" ]; then
    echo "FAIL the report printed no reproduce line"
    fails=$((fails + 1))
else
    rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
    TOY_STATE=/tmp/acc/state "$OUT/toy-bug" init >/dev/null 2>&1
    # Unquoted on purpose: the line is a sequence of VAR=VALUE words and `env` has to
    # receive them as separate arguments, exactly as a person pasting it would.
    # shellcheck disable=SC2086
    env TOY_STATE=/tmp/acc/state $line "$OUT/toy-bug" rotate >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "137" ] && [ ! -f /tmp/acc/state/key.json ] && [ -f /tmp/acc/state/key.json.tmp ]; then
        echo "ok   the printed line kills the target and leaves the reported state"
    else
        echo "FAIL reproduce line: exit $rc, state: $(ls /tmp/acc/state | tr '\n' ' ')"
        echo "     | $line"
        fails=$((fails + 1))
    fi
fi

echo ""
echo "=========== check 2k: an empty oracle is not agreement ==========="
# The pair with check 2d. There, a target that touches nothing PASSes because a real
# strace examined hundreds of lines and confirmed it. Here the same target meets an
# oracle that recorded nothing: two empty views, which the comparison would call
# agreement. It has to be UNKNOWN.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug doctor" \
    --shim "$SHIM" --work /tmp/acc/work --oracle "$ROOT/spike/empty-oracle.sh" 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "oracle_saw_nothing"; then
    echo "ok   an oracle that observed nothing does not confirm anything (exit 2)"
    reasons="$reasons oracle_saw_nothing"
else
    echo "FAIL empty oracle: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# And an oracle that cannot be started at all is a setup error, not a verdict about the
# target. Without this the report blamed the operation for exiting non-zero when it was
# the measuring apparatus that never ran.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/no-such-strace 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "oracle is not an executable"; then
    echo "ok   a missing oracle is SETUP ERROR, not a verdict about the target"
else
    echo "FAIL missing oracle: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2l: a state directory larger than one buffer ==========="
# restore() collects names into a fixed buffer before deleting. Stopping at the bound
# left the previous world's files in place; failing at it made any directory of more than
# 256 entries unexplorable, reported as a setup error naming nothing. Neither shows up
# in a suite whose state directories hold one file.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acc/state "$OUT/toy-fixed" init >/dev/null 2>&1
i=0
while [ $i -lt 300 ]; do
    echo "filler" > /tmp/acc/state/f$i.dat
    i=$((i + 1))
done
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
left=$(ls -1 /tmp/acc/state | wc -l | tr -d ' ')
if [ "$rc" = "0" ] && [ "$left" = "301" ]; then
    echo "ok   301 entries explored and restored intact"
else
    echo "FAIL large state directory: exit $rc, $left entries left of 301"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2m: a state directory named through a symlink ==========="
# The engine resolves --state, so the shim filters on the resolved spelling while a
# target told the unresolved one hands *that* to unlink and rename. Path arguments then
# fall outside the filter and only descriptor-based operations are counted.
#
# macOS meets this every time, because /tmp is a symlink to /private/tmp — and it showed
# up only in the reproduce line, since during exploration the engine hands the target the
# resolved path itself. Linux has to build the symlink to reach the same case.
rm -rf /tmp/acc /tmp/acclink && mkdir -p /tmp/acc/state
ln -s /tmp/acc /tmp/acclink
o=$("$SIDEEYE" explore --state /tmp/acclink/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
# A baseline, not a discriminator: this stays green with the fix reverted, because the
# engine hands the toy the resolved path through TOY_STATE and the two spellings never
# meet. Kept so a regression in the ordinary path is visible; the assertion that pins the
# fix is the reproduce line below, which went red without it.
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   the symlinked spelling still reaches the same crash point (baseline)"
else
    echo "FAIL symlinked state dir: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# And the reproduce line printed for it has to work when the target is pointed at the
# spelling the caller used, which is the only spelling the caller knows.
line=$(echo "$o" | grep '^reproduce' | sed 's/^reproduce  *//; s/ <operation>$//')
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acclink/state "$OUT/toy-bug" init >/dev/null 2>&1
# No `set +e` / `set -e` pair here. This suite runs under `set -u` only, and a "restoring"
# `set -e` would switch errexit *on* from that point — which it did: the next check runs
# the buggy toy, sideeye correctly exits 1, and the whole suite ended there in silence,
# after its last passing line. Commands whose failure is expected are simply not guarded.
# shellcheck disable=SC2086
env TOY_STATE=/tmp/acclink/state $line "$OUT/toy-bug" rotate >/dev/null 2>&1
rc=$?
if [ "$rc" = "137" ] && [ ! -f /tmp/acc/state/key.json ] && [ -f /tmp/acc/state/key.json.tmp ]; then
    echo "ok   its reproduce line works through the symlink too"
else
    echo "FAIL symlinked reproduce line: exit $rc, state: $(ls /tmp/acc/state | tr '\n' ' ')"
    echo "     | $line"
    fails=$((fails + 1))
fi
rm -f /tmp/acclink

echo ""
echo "=========== check 2n: a failure that needs no crash is not a counterexample ==========="
# check.sh refuses to run without TOY, so it fails in every world — including the baseline,
# which was never killed. Before this gate the report read "FAIL 6 of 6 crash worlds
# violated an invariant", blaming crashing for something that happens without it. Found
# while generating an example for the README, not by review.
#
# Only reachable through a checker: for the baseline world `crashed` is `final`, and
# judgeL0 compares every shared file against pre or post, so post always matches.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
unset TOY 2>/dev/null || true
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "baseline_violates_invariant"; then
    echo "ok   an invariant that fails without a crash is UNKNOWN, not FAIL (exit 2)"
    reasons="$reasons baseline_violates_invariant"
else
    echo "FAIL baseline violation: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The control: the same checker, correctly configured, must still find the planted bug at
# the crash point — otherwise the gate above would be indistinguishable from one that
# swallows every L2 finding.
TOY=$OUT/toy-bug
export TOY
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
unset TOY
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   the same checker still reports the real counterexample (exit 1)"
else
    echo "FAIL configured checker control: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2o: nothing the target spawned outlives the run ==========="
# `runChild` used to wait for the direct child only. Everything the target spawned kept
# running — writing into the state directory while the engine was snapshotting, restoring
# for the next world, or running the checker. The verdict then describes a moment nobody
# chose. v0.1 only got away with it because a target that forks is refused before any
# world is explored; the recording run still had the hazard.
#
# The observation point is a file, not the verdict. `TOY_FORK_LATE` is still
# `child_process_detected`, so this check works without boundary tolerance existing.
#
# Deliberately no `--oracle`: `strace -f` follows the late child and does not exit until
# its tracees do, so the write would land before the engine ever returned and the check
# would be measuring strace instead of containment. Measured, not assumed — see BUILDLOG.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_FORK_LATE=1 export TOY_FORK_LATE
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
unset TOY_FORK_LATE

# The absence of a file is only evidence if the thing that would have created it ran.
# `child_process_detected` is that proof: the shim can only report it after the operation
# started and forked. Without this, a run that died in setup would leave no late.txt and
# the check would pass having measured nothing.
if [ "$rc" != "2" ] || ! echo "$o" | grep -q "child_process_detected"; then
    echo "FAIL the operation never reached the fork: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
else
    # The child sleeps 300ms before writing. Wait past that, then look.
    sleep 1
    if [ -f /tmp/acc/state/late.txt ]; then
        echo "FAIL a descendant outlived the run and wrote into the state directory"
        fails=$((fails + 1))
    else
        echo "ok   the target forked, and no descendant survived to write afterwards"
    fi
fi

echo ""
echo "=========== check 2p: observing a target must not break it ==========="
# The shim's vfork wrapper used to be an ordinary function, and that was fatal to any
# target which called it. Measured, with the control that places the fault: vfork+exec
# exits 0 on its own and exited 127 under the shim — and it did so with the shim
# *inactive*, so the cause was never the recording path. It was the wrapper's own stack
# frame, alive across vfork's double return on the stack the child shares; the child
# clobbered it and the parent resumed into the child's branch. No output, no signal:
# silently wrong control flow.
#
# What made it worse than a crash is what sideeye then said about it:
#   UNKNOWN recording_run_failed / "the operation did not exit normally"
# blaming the target for a death sideeye caused. The wrapper is now a recorded boundary
# followed by a guaranteed tail jump — no frame exists at the moment of the call. Both
# halves are asserted below: the target lives, and the refusal names the boundary rather
# than the corpse. Reverting the tail call to an ordinary call turns 2p red (measured).

# 1. The control. If this ever fails the toy is broken and everything after it is noise.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acc/state "$OUT/toy-bug" init >/dev/null 2>&1
TOY_STATE=/tmp/acc/state TOY_VFORK=1 "$OUT/toy-bug" rotate >/dev/null 2>&1
rc=$?
if [ "$rc" = "0" ]; then
    echo "ok   the vforking toy exits 0 on its own (control)"
else
    echo "FAIL the control is broken: the toy exits $rc without sideeye anywhere near it"
    fails=$((fails + 1))
fi

# 2. The same target, with the shim loaded and armed exactly as the engine loads it.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acc/state "$OUT/toy-bug" init >/dev/null 2>&1
rm -f /tmp/acc/vfork-trace.bin
TOY_STATE=/tmp/acc/state TOY_VFORK=1 \
    LD_PRELOAD="$SHIM" \
    SIDEEYE_STATE_DIR=/tmp/acc/state \
    SIDEEYE_TRACE_PATH=/tmp/acc/vfork-trace.bin \
    "$OUT/toy-bug" rotate >/dev/null 2>&1
rc=$?
if [ "$rc" = "0" ]; then
    echo "ok   it still exits 0 with the shim loaded and recording"
else
    echo "FAIL the shim changed the target's outcome: exit $rc, wanted 0"
    fails=$((fails + 1))
fi

# ...and the boundary has to be in the shim's own trace. Neither the exit code above nor
# the verdict below proves that: the run under sideeye carries an oracle, whose clone
# detection alone produces child_process_detected — and the toy's child execs, so even a
# shim that lost its vfork wrapper would still record an exec boundary from inside the
# child. Only a fork-class record (op 200) in this trace says the vfork call itself was
# seen. Counted with a real decoder for the same reason check 2i uses one: grep succeeds
# on garbage.
fork_recs=$(python3 -c '
import struct, sys
try:
    b = open(sys.argv[1], "rb").read()
except OSError:
    print(0); raise SystemExit
i, n = 12, 0
while i + 10 <= len(b):
    op, seq, plen = struct.unpack_from("<HII", b, i); i += 10 + plen
    if i + 4 > len(b): break
    (alen,) = struct.unpack_from("<I", b, i); i += 4 + alen
    if op == 200: n += 1
print(n)' /tmp/acc/vfork-trace.bin)
if [ "${fork_recs:-0}" -ge 1 ]; then
    echo "ok   the vfork call itself was recorded ($fork_recs fork-class record)"
else
    echo "FAIL no fork-class record in the trace: the vfork interposition is not recording"
    fails=$((fails + 1))
fi

# 3. And the verdict names the boundary rather than the death.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_VFORK=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "child_process_detected"; then
    echo "ok   a vforking target is refused for creating a process, not for dying"
elif echo "$o" | grep -q "recording_run_failed"; then
    echo "FAIL the target died under observation and was blamed for it (recording_run_failed)"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
else
    echo "FAIL vfork verdict: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# 4. The boundary must still be *seen*. Dropping the vfork interposition entirely would
# also make checks 2 and 3 pass — the target lives when nothing is in the way — but it
# would open a hole on the platform with no oracle: a vfork child that never execs is
# invisible to everything else. So the export has to exist, and the verdict above has to
# have come from it. The positive control matters: `readelf` naming the wrong section, or
# a typo in the field, would otherwise report every symbol as absent.
syms=$(readelf --dyn-syms "$SHIM" | awk '{print $8}')
if ! echo "$syms" | grep -qx "fork"; then
    echo "FAIL the symbol check cannot see the shim's exports at all (fork is missing too)"
    fails=$((fails + 1))
elif ! echo "$syms" | grep -qx "vfork"; then
    echo "FAIL the shim no longer interposes vfork; surviving by not observing is not the fix"
    fails=$((fails + 1))
else
    echo "ok   the shim interposes vfork and the target survives it"
fi

echo ""
echo "=========== check 2b: the reasons are distinct ==========="
# Last, so that every UNKNOWN-producing case above has already contributed. It used to
# run in the middle, and a later case appended to $reasons after the count had been
# taken — the value was written and never read, so the new detector could have collapsed
# into an existing one without the count noticing.
distinct=$(echo "$reasons" | tr ' ' '\n' | grep -v '^$' | sort -u | wc -l | tr -d ' ')
total=$(echo "$reasons" | tr ' ' '\n' | grep -v '^$' | wc -l | tr -d ' ')
echo "detectors fired: $reasons"
echo "distinct: $distinct of $total"
# A single always-UNKNOWN path would give 1 no matter how many cases ran.
if [ "$distinct" -lt 10 ]; then
    echo "FAIL: expected at least ten distinct detectors, got $distinct"
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

reached_end=1
echo ""
if [ "$fails" = "0" ]; then
    echo "ALL ACCEPTANCE CHECKS PASSED"
    exit 0
fi
echo "$fails ACCEPTANCE CHECK(S) FAILED"
exit 1
