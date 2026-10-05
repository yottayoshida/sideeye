#!/bin/sh
# Host side: one box per call of gate-all.sh (a pinned define needs its own, see gen-defines.py).
#   sh apparatus/gate.sh <name> [...]
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/entry-out"
exec docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/entry-out":/out sideeye-ud1005 sh /ap/gate-all.sh "$@"
