#!/bin/sh
# Host side of #947's measurement. Builds the box (once), then runs each target in a box of its own
# (logrotate's /etc/ld.so.preload must not ride on the next), with the state on a named volume —
# the Docker VM's own disk, not the container's overlay — and records the filesystem it is on.
#
#   sh host.sh <out-dir> <engine-dir> <label>
#
# <engine-dir> is a `zig build -Dtarget=aarch64-linux-gnu --prefix <engine-dir>`; <label> names it
# in the output (the commit it was built from).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out=${1:?out-dir}; eng=${2:?engine-dir}; label=${3:?label}
mkdir -p "$out/$label"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
docker image inspect sideeye-xattr947 > /dev/null 2>&1 || docker build -t sideeye-xattr947 "$here" > "$out/build.txt" 2>&1
docker run --rm sideeye-xattr947 cat /versions.txt > "$out/versions.txt"
for t in vim logrotate; do
    case $t in
    vim) ap="$root/spike/dogfood/2026-10-06-read-only-684/apparatus" ;;
    logrotate) ap="$root/spike/dogfood/2026-10-14-mechanisms/apparatus" ;;
    esac
    vol="sideeye-xattr947-$label-$t"
    docker volume rm -f "$vol" > /dev/null
    docker volume create "$vol" > /dev/null
    docker run --rm --privileged --cgroupns=private --network none \
        -v "$ap:/ap:ro" -v "$here:/x:ro" -v "$eng:/eng:ro" -v "$vol:/s" -v "$out/$label:/out" \
        sideeye-xattr947 sh /x/run.sh "$t" || true
    docker volume rm -f "$vol" > /dev/null
done
