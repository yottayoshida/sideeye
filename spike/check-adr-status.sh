#!/bin/sh
# CI entry point for the Status line of every ADR under docs/adr/.
#
# Why this exists: the convention used to be "created Proposed, flipped to
# Accepted when the implementing PR merges", and an ADR file arrives in the same
# pull request as the work it decides. The flip therefore lands after that PR is
# already merged, so honouring the rule needs a second PR. Measured over the
# whole history: twenty of twenty-five born-Proposed ADRs did get flipped (ten by
# a dedicated commit), and five did not — all five between 2026-08-25 and 08-27,
# when releases were dense (#360). The default is inverted now: an ADR is written
# Accepted, and this check refuses a Status that says otherwise without saying why.
#
# Contract:
#
#   * every ADR file carries a Status line, in one of the two spellings the
#     corpus actually uses — `- **Status:** …` (18 files) or `Status: …` (13).
#     A file with neither is a FAILURE, not a skip: "no Proposed found" over a
#     file the check could not read is a true statement about nothing.
#
#   * only the FIRST WORD of that line is judged, and it must be one of
#     Accepted / Superseded / Deprecated — or Proposed carrying a `(design-first`
#     marker, which is the pre-registration case (Seal A, ADR 0012/0015/0016:
#     the campaign is declared before it runs, so Proposed is the honest value).
#     Anything else fails, including Draft and WIP: the complaint behind #360 is
#     that a reader cannot separate a shipped decision from an open one, and
#     that is not a question about the spelling `Proposed`.
#
#     Judging the first word rather than the line is what keeps the check off
#     two real files. `0002`'s line reads `Accepted (2026-08-11; proposed
#     2026-08-10)` — a case-insensitive search of the line fails it. `0030` says
#     `Proposed by external review` in its body — a search of the file fails it.
#     Both are correct as written; a check that reddens on them would be trained
#     away within a week.
#
#   * comparison is case-sensitive. `accepted` fails. The set is small and
#     written by hand, so the safe direction is to refuse a spelling nobody uses.
#
#   * the walk's coverage is asserted, not printed. The file count comes from the
#     find expression; the walked count is incremented in the loop. A narrowing
#     applied to one cannot reach the other, which is the shape that let a
#     sibling check walk 29 of 31 files and report `ok` (see check-adr-numbering.sh).
#     Zero files is a FAILURE too — a path typo would otherwise pass over an
#     empty set.
#
# Usage:
#   sh spike/check-adr-status.sh [<adr-dir>]
#   sh spike/check-adr-status.sh --selftest

set -u

ACCEPTED_WORDS='Accepted Superseded Deprecated'

# Prints the Status line of $1, or nothing. Both spellings, anchored at the line
# start so a mention inside a paragraph cannot be mistaken for the declaration.
status_line_of() {
    grep -m1 -E '^(- \*\*Status:\*\*|Status:)' "$1" 2>/dev/null || true
}

# The first word after the label. `- **Status:** Accepted (…)` -> `Accepted`.
# A trailing CR is stripped: a CRLF file would otherwise report `Accepted` as
# disallowed beside a list containing `Accepted`, because the carriage return
# rides on the word and is invisible in a terminal. Fail-closed either way, but
# a diagnostic that reads as a lie costs more than the line that prevents it.
first_word_of() {
    printf '%s\n' "$1" |
        tr -d '\r' |
        sed -E 's/^- \*\*Status:\*\*[[:space:]]*//; s/^Status:[[:space:]]*//' |
        awk '{print $1; exit}'
}

# 0 when the value is allowed, 1 otherwise. $1 = first word, $2 = whole line.
value_is_allowed() {
    _w=$1
    _line=$2
    for _ok in $ACCEPTED_WORDS; do
        [ "$_w" = "$_ok" ] && return 0
    done
    if [ "$_w" = "Proposed" ]; then
        # The marker has to attach to the word, not merely appear on the line:
        # `Proposed — see the (design-first) note below` is a mention, not a
        # declaration, and a substring test over the whole line accepts it.
        case "$_line" in
            *'Proposed (design-first'*) return 0 ;;
        esac
    fi
    return 1
}

