#!/bin/sh
# Does FSEvents give macOS a corroborator that costs no root? (#286, route B)
#
# #181 measured the platform's privileged observers and found the strace-grade
# account priced at root by design. #286 asks the weaker question this survey
# answers a first piece of: what verification is reachable WITHOUT root.
#
# Two hypotheses, kept apart on purpose:
#
#   H1  FSEvents can produce a full OpClass sequence, good enough to drop into
#       src/oracle.zig's compare(). This survey hunts counterexamples to H1.
#   H2  FSEvents can act as an independent veto, catching a mutation the shim
#       failed to report. This survey builds the apparatus and does NOT judge it.
#
# The asymmetry is why the work is cheap and why the wording is careful. One
# counterexample kills H1. No counterexample proves nothing: FSEvents.h calls
# its flags a hint, and agreeing runs are not a guarantee about future runs.
# So a clean sweep here would read "worth further study", never "it works".
#
# Everything below runs unprivileged, deliberately. The moment a leg needs
# root or a Full Disk Access grant, the premise of route B is gone and there
# is nothing left to measure.
set -u
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
W=$(mktemp -d "$HOME/se286.XXXXXX") || { echo "BROKEN: mktemp failed" >&2; exit 1; }
case "$W" in
    "$HOME"/se286.*) : ;;
    *) echo "BROKEN: refusing to work in unexpected directory '$W'" >&2; exit 1 ;;
esac
BIN="$W/bin"; mkdir -p "$BIN"
JUDGE_OUT="$W/judge-out.txt"
FAILS=0
bad() { echo "BROKEN: $*"; FAILS=$((FAILS+1)); }

# How long to wait after the probe returns before asking for the flush. The
# flush itself (FSEventStreamFlushSync) is what guarantees delivery of what
# fseventsd already holds; this only covers the gap between the syscall
# returning and fseventsd having the event. Reported because a reader must be
# able to tell a coalescing result from a too-short wait.
SETTLE=0.4
# Repetitions for the timing-dependent legs. A single run cannot separate
# "this configuration coalesces" from "these two calls happened to land in the
# same window once".
REPS=5

echo "== environment"
sw_vers | sed 's/^/   /'
echo "   $(uname -rm)"
echo "   $(csrutil status)"
echo "   invoked as uid $(id -u) — every leg here is unprivileged by design"
echo "   settle before flush: ${SETTLE}s; repetitions for timing legs: $REPS"

echo ""
echo "== the judge, seen red before it judges anything"
echo "-- selftest (accept side, reject side, and apparatus-BROKEN side)"
# Not piped: the exit status of `cmd | sed` is sed's, so a failing selftest
# would have gone unnoticed while its own output scrolled past.
python3 "$here/judge.py" --selftest > "$W/selftest.txt" 2>&1
strc=$?
sed 's/^/  /' "$W/selftest.txt"
[ "$strc" -eq 0 ] || bad "judge selftest failed (rc $strc)"
echo "-- positive control: the selftest must kill a judge that always accepts"
sed 's/^        return 1$/        return 0  # SABOTAGE/' "$here/judge.py" > "$W/judge-accept.py"
python3 "$W/judge-accept.py" --selftest > "$W/st-accept.txt" 2>&1
n=$(grep -c 'selftest FAIL' "$W/st-accept.txt" || true)
grep -q 'selftest cases:' "$W/st-accept.txt" \
    || bad "the always-accept control did not run to completion"
echo "   always-accept judge -> $n selftest failure(s)"
[ "${n:-0}" -gt 0 ] || bad "an always-accept judge passed the selftest: the suite proves nothing"
echo "-- positive control: and a judge that always rejects"
# The always-reject control replaces v_mapping's BODY, bounded by the next
# top-level def. An earlier version spliced from v_mapping to j_mapping and
# deleted the four functions in between, so the sabotaged copy died with a
# NameError and reported zero failures. A crash and an ineffective control
# produce the same zero, which is why the check below also requires the run
# to have completed.
python3 - "$here/judge.py" "$W/judge-reject.py" <<'SABOTAGE'
import re
import sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^def v_mapping\([^)]*\):", src, re.M)
if not m:
    sys.exit("could not locate v_mapping to sabotage")
