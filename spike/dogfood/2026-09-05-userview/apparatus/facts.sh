#!/bin/sh
# 報告に書く事実を全部ここで実測する。記憶や要約から書かない。
set -u
echo "########## バージョンと環境 ##########"
echo "--- OS ---"; cat /etc/os-release | grep -E "^(PRETTY_NAME|VERSION)="
echo "--- arch ---"; uname -m
echo "--- ImageMagick ---"; mogrify --version 2>&1 | head -2
echo "--- exiv2 ---"; exiv2 --version 2>&1 | head -2
echo "--- Debian パッケージ版 ---"
dpkg -l imagemagick exiv2 2>/dev/null | grep -E "^ii" | awk '{printf "  %-24s %s\n", $2, $3}'

echo
echo "########## mogrify の書き込み経路（1枚のとき）##########"
mkdir -p /work/f/im && cd /work/f/im
ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y one.png
strace -f -e trace=openat,open,rename,renameat,unlink,unlinkat,write,ftruncate \
  -o /tmp/im.txt mogrify -resize 50% /work/f/im/one.png > /dev/null 2>&1
echo "  strace rc=$?"
grep -E "one\.png" /tmp/im.txt | grep -vE "ENOENT|= -1" | head -12 | sed 's/^/  /' | cut -c1-160

echo
echo "########## exiv2 rm の書き込み経路（1枚のとき）##########"
mkdir -p /work/f/ex && cd /work/f/ex
ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y one.jpg
strace -f -e trace=openat,open,rename,renameat,unlink,unlinkat,write,ftruncate \
  -o /tmp/ex.txt exiv2 rm /work/f/ex/one.jpg > /dev/null 2>&1
echo "  strace rc=$?"
grep -E "one\.jpg|\.exv|tmp" /tmp/ex.txt | grep -vE "ENOENT|= -1" | head -14 | sed 's/^/  /' | cut -c1-160

echo
echo "########## 各ツールの文書は in-place について何と言っているか ##########"
echo "--- mogrify の man ---"
man mogrify 2>/dev/null | head -20 | grep -iE "overwrit|in.place|original" | sed 's/^/  /'
mogrify --help 2>&1 | head -6 | sed 's/^/  /'
echo "--- exiv2 の man（rm の説明）---"
man exiv2 2>/dev/null | grep -A4 -iE "^ *rm\b|delete.*metadata" | head -12 | sed 's/^/  /'
