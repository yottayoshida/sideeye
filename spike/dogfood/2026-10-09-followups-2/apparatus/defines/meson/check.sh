#!/bin/sh
# 再設定の途中で落ちても、meson はその build ディレクトリを読める。
out=$(meson introspect --projectinfo "/s/meson/state" 2>/tmp/e.txt) || {
  echo "meson が build ディレクトリを読めない: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
echo "$out" | grep -q "probe" || { echo "projectinfo に probe が無い: $(echo "$out" | cut -c1-80)"; exit 1; }
exit 0
