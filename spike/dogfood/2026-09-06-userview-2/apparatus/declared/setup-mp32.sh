#!/bin/sh
mkdir -p /work/st/m3
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do
  lame --quiet /tmp/src.wav "/work/st/m3/$n.mp3"
  mid3v2 --TXXX "ORIG:keep" "/work/st/m3/$n.mp3"
done
