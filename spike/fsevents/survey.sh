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
#       failed to report. Judged at two points in L7 (#293) and not settled:
#       containment fails on a clean run and sensitivity holds. The rate over a
#       corpus, which is what would settle it, is still not measured here.
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
/usr/bin/cc -O0 -Wall -Wextra -o "$BIN/bypass" "$here/bypass.c" || bad "bypass build failed"
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
echo "== L7: can this be a veto rather than an oracle? (#293)"
echo "   H1 asked whether a capture rebuilds into the OpClass sequence"
echo "   src/oracle.zig compares. L1-L4 measured that it does not. H2 is a"
echo "   weaker question, so it gets a weaker relation: PATH SET CONTAINMENT."
echo "   Every path FSEvents reports must be one the account already names."
echo "   Containment passes through coalescing and reordering by construction,"
echo "   because it never asks which event belongs to which operation."
echo ""
echo "   Both legs take their ground truth from the probe's own record, never"
echo "   from the shim. Judging FSEvents against the shim in an experiment"
echo "   about the shim's incompleteness is circular: an event with no matching"
echo "   operation is either a false alarm or a real miss, and that comparison"
echo "   cannot say which."

L7="$W/L7"; mkdir -p "$L7"

echo ""
echo "-- L7a: the planted mutation is invisible to the shim, measured not assumed"
echo "   The sensitivity leg below plants a clonefile(2), which WAS absent from"
echo "   the then-40 symbols shim/src/macos.zig interposed when this survey ran"
echo "   (v11). Trace contract v12 (#333) interposes the clone family, so this"
echo "   precondition now refuses by design; the recorded result stands as a"
echo "   v11 measurement, and a re-run needs an msync-class mutation (#293)."
echo "   If that were wrong, a"
echo "   silent capture could not be told from a capture of something the shim"
echo "   already saw, and the leg would prove nothing in either direction."
SHIM="$repo/zig-out/lib/libsideeye_shim.dylib"
if [ ! -f "$SHIM" ]; then
    bad "L7a: no shim at $SHIM — build it before this leg can check anything"
else
    mkdir -p "$L7/shim/state"
    DYLD_INSERT_LIBRARIES="$SHIM" \
    SIDEEYE_STATE_DIR="$L7/shim/state" \
    SIDEEYE_TRACE_PATH="$L7/shim/trace.bin" \
        "$BIN/bypass" --run "$L7/shim/state" > "$L7/shim/ops.jsonl" 2> "$L7/shim/err"
    l7_brc=$?
    [ "$l7_brc" -eq 0 ] || bad "L7a: the bypass probe exited $l7_brc under the shim"
    if [ ! -s "$L7/shim/trace.bin" ]; then
        bad "L7a: the shim wrote no trace, so its silence about the clone means nothing"
    else
        # Read the trace ONCE, check that the read itself worked, and test every
        # condition against the saved output. Running strings a second time for
        # the absence made a failed read indistinguishable from a real absence:
        # both come back as a non-zero grep, and the leg would have called that
        # a proven bypass. The control has to be present before the absence is
        # readable at all — a trace missing everything would "prove" the bypass
        # for the wrong reason.
        if LC_ALL=C strings -a "$L7/shim/trace.bin" > "$L7/shim/strings.txt" 2> "$L7/shim/strings.err"; then
            l7_ctl=$(grep -c 'seen-by-shim\.txt' "$L7/shim/strings.txt")
            l7_src=$(grep -c 'clone-src\.txt' "$L7/shim/strings.txt")
            l7_dst=$(grep -c 'clone-dst\.txt' "$L7/shim/strings.txt")
            if [ "$l7_ctl" -eq 0 ] || [ "$l7_src" -eq 0 ]; then
                bad "L7a: the trace names the control $l7_ctl time(s) and the clone source $l7_src time(s); the shim did not record what it does interpose"
            elif [ "$l7_dst" -ne 0 ]; then
                bad "L7a: the shim DOES record the clone destination ($l7_dst mention(s)) — pick another mutation"
            else
                echo "   ok: the trace names seen-by-shim.txt ($l7_ctl) and clone-src.txt ($l7_src),"
                echo "       and never names clone-dst.txt"
            fi
        else
            bad "L7a: strings could not read the trace, so nothing in it has been checked"
        fi
    fi
fi

