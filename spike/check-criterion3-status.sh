#!/bin/sh
# CI entry point for criterion 3's status, which three documents carry (#356).
#
# Why this exists: `PRD.md`, `DESIGN.md` §18 and `docs/kill-criteria-review.md` each
# record v1.0 entry criterion 3's status as dated paragraphs that are appended and never
# rewritten. Nothing compared them, and the only thing that would notice two of them
# asserting different states of the same release gate was a reader who opened all three.
# During #240 a correction to the review page was silently reverted by a restore from an
# older copy while BUILDLOG still claimed it; an external reviewer found it, not a check.
#
# The three documents already say who carries what — the review page: "`PRD.md` carries
# the criterion's status line"; DESIGN §18: "`PRD.md` carries the criterion's status";
# PRD: "the binding definition lives in `DESIGN.md` §18". This check makes that split
# machine-readable with three kinds of HTML-comment marker, each alone on a line:
#
#   <!-- criterion-3-current: YYYY-MM-DD STATE -->    PRD.md, exactly one — the status
#   <!-- criterion-3-state: YYYY-MM-DD STATE -->      docs/kill-criteria-review.md, one per
#                                                     dated section, in file order — the events
#   <!-- criterion-3-status: PRD.md -->               DESIGN.md — a pointer, nothing more
#
# Contract:
#
#   * PRD.md carries exactly one `current` marker and no `state` marker. The review page
#     carries at least one `state` marker and no `current`. DESIGN.md carries exactly one
#     `status: PRD.md` pointer and no `current`. STATE is `met` or `reopened`; anything
#     else is a FAILURE, not an ignored line — an unknown value would otherwise leave an
#     older `met` reading as the latest.
#   * PRD's `current` equals the review page's LAST `state` marker, date and state both.
#     File order is the timeline (a dated paragraph is appended, never rewritten, so a new
#     marker goes after the last), which also settles two markers on one day.
#   * The review page's `state` markers equal the pinned history below, in full — count
#     included. A new adjudication therefore touches three files in one pull request:
#     the marker, PRD's `current`, and the pin here. That is deliberate: a marker deleted
#     from the end with PRD moved back to match would otherwise pass, and a pull request
#     that records a state change without extending the pin is a pull request that did
#     not mean to.
#   * Every H2 section of the review page after `## The verdict` whose heading carries a
#     date `(YYYY-MM-DD` holds exactly one `state` marker — so a new dated section written
#     without its marker goes red, which is the commonest way the two files would drift.
#     Undated H2s and H3s are not subject.
#   * A marker is counted only at column 1, outside fenced code, ending the line: a
#     marker quoted in prose, indented (a Markdown code block), inside a fence or
#     followed by trailing text is not a marker. The counts are printed on success so a
#     run that read nothing cannot pass as a run that agreed.
#
# What this does NOT hold: the prose beside the markers. A section re-scored in words
# with its marker left alone, or PRD's bold status line edited under an unchanged
# marker, is green here and is held by review, the way the figures on the review page
# are (ADR 0039).
#
# The pinned history is a transcription, correct when written and held by nothing but
# this file: extend it in the same pull request that appends a marker.
#
# Sunset: delete this check if PRD's `current` marker is ever generated from the review
# page (then the two are one), or if the review page stops carrying dated state markers.
#
# Usage:
#   sh spike/check-criterion3-status.sh [<repo-root>]
#   sh spike/check-criterion3-status.sh --selftest

set -u

PIN='2026-08-16 met
2026-08-26 reopened
2026-08-27 met'
KNOWN_STATES='met reopened'

