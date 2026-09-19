#!/bin/sh
# A synthetic target for the rehearsal only (#618). Not a package; not one of the four.
#
# It keeps two things in one directory, which is the shape the rehearsal needs:
#
#   notes.txt   the durable record. Appended to, and the tool's contract is about its contents.
#   .index      a derived index of line counts, rebuilt from notes.txt whenever it is missing.
#
# Usage: synthetic-target.sh <state-dir> <text>
set -eu
dir=${1:?state dir}; text=${2:?text}
mkdir -p "$dir"
tmp="$dir/.notes.tmp"
cp "$dir/notes.txt" "$tmp" 2>/dev/null || : > "$tmp"
printf '%s\n' "$text" >> "$tmp"
mv "$tmp" "$dir/notes.txt"          # the durable write, old-or-new by rename
wc -l < "$dir/notes.txt" > "$dir/.index"   # the derived index, rebuilt on demand
