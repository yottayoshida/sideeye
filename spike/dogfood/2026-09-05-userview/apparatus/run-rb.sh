#!/bin/sh
# rdiff-backup: --api-version 201 は 2.2.6 で通らなかった（1回目の素の呼び方は rc=0 だった）。
# 元に戻し、同じ秒での2回目を避けるために間を空ける。
set -u
SE=/se/bin/sideeye; SHIM=/se/lib/libsideeye_shim.so; OUT=/work/out2
mkdir -p "$OUT" /work/rb3/src
printf 'one\n' > /work/rb3/src/f1.txt
printf 'two\n' > /work/rb3/src/f2.txt
rdiff-backup backup /work/rb3/src /work/rb3/bk > "$OUT/rb3-setup.txt" 2>&1
echo "setup raw rc=$?"
tail -2 "$OUT/rb3-setup.txt"
sleep 3
printf 'one changed\n' > /work/rb3/src/f1.txt
echo "setup 後の bk のファイル数: $(find /work/rb3/bk -type f 2>/dev/null | wc -l)"
"$SE" preflight --state /work/rb3/bk \
  --operation "/usr/bin/rdiff-backup backup /work/rb3/src /work/rb3/bk" \
  --shim "$SHIM" > "$OUT/rdiff-backup3.txt" 2>&1
rc=$?
echo "preflight raw rc=$rc"
head -8 "$OUT/rdiff-backup3.txt"
