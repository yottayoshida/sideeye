#!/bin/sh
# 回復可能性。元の名前か ~ 付き（3 度目の patch はランダム hex が付く）のどちらかに
# 読める画像が残っていること。偽なら、その世界では画像がどこにも無い＝データ損失。
for f in /work/im/img1.png /work/im/img1.png~*; do
  if [ -f "$f" ] && /usr/bin/identify "$f" > /dev/null 2>&1; then exit 0; fi
done
echo "どちらの名前にも読める画像が無い: $(ls -la /work/im 2>&1 | tr '\n' ' ')"
exit 1
