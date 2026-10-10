#!/bin/sh
# Build the FAQ box. Stages this machine's TLS-intercepting proxy CA (empty when there is
# none) as spike/followup-690/build.sh does, builds sideeye-faq, and removes the CA again.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
cp "$here/../../../../docs/ci-quickstart/release/install-sideeye.sh" "$here/install-sideeye.sh"
docker build -t sideeye-faq "$here"
rm -f "$here/proxy-ca.pem" "$here/install-sideeye.sh"
