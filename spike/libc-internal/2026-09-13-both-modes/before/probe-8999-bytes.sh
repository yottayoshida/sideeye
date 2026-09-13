#!/bin/sh
# #541 plan probe: is dprintf judged under --observe syscalls? Run in sideeye-spike
# (gcc) with the engine at /se and the worktree at /wt (read-only).
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
echo "engine: $("$SE" --version 2>&1 | head -1)   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
echo "libc: $(ldd --version 2>&1 | head -1)   arch: $(uname -m)"
gcc -O0 -Wall -o /tmp/toy-libc-internal /wt/spike/toys/toy_mkstemp.c || { echo BROKEN; exit 2; }
gcc -O0 -Wall -o /tmp/big541 /ap/big541.c || { echo BROKEN; exit 2; }
echo "toy sha256: $(sha256sum /wt/spike/toys/toy_mkstemp.c | cut -d' ' -f1)"

echo "==================== plain strace: the writes dprintf issues ===================="
for m in small large; do
  rm -rf /tmp/pl && mkdir -p /tmp/pl && TOY_STATE=/tmp/pl/state /tmp/big541 init
  TOY_STATE=/tmp/pl/state strace -f -e trace=write -o /tmp/pl.strace /tmp/big541 $m
  echo "$m: $(grep -c 'write(3' /tmp/pl.strace) write(s) to fd 3: $(grep 'write(3' /tmp/pl.strace | sed 's/.*= //' | tr '\n' ' ')"
done

run() { # $1 mode, $2 binary, $3 member, $4 tag
  W=/tmp/w541 && rm -rf $W && mkdir -p $W/state
  export TOY_STATE=$W/state
  "$SE" explore --state $W/state --setup "$2 init" --operation "$2 $3" \
    --shim "$SHIM" --work $W/work --oracle /usr/bin/strace --observe "$1" > /tmp/out.txt 2>&1
  rc=$?
  echo "---- $4 / --observe $1: rc=$rc"
  head -1 /tmp/out.txt
  grep -E "crash point|oracle|explored" /tmp/out.txt | head -4
}
for mode in wrappers syscalls; do
  run $mode /tmp/toy-libc-internal dprintf "toy_mkstemp dprintf (the member measure-libc-internal.sh runs)"
  run $mode /tmp/big541 small "big541 small (12 bytes)"
  run $mode /tmp/big541 large "big541 large (8999 bytes)"
done
echo "==================== repeats: syscalls, large ===================="
for i in 1 2 3; do run syscalls /tmp/big541 large "repeat $i"; done
