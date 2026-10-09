#!/bin/sh
# Build the 2026-10-10 box (copied from 2026-10-09 follow-ups 3's build.sh: the same CA staging
# and the same check that the vendored installer is the page's).
#   sh build.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; echo "build: staged the proxy CA from $CA_PEM" >&2
else : > "$here/proxy-ca.pem"; echo "build: no CA at $CA_PEM; building with an empty one" >&2; fi
page="$root/docs/ci-quickstart/release/install-sideeye.sh"
cp "$page" "$here/install-sideeye.sh"
c=$(git -C "$root" show v1.10.0:docs/ci-quickstart/release/install-sideeye.sh | shasum -a 256 | cut -d' ' -f1)
b=$(shasum -a 256 "$here/install-sideeye.sh" | cut -d' ' -f1)
echo "build: vendored install-sideeye.sh sha256 $b; at tag v1.10.0 $c" >&2
docker build -t sideeye-dx1010 "$here"
