#!/bin/sh
# Each FAIL's window entered without Sideeye and without a kill: the operation run once with
# `ulimit -f 0`, so the write after the truncating open fails. Sizes before and after, the exit
# code, and what is left in the directory. Run after the explores; not a prediction.
set -u
one() { # <define> <file, relative to the state root>
    d=/ap/defines/$1; f=$2
    sh "$d/seed.sh" > /dev/null 2>&1 || { echo "## $1: seed failed"; return; }
    state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
    op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
    cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml"); cwd=${cwd:-/}
    echo "## $1: $op"
    echo "before: $(wc -c < "$state/$f") bytes"
    ( cd "$cwd" && ulimit -f 0 && $op ) > /tmp/ulimit.out 2>&1
    echo "exit $?: $(tail -1 /tmp/ulimit.out | cut -c1-160)"
    echo "after:  $(wc -c < "$state/$f") bytes; directory: $(ls -A "$(dirname "$state/$f")" | tr '\n' ' ')"
}
one alejandra-r1 a.nix
one biome a.js
one gofumpt-r1 main.go
one helm-r1 cfg/repositories.yaml
one jsonnetfmt-r1 a.jsonnet
one ktfmt a.kt
one oxfmt a.js
one pg_format a.sql
one pint a.php
one scalafmt a.scala
one tombi-r1 a.toml
one yamlfmt-r1 a.yaml
one rumdl-nocache a.md
