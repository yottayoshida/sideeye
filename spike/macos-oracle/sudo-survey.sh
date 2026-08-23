#!/bin/sh
# The privileged half of the macOS oracle survey (#181). RUN BY THE OWNER:
#
#   sudo /path/to/spike/macos-oracle/sudo-survey.sh
#
# Five candidates, each asked the same narrow question the oracle role
# needs answered: an independent account of the toy's state-directory
# operations, attributable and ordered. Every leg gets a fresh state
# directory, a bounded runtime, and its capture judged by the same
# check-capture.py the unprivileged half showed red first.
#
# The invocations are designed from this machine's man pages, captured in
# survey.txt, not from memory: ktrace's filter grammar (class specifier
# 'C3' = the filesystem class), fs_usage's process-name filter, and
# eslogger's root + Full Disk Access requirements are all documented
# there. OpenBSM has no leg here: auditd(8) declares the subsystem
# deprecated since 11.0 and DISABLED since 14.0, which the unprivileged
# half records as its dismissal.
#
# What this script deliberately does not do: touch anything outside its
# own mktemp directory and its transcript, or leave observers running
# (every background observer is killed by its leg, and a watchdog bounds
# each leg at 45s).
set -u
[ "$(id -u)" = 0 ] || {
    echo "this is the privileged half; run it with sudo" >&2
    exit 2
}
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$here/sudo-survey.txt"
exec > "$OUT" 2>&1
W=$(mktemp -d /private/tmp/se181.XXXXXX)
FAILS=0
bad() { echo "BROKEN: $*"; FAILS=$((FAILS+1)); }
CHECK="$here/check-capture.py"

# Run one observer command bounded: the observer goes to the background,
# the toy runs against a fresh state dir once the observer has settled,
# then the observer is killed. Captures land in $1.
#
# The settle time is a real parameter, not politeness: an observer that
# initialises slowly (eslogger creates an ES client) would miss the
# toy's whole life, and that miss would be indistinguishable from
# blindness. 2 seconds for every leg, uniformly.
observe() { # capture-file state-dir observer-cmd...
    cap=$1; st=$2; shift 2
    mkdir -p "$st"
    "$@" > "$cap" 2>&1 &
    obs=$!
    ( sleep 45; kill "$obs" 2>/dev/null ) &
    watchdog=$!
    sleep 2
    "$W/toy" "$st" > "$st.toy-account" 2>&1
    toyrc=$?
    sleep 2
    kill "$obs" 2>/dev/null
    wait "$obs" 2>/dev/null
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    echo "   toy rc=$toyrc (its own account: $(wc -l < "$st.toy-account" | tr -d ' ') lines)"
    [ "$toyrc" -eq 0 ] || bad "the toy itself failed under this observer, so the capture judges a run that did not complete"
}

verdict() { # capture-file label
    echo "   capture: $(wc -l < "$1" | tr -d ' ') line(s), $(wc -c < "$1" | tr -d ' ') bytes"
    echo "   marker lines, first 10:"
    grep -n 'marker-' "$1" | head -10 | sed 's/^/     /'
    grep -c 'marker-' "$1" > /dev/null || echo "     (none)"
    python3 "$CHECK" "$1" "$2"
}

# Run one runner-style tool (it launches the toy itself: dtruss, dtrace -c,
# ktrace -c) in the foreground with a watchdog, and record ITS exit code,
# which for this family is part of the answer.
runner() { # capture-file cmd...
    cap=$1; shift
    "$@" > "$cap" 2>&1 &
    job=$!
    ( sleep 45; kill "$job" 2>/dev/null ) &
    watchdog=$!
    wait "$job"
    jrc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    echo "   runner rc=$jrc"
}

echo "== environment (privileged half)"
sw_vers | sed 's/^/   /'
echo "   $(csrutil status)"
echo "   uid $(id -u), invoked via sudo by ${SUDO_USER:-<unset>}"
date -u '+   %Y-%m-%dT%H:%M:%SZ'

echo ""
echo "== the toy, rebuilt here so this half stands alone"
/usr/bin/cc -O0 -o "$W/toy" "$here/toy.c" || bad "toy build failed; every leg below will report blindness that is really a missing binary"
codesign -dv "$W/toy" 2>&1 | grep -E 'Signature|CodeDirectory' | sed 's/^/   /'
echo "   (ad-hoc linker signature: the self-built, non-platform case the"
echo "    SIP question turns on)"

echo ""
echo "=============================================================="
echo "L1. dtruss as root: the measurement ADR 0001 promised in 2026-08-10"
echo "=============================================================="
mkdir -p "$W/state-d"
runner "$W/dtruss.cap" dtruss -f "$W/toy" "$W/state-d"
verdict "$W/dtruss.cap" "dtruss"

echo ""
echo "=============================================================="
echo "L2. dtrace itself, minimal syscall aggregate: splits 'DTrace is"
echo "    blocked' from 'the dtruss wrapper is broken'"
echo "=============================================================="
mkdir -p "$W/state-t"
runner "$W/dtrace.cap" dtrace -q \
    -n 'syscall:::entry /pid == $target/ { @[probefunc] = count(); }' \
    -c "$W/toy $W/state-t"
echo "   capture: $(wc -l < "$W/dtrace.cap" | tr -d ' ') line(s); head:"
head -8 "$W/dtrace.cap" | sed 's/^/     /'
echo "   syscall names seen (nonzero rows prove per-pid visibility even"
echo "   though this probe prints no paths):"
grep -cE '^ *[a-z_]+ +[0-9]+$' "$W/dtrace.cap" | sed 's/^/     aggregate rows: /'

echo ""
echo "=============================================================="
echo "L3. fs_usage: kdebug substrate, filtered to the toy by name"
echo "=============================================================="
observe "$W/fsusage.cap" "$W/state-f" fs_usage -w -f filesystem toy
verdict "$W/fsusage.cap" "fs_usage"

echo ""
echo "=============================================================="
echo "L4. ktrace: same substrate, first-party interface, C3 = the"
echo "    filesystem class per this machine's man page"
echo "=============================================================="
mkdir -p "$W/state-k"
runner "$W/ktrace.cap" ktrace trace -f C3 -c "$W/toy" "$W/state-k"
verdict "$W/ktrace.cap" "ktrace"

echo ""
echo "=============================================================="
echo "L5. eslogger: Endpoint Security's shipped CLI (root + the invoking"
echo "    terminal's Full Disk Access decide this one)"
echo "=============================================================="
observe "$W/es.cap" "$W/state-e" eslogger create rename unlink close
verdict "$W/es.cap" "eslogger"

echo ""
echo "== residue check: no observer left behind"
for name in dtruss dtrace fs_usage ktrace eslogger; do
    if pgrep -x "$name" > /dev/null 2>&1; then
        bad "an observer named $name is still running; kill it by hand"
    fi
done
echo "   (silence above = all observers exited or were killed)"

/bin/rm -rf "${W:?}"
echo ""
echo "== BROKEN checks: $FAILS"
rc=0
[ "$FAILS" -eq 0 ] || rc=1
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER" "$OUT"
echo "wrote $OUT (rc=$rc)" > /dev/tty 2>/dev/null || true
exit $rc
