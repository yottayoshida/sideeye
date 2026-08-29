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
run_case "toy-fixed PASSes"    "$OUT/toy-fixed" 0 "explored worlds satisfied"

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
# Anchored to the explored LINE ("explored N worlds"): the PASS headline now also
# contains the word "explored", and `[0-9]*` matches zero digits — the unanchored
# pattern silently picked it up as an empty value when the headline was relabeled.
e=$(echo "$o" | grep -o 'explored [0-9][0-9]* worlds' | awk '{print $2}')
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
echo "=========== check 2r: the stdout capture joins the quiescence observation (#46) ==========="
# A checker that appends to the world's capture stands in for the straggler the
# containment design refuses to let anyone manufacture: setsid/setpgid refuse hard, and
# a group member cannot outlive the group kill deterministically. The checker runs
# between the engine's two capture samples, so its append lands exactly where a
# surviving writer's bytes would — no scheduling race, the guard's own predicate. Both
# checkers carry a real invariant (the key must be readable) so the falsification gate
# accepts them; the appending one shields the append so its verdict still comes from
# the invariant alone.
cat > /tmp/acc/quiet-check.sh <<'CHECK'
#!/bin/sh
exec grep -q "^key=" "$SIDEEYE_STATE_DIR/key.json"
CHECK
cat > /tmp/acc/append-check.sh <<'CHECK'
#!/bin/sh
printf 'a straggler was here\n' >> /tmp/acc/work/stdout-world.txt 2>/dev/null || :
exec grep -q "^key=" "$SIDEEYE_STATE_DIR/key.json"
CHECK
chmod 755 /tmp/acc/quiet-check.sh /tmp/acc/append-check.sh

# Green control first: the same tolerated boundary, a checker that touches nothing
# beyond its invariant — the verdict must be the boundary-free one.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
TOY_FORK=1 export TOY_FORK
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check /tmp/acc/quiet-check.sh \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
unset TOY_FORK
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   tolerated boundary + quiet checker keeps its verdict (exit 1)"
else
    echo "FAIL capture-quiescence green control: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# The append is observed and refused. Before this check's change the identical run
# reached exit 1 with the appended bytes sitting unread in the capture (measured
# 2026-08-17 on the pre-change engine).
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
TOY_FORK=1 export TOY_FORK
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check /tmp/acc/append-check.sh \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
unset TOY_FORK
if [ "$rc" = "2" ] && echo "$o" | grep -q "stdout capture of a crashed world changed"; then
    echo "ok   a write landing between the capture samples is refused (exit 2)"
else
    echo "FAIL capture-quiescence red: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

# NOTE(#169): the world-only arming check that lived here is gone, not migrated.
# Its machinery (#46's capture observation) is unreachable on the world-only side
# now — the refusal fires first — and on the tolerated side the check directly
# above already pins the identical run (TOY_FORK + contaminating checker, same
# predicates), so a migrated copy would only re-run it.

# A world-only boundary refuses (#169): the recording forks nothing — one variable
# makes every WORLD fork — and the recording's clearance cannot cover a boundary it
# never crossed; worlds run with no oracle at all. Same reason token as the
# recording-time refusal (its per-world analog), distinguished by the message, and
# the JSON processes account must tell the world's story, not "single process".
# Pre-#169 this exact run reached a full verdict (exit 1).
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
TOY_FORK_WORLD=1 export TOY_FORK_WORLD
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check /tmp/acc/quiet-check.sh \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/world-only.json 2>&1)
rc=$?
unset TOY_FORK_WORLD
if [ "$rc" = "2" ] && echo "$o" | grep -q "boundary appeared in an explored world that the recording never crossed" \
   && ! echo "$o" | grep -q "observed for quiescence only" \
   && python3 -c 'import json,sys
d = json.load(open("/tmp/acc/world-only.json"))
if d.get("unknown_reason") != "boundary_without_oracle":
    sys.exit("unknown_reason is %r, wanted boundary_without_oracle" % d.get("unknown_reason"))
p = d.get("processes")
if not isinstance(p, str) or "refused" not in p or "explored world" not in p:
    sys.exit("the processes account still tells the recording story: %r" % p)
if "observed for quiescence only" in p:
    sys.exit("the pre-#169 tolerate wording survives in the processes account")'; then
    echo "ok   a world-only boundary refuses under the recording-time reason (exit 2)"
else
    echo "FAIL world-only boundary refusal: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2s: an unreproducible state entry refuses before any world is judged (#5) ==========="
# restore cannot recreate a FIFO, socket or device. Pre-change, every config below
# reached a full verdict with the entry silently dropped from each explored world
# (measured 2026-08-17). One red per detection site, deliberately: the same demotion
# wired at only one snapshot passes a single red and silently misses the other two.
# The symlink case is the discriminator AND the green control through the same
# apparatus shape — a setup-created non-regular-file entry that must NOT refuse.
cat > /tmp/acc/fifo-setup.sh <<CHECK
#!/bin/sh
"$OUT/toy-bug" init && mkfifo /tmp/acc/state/pipe
CHECK
cat > /tmp/acc/link-setup.sh <<CHECK
#!/bin/sh
"$OUT/toy-bug" init && ln -s key.json /tmp/acc/state/alias
CHECK
cat > /tmp/acc/hostile-fifo-setup.sh <<CHECK
#!/bin/sh
"$OUT/toy-bug" init && mkfifo "/tmp/acc/state/\$(printf 'p\nq')"
CHECK
chmod 755 /tmp/acc/fifo-setup.sh /tmp/acc/link-setup.sh /tmp/acc/hostile-fifo-setup.sh

# initial: present before the recording run — checked with the JSON reason too.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup /tmp/acc/fifo-setup.sh --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/report.json 2>&1)
rc=$?
jr=$(python3 -c 'import json,sys
d=json.load(open("/tmp/acc/report.json"))
d.get("unknown_reason")=="unsupported_state_entry" or sys.exit("reason: %s"%d.get("unknown_reason"))
sys.stdout.write("ok")' 2>/dev/null)
if [ "$rc" = "2" ] && echo "$o" | grep -q "present before the recording run: pipe" && [ "${jr:-}" = "ok" ]; then
    echo "ok   a FIFO present before the recording refuses, named, JSON reason carried"
else
    echo "FAIL #5 initial red: exit $rc jr=${jr:-none}"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# final: appears during the recording run. The no-oracle path is the only observation
# window — under an oracle the defined-list refusal (#121) keeps precedence, which
# check 2w-b's TOY_MKNOD control pins separately.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
TOY_MKNOD=1 export TOY_MKNOD
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
unset TOY_MKNOD
if [ "$rc" = "2" ] && echo "$o" | grep -q "appeared during the recording run: fifo"; then
    echo "ok   a FIFO left by the operation refuses on the no-oracle path"
else
    echo "FAIL #5 final red: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# crashed: exists only inside the crash window — the mknod is invisible (no oracle),
# the remove's unlink is a kill point, and the world killed before it holds the FIFO.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
TOY_MKNOD_TRANSIENT=1 export TOY_MKNOD_TRANSIENT
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
unset TOY_MKNOD_TRANSIENT
if [ "$rc" = "2" ] && echo "$o" | grep -q "left in a crashed world: transient-fifo"; then
    echo "ok   a FIFO alive only in the crash window refuses at the crashed snapshot"
else
    echo "FAIL #5 crashed red: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# Only the baseline leaves the entry: killed worlds never reach the toy's last act,
# so the report must attribute the un-killed re-run, not a fictitious crash.
rm -rf /tmp/acc/state /tmp/acc/work /tmp/acc/once-flag && mkdir -p /tmp/acc/state
TOY_MKNOD_BASELINE=1 TOY_ONCE_FLAG=/tmp/acc/once-flag export TOY_MKNOD_BASELINE TOY_ONCE_FLAG
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --allow-unverified 2>&1)
rc=$?
unset TOY_MKNOD_BASELINE TOY_ONCE_FLAG
if [ "$rc" = "2" ] && echo "$o" | grep -q "left by the baseline re-run: baseline-fifo"; then
    echo "ok   an entry only the baseline leaves is attributed to the baseline, not a crash"
else
    echo "FAIL #5 baseline attribution: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# The discriminator: a setup-created symlink is first-class (#122) and must keep its
# verdict — an implementation refusing "anything that is not a regular file" dies here.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup /tmp/acc/link-setup.sh --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "crash point 5 of 5"; then
    echo "ok   a setup-created symlink stays judged, not refused"
else
    echo "FAIL #5 symlink discriminator: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

# A hostile FIFO name cannot forge report lines: the entry name reaches the text
# through the one-byte-per-byte defang (#26). The predicate proves on every run that
# it can see the forgery it guards against, on a synthetic raw-shaped line.
if printf 'x (present before the recording run: p\nq) y\n' | grep -q "^q)"; then :; else
    echo "FAIL #5 hostile-name predicate cannot see the forgery it guards against"
    fails=$((fails + 1))
fi
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup /tmp/acc/hostile-fifo-setup.sh --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "present before the recording run: p?q" && ! echo "$o" | grep -q "^q)"; then
    echo "ok   a newline-named FIFO refuses defanged, forging no line"
else
    echo "FAIL #5 hostile name: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2t: the headline's numbers are the JSON's numbers (#150) ==========="
