#!/bin/sh
# spike/platforms/wsl2-inner.sh — the WSL2 leg of the platform probe (#697, ADR 0105), run as
# root inside the Ubuntu 24.04 distribution that .github/workflows/spike-platforms.yml imports
# on a Windows runner. The checkout is reached through /mnt (the Windows drive); the engine and
# the state go on the distribution's own filesystem, so what is measured is WSL2's ext4 and
# not the Windows drive. SIDEEYE_VERSION and GH_TOKEN arrive through WSLENV.
#
#   SIDEEYE_VERSION=v1.10.0 sh spike/platforms/wsl2-inner.sh <out dir>
set -u

out=${1:?usage: SIDEEYE_VERSION=<tag> wsl2-inner.sh <out dir>}
V=${SIDEEYE_VERSION:?set SIDEEYE_VERSION to the release tag to measure}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$out"

{ uname -r; cat /proc/version; } > "$out/wsl2-kernel.txt"
export DEBIAN_FRONTEND=noninteractive
{ apt-get update -qq && apt-get install -y -qq strace python3 curl ca-certificates; } > "$out/wsl2-apt.txt" 2>&1 || {
    echo "wsl2: packages could not be installed"; tail -5 "$out/wsl2-apt.txt"; exit 1
}
bin=$(sh "$root/docs/ci-quickstart/release/install-sideeye.sh" "$V" /opt/sideeye 2> "$out/wsl2-install.txt") || {
    echo "wsl2: the engine could not be installed"; cat "$out/wsl2-install.txt"; exit 1
}
mkdir -p /s
sh "$here/measure.sh" "$bin" "$out" wsl2
[ "$(grep -c . "$out/wsl2/summary.txt" 2>/dev/null)" = 3 ] || { echo "wsl2: no complete record"; exit 1; }