nxt = re.search(r"^def ", src[m.end():], re.M)
if not nxt:
    sys.exit("could not find the end of v_mapping")
args = m.group(0)[len("def v_mapping("):-2]
open(sys.argv[2], "w", encoding="utf-8").write(
    src[:m.start()]
    + f"def v_mapping({args}):\n    return 1  # SABOTAGE\n\n\n"
    + src[m.end() + nxt.start():])
SABOTAGE
python3 "$W/judge-reject.py" --selftest > "$W/st-reject.txt" 2>&1
n=$(grep -c 'selftest FAIL' "$W/st-reject.txt" || true)
grep -q 'selftest cases:' "$W/st-reject.txt" \
    || bad "the always-reject control did not run to completion"
echo "   always-reject judge -> $n selftest failure(s)"
[ "${n:-0}" -gt 0 ] || bad "an always-reject judge passed the selftest: the suite proves nothing"

echo ""
echo "== the header lines this survey is designed from"
echo "   (committed because a design source that lives only in a session's"
echo "    memory is not a source — the #181 lesson)"
SDK=$(xcrun --show-sdk-path 2>/dev/null)
H="$SDK/System/Library/Frameworks/CoreServices.framework/Frameworks/FSEvents.framework/Headers/FSEvents.h"
echo "   $H"
if [ -r "$H" ]; then
    echo "-- latency exists to hide intermediate states, and names the very"
    echo "   write pattern this project judges"
    grep -n -A4 '"latency" parameter that tells how long' "$H" | sed 's/^/   | /'
    echo "-- an event id belongs to the most recent event for that directory"
    grep -n -A3 'Each event ID comes from the most' "$H" | sed 's/^/   | /'
    echo "-- MarkSelf/OwnEvent: the framework can tell its own client's events"
    echo "   apart. It exposes no pid for anyone else."
    grep -n 'kFSEventStreamCreateFlagMarkSelf\|kFSEventStreamEventFlagOwnEvent' "$H" \
        | grep '=' | sed 's/^/   | /'
    echo "-- ScheduleWithRunLoop is deprecated since macOS 13; the watcher uses"
    echo "   a dispatch queue instead"
    grep -n 'Use FSEventStreamSetDispatchQueue instead' "$H" | head -1 | sed 's/^/   | /'
else
    bad "FSEvents.h not readable at $H; the design cites lines it cannot show"
fi

echo ""
echo "== build"
/usr/bin/cc -O0 -Wall -Wextra -o "$BIN/watcher" "$here/watcher.c" -framework CoreServices \
    || bad "watcher build failed"
/usr/bin/cc -O0 -Wall -Wextra -o "$BIN/probe" "$here/probe.c" || bad "probe build failed"
echo "   watcher: $(ls -l "$BIN/watcher" 2>/dev/null | awk '{print $5}') bytes"
echo "   probe:   $(ls -l "$BIN/probe" 2>/dev/null | awk '{print $5}') bytes"

# Bounded wait for the watcher's READY. A leg that proceeds on timeout would
# measure a window that had not opened yet, and its empty capture would read
# as a finding.
wait_ready() {
    f=$1; label=$2
    i=0
    while [ "$i" -lt 200 ]; do
        if grep -q '"type":"ready"' "$f" 2>/dev/null; then return 0; fi
        sleep 0.05; i=$((i+1))
    done
    bad "watcher never reported ready: $label"
    return 1
}

