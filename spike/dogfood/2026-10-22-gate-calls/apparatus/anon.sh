#!/bin/sh
set -u
gcc -O0 -g -o /tmp/toy-fixed /w/spike/toys/toy.c -lpthread || exit 9
for eng in main branch; do
  for mode in wrappers syscalls supervised; do
    rm -rf /tmp/acc && mkdir -p /tmp/acc/state
    o=$(TOY_ANONFD=1 /t/$eng-out/bin/sideeye explore --state /tmp/acc/state \
        --setup "/tmp/toy-fixed init" --operation "/tmp/toy-fixed rotate" --observe "$mode" \
        --shim /t/branch-out/lib/libsideeye_shim.so --work /tmp/acc/work --oracle /usr/bin/strace 2>&1)
    rc=$?
    echo "== $eng $mode rc=$rc"
    printf '%s\n' "$o" | head -3
    printf '%s\n' "$o" | grep -E "explored  +[0-9]+ worlds"
    grep -hE 'unlinkat\([^,]*, ""|sync_file_range|syncfs' /tmp/acc/work/oracle.txt 2>/dev/null | head -4
  done
done
