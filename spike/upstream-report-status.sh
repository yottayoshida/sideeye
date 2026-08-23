#!/bin/sh
# upstream-report-status.sh — measure, rather than remember, where this
# project's upstream reports stand.
#
# The reports are cited in PRD.md, #140 and the cohort records, and every
# citation carries dates. Hand-written dates go stale silently: a table
# saying "0 comments" is indistinguishable from a table nobody re-read.
# This prints the state as of now, in a form that can be pasted into a
# document with its measurement date attached.
#
# Usage:
#   sh spike/upstream-report-status.sh            # the standing reports
#   sh spike/upstream-report-status.sh --selftest # falsify the reader
#
# Exit 0 measured, 2 could not measure. There is no exit 1 - this script
# reports, it does not judge.
set -u

# The filed reports, one per line: <owner/repo> <number>. Additions here
# are the only place the list lives.
REPORTS='GothenburgBitFactory/timewarrior 778
topydo/topydo 341
aspiers/stow 139
lfos/calcurse 529
python-poetry/poetry 11019'

command -v gh >/dev/null 2>&1 ||
    { echo "BROKEN gh not installed - cannot measure"; exit 2; }

read_one() { # repo number -> "state comments updatedAt" or BROKEN
    out=$(gh issue view "$2" -R "$1" \
              --json state,comments,updatedAt \
              -q '"\(.state) \(.comments|length) \(.updatedAt[0:10])"' 2>&1)
    rc=$?
    [ $rc -eq 0 ] || { echo "BROKEN rc=$rc"; return; }
    printf '%s\n' "$out"
}

if [ "${1:-}" = "--selftest" ]; then
    # The reader must be able to come back with something other than the
    # answer it is used to. The control is an issue known to carry
    # comments: if it reads back as zero, the reader is not reading.
    echo "== control: a known issue with comments must not read as 0"
    ctl=$(read_one psf/black 2479)
    echo "  psf/black#2479 -> $ctl (expected OPEN with a non-zero comment count)"
    case "$ctl" in
        BROKEN*) echo "== self-test FAILED: the reader errored"; exit 2 ;;
        "OPEN 0 "*) echo "== self-test FAILED: control reads zero comments"; exit 2 ;;
    esac
    echo "== self-test ok"
    exit 0
fi

echo "| Report | State | Comments | Last activity |"
echo "|---|---|---|---|"
broken=0
n=0
printf '%s\n' "$REPORTS" | while read -r repo num; do
    [ -n "$repo" ] || continue
    n=$((n + 1))
    row=$(read_one "$repo" "$num")
    case "$row" in
        BROKEN*) echo "| \`$repo#$num\` | BROKEN | - | - |"; broken=$((broken + 1)) ;;
        *) set -- $row
           echo "| \`$repo#$num\` | $1 | $2 | $3 |" ;;
    esac
done
echo
echo "measured $(date -u +%Y-%m-%dT%H:%M:%SZ) by spike/upstream-report-status.sh"
exit 0