check_dir() {
    _dir=$1
    _quiet=${2:-}

    if [ ! -d "$_dir" ]; then
        printf 'FAIL  no ADR directory at %s — this check could not look\n' "$_dir" >&2
        return 1
    fi

    # Two counts from two expressions. The walk increments its own; a narrowing
    # applied to the find below cannot reach the loop's counter, so a partial
    # walk shows up as a mismatch rather than as a shorter clean run.
    _n_files=$(find "$_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$_n_files" -eq 0 ]; then
        printf 'FAIL  %s holds no ADR file — this check could not look\n' "$_dir" >&2
        return 1
    fi

    _walked=0
    _bad=0
    for _f in "$_dir"/*.md; do
        [ -f "$_f" ] || continue
        _walked=$((_walked + 1))
        _name=${_f##*/}
        _line=$(status_line_of "$_f")

        if [ -z "$_line" ]; then
            printf 'FAIL  %s has no Status line (expected `- **Status:** …` or `Status: …` at a line start)\n' \
                "$_name" >&2
            # The nearest line mentioning Status, so a spelling like
            # `- **Status**: Accepted` — colon outside the bold — is findable
            # without hunting. Without this the message reads as a lie to
            # someone looking straight at a Status line.
            _near=$(grep -m1 -n 'Status' "$_f" 2>/dev/null || true)
            [ -n "$_near" ] && printf '      nearest line mentioning Status: %s\n' "$_near" >&2
            _bad=$((_bad + 1))
            continue
        fi

        _word=$(first_word_of "$_line")
        if ! value_is_allowed "$_word" "$_line"; then
            printf 'FAIL  %s: Status is `%s`\n' "$_name" "$_word" >&2
            printf '      allowed: %s, or Proposed with a `(design-first …)` marker\n' \
                "$(echo "$ACCEPTED_WORDS" | tr ' ' '/')" >&2
            printf '      line: %s\n' "$_line" >&2
            _bad=$((_bad + 1))
        fi
    done

    if [ "$_walked" != "$_n_files" ]; then
        printf 'FAIL  walked %s file(s) but %s ADR file(s) are present — the walk is partial\n' \
            "$_walked" "$_n_files" >&2
        return 1
    fi

    [ "$_bad" -gt 0 ] && return 1

    [ -n "$_quiet" ] || printf 'ok   %s ADR(s) under %s: every Status line present and shipped-or-declared\n' \
        "$_walked" "$_dir"
    return 0
}

