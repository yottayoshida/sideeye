#!/bin/sh
# Per-call cost of the per-thread slot (item 4). Runs in the acceptance image; the v15
# shim is the one built from `7a2d443` and mounted at /v15, the v16 one at /se.
set -u
N=${N:-200000}
gcc -O2 -o /tmp/bench /hostap/bench.c
mkdir -p /tmp/bstate
export SIDEEYE_STATE_DIR=/tmp/bstate SIDEEYE_TRACE_PATH=/tmp/btrace.bin
run() { # run <label> <shim or ->
  label=$1; shim=$2
  for i in 1 2 3 4 5 6 7; do
    rm -f /tmp/btrace.bin
    s=$(date +%s%N)
    if [ "$shim" = "-" ]; then /tmp/bench "$N"; else LD_PRELOAD="$shim" /tmp/bench "$N"; fi
    e=$(date +%s%N)
    echo $(( (e - s) / 1000 ))
  done | sort -n | awk -v l="$label" -v n="$N" 'BEGIN{c=0}{v[c++]=$1}END{med=v[int(c/2)]; printf "%-12s median %8d us over %d iterations = %.3f us per open+close pair\n", l, med, n, med/n}'
}
run "no shim"  -
run "v15 shim" /v15/lib/libsideeye_shim.so
run "v16 shim" /se/lib/libsideeye_shim.so
