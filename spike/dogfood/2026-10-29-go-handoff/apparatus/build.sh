#!/bin/sh
# Build the box for #987's measurement (sideeye-gh1029). The proxy CA staged as 2026-10-25's build.sh
# stages it; Gogs's app.ini taken from 2026-10-25 set 2, where it is committed.
#   sh build.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
cp "$here/../../2026-10-25-shipped-v1160/apparatus/sets/2/gogs-app.ini" "$here/gogs-app.ini"
docker build -t sideeye-gh1029 "$here"