# A wording-only pin passes an implementation that relabels AND wrongly changes the
# denominator to crash points; these legs bind the printed numerator/denominator to
# the same run's machine fields. Old-label absence is checked on the headline forms
# only: l1's "of N crash worlds" counts crash points and is correct, and the metadata
# note's prose is not a counting statement.
rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/report.json 2>&1)
rc=$?
hd=$(HEADLINE="$(echo "$o" | head -1)" python3 -c 'import json,os,re,sys
h = os.environ["HEADLINE"]
m = re.match(r"^FAIL  ([0-9]+) of ([0-9]+) explored worlds violated an invariant$", h)
if not m: sys.exit("headline shape: %r" % h)
d = json.load(open("/tmp/acc/report.json"))
if int(m.group(1)) != d["violations"]: sys.exit("numerator %s != violations %r" % (m.group(1), d["violations"]))
if int(m.group(2)) != d["explored"]: sys.exit("denominator %s != explored %r" % (m.group(2), d["explored"]))
sys.stdout.write("ok")' 2>&1)
if [ "$rc" = "1" ] && [ "${hd:-}" = "ok" ] && ! echo "$o" | grep -q "crash worlds violated"; then
    echo "ok   FAIL headline: numerator==violations, denominator==explored, old label absent"
else
    echo "FAIL #150 FAIL-side structural pin: rc=$rc ${hd:-}"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi

rm -rf /tmp/acc/state /tmp/acc/work && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace --json /tmp/acc/report.json 2>&1)
rc=$?
hd=$(HEADLINE="$(echo "$o" | head -1)" python3 -c 'import json,os,re,sys
h = os.environ["HEADLINE"]
m = re.match(r"^PASS  ([0-9]+)/([0-9]+) explored worlds satisfied the built-in atomicity invariant$", h)
if not m: sys.exit("headline shape: %r" % h)
d = json.load(open("/tmp/acc/report.json"))
if int(m.group(1)) != d["explored"]: sys.exit("numerator %s != explored %r" % (m.group(1), d["explored"]))
if int(m.group(2)) != d["explored"]: sys.exit("denominator %s != explored %r" % (m.group(2), d["explored"]))
sys.stdout.write("ok")' 2>&1)
if [ "$rc" = "0" ] && [ "${hd:-}" = "ok" ] && ! echo "$o" | grep -q "crash worlds satisfied"; then
    echo "ok   PASS headline: both numbers==explored, old label absent"
else
    echo "FAIL #150 PASS-side structural pin: rc=$rc ${hd:-}"
    echo "$o" | sed 's/^/     | /' | head -4
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
# macOS has no oracle sideeye can use by default — SIP leaves DTrace's syscall provider
# with no probes even as root, and the candidate measured oracle-shaped (fs_usage) is
# root-gated (#181) — so there has to be a way to accept PASS without one. It must be
# asked for explicitly and it must be visible in the report, otherwise the two kinds of
# PASS are indistinguishable.
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

# oracle_verified is promised as a JSON bool (#157): field()'s print() cannot tell a
# bool true from a string "True", so this pin checks the TYPE with the value — and
# self-falsifies against an in-memory string-"True" document through the SAME
# predicate on every call, so the red cannot drift from what it guards.
ov_pin() { python3 -c 'import json,sys
def pin(doc, expected):
    v = doc.get("oracle_verified")
    return type(v) is bool and v is expected
if pin({"oracle_verified": "True"}, True):
    sys.exit("self-falsification failed: a string \"True\" passed the typed pin")
d = json.load(open(sys.argv[1]))
if not pin(d, sys.argv[2] == "true"):
    sys.exit("oracle_verified is %r, wanted %s as a JSON bool" % (d.get("oracle_verified"), sys.argv[2]))' "$1" "$2" 2>&1; }

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
    --shim "$SHIM" --work /tmp/acc/work --oracle "$ROOT/spike/empty-oracle.sh" \
    --json /tmp/acc/report.json 2>&1)
rc=$?
if [ "$rc" = "2" ] && echo "$o" | grep -q "oracle_saw_nothing"; then
    echo "ok   an oracle that observed nothing does not confirm anything (exit 2)"
    reasons="$reasons oracle_saw_nothing"
else
    echo "FAIL empty oracle: exit $rc"
    echo "$o" | sed 's/^/     | /'
    fails=$((fails + 1))
fi
# #94: this is the "--oracle was given, the oracle ran, and the comparison did not
# complete" path — the evidence bit must stay false here, not only where no oracle
# exists at all. The total rule has one true-point; this pins one of its elsewheres.
if ov_pin /tmp/acc/report.json false >/dev/null; then
    echo "ok   oracle_verified stays false (as a JSON bool) when the oracle ran but nothing was compared"
else
    echo "FAIL oracle_verified on the empty-oracle path: $(ov_pin /tmp/acc/report.json false)"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2k2: an oracle capture that cannot be read is a SETUP ERROR that says so (#363) ==========="
# The third corner of 2d/2k: 2d reads a real capture, 2k reads a readable-but-empty
# one (UNKNOWN oracle_saw_nothing), and here the capture cannot be read at all. The
# refusal must name what was measured — the capture file could not be read — not
# "produced no output", which is 2k's condition and was this message's wording until
# #363's adjudication caught the mismatch.
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
o=$("$SIDEEYE" explore --state /tmp/acc/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug doctor" \
    --shim "$SHIM" --work /tmp/acc/work --oracle "$ROOT/spike/vanishing-oracle.sh" 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "capture file could not be read"; then
    echo "ok   a vanished oracle capture refuses as SETUP ERROR, naming the unreadable capture"
else
    echo "FAIL vanished oracle capture: exit $rc (wanted 3 + the unreadable-capture wording)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 2ac: a hostile file name cannot forge text-report lines (#26) ==========="
# A Unix file name may carry newlines, and the FAIL block prints target-chosen
# paths. Measured red on the pre-fix binary: this exact scenario printed the
# forged line "not tested  nothing" as its own report line. Green asserts all
# three sides: the forged line is ABSENT from the text, the defanged spelling
# is present, and the JSON round-trips the raw bytes (the machine side's
# contract is the exact name). The operation is a single-process python file —
# a shell script spawning rm/mv is refused as child_touched_state_dir
# (measured while building this check).
rm -rf /tmp/acc && mkdir -p /tmp/acc/state
printf 'old' > "/tmp/acc/state/log
not tested  nothing"
printf 'new' > /tmp/acc/state/next
cat > /tmp/acc/op26.py <<'EOPY'
#!/usr/bin/env python3
import os
bad = "/tmp/acc/state/log\nnot tested  nothing"
os.unlink(bad)
os.rename("/tmp/acc/state/next", bad)
EOPY
chmod 755 /tmp/acc/op26.py
o=$("$SIDEEYE" explore --state /tmp/acc/state --operation /tmp/acc/op26.py \
    --shim "$SHIM" --work /tmp/acc/work --oracle /usr/bin/strace \
    --json /tmp/acc/report.json 2>&1)
rc=$?
forge_fails=0
[ "$rc" = "1" ] || { echo "     wanted FAIL (exit 1), got exit $rc"; forge_fails=$((forge_fails + 1)); }
[ "$(field /tmp/acc/report.json verdict)" = "FAIL" ] || { echo "     JSON verdict is not FAIL"; forge_fails=$((forge_fails + 1)); }
if printf '%s\n' "$o" | grep -qx "not tested  nothing"; then
    echo "     the forged line is present — target-chosen bytes reached the text raw"
    forge_fails=$((forge_fails + 1))
fi
printf '%s\n' "$o" | grep -q "log?not tested  nothing" || { echo "     the defanged spelling is missing from the text"; forge_fails=$((forge_fails + 1)); }
# The machine side keeps the exact bytes: subject round-trips with the newline.
rt=$(python3 -c 'import json,sys; d=json.load(open("/tmp/acc/report.json")); sys.stdout.write("ok" if d["earliest"]["subject"] == "log\nnot tested  nothing" else "bad")' 2>/dev/null)
[ "$rt" = "ok" ] || { echo "     JSON subject did not round-trip the raw name"; forge_fails=$((forge_fails + 1)); }
# The forged-line predicate falsifies itself each run: fed a synthetic report
# that DOES carry the forged line, it must detect it — a predicate that cannot
# go red proves nothing by staying green.
if printf 'path        log\nnot tested  nothing\n' | grep -qx "not tested  nothing"; then :; else
    echo "     the forged-line predicate failed to detect a synthetic forgery — the check is blind"
    forge_fails=$((forge_fails + 1))
fi
if [ "$forge_fails" = "0" ]; then
    echo "ok   hostile names are defanged in the text and exact in the JSON"
else
    echo "FAIL hostile-name check: $forge_fails of 6 legs wrong"
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
# Explicit checks, not assert: assert vanishes under PYTHONOPTIMIZE, and a judgement
# that can silently stop looking is worse than none (#58).
if python3 -c '
import json, sys
d = json.load(open("/tmp/acc/report.json"))
if d["l0"] != "1 path(s) judged pre-or-post; 1 file(s) judged by the history form (appended tails not judged): log.txt": sys.exit(d["l0"])
if "appended tails (files under the history form)" not in d["not_tested"]: sys.exit(d["not_tested"])
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
if d["l0"] != "2 path(s) judged pre-or-post": sys.exit(d["l0"])
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
if [ "$rc" = "0" ] && echo "$o" | grep -q "ownership/permission/timestamp write(s) observed and excluded"; then
    echo "ok   a chmod on state is excluded from judgement and named in the text report"
else
    echo "FAIL chmod: exit $rc (wanted PASS with the metadata note)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
if python3 - <<'PYEOF'
import json, sys
d = json.load(open('/tmp/acc/meta.json'))
if 'observed and excluded' not in d['metadata_writes']: sys.exit(d['metadata_writes'])
if 'chmod' not in d['metadata_writes']: sys.exit(d['metadata_writes'])
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
if [ "$rc" = "1" ] && echo "$o" | grep -q "explored worlds violated" && echo "$o" | grep -q "the case reproduced"; then
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

echo "=========== check 2sc: a replayed case cannot point destruction outside --state-under (#266) ==========="
# The case file names its own state directory, and replay empties (--fresh-state)
# and rebuilds (restore, once per world) whatever it names. Leg A measures that
# destruction for real — it is the red side the confinement exists for, kept in the
# suite so the danger being guarded stays demonstrated, not remembered. Legs B-D pin
# the confinement: outside refused (directory untouched), equal refused, inside
# passing. Legs E-F pin the flag surface itself.
VICTIM=/tmp/acc-victim
rm -rf "$VICTIM" && mkdir -p "$VICTIM" && echo "survives" > "$VICTIM/sentinel.txt"
python3 - "$case_file" /tmp/acc/outside-case.json "$VICTIM" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["define"]["state"] = sys.argv[3]
json.dump(c, open(sys.argv[2], "w"))
PY
# Leg A (the measured red side): without the flag, the same case empties the victim.
o=$("$SIDEEYE" replay /tmp/acc/outside-case.json --fresh-state --shim "$SHIM" --work /tmp/acc/work-sca --oracle /usr/bin/strace 2>&1)
if [ ! -e "$VICTIM/sentinel.txt" ]; then
    echo "ok   without the flag, a case-named outside directory really is emptied (the danger is real)"
else
    echo "FAIL red side: the unconfined replay left the victim's sentinel in place — what is the confinement for?"
    fails=$((fails + 1))
fi
# Leg B: with the flag, the same case refuses BEFORE anything destructive, and the
# refusal names the range. The sentinel must survive.
rm -rf "$VICTIM" && mkdir -p "$VICTIM" && echo "survives" > "$VICTIM/sentinel.txt"
o=$("$SIDEEYE" replay /tmp/acc/outside-case.json --fresh-state --state-under /tmp/acc --shim "$SHIM" --work /tmp/acc/work-scb --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "outside the allowed range" && [ -s "$VICTIM/sentinel.txt" ]; then
    echo "ok   an outside state refuses (exit 3, range named) and the outside directory is untouched"
else
    echo "FAIL state-under confinement: exit $rc, sentinel $([ -e "$VICTIM/sentinel.txt" ] && echo present || echo GONE)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# Leg C: equal to the range is refused too — strict inside, or a case naming the
# range itself would make the whole workspace the sacrificial directory.
o=$("$SIDEEYE" replay /tmp/acc/outside-case.json --fresh-state --state-under "$VICTIM" --shim "$SHIM" --work /tmp/acc/work-scc --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "outside the allowed range"; then
    echo "ok   a state EQUAL to the range is refused (strict inside)"
else
    echo "FAIL equal-to-range: exit $rc (wanted 3 + range refusal)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# Leg D (positive control): the untouched case, whose state lives under /tmp, replays
# to its usual reproduction under --state-under /tmp. The confinement must not turn
# every replay into a refusal.
o=$("$SIDEEYE" replay "$case_file" --state-under /tmp --shim "$SHIM" --work /tmp/acc/work-scd --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "1" ] && echo "$o" | grep -q "the case reproduced"; then
    echo "ok   an inside state still replays to its verdict (positive control)"
else
    echo "FAIL positive control under --state-under: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# Leg E: the flag belongs to replay alone; explore refuses it by name (ADR 0007's
# no-accepted-but-inert rule).
o=$("$SIDEEYE" explore --state /tmp/acc/state --operation /bin/true --state-under /tmp --shim "$SHIM" --work /tmp/acc/work-sce 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q -- "--state-under applies to replay only"; then
    echo "ok   explore refuses --state-under by name"
else
    echo "FAIL explore accepted --state-under (exit $rc)"
    fails=$((fails + 1))
fi
# Leg F: a confinement flag is not last-wins; a second spelling refuses.
o=$("$SIDEEYE" replay "$case_file" --state-under /tmp --state-under /tmp/acc --shim "$SHIM" --work /tmp/acc/work-scf 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "given twice"; then
    echo "ok   a duplicated --state-under refuses rather than letting the second spelling win"
else
    echo "FAIL duplicate --state-under: exit $rc"
    fails=$((fails + 1))
fi
# Leg G: the refusal's cleanup, measured on its own predicate (security review,
# Major-1): a case naming a NOT-YET-EXISTING outside state makes this invocation's
# own mkdir succeed, so the refusal has something real to undo — and must leave
# neither that directory nor the work dir behind. Legs B-F never create the state
# dir (the victim exists), so without this leg the undo calls could all be deleted
# and the suite would stay green.
python3 - "$case_file" /tmp/acc/outside-case-g.json "$VICTIM/never-made" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["define"]["state"] = sys.argv[3]
json.dump(c, open(sys.argv[2], "w"))
PY
o=$("$SIDEEYE" replay /tmp/acc/outside-case-g.json --fresh-state --state-under /tmp/acc --shim "$SHIM" --work /tmp/acc/work-scg --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "3" ] && [ ! -e "$VICTIM/never-made" ] && [ ! -e /tmp/acc/work-scg ]; then
    echo "ok   a refusal leaves the filesystem as it found it: neither the state nor the work mkdir survives"
else
    echo "FAIL refusal cleanup: exit $rc, state $([ -e "$VICTIM/never-made" ] && echo LEFT || echo gone), work $([ -e /tmp/acc/work-scg ] && echo LEFT || echo gone)"
    fails=$((fails + 1))
fi
# Leg H: "/" as a range would confine nothing — isStrictlyInsideDir answers true
# for every absolute path under it — so the flag refuses the range itself. Without
# this leg, deleting that one branch turns --state-under / into a silent no-op
# (security review, Major-2: the one mutation that makes the feature fail open).
o=$("$SIDEEYE" replay /tmp/acc/outside-case.json --fresh-state --state-under / --shim "$SHIM" --work /tmp/acc/work-sch 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "would confine nothing"; then
    echo "ok   --state-under / refuses as a range that confines nothing"
else
    echo "FAIL state-under /: exit $rc (wanted 3 + confine-nothing refusal)"
    echo "$o" | sed 's/^/     | /' | head -4
    fails=$((fails + 1))
fi
# Leg E2: preflight refuses the flag by the same name explore does — measured, not
# inferred from the shared predicate (security review, Minor-6).
o=$("$SIDEEYE" preflight --state /tmp/acc/state --operation /bin/true --state-under /tmp --shim "$SHIM" --work /tmp/acc/work-sce2 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q -- "--state-under applies to replay only"; then
    echo "ok   preflight refuses --state-under by name"
else
    echo "FAIL preflight accepted --state-under (exit $rc)"
    fails=$((fails + 1))
fi
rm -rf "$VICTIM"

echo "=========== check 2sq: a shim that renumbers without re-announcing is refused (#270) ==========="
# The recording-side numbering refusal (records vs highest sequence number) survived
# with BOTH its asserts disabled — the structural double-announcement rule intercepts
# every naturally occurring shape first (BUILDLOG 2026-08-16, R2's measured mutant).
# The one shape that reaches it is a shim that renumbers without re-announcing, which
# no interposed path produces on its own — so the apparatus builds it: the same shim
# source with a compile-time gap (skips number 2), a separately named artifact that
# plain `zig build` never produces.
GAPSHIM=$ROOT/zig-out/lib/libsideeye_shim_testgap.so
if [ ! -f "$GAPSHIM" ]; then
    echo "FAIL gap-shim apparatus missing: build with zig build -Dtest-seq-gap (add -Dtarget=... for the container)"
    fails=$((fails + 1))
else
    rm -rf /tmp/acc-gap && mkdir -p /tmp/acc-gap/state
    o=$("$SIDEEYE" explore --state /tmp/acc-gap/state \
        --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
        --shim "$GAPSHIM" --work /tmp/acc-gap/work --oracle /usr/bin/strace 2>&1)
    rc=$?
    if [ "$rc" = "2" ] && echo "$o" | grep -q "sequence_numbering_broken"; then
        echo "ok   the numbering net catches the one shape built to reach it (exit 2, sequence_numbering_broken)"
    else
        echo "FAIL gap shim: exit $rc (wanted 2 + sequence_numbering_broken)"
        echo "$o" | sed 's/^/     | /' | head -8
        fails=$((fails + 1))
    fi
    rm -rf /tmp/acc-gap
fi

echo "=========== check 2fc: a state file over the per-file cap refuses by name (#265) ==========="
# The snapshot path was the one unbounded read in the engine; a big enough file
# turned the judgment into an OOM kill with no report. The unit tests drive the
# boundary with a small parameterized cap; this leg drives the SHIPPED constant
# end to end — a real explore over a real 64MiB+1 file — so the production wiring
# (cap value, diag, call-site message) is the thing measured. The file is sparse:
# reads return zeros without paying 64 MiB of disk.
rm -rf /tmp/acc-cap && mkdir -p /tmp/acc-cap/state
python3 - <<'PY'
with open("/tmp/acc-cap/state/huge.bin", "wb") as f:
    f.seek(64 * 1024 * 1024)   # one byte past the cap
    f.write(b"x")
PY
o=$("$SIDEEYE" explore --state /tmp/acc-cap/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc-cap/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "3" ] && echo "$o" | grep -q "too large for byte-level judgment" && echo "$o" | grep -q "huge.bin"; then
    echo "ok   a file over the cap is a named SETUP ERROR, not an OOM kill"
else
    echo "FAIL per-file cap: exit $rc (wanted 3, naming huge.bin)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-cap

echo "=========== check 2fd: the same cap AFTER the recording run is UNKNOWN, not exit 3 (#330) ==========="
# 2fc plants the file before anything runs, so exit 3 is true there. Here the
# operation writes it itself — an ordinary thing for a target to do — and the cap
# is hit at the final snapshot, past the recording run. Exit 3 would then say "the
# define did not run" about a define that ran to completion, and a caller reading
# that machine-readably retries the environment instead of reporting an unjudgeable
# run. The two legs also bound where `run_phase`'s assignment may sit: assign it
# before the initial snapshot and 2fc turns red; delete the assignment and this one
# does. That bounds an interval, not a point — an assignment moved anywhere between
# the two snapshots leaves both legs green, measured. `--json` is passed because the
# closed-set gate only checks that the names in the enum and the doc agree — that a
# member is ever REACHED is asserted here alone.
rm -rf /tmp/acc-cap-late && mkdir -p /tmp/acc-cap-late/state
# seek=67108864 count=1 writes byte 67,108,864, so the file is 67,108,865 bytes —
# one past the cap, which the reader compares with a strict >. Sparse, like 2fc.
o=$("$SIDEEYE" explore --state /tmp/acc-cap-late/state \
    --operation "dd if=/dev/zero of=/tmp/acc-cap-late/state/huge.bin bs=1 seek=67108864 count=1" \
    --shim "$SHIM" --work /tmp/acc-cap-late/work --oracle /usr/bin/strace \
    --json /tmp/acc-cap-late/r.json 2>&1)
rc=$?
if [ "$rc" = "2" ] \
    && echo "$o" | grep -q "state_file_too_large" \
    && echo "$o" | grep -q "huge.bin" \
    && grep -q '"unknown_reason": "state_file_too_large"' /tmp/acc-cap-late/r.json; then
    echo "ok   a cap hit past the recording run is UNKNOWN state_file_too_large, in text and JSON"
else
    echo "FAIL late per-file cap: exit $rc (wanted 2 + state_file_too_large in text and JSON)"
    echo "$o" | sed 's/^/     | /' | head -6
    sed 's/^/     json | /' /tmp/acc-cap-late/r.json 2>/dev/null | head -4
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-cap-late

echo "=========== check 2fg: a tree under the per-file cap but over the TREE ceiling refuses before anything runs (#323) ==========="
# The per-file cap bounds one read and the tree's total was unbounded, so files each
# comfortably under it summed into an OOM kill with no report. Eight sparse files of
# 32 MiB are each half of max_state_file_bytes (64 MiB) and together reach 396 MiB of
# arena against a 256 MiB ceiling — measured, not sized by eye, because the arena's cost
# is not the tree's size. A green here that came from the per-file cap would be the wrong
# rule, which is why the per-file wording is asserted ABSENT rather than left to chance.
# Sparse: reads return zeros without paying the disk.
#
# Both legs drive the SHIPPED constants end to end. The unit tests drive small caps and
# can say things these cannot (the arena's reach at the break, an all-empty tree); these
# say the thing the unit tests cannot, which is that the production wiring — constant,
# diag, call-site message, JSON field — is connected.
rm -rf /tmp/acc-tree && mkdir -p /tmp/acc-tree/state
python3 - <<'PY'
for i in range(8):
    with open("/tmp/acc-tree/state/big%d.bin" % i, "wb") as f:
        f.truncate(32 * 1024 * 1024)
PY
o=$("$SIDEEYE" explore --state /tmp/acc-tree/state \
    --operation "/bin/true" \
    --shim "$SHIM" --work /tmp/acc-tree/work --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "3" ] \
    && echo "$o" | grep -q "the state tree is too large to snapshot" \
    && echo "$o" | grep -q "byte ceiling" \
    && ! echo "$o" | grep -q "a state file is too large"; then
    echo "ok   a tree over the ceiling is a named SETUP ERROR, and not the per-file cap firing"
else
    echo "FAIL tree ceiling (early): exit $rc (wanted 3, the tree wording, and NOT the per-file wording)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-tree

echo "=========== check 2fh: the same ceiling AFTER the recording run is UNKNOWN, not exit 3 (#323) ==========="
# 2fg plants the tree before anything runs, so exit 3 is true there. Here the state starts
# empty and the operation brings the tree in itself — an ordinary thing for a target to do
# — and the ceiling breaks at the final snapshot, past the recording run, where exit 3
# would say "the define did not run" about a define that ran to completion.
#
# `cp -r` rather than a shell one-liner: --operation is split on spaces with no quoting, and
# a shell would put the writes in a child process, which the engine refuses for its own
# reasons before any snapshot is taken. One process, many files.
rm -rf /tmp/acc-tree-late && mkdir -p /tmp/acc-tree-late/state /tmp/acc-tree-late/staged
python3 - <<'PY'
for i in range(8):
    with open("/tmp/acc-tree-late/staged/big%d.bin" % i, "wb") as f:
        f.truncate(32 * 1024 * 1024)
PY
o=$("$SIDEEYE" explore --state /tmp/acc-tree-late/state \
    --operation "/bin/cp -r /tmp/acc-tree-late/staged /tmp/acc-tree-late/state/copied" \
    --shim "$SHIM" --work /tmp/acc-tree-late/work --oracle /usr/bin/strace \
    --json /tmp/acc-tree-late/r.json 2>&1)
rc=$?
# Every clause the success line claims, asserted: the verdict, the reason in the text, the
# reason in the JSON, and that the JSON says UNKNOWN rather than carrying a reason beside
# some other verdict.
if [ "$rc" = "2" ] \
    && echo "$o" | grep -q "state_tree_too_large" \
    && echo "$o" | grep -q "the state tree is too large to snapshot" \
    && grep -q '"unknown_reason": "state_tree_too_large"' /tmp/acc-tree-late/r.json \
    && grep -q '"verdict": "UNKNOWN"' /tmp/acc-tree-late/r.json; then
    echo "ok   a ceiling break past the recording run is UNKNOWN state_tree_too_large, in text and JSON"
else
    echo "FAIL tree ceiling (late): exit $rc (wanted 2 + state_tree_too_large in text and JSON, verdict UNKNOWN)"
    echo "$o" | sed 's/^/     | /' | head -6
    sed 's/^/     json | /' /tmp/acc-tree-late/r.json 2>/dev/null | head -4
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-tree-late

echo "=========== check 2an: the destructive vet refuses an ancestor of a denied tree (#358) ==========="
# #329 gave the naming vet an outward read of the denied lists and left the destructive
# one inward-only, so a root that is a PARENT of somewhere denied passed the predicate
# that empties directories while failing the one that only names files. The single real
# instance is /private/var — root-owned and macOS-only, which acceptance can neither
# create nor sacrifice. `-Dtest-ancestor-probe` builds an engine whose denied list carries
# one synthetic entry under /tmp, making its parent an ancestor with two components: the
# same shape, somewhere a sentinel can die.
#
# This asserts the DELETE, not the predicate's return value. The change is about what the
# engine refuses to empty, and a check that only reads a refusal string would not have
# noticed if the refusal arrived after the tree was gone.
#
# Note on the shape: leg A of check 2sc (#266) runs its destruction for real on every
# suite run, because the unconfined path survived that fix. This leg cannot — after #358
# the probe refuses, so the red side is a recorded observation plus the mutation, not a
# standing demonstration. Same form, different guarantee.
# Replay with --fresh-state, not explore, and the distinction is the harm itself:
# `restore` puts the initial snapshot BACK, so anything already in the root survives an
# explore untouched. `freshDir` — reached only through --fresh-state, which is replay-only
# — is what empties it. A first version of this leg used explore and measured a PASS with
# the sentinel intact, which is what the engine correctly does. Check 2sc directly above
# reaches the same function the same way, for the same reason.
PROBE=$ROOT/zig-out/bin/sideeye-ancprobe
if [ ! -x "$PROBE" ]; then
    echo "FAIL #358 leg: $PROBE missing — zig build -Dtest-ancestor-probe (add -Dtarget=... for the container)"
    fails=$((fails + 1))
else
    ANC=/tmp/se-anc-probe
    rm -rf "$ANC" && mkdir -p "$ANC" && echo "survives" > "$ANC/sentinel.txt"
    # The root must be the ancestor ITSELF. One level deeper (/tmp/se-anc-probe/x) and
    # the inward read refuses it — which it already did before #358, so the green would
    # attribute to the wrong rule.
    python3 - "$case_file" /tmp/acc/anc-case.json "$ANC" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["define"]["state"] = sys.argv[3]
json.dump(c, open(sys.argv[2], "w"))
PY
    o=$("$PROBE" replay /tmp/acc/anc-case.json --fresh-state \
        --shim "$SHIM" --work /tmp/acc-anc-work --oracle /usr/bin/strace 2>&1)
    rc=$?
    if [ "$rc" = "3" ] && echo "$o" | grep -q "nothing sacrificial belongs in" && [ -s "$ANC/sentinel.txt" ]; then
        echo "ok   a root that CONTAINS a denied entry refuses, and the sentinel inside it survives"
    else
        echo "FAIL #358 ancestor root: exit $rc, sentinel $([ -e "$ANC/sentinel.txt" ] && echo present || echo GONE)"
        echo "$o" | sed 's/^/     | /' | head -6
        fails=$((fails + 1))
    fi
    rm -rf "$ANC" /tmp/acc-anc-work
fi

echo "=========== check 2fe: a snapshot failure that is NOT the cap also stops claiming setup (#351) ==========="
# #330 gave the cap an honest verdict at the post-recording sites and left the other six
# SnapshotError values on exit 3. TooDeep is the reachable one: the walk refuses at
# max_depth = 32 with a strict >, and a target makes directories during its own
# operation. Both legs also assert the DETAIL, not only the verdict — before #351 the
# message was the call site's `what` and nothing else, so the text assertion is what
# makes each of these red on the commit before this one. Asserting the exit code alone
# would have made the initial leg green from birth, which checks nothing.
#
# The depth and the "32 levels" wording both pin engine.max_depth's VALUE, deliberately:
# changing the constant reddens these loudly rather than letting the message drift away
# from what the walk does. 40 is comfortably past it either way.
DEEP=$(python3 -c "print('/'.join('d%d' % i for i in range(40)))")

rm -rf /tmp/acc-deep-late && mkdir -p /tmp/acc-deep-late/state
o=$("$SIDEEYE" explore --state /tmp/acc-deep-late/state \
    --operation "/bin/mkdir -p /tmp/acc-deep-late/state/$DEEP" \
    --shim "$SHIM" --work /tmp/acc-deep-late/work --oracle /usr/bin/strace \
    --json /tmp/acc-deep-late/r.json 2>&1)
rc=$?
if [ "$rc" = "2" ] \
    && echo "$o" | grep -q "state_unsnapshotable" \
    && echo "$o" | grep -q "nested deeper than the 32 levels" \
    && echo "$o" | grep -q "final state" \
    && grep -q '"unknown_reason": "state_unsnapshotable"' /tmp/acc-deep-late/r.json; then
    echo "ok   a non-cap snapshot failure past the recording run is UNKNOWN state_unsnapshotable, naming the limit"
else
    echo "FAIL late non-cap snapshot: exit $rc (wanted 2 + state_unsnapshotable + the depth limit)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-deep-late

# Planted from the shell, the way 2fc plants its oversized file — routing it through
# --setup would add a second way to fail (setup exiting non-zero) that this leg would
# then have to tell apart from the one it is about. No --setup and no --oracle here for
# the same reason: the plant alone reaches the initial snapshot, which runs before the
# oracle's executability check, so both would only add ways to fail that are not this.
rm -rf /tmp/acc-deep-init && mkdir -p "/tmp/acc-deep-init/state/$DEEP"
o=$("$SIDEEYE" explore --state /tmp/acc-deep-init/state \
    --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc-deep-init/work 2>&1)
rc=$?
if [ "$rc" = "3" ] \
    && echo "$o" | grep -q "nested deeper than the 32 levels" \
    && echo "$o" | grep -q "initial state"; then
    echo "ok   the same failure before the recording run stays a SETUP ERROR, and still names the limit"
else
    echo "FAIL initial non-cap snapshot: exit $rc (wanted 3 + the depth limit, naming the initial state)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-deep-init

echo "=========== check 2vw: the vectored positional writes are counted (#256) ==========="
# The oracle has classified pwritev since v0.1; the shim never exported it, so a
# target writing this way was seen by one observer and not the other — measured
# before the fix as `oracle_missed_operation`, naming the pwritev line the shim
# had no record of. On macOS, where no oracle exists, the same write is invisible
# to everything, which is why this is a PASS hole rather than an ergonomic gap.
#
# The leg asserts the BYTES as well as the verdict: the toy hands pwritev two
# iovecs, so a wrapper with its arguments in the wrong order records the operation
# correctly and still writes the wrong thing. Removing the export from
# shim/src/linux.zig turns the verdict back into UNKNOWN.
rm -rf /tmp/acc-vw && mkdir -p /tmp/acc-vw/state
o=$("$SIDEEYE" explore --state /tmp/acc-vw/state \
    --setup "$OUT/toy-pwritev init" --operation "$OUT/toy-pwritev rotate" \
    --shim "$SHIM" --work /tmp/acc-vw/work --oracle /usr/bin/strace 2>&1)
rc=$?
key_bytes=$(cat /tmp/acc-vw/state/key.json 2>/dev/null)
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && [ "$key_bytes" = "key=2" ]; then
    echo "ok   a pwritev write reaches a verdict, and the bytes it wrote are right"
else
    echo "FAIL pwritev: exit $rc, key.json='$key_bytes' (wanted a verdict and key=2)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-vw
# The LFS alias, walked rather than assumed. A `_FILE_OFFSET_BITS=64` build resolves
# pwritev to glibc's pwritev64, which is a separate symbol: exporting one and not the
# other leaves the alias path invisible to the shim exactly as the whole family was
# before this batch. This leg is why the aliases are in the export list.
rm -rf /tmp/acc-vwl && mkdir -p /tmp/acc-vwl/state
o=$("$SIDEEYE" explore --state /tmp/acc-vwl/state \
    --setup "$OUT/toy-pwritev-lfs init" --operation "$OUT/toy-pwritev-lfs rotate" \
    --shim "$SHIM" --work /tmp/acc-vwl/work --oracle /usr/bin/strace 2>&1)
rc=$?
key_bytes=$(cat /tmp/acc-vwl/state/key.json 2>/dev/null)
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && [ "$key_bytes" = "key=2" ]; then
    echo "ok   the pwritev64 alias path is interposed too (LFS build reaches a verdict)"
else
    echo "FAIL pwritev64 alias: exit $rc, key.json='$key_bytes' (wanted a verdict and key=2)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-vwl

echo "=========== check 2cp: a copy's scope is its destination, not its argument 0 (#244) ==========="
# copy_file_range(fd_in, off_in, fd_out, …) puts the SOURCE first. Every other fd
# syscall in the contract puts the descriptor it writes there, which is why the
# oracle's scope test used to read argument 0 unconditionally. Reading it here is
# wrong in both directions at once, so both directions are legs:
#   into  — destination inside the state directory: a write that must be counted
#   out   — source inside, destination outside: nothing in the state changes
# An argument-0 reading answers each of these with the other one's answer.
rm -rf /tmp/acc-cp && mkdir -p /tmp/acc-cp/state /tmp/acc-cp/outside
o=$(TOY_OUTSIDE=/tmp/acc-cp/outside "$SIDEEYE" explore --state /tmp/acc-cp/state \
    --setup "$OUT/toy-copy init" --operation "$OUT/toy-copy rotate" \
    --shim "$SHIM" --work /tmp/acc-cp/work --oracle /usr/bin/strace 2>&1)
rc=$?
# A verdict (0 or 1), and the copy actually became a crash point: "explored 0" would
# mean the destination was scoped out — the miss an argument-0 reading produces.
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && ! echo "$o" | grep -q "explored 0 crash points"; then
    echo "ok   a copy INTO the state directory is counted and reaches a verdict"
else
    echo "FAIL copy into state: exit $rc"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-cp2 && mkdir -p /tmp/acc-cp2/state /tmp/acc-cp2/outside
o=$(TOY_OUTSIDE=/tmp/acc-cp2/outside "$SIDEEYE" explore --state /tmp/acc-cp2/state \
    --setup "$OUT/toy-copy init" --operation "$OUT/toy-copy read-out" \
    --shim "$SHIM" --work /tmp/acc-cp2/work --oracle /usr/bin/strace 2>&1)
rc=$?
# Reading the state out changes nothing in it: no crash points, and the honest
# answer is the 0-operation PASS. An argument-0 reading would count a write here.
if [ "$rc" = "0" ] && echo "$o" | grep -q "explored 0 crash points"; then
    echo "ok   a copy OUT of the state directory counts nothing (0 crash points)"
else
    echo "FAIL copy out of state: exit $rc (wanted 0 with no crash points)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-cp /tmp/acc-cp2

echo "=========== check 2sx: every classified syscall is interposed or explained (#256) ==========="
# The structural half. `pwritev`, `pwritev2` and `renameat2` were classified by the
# oracle and unexported by the shim from v0.1 until this batch, because nothing
# compared the two lists. This runs the comparison the way it has to be run — not
# as set equality — before this batch that comparison had 32 differences and 29 of
# them were legitimate — but as "classified implies interposed or explained". CI runs
# it too; here it sits beside the behaviour it protects.
o=$(python3 "$ROOT/spike/check-shim-coverage.py" "$ROOT/src/oracle.zig" "$ROOT/shim/src/linux.zig" 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "interposed or explained"; then
    echo "ok   the shim covers every syscall the oracle classifies (or says why not)"
else
    echo "FAIL shim coverage: exit $rc"
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
rm -rf "$SD" && mkdir -p "$SD/s1" "$SD/s2" "$SD/s3" "$SD/s4" "$SD/s5" "$SD/s6"
TOY_STATE=$SD/s1 "$SIDEEYE" explore --state "$SD/s1" \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work "$SD/w1" --oracle /usr/bin/strace --json "$SD/pass.json" >/dev/null 2>&1
# The FAIL fixture runs WITH the checker (#231): `checker_earliest` is a
# documented field, and the bidirectional pin below needs some generated report
# to carry it — a checkerless FAIL cannot, structurally. Same toy/check pair as
# check 1b, whose earliest world is checker-red (the combined invariant).
TOY_STATE=$SD/s2 TOY=$OUT/toy-bug "$SIDEEYE" explore --state "$SD/s2" \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
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

# The #94 value pins: the evidence bit is a value, not only a documented name. True is
# reserved for "the comparison completed and agreed" — so the oracle-borne FAIL carries
# true (the bit is about the run, not the verdict), and the --allow-unverified PASS
# carries false: exactly the pair the exit codes cannot distinguish. A build that does
# not emit the field fails every value pin (field() prints nothing for a missing key,
# and nothing is neither True nor False).
TOY_STATE=$SD/s5 "$SIDEEYE" explore --state "$SD/s5" \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work "$SD/w5" --allow-unverified --json "$SD/unverified-pass.json" >/dev/null 2>&1
# A FAIL needs no oracle and no flag — it exits before the PASS-side completeness
# gate — and its report must still carry the bit, as false (R1: the schema's
# Always=yes was otherwise pinned on no report of this exact shape).
TOY_STATE=$SD/s6 "$SIDEEYE" explore --state "$SD/s6" \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work "$SD/w6" --json "$SD/nooracle-fail.json" >/dev/null 2>&1
ev_fails=0
ov_pin "$SD/pass.json" true >/dev/null || { echo "     verified PASS: $(ov_pin "$SD/pass.json" true)"; ev_fails=$((ev_fails + 1)); }
ov_pin "$SD/fail.json" true >/dev/null || { echo "     oracle-borne FAIL: $(ov_pin "$SD/fail.json" true)"; ev_fails=$((ev_fails + 1)); }
ov_pin "$SD/unknown.json" false >/dev/null || { echo "     no-oracle UNKNOWN: $(ov_pin "$SD/unknown.json" false)"; ev_fails=$((ev_fails + 1)); }
ov_pin "$SD/unverified-pass.json" false >/dev/null || { echo "     --allow-unverified PASS: $(ov_pin "$SD/unverified-pass.json" false)"; ev_fails=$((ev_fails + 1)); }
ov_pin "$SD/setup.json" false >/dev/null || { echo "     SETUP_ERROR: $(ov_pin "$SD/setup.json" false)"; ev_fails=$((ev_fails + 1)); }
[ "$(field "$SD/nooracle-fail.json" verdict)" = "FAIL" ] || { echo "     no-oracle FAIL: verdict is '$(field "$SD/nooracle-fail.json" verdict)', wanted FAIL"; ev_fails=$((ev_fails + 1)); }
ov_pin "$SD/nooracle-fail.json" false >/dev/null || { echo "     no-oracle FAIL: $(ov_pin "$SD/nooracle-fail.json" false)"; ev_fails=$((ev_fails + 1)); }
if [ "$ev_fails" = "0" ]; then
    echo "ok   oracle_verified: true exactly where the comparison completed and agreed (typed as JSON bool)"
else
    echo "FAIL oracle_verified value pins: $ev_fails of 7 wrong"
    fails=$((fails + 1))
fi

echo ""
echo "=========== check 4c: the second exhibit — the earliest checker-red world (#231) ==========="
# The poetry shape, shrunk: TOY_SPLIT_REWRITE rewrites derived.txt then
# primary.txt in place (four kill points), and check-split.sh judges only the
# primary. World k=2 (derived mid-write) is an L0-only precision-limit
# observation; world k=4 (primary mid-write) is the checker-red one. The report
# must carry both exhibits, the earliest must own 000001, and the checker
# exhibit's own case must replay. Seen red once against the pre-change binary
# (no checker_earliest field) and once by the write-order mutation drill —
# both recorded in BUILDLOG (2026-08-22).
XD=/tmp/acc-exhibit
rm -rf "$XD" && mkdir -p "$XD/state"
TOY_STATE=$XD/state TOY_SPLIT_REWRITE=1 "$SIDEEYE" explore --state "$XD/state" \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check "$ROOT/spike/check-split.sh" \
    --shim "$SHIM" --work "$XD/work" --oracle /usr/bin/strace --json "$XD/r.json" > "$XD/out.txt" 2>&1
rc=$?
x_fails=0
[ "$rc" = "1" ] || { echo "     explore: exit $rc, wanted 1"; x_fails=$((x_fails + 1)); }
grep -q "^FAIL  2 of 5 explored worlds" "$XD/out.txt" || { echo "     headline: not 'FAIL  2 of 5'"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/r.json" earliest.crash_point)" = "2" ] || { echo "     earliest.crash_point: '$(field "$XD/r.json" earliest.crash_point)', wanted 2"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/r.json" earliest.invariant)" = "built-in atomicity (L0)" ] || { echo "     earliest.invariant: '$(field "$XD/r.json" earliest.invariant)'"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/r.json" checker_earliest.crash_point)" = "4" ] || { echo "     checker_earliest.crash_point: '$(field "$XD/r.json" checker_earliest.crash_point)', wanted 4"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/r.json" checker_earliest.invariant)" = "built-in atomicity, and the checker" ] || { echo "     checker_earliest.invariant: '$(field "$XD/r.json" checker_earliest.invariant)'"; x_fails=$((x_fails + 1)); }
ecase=$(field "$XD/r.json" case)
ccase=$(field "$XD/r.json" checker_earliest.case)
case "$ecase" in */cases/000001.json) : ;; *) echo "     case: '$ecase', wanted .../cases/000001.json"; x_fails=$((x_fails + 1)) ;; esac
case "$ccase" in */cases/000002.json) : ;; *) echo "     checker_earliest.case: '$ccase', wanted .../cases/000002.json"; x_fails=$((x_fails + 1)) ;; esac
# 000001's owner is the earliest, pinned in the case file itself, not by name.
[ "$(field "$ecase" k)" = "2" ] || { echo "     000001's k: '$(field "$ecase" k)', wanted 2 (the earliest)"; x_fails=$((x_fails + 1)); }
[ "$(field "$ccase" k)" = "4" ] || { echo "     000002's k: '$(field "$ccase" k)', wanted 4 (the checker world)"; x_fails=$((x_fails + 1)); }
grep -q "^checker red crash point 4 of 4 (built-in atomicity, and the checker)" "$XD/out.txt" || { echo "     text: no 'checker red' section for the distinct world"; x_fails=$((x_fails + 1)); }
# The checker exhibit's case replays on its own (R1: the replay path is part of
# the frozen surface, so its report is asserted, not assumed). The case carries
# the define, not the environment — the toy's env rides the invocation.
TOY_STATE=$XD/state TOY_SPLIT_REWRITE=1 "$SIDEEYE" replay "$ccase" --shim "$SHIM" --work "$XD/rwork" --json "$XD/rr.json" > "$XD/rout.txt" 2>&1
rrc=$?
[ "$rrc" = "1" ] || { echo "     replay: exit $rrc, wanted 1 (reproduced)"; x_fails=$((x_fails + 1)); }
grep -q "the case reproduced" "$XD/rout.txt" || { echo "     replay: no 'the case reproduced'"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/rr.json" earliest.crash_point)" = "4" ] || { echo "     replay earliest.crash_point: '$(field "$XD/rr.json" earliest.crash_point)', wanted 4"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/rr.json" checker_earliest.crash_point)" = "4" ] || { echo "     replay checker_earliest: '$(field "$XD/rr.json" checker_earliest.crash_point)', wanted 4"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/rr.json" checker_earliest.case)" = "$ccase" ] || { echo "     replay checker_earliest.case: '$(field "$XD/rr.json" checker_earliest.case)', wanted the replayed path"; x_fails=$((x_fails + 1)); }
[ "$(field "$XD/rr.json" checker_earliest.replay)" = "(this run is a replay; the case reproduced)" ] || { echo "     replay checker_earliest.replay: '$(field "$XD/rr.json" checker_earliest.replay)'"; x_fails=$((x_fails + 1)); }
# Same-world control: the plain buggy toy's earliest IS checker-red, so
# checker_earliest mirrors earliest, shares its case, and adds no text
# section. The crash point is pinned to its concrete value (5, the same
# number check 1 pins in text) so a missing/broken fail.json cannot make
# the two field() reads vacuously equal as empty strings (R1).
[ "$(field "$SD/fail.json" checker_earliest.crash_point)" = "5" ] || { echo "     same-world: checker_earliest.crash_point '$(field "$SD/fail.json" checker_earliest.crash_point)', wanted 5"; x_fails=$((x_fails + 1)); }
[ "$(field "$SD/fail.json" earliest.crash_point)" = "5" ] || { echo "     same-world: earliest.crash_point '$(field "$SD/fail.json" earliest.crash_point)', wanted 5"; x_fails=$((x_fails + 1)); }
[ "$(field "$SD/fail.json" checker_earliest.case)" = "$(field "$SD/fail.json" case)" ] && [ -n "$(field "$SD/fail.json" case)" ] || { echo "     same-world: cases differ or empty"; x_fails=$((x_fails + 1)); }
# And the text side of the same-world promise — no `checker red` section —
# needs a captured same-world FAIL, with a positive control on the same
# output so a silent run cannot pass the negative grep vacuously.
rm -rf "$XD/swstate" && mkdir -p "$XD/swstate"
TOY_STATE=$XD/swstate TOY=$OUT/toy-bug "$SIDEEYE" explore --state "$XD/swstate" \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --check "$ROOT/spike/check.sh" \
    --shim "$SHIM" --work "$XD/swwork" --oracle /usr/bin/strace > "$XD/swout.txt" 2>&1
grep -q "atomicity, and the checker" "$XD/swout.txt" || { echo "     same-world text: control line missing (run broke?)"; x_fails=$((x_fails + 1)); }
grep -q "^checker red" "$XD/swout.txt" && { echo "     same-world text: unexpected 'checker red' section"; x_fails=$((x_fails + 1)); }
if [ "$x_fails" = "0" ]; then
    echo "ok   both exhibits carried, 000001 owned by the earliest, the checker case replays"
else
    echo "FAIL the second exhibit: $x_fails assertion(s) wrong"
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
# seen-red-once, kept red forever. #239 added seven more, for the generation model
# and the three cohort ledgers: gen-unstarted-with-manifest (a measured generation
# recorded as unstarted), gen-complete-no-manifest (the reverse), ledger-missing (a
# committed cohort define in none of the three ledgers), ledger-overlap (one define
# claimed by two), ledger-successor (a supersession row whose replacement is in no
# corpus), ledger-unrelated-successor (a replacement that is a different target) and
# outcome-new-this-sweep (an already-triaged tool parked as untriaged).
# The first of those seven was itself red for the wrong reason when it was written —
# count.py read its reports before checking its status, so it died on a missing file
# — which is what this loop's message-matching exists to catch. **Predicates with no
# fixture, named so nobody reads this list as complete.** From #239: the generation
# group closed set, the since/group coverage rule, outcome-map's
# shape/uniqueness/enum, and the *disposition* conservation assert — an A-group FAIL
# whose tool carries a disposition the outcome table does not print, count.py's block
# headed `Conservation:`. That is NOT the attribution checks pinned below: those are a
# different predicate, and they are named attribution precisely so this sentence can
# tell the two apart. From the attribution work: the two post-byte-compare numerator
# bindings — the rate line's, and the outcome table's per-row comparison. Both read
# verdicts, so both would take `tampered-verdict`'s pinned message if they ran before
# the byte-compare; that is measured rather than reasoned, because the outcome one
# was written there first and did exactly that. No data-only fixture reaches either:
# one that perturbs the number dies earlier. Also the (B, judge) axis, which the
# funnel table cannot express because it
# has no judge column, so that family is measured by its denominator alone and the
# check says so in its own success line. Deleting any of these leaves this suite
# green, and that gap is filed rather than left implied. Sunset: never fired by the
# v1.0 freeze -> removal list (same rule as check 11).
ur_fails=0
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT"; then
    echo "     the live page/artifacts disagree with recomputation"
    ur_fails=$((ur_fails + 1))
fi
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/good" >/dev/null 2>&1; then
    echo "     fixture good failed — the gate cannot pass its own known-good input"
    ur_fails=$((ur_fails + 1))
fi
# A second green fixture, and the only place a SETUP_ERROR row exists at all: the
# live page has none and neither does `good`, so the rule that keeps such a row out
# of every denominator was reachable by nothing. Green here proves the exclusion
# holds; removing it from count.py turns THIS fixture red on the attribution row
# count while good and the live tree stay green (measured before shipping).
if ! python3 "$ROOT/spike/unknown-rate/count.py" check --root "$ROOT/spike/unknown-rate/fixtures/setup-error-present" >/dev/null 2>&1; then
    echo "     fixture setup-error-present failed — the SETUP_ERROR exclusion has no other reachable input"
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
    "tampered-manifest:against its expected" \
    "tampered-define:define digest mismatch" \
    "tampered-reason:not in the documented closed set" \
    "predata-no-placeholder:lacks the not-yet-measured placeholder" \
    "gen-unstarted-with-manifest:marked unstarted but" \
    "gen-complete-no-manifest:marked complete but has no manifest" \
    "ledger-missing:in no ledger" \
    "ledger-overlap:must be disjoint" \
    "ledger-successor:which is not a corpus define" \
    "ledger-unrelated-successor:which is a different target" \
    "outcome-new-this-sweep:declaring an already-triaged tool untriaged" \
    "attribution-slice-denominator:a row reaches its slice exactly once" \
    "attribution-slice-numerator:in the published rows" \
    "attribution-family-missing:a slice family that loses a label" \
    "attribution-denominator-drift:the table and the measurement disagree" \
    "attribution-detail-row-missing:rated rows against" \
    "attribution-reason-table:the reason table is" \
    "attribution-reason-sum:the reason counts sum to" \
    "attribution-outcome-sum:a row leaves the ratio without leaving a trace"; do
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
    echo "ok   unknown-rate page in sync; gate red on all twelve tampered fixtures"
else
    echo "FAIL unknown-rate drift gate: $ur_fails problem(s)"
    fails=$((fails + 1))
fi

# ---- #273: the CLI can describe itself, and the description matches the parser ----
#
# Two things had drifted independently. `--help` was not a word the parser knew, so the
# token fell through mode dispatch to usage()+exit 3 and `sideeye --help && ...` took the
# failure branch. And the synopsis had lost a whole mode (`mcp`) plus most of the flags the
# explore and replay lines accept.
#
# The help paths are checked by running them. The synopsis is checked against the parser's
# own source, so a mode or flag added without documenting it fails here rather than in
# someone's terminal.

cli_fails=0

# 1. All three spellings succeed, and all three print the same text.
h1=$("$SIDEEYE" --help 2>&1); rc1=$?
h2=$("$SIDEEYE" -h 2>&1);     rc2=$?
h3=$("$SIDEEYE" help 2>&1);   rc3=$?
for rc in "$rc1" "$rc2" "$rc3"; do
    [ "$rc" = "0" ] || { echo "     a help spelling exited $rc, want 0"; cli_fails=$((cli_fails + 1)); }
done
if [ "$h1" != "$h2" ] || [ "$h2" != "$h3" ]; then
    echo "     the three help spellings do not print the same text"
    cli_fails=$((cli_fails + 1))
fi

# 2. Extras are refused rather than ignored, the way `version` and `mcp` refuse them.
for spelling in --help -h help; do
    "$SIDEEYE" "$spelling" extra >/dev/null 2>&1
    rc=$?
    if [ "$rc" != "3" ]; then
        echo "     sideeye $spelling extra exited $rc, want 3 (extras must not be ignored)"
        cli_fails=$((cli_fails + 1))
    fi
done

# 3. The wrong-invocation path is unchanged: bare `sideeye` still prints the banner and
#    still exits 3. This suite's own CANNOT-RUN probe greps that first line, so adding
#    help must not have moved it.
#
#    The banner is read from the bare invocation's own output. Checking `$h1` instead
#    would be checking the help path a second time: usage() could vanish from the bare
#    branch and this would still pass, which is the "measured a different path than the
#    one that changed" shape.
bare_out=$("$SIDEEYE" 2>&1)
rc=$?
if [ "$rc" != "3" ]; then
    echo "     bare sideeye exited $rc, want 3"
    cli_fails=$((cli_fails + 1))
fi
printf '%s\n' "$bare_out" | head -1 | grep -q "^sideeye " || {
    echo "     the bare invocation's first line no longer starts with 'sideeye '"
    cli_fails=$((cli_fails + 1))
}

# 4. Every mode the parser dispatches on has a synopsis line. Read out of the source rather
#    than from a list kept here: a list would be the second hand-synced copy this repo has
#    already paid for (#65).
#
#    Matched broadly and then filtered, rather than matched narrowly: an `[a-z]+` pattern
#    covers today's seven modes and would silently miss a `show-report` or an `mcp2`, which
#    makes "every mode" a claim the check does not support. Only the flag spellings of help
#    (--help, -h) are dropped — they are answered by the same branch as `help` and get no
#    synopsis line of their own.
# The string literals the parser compares one argv slot against. Both callers below
# want the same thing out of `src/main.zig` and differ only in which slot.
parser_literals() { # argv-index
    grep -oE "eql\(u8, argv\[$1\], \"[^\"]+\"\)" "$ROOT/src/main.zig" |
        sed -e 's/.*, "//' -e 's/")$//' | sort -u
}

for m in $(parser_literals 1 | grep -v '^-'); do
    printf '%s\n' "$h1" | grep -qE "^  sideeye $m( |$)" || {
        echo "     the parser accepts \`sideeye $m\` but the synopsis has no line for it"
        cli_fails=$((cli_fails + 1))
    }
done

# 5. Every flag the synopsis advertises is one the parser actually reads. This catches a
#    misspelling in the usage text — the failure the six flags just added to the explore
#    line could have introduced.
#
#    The reverse direction, a flag a mode accepts but its line omits, is deliberately NOT
#    checked here. Which flags a mode accepts is decided by `if (mode == .preflight)
#    setupError(...)` branches that grep cannot tell apart from acceptance, and driving it
#    by execution needs a list of which flags take a value — a dummy argument after a
#    no-value flag comes back as "unknown option" and reads as a refusal. That list would
#    be another hand-synced copy, so the gap is filed rather than faked.
#    Extracted broadly here too: a narrow `[a-z-]+` would treat a flag the parser reads
#    under any other spelling as one it does not read, and report a drift that is not there.
parsed_flags=$(parser_literals i | grep '^--')
for f in $(printf '%s\n' "$h1" | grep -E '^  sideeye [^[:space:]]+ ' |
           grep -oE '\-\-[A-Za-z0-9][A-Za-z0-9-]*' | sort -u); do
    printf '%s\n' "$parsed_flags" | grep -qx -- "$f" || {
        echo "     the synopsis advertises $f but no parser branch reads it"
        cli_fails=$((cli_fails + 1))
    }
done

# 6. Every flag a mode accepts is on that mode's synopsis line, and every flag the line
#    advertises the mode accepts. This is the third direction, and the one that actually
#    drifted before #273 — `explore` was missing six of the twelve flags it accepts and
#    `replay` one of six, while the two directions above were both satisfied.
#
#    #295 filed it rather than faking it, because the two implementations available then
#    both failed. grep cannot tell `if (mode == .preflight) setupError(...)` from
#    acceptance. Driving it by execution needs to know which flags take a value, since a
#    dummy argument after a no-value flag comes back as "unknown option" and reads as a
#    refusal — and that list would be the hand-synced second copy #65 is about.
#
#    The second one turned out not to be blocked. Arity is measurable: put the flag LAST
#    and a value-taking one reaches the parse loop's own `i + 1 >= argv.len` guard, while
#    a no-value one is handled before that guard and fails elsewhere. Measured per flag
#    here, so no list exists to go stale.
#
#    Acceptance is then a differential. Each line gets a base invocation that parses and
#    fails on the first thing after parsing; an accepted flag leaves that failure
#    untouched and a refused one replaces it. Both directions are compared, because only
#    one of them catches a flag the parser starts refusing: such a flag leaves the
#    accepted set too, so "every accepted flag is advertised" stays true and green.
#
#    The unit is the LINE, not the mode. `explore` has two because `--config` excludes
#    the define-surface flags, so a per-mode union would claim `--config` and `--state`
#    are usable together.

acc_nx=/nonexistent-parent-for-acceptance/child
acc_argjson=/tmp/acc/argmatrix.json
mkdir -p /tmp/acc

# Values that are merely well-formed for their flag. A path that cannot exist serves
# nine of the eleven that take one; the two exceptions validate their value before anything else
# can fail, so a path there produces a complaint about the value and reads as a refusal.
# A stale entry fails loudly rather than quietly — the "accepted somewhere" assertion at
# the end turns it into a flag that no line accepts.
acc_dummy() {
    case "$1" in
        --expect-status)  printf '0' ;;
        --world-timeout)  printf '1' ;;
        --json)           printf '%s' "$acc_argjson" ;;
        # A directory that exists: --cwd is vetted before anything runs, so the
        # nonexistent default below would make the flag read as refused everywhere.
        --cwd)            printf '/' ;;
        *)                printf '%s' "$acc_nx.dummy" ;;
    esac
}

acc_takes_value() {
    "$SIDEEYE" explore "$1" </dev/null 2>&1 | head -1 | grep -q 'an option is missing its value'
}

# Every probe reads from /dev/null. `mcp` starts a stdin-reading server once its
# argument guard stops firing, so a regression in that guard would turn this check from
# a red into a hang. With EOF on stdin the server ends instead of waiting. The demo has
# no equivalent: if it ever accepts a no-value flag, the probe below builds and runs it,
# which is slow rather than stuck, and the catch-all reports that as apparatus breakage.
acc_first() { "$SIDEEYE" "$@" </dev/null 2>&1 | head -1; }

# Empty in, empty out: an unset difference must not read as a single blank token.
acc_sorted() { set -- $1; [ $# -gt 0 ] || return 0; printf '%s\n' "$@" | sort | tr '\n' ' '; }

# The candidates come from the PARSER, never from the synopsis. Taking them from the help
# text lets the text decide what gets compared: delete a flag from a line and it also
# leaves the candidate set, so both sides agree about a smaller world and the check stays
# green. Measured — removing --marker from the explore line dropped the candidates from 13
# to 12 and an earlier draft of this check did not notice.
# Both parsers, not just the shared loop: runDemo compares against rest[i] and would
# otherwise contribute nothing, so a demo-only flag added without a synopsis line would
# be invisible to a check that claims to cover demo. --shim is in the shared loop as well,
# which is the only reason the first draft appeared to cover it.
acc_flags=$( { parser_literals i
    grep -oE 'eql\(u8, rest\[i\], "[^"]+"\)' "$ROOT/src/main.zig" |
        sed -e 's/.*, "//' -e 's/")$//'
  } | sort -u | grep '^--')

# One base per synopsis line, written here rather than derived from the line. A derived
# base would let the synopsis pick its own test: a line that dropped a required flag would
# also stop being tested for it. The line's required part is asserted against the base
# instead, so the two cannot drift apart silently.
#
# The expected failure is pinned too. Without it a base flag is only ever "parsed", not
# "accepted": make the parser refuse --operation in preflight and the base's own failure
# becomes that refusal, every other flag compares equal to it, and the matrix agrees with
# the synopsis while the mode refuses a flag its line advertises. Pinning the message
# turns that into a BROKEN rather than a pass.
#
#   key | base argv | flags the line's required part must name | expected failure
acc_specs="preflight|preflight --state $acc_nx --operation /usr/bin/true|--state --operation|could not be resolved to an absolute path
explore-define|explore --state $acc_nx --operation /usr/bin/true|--state --operation|could not be resolved to an absolute path
explore-config|explore --config $acc_nx.toml|--config|--config could not be read
replay|replay $acc_nx.json||the case file could not be read"

acc_line_for() {
    case "$1" in
        preflight)      printf '%s\n' "$h1" | grep -E '^  sideeye preflight ' ;;
        explore-define) printf '%s\n' "$h1" | grep -E '^  sideeye explore --state ' ;;
        explore-config) printf '%s\n' "$h1" | grep -E '^  sideeye explore --config ' ;;
        replay)         printf '%s\n' "$h1" | grep -E '^  sideeye replay ' ;;
    esac
}

