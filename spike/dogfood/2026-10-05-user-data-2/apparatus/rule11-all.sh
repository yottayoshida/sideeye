#!/bin/sh
# Rule 11 for every repository named, one at a time (never in parallel: 2026-10-03 broke six
# transcripts by running two loops against the search limit). Appends to one transcript.
#   sh rule11-all.sh <out> <owner/repo> [...]
here="$(cd "$(dirname "$0")" && pwd)"
out=$1; shift
for r in "$@"; do sh "$here/rule11.sh" "$r" >> "$out" 2>&1; echo >> "$out"; done
echo "rule11-all: done $(date -u +%FT%TZ)" >> "$out"
