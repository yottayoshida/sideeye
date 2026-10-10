#!/bin/sh
# Files come from `git ls-files`, not a directory list: a list misses the next new directory.
# An empty set fails, never passes: a pathspec typo must not read as "all formatted".

set -u

check() {
    root=$1
    count=$(git -C "$root" ls-files -z -- '*.zig' | tr -cd '\000' | wc -c | tr -d ' ') || {
        echo "FAIL could not list tracked files under $root" >&2
        return 1
    }
    if [ "$count" -eq 0 ]; then
        echo "FAIL no tracked .zig file under $root — refusing to report an empty set as formatted" >&2
        return 1
    fi
    # Run in the root: git prints root-relative paths.
    if out=$(cd "$root" && git ls-files -z -- '*.zig' | xargs -0 zig fmt --check 2>&1); then
        echo "ok   $count tracked .zig file(s), every one what zig fmt leaves it"
        return 0
    fi
    printf '%s\n' "$out" | sed 's/^/     /' >&2
    echo "FAIL the file(s) above are not what zig fmt leaves them (of $count tracked). Run: zig fmt \$(git ls-files '*.zig')" >&2
    return 1
}

# The unformatted fixture sits two directories down: a check narrowed to top-level paths must fail it.
selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/zigfmt-selftest-XXXXXX") || {
        echo "FAIL selftest: could not create a scratch directory" >&2
        return 1
    }
    # `rm` can be wrapped on a workstation, so a leftover under $TMPDIR is accepted; never widen past the mkdtemp name.
    trap 'case "${tmp:-}" in */zigfmt-selftest-*) rm -rf "$tmp" 2>/dev/null ;; esac' EXIT INT TERM
    fails=0

    repo=$tmp/repo
    mkdir -p "$repo/a/b"
    git -C "$repo" init -q
    printf 'const x = 1;\n' > "$repo/top.zig"
    printf 'const  y = 2;\n' > "$repo/a/b/nested.zig"
    git -C "$repo" add top.zig a/b/nested.zig

    if out=$(check "$repo" 2>&1); then
        echo "FAIL selftest: passed a repository holding an unformatted file two directories down" >&2
        fails=$((fails + 1))
    elif ! printf '%s\n' "$out" | grep -q 'a/b/nested.zig'; then
        echo "FAIL selftest: went red without naming the unformatted file" >&2
        fails=$((fails + 1))
    fi

    # Keep this control: without it a check that always fails passes the case above.
    (cd "$repo" && zig fmt a/b/nested.zig >/dev/null)
    if ! check "$repo" >/dev/null 2>&1; then
        echo "FAIL selftest: went red on a repository whose every tracked file is formatted" >&2
        fails=$((fails + 1))
    fi

    # Do not check the working tree: an untracked file cannot reach main.
    printf 'const  z = 3;\n' > "$repo/a/untracked.zig"
    if ! check "$repo" >/dev/null 2>&1; then
        echo "FAIL selftest: went red on an untracked file" >&2
        fails=$((fails + 1))
    fi

    printf 'const = ;\n' > "$repo/a/broken.zig"
    git -C "$repo" add a/broken.zig
    if check "$repo" >/dev/null 2>&1; then
        echo "FAIL selftest: passed a tracked file zig fmt cannot parse" >&2
        fails=$((fails + 1))
    fi

    empty=$tmp/empty
    mkdir "$empty"
    git -C "$empty" init -q
    if check "$empty" >/dev/null 2>&1; then
        echo "FAIL selftest: passed a repository with no tracked .zig file" >&2
        fails=$((fails + 1))
    fi

    if [ "$fails" -eq 0 ]; then
        echo "ok   selftest: the check goes red on a nested unformatted file (naming it), on an unparseable file and on an empty set, and passes a formatted repository with an untracked unformatted file beside it"
        return 0
    fi
    return 1
}

if [ "${1:-}" = "--selftest" ]; then
    selftest
    exit $?
fi

root=$(git rev-parse --show-toplevel) || {
    echo "FAIL not inside a git repository" >&2
    exit 1
}
check "$root"
