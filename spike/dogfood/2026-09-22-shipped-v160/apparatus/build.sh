#!/bin/sh
# Build the box for the 2026-09-22 shipped-v160 run.
#
#   sh build.sh
#
# Copied from the verdict-chain run's build.sh, with the installer checked against BOTH
# places it lives: the working tree's copy of the page's file, and the file as it stood at
# the v1.6.0 tag. The two are the same bytes today; a run that records only one of them
# cannot say which one it installed with once they differ.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"

CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then
    cp "$CA_PEM" "$here/proxy-ca.pem"
    echo "build: staged the proxy CA from $CA_PEM" >&2
else
    : > "$here/proxy-ca.pem"
    echo "build: no CA at $CA_PEM; building with an empty one (no interception assumed)" >&2
fi

page="$root/docs/ci-quickstart/release/install-sideeye.sh"
cp "$page" "$here/install-sideeye.sh"
a=$(shasum -a 256 "$page" | cut -d' ' -f1)
b=$(shasum -a 256 "$here/install-sideeye.sh" | cut -d' ' -f1)
c=$(git -C "$root" show v1.6.0:docs/ci-quickstart/release/install-sideeye.sh | shasum -a 256 | cut -d' ' -f1)
[ "$a" = "$b" ] || { echo "build: the vendored installer is not the page's ($a vs $b)" >&2; exit 1; }
echo "build: vendored install-sideeye.sh  sha256 $b" >&2
echo "build: the page's (working tree)    sha256 $a" >&2
echo "build: the page's at tag v1.6.0     sha256 $c" >&2
[ "$a" = "$c" ] || echo "build: NOTE the page's installer has moved since v1.6.0" >&2

docker build -t sideeye-sv "$here"
echo "build: sideeye-sv ready; the install log is /install.log, its stdout /install.path, the tools /versions.txt" >&2
