#!/bin/sh
set -u
. /ap/env.sh
for mode in wrappers syscalls; do
  sh /ap/defines/duckdb/seed.sh > /out/seed-explore-$mode.log 2>&1
  rm -rf /tmp/w; /t/branch-out/bin/sideeye explore --config /ap/defines/duckdb/sideeye.toml \
    --oracle /usr/bin/strace --observe $mode --shim /t/branch-out/lib/libsideeye_shim.so --work /tmp/w > /out/duckdb-explore-$mode.txt 2>&1
  echo "== duckdb explore $mode: exit $?"; head -12 /out/duckdb-explore-$mode.txt
done
