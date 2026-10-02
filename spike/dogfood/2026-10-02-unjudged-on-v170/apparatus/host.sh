#!/bin/sh
# Host side of the 2026-10-02 unjudged-on-v170 run: the docker commands, one box per target.
#
#   sh host.sh <out dir> <target> [target ...]
#
# The box is `sideeye-uj170` (`Dockerfile` here): the 2026-09-28 box, which holds the released
# v1.7.0 installed by the page's installer, plus the tools of this run's targets. `run.sh` is
# the 2026-09-28 run's, unchanged: the page's command first, and a refusal's own next step
# followed when it names `--observe supervised` or `--observe syscalls`.
set -u
here=$(cd "$(dirname "$0")" && pwd); out=${1:?usage: host.sh <out dir> <target> [target ...]}; shift
[ $# -gt 0 ] || { echo "host.sh: name at least one target" >&2; exit 2; }
mkdir -p "$out"
docker image inspect sideeye-uj170 --format 'box sideeye-uj170 {{.Id}} created {{.Created}}'
for t in "$@"; do
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$here:/ap:ro" -v "$out:/out" sideeye-uj170 sh /ap/run.sh "$t" > "$out/$t.host.txt" 2>&1
    echo "$t: docker exit $? | $(tr '\n' '|' < "$out/$t/summary.txt" 2>/dev/null)"
done
