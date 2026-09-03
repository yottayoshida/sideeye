#!/bin/sh
# spike/lib/check-transcript.sh: a probe transcript must show that every verdict
# the cohort's manifest requires was actually JUDGED — not merely that nothing
# failed. The general form of cohort 4's probes/check-transcript.sh (#259),
# which hard-coded its four expected sets; this one reads them from a manifest,
# so the next cohort writes a table instead of a script.
#
# The accident that produced the original (2026-08-23): an interrupted edit
# truncated run-unison.sh mid-block, deleting a whole check and leaving comment
# lines. The result was still VALID SHELL: it ran, judged one condition fewer,
# and reported "conditions failed: 0". A green whose measured set is smaller
# than its claimed set is the register's own row: a count of zero failures says
# nothing until the size of the scan is asserted too.
#
# Scope, so a pass is read correctly: this compares verdict NAMES. A truncation
# that removed a predicate while leaving its verdict call still passes here. It
# closes the shape the accident had, not the class.
#
# Manifest: a TSV with four tab-separated columns and `#` comment lines — the
# same file the CI walker reads, so one format:
#
#   target<TAB>mode<TAB>transcript-file<TAB>space-separated verdict names
#
# The transcript-file column is the walker's (which file to check); this
# script is handed the transcript path on its command line and reads the names
# from the fourth column.
#
# Usage:
#   sh check-transcript.sh <manifest.tsv> <target> <mode> <transcript>
#   sh check-transcript.sh --list-rows <manifest.tsv>
#   sh check-transcript.sh --selftest
#
# --list-rows prints one line per manifest row — row number, target, mode and
# transcript file, joined by the unit separator (0x1f) — through the same
# filter `expected_for` applies, so the walker and this checker cannot read
# the manifest by two definitions.
#
# Exit 0 the emitted verdict set equals the expected set, 1 they differ
# (missing, renamed or extra), 2 the check could not run. Never read a 2 as a
# pass.
set -u

usage() { echo "usage: $0 <manifest.tsv> <target> <mode> <transcript> | $0 --list-rows <manifest.tsv> | $0 --selftest" >&2; exit 2; }

# The one reading of a manifest row: a non-comment line with at least four tab-separated
# columns. `expected_for` and `list_rows` both go through it.
manifest_rows() { # manifest awk-action
    awk -F'\t' -v OFS="$(printf '\037')" '$0 !~ /^#/ && NF >= 4 '"$2" "$1"
}

# Every non-comment, non-blank line is listed — a line with fewer than four columns
# comes out with empty columns, which the walker refuses by name, rather than vanishing.
list_rows() { # manifest
    [ -f "$1" ] || { echo "BROKEN check-transcript: no such manifest: $1" >&2; return 2; }
    awk -F'\t' -v OFS="$(printf '\037')" '$0 !~ /^#/ && $0 !~ /^[[:space:]]*$/ { print NR, $1, $2, $3 }' "$1"
}

# The expected set for target/mode, from the manifest. Exactly one row must match.
# awk reads the last line whether or not it ends in a newline, so a manifest
# written without one keeps its final row (the `while read` shape drops it).
expected_for() { # manifest target mode
    [ -f "$1" ] || return 1
    _rows=$(manifest_rows "$1" '&& $1 == "'"$2"'" && $2 == "'"$3"'" { print $4 }')
    [ -n "$_rows" ] || return 1
    [ "$(printf '%s\n' "$_rows" | wc -l | tr -d ' ')" -eq 1 ] || return 1
    printf '%s\n' "$_rows"
}

# Every verdict name the transcript actually carries, deduped and sorted.
# awk, not sed: sed's \| alternation is a GNU extension and matched nothing on
# BSD sed — caught by the instrument control below on the original's first run.
emitted_from() { # transcript
    awk '($1=="ok"||$1=="FAIL") && $2 ~ /^[A-Za-z0-9][A-Za-z0-9-]*:$/ {
             n=$2; sub(/:$/,"",n); print n }' "$1" | sort -u
}

