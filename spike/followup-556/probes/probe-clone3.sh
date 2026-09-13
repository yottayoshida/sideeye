#!/bin/sh
# #556 R1 C2: does glibc's posix_spawn take clone3 (with CLONE_CLEAR_SIGHAND) here, and what
# does the main shim do to that child under --observe syscalls?
set -u
echo "libc: $(ldd --version 2>&1 | head -1)   arch: $(uname -m)"
gcc -O0 -o /tmp/spawn556 /ap/spawn556.c || exit 2
mkdir -p /tmp/st
strace -f -e trace=clone,clone3,vfork -o /tmp/s.txt /tmp/spawn556 /tmp/st > /dev/null 2>&1
echo "-- clone family lines (first 6):"; grep -E "clone3|clone\(|vfork" /tmp/s.txt | head -6
echo "-- spawn toy under the main shim, preflight --observe syscalls:"
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
mkdir -p /s/spawn /wk
"$SE" preflight --state /s/spawn --operation "/tmp/spawn556 /s/spawn" --shim "$SHIM" --oracle /usr/bin/strace \
  --observe syscalls --work /wk > /tmp/pf.txt 2>&1; echo "preflight rc=$?"
grep -E " -> |^(UNKNOWN|PREFLIGHT)" /tmp/pf.txt; echo "-- head of the preflight output:"; head -4 /tmp/pf.txt
