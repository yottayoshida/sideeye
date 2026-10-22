#!/bin/sh
set -u
. /ap/env.sh
sh /ap/defines/duckdb/seed.sh > /dev/null 2>&1
rm -rf /out/w; /t/branch-out/bin/sideeye explore --config /ap/defines/duckdb/sideeye.toml \
  --oracle /usr/bin/strace --shim /t/branch-out/lib/libsideeye_shim.so --work /out/w > /dev/null 2>&1
/t/branch-out/bin/sideeye evidence /out/w/evidence/000001.json 2>&1 | head -60
