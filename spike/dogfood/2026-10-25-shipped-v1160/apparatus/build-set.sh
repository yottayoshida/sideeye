#!/bin/sh
# One box per set, so the four sets build and run side by side: sets/<N>/Dockerfile starts
# `FROM sideeye-sv1025` (build.sh's base: the engine and the devices) and adds that set's tools.
#   sh build-set.sh <N>        # builds sideeye-sv1025-s<N>
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
n=${1:?usage: build-set.sh <N>}
docker build -t "sideeye-sv1025-s$n" "$here/sets/$n"
docker run --rm "sideeye-sv1025-s$n" cat /versions.txt
