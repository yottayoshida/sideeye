#!/bin/sh
# Lab 2: DuckDB's gate refusal (unsupported_syscall_observed, unlinkat) asked again under
# --observe syscalls, where the shim's own wrappers are not the only witness, before deciding
# whether it is a wall.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-sv1012 sh /ap/lab-2.sh
set -u
. /ap/env.sh
SE=$(cat /install.path); mkdir -p /out/lab-2
for mode in wrappers syscalls; do
  sh /ap/defines/duckdb/seed.sh > /out/lab-2/seed-$mode.log 2>&1
  "$SE" preflight --config /ap/defines/duckdb/sideeye.toml --twice --oracle /usr/bin/strace --observe $mode > /out/lab-2/duckdb-$mode.txt 2>&1
  echo "duckdb --observe $mode: preflight exit $?"; grep -E '^(UNKNOWN|PREFLIGHT|next)' -A1 /out/lab-2/duckdb-$mode.txt | head -4
done
