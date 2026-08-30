#!/bin/sh
# CI entry point for docs/adr/ number allocation.
#
# Why this exists: numbering is "the highest existing number plus one", which
# reserves nothing. On 2026-08-27 two sessions each created a docs/adr/0028-*.md.
# The slugs differed, so the filenames differed, so git merged both without a
# conflict — and the only thing that noticed was the two sessions telling each
# other, which is not a mechanism (#373; ADR 0030 records the incident and the
# numbering rule, and names the gap this closes).
#
# Contract:
#
#   * the ADR directory holds NOTHING BUT ADR files. Every entry directly under
#     it is a regular file named NNNN-slug.md — exactly four digits, a hyphen, a
#     non-empty slug. The first draft scanned `-type f -name '*.md'` and called
#     that "every filename", which it is not: a symlink, a directory named
#     `0031-x.md`, an uppercase `.MD` and a plain `notes` were all invisible, so
#     four ways to collide or to sit unclassified reported `every number unique`
#     (all four measured in review). The population is asserted first, and
#     anything that is not an ADR file is named.
#   * those four digits are unique across the directory. A collision names both
#     files, because "0028 is taken" without saying by what leaves the reader to
#     go looking.
#   * finding no file at all is a FAILURE, not a pass. A path typo would
#     otherwise report success over an empty set — the failure mode this
#     repository keeps meeting.
#   * the walk covers every entry. TWO independent counts stand behind this: the
#     entry count (every child of the directory) and the ADR-file count. The
#     first draft compared only the walked count against the file count, and both
#     came from the same `find` expression — narrowing `-name` in both places
#     walked 29 of 31 and reported `ok` (measured). A count and a re-run of the
#     same command are not two predicates.
#
# What it does NOT check, and must not be described as checking:
#
#   * CONTIGUITY. After the 0028 collision was renumbered to 0029, 0028 was a
#     gap in the tracked sequence until the other side landed — during exactly
#     the window a check matters. Uniqueness only. A contiguity check would go
#     red on the correct resolution of the very problem this exists for.
#   * the merge that CREATES a collision. No status check is required on this
#     repository, so two pull requests can each carry a unique 0032 against the
#     same base, both go green, and both merge. This runs on pull requests too —
#     a branch cut from a main that already holds the number is caught there —
#     but the two-branches-same-base race is caught only on the post-merge run of
#     main. It reports a collision; it does not prevent one. Closing that needs a
#     required up-to-date check or a merge queue, which is a repository setting
#     and a separate decision.
#   * whether a renumber is safe to perform. It is the prescribed remedy and it
#     is not free: paths of the form docs/adr/NNNN-slug.md are hardcoded in
#     several tracked documents, and only spike/acceptance.sh sweeps any of them
#     (three pages, for slashed backtick references). Bare `ADR NNNN` prose
#     citations are checked by nothing and break semantically rather than
#     loudly — after a renumber they point at a different decision. Renumber
#     before anything cites the path.
#
# The ADR directory is an argument so the falsification fixtures can point it at
# a scratch copy. Reading `git ls-files` instead would make those fixtures
# invisible — untracked files in a temporary directory — and the check would
# pass over an empty set while appearing to test something.
#
# `--selftest` proves the check can go red, at run time, on every run. The
# uniqueness pass is a pipeline with no `set -e` behind it: breaking its `sed`
# yields an empty result, no failures, and `every number unique` over a directory
# that really holds a duplicate (measured). A one-time manual falsification on
# the authoring branch does not carry forward. This repository already writes the
# standard down — check-freeze-audit.sh generates its tampered copy at run time
# because "a committed fixture rots silently and an absent fixture must never
# read as a passed falsification" — and upstream-report-status.sh carries the
# same affordance.
set -u

self=$0

selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/adr-selftest-XXXXXX") || {
        echo "SELFTEST FAIL  could not create a scratch directory" >&2
        return 1
    }
    # One cleanup path rather than one per exit. The guard is not decoration: an
    # unset tmp would make this operate on the wrong place. Deliberately not
    # `rm -rf`: this fixture only ever creates regular files, so a flat delete
    # plus rmdir removes exactly what was made and nothing that was not — and a
    # recursive delete is the shape a developer's own guard tooling is most
    # likely to intercept, which would leave the scratch behind while the
    # selftest still reported success (measured on the authoring machine).
    trap '[ -n "${tmp:-}" ] && { rm -f "$tmp"/* 2>/dev/null; rmdir "$tmp" 2>/dev/null; }' EXIT INT TERM
    rc=0

    printf 'x\n' > "$tmp/0001-first.md"
    printf 'x\n' > "$tmp/0002-second.md"

    # Positive control first: without it, a check that always fails passes every
    # negative case below.
    if ! sh "$self" "$tmp" >/dev/null 2>&1; then
        echo "SELFTEST FAIL  a clean directory did not pass" >&2
        rc=1
    fi

    # The collision this check exists for, and the half a broken uniqueness
    # pipeline silently loses.
    printf 'x\n' > "$tmp/0002-third.md"
    out=$(sh "$self" "$tmp" 2>&1)
    if [ $? -eq 0 ]; then
        echo "SELFTEST FAIL  a real duplicate (0002 twice) was accepted" >&2
        rc=1
    else
        for want in 0002-second.md 0002-third.md; do
            case "$out" in
                *"$want"*) ;;
                *)
                    printf 'SELFTEST FAIL  the duplicate report did not name %s\n' "$want" >&2
                    rc=1
                    ;;
            esac
        done
    fi
    rm -f "$tmp/0002-third.md"

    # The population assertion: an entry that is not an ADR file.
    printf 'x\n' > "$tmp/notes"
    if sh "$self" "$tmp" >/dev/null 2>&1; then
        echo "SELFTEST FAIL  a non-ADR entry beside the ADRs was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/notes"

    # The grammar.
    printf 'x\n' > "$tmp/00010-five-digits.md"
    if sh "$self" "$tmp" >/dev/null 2>&1; then
        echo "SELFTEST FAIL  a five-digit prefix was accepted" >&2
        rc=1
    fi
    rm -f "$tmp/00010-five-digits.md"

    # The empty set.
    rm -f "$tmp"/*.md
    if sh "$self" "$tmp" >/dev/null 2>&1; then
        echo "SELFTEST FAIL  an empty directory was accepted" >&2
        rc=1
    fi

    if [ "$rc" = 0 ]; then
        echo "ok   selftest: the check passes a clean directory and goes red on a duplicate (naming both), a non-ADR entry, a bad prefix and an empty set"
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

if [ -z "$adr_dir" ] || [ ! -d "$adr_dir" ]; then
    printf 'FAIL  no ADR directory at %s — this check could not look\n' \
        "${1:-<repo>/docs/adr}" >&2
    exit 1
fi

# A newline in a name splits one record into two in the line-oriented walk below.
# A tab does not break that walk — `IFS= read -r` splits on newline only — but a
# name carrying either is outside the convention this check enforces, and a
# report that cannot print a name on one line cannot tell anyone what to rename.
# `find -print0` separates with NUL and introduces neither, so deleting those two
# bytes from the stream and comparing byte counts detects them and nothing else.
raw_bytes=$(find "$adr_dir" -mindepth 1 -maxdepth 1 -print0 | wc -c | tr -d ' ')
kept_bytes=$(find "$adr_dir" -mindepth 1 -maxdepth 1 -print0 |
    LC_ALL=C tr -d '\11\12' | wc -c | tr -d ' ')
if [ "$raw_bytes" != "$kept_bytes" ]; then
    printf 'FAIL  a name under %s contains a tab or a newline\n' "$adr_dir" >&2
    printf '      (%s such byte(s)). Rename it: ADR names are NNNN-slug.md and carry neither.\n' \
        "$((raw_bytes - kept_bytes))" >&2
    exit 1
fi

# Two counts from two different expressions. The ADR-file count drives the walk;
# the entry count is what makes the walk's coverage assertable, because a
# narrowing applied to the file expression cannot reach it.
n_entries=$(find "$adr_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
n_files=$(find "$adr_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')

if [ "$n_entries" -eq 0 ]; then
    printf 'FAIL  %s is empty — this check could not look\n' "$adr_dir" >&2
    exit 1
fi

if [ "$n_entries" != "$n_files" ]; then
    printf 'FAIL  %s holds %s entr(ies) but only %s are ADR files. Not an ADR file:\n' \
        "$adr_dir" "$n_entries" "$n_files" >&2
    find "$adr_dir" -mindepth 1 -maxdepth 1 ! \( -type f -name '*.md' \) |
        while IFS= read -r stray; do printf '          %s\n' "${stray##*/}" >&2; done
    printf '      A symlink, a directory or an uppercase .MD can carry a number this check\n' >&2
    printf '      would otherwise never compare. The directory holds ADR files and nothing else.\n' >&2
    exit 1
fi

# The same expression as n_files, deliberately. The walk-count assertion below asks
# "did the read loop consume the whole listing" — a narrower question than "is the
# listing the whole directory", which is n_entries' job. Deriving n_files from this
# listing instead would collapse the first question into a tautology.
listing=$(find "$adr_dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)

total=0
fails=0
# Names that passed the grammar, one per line, each already terminated. Only
# these reach the uniqueness pass: a name that is not NNNN-slug.md has no
# well-defined number to compare, and reporting it twice would say the same
# defect in two voices.
ok_names=""

# A here-document rather than a pipe, so the counters stay in this shell. A
# `find | while` would increment them in a subshell and the walk-count assertion
# below would compare zero against the file count on every run — including the
# runs where it is the only thing standing between a short read and a green.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    base=${path##*/}
    total=$((total + 1))

    case "$base" in
        [0-9][0-9][0-9][0-9]-?*.md) ;;
        *)
            printf 'FAIL  %s: not NNNN-slug.md — four digits, a hyphen, a non-empty slug\n' "$base"
            fails=$((fails + 1))
            continue
            ;;
    esac

    ok_names="$ok_names$base
"
done <<LISTING
$listing
LISTING

# The walk has to cover every file, not most of them.
if [ "$total" != "$n_files" ]; then
    printf 'FAIL  walked %s file(s) but %s holds %s — the listing and the walk disagree\n' \
        "$total" "$adr_dir" "$n_files" >&2
    exit 1
fi

if [ -n "$ok_names" ]; then
    dups=$(printf '%s' "$ok_names" | sed 's/-.*//' | LC_ALL=C sort | uniq -d)
    for d in $dups; do
        printf 'FAIL  number %s is taken by more than one ADR:\n' "$d"
        printf '%s' "$ok_names" | grep "^$d-" | sed 's/^/          /'
        fails=$((fails + 1))
    done
fi

if [ "$fails" = 0 ]; then
    printf 'ok   %s ADR(s) under %s: every entry an ADR file, every name NNNN-slug.md, every number unique\n' \
        "$total" "$adr_dir"
    exit 0
fi

printf 'FAIL ADR numbering under %s: %s problem(s) over %s file(s)\n' "$adr_dir" "$fails" "$total" >&2
exit 1
