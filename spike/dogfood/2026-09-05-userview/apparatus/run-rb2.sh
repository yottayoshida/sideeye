#!/bin/sh
set -u
SE=/se/bin/sideeye; SHIM=/se/lib/libsideeye_shim.so; OUT=/work/out2
mkdir -p "$OUT" /work/rb4/src
printf 'one\n' > /work/rb4/src/f1.txt
printf 'two\n' > /work/rb4/src/f2.txt
rdiff-backup backup /work/rb4/src /work/rb4/bk > /dev/null 2>&1
sleep 3
printf 'one changed\n' > /work/rb4/src/f1.txt
"$SE" preflight --state /work/rb4/bk \
  --operation "/usr/bin/rdiff-backup backup /work/rb4/src /work/rb4/bk" \
  --shim "$SHIM" --oracle /usr/bin/strace > "$OUT/rdiff-backup4.txt" 2>&1
rc=$?
echo "preflight+oracle raw rc=$rc"
head -8 "$OUT/rdiff-backup4.txt"
