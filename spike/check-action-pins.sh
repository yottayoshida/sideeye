#!/bin/sh
# CI entry point for action pinning across .github/workflows.
#
# Why this exists: `uses: actions/checkout@v4` names a tag, and a tag is a
# pointer the action's owner can move. Whatever it points at runs with this
# repository's checkout in front of it and, in release.yml, with the token that
# uploads the artifacts people download. `spike-fsusage.yml` already pinned its
# three by commit and said why in a comment — but it said it about ITSELF ("these
# actions run before a script that runs as root"), so the judgment sat in the
# repository, scoped to one file, while the other twenty-one stayed on tags.
# ADR 0060 widens the scope; this check is what holds it there, because pinning
# is not a thing you do once. The next workflow anyone adds will be written from
# a README that says `@v4`.
#
# Contract:
#
#   * every `uses:` names `<owner>/<repo>[/<path>]@<40 hex>`. Not merely something
#     ending in forty hex: `docker://x@<40 hex>` and `./.github/actions/x@<40 hex>`
#     both satisfied a looser rule and neither is a pinned action (both measured).
#   * the version the SHA came from travels beside it as a trailing comment
#     (`# v4`). This is checked, because the first draft wrote the requirement into
#     this header and into ADR 0060 and then dropped the comment before testing —
#     a reference with no comment passed, so the page said a rule the code did not
#     hold (measured, first-read review).
#   * finding NOTHING is a FAILURE. A directory with no workflow files, or workflow
#     files with no `uses:` at all, exits 1 rather than reporting that every action
#     it did not look at is pinned. The failure this repository keeps meeting is a
#     check that passes over an empty set, and a glob that matched nothing is
#     exactly how you get one.
#
# THREE assertions stand behind the walk, and the reason each exists is that the
# draft without it went green over a subset:
#
#   1. TWO FILE SETS, from two mechanisms — `find` and the shell's glob. The first
#      draft derived the walk, the independent count and the file count from ONE
#      `find`, and called the walk and the count independent because one used grep
#      and the other awk. Narrowing that single `find` to `-name 'ci.yml'` produced
#      `ok 16 action reference(s) across 1 workflow(s) … every one pinned` —
#      release.yml, the leg holding the token, never read (measured). Splitting the
#      LINE pattern is not splitting the INPUT. This is exactly what
#      check-adr-numbering.sh's header records about its own near-miss: "both came
#      from the same `find` expression … a count and a re-run of the same command
#      are not two predicates."
#   2. TWO LINE PATTERNS — the narrow one the walk reads, and a wider one that only
#      counts. `- {uses: a/b@v4}` (flow mapping) and `uses : a/b@v4` (space before
#      the colon, legal YAML) are missed by the narrow pattern; with nothing else
#      looking, three references of which two named tags reported `ok 1 action
#      reference(s) … every one pinned` (measured). The wide pattern does not
#      understand them either — it counts them, which is enough to refuse rather
#      than to pass over them. A `uses:` inside a comment would also be counted and
#      would fail this check: the error is in the direction of refusing, and the
#      remedy is to write the comment without the colon.
#   3. AN INDEPENDENT COUNT, by awk over the glob set. Its input is the set `find`
#      did not produce, so a narrowing of either is visible in the comparison.
#
# Assertion 1 also catches two cases it was not built for, and its message names
# neither, so a reader meeting "two listings disagree" should check for these before
# hunting a narrowing bug:
#   * a SYMLINKED workflow. `find -type f` skips it; the glob's `[ -f ]` follows it.
#     Whether GitHub executes one is not measured, and a file the walk cannot see must
#     not be reported as pinned, so refusing is the direction that needs no answer.
#   * a DOT-PREFIXED name (`.hidden.yml`, an editor's backup). `find -name '*.yml'`
#     matches a leading dot; the shell's glob does not. This one is a selftest case,
#     because the same difference is what makes the branch drivable by data.
#
# What it does NOT check, and must not be described as checking:
#
#   * that a SHA exists, or that it is what the trailing comment claims. That needs
#     the network and a token. What stands behind it is the CI run itself: a SHA
#     that names nothing fails the job that uses it, loudly, on the pull request
#     that introduced it.
#   * that the pinned commit is a good one to run. Pinning freezes the code; it does
#     not review it. A compromised action pinned by SHA runs the compromised code
#     forever rather than for one window — the trade this makes on purpose, because
#     the alternative moves without anyone looking.
#   * YAML, as a grammar. This reads lines. Assertion 2 above converts the forms it
#     cannot read into a refusal rather than a silent omission, which is the most a
#     line reader can offer; a workflow written entirely in flow style would fail
#     here and want a real parser.
#
# The workflow directory is an argument so the selftest can point it at a scratch
# copy. Reading `git ls-files` instead would make those fixtures invisible —
# untracked files in a temporary directory — and the check would pass over an empty
# set while appearing to test something.
#
# `--selftest` proves the check can go red, at run time, on every run — including
# the count-disagreement branch, which the first draft asserted in this header and
# exercised nowhere (found by first-read review: the BUILDLOG table said "red on the
# real directory" for that row alone, which is the shape of a falsification that
# does not carry forward).
#
# Sunset: NOT "delete this if it has not failed by <date>". A pin check that never
# goes red is a check doing its job — it means nobody added an unpinned action — so
# the usual rule would delete it exactly while it is working. Delete it when one of
# these becomes true instead:
#   * GitHub makes action tags immutable, so `@v4` cannot be repointed; or
#   * something else keeps these SHAs current (a Dependabot configuration that
#     rewrites them), in which case that mechanism holds the invariant and this
#     check becomes the second place one judgment lives.
set -u