# capture <outdir> <mode> <gap_ms> <watcher flags...>
#
# Runs one operation under one watcher configuration. The setup for the mode
# happens BEFORE the watcher starts, so the preparation cannot be mistaken for
# the operation under test.
capture() {
    od=$1; mode=$2; gap=$3; shift 3
    mkdir -p "$od/state"
    "$BIN/probe" --setup "$od/state" "$mode" 2> "$od/setup.err" \
        || { bad "setup failed for mode $mode"; return 1; }
    mkfifo "$od/ctl"
    "$BIN/watcher" --path "$od/state" "$@" < "$od/ctl" > "$od/events.jsonl" 2> "$od/watcher.err" &
    wpid=$!
    exec 9> "$od/ctl"
    wait_ready "$od/events.jsonl" "mode $mode"
    "$BIN/probe" --run "$od/state" "$mode" --gap-ms "$gap" > "$od/ops.jsonl" 2> "$od/probe.err"
    prc=$?
    # Consumed and cleared here. A `VAR=x func` prefix does NOT reliably scope
    # to the call in POSIX sh: /bin/sh on this machine leaves the assignment
    # set afterwards, which silently gave L3 onwards the last L2 settle and
    # made the transcript's stated wait wrong. Measured, not assumed.
    settle_now="${SETTLE_OVERRIDE:-$SETTLE}"
    unset SETTLE_OVERRIDE
    echo "   (settle ${settle_now}s)"
    sleep "$settle_now"
    echo stop >&9
    exec 9>&-
    wait "$wpid"; wrc=$?
    [ "$prc" -eq 0 ] || bad "probe rc=$prc for mode $mode"
    [ "$wrc" -eq 0 ] || bad "watcher rc=$wrc for mode $mode"
    return 0
}

# judge <verdict-kind> <args...> — rc 2 is a broken apparatus and counts;
# rc 1 is a hypothesis that failed its test and does not.
# Writes to $JUDGE_OUT and returns the judge's own rc. Callers render the file
# however they like; nothing here runs inside a pipeline, so `bad` reaches the
# parent shell and rc 2 cannot be swallowed by a formatting stage.
judge() {
    kind=$1; shift
    python3 "$here/judge.py" "$kind" "$@" > "$JUDGE_OUT" 2>&1
    jrc=$?
    if [ "$jrc" -eq 2 ]; then bad "judge $kind could not measure (rc 2)"; fi
    return "$jrc"
}

echo ""
echo "== L0: is the apparatus alive?"
echo "   One file created after READY must produce at least one event for that"
echo "   path. This is a control on the WATCHER. It deliberately does not ask"
echo "   whether several operations arrive distinctly — that is the question"
echo "   under test, and a control that assumes the answer is not a control."
L0="$W/L0"; mkdir -p "$L0"
capture "$L0" create 0 --file-events --latency 0 --no-defer
judge soundness "$L0/events.jsonl" "$L0/ops.jsonl"
l0rc=$?
cat "$JUDGE_OUT"
echo "   L0 verdict rc=$l0rc"
if [ "$l0rc" -ne 0 ]; then
    bad "the soundness control failed; every measurement below is uninterpretable"
fi

echo ""
echo "== L1: which operations produce an event at all?"
echo "   The shim records every ATTEMPT before it runs, and says why: a failed"
echo "   attempt has to count on both sides or the accounts desync"
echo "   (shim/src/ops.zig). FSEvents reports changes, so an attempt that"
echo "   changed nothing has nothing to report. Each mode runs alone."
MODES="create write fsync truncate-same truncate-shrink rename unlink mkdir rmdir link symlink fail-open fail-unlink fail-rename fail-mkdir fail-rmdir fail-link fail-truncate"
dead=0; live=0
for m in $MODES; do
    d="$W/L1-$m"; mkdir -p "$d"
    echo "-- mode $m"
    capture "$d" "$m" 0 --file-events --latency 0 --no-defer || continue
    judge mapping "$d/events.jsonl" "$d/ops.jsonl"
    rc=$?
    cat "$JUDGE_OUT"
    if [ "$rc" -eq 1 ]; then dead=$((dead+1)); elif [ "$rc" -eq 0 ]; then live=$((live+1)); fi
done
echo ""
echo "   L1 summary: $live mode(s) fully observed, $dead mode(s) with at least"
echo "   one operation that produced no event."

