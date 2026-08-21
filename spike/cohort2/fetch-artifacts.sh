#!/bin/sh
# Fetch the pinned release artifacts the cohort-2 image copies in
# (see Dockerfile). This runs on the HOST, not in the container: the
# development machine sits behind a TLS-intercepting proxy whose CA the
# host trusts but a stock Debian container does not: in-container pip
# failed certificate verification (measured 2026-08-21, first image
# build), and in-container curl shares the same trust store (inference —
# curl was dropped from the image rather than measured). Moving the
# downloads host-side keeps the corporate CA out of the
# image and the repository; the pins below and the Dockerfile's own
# re-verification keep the build honest anywhere else.
#
# Pins: mercurial from PyPI's published sha256 for the 7.2.4 sdist; bun
# from upstream's SHASUMS256.txt for bun-v1.4.0; jj measured from the
# 2026-08-21 download of v0.44.0 (upstream ships no checksum asset — a
# first-download pin, stated as such).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
dest="$here/artifacts"
mkdir -p "$dest"

sum() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
    else shasum -a 256 "$1"; fi
}

fetch() {
    name=$1; url=$2; want=$3
    out="$dest/$name"
    if [ -f "$out" ]; then
        got=$(sum "$out" | cut -d' ' -f1)
        [ "$got" = "$want" ] && { echo "ok   $name (cached)"; return 0; }
        echo "stale $name: checksum mismatch, refetching" >&2
        rm -f "$out"
    fi
    curl -fsSL -o "$out" "$url"
    got=$(sum "$out" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { echo "FAIL $name: sha256 $got, wanted $want" >&2; rm -f "$out"; exit 1; }
    echo "ok   $name"
}

fetch mercurial-7.2.4.tar.gz \
    "https://files.pythonhosted.org/packages/source/m/mercurial/mercurial-7.2.4.tar.gz" \
    85839e0f39e6cb893a88932aa36ef661759f3c5c5de4551ad26bd9df53cb71a2

fetch jj-v0.44.0-aarch64-unknown-linux-musl.tar.gz \
    "https://github.com/jj-vcs/jj/releases/download/v0.44.0/jj-v0.44.0-aarch64-unknown-linux-musl.tar.gz" \
    60d42fa2a9abaa445eff10cd2087458562aaad5a54b90309e5a3787ecc985ff2

fetch bun-linux-aarch64.zip \
    "https://github.com/oven-sh/bun/releases/download/bun-v1.4.0/bun-linux-aarch64.zip" \
    4b1a332ee861983eb93bcfe6f770fff94e3e31b2c388bdaea3c8ed35e58eed0e

echo "artifacts ready in $dest"
