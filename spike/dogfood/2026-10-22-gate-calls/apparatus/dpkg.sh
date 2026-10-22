#!/bin/sh
set -u
D=/ap/defines/dpkg-upgrade
. $D/env.sh
for eng in main branch; do
  for mode in wrappers syscalls supervised; do
    sh $D/seed.sh > /out/seed-$eng-$mode.log 2>&1 || echo "seed failed"
    rm -rf /tmp/w; /t/$eng-out/bin/sideeye preflight --config $D/sideeye.toml --twice \
      --oracle /usr/bin/strace --observe $mode --shim /t/branch-out/lib/libsideeye_shim.so --work /tmp/w > /out/dpkg-$eng-$mode.txt 2>&1
    echo "== dpkg $eng $mode: preflight exit $?"
    grep -E '^(UNKNOWN|PREFLIGHT|SETUP)' -A1 /out/dpkg-$eng-$mode.txt | head -3
    echo "   sync_file_range lines in the oracle trace: $(cat /tmp/w/oracle*.txt 2>/dev/null | grep -c 'sync_file_range(')"
  done
done
