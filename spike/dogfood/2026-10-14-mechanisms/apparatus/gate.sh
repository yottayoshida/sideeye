#!/bin/sh
# Host side: one box per call of gate-all.sh (a pinned define needs its own: its env.sh writes /etc/ld.so.preload).
#   sh apparatus/gate.sh <name> [...]
# Copied from 2026-10-12 shipped-v1120 with one change: every call first prints the sha256 of
# CANDIDATES.md, so each gate transcript shows the order and the invariants it ran against were the
# committed ones (#861).
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"
mkdir -p "$run/transcripts/entry-out"
echo "CANDIDATES.md sha256 $(shasum -a 256 "$run/CANDIDATES.md" | cut -d' ' -f1) at $(date -u +%FT%TZ) for: $*" | tee -a "$run/transcripts/entry-out/candidates.sha256"
exec docker run --rm --privileged --cgroupns=private --network none -v "$here":/ap:ro -v "$run/transcripts/entry-out":/out sideeye-m1014 sh /ap/gate-all.sh "$@"