echo ""
echo "== L2: how many entries does one run produce?"
echo "   Repeated $REPS times per configuration, because one run cannot"
echo "   separate a rule from a coincidence."
# Each configuration carries its own settle, because a latency longer than
# the wait produces an empty capture that says nothing about coalescing. The
# first run of this survey had a fixed 0.4s and reported 0 entries for
# latency=1.0 five times out of five; that was the apparatus, not FSEvents.
for cfg in "0 0 0.4 --no-defer" "0 0 0.4 " "0.01 0 0.4 " "1.0 0 2.5 " "0 50 0.4 --no-defer" "0 200 0.8 --no-defer"; do
    lat=$(echo "$cfg" | awk '{print $1}')
    gap=$(echo "$cfg" | awk '{print $2}')
    st=$(echo "$cfg" | awk '{print $3}')
    nd=$(echo "$cfg" | awk '{print $4}')
    echo "-- latency=$lat gap=${gap}ms settle=${st}s ${nd:-(defer)}"
    r=1
    while [ "$r" -le "$REPS" ]; do
        d="$W/L2-$lat-$gap-${nd:-defer}-$r"; mkdir -p "$d"
        SETTLE_OVERRIDE=$st capture "$d" fsync "$gap" --file-events --latency "$lat" $nd \
            || { r=$((r+1)); continue; }
        judge coalescing "$d/events.jsonl" "$d/ops.jsonl"
        crc=$?
        printf '   rep %d (rc %d): ' "$r" "$crc"
        tr '\n' ' ' < "$JUDGE_OUT" | sed 's/  */ /g'
        echo ""
        r=$((r+1))
    done
done

echo ""
echo "== L3: does entry order carry operation order?"
echo "   The fsync mode issues open, write, fsync against one path — three"
echo "   operations the comparison keeps, in a fixed order."
L3="$W/L3"; mkdir -p "$L3"
capture "$L3" fsync 200 --file-events --latency 0 --no-defer
judge ordering "$L3/events.jsonl" "$L3/ops.jsonl"
l3rc=$?
cat "$JUDGE_OUT"
echo "   L3 verdict rc=$l3rc"

