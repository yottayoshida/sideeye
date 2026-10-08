#!/bin/sh
# The host side of #690: one box per target, the way the recorded rows ran theirs
# (`--privileged --cgroupns=private` so --observe supervised can make its cgroups;
# no network). The engine is the tree at <se>, built for aarch64-linux with -Dtrace-ops.
# usage: host.sh <se tree> <out dir> [target...]   (targets: tombi mogrify isort dotter)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
se=$1
out=$2
shift 2
[ $# -gt 0 ] || set -- tombi mogrify isort dotter
mkdir -p "$out"
for t in "$@"; do
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$se":/se:ro -v "$here":/ap:ro -v "$out":/out sideeye-f690 sh /ap/run.sh "$t"
done
