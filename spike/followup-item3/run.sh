#!/bin/sh
# Measure the shape of strace's wait lines under the engine's own flags.
set -eu
cd /w
mkdir -p state out
gcc -O0 -g -o out/serial serial.c
gcc -O0 -g -o out/conc conc.c
gcc -O0 -g -o out/sys sys.c
FLAGS="-f -y -e trace=%file,%desc,%process,setsid,setpgid"
for t in serial conc sys; do
    rm -rf state; mkdir -p state
    strace $FLAGS -o "out/$t.strace" "./out/$t" /w/state
    echo "=== $t: rc=$? files=$(ls state | tr '\n' ' ')"
done
echo "=== strace version ==="
strace --version | head -2
