#!/bin/sh
# Build a deterministic source tree for genisoimage to read.
set -e
here=$(cd "$(dirname "$0")" && pwd)
st="$here/state"
rm -rf "$st"
mkdir -p "$st/src/sub" "$st/src/docs"
i=0
while [ $i -lt 6 ]; do
    # deterministic bytes, no /dev/urandom
    yes "payload-line-$i-0123456789abcdef" 2>/dev/null | head -c 120000 > "$st/src/f$i.bin"
    i=$((i+1))
done
printf "note\n"    > "$st/src/sub/note.txt"
printf "readme\n"  > "$st/src/docs/readme.txt"
# pin mtimes so the source tree is byte- and metadata-stable
find "$st/src" -exec touch -t 202001010000.00 {} +
"$here/check.py" --record
