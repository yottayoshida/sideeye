#!/bin/sh
# Lab 11 (2026-10-07 user-data-3): what sndfile-metadata-set's crashed WAV holds. The define is explored
# again with an inspector declared as its recovery (inspect-wav.py), so each saved FAIL world's state is
# read as the crash left it; and the inspector reads the seeded file and the completed run's file too.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-11.sh > transcripts/lab-11.txt 2>&1
set -u
. /ap/env.sh
SE=$(cat /install.path); d=/ap/defines/sndfile
echo "=== the seeded file"; sh $d/seed.sh; /opt/py/bin/python -I /ap/inspect-wav.py /s/snd/a.wav
echo "=== after a completed run"; sh $d/seed.sh; cd /s/snd-in && sndfile-metadata-set --str-comment edited /s/snd/a.wav < /dev/null; /opt/py/bin/python -I /ap/inspect-wav.py /s/snd/a.wav
echo "=== each crashed world, through [recovery] (defines/sndfile-lab11)"
cd /; sh $d/seed.sh
"$SE" explore --config /ap/defines/sndfile-lab11/sideeye.toml --oracle /usr/bin/strace --work /tmp/w11 2>&1 | cut -c1-200
