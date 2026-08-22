#!/bin/sh
# novelty-prescan.sh — record the tracker search that decides whether a
# target's write shape is already known, BEFORE the target is frozen into
# a cohort.
#
# Cohort 3 spent a slot learning this. black was probed, defined, explored
# and reached a reproduced checker-red verdict; only then did the novelty
# search find psf/black#2479, open since 2021, with a fix PR pending. One
# target later, rustfmt's gate was checked before its define existed and
# the cohort kept the knowledge instead of paying for it twice.
#
# This script does NOT decide novelty. It produces the transcript that a
# novelty judgement cites: which queries ran, against which tracker, and
# what came back, with the controls that make a zero mean something.
#
# Two controls run first, every time:
#   positive  psf/black + "disk" must return the two issues this project
#             already knows (2479, 5207). If it does not, the search path
#             is broken and every zero below is meaningless.
#   negative  a nonsense token must return 0, so a zero is a measurement
#             rather than a default.
#
# One measured trap, closed by refusal (2026-08-22, against psf/black):
#
#     disk        -> 30 hits, including 2479 and 5207
#     disk full   -> 0 hits
#     disk+full   -> 5 hits
#     full disk   -> 0 hits
#
#   (all four at --limit 100; the same four at --limit 5 read 5/0/5/0, so
#   the limit is part of the number and belongs in the transcript)
#
# A space-separated phrase silently returns nothing through this API. A
# pre-scan written the natural way ("crash during write", "empty file")
# would report zero for every term and the target would be called novel.
# Multi-word terms are therefore refused, with the + form named.
#
# What this scan does NOT do, measured 2026-08-22 against psf/black:
# it does not enumerate a tracker. A broad term saturates the page limit
# (crash, empty, truncate and truncated all returned exactly 100, i.e. a
# floor, not a count), and only the top 20 by GitHub's relevance order are
# listed. That ordering is why the two known black issues surfaced under
# eight different terms - a property of the ranking, not a guarantee.
# Narrowing with in:title makes it worse, not better: `truncate in:title`
# returns 0 against a repository whose known issue `truncate` finds.
# The scan is built to make a known write shape hard to miss across many
# terms; it cannot prove absence, and no zero here means "novel" on its
# own.
#
# Usage:
#   sh spike/cohort4/novelty-prescan.sh <owner/repo> [extra-terms...]
#   sh spike/cohort4/novelty-prescan.sh --selftest   # the search path
#   sh spike/cohort4/novelty-prescan.sh --validate   # the term list itself
#
# Exit 0 the scan ran with its controls green, 2 the scan could not
# measure. There is no exit 1: this script has no verdict to give.
set -u

# Single tokens, or + joins. The vocabulary is derived from the real
# issues this project has already had to find, not from imagination -
# see --validate, which holds the list to them:
#
#   psf/black#2479        "... wipes or corrupts target when disk is full"
#   psf/black#5207        "Write formatted files atomically to avoid corruption ..."
#   rust-lang/rustfmt#6041 "Gracefully handle full disk instead of erasing file contents"
#
# The third one is why the list is not a matter of taste: it answers only
# `disk` and `disk+full`. Drop `disk` and rustfmt reads as novel.
TERMS=${NOVELTY_TERMS:-'crash corrupt corruption truncated truncate empty atomic atomically
interrupted interrupt sigkill sigint ctrl-c power outage ENOSPC disk partial
incomplete dataloss recover recovery rollback resume half-written
wipe wipes erase erasing erased destroy destroys overwrite clobber
blank unreadable garbage mangled contents in-place unclean shutdown reboot
disk+full data+loss partial+write crash+safe atomic+write lock+file
write+failure file+contents'}

need() {
    command -v "$1" >/dev/null 2>&1 ||
        { echo "BROKEN $1 not installed - the scan cannot measure"; exit 2; }
}

# GitHub's search API allows 30 authenticated requests a minute; a
# throttled scan is slower than a scan that half-refuses on 403.
THROTTLE=${NOVELTY_THROTTLE:-2}

count_hits() { # repo term -> integer, or the word BROKEN
    sleep "$THROTTLE"
    n=$(gh search issues --repo "$1" --include-prs --limit 100 \
            --json number -q 'length' "$2" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "BROKEN"
        return
    fi
    case "$n" in
        ''|*[!0-9]*) echo "BROKEN" ;;
        100) echo ">=100" ;;
        *) echo "$n" ;;
    esac
}

