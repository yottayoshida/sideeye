#!/bin/sh
# screen 第4弾: Go 枠を読みで落とさず実測する。dasel は Debian に無いので
# GitHub release の linux_arm64 バイナリ（プロジェクトが配る唯一の Linux 形）。
set -u
mkdir -p /work/d4
cd /work/d4
cp /work/dasel_linux_arm64 /work/d4/dasel
chmod +x /work/d4/dasel
printf '{"a":1,"b":{"c":2}}\n' > /work/d4/f.json

echo "--- 素材 ---"
ls -la /work/d4
echo "--- linkage ---"
file -L /work/d4/dasel

echo
echo "=== 実操作でスレッドを測る ==="
strace -f -e trace=clone,clone3 -o /tmp/tr4.txt /work/d4/dasel put -f /work/d4/f.json -t int -v 9 '.b.c' > /tmp/op4.txt 2>&1
rc=$?
th=$(grep -c CLONE_THREAD /tmp/tr4.txt 2>/dev/null | head -1)
ch=$(grep -c clone /tmp/tr4.txt 2>/dev/null | head -1)
if file -L /work/d4/dasel | grep -q "statically linked"; then link=static; else link=dynamic; fi
printf "dasel        %-8s thread=%-4s clone=%-4s rc=%s\n" "$link" "$th" "$ch" "$rc"
[ "$rc" -ne 0 ] && echo "    失敗: $(head -3 /tmp/op4.txt | tr '\n' ' ' | cut -c1-160)"

echo
echo "--- 書き込み後 ---"
cat /work/d4/f.json
ls -la /work/d4/f.json

echo
echo "--- 書き込み経路 ---"
printf '{"a":1,"b":{"c":2}}\n' > /work/d4/g.json
strace -f -e trace=openat,rename,renameat,unlink,unlinkat,ftruncate -o /tmp/w4.txt \
  /work/d4/dasel put -f /work/d4/g.json -t int -v 7 '.b.c' >/dev/null 2>&1
grep -E "g\.json|rename|unlink|tmp" /tmp/w4.txt | head -12