acc_seen=""
acc_lines=0
acc_probes=0

while IFS='|' read -r acc_key acc_base acc_required acc_expect; do
    [ -n "$acc_key" ] || continue
    acc_line=$(acc_line_for "$acc_key")
    if [ -z "$acc_line" ]; then
        echo "     no synopsis line matches the base written here for $acc_key"
        cli_fails=$((cli_fails + 1))
        continue
    fi
    # Exactly one. Splitting a line in two makes the grep return both, and the advertised
    # set becomes their union: each line could be missing half its flags and the union
    # would still match what the mode accepts. The unit is the line.
    if [ "$(printf '%s\n' "$acc_line" | wc -l | tr -d ' ')" != 1 ]; then
        echo "     $acc_key matches more than one synopsis line; the unit of this check is the line"
        cli_fails=$((cli_fails + 1))
        continue
    fi

    # The base must survive argument handling. If it dies there, every flag below reads
    # as refused and the check reports a drift of the entire matrix.
    acc_base_out=$(eval "\"\$SIDEEYE\" $acc_base" </dev/null 2>&1 | head -1)
    case "$acc_base_out" in
        *"$acc_expect"*) ;;
        *)
            echo "     the $acc_key base should fail with [$acc_expect] and failed with: $acc_base_out"
            cli_fails=$((cli_fails + 1))
            continue
            ;;
    esac

    acc_line_required=$(printf '%s' "$acc_line" | sed 's/\[.*//' |
        grep -oE '\-\-[A-Za-z0-9][A-Za-z0-9-]*' | sort -u | tr '\n' ' ')
    if [ "$acc_line_required" != "$(acc_sorted "$acc_required")" ]; then
        echo "     the $acc_key line requires [$acc_line_required] but its base names [$(acc_sorted "$acc_required")]"
        cli_fails=$((cli_fails + 1))
        continue
    fi

    acc_advertised=$(printf '%s' "$acc_line" | grep -oE '\-\-[A-Za-z0-9][A-Za-z0-9-]*' | sort -u | tr '\n' ' ')

    acc_accepted=""
    for acc_f in $acc_flags; do
        # A flag in the base parsed by definition — the base got past argument handling.
        case " $acc_base " in
            *" $acc_f "*) acc_accepted="$acc_accepted $acc_f"; continue ;;
        esac
        if acc_takes_value "$acc_f"; then
            acc_out=$(eval "\"\$SIDEEYE\" $acc_base \"\$acc_f\" \"\$(acc_dummy \"\$acc_f\")\"" </dev/null 2>&1 | head -1)
        else
            acc_out=$(eval "\"\$SIDEEYE\" $acc_base \"\$acc_f\"" </dev/null 2>&1 | head -1)
        fi
        acc_probes=$((acc_probes + 1))
        [ "$acc_out" = "$acc_base_out" ] && acc_accepted="$acc_accepted $acc_f"
    done
    acc_accepted=$(acc_sorted "$acc_accepted")

    if [ "$acc_accepted" != "$acc_advertised" ]; then
        echo "     $acc_key accepts [$acc_accepted] but its synopsis line names [$acc_advertised]"
        cli_fails=$((cli_fails + 1))
    fi
    acc_seen="$acc_seen $acc_accepted"
    acc_lines=$((acc_lines + 1))
