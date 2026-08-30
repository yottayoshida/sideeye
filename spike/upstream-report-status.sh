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

# The filed reports come from spike/upstream-reports.tsv, which is the record
# rather than a copy of one. Until #297 this list lived here as a literal, and a
# report filed without editing the literal was invisible: the table looked
# whole, every row read fine, and the script exited 0 - six of six and six of
# seven print the same way. The cohort-4 close depended on remembering to add
# himalaya by hand (PR #253), and nothing asked.
#
# spike/check-upstream-ledger.sh now holds that ledger and the
# <!-- upstream-report: ... --> markers in docs/target-classes.md to each other
# in both directions, in CI. A filing recorded in one place and not the other is
# red rather than silent. What the pair cannot see is a filing written into
# neither record - and prose naming a report in that file is not one of the
# records, only a marker is. The closing line says that rather than implying
# otherwise.
#
# Deriving the list from a tracker was tried and does not work. The first
# candidate it returns is a false positive: `alecthomas/devtodo#9` exists, was
# opened by this account, and stood outside the list - because it was filed and
# WITHDRAWN the same day, on the owner's judgement (spike/assisted/NOVELTY.md).
# A withdrawn report and an unlisted one have the same shape on a tracker. The
# ledger's status column is what separates them, and it carries that row now.
#
# Readability first, PATH only as a fallback: `sh script.sh` from the directory
# holding it gives a $0 with no slash that opens perfectly well, and resolving
# through PATH first turns that working invocation into a refusal whenever the
# script's own directory is not on PATH. That inversion was shipped once here.
self=$0
[ -r "$self" ] || self=$(command -v -- "$self" 2>/dev/null) || self=""
[ -n "$self" ] && [ -r "$self" ] || {
    echo "BROKEN cannot read this script (\$0 = $0) - the ledger is resolved from it"
    exit 2; }
LEDGER=$(dirname -- "$self")/upstream-reports.tsv
[ -r "$LEDGER" ] || { echo "BROKEN cannot read the ledger: $LEDGER"; exit 2; }

# The standing rows come from check-upstream-ledger.sh, which checks the two
# records against each other first and prints the subset only if they hold. Two
# things follow from asking rather than selecting.
#
# The contract is enforced HERE and not only in CI, because this is the script a
# person runs by hand: without it a status typo drops a standing report and this
# table prints "N of N" over the smaller N and exits 0, which is the sentence
# #297 was filed about, one column to the right.
#
# And the selection has one implementation. Restating it is what drifted, inside
# a single review round: this script spelled a comment `^#` while the checker
# spelled it `^[ \t]*#`, so an indented comment line carrying four fields was a
# comment to one reader and a report to the other, and the table printed
# "read 7 of 7" over six standing reports — silently over-counting, where #297
# was silently under-counting. One reader of the ledger, not two required to
# stay in step.
CHECKER=$(dirname -- "$self")/check-upstream-ledger.sh
[ -r "$CHECKER" ] || {
    echo "BROKEN cannot read $CHECKER - the ledger would go unverified"; exit 2; }
REPORTS=$(sh "$CHECKER" --standing 2>&1); _lc_rc=$?
[ "$_lc_rc" -eq 0 ] || {
    echo "BROKEN the ledger does not pass spike/check-upstream-ledger.sh, so this table"
    echo "       would be measuring an unknown subset of what was filed:"
    printf '%s\n' "$REPORTS" | sed 's/^/       /'
    exit 2; }
# A ledger that passes the checker can still name no standing report - every row
# withdrawn - and an empty table must not read as "no reports to check".
[ -n "$REPORTS" ] || {
    echo "BROKEN the ledger names no standing report - $LEDGER"; exit 2; }

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
    trap 'rm -f "$st_dir/gh" "$st_dir/spike/upstream-report-status.sh" \
            "$st_dir/spike/check-upstream-ledger.sh" \
            "$st_dir/spike/upstream-reports.tsv" \
            "$st_dir/docs/target-classes.md"; \
          rmdir "$st_dir/spike" "$st_dir/docs" "$st_dir" 2>/dev/null' EXIT

    # $self and $LEDGER are resolved at the top of the file, before this block:
    # the short leg copies both, and the main path needs them anyway now that the
    # list is read rather than carried.
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

    # One unreadable report out of the standing set. This is the leg that pins the predicate:
    # all-BROKEN and all-readable are also satisfied by `broken == n`, so without a
    # mixed run the requirement being checked would be "every report failed" rather
    # than "any report failed".
    cat > "$st_dir/gh" <<'FAKE'
