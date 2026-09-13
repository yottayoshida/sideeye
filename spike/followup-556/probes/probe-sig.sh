#!/bin/sh
# #556 same-class probe (the doors). Needs gcc: run in sideeye-spike, engine at /se.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
echo "engine: $("$SE" --version 2>&1 | head -1)   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
echo "libc: $(ldd --version 2>&1 | head -1)   arch: $(uname -m)"
gcc -O0 -Wall -o /tmp/sig556 /ap/sig556.c || { echo "BROKEN: compile"; exit 2; }
mkdir -p /s/plain
echo "==================== plain ===================="
/tmp/sig556 /s/plain
for m in wrappers syscalls; do
  mkdir -p /s/$m /wk/$m
  echo "==================== preflight --observe $m ===================="
  "$SE" preflight --state /s/$m --operation "/tmp/sig556 /s/$m" \
    --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work /wk/$m > /tmp/pf.$m.txt 2>&1
  echo "preflight rc=$?"
  grep -E " -> |^(UNKNOWN|PREFLIGHT)" /tmp/pf.$m.txt
done
