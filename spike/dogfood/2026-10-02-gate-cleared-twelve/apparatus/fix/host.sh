#!/bin/sh
# Host side of the two upstream fixes measured on 2026-10-02: the docker commands.
#
#   sh host.sh <dir holding src-<tool>-<base|fix>> <out dir>
#
# src-codespell-base  codespell-project/codespell at d15559f7 (the parent of the fix)
# src-codespell-fix   ... at 68804d2f (codespell-project/codespell#4028, merged 2026-09-21)
# src-rubocop-base    rubocop/rubocop at 0d7a2163e (the parent of the fix)
# src-rubocop-fix     ... at b39e7f467 (rubocop/rubocop#15721, merged 2026-09-16)
#
# Each tree is run from source, read-only on /src, in the `sideeye-sv170` box: codespell as
# `python3 -m codespell_lib` with PYTHONPATH=/src (both trees given the same one-line
# `codespell_lib/_version.py`, which the build normally generates), RuboCop as
# `ruby /src/exe/rubocop` against the box's installed gems. Neither is a release.
set -u
here=$(cd "$(dirname "$0")/.." && pwd); src=${1:?usage: host.sh <src dir> <out dir>}; out=${2:?}
mkdir -p "$out"
for t in codespell rubocop; do
    for w in base fix; do
        mkdir -p "$out/$t-$w"
        docker run --rm --privileged --cgroupns=private --network none -e PYTHONPATH=/src \
            -v "$here:/ap:ro" -v "$src/src-$t-$w:/src:ro" -v "$out/$t-$w:/out" \
            sideeye-sv170 sh /ap/fix/measure.sh "$t" > "$out/$t-$w.txt" 2>&1
        echo "$t-$w: docker exit $? | $(grep '^explore exit' "$out/$t-$w.txt")"
    done
done
