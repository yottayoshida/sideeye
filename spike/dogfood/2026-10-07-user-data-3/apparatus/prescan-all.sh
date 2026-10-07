#!/bin/sh
# Rule 14's novelty pre-scan (spike/cohort4/novelty-prescan.sh) on each tracker named, ONE AT A TIME:
# 2026-10-03 ran two loops in parallel and broke six transcripts on the search rate limit. A
# transcript that does not end with the scan's own controls green is kept as `.broken` and the
# tracker re-run once at the end of the list.
#   sh prescan-all.sh <owner/repo> [...]
here="$(cd "$(dirname "$0")" && pwd)"; run="$(dirname "$here")"; root="$(cd "$here/../../../.." && pwd)"
out="$run/transcripts/receipts"; mkdir -p "$out"
retry=""
scan() {
    f="$out/$(echo "$1" | tr / _).prescan.txt"
    echo "prescan start $1 $(date -u +%FT%TZ)"
    sh "$root/spike/cohort4/novelty-prescan.sh" "$1" > "$f" 2>&1; rc=$?
    echo "prescan end   $1 $(date -u +%FT%TZ) rc=$rc"
    return $rc
}
for r in "$@"; do
    scan "$r" || { mv "$out/$(echo "$r" | tr / _).prescan.txt" "$out/$(echo "$r" | tr / _).prescan.txt.broken"; retry="$retry $r"; }
done
for r in $retry; do scan "$r"; done
echo "prescan-all: done $(date -u +%FT%TZ)"
