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

# The refusal names what it refused on (#41): the divergence index, the raw strace
# line the oracle saw there, and where the shim's account stood — in the text and in
# the JSON, with identical content (DESIGN §13). Decoding a binary trace by hand to
# learn which operation split the accounts was the single largest avoidable cost in
# the timewarrior session; an agent driving the define loop cannot do even that.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-mixed init" --operation "$OUT/toy-mixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --json /tmp/acc/report.json \
    --oracle /usr/bin/strace 2>&1)
rc=$?
# The text detail (the line after UNKNOWN) and the JSON message must be byte-equal —
# "identical content" is the claim, and two independent substring probes would let the
# two forms drift apart (or let a control byte through on the text side) unnoticed.
text_detail=$(echo "$o" | sed -n '/^UNKNOWN/{n;s/^ *//;p;}' | head -1)
match=$(TEXT_DETAIL="$text_detail" python3 -c '
import json, os
try:
    m = json.load(open("/tmp/acc/report.json")).get("message", "")
except Exception:
    m = None
t = os.environ["TEXT_DETAIL"]
ok = m is not None and m == t and "divergence at operation 3" in m and "key.json" in m
print(1 if ok else 0)')
if [ "$rc" = "2" ] && [ "${match:-0}" = "1" ]; then
    echo "ok   the refusal names the divergent operation, byte-equal in text and JSON"
else
    echo "FAIL named refusal: exit $rc match=${match:-0}"
    echo "     | text: $text_detail"
    python3 -c "import json; print(\"     | json:\", json.load(open(\"/tmp/acc/report.json\")).get(\"message\",\"(none)\"))" 2>/dev/null
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

TOY_THREAD=1 export TOY_THREAD
run_case "thread is UNKNOWN"     "$OUT/toy-bug"    2 "multiple_threads_detected"
unset TOY_THREAD

echo ""
echo "=========== check 2q: a boundary is judged by what the child did ==========="
# One binary, one environment variable of difference per case. An engine that decides by
# anything other than the child's actual behaviour — always refuse, always tolerate,
# match on the target's name — cannot pass all six.

# A fork whose child exits quietly: the subject's account is complete, so the planted
# bug must be found at the same crash point as the boundary-free run.
TOY_FORK=1 export TOY_FORK
run_case "fork + quiet child explores"      "$OUT/toy-bug" 1 "crash point 5 of 5"
unset TOY_FORK

# The same, through posix_spawn: a new process *and* a new image.
TOY_SPAWN=1 export TOY_SPAWN
run_case "spawn + quiet child explores"     "$OUT/toy-bug" 1 "crash point 5 of 5"
unset TOY_SPAWN

# A forked child that writes into the state directory: no crash-point address exists
# for its operation, whatever else is true.
TOY_FORK_WRITES=1 export TOY_FORK_WRITES
run_case "fork + writing child is refused"  "$OUT/toy-bug" 2 "child_touched_state_dir"
unset TOY_FORK_WRITES

# A spawned shell that writes into the state directory: the child never loaded the shim
# of the process the engine armed, so only the oracle sees this one.
TOY_SPAWN_WRITES=1 export TOY_SPAWN_WRITES
run_case "spawn + writing child is refused" "$OUT/toy-bug" 2 "child_touched_state_dir"
unset TOY_SPAWN_WRITES

# A child that leaves the process group: the engine cannot claim to have stopped it,
# oracle or no oracle.
TOY_DETACH=1 export TOY_DETACH
run_case "a child that detaches is refused" "$OUT/toy-bug" 2 "left the containment group"
unset TOY_DETACH

# And without an oracle the whole question is unanswerable: the shim only sees processes
# that load it, and "was not seen" must never be read as "did nothing".
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_FORK=1 export TOY_FORK
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
unset TOY_FORK
if [ "$rc" = "2" ] && echo "$o" | grep -q "boundary_without_oracle"; then
    echo "ok   the same quiet fork is UNKNOWN without an oracle (exit 2)"
    reasons="$reasons boundary_without_oracle"
else
    echo "FAIL boundary without oracle: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

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

# ---- #134: the falsification gate's child output is labeled per line ----
# The gate produces, by design, exactly the output a real finding would — a target
# failing over a broken store — and one unlabeled gate line was harvested as world
# evidence (the buku correction, PR #133). The buggy run above has the checker
# speaking in BOTH places: over the gate's corruption probe (must carry the
# `falsify: ` prefix on every line) and in a failing world (must stay unlabeled).
# Both sides are counted, not just grepped: a silent checker would make a
# presence-only check pass vacuously.
gate_n=$(printf '%s\n' "$o" | grep -c "^falsify: doctor says" || true)
world_n=$(printf '%s\n' "$o" | grep -c "^doctor says" || true)
if [ "${gate_n:-0}" -ge 1 ] && [ "${world_n:-0}" -ge 1 ]; then
    echo "ok   gate output labeled (falsify: x$gate_n), world checker output unlabeled (x$world_n)"
else
    echo "FAIL #134 labeling: gate falsify-lines=$gate_n world unlabeled-lines=$world_n"
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

# A blocked capture must not read as a red checker. The capture stub _exit(126)s
# when it cannot open the capture file; before this was discriminated, a directory
# squatting on the capture path made /bin/true — a checker that can never fail —
# pass the gate (R1 of #134, measured on the default world-writable /tmp work dir).
rm -rf /tmp/acc && mkdir -p /tmp/acc/state /tmp/acc/work/falsify-check.txt
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check /bin/true \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "could not open its stdout capture"; then
    echo "ok   a blocked falsify capture refuses loudly instead of reading as a red checker (exit 2)"
else
    echo "FAIL blocked falsify capture: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
unset TOY

echo ""
echo "=========== check 2ex: a self-exec chain is judged; its escapes are refused (#123) ==========="
# The v10 slice, both sides at once. The planted bug must be FOUND across the image
# change (a verdict, not a refusal, and exit 1 exactly — a different-reason UNKNOWN
# must not satisfy this), the child-exec shape must stay refused, and the chain that
# escapes interposition (execl carries no count) must be caught as renumbering.
TOY=$OUT/toy-bug
export TOY
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_SELFEXEC=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "oracle      agreed" && echo "$o" | grep -q "^FAIL" && echo "$o" | grep -q "image replaced"; then
    echo "ok   the planted bug is found across a self-exec, oracle agreeing, image change disclosed (exit 1)"
else
    echo "FAIL self-exec judged run: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
# The second image appended to the same trace; the header guard must have kept it
# to ONE header (a second header would be a mid-file version stamp nothing parses).
hdrs=$(python3 -c "print(open('/tmp/acc/work/trace-record.bin','rb').read().count(b'SIDEEYE1'))" 2>/dev/null || echo 0)
if [ "$hdrs" = "1" ]; then
    echo "ok   one trace header across the image change"
else
    echo "FAIL trace header count across self-exec: $hdrs"
    fails=$((fails + 1))
fi

TOY=$OUT/toy-fixed
export TOY
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_FORKEXEC=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "child_touched_state_dir"; then
    echo "ok   a child that execs and writes stays refused (exit 2)"
else
    echo "FAIL fork+exec refusal: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXECL=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "announced itself again without an exec record"; then
    echo "ok   an uninterposed exec is caught structurally by the double announcement (exit 2)"
else
    echo "FAIL execl uninterposed: exit $rc"
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
# 5, not 6: close is recorded but no longer compared (ADR 0003), so the agreed set for
# the buggy rotate is open, write, fsync, unlink, rename.
if echo "$o" | grep -q "agreed on 5 operations" && [ "${scanned:-0}" -gt 10 ]; then
    echo "ok   the oracle agreed on 5 operations over $scanned examined lines"
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
if [ "$rc" = "0" ] && echo "$o" | grep -q "nothing that can change" \
    && echo "$o" | grep -q "expected status: 0"; then
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

# The trigger used to be a missing --shim; #78 turned that into a default (the shim
# is found beside the binary — check 9), so a missing --state carries the torch.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --operation "$OUT/toy-bug rotate" --shim "$SHIM" \
    --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
rc=$?
if [ "$rc" = "3" ]; then
    echo "ok   a missing --state is SETUP ERROR (exit 3)"
else
    echo "FAIL missing --state: exit $rc, wanted 3"
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

# How many records of one op class a trace holds, with a real decoder — grep succeeds on
# garbage, and both callers exist to prove a record is (or is not) present.
count_op_records() { python3 -c '
import struct, sys
try:
    b = open(sys.argv[1], "rb").read()
except OSError:
    print(0); raise SystemExit
want = int(sys.argv[2])
i, n = 12, 0
while i + 14 <= len(b):
    op, seq, pid, plen = struct.unpack_from("<HIII", b, i); i += 14 + plen
    if i + 4 > len(b): break
    (alen,) = struct.unpack_from("<I", b, i); i += 4 + alen
    if op == want: n += 1
print(n)' "$1" "$2"; }

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
# `boundary_without_oracle` is that proof: the shim can only record the fork after the
# operation started and forked, and this run carries no oracle. Without this, a run that
# died in setup would leave no late.txt and the check would pass having measured nothing.
if [ "$rc" != "2" ] || ! echo "$o" | grep -q "boundary_without_oracle"; then
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
fork_recs=$(count_op_records /tmp/acc/vfork-trace.bin 200)
if [ "${fork_recs:-0}" -ge 1 ]; then
    echo "ok   the vfork call itself was recorded ($fork_recs fork-class record)"
else
    echo "FAIL no fork-class record in the trace: the vfork interposition is not recording"
    fails=$((fails + 1))
fi

# 3. And the verdict describes the target, not the observation. With boundary tolerance
# a vfork+exec whose child touches nothing is explorable: the planted bug must surface
# at the same crash point as the boundary-free run. `recording_run_failed` here would
# mean the target died under observation and was blamed for it — the original defect.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_VFORK=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   a vfork+exec target is explored, reaching the same crash point"
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
echo "=========== check 2s: a read-only open is not an address ==========="
# ADR 0003: a write-incapable open cannot change state, so the world killed immediately
# before it is byte-identical to the world killed at the next address. TOY_READ_FIRST
# reads the key (one read-only open) before rotating; the crash point count and the
# verdict must be identical to the plain rotate. Under the old rules the read consumed
# crash point 1 and this run reported 6 of 6 — that is the red this check replaces.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_READ_FIRST=1 export TOY_READ_FIRST
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
unset TOY_READ_FIRST
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   the read-first rotate reaches the same crash point count as the plain one"
else
    echo "FAIL read-first rotate: exit $rc (wanted the plain rotate's 5 of 5)"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The close exclusion is from the *comparison*, not from the trace: the recording must
# survive, or the exclusion has quietly become a removal. Counted with a real decoder.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acc/state "$OUT/toy-bug" init >/dev/null 2>&1
rm -f /tmp/acc/close-trace.bin
TOY_STATE=/tmp/acc/state LD_PRELOAD="$SHIM" \
    SIDEEYE_STATE_DIR=/tmp/acc/state SIDEEYE_TRACE_PATH=/tmp/acc/close-trace.bin \
    "$OUT/toy-bug" rotate >/dev/null 2>&1
close_recs=$(count_op_records /tmp/acc/close-trace.bin 100)
if [ "${close_recs:-0}" -ge 1 ]; then
    echo "ok   close is still recorded in the trace ($close_recs record)"
else
    echo "FAIL no close record in the trace: the comparison exclusion became a removal"
    fails=$((fails + 1))
fi

echo "=========== check 2t: the history-preservation form (ADR 0004) ==========="
# TOY_APPEND appends one line whose bytes no run repeats (pid + monotonic clock), in
# several small writes. Under pre-or-post alone the re-run baseline can never match the
# recorded final, so the run is structurally UNKNOWN — the measured wall of the first
# real target (#24). Under the history form it passes, judged only on whether the bytes
# that predate the operation survive. The counts are asserted exactly: the state also
# holds key.json, whose post *diverges* from its pre, so an implementation that applies
# the prefix rule to every changed file reports "0 path(s) judged pre-or-post" here and
# goes red.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_APPEND=1 export TOY_APPEND
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/report.json 2>&1)
rc=$?
unset TOY_APPEND
if [ "$rc" = "0" ] && echo "$o" | grep -qF "1 path(s) judged pre-or-post; 1 file(s) judged by the history form (appended tails not judged): log.txt"; then
    echo "ok   a nondeterministic append passes, named and counted under the history form"
else
    echo "FAIL append toy: exit $rc (wanted PASS naming exactly log.txt under the history form)"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
# DESIGN §13: the JSON carries the same claim, and the untested set widened with it.
if python3 -c '
import json, sys
d = json.load(open("/tmp/acc/report.json"))
assert d["l0"] == "1 path(s) judged pre-or-post; 1 file(s) judged by the history form (appended tails not judged): log.txt", d["l0"]
assert "appended tails (files under the history form)" in d["not_tested"], d["not_tested"]
' 2>/dev/null; then
    echo "ok     ...and the JSON agrees, with appended tails in not_tested"
else
    echo "FAIL the JSON l0/not_tested does not match the text claim"
    fails=$((fails + 1))
fi

# The same final content produced the way history dies: read all, ftruncate, write
# back. The world killed between the truncate and the first write holds an empty file —
# history gone — and the verdict must be a FAIL whose window reads "after truncate".
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_APPEND_REWRITE=1 export TOY_APPEND_REWRITE
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
unset TOY_APPEND_REWRITE
if [ "$rc" = "1" ] && echo "$o" | grep -q "no longer a prefix" && echo "$o" | grep -q "after  truncate"; then
    echo "ok   rewriting history FAILs at the truncate window"
else
    echo "FAIL rewrite toy: exit $rc (wanted FAIL with 'no longer a prefix' after truncate)"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The boundary of the relaxation: a rewrite that no run repeats is NOT an extension,
# stays on pre-or-post, and still refuses — the history form must not leak to it.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_NONDET_REWRITE=1 export TOY_NONDET_REWRITE
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/report.json 2>&1)
rc=$?
unset TOY_NONDET_REWRITE
if [ "$rc" = "2" ] && echo "$o" | grep -q "baseline_violates_invariant" \
        && echo "$o" | grep -qF "atomicity   2 path(s) judged pre-or-post"; then
    echo "ok   a nondeterministic rewrite still refuses, and the UNKNOWN text says what was classified"