#!/bin/sh
case " $* " in
    *" 139 "*) exit 7 ;;   # aspiers/stow, one of the standing rows
    *) echo "OPEN 3 2026-01-01" ;;
esac
FAKE
    chmod +x "$st_dir/gh"
    leg 2 "mixed leg: one unreadable report out of $report_count must still not exit 0"
    leg_rows 1 '| BROKEN |' "mixed leg BROKEN rows"

    printf '#!/bin/sh\necho "OPEN 3 2026-01-01"\n' > "$st_dir/gh"
    chmod +x "$st_dir/gh"
    leg 0 "green leg: every report readable must exit 0"
    leg_rows "$report_count" '^| `' "green leg emitted rows"
    leg_rows 1 "read $report_count of $report_count standing reports" \
        "green leg names its own denominator"

    # The denominator has to come from the list, not from a number written beside
    # it (#297). Checked by running a COPY of this script with one report row
    # deleted: if the closing line still says the old count, the count is a
    # constant pretending to be a measurement.
    #
    # A copy rather than an env override: an override would be a surface that
    # exists only for the test, and the thing under test is what the committed
    # script does with the committed list.
    mkdir -p "$st_dir/spike" "$st_dir/docs" || {
        echo "== self-test FAILED: could not build the scratch tree"; exit 2; }
    short_self="$st_dir/spike/upstream-report-status.sh"
    cp "$self" "$short_self" || {
        echo "== self-test FAILED: could not copy this script"; exit 2; }
    # The checker and the table travel with the copy: this script refuses to
    # measure a ledger the checker rejects, so a row leaving the ledger has to
    # take its marker with it, exactly as a real removal would.
    cp "$CHECKER" "$st_dir/spike/check-upstream-ledger.sh" || {
        echo "== self-test FAILED: could not copy the ledger checker"; exit 2; }
    _tbl=$(dirname -- "$self")/../docs/target-classes.md
    # A tab-safe pattern: a literal tab in this source would be one editor away
    # from a space, and the row would then quietly fail to match.
    sed '/^topydo\/topydo[[:space:]]341[[:space:]]/d' "$LEDGER" \
        > "$st_dir/spike/upstream-reports.tsv" || {
        echo "== self-test FAILED: could not build the shortened ledger"; exit 2; }
    sed 's| <!-- upstream-report: topydo/topydo#341 -->||' "$_tbl" \
        > "$st_dir/docs/target-classes.md" || {
        echo "== self-test FAILED: could not build the matching table"; exit 2; }
    short_count=$((report_count - 1))
    if grep -q '^topydo/topydo[[:space:]]341[[:space:]]' \
            "$st_dir/spike/upstream-reports.tsv"; then
        echo "== self-test FAILED: the shortened ledger still carries the row it was meant to lose"
        exit 2
    fi
    echo "== short leg: one row fewer must change the denominator"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "== self-test FAILED: short leg exited $rc, wanted 0"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_rows "$short_count" '^| `' "short leg emitted rows"
    leg_rows 1 "read $short_count of $short_count standing reports" \
        "short leg denominator followed the ledger"
    leg_rows 0 "read $report_count of $report_count standing reports" \
        "short leg must not still claim the full count"

    # The ledger is read, so it can also be empty - and an empty one must not
    # read as "no reports to check". This leg did not exist while the list was a
    # literal in the source: deleting it there deleted the script's own syntax.
    # The checker is what refuses, which is the point: one implementation of the
    # ledger's contract, invoked here rather than restated.
    : > "$st_dir/spike/upstream-reports.tsv"
    echo "== empty-ledger leg: a ledger that parses to nothing must not exit 0"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "2" ]; then
        echo "== self-test FAILED: empty-ledger leg exited $rc, wanted 2"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_rows 1 'does not pass spike/check-upstream-ledger.sh' \
        "empty-ledger leg names the check that refused"

    # A status typo is #297's own shape one column to the right: the awk filter
    # selects standing rows, so a misspelling drops one and this table prints
    # "N of N" over the smaller N, exit 0. Five of six reads exactly like six of
    # six. Refusing the vocabulary is what stops it, and this leg is what stops
    # the refusal from being deleted.
    sed 's|^\(pimalaya/himalaya[[:space:]]738[[:space:]]\)standing|\1standng|' "$LEDGER" \
        > "$st_dir/spike/upstream-reports.tsv" || exit 2
    cp "$_tbl" "$st_dir/docs/target-classes.md" || exit 2
    grep -q 'standng' "$st_dir/spike/upstream-reports.tsv" || {
        echo "== self-test FAILED: the status typo was not planted"; exit 2; }
    echo "== status-typo leg: a misspelled status must not quietly shrink the table"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "2" ]; then
        echo "== self-test FAILED: status-typo leg exited $rc, wanted 2"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_rows 0 'standing reports in spike/upstream-reports.tsv' \
        "status-typo leg must not print a closing count at all"

    # A ledger the checker fully accepts can still name no standing report: every
    # row withdrawn. The checker has nothing to object to — the vocabulary is
    # legal and the markers match — so this is the one shape where the guard
    # below is the only thing standing between an empty table and "exit 0".
    # Found by mutation: without this leg, deleting that guard survives.
    sed 's|standing|withdrawn|' "$LEDGER" > "$st_dir/spike/upstream-reports.tsv" || exit 2
    cp "$_tbl" "$st_dir/docs/target-classes.md" || exit 2
    echo "== all-withdrawn leg: a ledger naming no standing report must not exit 0"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "2" ]; then
        echo "== self-test FAILED: all-withdrawn leg exited $rc, wanted 2"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_rows 1 'names no standing report' "all-withdrawn leg says what is missing"

    # An indented comment line carrying four tab-separated fields. `^#` and
    # `^[ \t]*#` disagree about exactly this line: one reads a comment, the other
    # a report. That disagreement is what produced "read 7 of 7" over six
    # standing reports while the checker said the records agreed — silent
    # over-counting, the mirror of the under-counting #297 was filed about. The
    # selection has one implementation now; this leg is what keeps it that way.
    cp "$LEDGER" "$st_dir/spike/upstream-reports.tsv" || exit 2
    cp "$_tbl" "$st_dir/docs/target-classes.md" || exit 2
    printf ' # example/indented\t1\tstanding\tnot a report\n' \
        >> "$st_dir/spike/upstream-reports.tsv"
    echo "== indented-comment leg: an indented comment row must not become a report"
    leg_out=$(PATH="$st_dir:$PATH" sh "$short_self" 2>&1)
    rc=$?
    if [ "$rc" != "0" ]; then
        echo "== self-test FAILED: indented-comment leg exited $rc, wanted 0"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_rows 1 "read $report_count of $report_count standing reports" \
        "indented-comment leg left the count where it was"
    leg_rows 0 'example/indented' "indented-comment leg did not emit the comment as a row"

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

