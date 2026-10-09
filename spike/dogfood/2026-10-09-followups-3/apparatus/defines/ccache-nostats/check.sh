#!/bin/sh
# With the statistics off there is no hit counter to read; this judges what the cache gives back: the
# object for a.c, compiled through ccache, is byte for byte the one compiled before the operation.
CCACHE_DIR=/s/ccache/state CCACHE_NOSTATS=1 ccache gcc -c /s/ccache/aux/src/a.c -o /tmp/chk.o > /tmp/e.txt 2>&1 || {
  echo "compiling through the cache failed: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-120)"; exit 1; }
cmp -s /tmp/chk.o /s/ccache/aux/src/a.o.golden || { echo "the object from the cache differs from the original"; exit 1; }
exit 0