done <<ACC_SPECS
$acc_specs
ACC_SPECS

# `demo` is parsed by runDemo, before the mode enum, so it drifts independently of
# everything above. Probed with the flag LAST, which never starts the demo: --shim is its
# only flag and it takes a value, so a hit is "missing its value" and everything else is
# the refusal. A demo that actually ran would mean it gained a no-value flag, and that is
# apparatus breakage rather than an answer.
acc_demo_line=$(printf '%s\n' "$h1" | grep -E '^  sideeye demo')
acc_demo_advertised=$(printf '%s' "$acc_demo_line" | grep -oE '\-\-[A-Za-z0-9][A-Za-z0-9-]*' | sort -u | tr '\n' ' ')
acc_demo_accepted=""
for acc_f in $acc_flags; do
    acc_out=$(acc_first demo "$acc_f")
    acc_probes=$((acc_probes + 1))
    case "$acc_out" in
        *"demo takes only"*) ;;
        *"is missing its value"*) acc_demo_accepted="$acc_demo_accepted $acc_f" ;;
        *)
            echo "     the demo probe for $acc_f neither refused nor asked for a value: $acc_out"
            cli_fails=$((cli_fails + 1))
            ;;
    esac
done
acc_demo_accepted=$(acc_sorted "$acc_demo_accepted")
if [ "$acc_demo_accepted" != "$acc_demo_advertised" ]; then
    echo "     demo accepts [$acc_demo_accepted] but its synopsis line names [$acc_demo_advertised]"
    cli_fails=$((cli_fails + 1))