self=$0

# `<owner>/<repo>[/<path>]@<40 hex>`. The leading segment may not begin with a dot
# (which is what makes `./.github/actions/x` fail) and may not contain a colon
# (`docker://x`).
is_pinned() {
    printf '%s' "$1" | grep -qE '^[A-Za-z0-9_][A-Za-z0-9._-]*/[A-Za-z0-9._/-]+@[0-9a-fA-F]{40}$'
}

scan() {  # $1 = workflow directory. 0 = every action pinned, 1 = not.
    dir=$1

    if [ ! -d "$dir" ]; then
        printf 'FAIL  no workflow directory at %s — this check could not look\n' "$dir" >&2
        return 1
    fi

    # Assertion 1, first half: the set `find` sees.
    files=$(find "$dir" -mindepth 1 -maxdepth 1 -type f \
        \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort)
    n_find=$(printf '%s\n' "$files" | grep -c '[^[:space:]]' || true)

    # Assertion 1, second half: the set the shell's glob sees, held in the
    # positional parameters so awk below reads exactly this set and not a glob that
    # may not have matched. (A literal `"$dir"/*.yaml` reaching awk makes it exit
    # non-zero with no output, which the first draft turned into a count of 0 and a
    # refusal on every real run — measured.)
    shift $#
    for g in "$dir"/*.yml "$dir"/*.yaml; do
        [ -f "$g" ] && set -- "$@" "$g"
    done
    n_glob=$#

    if [ "$n_find" != "$n_glob" ]; then
        printf 'FAIL  two listings of %s disagree: find sees %s file(s), the shell glob sees %s —\n' \
            "$dir" "$n_find" "$n_glob" >&2
        printf '      the walk would be over a subset. Fix the listing before reading a verdict.\n' >&2
        return 1
    fi

    if [ "$n_find" -eq 0 ]; then
        printf 'FAIL  %s holds no workflow files — this check could not look\n' "$dir" >&2
        return 1
    fi

    # Assertion 3: an independent count, over the glob set rather than find's. No
    # empty-set guard here: the two refusals above leave n_glob == n_find > 0.
    n_by_awk=$(awk '/^[ \t]*-?[ \t]*uses:/ { n++ } END { print n + 0 }' "$@")

    total=0
    fails=0

    # A here-document rather than a pipe: a `grep | while` increments the counters
    # in a subshell, and the coverage assertions below would then compare zero
    # against the file count on every run — including the runs where they are the
    # only thing between a short read and a green.
    records=$(printf '%s\n' "$files" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -nE '^[[:space:]]*-?[[:space:]]*uses:' "$f" 2>/dev/null |
            while IFS= read -r hit; do printf '%s:%s\n' "$f" "$hit"; done
    done)

    # Assertion 2: the wider pattern. Anything it counts that the walk does not read
    # is a form this check cannot parse, and an unparsed `uses:` must refuse.
    n_wide=0
    for g in "$@"; do
        c=$(grep -cE 'uses[[:space:]]*:' "$g" || true)
        n_wide=$((n_wide + c))
    done

    while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        total=$((total + 1))

        file=${rec%%:*}
        rest=${rec#*:}
        lineno=${rest%%:*}
        line=${rest#*:}

        after=${line#*uses:}
        value=${after%%#*}
        value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        if ! is_pinned "$value"; then
            printf 'FAIL  %s:%s names %s\n' "${file##*/}" "$lineno" "${value:-<nothing>}"
            printf '      Pin it: uses: <owner>/<repo>@<40-char commit SHA> # <the tag it came from>\n'
            printf '      The SHA for a tag: gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq .object.sha\n'
            fails=$((fails + 1))
            continue
        fi

        # The trailing comment the contract requires, and ADR 0060 states.
        case "$after" in
            *'#'*) ;;
            *)
                printf 'FAIL  %s:%s pins %s with no trailing comment\n' \
                    "${file##*/}" "$lineno" "$value"
                printf '      A SHA alone tells the next reader nothing about what it is or when to move it.\n'
                printf '      Write the tag it came from: uses: %s # v4\n' "$value"
                fails=$((fails + 1))
                ;;
        esac
    done <<RECORDS
