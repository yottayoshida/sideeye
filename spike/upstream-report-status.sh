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
#
# "Could not measure" includes a report whose row came back BROKEN, not just
# a missing gh. Through #271 it did not: `broken` was incremented inside a
# pipeline subshell, so nothing outside the loop could read it, and the
# script ended `exit 0` unconditionally - a table whose every row was BROKEN
# exited 0 under a header promising "Exit 0 measured". Judging OPEN against
# CLOSED is still not this script's business; being unable to read a report
# at all is a failure to measure, which is what exit 2 already meant for a
# missing gh a few lines below.
set -u

# The filed reports, one per line: <owner/repo> <number>. Additions here
# are the only place the list lives.
#
# NOT CHECKED (#271): whether this list still matches the set of reports
# actually filed. A report filed upstream without being added here is
# invisible - the cohort-4 close depended on remembering to add himalaya by
# hand (PR #253). Declaring an expected count beside the list does not fix
# it: both would be forgotten together. Deriving the list from the tracker
# needs a second network dependency with its own failure modes, so the gap
# is left open and named rather than papered over.
REPORTS='GothenburgBitFactory/timewarrior 778
topydo/topydo 341
aspiers/stow 139
lfos/calcurse 529
python-poetry/poetry 11019
pimalaya/himalaya 738'

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

    # The exit code has to move in both directions, and it has to be measured
    # on this script rather than on a copy of its logic: the copy is the
    # thing that keeps agreeing with itself. Both legs re-invoke this file
    # with a fake `gh` first in PATH, so the real loop, the real counter and
    # the real exit decision are what answer.
    #
    # Before #271 the failing leg exited 0 - the counter died in a pipeline
    # subshell and nothing read it - so a fully unreadable table was
    # indistinguishable from a clean one.
    st_dir=$(mktemp -d "${TMPDIR:-/tmp}/upstream-selftest-XXXXXX") || {
        echo "== self-test FAILED: could not make a scratch dir"; exit 2; }
    # Named removal, not `rm -rf`: this scratch dir holds exactly one file we
    # put there, so deleting it by name cannot take anything else with it,
    # and it does not trip the recursive-delete guards some developers run
    # locally - one of which silently left the directory behind here.
    trap 'rm -f "$st_dir/gh"; rmdir "$st_dir" 2>/dev/null' EXIT

    self=$0
    leg_out=""

    # Run this script with the fake gh in front, and require the exit code the
    # leg is named for. The output is kept in $leg_out for the row assertion
    # that follows each call: an exit code alone cannot tell a run that
    # measured everything from one that printed nothing, or a BROKEN row from
    # the gh-missing guard that exits 2 without entering the loop at all.
    leg() { # want_rc label
        echo "== $2"
        leg_out=$(PATH="$st_dir:$PATH" sh "$self" 2>&1)
        rc=$?
        [ "$rc" = "$1" ] && return 0
        echo "== self-test FAILED: $2 — exited $rc, wanted $1"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    }

    leg_rows() { # want_count pattern what
        got=$(printf '%s' "$leg_out" | grep -c "$2")
        [ "$got" = "$1" ] && return 0
        echo "== self-test FAILED: $3 — found $got, wanted $1"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    }

    report_count=$(printf '%s\n' "$REPORTS" | grep -c .)

    printf '#!/bin/sh\nexit 7\n' > "$st_dir/gh"        # every read fails
    chmod +x "$st_dir/gh"
    leg 2 "red leg: every report unreadable must not exit 0"
    leg_rows "$report_count" '| BROKEN |' "red leg BROKEN rows"

    # One unreadable report out of six. This is the leg that pins the predicate:
    # all-BROKEN and all-readable are also satisfied by `broken == n`, so without a
    # mixed run the requirement being checked would be "every report failed" rather
    # than "any report failed".
    cat > "$st_dir/gh" <<'FAKE'
#!/bin/sh
case " $* " in
    *" 139 "*) exit 7 ;;   # aspiers/stow, one of the six
    *) echo "OPEN 3 2026-01-01" ;;
esac
FAKE
    chmod +x "$st_dir/gh"
    leg 2 "mixed leg: one unreadable report out of six must still not exit 0"
    leg_rows 1 '| BROKEN |' "mixed leg BROKEN rows"

    printf '#!/bin/sh\necho "OPEN 3 2026-01-01"\n' > "$st_dir/gh"
    chmod +x "$st_dir/gh"
    leg 0 "green leg: every report readable must exit 0"
    leg_rows "$report_count" '^| `' "green leg emitted rows"

    echo "== self-test ok"
    exit 0
fi

echo "| Report | State | Comments | Last activity |"
echo "|---|---|---|---|"
broken=0
n=0
# Fed by redirection, not a pipe. A `printf | while read` loop runs in a
# subshell, so `broken` and `n` were incremented in a process that then
# exited, leaving both unreadable here and the script's own verdict
# unwritable (#271). The same shape is avoided deliberately elsewhere in
# this tree - see the comment above the loop in unknown-rate/sweep.sh,
# which calls pipes-hide-failures a measured class in this workspace, and
# blind-hunt2/verify-seals.sh, which uses `done < file` so an in-loop exit
# survives. A here-doc rather than a here-string: this is #!/bin/sh, which
# is dash on Linux, and <<< is a bashism.
while read -r repo num; do
    [ -n "$repo" ] || continue
    n=$((n + 1))
    row=$(read_one "$repo" "$num")
    case "$row" in
        BROKEN*) echo "| \`$repo#$num\` | BROKEN | - | - |"; broken=$((broken + 1)) ;;
        *) set -- $row
           echo "| \`$repo#$num\` | $1 | $2 | $3 |" ;;
    esac
done <<EOF
$REPORTS
EOF
echo
echo "measured $(date -u +%Y-%m-%dT%H:%M:%SZ) by spike/upstream-report-status.sh"

# Every row is printed before this decides anything: a partial table is more
# useful than none, and the caller asked for the standing state. The exit
# code is what an unattended caller reads, and it has to distinguish
# "measured, here it is" from "could not read $broken of $n of them".
if [ "$broken" -gt 0 ]; then
    echo
    echo "could not read $broken of $n reports - the rows above are incomplete"
    exit 2
fi
exit 0