echo ""
echo "-- L7b: containment on runs with nothing wrong"
echo "   Over the probe's whole succeeding repertoire, not one mode. Repeating"
echo "   a single mode raises the run count without widening what containment"
echo "   was tested against: five runs of one write are five observations of"
echo "   one path. The modes below reach files, directories, links and renames,"
echo "   which is what makes 'stayed inside the account' a claim about the"
echo "   account rather than about one file."
L7B_MODES="create write fsync truncate-shrink truncate-same rename link symlink mkdir rmdir unlink"
l7b_out=0
l7b_runs=0
l7b_paths=0
l7b_events=0
for l7_m in $L7B_MODES; do
    l7_i=0
    while [ "$l7_i" -lt "$REPS" ]; do
        l7_d="$L7/b-$l7_m-$l7_i"; mkdir -p "$l7_d"
        if capture "$l7_d" "$l7_m" 0 --file-events --latency 0 --no-defer; then
            judge veto-containment "$l7_d/events.jsonl" "$l7_d/ops.jsonl"
            l7_jrc=$?
            l7b_runs=$((l7b_runs + 1))
            case "$l7_jrc" in
                1) l7b_out=$((l7b_out + 1)); echo "-- $l7_m run $l7_i"; sed 's/^/   /' "$JUDGE_OUT" ;;
            esac
            # Counted from the judge's own line rather than recomputed here: a
            # second implementation of "how many paths" is the copy that drifts.
            l7_np=$(sed -n 's/.*over \([0-9][0-9]*\) path(s).*/\1/p' "$JUDGE_OUT")
            l7_ne=$(sed -n 's/.*; \([0-9][0-9]*\) event(s) besides.*/\1/p' "$JUDGE_OUT")
            # The extraction has to have worked. Reading these out of the judge's
            # line avoids a second implementation of "how many paths", but moves
            # the dependency onto its wording: a reworded line makes sed return
            # nothing, ${x:-0} turns that into a zero, and the totals below shrink
            # without saying why. Asserted here rather than defaulted.
            case "$l7_np" in ''|*[!0-9]*) bad "L7b $l7_m run $l7_i: could not read the path count out of the judge's output"; l7_np=0 ;; esac
            case "$l7_ne" in ''|*[!0-9]*) bad "L7b $l7_m run $l7_i: could not read the event count out of the judge's output"; l7_ne=0 ;; esac
            l7b_paths=$((l7b_paths + l7_np))
            l7b_events=$((l7b_events + l7_ne))
        else
            bad "L7b $l7_m run $l7_i capture failed"
        fi
        l7_i=$((l7_i + 1))
    done
done
echo "   $REPS runs per mode answers 'does this reproduce', not 'how often'."
echo "   A behaviour appearing one run in five is missed entirely by five runs"
echo "   about a third of the time, so a mode reading 0/$REPS here is not a mode"
echo "   that does not do it. No rate is claimed below."
echo "   containment held in $((l7b_runs - l7b_out))/$l7b_runs runs across"
echo "   $(printf '%s\n' $L7B_MODES | wc -l | tr -d ' ') modes, over $l7b_paths path-observations and $l7b_events event(s)"
echo "   besides the sentinels. A run reaching zero events would be counted"
echo "   here as containment holding, which is why the event total is printed:"
echo "   containment over nothing is not containment."

echo ""
echo "-- L7d: positive control for the unrelated bucket"
echo "   L7b reported zero unrelated paths over 55 runs. That is the number a"
echo "   working classifier gives in a directory only the probe uses, and it is"
echo "   also the number a classifier that never reaches that branch gives."
echo "   Nothing in L7b tells the two apart, so a second actor writes a path"
echo "   the account will never name, and the branch has to say so."
l7_d="$L7/d"; mkdir -p "$l7_d/state"
mkfifo "$l7_d/ctl" || bad "L7d: mkfifo failed"
"$BIN/watcher" --path "$l7_d/state" --file-events --latency 0 --no-defer \
    < "$l7_d/ctl" > "$l7_d/events.jsonl" 2> "$l7_d/watcher.err" &