echo ""
echo "== L4: can the output say WHO acted?"
echo "   Two runs of the same operation on the same path, differing only in"
echo "   which program performed it. A neighbour-only path would separate by"
echo "   path and prove nothing, so both runs write the identical name."
# One state directory, one file name, two runs. The first version of this
# leg gave each side its own parent directory, so the two captures differed
# in the absolute path and the judge said "distinguishable" for a reason that
# had nothing to do with who acted. Same path or the leg proves nothing.
L4="$W/L4"; mkdir -p "$L4/state"
for side in A B; do
    od="$L4/$side"; mkdir -p "$od"
    # The whole directory is cleared before the watcher starts, so both runs
    # begin from the same state and the removal is outside the window. Clearing
    # only `target` left the first run's sentinel in place, which turned the
    # second run's create into a truncate and added ItemInodeMetaMod to it: a
    # difference about the harness, not about who acted.
    /bin/rm -f "$L4/state"/* 2>/dev/null || true
    mkfifo "$od/ctl"
    "$BIN/watcher" --path "$L4/state" --file-events --latency 0 --no-defer \
        < "$od/ctl" > "$od/events.jsonl" 2> "$od/watcher.err" &
    wpid=$!
    exec 9> "$od/ctl"
    wait_ready "$od/events.jsonl" "L4 side $side"
    if [ "$side" = A ]; then
        "$BIN/probe" --run "$L4/state" create > "$od/ops.jsonl" 2> "$od/probe.err"
        prc=$?
        [ "$prc" -eq 0 ] || bad "L4 side A probe rc=$prc"
        echo "   A: the probe created $L4/state/target (rc $prc)"
    else
        # A different program entirely, performing the same two
        # open(O_WRONLY|O_CREAT|O_TRUNC) calls the probe performs, sentinel
        # included. Without the sentinel this side would hold one entry fewer
        # and the leg would "differ" for a reason that is about the harness.
        /bin/sh -c ': > "$0/target"; : > "$0/sentinel"' "$L4/state"
        prc=$?
        [ "$prc" -eq 0 ] || bad "L4 side B /bin/sh rc=$prc"
        [ -f "$L4/state/target" ] || bad "L4 side B left no file to observe"
        echo "   B: /bin/sh created $L4/state/target (rc $prc)"
    fi
    sleep "$SETTLE"
    echo stop >&9; exec 9>&-
    wait "$wpid" || bad "L4 side $side watcher rc nonzero"
done
judge attribution "$L4/A/events.jsonl" "$L4/B/events.jsonl"
l4rc=$?
cat "$JUDGE_OUT"
# Both sides must have seen their sentinel, or "differ" and "agree" are both
# meaningless. Checked here because v_attribution takes no ops file.
for side in A B; do
    grep -q '"path":"[^"]*sentinel"' "$L4/$side/events.jsonl" \
        || bad "L4 side $side sentinel produced no event"
done
echo "   L4 verdict rc=$l4rc"

echo ""
echo "== L5: what MarkSelf and IgnoreSelf actually cover"
echo "   Both flags are about the watcher's own process. The control is the"
echo "   watcher writing a file itself; the probe is never 'self' to it."
for f in "--mark-self" "--ignore-self"; do
    d="$W/L5-$(echo "$f" | tr -d '-')"; mkdir -p "$d/state"
    mkfifo "$d/ctl"
    "$BIN/watcher" --path "$d/state" --file-events --latency 0 --no-defer "$f" \
        --self-write "$d/state/by-watcher" < "$d/ctl" > "$d/events.jsonl" 2> "$d/watcher.err" &
    wpid=$!
    exec 9> "$d/ctl"
    wait_ready "$d/events.jsonl" "L5 $f"
    "$BIN/probe" --run "$d/state" create > "$d/ops.jsonl" 2> "$d/probe.err"
    prc=$?
    [ "$prc" -eq 0 ] || bad "L5 $f probe rc=$prc"
    sleep "$SETTLE"
    echo stop >&9; exec 9>&-
    wait "$wpid" || bad "L5 $f watcher rc nonzero"
    grep -q '"type":"ready"' "$d/events.jsonl" || bad "L5 $f capture has no ready"
    grep -q '"type":"done"' "$d/events.jsonl" || bad "L5 $f capture has no done"
    echo "-- $f"
    echo "   watcher's own write:"
    grep '"type":"self_write"' "$d/events.jsonl" | sed 's/^/     /'
    echo "   events recorded:"
    grep '"type":"event"' "$d/events.jsonl" | sed 's/^/     /' || echo "     (none)"
done

echo ""
echo "== L6: do the flags describe this window, or the path's history?"
echo "   L1 showed ItemCreated on every mode whose setup created the file"
echo "   before the watcher started. Two explanations fit that: the flags"
echo "   summarise what is known about the path, or the setup's own event was"
echo "   still in flight. They are told apart by waiting between the setup and"
echo "   the watcher. Without this leg, writing either sentence would claim"
echo "   more than the measurement."
for wait_s in 0 3; do
    d="$W/L6-wait$wait_s"; mkdir -p "$d/state"
    "$BIN/probe" --setup "$d/state" write 2> "$d/setup.err" || bad "L6 setup failed"
    [ "$wait_s" = 0 ] || sleep "$wait_s"
    mkfifo "$d/ctl"
    "$BIN/watcher" --path "$d/state" --file-events --latency 0 --no-defer \
        < "$d/ctl" > "$d/events.jsonl" 2> "$d/watcher.err" &
    wpid=$!
    exec 9> "$d/ctl"
    wait_ready "$d/events.jsonl" "L6 wait=$wait_s"
    "$BIN/probe" --run "$d/state" write > "$d/ops.jsonl" 2> "$d/probe.err"
    prc=$?
    [ "$prc" -eq 0 ] || bad "L6 wait=$wait_s probe rc=$prc"
    sleep "$SETTLE"
    echo stop >&9; exec 9>&-
    wait "$wpid" || bad "L6 wait=$wait_s watcher rc nonzero"
    # The same liveness requirement the judge enforces elsewhere: without the
    # sentinel's event, a missing ItemCreated would be unreadable either way.
    grep -q '"path":"[^"]*sentinel"' "$d/events.jsonl" \
        || bad "L6 wait=$wait_s sentinel produced no event"
    echo "-- setup, then ${wait_s}s, then watcher, then open+write"
    grep '"type":"event"' "$d/events.jsonl" | sed 's/^/     /' || echo "     (no event)"
done

echo ""
echo "== what this survey does not answer"
echo "   H2 (an independent veto) is not judged here. The apparatus above is"
echo "   what H2 would need, but 'what fraction of unreported mutations does"
echo "   this catch' is a different measurement against a different corpus."
echo "   Also unmeasured: behaviour under load, on non-APFS volumes, across"
echo "   the network, and after a Full Disk Access grant (out of scope: a"
echo "   grant would end the unprivileged premise)."

/bin/rm -rf "${W:?}"
echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
