#!/bin/sh
# Lab 2: Exiv2 PR #9504's window reproduced without Sideeye — strace kills exiv2 at the rename that
# follows the remove of the picture (the order replaceFileAtomically has on everything but Windows).
# The control (Debian's 0.28.5) gets the same treatment at its first write, the report's window.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-2.sh
set -u
mk() { rm -rf /tmp/ex && mkdir -p /tmp/ex && cd /tmp/ex && ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y pic1.jpg && exiv2 -M"set Exif.Image.Artist probe" pic1.jpg && ls -l; }
echo "## PR #9504 (exiv2 $(exiv2-pr --version | head -1 | cut -c7-))"
mk
strace -f -qq -o /tmp/pr.strace -P "$PWD/pic1.jpg" -e trace=openat,unlinkat,renameat,renameat2 -e inject=renameat,renameat2:signal=KILL \
  exiv2-pr rm "$PWD/pic1.jpg"; echo "exiv2-pr exit $?"
cat /tmp/pr.strace
ls -l /tmp/ex
for f in /tmp/ex/*; do echo "$f: $(identify "$f" 2>&1 | cut -c1-80)"; done
echo "## Debian's exiv2 0.28.5, the report's window"
mk
strace -f -qq -o /tmp/deb.strace -P "$PWD/pic1.jpg" -e trace=openat,write -e inject=write:signal=KILL \
  exiv2 rm "$PWD/pic1.jpg"; echo "exiv2 exit $?"
grep -v ENOENT /tmp/deb.strace | head -4
ls -l /tmp/ex
