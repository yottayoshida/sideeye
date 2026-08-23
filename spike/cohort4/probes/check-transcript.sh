#!/bin/sh
# check-transcript.sh: the probe transcript must show that every condition
# the frozen plan requires was actually JUDGED, not merely that nothing
# failed. PROTOCOL.md says "all nine conditions or the probe has not
# passed"; until this script that requirement was honoured by hand.
#
# Why it exists, from the accident that produced it (2026-08-23): an
# interrupted edit truncated run-unison.sh mid-block, deleting the whole
# 4-round-trip check and leaving behind only comment lines. The result was
# still VALID SHELL: it ran, judged one condition fewer, and would have
# reported "conditions failed: 0". A green whose measured set is smaller
# than its claimed set is the register's own row: a count of zero failures
# says nothing until the size of the scan is asserted too.
#
# Usage:
#   sh check-transcript.sh <target> <mode> <transcript-file>
#   sh check-transcript.sh --selftest
#
# Exit 0 the emitted verdict set equals the expected set, 1 they differ
# (missing, renamed or extra), 2 the check could not run. Never read a 2
# as a pass.
set -u

usage() { echo "usage: $0 <target> <mode> <transcript> | $0 --selftest" >&2; exit 2; }

# The expected sets, per target and mode. These are the names the frozen
# plans require to be judged; 6-closure is emitted by cohort 2's
# closure_check, the rest by the probe script itself, and reading them off
# the transcript covers both sources uniformly.
expected_for() { # target mode
    case "$1/$2" in
      himalaya/bare)
        echo "1-exit-codes 2-non-noop 3-artifact-count 4-round-trip 5-determinism-falsification 6-closure 8-visibility-falsification" ;;
      himalaya/apparatus)
        echo "1-exit-codes 2-non-noop 3-artifact-count 4-round-trip 5-determinism 6-closure seccomp-active 8-visibility 9-interior" ;;
      unison/bare)
        echo "1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism-falsification 6-closure 8-visibility-falsification" ;;
      unison/apparatus)
        echo "1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism 6-closure seccomp-active 8-visibility 9-interior" ;;
      *) return 1 ;;
    esac
}

# Every verdict name the transcript actually carries, deduped and sorted.
# awk, not sed: the first cut used sed's \| alternation, which is a GNU
# extension - it matched inside the container and extracted nothing on the
# macOS host, where BSD sed treats it literally. The instrument control
# below is what caught that, on this script's own first run.
emitted_from() { # transcript
    awk '($1=="ok"||$1=="FAIL") && $2 ~ /^[A-Za-z0-9][A-Za-z0-9-]*:$/ {
             n=$2; sub(/:$/,"",n); print n }' "$1" | sort -u
}

check() { # target mode transcript
    _t=$1; _m=$2; _f=$3
    [ -f "$_f" ] || { echo "BROKEN check-transcript: no such transcript: $_f"; return 2; }
    _want=$(expected_for "$_t" "$_m") || {
        echo "BROKEN check-transcript: no expected set for target=$_t mode=$_m"; return 2; }

    _got=$(emitted_from "$_f")
    # Instrument control (the C2 register row): a zero extraction and a
    # transcript with no verdicts at all are the same number. Refuse to
    # report a set difference when the extractor found nothing.
    _n=$(printf '%s\n' "$_got" | grep -c '[^[:space:]]')
    if [ "$_n" -eq 0 ]; then
        echo "BROKEN check-transcript: the extractor found 0 verdict lines in $_f - it cannot tell 'every condition missing' from 'the pattern does not match this transcript'"
        return 2
    fi

    _missing=""
    for _e in $_want; do
        printf '%s\n' "$_got" | grep -qx "$_e" || _missing="$_missing $_e"
    done
    _extra=""
    for _g in $_got; do
        case " $_want " in *" $_g "*) ;; *) _extra="$_extra $_g" ;; esac
    done

    echo "verdict manifest ($_t/$_m): expected $(printf '%s' "$_want" | wc -w | tr -d ' '), found $_n"
    echo "  expected:$(printf '%s' " $_want")"
    echo "  emitted: $(printf '%s\n' "$_got" | tr '\n' ' ')"
    if [ -n "$_missing" ] || [ -n "$_extra" ]; then
        [ -n "$_missing" ] && echo "  MISSING:$_missing (a condition the plan requires was not judged)"
        [ -n "$_extra" ] && echo "  UNEXPECTED:$_extra (a renamed or extra verdict - the plan and the harness disagree)"
        echo "MANIFEST FAIL: the judged set is not the required set"
        return 1
    fi
    echo "MANIFEST PASS: every required condition was judged"
    return 0
}

