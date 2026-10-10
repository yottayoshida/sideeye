#!/bin/sh
# CI entry point for Zig formatting (#695).
#
# Why this exists: nothing ran `zig fmt --check` before it, and eight tracked files had
# drifted from what `zig fmt` produces when it landed. spike/check-main-shape.sh had been
# reading "directly inside a container" as four spaces of indentation on the strength of
# "what `zig fmt` produces and what every file here has" — the second half of which was
# no longer true, and the first half of which nothing enforced.
#
# Contract:
#
#   * every TRACKED .zig file is what `zig fmt` would leave it. The files are collected
#     by `git ls-files`, not by a list of directories: the list this check was first
#     drafted with (`src shim build.zig`) would have missed spike/fsusage/scan.zig, which
#     was one of the eight. An untracked .zig file is not checked — it cannot reach main.
#   * finding no file at all is a FAILURE, not a pass. A pathspec typo would otherwise
#     report success over an empty set — the failure mode this repository keeps meeting.
#   * a file `zig fmt` cannot parse is a failure too: `zig fmt --check` exits non-zero on
#     it, and this check passes that through rather than reading it as "formatted".
#
# What it does NOT check: anything `zig fmt` accepts — including a region between
# `// zig fmt: off` and `// zig fmt: on`, which the formatter leaves as written. It is a
# formatter, not a linter; the shape rules spike/check-main-shape.sh holds stay that
# script's. And it stops nothing by itself: the `fmt` job is not a required check.
#
# Run from anywhere inside the repository: the root is git's, not the caller's cwd.

set -u

# check <repository root>: 0 when every tracked .zig file is formatted, 1 otherwise.
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
    # `zig fmt --check` names every file it would change and exits 1 if there is one.
    # The paths git prints are relative to the root, so the listing runs there.
    if out=$(cd "$root" && git ls-files -z -- '*.zig' | xargs -0 zig fmt --check 2>&1); then
        echo "ok   $count tracked .zig file(s), every one what zig fmt leaves it"
        return 0
    fi
    printf '%s\n' "$out" | sed 's/^/     /' >&2
    echo "FAIL the file(s) above are not what zig fmt leaves them (of $count tracked). Run: zig fmt \$(git ls-files '*.zig')" >&2
    return 1
}

# `--selftest` proves the check can go red, at run time, on every run — and that it goes
# red on HOW the files are collected, not only on what the formatter says: the fixture's
# unformatted file sits two directories down, so a check narrowed to a list of top-level
# paths passes its own top-level file and misses it.
selftest() {
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/zigfmt-selftest-XXXXXX") || {
        echo "FAIL selftest: could not create a scratch directory" >&2
        return 1
    }
    # Best effort: on a runner this removes the scratch repositories; where `rm` is
    # wrapped (some workstations route recursive deletes elsewhere) they stay under
    # $TMPDIR, which the OS clears. Guarded so an empty $tmp can never widen the target.
    trap 'case "${tmp:-}" in */zigfmt-selftest-*) rm -rf "$tmp" 2>/dev/null ;; esac' EXIT INT TERM
    fails=0

    repo=$tmp/repo
    mkdir -p "$repo/a/b"
    git -C "$repo" init -q
    printf 'const x = 1;\n' > "$repo/top.zig"
    # Two spaces after `const`: valid Zig, and not what `zig fmt` renders.
    printf 'const  y = 2;\n' > "$repo/a/b/nested.zig"
    git -C "$repo" add top.zig a/b/nested.zig

    if out=$(check "$repo" 2>&1); then
        echo "FAIL selftest: passed a repository holding an unformatted file two directories down" >&2
        fails=$((fails + 1))
    elif ! printf '%s\n' "$out" | grep -q 'a/b/nested.zig'; then
        echo "FAIL selftest: went red without naming the unformatted file" >&2
        fails=$((fails + 1))
    fi

    # Positive control: without it, a check that always fails passes the case above.
    (cd "$repo" && zig fmt a/b/nested.zig >/dev/null)
    if ! check "$repo" >/dev/null 2>&1; then
        echo "FAIL selftest: went red on a repository whose every tracked file is formatted" >&2
        fails=$((fails + 1))
    fi

    # An untracked unformatted file does not count: it cannot reach main, and checking
    # the working tree instead of the index would make the result depend on whoever ran it.
    printf 'const  z = 3;\n' > "$repo/a/untracked.zig"
    if ! check "$repo" >/dev/null 2>&1; then
        echo "FAIL selftest: went red on an untracked file" >&2
        fails=$((fails + 1))
    fi

    # A file the formatter cannot parse is a failure, not "formatted".
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