fi
acc_seen="$acc_seen $acc_demo_accepted"
acc_lines=$((acc_lines + 1))

# The three argument-free modes. Their lines advertise nothing, so the claim is that they
# accept nothing — checked by execution rather than assumed, and the flag alone never
# starts the MCP server because the refusal happens before anything else.
for acc_m in mcp help version; do
    acc_m_line=$(printf '%s\n' "$h1" | grep -E "^  sideeye $acc_m\$")
    if [ -z "$acc_m_line" ]; then
        echo "     the synopsis has no bare line for $acc_m"
        cli_fails=$((cli_fails + 1))
        continue
    fi
    for acc_f in $acc_flags; do
        acc_out=$(acc_first "$acc_m" "$acc_f")
        acc_probes=$((acc_probes + 1))
        case "$acc_out" in
            *"takes no arguments"*) ;;
            *)
                echo "     $acc_m accepts $acc_f, which its synopsis line does not advertise: $acc_out"
                cli_fails=$((cli_fails + 1))
                ;;
        esac
    done
    acc_lines=$((acc_lines + 1))
done

# Every flag the parser reads has to be accepted by at least one line. A flag accepted
# nowhere is either a real finding or a stale acc_dummy entry, and both need looking at;
# without this, a dummy that stopped being well-formed would quietly turn its flag into a
# refusal everywhere and the matrix would still be self-consistent.
for acc_f in $acc_flags; do
    case " $acc_seen " in
        *" $acc_f "*) ;;
        *)
            echo "     $acc_f is accepted by no synopsis line — a real drift, or acc_dummy no longer gives it a well-formed value"
            cli_fails=$((cli_fails + 1))
            ;;
    esac
done

# Every synopsis line has to have been covered. The four bases above are written here,
# so a line added to the usage text would simply not be tested — the same shape as taking
# the candidate flags from the synopsis, one level up: the check would choose which lines
# exist rather than the text. Counted from the text and compared against what ran.
acc_declared=$(printf '%s\n' "$h1" | grep -cE '^  sideeye ')
if [ "$acc_declared" != "$acc_lines" ]; then
    echo "     the synopsis has $acc_declared lines but this check covered $acc_lines — a line was added without a base"
    cli_fails=$((cli_fails + 1))
fi

# The scan volume is part of the result: a loop that silently covered nothing reports the
# same zero failures as one that covered everything.
echo "     arg matrix: $acc_lines of $acc_declared synopsis lines x $(printf '%s\n' $acc_flags | wc -l | tr -d ' ') parser flags, $acc_probes probes"

if [ "$cli_fails" = "0" ]; then
    echo "ok   help exits 0 in three spellings, refuses extras, and the synopsis and parser agree in all three directions"
else
    echo "FAIL CLI self-description: $cli_fails problem(s)"
    fails=$((fails + 1))
fi

echo "=========== check 15: help is answered per mode, and cannot reach the parser (#296) ==========="
# `sideeye --help` has worked since #273, but only at the top level: the branch sits
# before the mode dispatch, so once a mode word is consumed `--help` falls through to
# the parse loop. Measured before this check was written, on the four modes that take
# flags — four different failures, none of them help:
#
#   explore --help    an option is missing its value   (the arity guard: --help is last)
#   preflight --help  an option is missing its value
#   replay --help     the usage banner, exit 3         (dispatch rejects a leading '-')
#   demo --help       demo takes only --shim <lib>...
#
# The ticket's own transcript says explore prints "unknown option"; it does not. That
# is what the four-element form produces. The failure is real, the transcript is not.
#
# WHY THE SHAPE IS EXACT, and why this check does not ask for more. The obvious fix —
# treat --help as a no-value flag inside the shared loop — deletes files. `--json`
# calls removeFile() while parsing, so `explore --state X --json report.json --help`
# would remove an existing report on the way to printing usage. Answering only
# `[sideeye, <mode>, --help]`, before the dispatch, cannot reach the loop at all.
# Late-position help is therefore NOT supported and NOT checked here: it needs the
# parser split into a side-effect-free stage and a side-effecting one, which is a
# larger change than this ticket.
#
# The mode list is read out of src/main.zig, never written here. A list here would let
# the check pick its own population: add a mode and the check would keep passing over
# the old set. Same reason #295 takes its flag candidates from the parser.
help_fails=0

# The modes that take flags, from the parser. mcp/help/version take no arguments and
# keep refusing extras, so they are deliberately absent — their synopsis lines advertise
# nothing and --help is an extra there in the literal sense.
help_modes=$(parser_literals 1 | grep -v '^-' | grep -vE '^(mcp|help|version)$')
help_mode_n=$(printf '%s\n' $help_modes | grep -c .)
if [ "$help_mode_n" -lt 4 ]; then
    echo "     only $help_mode_n flag-taking modes came out of the parser; expected at least 4"
    help_fails=$((help_fails + 1))
fi

help_dir=/tmp/acc-help.$$
mkdir -p "$help_dir"
"$SIDEEYE" --help > "$help_dir/canonical" 2>"$help_dir/canonical.err"
help_rc=$?
if [ "$help_rc" != "0" ] || [ ! -s "$help_dir/canonical" ]; then
    echo "     sideeye --help itself is not usable as the reference (rc=$help_rc)"
    help_fails=$((help_fails + 1))
fi

# rc, stdout and stderr are three separate assertions, and stdout is compared with cmp
# rather than in a shell variable: command substitution strips trailing newlines, so a
# variable comparison cannot honestly be called byte-identical.
for help_m in $help_modes; do
    for help_spelling in --help -h; do
        "$SIDEEYE" "$help_m" "$help_spelling" > "$help_dir/out" 2>"$help_dir/err"
        help_rc=$?
        [ "$help_rc" = "0" ] || {
            echo "     sideeye $help_m $help_spelling exited $help_rc, want 0"
            help_fails=$((help_fails + 1)); }
        cmp -s "$help_dir/canonical" "$help_dir/out" || {
            echo "     sideeye $help_m $help_spelling does not print what sideeye --help prints"
            help_fails=$((help_fails + 1)); }
        # Weak on its own: setupError writes to STDOUT in this program (measured), so a
        # failing help path leaves stderr empty too. The cmp above is what catches that.
        # This one catches a help path that starts writing to stderr at all.
        if [ -s "$help_dir/err" ]; then
            echo "     sideeye $help_m $help_spelling wrote to stderr: $(head -c 120 "$help_dir/err")"
            help_fails=$((help_fails + 1))
        fi
    done

    # Extras still refuse, the way the top level refuses them (#273). Without this the
    # exact shape could quietly become a prefix match.
    "$SIDEEYE" "$help_m" --help extra >/dev/null 2>&1
    if [ "$?" = "0" ]; then
        echo "     sideeye $help_m --help extra exited 0; the shape is meant to be exact"
        help_fails=$((help_fails + 1))
    fi
done


