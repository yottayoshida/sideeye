#!/bin/sh
# ラウンド3 スクリーニング。
set -u
mkdir -p /work/d && cd /work/d
python3 -c "
from PIL import Image, ImageDraw
im = Image.new('RGB', (160, 60), 'white')
d = ImageDraw.Draw(im)
d.text((6, 20), 'MARKER TEXT', fill='black')
im.save('/work/d/a.png')
im.save('/work/d/out.png')
"
mkdir -p /work/d/doc/src /work/d/doc/build /work/d/venvs /work/d/bat/src
printf 'project = "probe"\nextensions = []\n' > /work/d/doc/src/conf.py
printf 'Probe\n=====\n\nMARKER body text.\n' > /work/d/doc/src/index.rst
printf 'hello MARKER\n' > /work/d/out.txt
check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  [ -z "$path" ] && { printf "%-12s 見つからない\n" "$name"; return 0; }
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-40)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi ELF; then link=dynamic; else link=script; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr-$name.txt "$@" > /tmp/op-$name.txt 2>&1
  rc=$?
  printf "%-12s %-8s thread=%-4s clone=%-4s rc=%-3s %s\n" "$name" "$link" \
    "$(grep -c CLONE_THREAD /tmp/tr-$name.txt)" "$(grep -c clone /tmp/tr-$name.txt)" "$rc" "$kind"
  [ "$rc" -ne 0 ] && echo "    失敗: $(head -3 /tmp/op-$name.txt | tr '\n' ' ' | cut -c1-170)"
  return 0
}
echo "=== 候補スクリーニング（実操作で測る）==="
check bat       batcat       env XDG_CACHE_HOME=/work/d/bat batcat cache --build --source /work/d/bat/src --target /work/d/bat/t
check sphinx    sphinx-build sphinx-build -q -b html /work/d/doc/src /work/d/doc/build
check virtualenv virtualenv  virtualenv -q --no-download /work/d/venvs/v1
check vips      vips         vips copy /work/d/a.png /work/d/out.png
check tesseract tesseract    tesseract /work/d/a.png /work/d/out
echo; echo "--- 書き込み後 ---"; ls -la /work/d | head -12; ls /work/d/doc/build 2>/dev/null | head -4
