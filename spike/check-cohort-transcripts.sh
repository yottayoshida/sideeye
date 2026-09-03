#!/bin/sh
# CI entry point for the cohorts' probe transcripts (#259): every committed probe
# transcript for which a cohort declares a verdict set is re-verified against that
# set, with the checker the cohort itself sealed or, from cohort 5 on, with the
# shared spike/lib/check-transcript.sh reading the cohort's manifest.
#
# Why it exists: cohort 4 wrote check-transcript.sh after a truncated probe script
# reported "conditions failed: 0" with one condition never judged, and capture.sh
# runs it once, at capture time. Nothing ran it again. A transcript that was edited,
# or a checker whose expected sets drifted from what the probes emit, would go
# unnoticed until the next cohort read the record. This walks the records on every
# push, the way check-sealed-campaigns.sh walks the campaigns.
#
# Contract, strict in both directions, in the shape of that precedent:
#
#   * cohort 4 is SEALED. Its probes/ directory takes no new files, so the
#     (target, mode, transcript) triples its checker declares sets for — four of
#     the eight transcripts — and the names of all eight `*.txt` transcripts are
#     held HERE, not there. Transcripts are what this walker watches; a script or
#     a page added to that directory is the sealing rule's business, not this one's.
#     The other four (drills, drills-under-image, positive-control,
#     unison-clock-diagnosis) carry no verdict set: the checker would report a
#     false MANIFEST FAIL (three are non-empty) or BROKEN (one has no verdicts),
#     so they are listed as known and left alone. If the set of files changes in
#     either direction this fails: a record that grew a transcript nobody declared
#     a set for, or lost one, is the drift this walker is for.
#   * a cohort directory with probes/verdicts.tsv (cohort 5 onward) is walked from
#     that manifest: each row names target, mode, the transcript file and the set,
#     and spike/lib/check-transcript.sh judges it. A manifest row whose transcript
#     is missing fails, and so does a transcript (probes/*.txt) no row declares —
#     the same two directions the sealed cohort gets, so a record cannot grow a
#     transcript nobody holds to a set.
#   * walking nothing is a failure, not a pass. Today the count is one (cohort 4);
#     counting only manifest cohorts would be a permanent red until cohort 5 exists,
#     so the sealed cohort's hand-held triples count as walked.
#
# `sh spike/check-cohort-transcripts.sh --selftest` proves the reds: on a copy of the
# repository's cohort-4 record it cuts one transcript short, removes one, and adds a
# cohort-5-shaped record with an undeclared transcript, and requires the walker to fail
# each with the line that names it. Acceptance check 11e runs it; CI runs it beside the
# walk itself.
set -u