selftest() {
    # A fresh directory per run, and cleanup by named file rather than by
    # recursive delete (the workspace's own rule; a recursive rm here is
    # both unnecessary and blocked by the local guard).
    _ws=$(mktemp -d "${TMPDIR:-/tmp}/check-transcript-selftest-XXXXXX") \
        || { echo "BROKEN selftest: cannot create a work directory"; exit 2; }
    trap 'rm -f "$_ws/complete.txt" "$_ws/missing.txt" "$_ws/renamed.txt" "$_ws/empty.txt"; rmdir "$_ws" 2>/dev/null' EXIT
    _fails=0

    # A complete synthetic transcript for unison/bare.
    for _n in 1-exit-codes 2-non-noop 3-artifacts 4-round-trip \
              5-determinism-falsification 6-closure 8-visibility-falsification; do
        echo "ok   $_n: synthetic" >> "$_ws/complete.txt"
    done
    echo "== some prose that is not a verdict: 4-round-trip appears here too" >> "$_ws/complete.txt"

    echo "-- selftest 1: a complete transcript must pass"
    check unison bare "$_ws/complete.txt"; _rc=$?
    [ "$_rc" -eq 0 ] || { echo "SELFTEST FAIL: complete transcript returned $_rc"; _fails=$((_fails+1)); }

    # Red 1, the accident's own shape: one verdict block deleted.
    grep -v '^ok   4-round-trip:' "$_ws/complete.txt" > "$_ws/missing.txt"
    echo "-- selftest 2: a deleted verdict must turn it red"
    check unison bare "$_ws/missing.txt"; _rc=$?
    [ "$_rc" -eq 1 ] || { echo "SELFTEST FAIL: missing-verdict transcript returned $_rc, wanted 1"; _fails=$((_fails+1)); }

    # Red 2, the other direction of set inequality: a renamed verdict.
    # The accident cannot produce this one, which is why it is here.
    sed 's/^ok   6-closure:/ok   6-clsoure:/' "$_ws/complete.txt" > "$_ws/renamed.txt"
    echo "-- selftest 3: a renamed verdict must turn it red on both sides"
    check unison bare "$_ws/renamed.txt"; _rc=$?
    [ "$_rc" -eq 1 ] || { echo "SELFTEST FAIL: renamed-verdict transcript returned $_rc, wanted 1"; _fails=$((_fails+1)); }

    # Red 3: the extractor's own control. A transcript with no verdict
    # lines must be BROKEN, never "everything missing".
    echo "== nothing here is a verdict line" > "$_ws/empty.txt"
    echo "-- selftest 4: a transcript with no verdicts must be BROKEN (2), not a set difference"
    check unison bare "$_ws/empty.txt"; _rc=$?
    [ "$_rc" -eq 2 ] || { echo "SELFTEST FAIL: verdict-less transcript returned $_rc, wanted 2"; _fails=$((_fails+1)); }

    echo "== selftest failures: $_fails of 4"
    [ "$_fails" -eq 0 ] || exit 1
    exit 0
}

[ $# -ge 1 ] || usage
[ "$1" = "--selftest" ] && selftest
[ $# -eq 3 ] || usage
check "$1" "$2" "$3"
exit $?
