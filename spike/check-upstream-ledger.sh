#!/bin/sh
# check-upstream-ledger.sh — the report ledger and the target table name the
# same filings, on the same rows, in both directions (#297).
#
# Why this exists: spike/upstream-report-status.sh carried a hand-written list
# of six reports, and a report filed without editing that list was invisible.
# The table looked whole, every row read fine, and the script exited 0 — six of
# six and six of seven print the same way. The cohort-4 close depended on
# remembering to add himalaya by hand (PR #253). Nothing asked.
#
# Contract, deliberately strict in both directions:
#   * every identifier in spike/upstream-reports.tsv is marked in
#     docs/target-classes.md as <!-- upstream-report: owner/repo#N -->
#   * every such marker names an identifier the ledger carries
#   * each marker sits on ITS tool's row: the second pipe-separated column of
#     the marked line must equal the ledger's finding column. A marker anywhere
#     in the file is not what the three documents describing this claim say
#   * the ledger parses as its own contract says: exactly four TAB-separated
#     fields, a status of standing or withdrawn, no identifier twice
#   * no identifier is marked twice. Only the last marker for an identifier
#     survives, so a stray copy on another row would be erased by the correct
#     one and the row rule above would pass straight over it
#   * the two are not BOTH empty. Two empty sets agree, and that agreement is
#     what a broken extractor also produces, so it is BROKEN rather than ok.
#     One side empty needs no rule of its own: containment refuses it as the
#     disagreement it is
#
# Every clause above is here because dropping it was silent. Three fields
# instead of four, or spaces where tabs belong, parsed to nothing and the row
# vanished from both scripts with no line of output. A status typo dropped a
# standing report and the status table still printed "N of N", exit 0 — the
# same sentence this project used to describe the defect it was fixing. And a
# marker on the wrong row satisfied a set comparison while making the documents
# that describe it false.
#
# WHAT THIS CANNOT SEE, said here rather than left to be discovered: a report
# filed without being written into EITHER record. Prose in docs/target-classes.md
# naming a filing does NOT count — only a marker does, so a row written the way
# the six existing ones are written, with no marker, is invisible here. The two
# records are held to each other; nothing reaches a tracker. Deriving the set
# from one was measured and rejected: a withdrawn report and an unlisted one
# have the same shape there, and the search is per-account, not per-project.
#
# The markers are also what separates our filings from issues merely cited in
# the same table. psf/black#2479, psf/black#5207 (a pull request, not even an
# issue) and rust-lang/rustfmt#6041 are other people's reports, named in the
# novelty rows. A rule matching the identifier shape alone collects all three —
# and, worse in the direction that matters, MISSES alecthomas/devtodo#9
# entirely, because the row recording that filing says only that the finding is
# kept unreported. Shape over-collects and under-collects at once; a marker is
# an assertion, which is why it is one.
#
# Usage:
#   sh spike/check-upstream-ledger.sh            # check
#   sh spike/check-upstream-ledger.sh --standing # the standing rows, checked first
#   sh spike/check-upstream-ledger.sh --selftest # falsify the checker
#
# Exit 0 the two directions hold, 1 they do not, 2 the check could not run.
# Never read a 2 as a pass — and a comparison that fails to run is a 2, not the
# agreement of two sets nobody managed to build.
set -u

# Readability first, PATH only as a fallback. `sh script.sh` from the directory
# holding it gives a $0 with no slash that opens perfectly well; resolving
# through PATH first turns that working form into a refusal whenever the
# script's directory is not on PATH (BUILDLOG 2026-08-25, the same mistake made
# once already in upstream-report-status.sh).
self=$0
[ -r "$self" ] || self=$(command -v -- "$self" 2>/dev/null) || self=""
[ -n "$self" ] && [ -r "$self" ] || {
    echo "BROKEN cannot read this script (\$0 = $0) - the root is resolved from it"
    exit 2; }
root=$(CDPATH= cd -- "$(dirname -- "$self")/.." 2>/dev/null && pwd) || root=""
[ -n "$root" ] || { echo "BROKEN cannot resolve the repository root from $self"; exit 2; }

LEDGER=$root/spike/upstream-reports.tsv
TABLE=$root/docs/target-classes.md

command -v awk >/dev/null 2>&1 ||
    { echo "BROKEN awk not found - the comparison cannot run"; exit 2; }

