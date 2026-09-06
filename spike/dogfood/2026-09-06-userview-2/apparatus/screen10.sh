#!/bin/sh
# slate 3 の screen。3 軸に加えて rule 8（in-place で書くコマンドが本当にあるか）も見る。
set -u
mkdir -p /work/s5 && cd /work/s5

# Python 素材
cat > /work/s5/a.py <<'EOP'
import sys
import os
from collections import OrderedDict
import json

d = dict()
s = "%s-%s" % (1, 2)
print(sys.argv, os.sep, OrderedDict(), json.dumps(d), s)
EOP
cp /work/s5/a.py /work/s5/b.py

# 画像素材: PPM -> JPEG、そして最小 PNG
python3 - <<'PY'
import zlib, struct
# PPM (cjpeg の入力)
w = h = 32
with open('/work/s5/src.ppm', 'wb') as f:
    f.write(b'P6\n%d %d\n255\n' % (w, h))
    f.write(bytes([(x * 7 + y * 3) % 256 for y in range(h) for x in range(w) for _ in range(3)]))
# PNG
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
raw = b''.join(b'\x00' + bytes([(x * 5 + y) % 256 for x in range(w * 3)]) for y in range(h))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open('/work/s5/a.png', 'wb').write(png)
print('素材 ok')
PY
cjpeg -quality 80 -outfile /work/s5/a.jpg /work/s5/src.ppm 2>/dev/null
cp /work/s5/a.png /work/s5/b.png

echo "--- 素材 ---"
ls -la /work/s5

check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi

  strace -f -e trace=clone,clone3,execve -o /tmp/c.txt "$@" > /tmp/o.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/c.txt 2>/dev/null | head -1)
  ex=$(grep -c execve /tmp/c.txt 2>/dev/null | head -1)

  strace -f -e trace=write -o /tmp/w.txt "$@" > /dev/null 2>&1
  w4096=$(grep -c ", 4096)" /tmp/w.txt 2>/dev/null | head -1)
  wall=$(grep -c "write(" /tmp/w.txt 2>/dev/null | head -1)

  printf "%-12s %-8s thread=%-3s execve=%-3s rc=%-3s write=%-4s うち4096=%s\n" \
    "$name" "$link" "$th" "$ex" "$rc" "$wall" "$w4096"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/o.txt | tr '\n' ' ' | cut -c1-160)"
  fi
  return 0
}

echo
echo "=== slate 3 の screen ==="
check isort     isort     isort /work/s5/a.py
check pyupgrade pyupgrade pyupgrade --py311-plus /work/s5/b.py
check jpegtran  jpegtran  jpegtran -copy all -optimize -outfile /work/s5/a.jpg /work/s5/a.jpg
echo "--- pngfix に in-place で書く経路があるか（rule 8）---"
pngfix --help 2>&1 | head -8
check pngfix    pngfix    pngfix --out=/work/s5/b.png /work/s5/b.png

echo
echo "--- 書き込み後 ---"
ls -la /work/s5
