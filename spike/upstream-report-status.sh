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
# NOT CHECKED (#297, split out of #271): whether this list still matches the
# set of reports actually filed. A report filed upstream without being added
# here is invisible - the cohort-4 close depended on remembering to add
# himalaya by
# hand (PR #253). Declaring an expected count beside the list does not fix
# it: both would be forgotten together.
#
# Deriving the list from the tracker was tried and does not work, which is a
# stronger reason than the one first written here. The first candidate it
# returns is a false positive: `alecthomas/devtodo#9` exists, was opened by
# this account, and is absent from the list - because it was filed and
# WITHDRAWN the same day, on the owner's judgement (spike/assisted/NOVELTY.md;
# outcome-map.tsv and docs/target-classes.md agree). A withdrawn report and an
# unlisted one have the same shape in the tracker. What separates them is a
# judgement recorded in prose, which no derivation reads. So the gap stays
# open and named; what changed (#297) is only that the closing line now says
# whose denominator it is reporting.
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
    trap 'rm -f "$st_dir/gh" "$st_dir/short.sh"; rmdir "$st_dir" 2>/dev/null' EXIT

    # The short leg below reads this file with `sed`, which — unlike `sh "$self"` —
    # does no PATH search. Readability is therefore checked first and PATH is only a
    # fallback: `sh script.sh` from the directory holding it gives a $0 with no slash
    # that sed opens perfectly well, and an earlier version of this block resolved
    # through PATH unconditionally and turned that working invocation into a refusal.
    #
    # NOT a fix for an observed failure. A PATH invocation gives $0 as an absolute
    # path — the shell resolves before exec — so the case this guards was never
    # reachable through the documented usage. It is here because the short leg depends
    # on reading this file, and it should say so where it fails rather than produce a
    # confusing sed error.
    self=$0
    [ -r "$self" ] || self=$(command -v -- "$self" 2>/dev/null) || self=""
    [ -n "$self" ] && [ -r "$self" ] || {
        echo "== self-test FAILED: cannot read this script (\$0 = $0) — the short leg needs to"
        exit 2; }
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
    leg_rows 1 "read $report_count of $report_count reports listed in REPORTS" \
        "green leg names its own denominator"

    # The denominator has to come from the list, not from a number written beside
    # it (#297). Checked by running a COPY of this script with one report row
    # deleted: if the closing line still says the old count, the count is a
    # constant pretending to be a measurement.
    #
    # A copy rather than an env override: an override would be a surface that
    # exists only for the test, and the thing under test is what the committed
    # script does with the committed list.
    short_self="$st_dir/short.sh"
    sed '/^topydo\/topydo 341$/d' "$self" > "$short_self" || {
        echo "== self-test FAILED: could not build the shortened copy"; exit 2; }
    short_count=$((report_count - 1))
    if [ "$(grep -c '^topydo/topydo 341$' "$short_self")" != "0" ]; then
        echo "== self-test FAILED: the shortened copy still carries the row it was meant to lose"
        exit 2
    fi
    echo "== short leg: one row fewer must change the denominator"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "== self-test FAILED: short leg exited $rc, wanted 0"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        rm -f "$short_self"; exit 2
    fi
    leg_rows "$short_count" '^| `' "short leg emitted rows"
    leg_rows 1 "read $short_count of $short_count reports listed in REPORTS" \
        "short leg denominator followed the list"
    leg_rows 0 "read $report_count of $report_count reports listed in REPORTS" \
        "short leg must not still claim the full count"
    rm -f "$short_self"

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

# The denominator is named, and it is named as this list's (#297). Until now the
# success path printed no count at all, so a reader took completeness from the
# table looking whole - and the table is whole with respect to REPORTS, which is
# not the same as whole with respect to what was filed. A report filed without
# editing the literal above is still invisible here; this line does not find it,
# it only stops the output from implying there is nothing to find.
#
# NOT A FIX FOR #297. The claim shrank; the ability did not grow. Forget to add an
# eighth report and this still says "N of N reports listed in REPORTS" and exits 0.
# What it buys is that the sentence is true, and that the reader can see the
# denominator is list-relative.
#
# $n rather than a constant: the count comes from the rows the loop actually
# walked, so a row that stops being walked changes the number. A literal here
# would agree with the list only until someone edited one of them.
if [ "$broken" -gt 0 ]; then
    echo
    echo "could not read $broken of $n reports listed in REPORTS - the rows above are incomplete"
    exit 2
fi
echo "read $n of $n reports listed in REPORTS (this list, not every report ever filed - #297)"
exit 0
