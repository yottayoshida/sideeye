#!/bin/sh
# Build the #690 box. Stages this machine's proxy CA (empty when there is none), as
# spike/dogfood/2026-09-28-shipped-v170/apparatus/build.sh does, and builds sideeye-f690.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then
    cp "$CA_PEM" "$here/proxy-ca.pem"
    echo "build: staged the proxy CA from $CA_PEM" >&2
else
    : > "$here/proxy-ca.pem"
    echo "build: no CA at $CA_PEM; building with an empty one" >&2
fi
docker build -t sideeye-f690 "$here"
rm -f "$here/proxy-ca.pem"
