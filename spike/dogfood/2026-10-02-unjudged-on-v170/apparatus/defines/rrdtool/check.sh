#!/bin/sh
# 更新の途中で落ちても、RRD は読めて、前に入れた値は残っている。
rrdtool info "/s/rrdtool/state/t.rrd" > /tmp/info.txt 2>/tmp/e.txt || {
  echo "rrdtool info が読めない（$(wc -c < "/s/rrdtool/state/t.rrd" 2>/dev/null) bytes）: $(head -1 /tmp/e.txt)"; exit 1; }
grep -q "ds\[v\]" /tmp/info.txt || { echo "データソース v が info に出てこない"; exit 1; }
rrdtool fetch "/s/rrdtool/state/t.rrd" AVERAGE --start 1700000000 --end 1700000180 > /tmp/f.txt 2>/tmp/e2.txt || {
  echo "rrdtool fetch が失敗した: $(head -1 /tmp/e2.txt)"; exit 1; }
grep -qE '1700000120: 2\.2' /tmp/f.txt || {
  echo "前に入れた 1700000120 の値 22 が消えた（fetch: $(tr '\n' ' ' < /tmp/f.txt | cut -c1-120)）"; exit 1; }
exit 0
