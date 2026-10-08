#!/bin/sh
# What mogrify writes into a PNG's date and time chunks (#690), inside sideeye-f690:
#   docker run --rm --network none -v "$PWD":/ap:ro sideeye-f690 sh /ap/date-chunks.sh
# The input is made, then two seconds later its modification time is set far in the past —
# which moves its change time (ctime) to that moment. Reading the output's chunks back says
# which of the input's times each date chunk copies, and where each chunk sits.
set -eu
d=$(mktemp -d)
cd "$d"
ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y a.png
echo "input made:    $(date -u +%FT%T)"
sleep 2
touch -d "2020-01-02 03:04:05" a.png
echo "after touch:   mtime $(stat -c %y a.png | cut -c1-19)  ctime $(stat -c %z a.png | cut -c1-19)"
sleep 2
mogrify -resize 50% a.png
echo "output made:   $(date -u +%FT%T)"
python3 - a.png <<'EOP'
import struct, sys
b = open(sys.argv[1], "rb").read()
i = 8
while i < len(b):
    n = struct.unpack(">I", b[i:i + 4])[0]
    t = b[i + 4:i + 8].decode()
    d = b[i + 8:i + 8 + n]
    if t == "tEXt":
        print("offset %3d %s %s" % (i, t, d.replace(b"\x00", b"=").decode()))
    elif t == "tIME":
        print("offset %3d %s %04d-%02d-%02dT%02d:%02d:%02d (seconds byte at offset %d)" % ((i, t) + struct.unpack(">HBBBBB", d) + (i + 8 + 6,)))
    else:
        print("offset %3d %s (%d bytes)" % (i, t, n))
    i += 12 + n
print("file length %d" % len(b))
EOP