check() { # manifest target mode transcript
    _mf=$1; _t=$2; _m=$3; _f=$4
    [ -f "$_f" ] || { echo "BROKEN check-transcript: no such transcript: $_f"; return 2; }
    [ -f "$_mf" ] || { echo "BROKEN check-transcript: no such manifest: $_mf"; return 2; }
    _want=$(expected_for "$_mf" "$_t" "$_m") || {
        echo "BROKEN check-transcript: the manifest $_mf has no single row for target=$_t mode=$_m"; return 2; }

    _got=$(emitted_from "$_f")
    # Instrument control: a zero extraction and a transcript with no verdicts at
    # all are the same number. Refuse to report a set difference when the
    # extractor found nothing.
    _n=$(printf '%s\n' "$_got" | grep -c '[^[:space:]]')
    if [ "$_n" -eq 0 ]; then
        echo "BROKEN check-transcript: the extractor found 0 verdict lines in $_f - it cannot tell 'every condition missing' from 'the pattern does not match this file'"
        return 2
    fi

    # Both directions through the same literal membership test: names are
    # `[A-Za-z0-9-]` by the extractor's pattern, so a `case` over the space-joined
    # set is exact — `1-exit.codes` cannot match `1-exit-codes` and hide a rename.
    _gotline=" $(printf '%s\n' "$_got" | tr '\n' ' ') "
    _missing=""
    for _e in $_want; do
        case "$_gotline" in *" $_e "*) ;; *) _missing="$_missing $_e" ;; esac
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
    # A fresh directory per run; cleanup by named file, not recursive delete.
    _ws=$(mktemp -d "${TMPDIR:-/tmp}/lib-check-transcript-selftest-XXXXXX") \
        || { echo "BROKEN selftest: cannot create a work directory"; exit 2; }
    trap 'rm -f "$_ws"/*; rmdir "$_ws" 2>/dev/null' EXIT
    _fails=0
    _cases=0
    expect_rc() { # WANT LABEL manifest target mode transcript
        _er_want=$1; _er_label=$2; shift 2
        _cases=$((_cases + 1))
        echo "-- selftest $_cases: $_er_label"
        check "$@"; _er_rc=$?
        [ "$_er_rc" -eq "$_er_want" ] || { echo "SELFTEST FAIL: $_er_label returned $_er_rc, wanted $_er_want"; _fails=$((_fails+1)); }
    }
    _mf="$_ws/verdicts.tsv"
    {
        echo "# synthetic manifest for the selftest: cohort 4's unison sets, verbatim"
        printf 'unison\tbare\tunison-bare.txt\t%s\n' "1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism-falsification 6-closure 8-visibility-falsification"
        # The last row is written WITHOUT a trailing newline on purpose: a manifest saved
        # that way must still yield its final row.
        printf 'unison\tapparatus\tunison.txt\t%s' "1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism 6-closure seccomp-active 8-visibility 9-interior"
    } > "$_mf"

    for _n in 1-exit-codes 2-non-noop 3-artifacts 4-round-trip \
              5-determinism-falsification 6-closure 8-visibility-falsification; do
        echo "ok   $_n: synthetic" >> "$_ws/complete.txt"
    done
    echo "== some prose that is not a verdict: 4-round-trip appears here too" >> "$_ws/complete.txt"
    # The line the sealed checker appends to a captured transcript (capture.sh): its first
    # word is none of ok/FAIL, so it must not be read as a verdict.
    echo "verdict manifest (unison/bare): expected 7, found 7" >> "$_ws/complete.txt"

    expect_rc 0 "a complete transcript must pass" "$_mf" unison bare "$_ws/complete.txt"

    # The accident's own shape: one verdict block deleted.
    grep -v '^ok   4-round-trip:' "$_ws/complete.txt" > "$_ws/missing.txt"
    expect_rc 1 "a deleted verdict must turn it red" "$_mf" unison bare "$_ws/missing.txt"

    # The other direction of set inequality: a renamed verdict.
    sed 's/^ok   6-closure:/ok   6-clsoure:/' "$_ws/complete.txt" > "$_ws/renamed.txt"
    expect_rc 1 "a renamed verdict must turn it red on both sides" "$_mf" unison bare "$_ws/renamed.txt"

    # A rename that a pattern match would forgive: `.` in the transcript's name matches
    # `-` in the manifest's unless the names are compared as literals.
    sed 's/^ok   1-exit-codes:/ok   1-exit.codes:/' "$_ws/complete.txt" > "$_ws/dotted.txt"
    expect_rc 1 "a rename that only a literal comparison catches must turn it red" "$_mf" unison bare "$_ws/dotted.txt"

    # A verdict the plan never asked for, with none missing.
    cp "$_ws/complete.txt" "$_ws/extra.txt"
    echo "ok   10-invented: synthetic" >> "$_ws/extra.txt"
    expect_rc 1 "an extra verdict alone must turn it red" "$_mf" unison bare "$_ws/extra.txt"

    # A target/mode this manifest has no row for must be BROKEN, never "nothing required".
    expect_rc 2 "an unknown target/mode must be BROKEN (2)" "$_mf" unison sideways "$_ws/complete.txt"

    # The extractor's own control.
    echo "== nothing here is a verdict line" > "$_ws/empty.txt"
    expect_rc 2 "a transcript with no verdicts must be BROKEN (2), not a set difference" "$_mf" unison bare "$_ws/empty.txt"

    # The accident's other face: a transcript cut off mid-run keeps its early verdicts
    # and loses the late ones. Non-empty, so the instrument control passes it through,
    # and the set difference has to catch it.
    head -n 3 "$_ws/complete.txt" > "$_ws/truncated.txt"
    expect_rc 1 "a transcript truncated mid-run must turn it red" "$_mf" unison bare "$_ws/truncated.txt"

    # The apparatus row is the manifest's last line and has no trailing newline.
    for _n in 1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism 6-closure seccomp-active 8-visibility 9-interior; do
        echo "ok   $_n: synthetic" >> "$_ws/complete-ap.txt"
    done
    expect_rc 0 "the manifest's last row, written without a trailing newline, is read" "$_mf" unison apparatus "$_ws/complete-ap.txt"

    printf '\nunison\tbare\tunison-bare.txt\t1-exit-codes\n' >> "$_mf"
    expect_rc 2 "a manifest with two rows for one target/mode must be BROKEN (2)" "$_mf" unison bare "$_ws/complete.txt"

    echo "== selftest failures: $_fails of $_cases"
    [ "$_fails" -eq 0 ] || exit 1
    exit 0
}

[ $# -ge 1 ] || usage
[ "$1" = "--selftest" ] && selftest
if [ "$1" = "--list-rows" ]; then
    [ $# -eq 2 ] || usage
    list_rows "$2"; exit $?
fi
[ $# -eq 4 ] || usage
check "$1" "$2" "$3" "$4"
exit $?
