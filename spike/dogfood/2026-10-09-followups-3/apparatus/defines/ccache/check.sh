#!/bin/sh
# 前に cache へ入れた a.c が、cache から取り出せる（当たる）こと。
# 「ccache -s が動く」だけでは、中身がゴミでも通ってしまった。
before=$(CCACHE_DIR="/s/ccache/state" ccache --print-stats 2>/dev/null | awk '$1=="direct_cache_hit"{print $2}')
[ -n "$before" ] || { echo "ccache の統計が読めない"; exit 1; }
CCACHE_DIR="/s/ccache/state" ccache gcc -c /s/ccache/aux/src/a.c -o /tmp/chk.o >/tmp/e.txt 2>&1 || {
  echo "cache を使ったコンパイルが失敗した: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-120)"; exit 1; }
after=$(CCACHE_DIR="/s/ccache/state" ccache --print-stats 2>/dev/null | awk '$1=="direct_cache_hit"{print $2}')
[ "$after" -gt "$before" ] || {
  echo "前に入れた a.c が cache から取り出せない（direct_cache_hit $before -> $after）"; exit 1; }
cmp -s /tmp/chk.o /s/ccache/aux/src/a.o.golden || {
  echo "cache から出てきた .o が元と違う"; exit 1; }
exit 0