# The flag that takes a value still takes it. `--marker --help` means a marker whose
# bytes are "--help", and a pre-scan for --help anywhere would have broken that.
#
# Compared against a control rather than against a fixed message. The first draft
# expected "an option is missing its value" and was simply wrong about which failure
# comes next — --marker swallows --help, the loop ends, and the run dies on the missing
# --state. Asserting the message would have pinned this check to today's ordering of
# unrelated guards. Asserting that --help and an ordinary value reach the SAME place
# pins the property: whatever --marker does with its value, it does it to both.
"$SIDEEYE" explore --marker --help > "$help_dir/marker.err" 2>&1
help_marker_rc=$?
"$SIDEEYE" explore --marker ZZZ > "$help_dir/control.err" 2>&1
help_control_rc=$?
# The exit status is compared too. Output alone would let a regression through that
# prints the same refusal and then exits 0 — which is precisely what a help branch
# reached at this position would do.
if [ "$help_marker_rc" != "$help_control_rc" ] || [ "$help_marker_rc" = "0" ]; then
    echo "     explore --marker --help exited $help_marker_rc against the control's $help_control_rc (both should be equal and non-zero)"
    help_fails=$((help_fails + 1))
fi
if ! cmp -s "$help_dir/marker.err" "$help_dir/control.err"; then
    echo "     explore --marker --help did not take the same path as --marker ZZZ; --help was not consumed as a value"
    help_fails=$((help_fails + 1))
fi
# Both must be non-empty: two empty files compare equal, and would pass this vacuously.
if [ ! -s "$help_dir/control.err" ]; then
    echo "     the --marker control produced no output, so the comparison above measures nothing"
    help_fails=$((help_fails + 1))
fi

# LATE-POSITION HELP MUST STILL REFUSE, and this is the assertion that protects the
# design. `--json` calls removeFile() while parsing, so a help branch that lives in the
# shared loop would answer `explore --state X --json report.json --help` with usage and
# exit 0 — after deleting report.json. The shape that ships is answered before the loop
# and cannot reach it.
#
# Checked by execution, with a --json path that does not exist and is not created: the
# probe cannot destroy anything whether or not the regression is present. A non-zero
# exit is the assertion. Do NOT relax this to "the file survived" — under the shipping
# design the file is deleted by the normal parse anyway, so survival is not the property.
#
# The first version of this block was a grep for `eql(u8, argv[i], "--help")` and
# claimed that moving help into the loop "in any form" would go red. It would not:
# `eql(u8, "--help", argv[i])` has the same meaning and a different shape, and passes.
# The grep is kept below as a cheap second opinion, but it is not the assertion.
help_late_nx=/nonexistent-parent-for-help/report.json
for help_m in $help_modes; do
    case "$help_m" in demo) continue ;; esac   # demo has its own parser and no --json
    "$SIDEEYE" "$help_m" --json "$help_late_nx" --help </dev/null >/dev/null 2>&1
    help_rc=$?
    if [ "$help_rc" = "0" ]; then
        echo "     sideeye $help_m --json <path> --help exited 0; late-position help is answered inside the parse loop, which has already called removeFile on that path"
        help_fails=$((help_fails + 1))
    fi
done

# The cheap second opinion. Narrower than the check above by construction — it knows one
# spelling of the comparison — so it is not load-bearing, and it is not described as if
# it were. It costs nothing and names the design decision where a reader will look.
help_loop=$(grep -cE 'eql\(u8, (argv|rest)\[i\], "(--help|-h)"\)' "$ROOT/src/main.zig")
[ "$help_loop" = "0" ] || {
    echo "     --help/-h appears as a parse-loop literal in src/main.zig ($help_loop site(s)); help must be answered before the loop, which calls removeFile for --json"
    help_fails=$((help_fails + 1)); }

rm -f "$help_dir"/canonical "$help_dir"/canonical.err "$help_dir"/out "$help_dir"/err "$help_dir"/marker.err "$help_dir"/control.err
rmdir "$help_dir" 2>/dev/null || true

if [ "$help_fails" = "0" ]; then
    echo "ok   $help_mode_n modes answer --help and -h with the top-level text, exit 0, and no help path enters the parse loop"
else
    echo "FAIL per-mode help: $help_fails problem(s)"
    fails=$((fails + 1))
fi

echo "=========== check 16: the destructive root is vetted before setup, and again before each delete (#267) ==========="

# Two directions, and the second is the one that matters. A denylist in front of the
# delete is easy to satisfy and easy to fool: the resolution it relies on happens before
# --setup, so a setup command that leaves a symlink where the state directory was sends
# the delete somewhere else with every list still satisfied. Leg (b) is that case.
vet_fails=0
vet_dir=/tmp/acc-vet
rm -rf "$vet_dir"
mkdir -p "$vet_dir/outside" "$vet_dir/state"

# (a1) A system tree that EXISTS is refused by the vet, by name. /var/lib is present on
#      both platforms this runs on, so the resolution ahead of the vet succeeds and the
#      vet is what answers. A non-existent path under the same tree does not test this:
#      whether the engine can create it decides which refusal fires first, and this leg
#      is about the message.
o=$("$SIDEEYE" explore --state /var/lib --operation /bin/true \
    --shim "$SHIM" --work "$vet_dir/work-a" 2>&1) && vrc=0 || vrc=$?
case "$o" in
    *"nothing sacrificial belongs in"*) : ;;
    *) echo "     denied root: wanted the sacrificial-root refusal, got: $(printf '%s' "$o" | head -1)"
       vet_fails=$((vet_fails + 1)) ;;
esac
[ "$vrc" = "3" ] || { echo "     denied root: exit $vrc, wanted 3 (setup error)"; vet_fails=$((vet_fails + 1)); }

# (a2) A refusal must leave the filesystem as it found it. The resolution needs a mkdir
#      first, so the vet has to undo it. Only the refusal and the absence are asserted
#      here, not the message: as root the vet answers, and without permission to create
#      the directory the earlier resolution failure answers instead. Both are refusals,
#      and which one arrives is a property of the machine rather than of this change.
vet_denied=/var/lib/acc-vet-should-not-exist
o=$("$SIDEEYE" explore --state "$vet_denied" --operation /bin/true \
    --shim "$SHIM" --work "$vet_dir/work-a2" 2>&1) && vrc_a2=0 || vrc_a2=$?
[ "$vrc_a2" = "3" ] || { echo "     denied root (absent): exit $vrc_a2, wanted 3"; vet_fails=$((vet_fails + 1)); }
[ -d "$vet_denied" ] && { echo "     denied root (absent): the refusal created the directory it refused"; vet_fails=$((vet_fails + 1)); }

# (b) A root replaced between the resolution and the exploration does not produce a
#     verdict. Measured: what answers here is not the re-vet in front of the delete but
#     the structural detector that runs before any world — the swap makes the state
#     change with no recorded operation, and the run refuses at that point, so nothing is
#     deleted either way. That is a pre-existing protection and this leg pins it as one.
#
#     The re-vet covers a different timing: the recorded operation, which runs hundreds
#     of times, replacing the root between one world's resolution and the next world's
#     delete. No define can stage that here, because the structural detectors see the
#     first swap first. It is pinned instead at the call sites in src/engine.zig, where
#     removing `assertRootUnchanged` from either `restore` or `freshDir` turns a test red.
#
#     Two earlier versions of this leg claimed to test the re-vet and did not. The first
#     used a sentinel inside the link's target, which the snapshot copies and `restore`
#     writes back — structurally unable to fail. The second used `/bin/true` as the
#     operation, which records nothing, so no world ran at all.
cat > "$vet_dir/swap.sh" <<SWAP
#!/bin/sh
rm -rf "$vet_dir/state"
ln -s "$vet_dir/outside" "$vet_dir/state"
SWAP
chmod 755 "$vet_dir/swap.sh"
# The operation has to write into the state directory. A define whose operation records
# nothing (/bin/true) never produces a world, so `restore` is never reached and the
# re-vet never runs — measured: this leg passed on one platform and reported
# `completeness_not_verified` on the other, neither for the reason it claims to test.
cat > "$vet_dir/op.sh" <<OP
#!/bin/sh
echo x > "$vet_dir/state/written"
OP
chmod 755 "$vet_dir/op.sh"
o=$("$SIDEEYE" explore --state "$vet_dir/state" --setup "$vet_dir/swap.sh" \
    --operation "$vet_dir/op.sh" --shim "$SHIM" --work "$vet_dir/work-b" 2>&1) && vrc2=0 || vrc2=$?
case "$o" in
    *state_changed_without_ops*) : ;;
    *) echo "     root swap: wanted the structural refusal (state_changed_without_ops), got: $(printf '%s' "$o" | head -1)"
       vet_fails=$((vet_fails + 1)) ;;
esac
case "$o" in
    *PASS*) echo "     root swap: a state directory replaced by a link produced a PASS"
            vet_fails=$((vet_fails + 1)) ;;
    *) : ;;
esac
[ "$vrc2" = "0" ] && {
    echo "     root swap: exit 0 over a state directory that had been replaced by a link"
    vet_fails=$((vet_fails + 1)); }

# Control for (b): the same define without the swap must still run. Without this, an
# implementation that refuses every root at all passes the two assertions above.
cat > "$vet_dir/noswap.sh" <<NOSWAP
#!/bin/sh
mkdir -p "$vet_dir/state2"
: > "$vet_dir/state2/seed"
NOSWAP
chmod 755 "$vet_dir/noswap.sh"
mkdir -p "$vet_dir/state2"
cat > "$vet_dir/op2.sh" <<OP2
#!/bin/sh
echo x > "$vet_dir/state2/written"
OP2
chmod 755 "$vet_dir/op2.sh"
o=$("$SIDEEYE" explore --state "$vet_dir/state2" --setup "$vet_dir/noswap.sh" \
    --operation "$vet_dir/op2.sh" --shim "$SHIM" --work "$vet_dir/work-c" 2>&1) && vrc3=0 || vrc3=$?
# The control has to show the define REACHED exploration, not merely that these two
# messages are absent: any other refusal, or an UNKNOWN raised before the first world,
# would satisfy an absence test. `atomicity ... path(s) judged` only appears once worlds
# have been judged, so it is the line that says the vet let the run through.
case "$o" in
    *"nothing sacrificial belongs in"*|*"could not be confirmed as the one this run resolved"*)
        echo "     control: an unswapped scratch root under /tmp was refused"
        vet_fails=$((vet_fails + 1)) ;;
    *) : ;;
esac
case "$o" in
    *"path(s) judged"*) : ;;
    *) echo "     control: the unswapped define never reached exploration: $(printf '%s' "$o" | head -1)"
       vet_fails=$((vet_fails + 1)) ;;
esac
# No exit-code assertion here. Without --oracle the run is UNKNOWN and exits 2, which is
# a different contract's business; pinning it in this check would make an unrelated policy
# change look like a destructive-root regression. The line above is the discriminator.
: "${vrc3:?}"

rm -rf "$vet_dir" "$vet_denied" 2>/dev/null || true

if [ "$vet_fails" = "0" ]; then
    echo "ok   a system tree is refused without being created, and a root replaced after resolution refuses instead of producing a verdict"
else
    echo "FAIL destructive-root vet: $vet_fails problem(s)"
    fails=$((fails + 1))
fi

echo "=========== check 17: --stop-when-orphaned stops at the next world boundary (#269) ==========="

# The launcher is assassinated by the define's own setup. That staging is what makes this
# deterministic: the launcher is provably alive when the engine records its getppid()
# baseline (the engine is its direct child, forked a moment earlier), and provably dead
# before the first world boundary (setup runs before the recording run). Three earlier
# stagings all had timing windows or measured the wrong pid: `exec` keeps the pid so the
# recorded pid WAS the engine; a forked launcher raced the sub-second exploration; and a
# sleep wrapper on the operation created a process boundary that ended the run before any
# world. Killing the parent from inside the run replaces every window with an ordering.
#
# "No world ran" is asserted on the REPORT's `explored` field, not on text. The text
# `explored N worlds` appears only on the PASS/FAIL paths, so its absence under UNKNOWN
# says nothing — an earlier assertion built on it stayed green when the guard was moved
# after the first world. The JSON field is written on every path.
ppid_fails=0
ppid_dir=/tmp/acc-ppid
rm -rf "$ppid_dir"
mkdir -p "$ppid_dir/state" "$ppid_dir/work"

cat > "$ppid_dir/assassin-setup.sh" <<PPSETUP
#!/bin/sh
kill -9 \$(cat "$ppid_dir/launcher.pid") 2>/dev/null
$OUT/toy-bug init
PPSETUP
cat > "$ppid_dir/plain-setup.sh" <<PPSETUP2
#!/bin/sh
$OUT/toy-bug init
PPSETUP2
chmod 755 "$ppid_dir/assassin-setup.sh" "$ppid_dir/plain-setup.sh"

ppid_field() { # json-path key
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); v=r.get(sys.argv[2]); print("" if v is None else v)' "$1" "$2" 2>/dev/null
}

# Leg 1: flag + assassinated launcher -> parent_exited before ANY world.
#
# The trailing `; se_rc=$?; exit $se_rc` is load-bearing: POSIX permits a shell to exec
# the last command of `sh -c`, and an exec'd engine IS the recorded pid — the assassin
# would then shoot the engine instead of the launcher. Both dashes at hand fork here
# (measured, bookworm and ubuntu), but the staging must not lean on unspecified
# behaviour, and the 137 assert below turns any violation loud.
sh -c "echo \$\$ > '$ppid_dir/launcher.pid'; '$SIDEEYE' explore --state '$ppid_dir/state' --setup '$ppid_dir/assassin-setup.sh' --operation '$OUT/toy-bug rotate' --shim '$SHIM' --work '$ppid_dir/work' --json '$ppid_dir/r1.json' --oracle /usr/bin/strace --stop-when-orphaned > '$ppid_dir/out1.txt' 2>&1; se_rc=\$?; exit \$se_rc" &
ppid_lw=$!
ppid_i=0
while [ ! -s "$ppid_dir/r1.json" ] && [ "$ppid_i" -lt 100 ]; do sleep 0.1; ppid_i=$((ppid_i + 1)); done
wait "$ppid_lw" 2>/dev/null
ppid_lrc=$?
# Staging precondition, same as mcp 9's: the launcher died by the assassin's SIGKILL.
# Any other exit means the kill went somewhere else and nothing below measures what it
# claims to.
[ "$ppid_lrc" = "137" ] || {
    echo "     leg 1 staging: the launcher exited $ppid_lrc, not 137 (SIGKILL) — the assassin did not shoot the launcher"
    ppid_fails=$((ppid_fails + 1)); }
[ "$(ppid_field "$ppid_dir/r1.json" unknown_reason)" = "parent_exited" ] || {
    echo "     leg 1: wanted unknown_reason parent_exited, got '$(ppid_field "$ppid_dir/r1.json" unknown_reason)' (verdict '$(ppid_field "$ppid_dir/r1.json" verdict)')"
    ppid_fails=$((ppid_fails + 1)); }
[ "$(ppid_field "$ppid_dir/r1.json" explored)" = "0" ] || {
    echo "     leg 1: explored=$(ppid_field "$ppid_dir/r1.json" explored), wanted 0 — worlds ran after the launcher died"
    ppid_fails=$((ppid_fails + 1)); }

# Leg 2: flag + living launcher (this shell) -> explores normally. Separates "reads the
# flag" from "refuses whenever the flag is present".
rm -rf "$ppid_dir/state" "$ppid_dir/work"; mkdir -p "$ppid_dir/state" "$ppid_dir/work"
"$SIDEEYE" explore --state "$ppid_dir/state" --setup "$ppid_dir/plain-setup.sh" \
    --operation "$OUT/toy-bug rotate" --shim "$SHIM" --work "$ppid_dir/work" \
    --json "$ppid_dir/r2.json" --oracle /usr/bin/strace --stop-when-orphaned \
    > "$ppid_dir/out2.txt" 2>&1
ppid_rc2=$?
[ "$ppid_rc2" = "1" ] || { echo "     leg 2: exit $ppid_rc2, wanted 1 (the buggy toy FAILs)"; ppid_fails=$((ppid_fails + 1)); }
ppid_e2=$(ppid_field "$ppid_dir/r2.json" explored)
[ -n "$ppid_e2" ] && [ "$ppid_e2" -gt 0 ] || {
    echo "     leg 2: explored='$ppid_e2', wanted > 0 — a live launcher must not stop the run"
    ppid_fails=$((ppid_fails + 1)); }