else
    echo "FAIL nondet-rewrite toy: exit $rc (wanted UNKNOWN baseline_violates_invariant + the atomicity line)"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
# The UNKNOWN's JSON still says what was classified — and that nothing was history.
if python3 -c '
import json, sys
d = json.load(open("/tmp/acc/report.json"))
assert d["l0"] == "2 path(s) judged pre-or-post", d["l0"]
' 2>/dev/null; then
    echo "ok     ...and its JSON reports the classification (no history files)"
else
    echo "FAIL the UNKNOWN JSON l0 note is wrong or missing"
    fails=$((fails + 1))
fi

echo "=========== check 2u: stdio is observed at flush granularity (ADR 0005) ==========="
# The wall the calibration sweep measured (#30): libc-internal calls never cross the
# PLT, so a target writing through stdio was invisible to the shim and every such run
# refused as oracle_missed_operation. The stream wrappers observe the flush — the one
# place where stdio granularity and syscall granularity coincide. Asserted with the
# real decoder, not grep: the recorded kill-point sequence must be exactly the
# syscalls the oracle sees, in order, with the right paths.
kill_sequence() { python3 -c '
import struct, sys
b = open(sys.argv[1], "rb").read()
names = {1:"open",2:"write",3:"rename",4:"unlink",5:"fsync",6:"truncate",7:"mkdir",8:"rmdir",9:"link"}
i, out = 12, []
while i + 14 <= len(b):
    op, seq, pid, plen = struct.unpack_from("<HIII", b, i); i += 14
    path = b[i:i+plen].decode("utf-8", "replace"); i += plen
    if i + 4 > len(b): break
    (alen,) = struct.unpack_from("<I", b, i); i += 4 + alen
    if op in names:
        out.append(names[op] + ":" + path.rsplit("/", 1)[-1])
print(" ".join(out))' "$1"; }

stdio_case() { # $1 label, $2 env var, $3 toy, $4 expected kill sequence
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$(env "$2=1" "$SIDEEYE" explore --state /tmp/acc/state \
        --setup "$3 init" --operation "$3 rotate" \
        --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
    rc=$?
    seq_got=$(kill_sequence /tmp/acc/work/trace-record.bin)
    if [ "$rc" = "0" ] && [ "$seq_got" = "$4" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: exit $rc"
        echo "     | want: $4"
        echo "     | got:  $seq_got"
        echo "$o" | sed 's/^/     | /' | head -8
        fails=$((fails + 1))
    fi
}

rotate_tail="open:key.json.tmp write:key.json.tmp fsync:key.json.tmp rename:key.json.tmp"
stdio_case "the COMMIT_EDITMSG shape passes ('r' consumes no address)" TOY_STDIO "$OUT/toy-fixed" \
    "open:stdio.txt write:stdio.txt $rotate_tail"
stdio_case "  ...and identically through the fopen64 alias (LFS build)" TOY_STDIO "$OUT/toy-lfs" \
    "open:stdio.txt write:stdio.txt $rotate_tail"
stdio_case "every fflush with pending bytes is one write address; the empty one is none" TOY_STDIO_FLUSH "$OUT/toy-fixed" \
    "open:stdio.txt write:stdio.txt write:stdio.txt write:stdio.txt $rotate_tail"
stdio_case "freopen with pending bytes records [write, close, open] in syscall order" TOY_STDIO_FREOPEN "$OUT/toy-fixed" \
    "open:stdio-a.txt write:stdio-a.txt open:stdio-b.txt write:stdio-b.txt $rotate_tail"
# The taskwarrior shape: an "r+" stream made dirty, then fseek — libc flushes inside
# the seek, so the seek family are flush points. Missing this cost the first dogfood
# run its verdict.
stdio_case "repositioning a dirty stream is a write address (the seek-flush)" TOY_STDIO_SEEK "$OUT/toy-fixed" \
    "open:stdio-seek.txt write:stdio-seek.txt $rotate_tail"

# The freopen kill worlds must be honest, not just its recording sequence: the wrapper
# flushes explicitly before recording the close/open pair, so a kill aimed at the new
# open (kill point 3: open-a, write-a, open-b) lands with the pending flush already
# durable. Without the interleave every record precedes the one real call, the flush
# never happens, and this world's file is empty while its address claims the write did.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_STATE=/tmp/acc/state "$OUT/toy-fixed" init >/dev/null 2>&1
rm -f /tmp/acc/fr-trace.bin
env TOY_STDIO_FREOPEN=1 TOY_STATE=/tmp/acc/state LD_PRELOAD="$SHIM" \
    SIDEEYE_STATE_DIR=/tmp/acc/state SIDEEYE_TRACE_PATH=/tmp/acc/fr-trace.bin \
    SIDEEYE_KILL_AT=3 "$OUT/toy-fixed" rotate >/dev/null 2>&1
landed=$(count_op_records /tmp/acc/fr-trace.bin 901)
if [ "${landed:-0}" = "1" ] && [ "$(cat /tmp/acc/state/stdio-a.txt 2>/dev/null)" = "into a" ]; then
    echo "ok   a kill at freopen's new open lands after the pending flush is durable"
else
    echo "FAIL freopen kill world: landed=$landed content='$(cat /tmp/acc/state/stdio-a.txt 2>/dev/null)'"
    fails=$((fails + 1))
fi

# The boundary, pinned from both sides: what bypasses the flush path must refuse, not
# quietly miscount. An overflow flush happens inside fprintf; an exit-time flush
# happens inside libc's cleanup. Neither crosses the wrappers.
for pair in "TOY_STDIO_BIG:a buffer overflow inside fprintf" "TOY_STDIO_NOCLOSE:an exit-time flush of a never-closed stream"; do
    var=${pair%%:*}; desc=${pair#*:}
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$(env "$var=1" "$SIDEEYE" explore --state /tmp/acc/state \
        --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
        --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
    rc=$?
    if [ "$rc" = "2" ] && echo "$o" | grep -q "oracle_missed_operation"; then
        echo "ok   $desc still refuses (outside the modelled boundary)"
    else
        echo "FAIL $var: exit $rc (wanted UNKNOWN oracle_missed_operation)"
        echo "$o" | sed 's/^/     | /' | head -6
        fails=$((fails + 1))
    fi
done

echo "=========== check 2v: typed path resolution and first-class links (ADR 0006) ==========="
# git's last wall (#31): the oracle scoped by scanning the whole line for an absolute
# state-directory string, so a relative mkdir/link with only a dirfd annotation was
# dropped — a fail-open of "refuse what you cannot see". Scope is now decided from
# resolved paths, and link is a first-class kill point.
link_tail="open:obj.tmp write:obj.tmp fsync:obj.tmp link:obj.tmp unlink:obj.tmp $rotate_tail"
stdio_case "the loose-object idiom passes, link recorded as a kill point" TOY_LINK "$OUT/toy-fixed" \
    "$link_tail"
# Spelling invariance: the same idiom spelled relative (after chdir into the state
# directory) resolves to the same operations. On aarch64 strace annotates the cwd; on
# x86-64 (CI) the legacy syscalls carry no annotation and the tracked cwd is what
# resolves them — so this case is where CI measures the cwd tracking.
stdio_case "  ...and identically when spelled relative (cwd tracking)" TOY_RELATIVE "$OUT/toy-fixed" \
    "$link_tail"
# outside -> state: a two-path operation touches the state directory when either end is
# inside. The recorded path is the source (outside), so the sequence leads with the link.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(env TOY_LINK_IN=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
link_recs=$(count_op_records /tmp/acc/work/trace-record.bin 9)
if [ "$rc" = "0" ] && [ "${link_recs:-0}" = "1" ]; then
    echo "ok   an outside->state link is counted (the either-endpoint rule)"
else
    echo "FAIL link-in: exit $rc, link records ${link_recs:-0} (wanted PASS with 1 link)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# A symlink inside the state directory is a first-class operation since contract v9
# (#122): the shim records the link path as a kill point (class 10), the engine
# restores links between worlds, and the run reaches a verdict. This is the one place
# CI proves the Linux shim wrapper end-to-end. Seen red: this exact run answered
# UNKNOWN unsupported_syscall_observed under the pre-v9 binary — the assertion this
# block replaced.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(env TOY_SYMLINK=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
sym_recs=$(count_op_records /tmp/acc/work/trace-record.bin 10)
if [ "$rc" = "0" ] && [ "${sym_recs:-0}" = "1" ]; then
    echo "ok   a symlink inside the state directory is a recorded kill point (v9)"
else
    echo "FAIL symlink: exit $rc, symlink records ${sym_recs:-0} (wanted PASS with 1 symlink record)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo "=========== check 2w: remove(3) is observed, attempt for attempt ==========="
# The timewarrior wall: libc implements remove(3) as unlink — then rmdir on the
# directory errno — internally, without crossing the PLT, so a shim that only
# interposes unlink is blind to every removal made through it while the oracle sees
# the syscalls; the run refused as oracle_missed_operation. The shim now reimplements
# remove through its own wrappers, so the recorded sequence matches strace attempt for
# attempt: the failed remove of a never-created path is an address on both accounts
# (timewarrior's AtomicFile cleanup does exactly that at every exit), and a directory
# shows glibc's failed unlink probe before the rmdir lands.
stdio_case "remove(3) of a file, a missing path, and a directory" TOY_REMOVE "$OUT/toy-fixed" \
    "open:scratch.txt write:scratch.txt unlink:scratch.txt unlink:never-made.tmp mkdir:subdir unlink:subdir rmdir:subdir $rotate_tail"

echo "=========== check 2w-b: ownership/permission writes are recorded-only (#121) ==========="
# The devtodo shape from the #118 cohort: one chmod on a state file sent the whole
# run to unsupported_syscall_observed. Option b: the oracle observes it, the verdict
# excludes it, and the report says so — text and JSON alike. Seen red: this exact
# run answered UNKNOWN unsupported_syscall_observed under the pre-#121 binary (the
# refusal this check replaces). The name is asserted as a substring so glibc's
# chmod-vs-fchmodat spelling choice cannot flake it — both contain "chmod".
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(env TOY_CHMOD=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/meta.json 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "ownership/permission write(s) observed and excluded"; then
    echo "ok   a chmod on state is excluded from judgement and named in the text report"
else
    echo "FAIL chmod: exit $rc (wanted PASS with the metadata note)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
if python3 - <<'PYEOF'
import json
d = json.load(open('/tmp/acc/meta.json'))
assert 'observed and excluded' in d['metadata_writes'], d['metadata_writes']
assert 'chmod' in d['metadata_writes'], d['metadata_writes']
PYEOF
then
    echo "ok   the JSON carries the same exclusion, syscall named"
else
    echo "FAIL the JSON metadata_writes field disagrees with the text"
    fails=$((fails + 1))
fi
# Control, same binary: an UNSUPPORTED state-touching syscall must still refuse —
# the exclusion is a defined list, not a loosened net. mknod is the nearest neighbour.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(env TOY_MKNOD=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "unsupported_syscall_observed" && echo "$o" | grep -q "mknod"; then
    # The name is asserted too ("mknod" is a substring of "mknodat", so glibc's
    # spelling choice cannot flake it): a refusal for some OTHER reason must not
    # count as the net being alive.
    echo "ok   the conservative net is still alive beside the exclusion (mknod refuses, by name)"
else
    echo "FAIL mknod control: exit $rc (wanted UNKNOWN unsupported_syscall_observed naming mknod)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2x: sideeye.toml is the define surface, and it fails closed ==========="
# ADR 0007: the file owns state/setup/operation/check; what the parser accepts is the
# width of the contract, so unknown keys, bare values and flag/file mixing refuse with
# the offending line named. `marker` doubles as the unknown-key probe on purpose — it
# must refuse until the change that makes L1 enforce it lands, because a key that
# parses before it acts is a declared invariant that silently never fires.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
flags_out=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
flags_verdict=$(echo "$flags_out" | grep "^PASS" | head -1)
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
cat > /tmp/acc/sideeye.toml <<TOML
[world]
state = "./state"                       # resolves against this file's directory
[define]
setup     = "$OUT/toy-fixed init"
operation = "$OUT/toy-fixed rotate"
TOML
toml_out=$("$SIDEEYE" explore --config /tmp/acc/sideeye.toml \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
toml_verdict=$(echo "$toml_out" | grep "^PASS" | head -1)
if [ -n "$toml_verdict" ] && [ "$toml_verdict" = "$flags_verdict" ]; then
    echo "ok   a toml-driven run reaches the very verdict the flags reach"
else
    echo "FAIL toml equivalence:"
    echo "     | flags: $flags_verdict"
    echo "     | toml:  $toml_verdict"
    echo "$toml_out" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

toml_refusal() { # $1 label, $2 toml body, $3 expected fragment
    printf '%s\n' "$2" > /tmp/acc/bad.toml
    o=$("$SIDEEYE" explore --config /tmp/acc/bad.toml --shim "$SHIM" --work /tmp/acc/work 2>&1)
    rc=$?
    if [ "$rc" = "3" ] && echo "$o" | grep -q "$3"; then
        echo "ok   $1"
    else
        echo "FAIL $1: exit $rc (wanted SETUP ERROR containing '$3')"
        echo "$o" | sed 's/^/     | /' | head -4
        fails=$((fails + 1))
    fi
}
toml_refusal "an unknown key refuses with its line" \
'[world]
state = "./state"
[define]
operation = "x"
budget = "x"' "line 5: unknown key"
toml_refusal "a bare value refuses" \
'[world]
state = ./state' "line 2"
o=$("$SIDEEYE" explore --config /tmp/acc/sideeye.toml --operation "x" --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "mutually exclusive"; then
    echo "ok   --config and a define-surface flag refuse together"
else
    echo "FAIL config/flag exclusivity: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi
# The argv form's boundary (#95, ADR 0019), through the binary: the unit tests pin
# every refusal branch; these four prove the same walls stand at the CLI, line named.
toml_refusal "the argv form refuses an unclosed bracket" \
'[world]
state = "./state"
[define]
operation = ["a", "b"' "line 4: .*does not close"
toml_refusal "the argv form refuses a trailing comma" \
'[world]
state = "./state"
[define]
operation = ["a",]' "trailing comma"
toml_refusal "the argv form refuses an empty array" \
'[world]
state = "./state"
[define]
operation = []' "the array is empty"
toml_refusal "a non-command key refuses the array form by name" \
'[world]
state = ["./state"]' "belongs to the commands"

echo "=========== check 2y: the L1 success marker is a strict subset, never a leak (ADR 0008) ==========="
# The post-success invariant fires only in worlds where the operation's own claim
# reached stdout before the kill: some worlds but never all (anti-vacuity, both ways),
# the whole post snapshot is judged there (a created file that vanished is a FAIL),
# and a marker the clean run cannot produce is UNKNOWN — not a silent vacuous PASS.
l1_case() { # $1 label, $2 env, $3 marker, $4 want_exit, $5.. want_text fragments
    lbl=$1; envv=$2; mkr=$3; want=$4; shift 4
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$(env "$envv=1" "$SIDEEYE" explore --state /tmp/acc/state \
        --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
        --shim "$SHIM" --work /tmp/acc/work --marker "$mkr" --oracle /usr/bin/strace 2>&1)
    rc=$?
    ok=1
    [ "$rc" = "$want" ] || ok=0
    for frag in "$@"; do echo "$o" | grep -q "$frag" || ok=0; done
    if [ "$ok" = "1" ]; then
        echo "ok   $lbl"
    else
        echo "FAIL $lbl: exit $rc (wanted $want)"
        echo "$o" | sed 's/^/     | /' | head -8
        fails=$((fails + 1))
    fi
}
l1_case "the correct shape passes, marker observed in some but not all crash worlds" \
    TOY_MARKER COMMITTED 0 "marker observed in"
# Anti-vacuity, numerically: 0 < observed < crash points, read from the report itself.
mw=$(echo "$o" | sed -n 's/.*marker observed in \([0-9]*\) of \([0-9]*\) crash worlds.*/\1 \2/p' | head -1)
mn=${mw% *}; mt=${mw#* }
if [ -n "$mw" ] && [ "$mn" -gt 0 ] && [ "$mn" -lt "$mt" ]; then
    echo "ok   ...and 0 < $mn < $mt"
else
    echo "FAIL l1 anti-vacuity bounds: got '$mw'"
    fails=$((fails + 1))
fi
l1_case "the claim-before-commit shape fails as not durable" \
    TOY_MARKER_EARLY COMMITTED 1 "post-success invariant" "did not survive"
l1_case "a created file missing from a marker world fails (the whole post snapshot is judged)" \
    TOY_MARKER_CREATES COMMITTED 1 "post-success invariant" "receipt.txt"
l1_case "a marker the clean run cannot produce is UNKNOWN, not a vacuous PASS" \
    TOY_MARKER NEVER_SAID 2 "marker_never_observed"
l1_case "an unflushed marker is honestly vacuous: observed in 0 crash worlds, still PASS" \
    TOY_MARKER_NOFLUSH COMMITTED 0 "marker observed in 0 of"

echo "=========== check 2z: a saved case replays honestly (ADR 0009) ==========="
# A FAIL saves its counterexample; replaying it re-runs the same pipeline restricted
# to that crash point plus the baseline — the trust gates included. A recording whose
# landing context changed answers "case no longer applies", never a verdict about a
# shifted address; and a replayed define whose checker cannot be falsified refuses
# exactly like an explore would (the gate-preservation probe).
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
case_file=/tmp/acc/work/cases/000001.json
if [ -s "$case_file" ] && echo "$o" | grep -q "replay      sideeye replay"; then
    echo "ok   a FAIL saves its case and prints the replay command"
else
    echo "FAIL case saving: file or replay line missing"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi
o=$("$SIDEEYE" replay "$case_file" --shim "$SHIM" --work /tmp/acc/work-r --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash worlds violated" && echo "$o" | grep -q "the case reproduced"; then
    echo "ok   an unchanged target reproduces the case (FAIL)"
else
    echo "FAIL replay reproduction: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi
o=$(env TOY_EXTRA_FIRST=1 "$SIDEEYE" replay "$case_file" --shim "$SHIM" --work /tmp/acc/work-r2 --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "case_no_longer_applies" && ! echo "$o" | grep -qE "^(PASS|FAIL)"; then
    echo "ok   a prefix insertion refuses as 'case no longer applies', with no verdict"
else
    echo "FAIL replay context guard: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
python3 - "$case_file" /tmp/acc/gated-case.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["define"]["check"] = "/bin/true"   # a checker falsification can never pass
json.dump(c, open(sys.argv[2], "w"))
PY
o=$("$SIDEEYE" replay /tmp/acc/gated-case.json --shim "$SHIM" --work /tmp/acc/work-r3 --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "checker_not_falsified"; then
    echo "ok   the trust gates run inside a replay (an unfalsifiable checker refuses)"
    reasons="$reasons case_no_longer_applies"
else
    echo "FAIL replay gate preservation: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo "=========== check 2aa: the DESIGN §12 worked example, driven by the toml alone ==========="
# The doctor cross-examination — the flagship L2 scenario — end to end with the define
# coming entirely from a sideeye.toml: the file, one checker script, nothing else. The
# PRD's v0.3 acceptance names exactly this run.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
cat > /tmp/acc/sideeye.toml <<TOML
[world]
state = "./state"
[define]
setup     = "$OUT/toy-bug init"
operation = "$OUT/toy-bug rotate"
check     = "$ROOT/spike/check.sh"
TOML
o=$(TOY="$OUT/toy-bug" "$SIDEEYE" explore --config /tmp/acc/sideeye.toml \
    --shim "$SHIM" --work /tmp/acc/work --json /tmp/acc/report.json --oracle /usr/bin/strace 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
echo "$o" | grep -q "checker" || ok=0
echo "$o" | grep -q "falsified before the run" || ok=0
[ -s /tmp/acc/work/cases/000001.json ] || ok=0
if [ "$ok" = "1" ]; then
    echo "ok   the doctor scenario runs end-to-end from a toml define (FAIL, falsified checker, case saved)"
else
    echo "FAIL toml-driven doctor scenario: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
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
if [ "$distinct" -lt 12 ]; then
    echo "FAIL: expected at least twelve distinct detectors, got $distinct"
    fails=$((fails + 1))
else
    echo "ok   $distinct different detectors fired"
fi

echo ""
echo "=========== check 2ab: the argv form spells what split-on-space cannot (#95, ADR 0019) ==========="
# The toy's rotate-msg demands ONE argv element "note with spaces". The negative
# control runs first and from the same define material: the string form splits that
# argument into three, the toy refuses before touching state, and the recording run
# fails — the exact UNKNOWN the sweep measured on hnb. The array form then reaches
# the toy verbatim: the BUGGY rotate explores to FAIL, the saved case is
# case_version 3 with the operation as a JSON array, and that case replays in a
# fresh work directory. Finally a v2 case hand-edited to carry an argv-form command
# refuses: the shape arrived with version 3, and version and shape travel together.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
cat > /tmp/acc/spacearg-str.toml <<TOML
[world]
state = "./state"
[define]
setup     = "$OUT/toy-bug init"
operation = "$OUT/toy-bug rotate-msg note with spaces"
TOML
o=$("$SIDEEYE" explore --config /tmp/acc/spacearg-str.toml \
    --shim "$SHIM" --work /tmp/acc/work-str --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "recording_run_failed"; then
    echo "ok   the string form cannot spell the spaced argument (UNKNOWN, recording run failed)"
else
    echo "FAIL string-form control: exit $rc (wanted 2 + recording_run_failed)"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
cat > /tmp/acc/spacearg.toml <<TOML
[world]
state = "./state"
[define]
setup     = "$OUT/toy-bug init"
operation = ["$OUT/toy-bug", "rotate-msg", "note with spaces"]
TOML
o=$("$SIDEEYE" explore --config /tmp/acc/spacearg.toml \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
spacecase=/tmp/acc/work/cases/000001.json
case_ok=0
grep -q '"case_version": 3' "$spacecase" 2>/dev/null \
    && grep -q '"operation": \["' "$spacecase" 2>/dev/null && case_ok=1
o2=$("$SIDEEYE" replay "$spacecase" --shim "$SHIM" --work /tmp/acc/work-r 2>&1)
rc2=$?
if [ "$rc" = "1" ] && [ "$case_ok" = "1" ] && [ "$rc2" = "1" ] \
    && echo "$o2" | grep -q "the case reproduced"; then
    echo "ok   the argv form explores to FAIL, saves a v3 case, and the case replays"
else
    echo "FAIL argv-form round-trip: explore=$rc case_fields=$case_ok replay=$rc2"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi
# Both arms of the pairing gate, each pinned to its message — a bare exit-3 match
# would also be satisfied by an unreadable fixture that was never written.
python3 - "$spacecase" /tmp/acc/v2-with-argv.json /tmp/acc/v1-with-argv.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
a = json.loads(json.dumps(c)); a["case_version"] = 2
json.dump(a, open(sys.argv[2], "w"))
b = json.loads(json.dumps(c)); b["case_version"] = 1; del b["define"]["expected_status"]
json.dump(b, open(sys.argv[3], "w"))
PY
o3=$("$SIDEEYE" replay /tmp/acc/v2-with-argv.json --shim "$SHIM" --work /tmp/acc/work-r2 2>&1)
rc3=$?
o4=$("$SIDEEYE" replay /tmp/acc/v1-with-argv.json --shim "$SHIM" --work /tmp/acc/work-r3 2>&1)
rc4=$?
if [ "$rc3" = "3" ] && echo "$o3" | grep -q "cannot carry an argv-form command" \
    && [ "$rc4" = "3" ] && echo "$o4" | grep -q "cannot carry an argv-form command"; then
    echo "ok   a v1 or v2 case carrying an argv-form command refuses (the shape arrived with v3)"
else
    echo "FAIL argv pairing gate: v2=$rc3 v1=$rc4 (wanted 3 + the named refusal, both)"
    echo "$o3" | sed 's/^/     | /' | head -2
    fails=$((fails + 1))
fi

echo "=========== check 3b: traces are identical up to pid renaming ==========="
# v0.1 claimed the recording run's trace was byte-identical across runs. v3 puts a pid
# in every record, and pids differ between runs by nature — so the claim becomes:
# identical after replacing each pid with its order of first appearance. Decoded with a
# real parser; the sequence includes op, seq and the normalised pid, so a record moving
# between processes cannot hide.
norm_trace() { python3 -c '
import struct, sys
b = open(sys.argv[1], "rb").read()
i, out, pids = 12, [], {}
while i + 14 <= len(b):
    op, seq, pid, plen = struct.unpack_from("<HIII", b, i); i += 14 + plen
    if i + 4 > len(b): break
    (alen,) = struct.unpack_from("<I", b, i); i += 4 + alen
    out.append("%d:%d:p%d" % (op, seq, pids.setdefault(pid, len(pids))))
print(" ".join(out))' "$1"; }

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
TOY_FORK=1 export TOY_FORK
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
t1=$(norm_trace /tmp/acc/work/trace-record.bin)
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
t2=$(norm_trace /tmp/acc/work/trace-record.bin)
unset TOY_FORK
if [ -n "$t1" ] && [ "$t1" = "$t2" ]; then
    echo "ok   two recording runs agree after pid normalisation ($(echo "$t1" | wc -w | tr -d ' ') records)"
else
    echo "FAIL normalised traces differ (or are empty)"
    echo "     | $t1"
    echo "     | $t2"
    fails=$((fails + 1))
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

echo "=========== check 4: the report schema page is held to the generated reports ==========="
# docs/report-schema.md promises three things this check enforces: every field a
# generated report carries is documented, every documented field is generatable,
# and the unknown_reason list matches the contract's enum. Four fresh reports
# cover all four verdicts; the comparison is a script taking paths, so the doc
# side can be falsified in isolation (mutate a copy, watch it go red).
SD=/tmp/acc-schema
rm -rf "$SD" && mkdir -p "$SD/s1" "$SD/s2" "$SD/s3" "$SD/s4"
TOY_STATE=$SD/s1 "$SIDEEYE" explore --state "$SD/s1" \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work "$SD/w1" --oracle /usr/bin/strace --json "$SD/pass.json" >/dev/null 2>&1
TOY_STATE=$SD/s2 "$SIDEEYE" explore --state "$SD/s2" \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work "$SD/w2" --oracle /usr/bin/strace --json "$SD/fail.json" >/dev/null 2>&1
# UNKNOWN needs the would-be-PASS path: a FAIL stands without the oracle, but a
# PASS without completeness refuses — so the fixed toy, oracle-less, is the recipe.
TOY_STATE=$SD/s3 "$SIDEEYE" explore --state "$SD/s3" \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work "$SD/w3" --json "$SD/unknown.json" >/dev/null 2>&1
TOY_STATE=$SD/s4 "$SIDEEYE" explore --state "$SD/s4" \
    --setup "/bin/false" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work "$SD/w4" --json "$SD/setup.json" >/dev/null 2>&1
if python3 "$ROOT/spike/check-report-schema.py" "$ROOT/docs/report-schema.md" "$ROOT/src/contract.zig" \
    "$SD/pass.json" "$SD/fail.json" "$SD/unknown.json" "$SD/setup.json"; then
    echo "ok   the schema page, the generated reports, and the contract enum agree"
else
    echo "FAIL the report schema page drifted from the reports (or the reports from the page)"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 5: sideeye demo — a first success that needs nothing written ==========="
# The demo compiles its embedded planted-bug toy with this machine's C compiler and
# self-execs an exploration. Expected exit is 1 — the planted bug found — which is what
# makes it a smoke test of the binary + shim pair. The window has to be named: a demo
# that "failed" without the counterexample would be smoke-testing nothing. No --shim:
# the sibling/../lib discovery is part of what this check pins.
o=$("$SIDEEYE" demo 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
echo "$o" | grep -q "after  unlink(" || ok=0
echo "$o" | grep -q "before rename(" || ok=0
echo "$o" | grep -q "falsified before the run" || ok=0
if [ "$ok" = "1" ]; then
    echo "ok   the demo finds the planted bug (exit 1, window named, checker falsified)"
else
    echo "FAIL demo: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# The compiler ladder, exercised rather than claimed: a stub `cc` that always fails
# must make the demo fall back to gcc — and the preamble names the compiler that won.
STUB=/tmp/acc-ccstub
rm -rf "$STUB" && mkdir -p "$STUB"
printf '#!/bin/sh\nexit 1\n' > "$STUB/cc" && chmod +x "$STUB/cc"
o=$(PATH="$STUB:$PATH" "$SIDEEYE" demo 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "compiled the planted-bug tool with gcc"; then
    echo "ok   a failing cc falls back to gcc, and the preamble says so"
else
    echo "FAIL compiler fallback: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# No compiler at all: the refusal names what to install, before any exploration starts.
o=$(PATH=/nonexistent "$SIDEEYE" demo 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "needs a C compiler"; then
    echo "ok   with no compiler the demo refuses by name (exit 3)"
else
    echo "FAIL compiler-absent refusal: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 6: preflight answers before the define exists ==========="
# Three legs. Accepted: the recording-phase gates all hold on the buggy toy, and the
# claim is exactly "recording accepted" — with the exploration-only refusals named as
# not checked, and no PASS/FAIL verdict anywhere. Refused: the static toy cannot be
# observed, and the refusal carries the same detector name a real run uses (a constant
# answer cannot satisfy both legs). Honesty: a target whose recording is clean but
# whose exploration refuses (a nondeterministic rewrite dies at the baseline) must be
# accepted by preflight WITH baseline behavior named as unchecked, while explore on
# the same define refuses — the pair that keeps preflight's claim scoped to what ran.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" preflight --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
ok=1
[ "$rc" = "0" ] || ok=0
echo "$o" | grep -q "recording accepted — 5 state-changing operation(s) observed" || ok=0
echo "$o" | grep -q "not checked" || ok=0
echo "$o" | grep -q "kill landing" || ok=0
echo "$o" | grep -q "world-side process boundaries" || ok=0
echo "$o" | grep -q "baseline behavior" || ok=0
echo "$o" | grep -q "checker falsification" || ok=0
# The graduation hint must carry the define that was actually accepted — a hint
# that dropped --setup would run a silently different define (R1 finding).
echo "$o" | grep -q -- "--setup" || ok=0
echo "$o" | grep -qE "^(PASS|FAIL)" && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   preflight accepts the buggy toy's recording and names what it did not check"
else
    echo "FAIL preflight accept leg: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -10
    fails=$((fails + 1))
fi

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" preflight --state /tmp/acc/state \
    --setup "$OUT/toy-static init" --operation "$OUT/toy-static rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "no_shim_marker"; then
    echo "ok   preflight refuses the static toy with the real detector's name"
else
    echo "FAIL preflight refuse leg: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_NONDET_REWRITE=1 "$SIDEEYE" preflight --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
pf_ok=0
if [ "$rc" = "0" ] && echo "$o" | grep -q "recording accepted" && echo "$o" | grep -q "baseline behavior"; then
    pf_ok=1
fi
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
o2=$(TOY_NONDET_REWRITE=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc2=$?
if [ "$pf_ok" = "1" ] && [ "$rc2" = "2" ] && echo "$o2" | grep -q "baseline_violates_invariant"; then
    echo "ok   a recording-clean, exploration-refused target splits the claims: accepted + named unchecked vs refused"
else
    echo "FAIL preflight honesty pair: preflight=$rc explore=$rc2"
    echo "$o" | sed 's/^/     | /' | head -4
    echo "$o2" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 7: no descriptor number is exempt (contract v8) ==========="
# TOY_DUP2 writes state through fd 1, fd 2, fd 0 and a stdio leg on rebound stdout.
# Before v8 the shim skipped fd <= 2 unconditionally: measured as PASS 9/9 without an
# oracle (four invisible state writes — the false PASS) and oracle_missed_operation
# with one. Now every leg must be counted AND the oracle must agree — the agreement is
# the per-leg pin: a fix for fd 1 alone would leave the count short and the oracle
# refusing. The exact numbers (12 operations, 13 worlds) are the born-red anchors.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_DUP2=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
ok=1
[ "$rc" = "0" ] || ok=0
echo "$o" | grep -q "explored 13 worlds (crash points 12 + 1 baseline)" || ok=0
echo "$o" | grep -q "agreed on 12 operations" || ok=0
if [ "$ok" = "1" ]; then
    echo "ok   state writes through fd 0/1/2 and rebound stdio are counted, and the oracle agrees"
else
    echo "FAIL dup2 observation: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# The control: the same toy without TOY_DUP2 keeps its exact pre-v8 sequence — the
# exemption removal must not start recording ordinary stdout/stderr, whose captures
# live under --work. (The plain toy-bug counts are also pinned all over this suite.)
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
if [ "$?" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)"; then
    echo "ok   ordinary stdout/stderr are still unrecorded (location, not number, decides)"
else
    echo "FAIL plain-toy control drifted"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# --work inside the state directory is refused before anything runs: with no number
# exempt, the engine's own captures there would be observed as the target's state.
# The refusal must also leave no trace of itself — the first version planted
# <state>/work first and refused second (measured; review finding).
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/state/work 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "must not be the state directory or inside it" \
    && [ ! -e /tmp/acc/state/work ]; then
    echo "ok   --work inside the state directory refuses, and leaves nothing behind"
else
    echo "FAIL work-in-state guard: exit $rc (leftover: $(ls /tmp/acc/state 2>/dev/null | tr '\n' ' '))"
    echo "$o" | sed 's/^/     | /' | head -3
    fails=$((fails + 1))
fi

# A state directory of / contains every --work there is. The hand-rolled prefix test
# this replaced answered "outside" for it, because the character after "/" in "/tmp"
# is "t" (review finding); nothing is touched before the refusal, so the leg is safe
# to run for real.
o=$("$SIDEEYE" explore --state / \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/root-work 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "must not be the state directory or inside it"; then
    echo "ok   a root state directory contains every --work; refused"
else
    echo "FAIL root-state containment: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -3
    fails=$((fails + 1))
fi

# A case recorded under the previous contract refuses honestly. The fixture is a REAL
# case generated by the current writer with only contract_version mutated to 7 — a
# hand-written fixture could pass this check by merely failing to parse.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
"$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace >/dev/null 2>&1
python3 - /tmp/acc/work/cases/000001.json /tmp/acc/v7-case.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["contract_version"] = 7
json.dump(c, open(sys.argv[2], "w"))
PY
o=$("$SIDEEYE" replay /tmp/acc/v7-case.json --shim "$SHIM" --work /tmp/acc/work-r 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "different trace contract"; then
    echo "ok   a v7-recorded case refuses as a contract mismatch, never a verdict"
else
    echo "FAIL v7 case handling: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# The containment vet runs before --fresh-state's deletion. The first version emptied
# the state directory and only then noticed --work sat inside it (measured: a sentinel
# planted in state was gone after the rc=3); a refusal must not cost the caller their
# data. Reuses the real case recorded for the v7 leg above.
echo "sentinel" > /tmp/acc/state/sentinel.txt
o=$("$SIDEEYE" replay /tmp/acc/work/cases/000001.json --fresh-state \
    --shim "$SHIM" --work /tmp/acc/state/work 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "must not be the state directory or inside it" \
    && [ -f /tmp/acc/state/sentinel.txt ] && [ ! -e /tmp/acc/state/work ]; then
    echo "ok   the containment vet refuses before --fresh-state deletes anything"
else
    echo "FAIL fresh-state ordering: exit $rc, sentinel $([ -f /tmp/acc/state/sentinel.txt ] && echo kept || echo LOST), leftover work dir $([ -e /tmp/acc/state/work ] && echo PRESENT || echo absent)"
    echo "$o" | sed 's/^/     | /' | head -3
    fails=$((fails + 1))
fi

# Daemonize-style hygiene sweeps close descriptor numbers they never opened. Below the
# shim's relocation floor the sweep misses the trace channel entirely and the verdict
# is untouched; this leg therefore also pins that the relocation happened (a trace fd
# left at its natural low number would be swept, and the run would refuse).
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_CLOSE_SWEEP=255 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)"; then
    echo "ok   a close(3..255) sweep misses the relocated trace fd; verdict untouched"
else
    echo "FAIL sweep below the relocation floor: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# A sweep that does reach the trace fd ends observation, and the shim must say so
# while it still can — never keep writing trace records through a number the target
# now owns. Measured before the guard existed: rc=2 for the accidental reason
# state_changed_without_ops, and the state file held the shim's binary trace records
# spliced between its own bytes. The refusal must now name the channel, and the
# state file must hold exactly what the target wrote.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_CLOSE_SWEEP=1023 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "unresolvable_path" \
    && printf 'key=2\n' | cmp -s - /tmp/acc/state/key.json; then
    echo "ok   a sweep that reaches the trace fd refuses, and never corrupts state"
else
    echo "FAIL sweep at the trace fd: exit $rc, key.json $(od -c /tmp/acc/state/key.json 2>/dev/null | head -1)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# Descriptors that are provably not files — eventfd and epoll stat with zero type
# bits, the kernel's anon-inode spelling — must be invisible to the verdict. Before
# fdKind knew that spelling, one close() of an eventfd sent the whole run to
# unresolvable_path (measured), which made every epoll-based target unjudgeable.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_ANONFD=1 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)"; then
    echo "ok   anon-inode descriptors (eventfd, epoll) are invisible to the verdict"
else
    echo "FAIL anon-inode descriptors moved the verdict: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 8: a declared success status governs every un-killed run (#3, ADR 0014) ==========="
# The three states of the declaration, driven by a toy that completes all of its
# state work and then exits 3 (the git-convention shape). Undeclared: refused with
# both statuses named. Declared right: explored in full. Declared wrong: refused
# with both statuses named — "matches the run" and "was declared" are different
# facts and the diagnostics must keep them apart.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "exited 3 during the recording run where 0 was expected" \
    && echo "$o" | grep -q "expected    exit 0"; then
    echo "ok   undeclared: a non-zero convention refuses, naming expected and actual"
else
    echo "FAIL undeclared non-zero handling: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" --expect-status 3 \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)" \
    && echo "$o" | grep -q "expected status: 3"; then
    echo "ok   declared right: explores in full, and the text report names the status"
else
    echo "FAIL declared-right exploration: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" --expect-status 2 \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "exited 3 during the recording run where 2 was expected"; then
    echo "ok   declared wrong: refused, naming expected and actual"
else
    echo "FAIL declared-wrong handling: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# The config spelling of the same declaration, plus its JSON report field. One value
# must ride from the toml through the run into the report — a caller auditing a PASS
# needs to see which status it was allowed to require.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
cat > /tmp/acc/def.toml <<TOML
[world]
state = "/tmp/acc/state"
[define]
setup = "$OUT/toy-fixed init"
operation = "$OUT/toy-fixed rotate"
expected_status = "3"
TOML
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" explore --config /tmp/acc/def.toml \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/es.json 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)" \
    && python3 -c "import json,sys; sys.exit(0 if json.load(open('/tmp/acc/es.json'))['expected_status'] == 3 else 1)"; then
    echo "ok   the toml spelling explores too, and the report carries expected_status"
else
    echo "FAIL toml expected_status: exit $rc, report field: $(python3 -c "import json; print(json.load(open('/tmp/acc/es.json')).get('expected_status'))" 2>/dev/null)"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# Both spellings share one grammar: out-of-range and non-numeric refuse by name,
# in the flag and in the file alike.
bad=0
for v in 256 -1 abc; do
    "$SIDEEYE" explore --state /tmp/acc/state --operation true --expect-status "$v" \
        --shim "$SHIM" >/dev/null 2>&1
    [ "$?" = "3" ] || bad=1
done
printf '[world]\nstate = "/tmp/acc/state"\n[define]\noperation = "true"\nexpected_status = "abc"\n' > /tmp/acc/bad.toml
o=$("$SIDEEYE" explore --config /tmp/acc/bad.toml --shim "$SHIM" 2>&1)
rc=$?
if [ "$bad" = "0" ] && [ "$rc" = "3" ] && echo "$o" | grep -q "must be an integer in 0..255"; then
    echo "ok   256, -1 and abc refuse in both spellings"
else
    echo "FAIL boundary rejection: flag ok=$bad, toml exit $rc"
    fails=$((fails + 1))
fi

# Preflight accepts the declaration and the graduation hint carries it — a hint
# without the status would hand explore a define that refuses the very recording
# preflight just accepted (the hint-drops-part-of-the-define defect class).
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" preflight --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" --expect-status 3 \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
rm -rf /tmp/acc/state && mkdir -p /tmp/acc/state
o2=$(TOY_EXIT_STATUS=3 "$SIDEEYE" preflight --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc2=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q -- "--expect-status 3" \
    && [ "$rc2" = "2" ]; then
    echo "ok   preflight accepts the declaration, carries it in the hint, refuses without it"
else
    echo "FAIL preflight wiring: with=$rc (hint: $(echo "$o" | grep -c -- '--expect-status 3')), without=$rc2"
    fails=$((fails + 1))
fi

# The saved case freezes the declaration (case_version 2) and a replay runs under
# it; a case_version 1 file — no expected_status — replays as "exit 0 was the
# contract", which is what every v1 case was recorded under.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=3 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" --expect-status 3 \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
case_ok=0
grep -q '"case_version": 2' /tmp/acc/work/cases/000001.json 2>/dev/null \
    && grep -q '"expected_status": 3' /tmp/acc/work/cases/000001.json 2>/dev/null && case_ok=1
o2=$(TOY_EXIT_STATUS=3 "$SIDEEYE" replay /tmp/acc/work/cases/000001.json \
    --shim "$SHIM" --work /tmp/acc/work-r 2>&1)
rc2=$?
if [ "$rc" = "1" ] && [ "$case_ok" = "1" ] && [ "$rc2" = "1" ] \
    && echo "$o" | grep -q "expected    exit 3"; then
    echo "ok   the case freezes the declaration (v2) and the replay runs under it"
else
    echo "FAIL case round-trip: explore=$rc case_fields=$case_ok replay=$rc2"
    fails=$((fails + 1))
fi

# The version and the field travel together: a v1 file carrying the field and a v2
# file missing it are both malformed — read under a guessed contract, a hand-edited
# case would replay as something it never was (R1 finding). And a refusal that
# happens *after* the declaration is read must report the declaration, not the
# default: the contract gate on a status-3 case says expected_status 3 (R1 finding).
python3 - /tmp/acc/work/cases/000001.json /tmp/acc/v1-with-field.json /tmp/acc/v2-without-field.json /tmp/acc/v2-old-contract.json /tmp/acc/v2-null-field.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
a = json.loads(json.dumps(c)); a["case_version"] = 1
json.dump(a, open(sys.argv[2], "w"))
b = json.loads(json.dumps(c)); del b["define"]["expected_status"]
json.dump(b, open(sys.argv[3], "w"))
d = json.loads(json.dumps(c)); d["contract_version"] = 7
json.dump(d, open(sys.argv[4], "w"))
e = json.loads(json.dumps(c)); e["define"]["expected_status"] = None
json.dump(e, open(sys.argv[5], "w"))
PY
"$SIDEEYE" replay /tmp/acc/v1-with-field.json --shim "$SHIM" --work /tmp/acc/work-r2 >/dev/null 2>&1
r1=$?
"$SIDEEYE" replay /tmp/acc/v2-without-field.json --shim "$SHIM" --work /tmp/acc/work-r3 >/dev/null 2>&1
r2=$?
"$SIDEEYE" replay /tmp/acc/v2-old-contract.json --shim "$SHIM" --work /tmp/acc/work-r4 \
    --json /tmp/acc/oldc.json >/dev/null 2>&1
r3=$?
r3f=$(python3 -c "import json; print(json.load(open('/tmp/acc/oldc.json'))['expected_status'])" 2>/dev/null)
"$SIDEEYE" replay /tmp/acc/v2-null-field.json --shim "$SHIM" --work /tmp/acc/work-r5 >/dev/null 2>&1
r4=$?
if [ "$r1" = "3" ] && [ "$r2" = "3" ] && [ "$r3" = "2" ] && [ "$r3f" = "3" ] && [ "$r4" = "3" ]; then
    echo "ok   version and declaration travel together, and a late refusal reports the declaration"
else
    echo "FAIL case shape gates: v1+field=$r1 v2-field=$r2 old-contract=$r3 reported=$r3f v2-null=$r4"
    fails=$((fails + 1))
fi

# v1 compatibility, on a real case: strip the field, mark it v1, and the replay
# must still reproduce (the plain toy's contract was exit 0 all along).
rm -rf /tmp/acc2 && mkdir -p /tmp/acc2/state
"$SIDEEYE" explore --state /tmp/acc2/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc2/work --allow-unverified >/dev/null 2>&1
python3 - /tmp/acc2/work/cases/000001.json /tmp/acc2/v1-case.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["case_version"] = 1
del c["define"]["expected_status"]
json.dump(c, open(sys.argv[2], "w"))
PY
o=$("$SIDEEYE" replay /tmp/acc2/v1-case.json --shim "$SHIM" --work /tmp/acc2/work-r 2>&1)
rc=$?
if [ "$rc" = "1" ]; then
    echo "ok   a v1 case (no expected_status) still replays; absent means 0"
else
    echo "FAIL v1 case compatibility: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# An exit status of 137 is an exit status, not a signal: declared, it explores in
# full — while every killed world still has to die by the kill signal itself. A
# conflation of the two (128+9 == 137) would break one side or the other here.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$(TOY_EXIT_STATUS=137 "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" --expect-status 137 \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 5 worlds (crash points 4 + 1 baseline)"; then
    echo "ok   exit(137) is an exit status, not a SIGKILL: declared, it explores"
else
    echo "FAIL 137/SIGKILL separation: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 9: the shim is found, not plumbed (#78) ==========="
# Tarball layout: binary and shim as siblings. With --shim omitted the default must
# find the sibling and reach the same verdict the plumbed run reaches; with the shim
# gone the refusal must name both looked-at paths — never fall back to some other
# library silently.
rm -rf /tmp/acc9 && mkdir -p /tmp/acc9/pack /tmp/acc9/state
cp "$SIDEEYE" /tmp/acc9/pack/sideeye
cp "$SHIM" /tmp/acc9/pack/libsideeye_shim.so
o=$(/tmp/acc9/pack/sideeye explore --state /tmp/acc9/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --work /tmp/acc9/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "FAIL"; then
    echo "ok   --shim omitted: the sibling shim is found and the verdict is the plumbed one"
else
    echo "FAIL shim default (tarball layout): exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# The other shipped layout: zig-out/bin + zig-out/lib, reached via the ../lib candidate.
rm -rf /tmp/acc9/state2 && mkdir -p /tmp/acc9/state2
o=$("$SIDEEYE" explore --state /tmp/acc9/state2 \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --work /tmp/acc9/work2 --oracle /usr/bin/strace 2>&1)
rc=$?
# The report must name the realpath-resolved file, not a bin/../lib spelling —
# which also proves it was the ../lib candidate that resolved, not a stray sibling.
if [ "$rc" = "1" ] && echo "$o" | grep -q "FAIL" \
    && echo "$o" | grep -q "zig-out/lib/libsideeye_shim.so" \
    && ! echo "$o" | grep -q 'bin/\.\./lib'; then
    echo "ok   the zig-out layout (../lib beside the binary) is found, and named realpathed"
else
    echo "FAIL shim default (zig-out layout): exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

rm -f /tmp/acc9/pack/libsideeye_shim.so
rm -rf /tmp/acc9/state && mkdir -p /tmp/acc9/state
o=$(/tmp/acc9/pack/sideeye explore --state /tmp/acc9/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --work /tmp/acc9/work 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "looked at /tmp/acc9/pack/libsideeye_shim.so" && echo "$o" | grep -q "pass --shim"; then
    echo "ok   no shim beside the binary: a loud error names both candidates"
else
    echo "FAIL shim absence: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 10: strace is named, never attached (#78) ==========="
# The refusal a would-be PASS gets without an oracle now NAMES the strace found on
# PATH — and still refuses. Attaching it silently would flip this exit to 0, so the
# rc pin here is also the not-attached proof.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "strace is on this machine: pass --oracle /"; then
    echo "ok   the no-oracle refusal names the discovered strace, and stays a refusal"
else
    echo "FAIL oracle hint: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

# With no strace reachable the hint must vanish and the message is yesterday's.
rm -rf /tmp/acc/state /tmp/acc/hintless && mkdir -p /tmp/acc/state /tmp/acc/hintless
o=$(env PATH=/tmp/acc/hintless "$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "completeness_not_verified" && ! echo "$o" | grep -q "strace is on this machine"; then
    echo "ok   a strace-less PATH drops the hint, nothing else changes"
else
    echo "FAIL oracle hint absence: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 11: the docs pages' repo paths exist (#79/#80) ==========="
# Guards path rot, not claim drift: every backticked token containing a slash in the
# evidence-first pages must exist in the repo, so a moved transcript or a renamed
# checker cannot leave a page pointing at nothing. Claim-vs-transcript verification
# stays a review-time axis. Pages that quote ratios or numbers must keep them out of
# backticks — a backticked "3/7" is extracted as a path here and goes red (#85). Sunset: never fired by the v1.0 freeze -> removal list.
doc_fails=0
for page in "$ROOT/docs/target-classes.md" "$ROOT/docs/checker-cookbook.md" "$ROOT/docs/kill-criteria-review.md"; do
    if [ ! -f "$page" ]; then
        echo "     missing page: $page"
        doc_fails=$((doc_fails + 1))
        continue
    fi
    refs=$(grep -o '`[^`]*`' "$page" | tr -d '`' | grep / | grep -v '[ <#]' || true)
    # The denominator is asserted: an extraction that finds almost nothing (say, the
    # pages moved to markdown links) must go red here, not pass over an empty loop.
    ref_count=$(printf '%s\n' "$refs" | grep -c . || true)
    if [ "$ref_count" -lt 5 ]; then
        echo "     only $ref_count slashed references extracted from ${page##*/} — the sweep is not seeing the page"
        doc_fails=$((doc_fails + 1))
    fi
    set -f
    for r in $refs; do
        case "$r" in -*|/*) continue ;; esac
        if [ ! -e "$ROOT/$r" ]; then
            echo "     missing: $r (in ${page##*/})"
            doc_fails=$((doc_fails + 1))
        fi
    done
    set +f
done
if [ "$doc_fails" = "0" ]; then
    echo "ok   every slashed backtick reference in the listed pages resolves in the repo"
else
    echo "FAIL docs reference existence: $doc_fails missing"
    fails=$((fails + 1))
fi

echo "=========== check 12: the UNKNOWN-rate page equals its recomputation (#84) ==========="
# Drift gate for docs/unknown-rate.md: the results block must byte-equal a fresh
# recomputation from corpus.tsv + the committed sweep artifacts (count.py check also
# re-verifies every manifest define digest against the checkout, requires published
# table rows >= corpus rows so an empty table can never read as a measured zero, and
# holds every unknown_reason to report-schema.md's closed set). Before the sweep's
# artifacts exist it asserts the explicit not-yet-measured placeholder instead.
# The gate's own predicates are proven falsifiable on committed fixtures every run —
# one fixture per predicate, not only the two accidents that motivated the gate:
# fixtures/good must pass; tampered-verdict (report verdict flipped, docs stale),
# tampered-manifest (a row deleted), tampered-define (define bytes edited after the
# hash), tampered-reason (an unknown_reason outside the documented closed set) and
# predata-no-placeholder (no artifacts and no placeholder line) must all fail — the
# seen-red-once, kept red forever. Sunset: never fired by the v1.0 freeze -> removal
# list (same rule as check 11).
ur_fails=0
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT"; then
    echo "     the live page/artifacts disagree with recomputation"
    ur_fails=$((ur_fails + 1))
fi
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/good" >/dev/null 2>&1; then
    echo "     fixture good failed — the gate cannot pass its own known-good input"
    ur_fails=$((ur_fails + 1))
fi
# Each tampered fixture must die on ITS OWN predicate's message, not merely
# exit non-zero: a fixture that dies for an unrelated reason (a missing
# file, a parse error) is a hollow red — it proves nothing about the
# predicate it was built for, and an rc-only loop cannot tell the
# difference (R2 caught a mid-flight state where all five were red for the
# wrong reason).
for pair in \
    "tampered-verdict:differs from recomputation" \
    "tampered-manifest:!= corpus rows" \
    "tampered-define:define digest mismatch" \
    "tampered-reason:not in the documented closed set" \
    "predata-no-placeholder:lacks the not-yet-measured placeholder"; do
    bad=${pair%%:*}; want=${pair#*:}
    out=$(python3 "$ROOT/spike/unknown-rate/count.py" check \
          --root "$ROOT/spike/unknown-rate/fixtures/$bad" 2>&1)
    rc=$?
    if [ "$rc" = 0 ]; then
        echo "     fixture $bad PASSED — the gate has gone blind to its own predicate"
        ur_fails=$((ur_fails + 1))
    elif ! printf '%s' "$out" | grep -qF "$want"; then
        echo "     fixture $bad died, but not on its predicate (wanted: $want)"
        printf '%s\n' "$out" | head -3 | sed 's/^/       /'
        ur_fails=$((ur_fails + 1))
    fi
done
if [ "$ur_fails" = "0" ]; then
    echo "ok   unknown-rate page in sync; gate red on all five tampered fixtures"
else
    echo "FAIL unknown-rate drift gate: $ur_fails problem(s)"
    fails=$((fails + 1))
fi

reached_end=1
echo ""
if [ "$fails" = "0" ]; then
    echo "ALL ACCEPTANCE CHECKS PASSED"
    exit 0
fi
echo "$fails ACCEPTANCE CHECK(S) FAILED"
exit 1
