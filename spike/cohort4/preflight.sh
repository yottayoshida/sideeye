#!/bin/sh
# preflight.sh — probe conditions 8 and 9, decided by measurement instead
# of by forecast. Engine-free: no kill, no checker, no define, so running
# it observes normal execution only and the provenance gate is untouched.
#
#   visibility  Every state-root mutation the kernel performed must also
#               have passed through a function an LD_PRELOAD shim can
#               interpose. Cargo's manifest rename did not, and finding
#               that out cost two defines and two explores
#               (spike/cohort3/cargo-r2/raw-rename-diagnosis.txt).
#
#   interior    How many engine-reachable kill points the operation has
#               inside the state root. papis was probed and defined before
#               anyone counted: its single atomic renameat leaves exactly
#               one, i.e. no interior to crash inside. A count of 1 is not
#               a failure — it is a fact the owner should hold before the
#               slot is spent.
#
# Usage (Linux, inside the cohort image):
#   sh spike/cohort4/preflight.sh visibility <state-root> -- <cmd> [args...]
#   sh spike/cohort4/preflight.sh interior   <state-root> -- <cmd> [args...]
#   sh spike/cohort4/preflight.sh --selftest
#
# --selftest is the falsification this repository requires of a new guard
# before it is trusted: spike/toys/toy.c routes its writes through libc and
# must come out green; spike/toys/toy_raw.c issues the same writes through
# syscall(2) and must come out red. A gate that has never been seen red
# says nothing about what it passed.
#
# What this gate does NOT see, stated so a green is read correctly:
# every class is compared path to path - the descriptor classes reach the
# interposer as a number, so the logger resolves them through
# /proc/self/fd, and an interposed call it could not resolve is reported
# and never used to excuse a mismatch. The comparison is on basenames, so
# two files sharing a name in different directories inside the root can
# cover for each other. A child that drops the preload (static, setuid)
# reads as a wall here, which is true but names a different wall class.
# And it measures one normal run: it says nothing about crash behaviour,
# which is the engine's job, later.
#
# Exit 0 the condition holds, 1 the condition fails (a named wall), 2 the
# gate could not measure. Never read a 2 as a pass.
set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOGGER_SRC="$here/visibility-logger.c"

die_broken() { echo "BROKEN $*"; exit 2; }

need() {
    command -v "$1" >/dev/null 2>&1 ||
        die_broken "$1 not installed - the gate cannot measure (the missing-nm lesson)"
}

# The analyser. Both subcommands and the self-test go through these lines.
ANALYSE="$here/preflight-analyse.py"

run_measured() { # mode root outdir cmd...
    mode=$1; root=$2; out=$3; shift 3
    [ -d "$root" ] || die_broken "state root $root does not exist"
    need cc
    need strace
    need python3
    [ -f "$LOGGER_SRC" ] || die_broken "logger source missing: $LOGGER_SRC"
    [ -f "$ANALYSE" ] || die_broken "analyser missing: $ANALYSE"

    cc -shared -fPIC -O1 -o "$out/visibility-logger.so" "$LOGGER_SRC" -ldl
    rc=$?
    [ $rc -eq 0 ] || die_broken "logger did not compile (cc rc=$rc)"

    : > "$out/logger.txt"
    # One run, two witnesses - the same design the engine uses. Exit
    # status is captured before anything is formatted or piped.
    SIDEEYE_VISLOG="$out/logger.txt" \
    LD_PRELOAD="$out/visibility-logger.so" \
    strace -f -y -o "$out/strace.txt" \
        -e trace=%file,write,pwrite64,writev,fsync,fdatasync,ftruncate \
        "$@" > "$out/stdout.txt" 2> "$out/stderr.txt"
    target_rc=$?
    echo "== target exit status: $target_rc"
    [ -s "$out/strace.txt" ] || die_broken "strace produced no output"

    python3 "$ANALYSE" "$mode" "$root" "$out/strace.txt" "$out/logger.txt"
}

# The analyser's class set is a second copy of the engine's kill-point
# OpClass (src/contract.zig) — #65's shape, introduced by this change. It
# therefore carries a check that goes red when the engine moves, rather
# than a comment asking the next reader to remember.
DRIFT="$here/class-drift-check.py"

selftest() {
    need cc
    need python3
    echo "== class-drift check against the engine (#65's shape)"
    if [ -f "$DRIFT" ]; then
        python3 "$DRIFT" "$here/../../src/contract.zig" "$ANALYSE"
        rc=$?
        [ $rc -eq 0 ] || return 1
    else
        echo "  BROKEN drift check missing: $DRIFT"
        return 2
    fi
    echo
    tmp=${TMPDIR:-/tmp}/preflight-selftest.$$
    mkdir -p "$tmp/libc/state" "$tmp/raw/state" || die_broken "cannot create $tmp"
    toys="$here/../toys"
    [ -f "$toys/toy.c" ] || die_broken "toy sources not found at $toys"

    cc -o "$tmp/toy" "$toys/toy.c" || die_broken "toy.c did not compile"
    cc -o "$tmp/toy_raw" "$toys/toy_raw.c" || die_broken "toy_raw.c did not compile"

    # The toys need their store initialised; only the rotate is measured.
    TOY_STATE="$tmp/libc/state" "$tmp/toy" init > /dev/null 2>&1 ||
        die_broken "toy init failed"
    TOY_STATE="$tmp/raw/state" "$tmp/toy_raw" init > /dev/null 2>&1 ||
        die_broken "toy_raw init failed"

    fails=0
    echo "== negative control: libc-routed writes must be fully visible"
    mkdir -p "$tmp/libc/out"
    TOY_STATE="$tmp/libc/state" run_measured visibility "$tmp/libc/state" "$tmp/libc/out" \
        env "TOY_STATE=$tmp/libc/state" "$tmp/toy" rotate
    rc=$?
    echo "-- verdict rc=$rc (expected 0)"
    [ $rc -eq 0 ] || fails=$((fails + 1))

    echo
    echo "== positive control: raw-syscall writes must be caught (the cargo class)"
    mkdir -p "$tmp/raw/out"
    TOY_STATE="$tmp/raw/state" run_measured visibility "$tmp/raw/state" "$tmp/raw/out" \
        env "TOY_STATE=$tmp/raw/state" "$tmp/toy_raw" rotate
    rc=$?
    echo "-- verdict rc=$rc (expected 1)"
    [ $rc -eq 1 ] || fails=$((fails + 1))

    echo
    echo "== interior count on the libc toy (informational)"
    run_measured interior "$tmp/libc/state" "$tmp/libc/out" \
        env "TOY_STATE=$tmp/libc/state" "$tmp/toy" rotate

    echo
    echo "== self-test failures: $fails of 2"
    [ $fails -eq 0 ] || return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    visibility | interior)
        mode=$1; shift
        [ $# -ge 1 ] || die_broken "usage: preflight.sh $mode <state-root> -- <cmd>..."
        root=$1; shift
        [ "${1:-}" = "--" ] || die_broken "expected -- before the command"
        shift
        out=${SIDEEYE_PREFLIGHT_OUT:-${TMPDIR:-/tmp}/preflight.$$}
        mkdir -p "$out" || die_broken "cannot create $out"
        echo "== artifacts: $out"
        run_measured "$mode" "$root" "$out" "$@"
        exit $?
        ;;
    *)
        awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
        exit 2 ;;
esac