# Leg 3: NO flag + assassinated launcher -> explores normally. This is the nohup pattern:
# without the opt-in, an orphaned run keeps going, and it separates "gated by the flag"
# from "checks unconditionally".
rm -rf "$ppid_dir/state" "$ppid_dir/work"; mkdir -p "$ppid_dir/state" "$ppid_dir/work"
sh -c "echo \$\$ > '$ppid_dir/launcher.pid'; '$SIDEEYE' explore --state '$ppid_dir/state' --setup '$ppid_dir/assassin-setup.sh' --operation '$OUT/toy-bug rotate' --shim '$SHIM' --work '$ppid_dir/work' --json '$ppid_dir/r3.json' --oracle /usr/bin/strace > '$ppid_dir/out3.txt' 2>&1; se_rc=\$?; exit \$se_rc" &
ppid_lw=$!
ppid_i=0
while [ ! -s "$ppid_dir/r3.json" ] && [ "$ppid_i" -lt 100 ]; do sleep 0.1; ppid_i=$((ppid_i + 1)); done
wait "$ppid_lw" 2>/dev/null
ppid_lrc=$?
[ "$ppid_lrc" = "137" ] || {
    echo "     leg 3 staging: the launcher exited $ppid_lrc, not 137 (SIGKILL)"
    ppid_fails=$((ppid_fails + 1)); }
[ "$(ppid_field "$ppid_dir/r3.json" unknown_reason)" = "parent_exited" ] && {
    echo "     leg 3: refused with parent_exited although the flag was not given"
    ppid_fails=$((ppid_fails + 1)); }
ppid_e3=$(ppid_field "$ppid_dir/r3.json" explored)
[ -n "$ppid_e3" ] && [ "$ppid_e3" -gt 0 ] || {
    echo "     leg 3: explored='$ppid_e3', wanted > 0 — an orphan without the flag must finish"
    ppid_fails=$((ppid_fails + 1)); }

rm -rf "$ppid_dir"

if [ "$ppid_fails" = "0" ]; then
    echo "ok   an assassinated launcher stops the run before any world; a live launcher and a flagless orphan both explore to the end"
else
    echo "FAIL stop-when-orphaned: $ppid_fails problem(s)"
    fails=$((fails + 1))
fi

# The trace read's cap names itself at BOTH read sites (#324). Neither can be reached
# by a fixture: the engine unlinks the trace before every run, so no oversized file can
# be planted, and the shipped 64 MiB ceiling would need on the order of a million
# recorded operations to reach through the only writer there is. So the apparatus lowers
# the cap instead — two separately named engines that plain `zig build` never produces,
# one capping the recording read and one capping the world read. Two, because the
# recording read happens first and exits: a single binary capping both can only ever
# demonstrate the first branch.
#
# What this pins is the WIRING, which no unit test can reach: the branches live in
# main.zig, whose refusals exit the process. Disabling the check turns BOTH legs red at
# once, each with the refusal its own collapse produces — `no_shim_marker` at the
# recording read, `kill_did_not_land` at the world read, the latter a claim about the
# engine's own kill drawn from a trace the engine declined to read. Reverting either
# call site alone turns that site's leg red on the reason, not on the exit code: both
# collapses still exit 2, so the grep is what does the work.
CAPBIN=$ROOT/zig-out/bin/sideeye-testtracecap
CAPBIN_W=$ROOT/zig-out/bin/sideeye-testtracecap-world
if [ ! -x "$CAPBIN" ] || [ ! -x "$CAPBIN_W" ]; then
    echo "FAIL trace-cap apparatus missing: build with zig build -Dtest-trace-cap (add -Dtarget=... for the container)"
    fails=$((fails + 1))
else
    # One parent for all three runs, removed once at the end. Three separate
    # /tmp/acc-* trees would follow the suite's usual shape, but this check is run
    # repeatedly while its own mutations are measured, and each run left three more
    # directories behind on any machine where the recursive remove is intercepted.
    capdir=/tmp/acc-tracecap-$$
    cap_fails=0
    for site in recording world; do
        case "$site" in
            recording) bin=$CAPBIN;   want="the recording run" ;;
            world)     bin=$CAPBIN_W; want="an explored world" ;;
        esac
        d=$capdir/$site
        mkdir -p "$d/state"
        o=$(TOY_STATE=$d/state "$bin" explore --state "$d/state" \
            --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
            --shim "$SHIM" --work "$d/work" --allow-unverified 2>&1)
        rc=$?
        if [ "$rc" != "2" ]; then
            echo "FAIL trace cap ($site): expected exit 2, got $rc"
            cap_fails=$((cap_fails + 1))
        elif ! echo "$o" | grep -q "trace_too_large"; then
            echo "FAIL trace cap ($site): refused as something else — $(echo "$o" | head -2 | tr '\n' ' ')"
            cap_fails=$((cap_fails + 1))
        elif ! echo "$o" | grep -q "the trace from $want"; then
            echo "FAIL trace cap ($site): the refusal does not name which read it was"
            cap_fails=$((cap_fails + 1))
        elif ! echo "$o" | grep -q "against a 64-byte cap"; then
            # The cap in the message must be the one that fired, not the shipped
            # constant. It said 67108864 once, on a run capped at 64.
            echo "FAIL trace cap ($site): the message names a cap that did not fire"
            cap_fails=$((cap_fails + 1))
        fi
    done
    # The control: the shipped engine, same define, is nowhere near its ceiling and
    # reaches a verdict. Without it, an engine that refused every trace would pass the
    # two legs above.
    d=$capdir/control
    mkdir -p "$d/state"
    TOY_STATE=$d/state "$SIDEEYE" explore --state "$d/state" \
        --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
        --shim "$SHIM" --work "$d/work" --allow-unverified >/dev/null 2>&1
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "FAIL trace cap (control): the shipped engine did not reach a verdict (exit $rc)"
        cap_fails=$((cap_fails + 1))
    fi
    rm -rf "$capdir"
    if [ "$cap_fails" = "0" ]; then
        echo "ok   the trace cap names itself at both read sites, and the shipped cap is nowhere near"
    else
        fails=$((fails + 1))
    fi
fi

echo "=========== check: a rewrite the engine cannot perform refuses in its own phase (#363 Group B) ==========="
# state_rewrite_failed: after the define has run, the engine failing to rewrite the
# state tree it recorded is UNKNOWN with that name, never a SETUP ERROR; before the
# define, the same failure honestly stays exit 3. The plant is a subdirectory the
# snapshot can read (r-x) but whose entries cannot be unlinked (no write bit on the
# directory), so it survives the initial snapshot and kills the first rewrite that
# tries to delete through it. Planted from the shell for 2fc's reason. Non-root only:
# root ignores permission bits, so the plant does not fire there (this suite's CI
# runner is non-root; spike/Dockerfile run bare is root, and there these legs FAIL
# loudly rather than skip).
#
# Leg A: the world loop's restore, the first rewrite a checkerless run reaches.
rm -rf /tmp/acc-rw && mkdir -p /tmp/acc-rw/state/pin
echo x > /tmp/acc-rw/state/pin/f
chmod 555 /tmp/acc-rw/state/pin
o=$(TOY_STATE=/tmp/acc-rw/state "$SIDEEYE" explore --state /tmp/acc-rw/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --shim "$SHIM" --work /tmp/acc-rw/work --allow-unverified \
    --json /tmp/acc-rw/r.json 2>&1)
rc=$?
if [ "$rc" = "2" ] \
    && echo "$o" | grep -q "state_rewrite_failed" \
    && echo "$o" | grep -q "could not restore the state directory" \
    && grep -q '"unknown_reason": "state_rewrite_failed"' /tmp/acc-rw/r.json \
    && grep -q '"verdict": "UNKNOWN"' /tmp/acc-rw/r.json \
    && ! grep -q '"earliest"' /tmp/acc-rw/r.json; then
    echo "ok   a restore the engine cannot perform past the recording run is UNKNOWN state_rewrite_failed"
else
    echo "FAIL rewrite failure at a world boundary: exit $rc (wanted 2 + state_rewrite_failed + UNKNOWN verdict with no earliest)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# Leg B: the falsification probe's restore — the earlier rewrite a checkered run
# reaches first. Distinguishes an implementation that rerouted only the world loop.
# /bin/true stands in for the checker: the probe's restore fails before any checker
# would run, so its content is irrelevant by construction.
rm -f /tmp/acc-rw/r.json
o=$(TOY_STATE=/tmp/acc-rw/state "$SIDEEYE" explore --state /tmp/acc-rw/state \
    --setup "$OUT/toy-fixed init" --operation "$OUT/toy-fixed rotate" \
    --check /bin/true \
    --shim "$SHIM" --work /tmp/acc-rw/work-b --allow-unverified \
    --json /tmp/acc-rw/r.json 2>&1)
rc=$?
if [ "$rc" = "2" ] \
    && echo "$o" | grep -q "state_rewrite_failed" \
    && echo "$o" | grep -q "before falsifying the checker" \
    && grep -q '"unknown_reason": "state_rewrite_failed"' /tmp/acc-rw/r.json; then
    echo "ok   the falsification probe's restore refuses with the same name, at its own site"
else
    echo "FAIL rewrite failure at the probe: exit $rc (wanted 2 + state_rewrite_failed + the probe's wording)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
chmod 755 /tmp/acc-rw/state/pin 2>/dev/null
rm -rf /tmp/acc-rw
# Leg C, the contrast: the same plant, reached BEFORE the define runs — replay's
# --fresh-state emptying (the flag is replay-only) — honestly stays a SETUP ERROR
# with no unknown_reason. Without this pair, an implementation answering UNKNOWN
# unconditionally would pass legs A and B. The case comes from a fresh explore
# (2z's recipe) with its state pointer rewritten to the planted directory (2sc's
# recipe): exit 3 alone would also fit a case parse error, which is why the
# message, the verdict and the reason's absence are all required.
rm -rf /tmp/acc-rw-case && mkdir -p /tmp/acc-rw-case/state
"$SIDEEYE" explore --state /tmp/acc-rw-case/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc-rw-case/work --oracle /usr/bin/strace >/dev/null 2>&1
rwcase=/tmp/acc-rw-case/work/cases/000001.json
mkdir -p /tmp/acc-rw-case/planted/pin
echo x > /tmp/acc-rw-case/planted/pin/f
chmod 555 /tmp/acc-rw-case/planted/pin
python3 - "$rwcase" /tmp/acc-rw-case/case.json <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["define"]["state"] = "/tmp/acc-rw-case/planted"
json.dump(c, open(sys.argv[2], "w"))
PY
o=$("$SIDEEYE" replay /tmp/acc-rw-case/case.json --fresh-state \
    --shim "$SHIM" --work /tmp/acc-rw-case/work-c --oracle /usr/bin/strace \
    --json /tmp/acc-rw-case/r.json 2>&1)
rc=$?
if [ "$rc" = "3" ] \
    && echo "$o" | grep -q "fresh-state could not empty" \
    && grep -q '"verdict": "SETUP_ERROR"' /tmp/acc-rw-case/r.json \
    && ! grep -q '"unknown_reason"' /tmp/acc-rw-case/r.json; then
    echo "ok   the same failure before the define runs honestly stays a SETUP ERROR, with no reason claimed"
else
    echo "FAIL rewrite failure before the define: exit $rc (wanted 3 + fresh-state wording + no unknown_reason)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
chmod 755 /tmp/acc-rw-case/planted/pin 2>/dev/null
rm -rf /tmp/acc-rw-case

echo "=========== check: a world over its --world-timeout budget is sent SIGKILL and named (#263) ==========="
# child_timed_out: a world's operation still running after the budget expires is
# sent SIGKILL and refused UNKNOWN with the budget in the message. The contrast leg
# drives the same flag with a budget the run cannot reach — it pins "fires on
# measurement, not on presence"; the no-flag path is what every other check in this
# suite runs under. The fixture is a single-process C helper
# — the command string is split on whitespace with no quote handling, so a shell
# one-liner cannot carry `sh -c '...'`, and a shell `sleep` would be a child process
# tangled with the boundary detectors. It writes one state file always, and sleeps
# only when SIDEEYE_KILL_AT is set: the recording run (no kill_at) is instant, every
# crash world dies at the write before reaching the sleep, and only the un-killed
# baseline sleeps into the budget.
rm -rf /tmp/acc-wt && mkdir -p /tmp/acc-wt/state
cat > /tmp/acc-wt/sleeper.c <<'EOF'
/* Write-tmp-then-rename, toy-fixed's own crash-consistent shape: the scratch file
 * is in neither the pre nor the post snapshot, and the rename is atomic, so every
 * crash world satisfies the built-in invariant and the contrast leg can PASS. The
 * first version wrote the file in place — truncate then write, the classic torn
 * write — and turned the contrast into a genuine FAIL. */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    const char *dir = getenv("TOY_STATE");
    if (!dir) return 1;
    char tmp[512], fin[512];
    snprintf(tmp, sizeof tmp, "%s/f.tmp", dir);
    snprintf(fin, sizeof fin, "%s/f", dir);
    FILE *f = fopen(tmp, "w");
    if (!f) return 1;
    fputs("t\n", f);
    fclose(f);
    if (rename(tmp, fin) != 0) return 1;
    if (getenv("SIDEEYE_KILL_AT")) {
        const char *s = getenv("TOY_SLEEP");
        sleep(s ? (unsigned)atoi(s) : 30);
    }
    return 0;
}
EOF
cc -O0 -o /tmp/acc-wt/sleeper /tmp/acc-wt/sleeper.c || { echo "FAIL world-timeout: fixture did not compile"; fails=$((fails + 1)); }
# The outer `timeout 60` is the leg's own net: the acceptance step in CI has no
# timeout of its own. A budget that silently never fires shows up as exit 0 after
# the fixture's natural 30s sleep — the elapsed check below catches that — and a
# budget path that itself hangs is cut at 60s and shows up as 124 instead of
# hanging the job for hours.
wt_t0=$(date +%s)
o=$(TOY_SLEEP=30 timeout 60 "$SIDEEYE" explore --state /tmp/acc-wt/state \
    --operation /tmp/acc-wt/sleeper \
    --world-timeout 1 \
    --shim "$SHIM" --work /tmp/acc-wt/work --allow-unverified \
    --json /tmp/acc-wt/r.json 2>&1)
rc=$?
wt_elapsed=$(( $(date +%s) - wt_t0 ))
# The elapsed bound is what separates "the budget cut the 30s sleep short" from
# "the fixture finished on its own and something else produced the refusal": a
# 1-second budget that takes 29 seconds to act is not the shipped promise.
if [ "$rc" = "2" ] \
    && [ "$wt_elapsed" -le 10 ] \
    && echo "$o" | grep -q "child_timed_out" \
    && echo "$o" | grep -q "budget of 1 second" \
    && grep -q '"unknown_reason": "child_timed_out"' /tmp/acc-wt/r.json \
    && grep -q '"verdict": "UNKNOWN"' /tmp/acc-wt/r.json \
    && ! grep -q '"earliest"' /tmp/acc-wt/r.json; then
    echo "ok   a world outliving its budget is refused UNKNOWN child_timed_out in ${wt_elapsed}s, naming the budget"
else
    echo "FAIL world over budget: exit $rc in ${wt_elapsed}s (wanted 2 + child_timed_out + the budget named, within 10s; ~30s+exit 0 = the budget never fired; 124 = the budget path itself hung)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
# The contrast: the same operation under a budget it cannot reach passes — an
# implementation that fires regardless of the budget, or whenever the flag is
# present, dies here. TOY_SLEEP trims the baseline's sleep to 2s so the leg costs
# seconds, not the fixture's full 30; the budget of a day is the "cannot reach"
# value, not a guess.
rm -rf /tmp/acc-wt/work /tmp/acc-wt/r.json
o=$(TOY_SLEEP=2 timeout 90 "$SIDEEYE" explore --state /tmp/acc-wt/state \
    --operation /tmp/acc-wt/sleeper \
    --world-timeout 86400 \
    --shim "$SHIM" --work /tmp/acc-wt/work --allow-unverified 2>&1)
rc=$?
if [ "$rc" = "0" ] && echo "$o" | grep -q "PASS"; then
    echo "ok   the same define under a generous budget still passes — the budget fires on measurement, not presence"
else
    echo "FAIL world-timeout contrast: exit $rc (wanted 0 PASS)"
    echo "$o" | sed 's/^/     | /' | head -6
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-wt