# One awk pass over both files rather than sort+comm over temporaries. A
# command substitution around `comm` discards its exit status, so a comparator
# that failed to run produced two empty difference lists and the script called
# that agreement — measured, exit 0 on a tree that genuinely disagreed. There
# is no comparator to fail now, no scratch file to leak, and awk's own exit
# status is this function's.
run_check() { # ledger table -> prints a verdict, returns 0/1/2
    _led=$1
    _tab=$2
    [ -r "$_led" ] || { echo "BROKEN cannot read the ledger: $_led"; return 2; }
    [ -r "$_tab" ] || { echo "BROKEN cannot read the target table: $_tab"; return 2; }

    # FILENAME rather than the usual NR == FNR two-file idiom: NR == FNR is true
    # for EVERY line of the second file when the first one is empty, because an
    # empty file advances neither counter. An empty ledger is a case this check
    # deliberately handles, so the idiom parses the target table as the ledger
    # and reports a hundred malformed rows — measured, by the empty leg below.
    awk -v LEDGERFILE="$_led" '
    FILENAME == LEDGERFILE {
        if ($0 ~ /^[ \t]*#/ || $0 ~ /^[ \t]*$/) next
        n = split($0, f, "\t")
        if (n != 4) {
            broken = broken sprintf("\n  ledger line %d: %d tab-separated field(s), want 4" \
                                    " - a row written with spaces is one field and would" \
                                    " otherwise vanish from both records in silence", FNR, n)
            next
        }
        id = f[1] "#" f[2]
        if (f[3] != "standing" && f[3] != "withdrawn")
            broken = broken sprintf("\n  ledger line %d: status \"%s\" is neither standing" \
                                    " nor withdrawn - the status script measures standing" \
                                    " rows only, so a typo here drops a report quietly",
                                    FNR, f[3])
        if (id in led)
            broken = broken sprintf("\n  ledger line %d: %s is listed twice", FNR, id)
        led[id] = f[4]
        ledn++
        next
    }
    {
        rest = $0
        nf = split($0, col, "|")
        tool = (nf >= 3) ? col[3] : "(not a table row)"
        gsub(/^[ \t]+/, "", tool)
        gsub(/[ \t]+$/, "", tool)
        while (match(rest, /<!-- upstream-report: [^ ]+ -->/) > 0) {
            m = substr(rest, RSTART, RLENGTH)
            rest = substr(rest, RSTART + RLENGTH)
            id = m
            sub(/^<!-- upstream-report: /, "", id)
            sub(/ -->$/, "", id)
            if (id in mark)
                broken = broken sprintf("\n  table line %d: %s is marked more than once",
                                        FNR, id)
            mark[id] = tool
            markn++
        }
    }
    END {
        if (broken != "") {
            printf "BROKEN the records do not parse the way their contract describes:%s\n", broken
            exit 2
        }
        if (ledn == 0 && markn == 0) {
            print "BROKEN both records are empty - an empty ledger and an empty table"
            print "       agree, and that agreement is not a measurement"
            exit 2
        }
        for (id in led) {
            if (!(id in mark))
                bad = bad sprintf("\n  in the ledger, no marker in the table: %s", id)
            else if (mark[id] != led[id])
                bad = bad sprintf("\n  %s is marked on row \"%s\", the ledger files it under \"%s\"",
                                  id, mark[id], led[id])
        }
        for (id in mark)
            if (!(id in led))
                bad = bad sprintf("\n  marked in the table, not in the ledger: %s", id)
        if (bad != "") {
            printf "REFUSE the ledger and the target table disagree:%s\n", bad
            printf "  ledger %d, markers %d\n", ledn, markn
            exit 1
        }
        printf "ok: %d filings, ledger and table agree in both directions\n", ledn
        print "    (this pair, not every report ever filed - prose naming a filing is not"
        print "     enough, only a marker is, and a filing in neither record is outside"
        print "     what these two can say - #297)"
        exit 0
    }
    ' "$_led" "$_tab"

    _rc=$?
    case "$_rc" in
        0|1|2) return "$_rc" ;;
        *) echo "BROKEN the comparison itself exited $_rc - that is not a verdict"; return 2 ;;
    esac
}

# The standing subset, for the one consumer that needs it. It lives here rather
# than in upstream-report-status.sh so that the rules deciding which rows count —
# what a comment looks like, how many fields a row must have, which status is
# measurable — have a single implementation. A second copy drifted inside one
# review round: the status script spelled a comment `^#` while this file spelled
# it `^[ \t]*#`, so an indented comment line carrying four fields was a comment
# to one reader and data to the other, and the table printed "read 7 of 7" over
# six standing reports. Exporting the subset removes the second reader rather
# than asking it to stay in step.
if [ "${1:-}" = "--standing" ]; then
    _v=$(run_check "$LEDGER" "$TABLE"); _vrc=$?
    [ "$_vrc" -eq 0 ] || { printf '%s\n' "$_v" >&2; exit "$_vrc"; }
    awk -F'\t' '!/^[ \t]*#/ && !/^[ \t]*$/ && NF == 4 && $3 == "standing" { print $1 " " $2 }' \
        "$LEDGER"
    exit 0
