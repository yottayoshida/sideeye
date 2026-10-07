#!/bin/sh
# Lab 12 (2026-10-07 user-data-3): sndfile-metadata-set killed at each crash point by the report's own
# reproduce line (LD_PRELOAD the shim, SIDEEYE_KILL_AT=<k>), then its a.wav read by inspect-wav.py and by
# sndfile-info. Crash point 3 is the explore's earliest exhibit.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-12.sh > transcripts/lab-12.txt 2>&1
set -u
. /ap/env.sh
SE=$(cat /install.path); SHIM=$(dirname "$SE")/libsideeye_shim.so; d=/ap/defines/sndfile
for k in 1 2 3; do
  echo "=== killed at crash point $k"
  cd /; sh $d/seed.sh; cd /s/snd-in
  SIDEEYE_STATE_DIR=/s/snd SIDEEYE_TRACE_PATH=/tmp/trace-$k.bin LD_PRELOAD=$SHIM SIDEEYE_KILL_AT=$k SIDEEYE_SEQ_BASE= \
    sndfile-metadata-set --str-comment edited /s/snd/a.wav < /dev/null; echo "  exit $?"
  /opt/py/bin/python -I /ap/inspect-wav.py /s/snd/a.wav | sed 's/^/  /'
  sndfile-info /s/snd/a.wav 2>&1 | grep -iE "frames|error|warning|length|riff|data :|duration" | head -8 | sed 's/^/  info: /'
  sndfile-convert /s/snd/a.wav /tmp/out-$k.wav > /tmp/conv.log 2>&1; echo "  sndfile-convert exit $? ($(head -c 120 /tmp/conv.log | tr '\n' ' '))"
  [ -f /tmp/out-$k.wav ] && /opt/py/bin/python -I /ap/inspect-wav.py /tmp/out-$k.wav | grep -E "data|file" | sed 's/^/  converted: /'
done
