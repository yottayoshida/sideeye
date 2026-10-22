#!/bin/sh
set -u
scratch=$1 target=$2 campaign=$3 box=$4 proc=$5 define=$6
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; dogfood="$(dirname "$run")"
out="$scratch/$target-$(date +%s)"; rec="$run/transcripts/$target"
mkdir -p "$out" "$rec"
{
    echo "target $target  campaign $campaign  box $box-v1150  procedure $proc $define"
    docker image inspect "$box-v1150" --format 'box {{.Id}} created {{.Created}}'
    echo "start $(date -u +%FT%TZ)"
} > "$rec/host.txt"
# Not the campaign's host script: it mounts that campaign's own transcripts/ as /out.
docker run --rm --privileged --cgroupns=private --network none \
    -v "$dogfood/$campaign/apparatus":/ap:ro -v "$out":/out "$box-v1150" sh "/ap/$proc" "$define" \
    > "$rec/stdout.txt" 2>&1
echo "exit $?  end $(date -u +%FT%TZ)" >> "$rec/host.txt"
rsync -a --exclude 'work-*' "$out/" "$rec/"