$records
RECORDS

    if [ "$total" -eq 0 ]; then
        printf 'FAIL  %s workflow file(s) under %s and not one `uses:` among them —\n' \
            "$n_find" "$dir" >&2
        printf '      a green here would be a statement about nothing.\n' >&2
        return 1
    fi

    if [ "$total" != "$n_by_awk" ]; then
        printf 'FAIL  the walk read %s `uses:` line(s); an independent count found %s —\n' \
            "$total" "$n_by_awk" >&2
        printf '      the two disagree, so neither can be trusted. Fix the walk before reading a verdict.\n' >&2
        return 1
    fi

    if [ "$total" != "$n_wide" ]; then
        printf 'FAIL  the walk read %s `uses:` line(s); a wider pattern counts %s —\n' \
            "$total" "$n_wide" >&2
        printf '      %s reference(s) are written in a form this check cannot read, so it cannot say\n' \
            "$((n_wide - total))" >&2
        printf '      they are pinned. Flow mappings (`- {uses: a/b@sha}`) and a space before the colon\n' >&2
        printf '      are the two known shapes; a `uses:` inside a comment counts here too — reword it.\n' >&2
        grep -nE 'uses[[:space:]]*:' "$@" 2>/dev/null |
            grep -vE ':?[0-9]+:[[:space:]]*-?[[:space:]]*uses:' | sed 's/^/          /' >&2
        return 1
    fi

    if [ "$fails" -eq 0 ]; then
        printf 'ok   %s action reference(s) across %s workflow(s) under %s, every one pinned by commit with its tag beside it\n' \
            "$total" "$n_find" "${dir##*/}"
        return 0
    fi

    printf 'FAIL action pinning under %s: %s of %s reference(s) are not a commit-pinned action with its tag\n' \
        "$dir" "$fails" "$total" >&2
    return 1
}

selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/action-pins-selftest-XXXXXX") || {
        echo "SELFTEST FAIL  could not create a scratch directory" >&2
        return 1
    }
    # One cleanup path. Deliberately not `rm -rf`: this fixture only ever creates
    # regular files, so a flat delete plus rmdir removes exactly what was made —
    # and a recursive delete is the shape a developer's own guard tooling is most
    # likely to intercept, which would leave the scratch behind while the selftest
    # still reported success.
    # The dot-prefixed names matter: one case below plants a `.hidden.yml`, and
    # `rm -f "$tmp"/*` does not match it — it would leak into the next case and
    # leave the scratch directory undeletable. `.*.yml` cannot match `.` or `..`.
    trap '[ -n "${tmp:-}" ] && { rm -f "$tmp"/* "$tmp"/.*.yml "$tmp"/.*.yaml 2>/dev/null; rmdir "$tmp" 2>/dev/null; }' EXIT INT TERM
    rc=0
    sha=11d5960a326750d5838078e36cf38b85af677262

    reset() { rm -f "$tmp"/*.yml "$tmp"/*.yaml "$tmp"/.*.yml "$tmp"/.*.yaml 2>/dev/null; }
    base() {
        reset
        cat > "$tmp/a.yml" <<YAML
jobs:
  one:
    steps:
      - uses: actions/checkout@$sha # v4
      - uses: mlugg/setup-zig@$sha # v2
YAML
    }
    # $1 = description, $2 = expected rc (0 or 1), $3.. = strings the output must carry
    expect() {
        desc=$1; want=$2; shift 2
        out=$(sh "$self" "$tmp" 2>&1); got=$?
        if [ "$want" -eq 0 ] && [ "$got" -ne 0 ]; then
            printf 'SELFTEST FAIL  %s: expected a pass, got rc=%s\n' "$desc" "$got" >&2
            rc=1
            return
        fi
        if [ "$want" -ne 0 ] && [ "$got" -eq 0 ]; then
            printf 'SELFTEST FAIL  %s: expected a refusal, got a pass\n' "$desc" >&2
            rc=1
            return
        fi
        for want_str in "$@"; do
            case "$out" in
                *"$want_str"*) ;;
                *) printf 'SELFTEST FAIL  %s: the report did not name %s\n' "$desc" "$want_str" >&2; rc=1 ;;
            esac
        done
    }

    # Positive control first: without it, a check that always fails passes every
    # negative case below.
    base
    expect "a fully pinned workflow" 0

    # Upper case resolves in git and must not be invented into a failure.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: actions/cache@%s # v4\n' \
        "$(printf '%s' "$sha" | tr 'a-f' 'A-F')" > "$tmp/b.yml"
    expect "an upper-case SHA" 0

    # A repository with a path segment (actions/aws/ec2-runner@sha).
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: some/action/sub@%s # v1\n' "$sha" > "$tmp/b.yml"
    expect "an owner/repo/path reference" 0

    # The defect this check exists for, named by file and line.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: actions/cache@v4\n' > "$tmp/b.yml"
    expect "a tag reference (@v4)" 1 "b.yml:4" "actions/cache@v4"

    # One character short of a SHA.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: actions/cache@%s # v4\n' \
        "$(printf '%s' "$sha" | cut -c1-39)" > "$tmp/b.yml"
    expect "a 39-character reference" 1

    # A local action: nothing to pin, and the decision belongs in the open.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: ./.github/actions/thing\n' > "$tmp/b.yml"
    expect "a reference with no @" 1

    # Forty hex on something that is not an action. Both passed a looser rule.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: docker://evil@%s # v1\n' "$sha" > "$tmp/b.yml"
    expect "a docker:// reference carrying 40 hex" 1
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: ./.github/actions/x@%s # v1\n' "$sha" > "$tmp/b.yml"
    expect "a local path carrying 40 hex" 1

    # The trailing comment the contract requires.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: actions/cache@%s\n' "$sha" > "$tmp/b.yml"
    expect "a SHA with no trailing comment" 1 "no trailing comment"

    # Assertion 2: forms the narrow pattern cannot read must refuse, not pass.
    base
    printf 'jobs:\n  two:\n    steps:\n      - {uses: actions/cache@v4}\n' > "$tmp/b.yml"
    expect "a flow mapping the walk cannot read" 1 "a wider pattern counts"
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses : actions/cache@v4\n' > "$tmp/b.yml"
    expect "a space before the colon" 1 "a wider pattern counts"

    # Assertion 3: the walk and the independent count disagreeing. A vertical tab
    # is whitespace to grep's [[:space:]] and not to awk's [ \t], so the line is
    # read by one and not the other — the branch the first draft asserted in its
    # header and exercised nowhere.
    base
    printf 'jobs:\n  two:\n    steps:\n\013      - uses: actions/cache@%s # v4\n' "$sha" > "$tmp/b.yml"
    expect "the walk and the independent count disagreeing" 1 "an independent count found"

    # Assertion 1: the two listings disagreeing. `find -name '*.yml'` matches a
    # leading dot and the shell's glob does not, so a dot-prefixed workflow is seen
    # by one listing and not the other. Driven by data rather than by editing the
    # script, for the same reason as the case above — and the file it plants really
    # does hold an unpinned action, so a check that silently took either listing
    # would report a green over it.
    base
    printf 'jobs:\n  two:\n    steps:\n      - uses: actions/cache@v4\n' > "$tmp/.hidden.yml"
    expect "two listings of the directory disagreeing" 1 "two listings of"
    reset

    # Workflow files with no actions at all: a green would describe nothing.
    reset
    printf 'name: nothing\non: push\n' > "$tmp/a.yml"
    expect "a workflow directory with no actions" 1

    # The empty set.
    reset
    expect "a directory with no workflow files" 1

    # A directory that is not there at all.
    if sh "$self" "$tmp/nope" >/dev/null 2>&1; then
        echo "SELFTEST FAIL  a missing directory was accepted" >&2
        rc=1
    fi

    if [ "$rc" = 0 ]; then
        echo "ok   selftest: 16 cases — 3 pass (pinned, upper-case SHA, owner/repo/path), 13 refuse (tag, 39 hex, no @, docker:// and local path carrying 40 hex, missing tag comment, flow mapping, space before colon, the two listings disagreeing, walk/count disagreement, no actions, no files, missing directory)"
    fi
    return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

wf_dir=${1:-}
if [ -z "$wf_dir" ]; then
    wf_dir=$(cd "$(dirname "$0")/../.github/workflows" 2>/dev/null && pwd) || wf_dir=""
    [ -n "$wf_dir" ] || wf_dir="<repo>/.github/workflows"
fi

scan "$wf_dir"
