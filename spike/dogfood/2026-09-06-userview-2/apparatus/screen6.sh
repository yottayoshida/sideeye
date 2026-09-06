#!/bin/sh
# slate 2 の screen。第1弾の 2 軸に「write が stdio か raw か」を足す。
#
# 判定: strace が見せる write のサイズ。stdio のバッファ溢れは 4096 の倍数ちょうどで
# 出る（glibc の既定バッファ）。ADR 0005 が観測するのは flush 点の write だけなので、
# fwrite の内部で出た write は shim に記録されず oracle_missed_operation になる。
set -u
mkdir -p /work/s2 && cd /work/s2

printf 'select a,b from t where a=1\n' > /work/s2/q.sql
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /work/s2/f.ttf
printf 'a,b\n1,2\n3,4\n' > /work/s2/f.csv
cat > /work/s2/l.beancount <<'EOB'
2026-01-01 open Assets:Cash
2026-01-01 open Expenses:Food
2026-01-02 * "lunch"
  Expenses:Food   10.00 JPY
  Assets:Cash
EOB
vips black /work/s2/img.png 64 64 2>/dev/null || echo "vips black が使えない"

echo "--- 素材 ---"
ls -la /work/s2

check() {  # check <名前> <バイナリ> <実操作コマンド...>
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi

  strace -f -e trace=clone,clone3 -o /tmp/c.txt "$@" > /tmp/o.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/c.txt 2>/dev/null | head -1)

  # write のサイズ分布。4096 ちょうどが並ぶなら stdio のバッファ溢れ。
  strace -f -e trace=write -o /tmp/w.txt "$@" > /dev/null 2>&1
  w4096=$(grep -c ", 4096)" /tmp/w.txt 2>/dev/null | head -1)
  wall=$(grep -c "write(" /tmp/w.txt 2>/dev/null | head -1)

  printf "%-12s %-8s thread=%-4s rc=%-3s write計=%-4s うち4096ちょうど=%s\n" \
    "$name" "$link" "$th" "$rc" "$wall" "$w4096"
  if [ "$rc" -ne 0 ]; then
    echo "    失敗: $(head -3 /tmp/o.txt | tr '\n' ' ' | cut -c1-150)"
  fi
  return 0
}

echo
echo "=== slate 2 の screen ==="
check sqlfluff  sqlfluff  sqlfluff fix --force --dialect ansi /work/s2/q.sql
check fonttools fonttools fonttools subset /work/s2/f.ttf --output-file=/work/s2/f.ttf --unicodes=U+0041-005A
check vips      vips      vips copy /work/s2/img.png /work/s2/img.png
check csvkit    csvformat csvformat /work/s2/f.csv
echo "--- beancount に in-place で書くコマンドがあるか（rule 8）---"
ls /usr/bin/bean* 2>/dev/null || echo "  bean-* が無い"

echo
echo "--- 書き込み後 ---"
ls -la /work/s2
