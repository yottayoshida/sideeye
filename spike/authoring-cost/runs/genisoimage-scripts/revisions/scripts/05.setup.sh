#!/bin/sh
# State for the realistic case: regenerating an image over last week/s image.
#   state/src      the tree genisoimage reads (must come back untouched)
#   state/out.iso  a PREVIOUS image already sitting at the output path
set -e
here=$(cd "$(dirname "$0")" && pwd)
st="$here/state"
rm -rf "$st" "$here/old.tree"
mkdir -p "$st/src/sub" "$st/src/docs"
i=0
while [ $i -lt 6 ]; do
    yes "payload-line-$i-0123456789abcdef" 2>/dev/null | head -c 120000 > "$st/src/f$i.bin"
    i=$((i+1))
done
printf "note\n"   > "$st/src/sub/note.txt"
printf "readme\n" > "$st/src/docs/readme.txt"

# The previous image: different content AND larger than the new one, so a
# surviving old tail cannot hide behind the new image/s length.
mkdir -p "$here/old.tree"
j=0
while [ $j -lt 9 ]; do
    yes "OLD-RELEASE-$j-fedcba9876543210" 2>/dev/null | head -c 160000 > "$here/old.tree/old$j.bin"
    j=$((j+1))
done
/usr/bin/genisoimage -quiet -V PREVIOUS -o "$st/out.iso" "$here/old.tree"
rm -rf "$here/old.tree"

find "$st" -exec touch -t 202001010000.00 {} +
"$here/check.py" --record
