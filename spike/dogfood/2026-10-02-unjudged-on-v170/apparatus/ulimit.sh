#!/bin/sh
# Each FAIL's window entered without Sideeye and without a kill: the operation run once with
# `ulimit -f 0`, so the write after the truncating open fails. The size and the bytes before and
# after, the exit code, the last line the tool printed, and what is left in the directory. Run
# after the explores; not a prediction.
#
# The tool's output is taken through a command substitution — a pipe. The first version of this
# script sent it to a regular file inside the limited subshell, where the limit applies to the
# tool's own stdout as well: every "last line" came back empty, and an exit code could be the
# write to that file rather than the write to the target (the first review's finding; that
# version's output is kept as `transcripts/ulimit-first-attempt.txt`). The bytes are compared
# with a copy taken before the run, because a size alone cannot tell a file left as it was from
# one rewritten to the same length.
set -u
. /ap/env.sh
one() { # <define> <file, relative to the state root>
    d=/ap/defines/$1; f=$2
    sh "$d/seed.sh" > /dev/null 2>&1 || { echo "## $1: seed failed"; return; }
    state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
    op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
    cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml"); cwd=${cwd:-/}
    cp "$state/$f" /tmp/before.copy
    echo "## $1: $op"
    echo "before: $(wc -c < "$state/$f") bytes"
    out=$( ( cd "$cwd" && ulimit -f 0 && $op ) 2>&1 ); rc=$?
    echo "exit $rc: $(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep . | tail -1 | cut -c1-160)"
    if cmp -s "$state/$f" /tmp/before.copy; then same="the bytes it had before"; else same="not the bytes it had before"; fi
    echo "after:  $(wc -c < "$state/$f") bytes, $same; directory: $(ls -A "$(dirname "$state/$f")" | tr '\n' ' ')"
}
# The comparison seen both ways before it is trusted: a file left alone, and one rewritten to
# the same length.
printf 'abc\n' > /tmp/c1; cp /tmp/c1 /tmp/before.copy
cmp -s /tmp/c1 /tmp/before.copy && echo "control: an untouched file compares as the bytes it had before"
printf 'abd\n' > /tmp/c1
cmp -s /tmp/c1 /tmp/before.copy || echo "control: a same-length rewrite compares as not the bytes it had before"
one git-cliff CHANGELOG.md
one js-beautify a.js
one ktlint Main.kt
one ormolu A.hs
one oxfmt-071 a.js
one pg_format-511 a.sql
one php-cs-fixer-r1 a.php
