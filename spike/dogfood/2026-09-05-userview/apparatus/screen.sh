#!/bin/sh
# 候補スクリーニング: 動的リンクか / 実際の書き込み操作でスレッドを作るか。
# --version では出ないスレッドがあるので（beets がそうだった）、必ず実操作で測る。
set -u
mkdir -p /work/d
cd /work/d

# 素材を作る
ffmpeg -loglevel error -f lavfi -i color=c=red:s=64x64 -frames:v 1 -y a.png 2>/dev/null
ffmpeg -loglevel error -f lavfi -i color=c=blue:s=64x64 -frames:v 1 -y a.jpg 2>/dev/null
cp a.png b.png; cp a.jpg b.jpg
convert a.png a.pdf 2>/dev/null || magick a.png a.pdf 2>/dev/null
mkdir -p srcdir dstdir; printf 'one\n' > srcdir/f1.txt; printf 'two\n' > srcdir/f2.txt
ls -la | head -12

check() {  # check <名前> <バイナリ> <実操作コマンド...>
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-14s %s\n" "$name" "見つからない"; return; fi
  # linkage
  if file -L "$path" | grep -q "statically linked"; then link="static"; else link="dynamic"; fi
  # 実操作でスレッドが作られるか
  strace -f -e trace=clone,clone3 -o /tmp/tr.txt "$@" > /tmp/op.txt 2>&1
  oprc=$?
  th=$(grep -c "CLONE_THREAD" /tmp/tr.txt 2>/dev/null || echo 0)
  ch=$(grep -c "clone" /tmp/tr.txt 2>/dev/null || echo 0)
  printf "%-14s %-8s スレッド=%-4s clone計=%-4s 操作rc=%-3s %s\n" \
    "$name" "$link" "$th" "$ch" "$oprc" "$path"
}

echo
echo "=== 候補スクリーニング（実操作で測る）==="
check mogrify   mogrify      mogrify -resize 50% a.png
check optipng   optipng      optipng -quiet -o1 b.png
check exiv2     exiv2        exiv2 -M"set Exif.Photo.UserComment test" a.jpg
check qpdf      qpdf         qpdf --replace-input a.pdf
check rsync     rsync        rsync -a srcdir/ dstdir/
check rdiffbk   rdiff-backup rdiff-backup --api-version 201 backup srcdir /work/d/bk
check newsboat  newsboat     newsboat -x reload -u /work/d/urls -c /work/d/cache.db
check weechat   weechat      weechat --dir /work/d/wee --run-command "/quit"
