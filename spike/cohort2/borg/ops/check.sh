#!/bin/sh
# Cohort-2 borg define (P1) checker. Property (proposals.md P1): crash
# anywhere inside `borg create`, and the repository is valid or
# recoverable through the documented steps — stale-lock removal, then
# `borg check` — with the pre-existing archive `base` conserved
# byte-identically and the listing old-or-new, never a third thing.
#
# The engine snapshots and judges L0 before this runs. All borg reads run
# at the CANONICAL path (a copied repo is a relocated repo to borg's
# security checks). Every borg output is captured with its rc checked (a
# timeout's 124 must never read as an answer).
set -u
D=${SIDEEYE_STATE_DIR:?checker needs SIDEEYE_STATE_DIR}
R="$D/repo"
B=/tmp/cohort2/borg
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(borg-create): $*"; exit 1; }
run() { # name timeout cmd...
    _n=$1; _t=$2; shift 2
    timeout "$_t" "$@" > "$T/$_n" 2>"$T/$_n.err"
    _rc=$?
    [ "$_rc" -eq 0 ] || fail "$_n: '$1 ...' exited $_rc (124 = timeout): $(head -c 200 "$T/$_n.err")"
}

[ -d "$R" ] || fail "the repository is missing from the state dir"

# ---- leg R: the documented stale-lock removal, exactly when a lock exists ----
if [ -e "$R/lock.exclusive" ] || [ -e "$R/lock.roster" ]; then
    echo "checker(borg-create): stale lock present; running the documented borg break-lock"
    timeout 60 borg break-lock "$R" > /dev/null 2>&1 || fail "leg R: borg break-lock failed on a stale lock"
fi

# ---- leg V: the target's own integrity oracle ----
timeout 120 borg check "$R" > /dev/null 2>&1 || fail "leg V: borg check failed after crash (and lock removal, when one ran)"

# ---- leg T: the listing is old-or-new ----
run "leg T list" 60 borg list --short "$R"
listing=$(cat "$T/leg T list")
case "$listing" in
    "base")  new=0 ;;  # old: the interrupted create left no archive
    "base
probe") new=1 ;;       # new: the create committed
    *) fail "leg T: archive listing '$listing' is neither the old state nor the completed create" ;;
esac

# ---- leg C: conservation of the pre-existing archive's bytes ----
mkdir -p "$T/cbase" && cd "$T/cbase"
run "leg C extract" 120 borg extract "$R::base"
printf 'alpha file, fixed bytes\n' > "$T/want-alpha-base"
printf 'beta file, fixed bytes\n'  > "$T/want-beta"
printf 'gamma file, fixed bytes\n' > "$T/want-gamma"
cmp -s "$T/cbase$B/src/alpha" "$T/want-alpha-base" || fail "leg C: base alpha bytes changed"
cmp -s "$T/cbase$B/src/beta"  "$T/want-beta"  || fail "leg C: base beta bytes changed"
cmp -s "$T/cbase$B/src/gamma" "$T/want-gamma" || fail "leg C: base gamma bytes changed"
cd /

# ---- leg N (new side only): the committed create carries the real bytes ----
if [ "$new" -eq 1 ]; then
    mkdir -p "$T/cprobe" && cd "$T/cprobe"
    run "leg N extract" 120 borg extract "$R::probe"
    printf 'alpha, modified fixed bytes\n' > "$T/want-alpha-new"
    cmp -s "$T/cprobe$B/src/alpha" "$T/want-alpha-new" || fail "leg N: probe alpha is neither old nor the archived bytes"
    cmp -s "$T/cprobe$B/src/beta" "$T/want-beta" || fail "leg N: probe lost or changed beta"
    cd /
fi

exit 0
