#!/bin/sh
# screen 第3弾: 4件目の枠を実操作で測る。
set -u
mkdir -p /work/d3
cd /work/d3

ffmpeg -loglevel error -f lavfi -i testsrc=size=64x64:rate=5:duration=1 \
       -pix_fmt yuv420p -y /work/d3/v.mp4 2>/dev/null
ffmpeg -loglevel error -f lavfi -i color=c=white:s=200x100 -frames:v 1 \
       -y /work/d3/page.png 2>/dev/null
python3 -c "
import subprocess
subprocess.run(['ffmpeg','-loglevel','error','-i','/work/d3/page.png','-y','/work/d3/in.pdf'])
" 2>/dev/null

echo "--- 素材 ---"
ls -la /work/d3

check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-38)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi
  strace -f -e trace=clone,clone3,execve -o /tmp/tr.txt "$@" > /tmp/op.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/tr.txt 2>/dev/null | head -1)
  ch=$(grep -c clone /tmp/tr.txt 2>/dev/null | head -1)
  ex=$(grep -c execve /tmp/tr.txt 2>/dev/null | head -1)
  printf "%-12s %-8s thread=%-4s clone=%-4s execve=%-4s rc=%-3s %s\n" \
    "$name" "$link" "$th" "$ch" "$ex" "$rc" "$kind"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/op.txt | tr '\n' ' ' | cut -c1-160)"
  fi
  if [ "$ex" -gt 1 ]; then
    echo "    子プロセス: $(grep execve /tmp/tr.txt | sed -n '2,4p' | sed 's/.*execve(//' | cut -c1-60 | tr '\n' ' ')"
  fi
  return 0
}

echo
echo "=== screen 第3弾 ==="
# MP4Box: gpac は Debian trixie に無い（no installation candidate）ので screen できない
check ocrmypdf ocrmypdf ocrmypdf --force-ocr --output-type pdf /work/d3/in.pdf /work/d3/in.pdf

echo
echo "--- 書き込み後 ---"
ls -la /work/d3
