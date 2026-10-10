#!/bin/sh
# spike/check-comment-only.sh — a pull request that removed comment lines changed nothing else.
#
#   sh spike/check-comment-only.sh <base-ref>    every src/*.zig that differs from <base-ref>
#   sh spike/check-comment-only.sh --selftest    the shapes this check must see red, and the one green
#
# Zig has line comments only, and every line of a multi-line string begins with `\\`, so a
# line whose first non-blank characters are `//` is a comment and nothing else can be — a
# plain diff does the whole job. Zero changed files is red, not green: a check that ran on
# nothing must not be told apart from one that passed.
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/comment-only-XXXXXX") || { echo "FAIL mktemp failed"; exit 1; }
trap 'case "${tmp:-}" in */comment-only-*) rm -rf "$tmp" 2>/dev/null ;; esac' EXIT INT TERM

# compare_pair <base-copy> <new-copy> <label>
# Returns 0 when only comment lines (and blank lines) were deleted; 1 when a line was added,
# rewritten or moved; 2 when a line that is not a comment was deleted. The two reds are kept
# apart so the selftest can tell that each half of the check is alive.
compare_pair() {
    diff "$1" "$2" >"$tmp/d"
    [ $? -le 1 ] || { echo "FAIL $3: diff could not compare the two copies"; return 2; }
    if grep '^>' "$tmp/d" | grep -vE '^>[[:space:]]*$' | grep -q .; then
        echo "FAIL $3: a line was added, rewritten or moved (the new copy has a line the base has not):"
        grep '^>' "$tmp/d" | grep -vE '^>[[:space:]]*$' | head -3 | sed 's/^/      /'
        return 1
    fi
    if grep '^<' "$tmp/d" | grep -vE '^<[[:space:]]*(//.*)?$' | grep -q .; then
        echo "FAIL $3: a line that is not a comment was deleted:"
        grep '^<' "$tmp/d" | grep -vE '^<[[:space:]]*(//.*)?$' | head -3 | sed 's/^/      /'
        return 2
    fi
    echo "ok   $3: $(grep -c '^<[[:space:]]*//' "$tmp/d") comment lines deleted, nothing else changed"
}

# require_files <newline-separated list>
require_files() {
    [ -n "$1" ] || { echo "FAIL no src/*.zig differs from the base — nothing was checked"; return 1; }
}

selftest() {
    d="$tmp/self"
    mkdir -p "$d"
    cat >"$d/base.zig" <<'EOF'
//! Module doc.
//! Second line.
const std = @import("std");

/// Doc for a.
/// Second doc line.
pub fn a() u32 {
    // a comment in the body
    return 1;
}

/// Doc for b.
pub fn b() []const u8 {
    return "http://x//y"; // a trailing comment stays
}

pub const text =
    \\line one
    \\line two
;
EOF
    cat >"$d/green.zig" <<'EOF'
const std = @import("std");

/// Doc for a.
pub fn a() u32 {
    return 1;
}

pub fn b() []const u8 {
    return "http://x//y"; // a trailing comment stays
}

pub const text =
    \\line one
    \\line two
;
EOF
    sed 's/return 1;/return 1 + 1;/' "$d/green.zig" >"$d/red-code.zig"
    sed 's#http://x//y#http://x/y#' "$d/green.zig" >"$d/red-string.zig"
    sed 's#/// Doc for a\.#/// Doc for a!#' "$d/green.zig" >"$d/red-reworded.zig"
    { cat "$d/green.zig"; echo "// appended"; } >"$d/red-appended.zig"
    awk '/\/\/\/ Doc for a\./ { held = $0; next } /^pub fn b/ { print held } { print }' "$d/green.zig" >"$d/red-moved.zig"
    sed '/return 1;/d' "$d/green.zig" >"$d/red-deleted-code.zig"
    sed '/\\\\line two/d' "$d/green.zig" >"$d/red-deleted-string-line.zig"

    failures=0
    total=0
    expect() {  # expect <green|added|deleted> <file> <label>
        total=$((total + 1))
        compare_pair "$d/base.zig" "$d/$2" "$3" >"$tmp/verdict"
        case $? in 0) got=green ;; 1) got=added ;; 2) got=deleted ;; *) got=other ;; esac
        if [ "$got" = "$1" ]; then
            echo "ok   selftest: $3 reads $got"
        else
            echo "FAIL selftest: $3 reads $got, expected $1"; sed 's/^/      /' "$tmp/verdict"; failures=$((failures + 1))
        fi
    }
    expect green green.zig "comment lines removed"
    expect added red-code.zig "a code token changed"
    expect added red-string.zig "a string literal changed"
    expect added red-reworded.zig "a kept doc comment reworded"
    expect added red-appended.zig "a comment line appended"
    expect added red-moved.zig "a doc comment moved onto another declaration"
    expect deleted red-deleted-code.zig "a code line deleted"
    expect deleted red-deleted-string-line.zig "a line of a multi-line string deleted"
    total=$((total + 1))
    if require_files "" >"$tmp/verdict"; then
        echo "FAIL selftest: zero changed files reads green"; failures=$((failures + 1))
    else
        echo "ok   selftest: zero changed files reads red"
    fi
    [ "$failures" -eq 0 ] || { echo "FAIL selftest: $failures of $total shapes did not read as expected"; exit 1; }
    echo "ok   selftest: $total shapes read as expected (1 green, the rest red)"
}

case "${1:-}" in
    --selftest) selftest; exit 0 ;;
    "") echo "usage: $0 <base-ref> | --selftest" >&2; exit 2 ;;
esac

base=$1
all=$(git -C "$root" diff --name-only "$base") \
    || { echo "FAIL git diff against '$base' failed — an unknown ref or a shallow clone, not a comment-only change"; exit 1; }
files=$(printf '%s\n' "$all" | grep '^src/.*\.zig$' || true)
others=$(printf '%s\n' "$all" | grep -v '^src/.*\.zig$' || true)
require_files "$files" || exit 1
if [ -n "$others" ]; then
    echo "note: changed outside src/*.zig, not checked here:"
    printf '%s\n' "$others" | sed 's/^/      /'
fi
mkdir -p "$tmp/base"
git -C "$root" archive "$base" -- src | tar -x -C "$tmp/base" \
    || { echo "FAIL could not read src/ at '$base'"; exit 1; }
rc=0
count=0
for f in $files; do
    count=$((count + 1))
    [ -f "$tmp/base/$f" ] || { echo "FAIL $f: not in $base (a new file is not a comment-only change)"; rc=1; continue; }
    compare_pair "$tmp/base/$f" "$root/$f" "$f" || rc=1
done
echo "checked $count file(s) against $base"
exit $rc
