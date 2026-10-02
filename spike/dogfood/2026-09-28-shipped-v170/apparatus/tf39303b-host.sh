#!/bin/sh
# Host side of the 2026-10-02 re-measurement of hashicorp/terraform#39303 (head 28a34e9b8, base
# its merge-base with main e3b5fc125). The 2026-09-29 measurement kept its box scripts and not
# the docker commands that ran them; this file is those commands.
#
#   sh tf39303b-host.sh <dir holding terraform-base and terraform-pr> <out dir>
#
# Both binaries are built the same way from a checkout of each commit:
#   CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o terraform-<base|pr> .
# Each is bind-mounted over /opt/bin/terraform in the sideeye-sv170 box (build.sh), which is
# privileged with its own cgroup namespace and has no network, as run.sh's header says.
# Colour escapes are stripped from what is kept; nothing else is edited.
set -u
here=$(cd "$(dirname "$0")" && pwd); bins=$1; out=$2
esc=$(printf '\033')
mkdir -p "$out"
box() {
    w=$1; name=$2; shift 2
    mkdir -p "$out/work-$name-$w"
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$here:/ap:ro" -v "$bins/terraform-$w:/opt/bin/terraform:ro" \
        -v "$out/work-$name-$w:/out" sideeye-sv170 "$@" > "$out/$name-$w.raw" 2>&1
    rc=$?
    sed "s/${esc}\[[0-9;]*m//g" "$out/$name-$w.raw" > "$out/$name-$w.txt"
    echo "$name-$w: docker exit $rc"
}
for w in base pr; do
    shasum -a 256 "$bins/terraform-$w"
    box "$w" probe sh /ap/tf39303-probe.sh
    box "$w" wrong sh /ap/tf39303-wrong.sh
    box "$w" supervised sh /ap/tf39303b-supervised.sh terraform
    box "$w" shrink sh /ap/tf39303b-supervised.sh terraform-shrink
done
for w in base pr; do box "$w" kill sh /ap/tf39303b-kill.sh; done