wpid=$!
exec 9> "$l7_d/ctl"
wait_ready "$l7_d/events.jsonl" "L7d"
"$BIN/probe" --setup "$l7_d/state" write 2> "$l7_d/setup.err" || bad "L7d setup failed"
"$BIN/probe" --run "$l7_d/state" write > "$l7_d/ops.jsonl" 2> "$l7_d/probe.err"
l7_prc=$?
# The neighbour: a different process, a path the probe never touches and the
# account therefore never names. /usr/bin/touch rather than the shell's own
# redirection, so the writer is unambiguously not this script.
/usr/bin/touch "$l7_d/state/written-by-a-neighbour" || bad "L7d: the neighbour could not write"
sleep "$SETTLE"
echo stop >&9; exec 9>&-
wait "$wpid"; l7_wrc=$?
[ "$l7_prc" -eq 0 ] || bad "L7d probe rc=$l7_prc"
[ "$l7_wrc" -eq 0 ] || bad "L7d watcher rc=$l7_wrc"
judge veto-containment "$l7_d/events.jsonl" "$l7_d/ops.jsonl"
l7_jrc=$?
sed 's/^/   /' "$JUDGE_OUT"
if grep -q 'unrelated to the account.*written-by-a-neighbour' "$JUDGE_OUT"; then
    echo "   ok: the neighbour's path reached the unrelated bucket, so that branch"
    echo "       is reachable and L7b's zero is a measurement rather than a gap"
elif grep -q 'ancestor of an account path.*written-by-a-neighbour' "$JUDGE_OUT"; then
    bad "L7d: a neighbour's own file was classified as an ancestor — the split mislabels"
else
    bad "L7d: the neighbour's write produced no outside path at all; the unrelated branch is still unmeasured"
fi

echo ""
echo "-- L7c: sensitivity — does the veto see what the account misses?"
l7_i=0
l7c_blind=0
while [ "$l7_i" -lt "$REPS" ]; do
    l7_d="$L7/c$l7_i"; mkdir -p "$l7_d/state"
    mkfifo "$l7_d/ctl" || { bad "L7c run $l7_i: mkfifo failed — the loop is repeating a directory"; break; }
    "$BIN/watcher" --path "$l7_d/state" --file-events --latency 0 --no-defer \
        < "$l7_d/ctl" > "$l7_d/events.jsonl" 2> "$l7_d/watcher.err" &
    wpid=$!
    exec 9> "$l7_d/ctl"
    wait_ready "$l7_d/events.jsonl" "L7c run $l7_i"
    "$BIN/bypass" --run "$l7_d/state" > "$l7_d/ops.jsonl" 2> "$l7_d/probe.err"
    prc=$?
    sleep "$SETTLE"
    echo stop >&9; exec 9>&-
    wait "$wpid"; wrc=$?
    [ "$prc" -eq 0 ] || bad "L7c run $l7_i bypass rc=$prc"
    [ "$wrc" -eq 0 ] || bad "L7c run $l7_i watcher rc=$wrc"
    judge veto-sensitivity "$l7_d/events.jsonl" "$l7_d/ops.jsonl"
    l7_jrc=$?
    sed 's/^/   /' "$JUDGE_OUT"
    [ "$l7_jrc" -eq 1 ] && l7c_blind=$((l7c_blind + 1))
    l7_i=$((l7_i + 1))
done
echo "   the veto saw the planted mutation in $((REPS - l7c_blind))/$REPS runs"

echo ""
echo "-- L7: what these two numbers do and do not settle"
echo "   Containment holding says a veto on this relation does not fire on a"
echo "   quiet run of THIS probe in a directory nothing else is using. It is"
echo "   not a soundness proof: a busier directory, an editor, a backup daemon"
echo "   or a second process would each be a path outside the account."
echo "   Sensitivity holding says the veto sees ONE mutation the shim misses."
echo "   The rate over a corpus is a different measurement and is not made"
echo "   here. Neither number licenses a report vocabulary; naming a claim"
echo "   weaker than oracle_verified reopens the contract (#201, #202, #156)."

echo ""
echo "== what this survey does not answer"
echo "   H2 is measured at two points in L7, not settled. What is missing is"
echo "   the rate: containment was measured on one probe in an idle directory,"
echo "   and sensitivity on one planted mutation. 'What fraction of unreported"
echo "   mutations does this catch, and how often does it fire on a clean run"
echo "   of a real target' needs a corpus this survey does not build."
echo "   Also unmeasured: behaviour under load, on non-APFS volumes, across"
echo "   the network, and after a Full Disk Access grant (out of scope: a"
echo "   grant would end the unprivileged premise)."

/bin/rm -rf "${W:?}"
echo ""
echo "== BROKEN checks: $FAILS"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