if [ "${1-}" = "--selftest" ]; then
    self=$(cd "$(dirname "$0")" && pwd)/check-cohort-transcripts.sh
    src=$(cd "$(dirname "$0")/.." && pwd)
    fails=0
    R=$(mktemp -d "${TMPDIR:-/tmp}/cohort-walker-selftest-XXXXXX") || { echo "BROKEN selftest: no work directory"; exit 2; }
    mkdir -p "$R/spike/cohort4/probes" "$R/spike/lib"
    cp "$src"/spike/cohort4/probes/*.txt "$src/spike/cohort4/probes/check-transcript.sh" "$R/spike/cohort4/probes/"
    cp "$src/spike/lib/check-transcript.sh" "$R/spike/lib/"
    expect() { # label want-rc must-contain
        _e_out=$(sh "$self" "$R" 2>&1); _e_rc=$?
        if [ "$_e_rc" -eq "$2" ] && printf '%s\n' "$_e_out" | grep -qF -- "$3"; then
            echo "ok   walker selftest: $1"
        else
            echo "FAIL walker selftest: $1 — rc=$_e_rc (wanted $2), looked for [$3]"
            printf '%s\n' "$_e_out" | grep '^FAIL' | head -3 | sed 's/^/     | /'
            fails=$((fails + 1))
        fi
    }
    expect "a faithful copy of the record is green" 0 "transcripts verified: 4, failures: 0"
    # Cut after the third verdict line, so the instrument control (zero verdicts) does not
    # fire and the red has to come from the set difference — the accident's own shape.
    cut_at=$(awk '($1=="ok"||$1=="FAIL") && $2 ~ /:$/ { n++; if (n == 3) { print NR; exit } }' "$src/spike/cohort4/probes/unison.txt")
    head -n "${cut_at:-20}" "$src/spike/cohort4/probes/unison.txt" > "$R/spike/cohort4/probes/unison.txt"
    expect "a transcript cut short fails on the set, not on the zero-verdict control" 1 "MISSING:"
    cp "$src/spike/cohort4/probes/unison.txt" "$R/spike/cohort4/probes/unison.txt"
    rm -f "$R/spike/cohort4/probes/drills.txt"
    expect "a missing transcript fails on the set" 1 "FAIL  cohort4: held transcript drills.txt is missing"
    cp "$src/spike/cohort4/probes/drills.txt" "$R/spike/cohort4/probes/drills.txt"
    mkdir -p "$R/spike/cohort5/probes"
    cp "$src/spike/cohort4/probes/unison-bare.txt" "$R/spike/cohort5/probes/unison-bare.txt"
    printf 'unison\tbare\tunison-bare.txt\t%s\n' "1-exit-codes 2-non-noop 3-artifacts 4-round-trip 5-determinism-falsification 6-closure 8-visibility-falsification" > "$R/spike/cohort5/probes/verdicts.tsv"
    expect "a manifest cohort with a declared transcript is green" 0 "transcripts verified: 5, failures: 0"
    cp "$src/spike/cohort4/probes/unison.txt" "$R/spike/cohort5/probes/stray.txt"
    expect "a transcript no manifest row declares fails" 1 "FAIL  cohort5: transcript stray.txt has no manifest row"
    rm -f "$R/spike/cohort5/probes/stray.txt"
    printf 'unison\tapparatus\tunison.txt\t1-exit-codes\n' >> "$R/spike/cohort5/probes/verdicts.tsv"
    expect "a manifest row whose transcript is missing fails" 1 "FAIL  cohort5: manifest names unison.txt for unison/apparatus but the transcript is not there"
    rm -f "$R"/spike/cohort5/probes/* "$R"/spike/cohort4/probes/* "$R"/spike/lib/*
    rmdir "$R/spike/cohort5/probes" "$R/spike/cohort5" "$R/spike/cohort4/probes" "$R/spike/cohort4" "$R/spike/lib" "$R/spike" "$R" 2>/dev/null
    echo "== walker selftest failures: $fails"
    [ "$fails" -eq 0 ] || exit 1
    exit 0
fi

root=${1:-$(cd "$(dirname "$0")/.." && pwd)}

fails=0
walked=0
verified=0

# verify LABEL CMD... — run the checker once, keep its output, report either way. The
# output shown on a red is the output of the run that produced the red.
verify() {
    _v_label=$1; shift
    if _v_out=$("$@" 2>&1); then
        echo "ok    $_v_label"
        verified=$((verified + 1))
    else
        _v_rc=$?
        echo "FAIL  $_v_label (rc=$_v_rc)"
        printf '%s\n' "$_v_out" | sed 's/^/      | /'
        fails=$((fails + 1))
    fi
}

# ---- cohort 4: sealed checker, triples and file set held here ---------------------
c4="$root/spike/cohort4/probes"
c4_files="drills-under-image.txt drills.txt himalaya-bare.txt himalaya.txt positive-control.txt unison-bare.txt unison-clock-diagnosis.txt unison.txt"
c4_triples="himalaya:bare:himalaya-bare.txt himalaya:apparatus:himalaya.txt unison:bare:unison-bare.txt unison:apparatus:unison.txt"

if [ -d "$c4" ]; then
    walked=$((walked + 1))
    # A set comparison, not a string one: glob order follows the locale's collation
    # (en_US.UTF-8 and C sort `drills-under-image.txt` against `drills.txt` differently —
    # the trap spike/cohort4/Dockerfile already pays for), so each held name is looked up
    # and the count is compared, in whatever order the directory lists them.
    # Every held name is present, and every present transcript is held: two directions,
    # and between them the whole set — a count would be derivable from the two and could
    # only ever fail alongside one of them.
    set_drift=0
    for name in $c4_files; do
        [ -f "$c4/$name" ] || { echo "FAIL  cohort4: held transcript $name is missing"; set_drift=1; }
    done
    for f in "$c4"/*.txt; do
        [ -f "$f" ] || continue
        base=${f##*/}
        case " $c4_files " in *" $base "*) ;; *) echo "FAIL  cohort4: transcript $base is not one this walker holds"; set_drift=1 ;; esac
    done
    if [ "$set_drift" = 0 ]; then
        echo "ok    cohort4: the eight sealed transcripts are the eight this walker knows"
    else
        echo "FAIL  cohort4: the sealed transcript set changed (held: $c4_files)"
        fails=$((fails + 1))
    fi

    if [ ! -x "$c4/check-transcript.sh" ]; then
        echo "FAIL  cohort4: probes/check-transcript.sh is missing or not executable"
        fails=$((fails + 1))
    else
        for triple in $c4_triples; do
            target=${triple%%:*}; rest=${triple#*:}; mode=${rest%%:*}; file=${rest#*:}
            # `sh file`, the way capture.sh and check-sealed-campaigns.sh invoke sealed
            # checkers; -x was checked above so the record's mode is also held.
            verify "cohort4: $file against the sealed set for $target/$mode" \
                sh "$c4/check-transcript.sh" "$target" "$mode" "$c4/$file"
        done
    fi
else
    echo "FAIL  cohort4: $c4 not found — the sealed record this walker holds triples for is gone"
    fails=$((fails + 1))
fi

# ---- cohort 5 onward: manifests --------------------------------------------------
for mf in "$root"/spike/cohort*/probes/verdicts.tsv; do
    [ -f "$mf" ] || continue
    probes=$(dirname "$mf")
    name=$(basename "$(dirname "$probes")")
    walked=$((walked + 1))
    rows=0
    # Rows: target<TAB>mode<TAB>transcript-file<TAB>space-separated names — the one
    # format, listed by the shared checker's own reader (`--list-rows`, unit-separated
    # columns: a non-blank IFS character is never collapsed, so an empty column stays
    # one) and judged by the same checker from the same file, so its duplicate-row and
    # missing-row refusals are on this path too. The loop reads a here-doc so it runs in
    # this shell and a final line without a newline is still a row.
    us=$(printf '\037')
    declared=" "
    while IFS="$us" read -r row target mode file; do
        [ -n "$row" ] || continue
        rows=$((rows + 1))
        if [ -z "$target" ] || [ -z "$mode" ] || [ -z "$file" ]; then
            echo "FAIL  $name: manifest row $row has an empty column"
            fails=$((fails + 1)); continue
        fi
        declared="$declared$file "
        if [ ! -f "$probes/$file" ]; then
            echo "FAIL  $name: manifest names $file for $target/$mode but the transcript is not there"
            fails=$((fails + 1)); continue
        fi
        verify "$name: $file against its manifest row for $target/$mode" \
            sh "$root/spike/lib/check-transcript.sh" "$mf" "$target" "$mode" "$probes/$file"
    done <<EOF
$(sh "$root/spike/lib/check-transcript.sh" --list-rows "$mf")
EOF
    [ "$rows" -gt 0 ] || { echo "FAIL  $name: probes/verdicts.tsv has no rows"; fails=$((fails + 1)); }
    # The other direction: every transcript in the record has a row. A cohort that
    # captures a probe and forgets its row would otherwise be a record nobody holds.
    for f in "$probes"/*.txt; do
        [ -f "$f" ] || continue
        base=${f##*/}
        case "$declared" in *" $base "*) ;; *) echo "FAIL  $name: transcript $base has no manifest row"; fails=$((fails + 1)) ;; esac
    done
done

if [ "$walked" = 0 ]; then
    echo "FAIL  no cohort record was walked under $root/spike/ — this check could not look" >&2
    exit 1
fi

echo ""
echo "cohorts walked: $walked, transcripts verified: $verified, failures: $fails"
[ "$fails" = 0 ]