# Every marker of kind $2 in file $1, one per line, as its payload. `current` and `state`
# take two words (DATE STATE) and `status` one (the pointer target) — the shapes are not
# interchangeable: an optional second word would let `<!-- criterion-3-state: 2026-09-03 -->`
# count as a state marker with no state, which the vocabulary check then reads as known
# because its second field is empty (review). Column 1, outside fenced code, whole line.
# CRs are stripped first: a CRLF file would otherwise hide the closing `-->` behind an
# invisible character.
markers() {
    tr -d '\r' < "$1" | awk -v kind="$2" '
        /^```/ { fence = !fence; next }
        fence { next }
        {
            words = (kind == "status") ? "[^ ]+" : "[^ ]+ [^ ]+"
            if (match($0, "^<!-- criterion-3-" kind ": " words " -->$")) {
                s = $0
                sub("^<!-- criterion-3-" kind ": ", "", s)
                sub(" -->$", "", s)
                print s
            }
        }'
}

# For the review page: "DATE|COUNT" per H2 after "## The verdict" whose heading carries a
# date, COUNT being the state markers inside that section (up to the next H2).
dated_sections() {
    tr -d '\r' < "$1" | awk '
        /^```/ { fence = !fence; next }
        fence { next }
        /^## / {
            if (started && dated) print name "|" count
            dated = 0; count = 0
            if ($0 ~ /^## The verdict/) { started = 1; next }
            if (started && match($0, /\(20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
                dated = 1
                name = substr($0, RSTART + 1, 10)
            }
            next
        }
        /^<!-- criterion-3-state: [^ ]+ [^ ]+ -->$/ { if (dated) count++ }
        END { if (started && dated) print name "|" count }'
}

count_lines() { printf '%s\n' "$1" | grep -c . || true; }

# 0 when every "DATE STATE" line in $1 has a known state; prints the offenders. Every line
# reaching here has two fields — `markers` requires them for `current` and `state`, which
# is what keeps a stateless marker from arriving as an empty offender the command
# substitution would swallow into "no offenders". The match is anchored: `-v` alone accepts
# `unmet`, which contains a known state as a substring.
states_known() {
    _unknown=$(printf '%s\n' "$1" | grep . | awk '{print $2}' |
        grep -vx -e met -e reopened || true)
    [ -z "$_unknown" ] && return 0
    printf '%s\n' "$_unknown"
    return 1
}

check_root() {
    _root=$1
    _quiet=${2:-}
    _prd="$_root/PRD.md"
    _rev="$_root/docs/kill-criteria-review.md"
    _des="$_root/DESIGN.md"
    _bad=0

    for _f in "$_prd" "$_rev" "$_des"; do
        if [ ! -f "$_f" ]; then
            printf 'FAIL  missing: %s — this check could not look\n' "$_f" >&2
            return 1
        fi
    done

    _cur=$(markers "$_prd" current)
    _n_cur=$(count_lines "$_cur")
    if [ "$_n_cur" -eq 0 ]; then
        printf 'FAIL  PRD.md has no current-status marker (no current); expected one `<!-- criterion-3-current: YYYY-MM-DD STATE -->` beside the status line\n' >&2
        _bad=$((_bad + 1))
    elif [ "$_n_cur" -gt 1 ]; then
        printf 'FAIL  PRD.md carries more than one current-status marker (%s); the current status has one line\n' "$_n_cur" >&2
        _bad=$((_bad + 1))
    fi
    if [ "$(count_lines "$(markers "$_prd" state)")" -gt 0 ]; then
        printf 'FAIL  PRD.md carries a state marker; the dated history lives on docs/kill-criteria-review.md, PRD.md carries the current status only\n' >&2
        _bad=$((_bad + 1))
    fi

    _states=$(markers "$_rev" state)
    _n_states=$(count_lines "$_states")
    if [ "$_n_states" -eq 0 ]; then
        printf 'FAIL  docs/kill-criteria-review.md has no state marker (no state)\n' >&2
        _bad=$((_bad + 1))
    fi
    if [ "$(count_lines "$(markers "$_rev" current)")" -gt 0 ]; then
        printf 'FAIL  docs/kill-criteria-review.md claims a current status; only PRD.md carries one\n' >&2
        _bad=$((_bad + 1))
    fi

    _offenders=$(states_known "$(printf '%s\n%s\n' "$_cur" "$_states")") || {
        printf 'FAIL  unknown state `%s`; known states: %s (a new state is added to this check, not written around it)\n' \
            "$(printf '%s' "$_offenders" | tr '\n' ' ')" "$(echo "$KNOWN_STATES" | tr ' ' '/')" >&2
        _bad=$((_bad + 1))
    }

    if [ "$_states" != "$PIN" ]; then
        printf 'FAIL  history: the review page'"'"'s state markers do not equal the pinned history in spike/check-criterion3-status.sh (extend the pin in the same pull request that appends a marker; a marker deleted, inserted, reordered or added without the pin is red here)\n' >&2
        printf '      pinned:  %s\n' "$(printf '%s' "$PIN" | tr '\n' ';')" >&2
        printf '      on page: %s\n' "$(printf '%s' "$_states" | tr '\n' ';')" >&2
        _bad=$((_bad + 1))
    fi

    _last=$(printf '%s\n' "$_states" | grep . | tail -n 1)
    if [ "$_n_cur" -eq 1 ] && [ -n "$_last" ] && [ "$_cur" != "$_last" ]; then
        printf 'FAIL  current disagrees with the last state marker: PRD.md says `%s`, docs/kill-criteria-review.md ends with `%s`\n' "$_cur" "$_last" >&2
        _bad=$((_bad + 1))
    fi

    # The whole payload, compared: `-z` would accept a pointer at another file, and a
    # second pointer makes this a two-line string that no single target equals (review).
    _ptr=$(markers "$_des" status)
    if [ "$_ptr" != "PRD.md" ]; then
        printf 'FAIL  DESIGN.md has no pointer (no pointer); expected exactly one `<!-- criterion-3-status: PRD.md -->` in §18, found: %s\n' "$(printf '%s' "$_ptr" | tr '\n' ';')" >&2
        _bad=$((_bad + 1))
    fi
    if [ "$(count_lines "$(markers "$_des" current)")" -gt 0 ]; then
        printf 'FAIL  DESIGN.md claims a current status; only PRD.md carries one\n' >&2
        _bad=$((_bad + 1))
    fi

    _sections=$(dated_sections "$_rev")
    _n_sections=$(count_lines "$_sections")
    for _s in $_sections; do
        _date=${_s%%|*}
        _count=${_s##*|}
        if [ "$_count" != "1" ]; then
            printf 'FAIL  dated section (%s) without exactly one state marker: it carries %s (a dated section records a state; write the marker after the paragraph that states it)\n' "$_date" "$_count" >&2
            _bad=$((_bad + 1))
        fi
    done

    [ "$_bad" -gt 0 ] && return 1

    [ -n "$_quiet" ] || printf 'ok   criterion 3 status: PRD.md current `%s` = the last of %s state marker(s) on docs/kill-criteria-review.md; DESIGN.md points at PRD.md; %s dated section(s) each carry one marker\n' \
        "$_cur" "$_n_states" "$_n_sections"
    return 0
}

# --- selftest -----------------------------------------------------------------------
# Copies of the three real files are mutated in scratch; the real files are never touched
# (this repository has a recorded accident of a restore from an older copy erasing an
# edit — BUILDLOG 2026-08-26). Each red case is asserted on its own diagnostic, not on the
# exit code alone: a copy that fails for an unrelated reason is a hollow red.

_scratch=
fresh() {
    # A clean copy of the three files under $_scratch/root, the real files untouched.
    rm -f "$_scratch/root/PRD.md" "$_scratch/root/DESIGN.md" "$_scratch/root/docs/kill-criteria-review.md"
    mkdir -p "$_scratch/root/docs"
    cp "$REPO/PRD.md" "$_scratch/root/PRD.md"
    cp "$REPO/DESIGN.md" "$_scratch/root/DESIGN.md"
    cp "$REPO/docs/kill-criteria-review.md" "$_scratch/root/docs/kill-criteria-review.md"
}
# sed in place without -i (not POSIX): $1 file, $2 sed program
edit() {
    sed "$2" "$1" > "$1.new" && mv "$1.new" "$1"
}
append() { printf '%s\n' "$2" >> "$1"; }

_st_rc=0
_reds=0
_greens=0
expect_red() {
    # $1 name, $2 diagnostic substring
    _reds=$((_reds + 1))
    _err=$(check_root "$_scratch/root" quiet 2>&1 >/dev/null); _rc=$?
    if [ "$_rc" -eq 0 ]; then
        printf 'SELFTEST FAIL  %s: the check passed\n' "$1" >&2; _st_rc=1
    elif ! printf '%s\n' "$_err" | grep -q -- "$2"; then
        printf 'SELFTEST FAIL  %s: red, but not on its own diagnostic (wanted `%s`)\n' "$1" "$2" >&2
        printf '%s\n' "$_err" | sed 's/^/      | /' >&2
        _st_rc=1
    fi
}
expect_green() {
    _greens=$((_greens + 1))
    _err=$(check_root "$_scratch/root" quiet 2>&1 >/dev/null); _rc=$?
    if [ "$_rc" -ne 0 ]; then
        printf 'SELFTEST FAIL  %s: the check went red\n' "$1" >&2
        printf '%s\n' "$_err" | sed 's/^/      | /' >&2
        _st_rc=1
    fi
}

selftest() {
    _scratch=$(mktemp -d "${TMPDIR:-/tmp}/criterion3-selftest-XXXXXX") || {
        echo "SELFTEST FAIL  could not create a scratch directory" >&2
        return 1
    }
    # INT/TERM exit rather than resume: POSIX resumes after the handler, which would run
    # the remaining cases against copies this handler has just deleted and print a wall of
    # SELFTEST FAILs for an interrupt the operator asked for.
    _cleanup='[ -n "${_scratch:-}" ] && { rm -f "$_scratch/root/PRD.md" "$_scratch/root/DESIGN.md" "$_scratch/root/docs/kill-criteria-review.md" "$_scratch"/root/*.new "$_scratch"/root/docs/*.new 2>/dev/null; rmdir "$_scratch/root/docs" "$_scratch/root" "$_scratch" 2>/dev/null; }'
    trap "$_cleanup" EXIT
    trap "$_cleanup; exit 130" INT
    trap "$_cleanup; exit 143" TERM
    P="$_scratch/root/PRD.md"; R="$_scratch/root/docs/kill-criteria-review.md"; D="$_scratch/root/DESIGN.md"

    # The live values, derived rather than transcribed: extending PIN with a new
    # adjudication must not also require editing this function (review).
    _want_states=$(count_lines "$PIN")
    _last_pin=$(printf '%s\n' "$PIN" | tail -n 1)
    _last_date=${_last_pin%% *}
    _last_state=${_last_pin##* }
    _first_pin=$(printf '%s\n' "$PIN" | head -n 1)

    # --- green control, with the population counted: a check that read nothing must
    # not pass here as a check that agreed.
    fresh; expect_green "clean copies"
    _c=$(count_lines "$(markers "$P" current)"); _s=$(count_lines "$(markers "$R" state)"); _d=$(count_lines "$(markers "$D" status)")
    if [ "$_c" != "1" ] || [ "$_s" != "$_want_states" ] || [ "$_d" != "1" ]; then
        printf 'SELFTEST FAIL  clean copies hold %s/%s/%s markers (current/state/pointer), wanted 1/%s/1\n' "$_c" "$_s" "$_d" "$_want_states" >&2; _st_rc=1
    fi

    # --- reds, one predicate each
    _flip=$([ "$_last_state" = "met" ] && echo reopened || echo met)
    fresh; edit "$P" "s/criterion-3-current: $_last_pin/criterion-3-current: $_last_date $_flip/"
    expect_red "PRD current state flipped" "current disagrees with the last state marker"
    fresh; edit "$P" "s/criterion-3-current: $_last_pin/criterion-3-current: ${_first_pin%% *} $_last_state/"
    expect_red "PRD current date moved, state kept" "current disagrees with the last state marker"
    fresh; append "$P" "<!-- criterion-3-current: $_last_pin -->"
    expect_red "PRD with two current markers" "more than one current"
    fresh; edit "$P" '/^<!-- criterion-3-current: /d'
    expect_red "PRD without a current marker" "no current"
    fresh; append "$P" "<!-- criterion-3-state: $_last_pin -->"
    expect_red "PRD carrying a state marker" "PRD.md carries a state marker"
    fresh; append "$R" '<!-- criterion-3-state: 2026-09-03 failed -->'
    expect_red "unknown state on the review page" "unknown state"
    # A state word that merely contains a known one: an unanchored vocabulary test
    # accepts `unmet`, and the marker then reads as a state nobody defined.
    fresh; append "$R" '<!-- criterion-3-state: 2026-09-03 unmet -->'
    expect_red "a state word containing a known state" "unknown state"
    # No state word at all. Counted as a marker at all only because the shape allowed a
    # missing second word; reported as known only because the offender was an empty line.
    fresh; append "$R" '<!-- criterion-3-state: 2026-09-03 -->'
    expect_green "a state marker with no state word is not a marker"
    fresh; edit "$R" '/^<!-- criterion-3-state: 2026-08-26 reopened -->$/d'
    expect_red "history: a marker deleted from the middle" "history"
    # Three passes through a placeholder: a single `s/a/b/; t; s/b/a/` is GNU-only (BSD
    # sed reads `t;` as a branch to a label named `;`), and the first draft of this case
    # was green because the swap never happened.
    fresh
    edit "$R" 's/^<!-- criterion-3-state: 2026-08-26 reopened -->$/<!-- SWAP-PLACEHOLDER -->/'
    edit "$R" 's/^<!-- criterion-3-state: 2026-08-27 met -->$/<!-- criterion-3-state: 2026-08-26 reopened -->/'
    edit "$R" 's/^<!-- SWAP-PLACEHOLDER -->$/<!-- criterion-3-state: 2026-08-27 met -->/'
    if [ "$(markers "$R" state | tr '\n' ';')" != "2026-08-16 met;2026-08-27 met;2026-08-26 reopened;" ]; then
        printf 'SELFTEST FAIL  the swap mutation did not take: %s\n' "$(markers "$R" state | tr '\n' ';')" >&2; _st_rc=1
    fi
    expect_red "history: the last two markers swapped" "history"
    fresh; edit "$R" '/^<!-- criterion-3-state: 2026-08-27 met -->$/d'; edit "$P" 's/criterion-3-current: 2026-08-27 met/criterion-3-current: 2026-08-26 reopened/'
    expect_red "history: the last marker deleted and PRD moved back to match" "history"
    fresh; append "$R" '<!-- criterion-3-state: 2026-09-03 reopened -->'; edit "$P" 's/criterion-3-current: 2026-08-27 met/criterion-3-current: 2026-09-03 reopened/'
    expect_red "history: a marker appended and PRD moved, pin not extended" "history"
    fresh; append "$R" ''; append "$R" '## Reopened (2026-09-03)'; append "$R" ''; append "$R" 'Prose only, no marker.'
    expect_red "a dated section without a marker" "dated section (2026-09-03) without exactly one state marker"
    # The other side of "exactly one": a dated section carrying two. Duplicating the last
    # marker in place puts both inside that section (history goes red too, but the
    # section's own diagnostic is what is asserted).
    fresh; edit "$R" "s|^<!-- criterion-3-state: $_last_pin -->\$|<!-- criterion-3-state: $_last_pin -->\\
<!-- criterion-3-state: $_last_pin -->|"
    expect_red "a dated section with two markers" "carries 2"
    fresh; append "$D" "<!-- criterion-3-current: $_last_pin -->"
    expect_red "DESIGN claiming a current status" "DESIGN.md claims a current status"
    fresh; edit "$D" '/^<!-- criterion-3-status: PRD.md -->$/d'
    expect_red "DESIGN without its pointer" "no pointer"
    # A pointer at some other file, and a second pointer: an emptiness test would take
    # both for a pointer that is present.
    fresh; edit "$D" 's/^<!-- criterion-3-status: PRD.md -->$/<!-- criterion-3-status: DESIGN.md -->/'
    expect_red "DESIGN pointing at another file" "no pointer"
    fresh; append "$D" '<!-- criterion-3-status: PRD.md -->'
    expect_red "DESIGN with two pointers" "no pointer"
    fresh; append "$R" "<!-- criterion-3-current: $_last_pin -->"
    expect_red "the review page claiming a current status" "claims a current status"
    fresh; edit "$P" "s|^<!-- criterion-3-current: $_last_pin -->\$|<!-- criterion-3-current: $_last_pin --> trailing|"
    expect_red "a marker with trailing text is not a marker" "no current"
    fresh; rm -f "$P"
    expect_red "PRD missing" "missing"

    # --- greens: the population is what the contract says and nothing wider.
    # Each mutation is asserted to have taken before the green is read: a fenced-marker
    # control whose insertion silently did nothing is an empty control that reads as a
    # working one (the swap case above was exactly that, once).
    # A LANGUAGE-TAGGED opening fence, deliberately: an implementation that toggles only
    # on a bare ``` agrees with the real one about every bare-fenced region, so a control
    # placed in one is green under both and selects nothing (measured — that mutant lived
    # through the first version of this control). Inside a ```toml block, the bare-only
    # reading has the fence closed here and counts the marker, which is red.
    fresh
    _fence_open=$(grep -n '^```[a-zA-Z]' "$D" | head -n 1 | cut -d: -f1)
    if [ -z "$_fence_open" ]; then
        printf 'SELFTEST FAIL  DESIGN.md holds no language-tagged fenced block — the fence control cannot select a bare-only toggle\n' >&2; _st_rc=1
    else
        awk -v ln="$_fence_open" 'NR == ln { print; print "<!-- criterion-3-current: 2099-01-01 reopened -->"; next } { print }' "$D" > "$D.new" && mv "$D.new" "$D"
        # The mutation landed, and it landed after a tagged opener: without both, this is
        # an empty control that reads as a working one.
        if ! sed -n "$((_fence_open + 1))p" "$D" | grep -q 'criterion-3-current: 2099-01-01' ||
           ! sed -n "${_fence_open}p" "$D" | grep -q '^```[a-zA-Z]'; then
            printf 'SELFTEST FAIL  the fenced-marker control was not inserted after a language-tagged opening fence\n' >&2; _st_rc=1
        fi
        expect_green "a marker inside a language-tagged fenced block in DESIGN is not counted"
    fi
    fresh; append "$P" 'Do not write `<!-- criterion-3-current: 2099-01-01 reopened -->` by hand in prose.'
    expect_green "a marker mentioned mid-sentence is not counted"
    fresh; append "$P" '    <!-- criterion-3-current: 2099-01-01 reopened -->'
    expect_green "an indented marker (a code block) is not counted"
    fresh; append "$R" ''; append "$R" '## Notes'; append "$R" ''; append "$R" 'An undated H2 needs no marker.'; append "$R" ''; append "$R" '### Row 9 (2026-09-03)'; append "$R" ''; append "$R" 'An H3 with a date needs none either.'
    expect_green "undated H2 and dated H3 are not subject to the section rule"
    # The section rule starts at `## The verdict`: a dated H2 before it is a row heading,
    # not a state record. Without the gate this copy would demand a marker in it.
    fresh
    _verdict_line=$(grep -n '^## The verdict' "$R" | head -n 1 | cut -d: -f1)
    if [ -z "$_verdict_line" ]; then
        printf 'SELFTEST FAIL  the review page has no `## The verdict` heading — the section gate has no anchor\n' >&2; _st_rc=1
    else
        awk -v ln="$_verdict_line" 'NR == ln { print "## Row 0 — an early dated heading (2026-01-01)"; print ""; print "Prose only, no marker."; print "" } { print }' "$R" > "$R.new" && mv "$R.new" "$R"
        if [ "$(grep -c '^## Row 0 — an early dated heading' "$R")" != "1" ]; then
            printf 'SELFTEST FAIL  the pre-verdict dated heading was not inserted\n' >&2; _st_rc=1
        fi
        expect_green "a dated H2 before the verdict is not subject to the section rule"
    fi
    fresh; expect_green "clean copies, again"

    if [ "$_st_rc" -eq 0 ]; then
        printf 'ok   selftest: 1/%s/1 markers on the clean copies; %s red cases each on their own diagnostic (a flipped or moved current, two or zero currents, a state marker in PRD, an unknown state, a state word containing a known one, four history mutations, a dated section with none or two markers, a current claimed by DESIGN or the review page, a missing pointer, a pointer at another file, two pointers, a marker with trailing text, a missing file); %s green controls (a fenced, quoted or indented marker, a state marker with no state word, undated H2 / dated H3 / pre-verdict dated H2, and the clean copies twice)\n' \
            "$_want_states" "$_reds" "$_greens"
    fi
    return "$_st_rc"
}

REPO=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || REPO=""
if [ "${1:-}" = "--selftest" ]; then
    [ -n "$REPO" ] || { echo "SELFTEST FAIL  could not locate the repository root" >&2; exit 1; }
    selftest
    exit $?
fi

root=${1:-$REPO}
if [ -z "$root" ]; then
    printf 'FAIL  no repository root given and none could be derived from %s\n' "$0" >&2
    exit 1
fi
check_root "$root"
exit $?
