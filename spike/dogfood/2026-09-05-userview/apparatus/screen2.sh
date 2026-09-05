#!/bin/sh
# 1回目のスクリーニングで私の書き方が悪くて失敗した3本を測り直す + oxipng を足す。
set -u
mkdir -p /work/d2 && cd /work/d2
mkdir -p srcdir; printf 'one\n' > srcdir/f1.txt; printf 'two\n' > srcdir/f2.txt
ffmpeg -loglevel error -f lavfi -i color=c=red:s=64x64 -frames:v 1 -y p1.png 2>/dev/null
cp p1.png p2.png

check() {
  name=$1; bin=$2; shift 2
  if [ -x "$bin" ]; then path=$bin; else path=$(command -v "$bin" 2>/dev/null); fi
  if [ -z "${path:-}" ]; then printf "%-18s 見つからない\n" "$name"; return 0; fi
  if file -L "$path" | grep -q "statically linked"; then link="static"; else link="dynamic"; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr.txt "$@" > /tmp/op.txt 2>&1
  oprc=$?
  th=$(grep -c "CLONE_THREAD" /tmp/tr.txt 2>/dev/null | head -1)
  ch=$(grep -c "clone" /tmp/tr.txt 2>/dev/null | head -1)
  printf "%-18s %-8s スレッド=%-4s clone計=%-4s rc=%s\n" "$name" "$link" "$th" "$ch" "$oprc"
  if [ "$oprc" -ne 0 ]; then echo "    失敗の中身: $(head -2 /tmp/op.txt | tr '\n' ' ' | cut -c1-130)"; fi
  return 0
}

echo "=== 測り直し + Rust 枠 ==="
check weechat-headless weechat-headless weechat-headless --dir /work/d2/wee --run-command "/save;/quit"
check rdiff-backup rdiff-backup rdiff-backup backup srcdir /work/d2/bk
printf 'https://example.com/feed.xml\n' > /work/d2/urls
check newsboat newsboat newsboat -x reload -u /work/d2/urls -c /work/d2/cache.db
echo "--- oxipng: 既定（rayon が並列する想定）---"
check "oxipng(既定)" /ox/oxipng /ox/oxipng -o1 -q p1.png
echo "--- oxipng: -t 1 で単一スレッドにする ---"
check "oxipng(-t 1)" /ox/oxipng /ox/oxipng -t 1 -o1 -q p2.png

echo
echo "=== 出来たファイル ==="
find /work/d2 -type f 2>/dev/null | sort | head -22