fi

if [ "${1:-}" = "--selftest" ]; then
    st=$(mktemp -d "${TMPDIR:-/tmp}/upstream-ledger-selftest-XXXXXX") || {
        echo "== self-test FAILED: could not make a scratch dir"; exit 2; }
    # Named removal rather than rm -rf: this tree holds exactly the files put
    # here, so deleting them by name cannot take anything else with it, and it
    # does not trip the recursive-delete guards some developers run locally.
    trap 'rm -f "$st/spike/check-upstream-ledger.sh" "$st/spike/upstream-reports.tsv" \
            "$st/docs/target-classes.md" "$st/bin/awk"; \
          rmdir "$st/spike" "$st/docs" "$st/bin" "$st" 2>/dev/null' EXIT
    mkdir -p "$st/spike" "$st/docs" "$st/bin" || {
        echo "== self-test FAILED: could not build the scratch tree"; exit 2; }

    # A copy of the whole layout rather than an env override: an override would
    # be a surface that exists only for the test, and what is under test is what
    # the committed script does with committed files. The copy keeps the
    # spike/../docs shape, so $0 resolution is exercised as well.
    cp "$self" "$st/spike/check-upstream-ledger.sh" || {
        echo "== self-test FAILED: could not copy the checker"; exit 2; }
    copy=$st/spike/check-upstream-ledger.sh

    leg() { # want_rc label
        echo "== $2"
        leg_out=$(sh "$copy" 2>&1)
        rc=$?
        [ "$rc" = "$1" ] && return 0
        echo "== self-test FAILED: $2 - exited $rc, wanted $1"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    }

    leg_says() { # pattern what
        printf '%s' "$leg_out" | grep -q "$1" && return 0
        echo "== self-test FAILED: $2 - the output does not name it"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    }

    reset_pair() {
        cp "$LEDGER" "$st/spike/upstream-reports.tsv" &&
        cp "$TABLE" "$st/docs/target-classes.md"
    }

    # Green first: if the committed pair does not agree, every red leg below
    # would be red for the wrong reason.
    reset_pair || exit 2
    leg 0 "green leg: the committed pair agrees in both directions"
    leg_says 'agree in both directions' "green leg names the agreement"

    # 1. A marker goes missing. This is the recorded accident's shape.
    reset_pair || exit 2
    sed 's| <!-- upstream-report: lfos/calcurse#529 -->||' "$TABLE" \
        > "$st/docs/target-classes.md" || exit 2
    grep -q 'upstream-report: lfos/calcurse#529' "$st/docs/target-classes.md" && {
        echo "== self-test FAILED: the edited table still carries the marker"; exit 2; }
    leg 1 "ledger-only leg: a ledger row whose marker was removed must refuse"
    leg_says 'lfos/calcurse#529' "ledger-only leg names the identifier"
    leg_says 'no marker in the table' "ledger-only leg names which side is missing"

    # 2. THE OTHER DIRECTION, and it must be the other branch. Deleting a
    # ledger row while its marker stays is the only shape that exercises
    # "marked in the table, not in the ledger" — appending a ledger row does
    # not: that lands in the same branch as leg 1. Without this leg the reverse
    # containment can be deleted outright and the selftest stays green while
    # printing "agree in both directions" (measured).
    reset_pair || exit 2
    sed '/^lfos\/calcurse[[:space:]]529[[:space:]]/d' "$LEDGER" \
        > "$st/spike/upstream-reports.tsv" || exit 2
    grep -q '^lfos/calcurse[[:space:]]529[[:space:]]' "$st/spike/upstream-reports.tsv" && {
        echo "== self-test FAILED: the shortened ledger still carries the row"; exit 2; }
    leg 1 "table-only leg: a marker with no ledger row must refuse the other way"
    leg_says 'marked in the table, not in the ledger' "table-only leg takes the other branch"
    leg_says 'lfos/calcurse#529' "table-only leg names the identifier"

    # 3. The marker sits on the wrong row. A set comparison passes this while
    # every document describing the claim says "on its row".
    reset_pair || exit 2
    # Move calcurse's marker onto the timewarrior row: drop it where it belongs
    # and append it where it does not. The identifier set is unchanged, which is
    # exactly why a set comparison passes this.
    sed 's| <!-- upstream-report: lfos/calcurse#529 -->||' "$TABLE" \
        | sed 's|<!-- upstream-report: GothenburgBitFactory/timewarrior#778 -->|& <!-- upstream-report: lfos/calcurse#529 -->|' \
        > "$st/docs/target-classes.md" || exit 2
    leg 1 "wrong-row leg: a marker on another tool's row must refuse"
    leg_says 'is marked on row' "wrong-row leg says the row is wrong"
    leg_says 'lfos/calcurse#529' "wrong-row leg names the identifier"

    # 3b. The same identifier marked on TWO rows, the correct one last. The
    # wrong-row leg above cannot see this: it MOVES a marker, leaving one copy,
    # while this COPIES it. `mark[id]` is overwritten by whichever marked row
    # comes last, so with the duplicate check removed the stray marker on
    # another tool's row is erased by the correct one and the run reads
    # `ok ... agree in both directions`. Found by review, mutating the branch
    # this leg now covers.
    reset_pair || exit 2
    sed 's|<!-- upstream-report: GothenburgBitFactory/timewarrior#778 -->|& <!-- upstream-report: lfos/calcurse#529 -->|' \
        "$TABLE" > "$st/docs/target-classes.md" || exit 2
    [ "$(grep -c 'upstream-report: lfos/calcurse#529' "$st/docs/target-classes.md")" = "2" ] || {
        echo "== self-test FAILED: the duplicate marker was not planted twice"; exit 2; }
    leg 2 "duplicate-marker leg: one identifier marked on two rows is BROKEN"
    leg_says 'marked more than once' "duplicate-marker leg says what is wrong"
    leg_says 'lfos/calcurse#529' "duplicate-marker leg names the identifier"

    # 4. A status typo. This is #297's own shape one column to the right: the
    # status script measures standing rows, so a misspelling drops a report and
    # the table prints "N of N" over the smaller N, exit 0.
    reset_pair || exit 2
    sed 's|^\(pimalaya/himalaya[[:space:]]738[[:space:]]\)standing|\1standng|' "$LEDGER" \
        > "$st/spike/upstream-reports.tsv" || exit 2
    grep -q 'standng' "$st/spike/upstream-reports.tsv" || {
        echo "== self-test FAILED: the typo was not planted"; exit 2; }
    leg 2 "status leg: a status outside the vocabulary is BROKEN, not a filter"
    leg_says 'standng' "status leg quotes the bad value"

    # 5. A row that is not four tab-separated fields. Both scripts skipped such
    # a row in silence, so a filing written with spaces was recorded nowhere
    # while its author believed otherwise.
    reset_pair || exit 2
    printf 'example/spaces 5 standing spaces\n' >> "$st/spike/upstream-reports.tsv"
    leg 2 "field-count leg: a space-written row is BROKEN, not skipped"
    leg_says 'want 4' "field-count leg says what it wanted"

    # 6. The same identifier twice.
    reset_pair || exit 2
    printf 'topydo/topydo\t341\tstanding\ttopydo\n' >> "$st/spike/upstream-reports.tsv"
    leg 2 "duplicate leg: an identifier listed twice is BROKEN"
    leg_says 'listed twice' "duplicate leg says what is wrong"

    # 7. Both empty. Two empty sets agree, and a broken extractor produces
    # exactly that, so agreement here must not be a pass.
    reset_pair || exit 2
    : > "$st/spike/upstream-reports.tsv"
    sed 's| <!-- upstream-report: [^ ]* -->||g' "$TABLE" \
        > "$st/docs/target-classes.md" || exit 2
    leg 2 "empty leg: two empty records agree, and that is BROKEN not ok"
    leg_says 'not a measurement' "empty leg says why agreement is not enough"

    # 8. The comparison itself fails to run. A `comm` in a command substitution
    # returned two empty lists and the script called it agreement (measured,
    # exit 0 on a disagreeing tree). awk's status is read now, and anything
    # outside 0/1/2 is BROKEN rather than a verdict.
    reset_pair || exit 2
    printf '#!/bin/sh\nexit 7\n' > "$st/bin/awk"
    chmod +x "$st/bin/awk"
    echo "== comparator leg: a comparison that cannot run must not read as agreement"
    leg_out=$(PATH="$st/bin:$PATH" sh "$copy" 2>&1)
    rc=$?
    rm -f "$st/bin/awk"
    if [ "$rc" != "2" ]; then
        echo "== self-test FAILED: comparator leg exited $rc, wanted 2"
        printf '%s\n' "$leg_out" | sed 's/^/     | /'
        exit 2
    fi
    leg_says 'not a verdict' "comparator leg says the exit is not a verdict"

    echo "== self-test ok"
    exit 0
fi

run_check "$LEDGER" "$TABLE"
exit $?
