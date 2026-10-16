#!/bin/sh
# build.sh <package=version>: builds the box image for one target and prints its id.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel)
pkg=${1:?usage: build.sh <package=version>}
CA_PEM=${CA_PEM:-/Library/Application Support/Netskope/STAgent/data/nscacert.pem}
if [ -f "$CA_PEM" ]; then cp "$CA_PEM" "$here/proxy-ca.pem"; else : > "$here/proxy-ca.pem"; fi
mkdir -p "$here/v1.13.0/docs"
# Not the working tree's documents: they move after the tag, and the subject is measured on v1.13.0's.
git -C "$root" show v1.13.0:README.md > "$here/v1.13.0/README.md"
for d in cli checker-cookbook apparatus; do
    git -C "$root" show "v1.13.0:docs/$d.md" > "$here/v1.13.0/docs/$d.md"
done
cp "$here/../watch-defines.py" "$here/watch-defines.py"
docker build -q --build-arg "TARGET_PKG=$pkg" "$here"