# The denominator is named, and what it is relative to has changed (#297). It
# used to be "this list", a literal in this file that a filing could miss with
# nothing noticing. It is now the ledger, and the ledger is held to the markers
# in docs/target-classes.md by spike/check-upstream-ledger.sh in CI, in both
# directions - so a report recorded in one of the two and not the other is red
# before it can reach this table.
#
# The residue is stated rather than implied: a filing written into NEITHER record
# is outside what either can say. Nothing here reaches a tracker, and deriving
# the set from one was measured and rejected (see the header). That is a smaller
# hole than the one #297 opened on - forgetting one of two records is now loud -
# and it is not zero.
#
# $n rather than a constant: the count comes from the rows the loop actually
# walked, so a row that stops being walked changes the number. A literal here
# would agree with the ledger only until someone edited one of them.
if [ "$broken" -gt 0 ]; then
    echo
    echo "could not read $broken of $n standing reports - the rows above are incomplete"
    exit 2
fi
echo "read $n of $n standing reports in spike/upstream-reports.tsv"
echo "  (the ledger and the MARKERS in docs/target-classes.md are held to each other"
echo "   in CI - prose in that file naming a filing is not a marker and is not held"
echo "   to anything, so a row written like the others with no marker is invisible"
echo "   here, as is a filing in neither record - #297)"
exit 0
