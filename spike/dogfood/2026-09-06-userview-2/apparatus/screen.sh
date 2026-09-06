#!/bin/sh
# 候補スクリーニング: 動的リンクか / 実際の書き込み操作でスレッドを作るか。
# --version では出ないスレッドがあるので（beets がそうだった）、必ず実操作で測る。
set -u
mkdir -p /work/d
cd /work/d

python3 /work/mkmat.py
flac -s -f /work/d/a.wav -o /work/d/a.flac
lame --quiet /work/d/a.wav /work/d/a.mp3 2>/dev/null
printf 'a,b\n1,2\n3,4\n' > /work/d/f.csv
printf 'if [ 1 ];then\necho x\nfi\n' > /work/d/f.sh
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /work/d/f.ttf 2>/dev/null
echo "--- 素材 ---"
ls -la /work/d

check() {  # check <名前> <バイナリ> <実操作コマンド...>
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-40)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr.txt "$@" > /tmp/op.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/tr.txt 2>/dev/null | head -1)
  ch=$(grep -c clone /tmp/tr.txt 2>/dev/null | head -1)
  printf "%-12s %-8s thread=%-4s clone=%-4s rc=%-3s %s\n" \
    "$name" "$link" "$th" "$ch" "$rc" "$kind"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/op.txt | tr '\n' ' ' | cut -c1-150)"
  fi
  return 0
}

echo
echo "=== 候補スクリーニング（実操作で測る）==="
check metaflac  metaflac  metaflac --set-tag=ARTIST=x /work/d/a.flac
check mid3v2    mid3v2    mid3v2 -a x /work/d/a.mp3
check mlr       mlr       mlr -I --csv put '$z=1' /work/d/f.csv
check shfmt     shfmt     shfmt -w /work/d/f.sh
check fontforge fontforge fontforge -lang=ff -c 'Open("/work/d/f.ttf"); Generate("/work/d/f.ttf");'

echo
echo "--- 書き込み後 ---"
ls -la /work/d
