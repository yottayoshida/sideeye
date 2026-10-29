#!/bin/sh
# Build the box (sideeye-r1029). The proxy CA is staged as 2026-10-25's build.sh stages it: copied from
# CA_PEM when the file is there, an empty file otherwise (no interception assumed). It stays out of git.
#
#   sh build.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
docker build -t sideeye-r1029 "$here"
docker run --rm sideeye-r1029 cat /versions.txt
