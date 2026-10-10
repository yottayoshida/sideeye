#!/bin/sh
# Builds the box. The proxy CA is staged the way the 2026-10-07 run staged it: on the machine this ran
# on, TLS out of a container passes through an intercepting proxy, and without its CA every download
# fails. Where there is no such CA an empty one is staged and nothing is assumed intercepted.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then
    cp "$CA_PEM" "$here/proxy-ca.pem"
    echo "build: staged the proxy CA from $CA_PEM" >&2
else
    : > "$here/proxy-ca.pem"
    echo "build: no CA at $CA_PEM; building with an empty one (no interception assumed)" >&2
fi
docker build -t sideeye-rm678 "$here"
rm -f "$here/proxy-ca.pem"
