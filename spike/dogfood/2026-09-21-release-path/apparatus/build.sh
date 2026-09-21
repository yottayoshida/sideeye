#!/bin/sh
# Build the run image, which is where the adoption step under test happens.
#
#   sh build.sh                       # needs a network; the explores do not
#
# The corporate proxy's CA is staged next to the Dockerfile because Docker Desktop will not share
# /Library, and it is **not committed**: it is this machine's network configuration, not this
# project's. On a machine with no interception, point CA_PEM at any CA bundle or an empty file —
# the install step simply has nothing extra to trust.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}

if [ -f "$CA_PEM" ]; then
    cp "$CA_PEM" "$here/proxy-ca.pem"
    echo "build: staged the proxy CA from $CA_PEM" >&2
else
    : > "$here/proxy-ca.pem"
    echo "build: no CA at $CA_PEM; building with an empty one (no interception assumed)" >&2
fi

# The vendored copy is refreshed from the page's own script and then held to it. A copy that
# drifts would make this run's whole claim — "we ran the script the quickstart tells a project to
# copy" — quietly false, and a record cannot check that about itself after the fact.
src="$here/../../../../docs/ci-quickstart/release/install-sideeye.sh"
cp "$src" "$here/install-sideeye.sh"
a=$(shasum -a 256 "$src" | cut -d' ' -f1)
b=$(shasum -a 256 "$here/install-sideeye.sh" | cut -d' ' -f1)
[ "$a" = "$b" ] || { echo "build: the vendored installer is not the page's ($a vs $b)" >&2; exit 1; }
echo "build: vendored install-sideeye.sh matches the page's, sha256 $a" >&2

docker build -t sideeye-relpath "$here"
echo "build: sideeye-relpath ready; the install log is /install.log and its stdout /install.path" >&2
