#!/bin/sh
# Same-class probe for #556 (posix_spawn file actions). Needs gcc: run in sideeye-spike.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
echo "engine: $("$SE" --version 2>&1 | head -1)   shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
echo "libc: $(ldd --version 2>&1 | head -1)"
gcc -O0 -Wall -o /tmp/spawn556 /ap/spawn556.c || { echo "BROKEN: compile"; exit 2; }
mkdir -p /s/plain
echo "==================== plain ===================="
/tmp/spawn556 /s/plain
for m in wrappers syscalls; do
  mkdir -p /s/$m /wk/$m
  echo "==================== preflight --observe $m ===================="
  "$SE" preflight --state /s/$m --operation "/tmp/spawn556 /s/$m" \
    --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work /wk/$m > /tmp/pf.$m.txt 2>&1
  echo "preflight rc=$?"
  grep -E " -> |^(UNKNOWN|PREFLIGHT)" /tmp/pf.$m.txt
done
