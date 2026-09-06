#!/bin/sh
mkdir -p /work/st/fl
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do
  flac -s -f /tmp/src.wav -o "/work/st/fl/$n.flac"
  metaflac --set-tag=ORIG=keep "/work/st/fl/$n.flac"
done
