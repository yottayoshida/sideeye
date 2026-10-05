#!/bin/sh
# One target's explore outcome in a few lines: the summary, the consequence table and where it stopped.
#   sh apparatus/evsum.sh <target>
d="$(cd "$(dirname "$0")/.." && pwd)/transcripts/explore/$1"
echo "======== $1"; cat "$d/summary.txt"; for l in explore syscalls supervised; do [ -f "$d/$l.replay.txt" ] && cat "$d/$l.replay.txt"; done
for l in explore syscalls supervised; do
  f="$d/$l.evidence.md"; [ -s "$f" ] || continue
  sed -n '/^## Consequence/,/^`Old bytes/p' "$f" | grep '^| `'
  sed -n '/^## Where it was interrupted/,/^```$/p' "$f" | sed -n '3,7p' | tr -s ' ' | tr '\n' ' '; echo
done
