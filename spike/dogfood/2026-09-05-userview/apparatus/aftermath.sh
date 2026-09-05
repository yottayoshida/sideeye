#!/bin/sh
# crash 後にディレクトリに何が残るかを実測する。
# 「データが失われるのか、名前が変わって残っているのか」で報告の重さが変わる。
# sideeye の reproduce 行が示す環境変数をそのまま使い、crash 後の中身を見る。
set -u
SHIM=/se/lib/libsideeye_shim.so

echo "########## mogrify: crash point 2 の後に何が残るか ##########"
mkdir -p /work/am/im
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y "/work/am/im/img$n.png"
done
echo "--- crash 前 ---"
ls -la /work/am/im | grep -v '^total\|^d' | awk '{printf "  %-28s %s bytes\n", $9, $5}'
SIDEEYE_STATE_DIR=/work/am/im \
SIDEEYE_TRACE_PATH=/work/am/trace-im.bin \
LD_PRELOAD="$SHIM" \
SIDEEYE_KILL_AT=2 \
/usr/bin/mogrify -resize 50% /work/am/im/img1.png /work/am/im/img2.png /work/am/im/img3.png > /dev/null 2>&1
echo "  （殺した後の rc=$?）"
echo "--- crash 後 ---"
ls -la /work/am/im | grep -v '^total\|^d' | awk '{printf "  %-28s %s bytes\n", $9, $5}'
echo "--- 元の内容はどこかに残っているか ---"
for f in /work/am/im/*; do
  printf "  %-32s " "$(basename "$f")"
  if identify "$f" > /dev/null 2>&1; then echo "identify が読める（$(identify -format '%wx%h' "$f" 2>/dev/null)）"; else echo "読めない"; fi
done

echo
echo "########## exiv2: crash point 2 の後に何が残るか ##########"
mkdir -p /work/am/ex
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y "/work/am/ex/pic$n.jpg"
done
echo "--- crash 前 ---"
ls -la /work/am/ex | grep -v '^total\|^d' | awk '{printf "  %-28s %s bytes\n", $9, $5}'
SIDEEYE_STATE_DIR=/work/am/ex \
SIDEEYE_TRACE_PATH=/work/am/trace-ex.bin \
LD_PRELOAD="$SHIM" \
SIDEEYE_KILL_AT=2 \
/usr/bin/exiv2 rm /work/am/ex/pic1.jpg /work/am/ex/pic2.jpg /work/am/ex/pic3.jpg > /dev/null 2>&1
echo "  （殺した後の rc=$?）"
echo "--- crash 後 ---"
ls -la /work/am/ex | grep -v '^total\|^d' | awk '{printf "  %-28s %s bytes\n", $9, $5}'
for f in /work/am/ex/*; do
  printf "  %-32s " "$(basename "$f")"
  if identify "$f" > /dev/null 2>&1; then echo "identify が読める"; else echo "読めない"; fi
done