# Check 19 — preflight --twice (#199): the second observation, both directions.
#
# Sensitivity and specificity in one leg, because either alone passes a constant
# answer: TOY_NONDET_REWRITE rewrites its file with different bytes every run and must
# split; TOY_APPEND_REWRITE reaches the same final content by a path that kills the
# history form, and must not. The equal side is also the restore mutant's grave — an
# implementation that skipped `engine.restore` before the second run would let the
# append land on top of the first run's output and report a split here.
#
# Exit codes are pinned exactly, not as "non-zero". A build without --twice implemented
# refuses the unknown flag with exit 3 (or "an option is missing its value" when it
# lands last on the command line), so a check that accepted any non-zero result would
# pass against an empty implementation.
rm -rf /tmp/acc-tw && mkdir -p /tmp/acc-tw/state /tmp/acc-tw/state2 /tmp/acc-tw/state3
o=$(TOY_NONDET_REWRITE=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc-tw/work 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
echo "$o" | grep -q "not accepted — the two observed runs left different state" || ok=0
echo "$o" | grep -q "^difference .*nondet.txt (content differs)" || ok=0
echo "$o" | grep -q "repeatability .*differed under --state" || ok=0
# The scope line is part of the claim, not decoration: without it the reader is left to
# assume the comparison covered metadata it never looked at.
echo "$o" | grep -q "not compared, and two runs are not all runs" || ok=0
# Neither refusal shape may be what produced the non-zero exit.
echo "$o" | grep -q "SETUP ERROR" && ok=0
echo "$o" | grep -q "^UNKNOWN" && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   --twice names the split, and exits 1 without claiming a verdict"
else
    echo "FAIL --twice split leg: exit $rc (wanted exactly 1)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

o=$(TOY_APPEND_REWRITE=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state2 \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --shim "$SHIM" --work /tmp/acc-tw/work2 2>&1)
rc=$?
ok=1
[ "$rc" = "0" ] || ok=0
echo "$o" | grep -q "recording accepted" || ok=0
echo "$o" | grep -q "repeatability .*left equal state under --state" || ok=0
echo "$o" | grep -q "^difference" && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   --twice accepts a target whose two runs agree (and the restore before run B happened)"
else
    echo "FAIL --twice equal leg: exit $rc (wanted 0)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# Check 20 — run B's exit status is checked, not assumed.
#
# The heading used to read "run B passes the gates run A did", which is false as a
# universal: run B gets nine of the fifteen gates a preflight can reach, and the
# function's own doc comment now lists both halves. What this leg drives is one of
# them — the exit status.
#
# The second observation is not "spawn it and diff the tree": a run that ended abnormally
# says nothing about repeatability, and comparing its wreckage against a successful run
# would report the failure as a split. An implementation that dropped the exit-status
# check would reach exit 0 or 1 here; the existing refusal is the only correct answer.
#
# toy-twice succeeds once and fails after; its counter lives OUTSIDE the state root
# deliberately, because restore rebuilds the state between the observations and a
# counter inside it would reset. Two shell-based fixtures were tried first and neither
# reached run B: one spawned a real target and refused as child_touched_state_dir, the
# other used its own redirections and refused as state_changed_without_ops.
o=$(TOY_TWICE_COUNTER=/tmp/acc-tw/count "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state3 \
    --setup "$OUT/toy-twice init" --operation "$OUT/toy-twice" \
    --shim "$SHIM" --work /tmp/acc-tw/work3 2>&1)
rc=$?
ok=1
[ "$rc" = "2" ] || ok=0
echo "$o" | grep -q "recording_run_failed" || ok=0
echo "$o" | grep -q "the second observed run exited 7" || ok=0
# Not a split, and not an acceptance: both would mean the status went unchecked.
echo "$o" | grep -q "not accepted — the two observed runs" && ok=0
echo "$o" | grep -q "recording accepted" && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   a second run that fails refuses by name rather than being compared"
else
    echo "FAIL --twice run-B gate: exit $rc (wanted 2, recording_run_failed)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# Check 21a — the only_in_second direction, which no other leg reaches.
#
# `classify` walks the pre-side and cannot report a path only the second snapshot has;
# `diffSnapshots` exists to add exactly that direction. It is also the only kind whose
# `rel` is borrowed from the SECOND snapshot — the other three borrow from the first —
# and review found the engine returning those borrowed paths after freeing the snapshot
# that owned them, reproduced as a segfault. Every leg written before that review went
# through `content_differs` and survived. This is the leg that fails on it.
mkdir -p /tmp/acc-tw/state5
o=$(TOY_TWICE_COUNTER=/tmp/acc-tw/count5 TOY_TWICE_EXTRA_ON_SECOND=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state5 \
    --setup "$OUT/toy-twice init" --operation "$OUT/toy-twice" \
    --shim "$SHIM" --work /tmp/acc-tw/work5 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
echo "$o" | grep -q "^difference .*only-in-second.txt (only after the second run)" || ok=0
echo "$o" | grep -q "not accepted — the two observed runs left different state" || ok=0
# WHAT THIS LEG DOES NOT CATCH, said out loud because the first draft claimed it did:
# the use-after-free that motivated it. Removing the arena copy in `observeAgain` and
# running this exact case printed the path correctly and exited 1 — a freed arena whose
# pages nobody reused reads back intact, so the leg stayed green against the defect.
# It covers the DIRECTION (`only_in_second`, which no other leg reaches and which
# `classify` structurally cannot produce); the ownership rule is held by the comment at
# the copy and by review, not by this.
if [ "$ok" = "1" ]; then
    echo "ok   a path only the second run created is named (direction covered; ownership is not)"
else
    echo "FAIL --twice only_in_second leg: exit $rc (wanted 1 naming only-in-second.txt)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# Check 21 — a differing path cannot forge a report line.
#
# Paths in the split report are target-chosen, and a Unix file name may hold a newline.
# Printed raw, "a\nb" would read as two lines and the second could impersonate any
# field the reader trusts. The l0 note has defanged control bytes since #26; this check
# exists because that guard's own test does not cover the new site — an implementation
# that printed `d.rel` instead of `textShown(arena, d.rel)` would leave every existing
# test green.
mkdir -p /tmp/acc-tw/state4
o=$(TOY_TWICE_COUNTER=/tmp/acc-tw/count4 TOY_TWICE_HOSTILE_NAME=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state4 \
    --setup "$OUT/toy-twice init" --operation "$OUT/toy-twice" \
    --shim "$SHIM" --work /tmp/acc-tw/work4 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
# One defanged unit per control byte: the name reads as a?b on one line.
echo "$o" | grep -q "^difference .*a?b (content differs)" || ok=0
# The forged half must not appear as a line of its own. Anchored, because the
# sanitised name legitimately contains the letter b.
echo "$o" | grep -qE '^b[[:space:]]' && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   a newline in a differing path is defanged instead of splitting the report"
else
    echo "FAIL --twice report safety: exit $rc (wanted 1 with a?b on one line)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi

# Check 22 — --twice under an oracle.
#
# The suite's own rule at the top: every case runs with an oracle where one exists. The
# first four --twice legs did not, and that is the direct reason a review found run B's
# boundary check gated on `oracle_path == null` — passing an oracle REMOVED it. This
# leg drives the oracle path so the combination is exercised at all.
#
# What it does NOT catch: that same boundary regression. The toys here cross no process
# boundary, so a build that dropped run B's hard-boundary check stays green. Catching
# that needs a target whose SECOND run creates a thread, which no fixture produces yet.
mkdir -p /tmp/acc-tw/state6
o=$(TOY_NONDET_REWRITE=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw/state6 \
    --setup "$OUT/toy-bug init" --operation "$OUT/toy-bug rotate" \
    --oracle /usr/bin/strace \
    --shim "$SHIM" --work /tmp/acc-tw/work6 2>&1)
rc=$?
ok=1
[ "$rc" = "1" ] || ok=0
echo "$o" | grep -q "^difference .*nondet.txt (content differs)" || ok=0
# The asymmetry is disclosed, not silent: run B's capture is written and never parsed.
echo "$o" | grep -q "the second run's oracle capture is written but not" || ok=0
if [ "$ok" = "1" ]; then
    echo "ok   --twice runs under an oracle and discloses that run B's capture is not compared"
else
    echo "FAIL --twice oracle leg: exit $rc (wanted 1 with the scope disclosure)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi
# Check 23 — the reported gap is measured, and a slow first run skips the sleep.
#
# Two things at once, both of which the other --twice legs structurally cannot reach.
#
# The gap is enforced by re-reading the monotonic clock until it passes the two-second
# floor, so a run A that already takes longer must take the branch that sleeps ZERO. No
# other fixture reaches it: they finish in milliseconds, so only the sleeping half of
# that loop has ever executed. TOY_TWICE_SLOW_FIRST makes run A take three seconds.
#
# It also kills the mutant that prints the constant instead of the measured interval.
# Everywhere else the two are within milliseconds of each other — 2000 plus overshoot
# versus 2000 — and no grep can separate them. Here the truth is above 3000 and the
# constant is 2000, so a four-digit figure starting at 3 or more is decisive.
mkdir -p /tmp/acc-tw2/state
o=$(TOY_TWICE_COUNTER=/tmp/acc-tw2/count TOY_TWICE_SLOW_FIRST=1 "$SIDEEYE" preflight --twice \
    --state /tmp/acc-tw2/state \
    --setup "$OUT/toy-twice init" --operation "$OUT/toy-twice" \
    --shim "$SHIM" --work /tmp/acc-tw2/work 2>&1)
rc=$?
ok=1
# Both runs succeed in this mode, so the comparison is reached and the repeatability
# line exists to be read. A refusal would exit before it.
[ "$rc" = "0" ] || ok=0
echo "$o" | grep -qE 'two runs [3-9][0-9]{3} ms apart left equal state' || ok=0
# The constant mutant prints exactly 2000; the measured value here cannot be under 3000.
echo "$o" | grep -q 'two runs 2[0-9][0-9][0-9] ms' && ok=0
if [ "$ok" = "1" ]; then
    echo "ok   the reported gap is measured, and a first run past the floor sleeps not at all"
else
    echo "FAIL --twice slow-first leg: exit $rc (wanted 0 with a gap over 3000 ms)"
    echo "$o" | sed 's/^/     | /' | head -8
    fails=$((fails + 1))
fi
rm -rf /tmp/acc-tw2 /tmp/acc-tw

echo "=========== check 2cw: a define declares where it runs, and the case freezes it ==========="
# The three legs are one fixture on purpose: the same define, moved. A pair that built a
# separate define per leg would let a typo in one fixture read as a cwd result.
#
# The operation reaches its state through a RELATIVE path, which is the only shape that
# can tell the two directories apart — an absolute one would pass from anywhere and the
# check would be measuring nothing. Scripts are 755 because the engine execs them
# directly (CLAUDE.md: a 644 script green under `sh` died at the first sealed run).
cwd_fails=0
cd=/tmp/acc-cwd
rm -rf $cd && mkdir -p $cd/state $cd/elsewhere
cat > $cd/op.sh <<'OP'
#!/bin/sh
echo committed > state/written
OP
cat > $cd/check.sh <<'CK'
#!/bin/sh
grep -q seed state/seed || exit 1
if [ -e state/written ]; then grep -q committed state/written || exit 1; fi
CK
chmod 755 $cd/op.sh $cd/check.sh
printf 'seed\n' > $cd/state/seed
write_toml() { # $1 = the cwd value to declare
    printf '[world]\nstate = "%s/state"\n\n[define]\noperation = "%s/op.sh"\ncheck     = "%s/check.sh"\ncwd       = "%s"\n' \
        "$cd" "$cd" "$cd" "$1" > $cd/sideeye.toml
}

# Leg 1: declared, and the run reaches a verdict.
write_toml "$cd"
o=$("$SIDEEYE" explore --config $cd/sideeye.toml --shim "$SHIM" --work $cd/work --oracle /usr/bin/strace 2>&1)
rc=$?
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && echo "$o" | grep -q "explored"; then
    echo "ok   a declared cwd puts the operation where its relative path resolves"
else
    echo "FAIL declared cwd: exit $rc (wanted a verdict)"
    echo "$o" | sed 's/^/     | /' | head -6
    cwd_fails=$((cwd_fails + 1))
fi

# Leg 2: the control. The same define pointed one directory over, where `state/` does not
# exist, must NOT reach a verdict. Without this, an implementation that ignored the key
# entirely would satisfy leg 1 whenever the engine happened to run in the right place.
write_toml "$cd/elsewhere"
o=$("$SIDEEYE" explore --config $cd/sideeye.toml --shim "$SHIM" --work $cd/work2 --oracle /usr/bin/strace 2>&1)
rc=$?
if [ "$rc" = "2" ] || [ "$rc" = "3" ]; then
    echo "ok   the same define one directory over does not reach a verdict"
else
    echo "FAIL cwd control: exit $rc (wanted a refusal, not a verdict)"
    echo "$o" | sed 's/^/     | /' | head -6
    cwd_fails=$((cwd_fails + 1))
fi

# Leg 3: a relative spelling resolves against the toml's own directory, not the caller's
# (ADR 0007). Run from `/`, which is where leg 1 and 2 were NOT run from.
write_toml "."
o=$(cd / && "$SIDEEYE" explore --config $cd/sideeye.toml --shim "$SHIM" --work $cd/work3 --oracle /usr/bin/strace 2>&1)
rc=$?
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && echo "$o" | grep -q "explored"; then
    echo "ok   a relative cwd resolves against the toml's directory, from any caller's"
else
    echo "FAIL relative cwd: exit $rc (wanted the same verdict as leg 1)"
    echo "$o" | sed 's/^/     | /' | head -6
    cwd_fails=$((cwd_fails + 1))
fi

# Leg 5: the engine's own paths do not travel with the child. `--work` and `--shim`
# spelled relatively are read against the engine's directory, not the declared one —
# three of their uses are opened after the chdir (the shim opens SIDEEYE_TRACE_PATH, the
# oracle opens its -o capture, the loader resolves the library), so before the pin this
# combination produced a run with no traces at all, reported as `no_shim_marker` and
# blamed on the target's linking. Run from a third directory so the two can differ.
write_toml "$cd"
cp "$SHIM" $cd/elsewhere/shim.so
o=$(cd $cd/elsewhere && "$SIDEEYE" explore --config $cd/sideeye.toml --shim ./shim.so --work relwork --oracle /usr/bin/strace 2>&1)
rc=$?
if { [ "$rc" = "0" ] || [ "$rc" = "1" ]; } && [ -f "$cd/elsewhere/relwork/trace-record.bin" ]; then
    echo "ok   a relative --work and --shim stay with the engine, not with the declared cwd"
else
    echo "FAIL relative engine paths under a declared cwd: exit $rc, traces in the engine's work dir: $(ls $cd/elsewhere/relwork 2>/dev/null | grep -c trace)"
    echo "$o" | sed 's/^/     | /' | head -4
    cwd_fails=$((cwd_fails + 1))
fi

# Leg 4: the version and the shape travel together. A case saved from a define carrying a
# cwd is version 4 and carries it; a file that says one without the other is malformed in
# both directions. Nothing else in this suite reaches version 4, so without this leg the
# law ships with no check at all — every existing case_version assertion stays green
# because no other fixture declares the key.
write_toml "$cd"
rm -rf $cd/work4 && "$SIDEEYE" explore --config $cd/sideeye.toml --shim "$SHIM" --work $cd/work4 --oracle /usr/bin/strace >/dev/null 2>&1
csv=$(find $cd/work4/cases -name '*.json' 2>/dev/null | head -1)
if [ -n "$csv" ] && grep -q '"case_version": 4' "$csv" && grep -q '"cwd"' "$csv"; then
    echo "ok   a case saved from a define with a cwd is version 4 and carries it"
    python3 - "$csv" "$cd" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1])); d = sys.argv[2]
three = dict(c); three["case_version"] = 3
json.dump(three, open(d + "/case-v3.json", "w"))
four = json.loads(json.dumps(c)); four["define"].pop("cwd")
json.dump(four, open(d + "/case-v4.json", "w"))
EOF
    for pair in "case-v3.json:cannot carry a cwd" "case-v4.json:must carry define.cwd"; do
        f=${pair%%:*}; want=${pair#*:}
        o=$("$SIDEEYE" replay $cd/$f --shim "$SHIM" --work $cd/work-r 2>&1)
        rc=$?
        if [ "$rc" = "3" ] && echo "$o" | grep -q "$want"; then
            echo "ok   $f refuses by name (exit 3)"
        else
            echo "FAIL $f: exit $rc, wanted 3 naming '$want'"
            echo "$o" | sed 's/^/     | /' | head -3
            cwd_fails=$((cwd_fails + 1))
        fi
    done
else
    echo "FAIL no case_version 4 file was written (nothing to check the law against)"
    cwd_fails=$((cwd_fails + 1))
fi
rm -rf $cd
if [ "$cwd_fails" != "0" ]; then
    fails=$((fails + cwd_fails))
    reasons="$reasons cwd"
fi
reached_end=1
echo ""
if [ "$fails" = "0" ]; then
    echo "ALL ACCEPTANCE CHECKS PASSED"
    exit 0
fi
echo "$fails ACCEPTANCE CHECK(S) FAILED"
exit 1