list_hits() { # repo term
    sleep "$THROTTLE"
    gh search issues --repo "$1" --include-prs --limit 20 \
        --json number,state,createdAt,title \
        -q '.[] | "      #\(.number) \(.state) \(.createdAt[0:10]) \(.title)"' \
        "$2" 2>&1
}

controls() {
    echo "== controls (the search path, before any target term is believed)"
    hits=$(count_hits psf/black disk)
    printf '  positive  psf/black + disk -> %s hit(s)\n' "$hits"
    case "$hits" in
        BROKEN) echo "  BROKEN the search path errored - every zero below would be meaningless"; return 2 ;;
        0)      echo "  BROKEN the positive control found nothing - the search path is not working"; return 2 ;;
    esac
    known=$(gh search issues --repo psf/black --include-prs --limit 100 \
                --json number -q '[.[].number] | map(select(. == 2479 or . == 5207)) | length' \
                disk 2>&1)
    printf '  positive  of those, the two known issues present: %s of 2\n' "$known"
    [ "$known" = "2" ] ||
        { echo "  BROKEN the control did not return the issues it is a control for"; return 2; }

    neg=$(count_hits psf/black zzqqxxnotaword)
    printf '  negative  psf/black + zzqqxxnotaword -> %s hit(s) (expected 0)\n' "$neg"
    [ "$neg" = "0" ] ||
        { echo "  BROKEN the negative control matched - a zero would mean nothing"; return 2; }
    return 0
}

selftest() {
    need gh
    controls
    rc=$?
    echo "== self-test rc=$rc (0 expected)"
    return $rc
}

# The slow check: run the whole term list against repositories whose
# crash-consistency issues this project already knows, and require that
# they come back. A term list that cannot find a known issue would call
# its target novel - which is the one mistake this script exists to stop.
validate() {
    need gh
    fails=0
    check_known() { # repo issue-number
        found=0
        for t in $TERMS; do
            hits=$(list_hits "$1" "$t" 2>&1)
            case "$hits" in
                *"#$2 "*) found=1; echo "  found #$2 in $1 via term: $t"; break ;;
            esac
        done
        if [ $found -eq 0 ]; then
            echo "  MISSED #$2 in $1 - no term in the list surfaces it"
            fails=$((fails + 1))
        fi
    }
    echo "== validate: the term list against issues this project already knows"
    check_known psf/black 2479
    check_known psf/black 5207
    check_known rust-lang/rustfmt 6041
    echo "== validate failures: $fails of 3"
    [ $fails -eq 0 ] || return 1
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    --validate) validate; exit $? ;;
    "" | -h | --help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 2 ;;
esac

need gh
repo=$1
shift

for t in "$@"; do
    case "$t" in
        *\ *) echo "BROKEN refusing the multi-word term '$t': a space-separated"
              echo "       phrase silently returns zero through this API. Use '$(printf '%s' "$t" | tr ' ' '+')'."
              exit 2 ;;
    esac
done

echo "== novelty pre-scan: $repo"
echo "== date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
controls || exit 2

echo
echo "== terms"
hit_terms=0
saturated=0
term_count=0
for t in $TERMS "$@"; do
    term_count=$((term_count + 1))
    hits=$(count_hits "$repo" "$t")
    case "$hits" in
        BROKEN) echo "  BROKEN the search errored on term '$t' - the scan is incomplete"; exit 2 ;;
    esac
    case "$hits" in
        ">=100") printf '  %-14s >=100 hit(s) - SATURATED at the page limit; the number is a floor, and only the top 20 by relevance are listed below\n' "$t"
                 saturated=$((saturated + 1))
                 hit_terms=$((hit_terms + 1))
                 list_hits "$repo" "$t" ;;
        0)       printf '  %-14s 0 hit(s)\n' "$t" ;;
        *)       printf '  %-14s %s hit(s) (all listed)\n' "$t" "$hits"
                 hit_terms=$((hit_terms + 1))
                 list_hits "$repo" "$t" ;;
    esac
done

echo
echo "== $term_count terms run; $hit_terms returned hits, $saturated of those saturated at the page limit"
echo "== counts are not summed: a saturated term has no count, and one issue answers many terms"
echo "== this script does not decide novelty. The judgement, and the write"
echo "   shape it is about, go in the target's proposal citing this transcript."
