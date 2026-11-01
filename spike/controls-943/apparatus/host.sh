#!/bin/sh
# Host side of #943's acceptance. Builds the box (once), then seeds the 2026-10-14 Alembic define as
# that run did and runs `sideeye preflight --config` on this directory's copy, which declares the
# run's four controls.
#
#   sh host.sh <out-dir> <engine-dir>
#
# <engine-dir> is a `zig build -Dtarget=aarch64-linux-gnu --prefix <engine-dir>`.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out=${1:?out-dir}; eng=${2:?engine-dir}
mkdir -p "$out"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
docker image inspect sideeye-controls943 > /dev/null 2>&1 || docker build -t sideeye-controls943 "$here" > "$out/build.txt" 2>&1
docker run --rm sideeye-controls943 cat /versions.txt > "$out/versions.txt"
docker run --rm --privileged --cgroupns=private --network none \
    -v "$root/spike/dogfood/2026-10-14-mechanisms/apparatus:/ap:ro" -v "$here:/x:ro" -v "$eng:/eng:ro" -v "$out:/out" \
    sideeye-controls943 sh /x/run.sh
