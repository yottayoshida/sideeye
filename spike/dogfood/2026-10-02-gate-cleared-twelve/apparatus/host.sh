#!/bin/sh
# Host side of the 2026-10-02 gate-cleared-twelve run: the docker commands, one box per target.
#
#   sh host.sh <out dir> [target ...]        (default: the twelve)
#
# The box is `sideeye-sv170`, the image the 2026-09-28 shipped-v170 run built
# (`../../2026-09-28-shipped-v170/apparatus/build.sh` and `Dockerfile`): the released v1.7.0
# installed by the page's installer, and every tool at the version that run pinned. It is not
# rebuilt here. `run.sh` and the defines are that run's, copied unchanged.
set -u
here=$(cd "$(dirname "$0")" && pwd); out=${1:?usage: host.sh <out dir> [target ...]}; shift
[ $# -gt 0 ] || set -- alejandra biome gofumpt helm jsonnetfmt ktfmt oxfmt pg_format pint scalafmt tombi yamlfmt
mkdir -p "$out"
docker image inspect sideeye-sv170 --format 'box sideeye-sv170 {{.Id}} created {{.Created}}'
for t in "$@"; do
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$here:/ap:ro" -v "$out:/out" sideeye-sv170 sh /ap/run.sh "$t" > "$out/$t.host.txt" 2>&1
    echo "$t: docker exit $? | $(tr '\n' '|' < "$out/$t/summary.txt" 2>/dev/null)"
done