# `--selftest` proves the check can go red AND that it stays green on the shapes
# it must not touch. The negative controls are the point: an over-matching check
# reddens, which looks like working, and is only caught by a fixture that must pass.
selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/adr-status-selftest-XXXXXX") || {
        echo "SELFTEST FAIL  could not create a scratch directory" >&2
        return 1
    }
    # Flat delete plus rmdir, not `rm -rf`: this fixture only ever makes regular
    # files, and a recursive delete is the shape a developer's own guard tooling
    # is most likely to intercept — which would leave scratch behind while the
    # selftest still reported success.
    # The dotted name below is deliberate (the partial-walk case), so the cleanup
    # glob has to name it too — otherwise a selftest that exits early leaves the
    # scratch directory behind and the rmdir fails silently.
    trap '[ -n "${tmp:-}" ] && { rm -f "$tmp"/*.md "$tmp"/.*.md 2>/dev/null; rmdir "$tmp" 2>/dev/null; }' EXIT INT TERM
    rc=0

    # --- negative controls: the clean set, three files, all of which must pass.
    printf -- '- **Status:** Accepted (2026-08-11; proposed 2026-08-10). Superseded in part by #169\n' \
        > "$tmp/0001-parenthetical-lowercase.md"
    printf 'Status: Accepted\n\nThe body says Proposed by external review, which is prose, not a declaration.\n' \
        > "$tmp/0002-body-mentions-proposed.md"
    printf 'Status: Proposed (design-first: the campaign is sealed before it runs)\n' \
        > "$tmp/0003-seal-a.md"

    if ! check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  the clean set was refused (over-matching)" >&2
        rc=1
    fi

    # The clean set is a known size, so a narrowing that walks fewer files is
    # caught here rather than in production. `check_dir` asserts walked == found;
    # this asserts found == what the fixture actually wrote.
    n=$(find "$tmp" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
    if [ "$n" != "3" ]; then
        echo "SELFTEST FAIL  the clean fixture should hold 3 files, found $n" >&2
        rc=1
    fi

    # --- red: a bare Proposed in each of the two spellings. One at a time, so a
    # check that knows only one spelling cannot hide behind the other.
    printf -- '- **Status:** Proposed\n' > "$tmp/0004-bare-bold.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a bare Proposed in the bold spelling was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/0004-bare-bold.md"

    printf 'Status: Proposed\n' > "$tmp/0005-bare-plain.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a bare Proposed in the plain spelling was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/0005-bare-plain.md"

    # --- red: a value outside the set. #360 is about readers telling shipped
    # from open, which Draft leaves just as unreadable as Proposed.
    printf 'Status: Draft\n' > "$tmp/0006-draft.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  Status: Draft was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/0006-draft.md"

    # --- red: no Status line at all. Without this, "no Proposed found" is true
    # of a file nothing read.
    printf '# 0007 — a decision with no status\n\nBody only.\n' > "$tmp/0007-no-status.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a file with no Status line was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/0007-no-status.md"

    # --- red: lowercase. Case-sensitive by decision, refusing a spelling nobody uses.
    printf 'Status: accepted\n' > "$tmp/0008-lowercase.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a lowercase status word was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/0008-lowercase.md"

    # --- red: the marker present but not attached to the word. A substring test
    # over the whole line accepts a mention; the exception is for a declaration.
    printf 'Status: Proposed — see the (design-first) note below\n' > "$tmp/0009-marker-unattached.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a design-first mention was read as a declaration" >&2
        rc=1
    fi
    rm -f "$tmp/0009-marker-unattached.md"

    # --- red: a partial walk. Neither empty nor complete, which is the shape the
    # count comparison exists for and the one a sibling check was caught in
    # (29 files of 31, reported ok). A dotted name is the cheapest way to make the
    # two expressions disagree without touching either: `find -name '*.md'` counts
    # it, the `"$dir"/*.md` glob does not walk it. Without this case the whole
    # comparison could be deleted and this selftest would still pass.
    printf 'Status: Accepted\n' > "$tmp/.hidden.md"
    if check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  a partial walk was accepted (the count comparison is not doing anything)" >&2
        rc=1
    fi
    rm -f "$tmp/.hidden.md"

    # --- red: an empty directory. A path typo must not pass over nothing.
    empty=$(mktemp -d "${TMPDIR:-/tmp}/adr-status-empty-XXXXXX") || {
        echo "SELFTEST FAIL  could not create the empty scratch directory" >&2
        return 1
    }
    if check_dir "$empty" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  an empty directory was accepted" >&2
        rc=1
    fi
    rmdir "$empty" 2>/dev/null

    # --- green again: the clean set still passes after all of the above.
    if ! check_dir "$tmp" quiet 2>/dev/null; then
        echo "SELFTEST FAIL  the clean set stopped passing after the red cases" >&2
        rc=1
    fi

    if [ "$rc" = "0" ]; then
        echo "ok   selftest: the check passes a parenthetical lowercase, a body mention and a design-first marker, and goes red on a bare Proposed in either spelling, a Draft, a missing Status line, a lowercase word, an unattached marker, a partial walk and an empty set"
    fi
    return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

adr_dir=${1:-}
if [ -z "$adr_dir" ]; then
    adr_dir=$(cd "$(dirname "$0")/../docs/adr" 2>/dev/null && pwd) || adr_dir=""
fi
if [ -z "$adr_dir" ]; then
    printf 'FAIL  no ADR directory at %s — this check could not look\n' \
        "${1:-<repo>/docs/adr}" >&2
    exit 1
fi

check_dir "$adr_dir"
exit $?
