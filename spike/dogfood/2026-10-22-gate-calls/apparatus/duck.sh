#!/bin/sh
set -u
. /ap/env.sh
for eng in main branch; do
  for mode in wrappers syscalls supervised; do
    sh /ap/defines/duckdb/seed.sh > /out/seed-$eng-$mode.log 2>&1
    rm -rf /tmp/w; /t/$eng-out/bin/sideeye preflight --config /ap/defines/duckdb/sideeye.toml --twice \
      --oracle /usr/bin/strace --observe $mode --shim /t/branch-out/lib/libsideeye_shim.so --work /tmp/w > /out/duckdb-$eng-$mode.txt 2>&1
    echo "== duckdb $eng $mode: preflight exit $?"
    grep -E '^(UNKNOWN|PREFLIGHT|recording|SETUP)' -A1 /out/duckdb-$eng-$mode.txt | head -3
    echo "   empty unlinkat lines in the oracle trace: $(cat /tmp/w/oracle*.txt 2>/dev/null | grep -c 'unlinkat([^,]*, ""')"
    ls /tmp/w | head -5 | tr '\n' ' '; echo
  done
done
