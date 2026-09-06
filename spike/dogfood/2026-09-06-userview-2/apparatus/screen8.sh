#!/bin/sh
# slate 2 の残り2枠。3 軸（linkage / threads / write が stdio か raw か）。
set -u
mkdir -p /work/s4 && cd /work/s4

python3 -c "
import sys
open('/work/s4/big.txt','w').write('probe line\n' * 2000)
"
cat > /work/s4/l.beancount <<'EOB'
2026-01-01 open Assets:Cash
2026-01-01 open Expenses:Food
2026-01-02 * "lunch"
  Expenses:Food   10.00 JPY
  Assets:Cash
2026-01-03 * "coffee"
  Expenses:Food    3.50 JPY
  Assets:Cash
EOB

echo "--- 素材 ---"
ls -la /work/s4

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
  printf "%-12s %-8s thread=%-3s execve=%-3s rc=%-3s\n" "$name" "$link" "$th" "$ex" "$rc"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/o.txt | tr '\n' ' ' | cut -c1-170)"
  fi
  return 0
}

echo
echo "=== slate 2 の screen（残り2枠）==="
check zstd     zstd        zstd --rm -q -f /work/s4/big.txt
check beanfmt  bean-format bean-format -o /work/s4/l.beancount /work/s4/l.beancount

echo
echo "--- 書き込み後 ---"
ls -la /work/s4

echo
echo "=== 書き込み経路（この2本が何をするか）==="
python3 -c "open('/work/s4/b2.txt','w').write('probe line\n' * 2000)"
echo "--- zstd --rm ---"
strace -f -e trace=openat,rename,renameat,unlink,unlinkat,ftruncate,write -o /tmp/wz.txt \
  zstd --rm -q -f /work/s4/b2.txt 2>/dev/null
grep -E "b2\.txt|rename|unlink" /tmp/wz.txt | grep -v ENOENT | head -8
echo "  write のサイズ分布: $(grep -oE 'write\([0-9]+, .*, [0-9]+\)' /tmp/wz.txt | grep -oE '[0-9]+\)$' | sort -n | uniq -c | tr '\n' ' ')"

cp /work/s4/l.beancount /work/s4/l2.beancount
echo "--- bean-format -o 同名 ---"
strace -f -e trace=openat,rename,renameat,unlink,unlinkat,ftruncate,write -o /tmp/wb.txt \
  bean-format -o /work/s4/l2.beancount /work/s4/l2.beancount 2>/dev/null
grep -E "l2\.beancount|rename|unlink" /tmp/wb.txt | grep -v ENOENT | head -8
