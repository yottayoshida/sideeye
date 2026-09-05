#!/bin/sh
# 対象4: joplin CLI。Node/libuv の壁を実測する（docs/target-classes.md が「予測のみ」と書いている行）
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out
mkdir -p "$OUT"

echo "joplin の実体: $(command -v joplin)"
echo "1行目: $(head -1 $(command -v joplin))"
echo "node の実体: $(command -v node)"
echo "node は動的リンクか: $(grep -qa 'ld-linux-aarch64' $(command -v node) && echo dynamic || echo static)"
echo

# setup: notebook を1つ作り、note を1つ入れておく
mkdir -p /work/jp
joplin --profile /work/jp mkbook TestBook > /dev/null 2>&1
joplin --profile /work/jp use TestBook   > /dev/null 2>&1
joplin --profile /work/jp mknote SeedNote > /dev/null 2>&1
echo "setup 後の profile:"
find /work/jp -maxdepth 1 -type f | sort | sed 's/^/  /'
echo

echo "==================== joplin ===================="
"$SE" preflight \
  --state /work/jp \
  --operation "$(command -v joplin) --profile /work/jp mknote SecondNote" \
  --shim "$SHIM" > "$OUT/joplin.txt" 2>&1
rc=$?
echo "raw rc=$rc"
head -6 "$OUT/joplin.txt"
echo

echo "==================== joplin + oracle ===================="
"$SE" preflight \
  --state /work/jp \
  --operation "$(command -v joplin) --profile /work/jp mknote ThirdNote" \
  --shim "$SHIM" --oracle /usr/bin/strace > "$OUT/joplin-oracle.txt" 2>&1
rc=$?
echo "raw rc=$rc"
head -6 "$OUT/joplin-oracle.txt"
