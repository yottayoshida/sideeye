#!/bin/sh
# rdiff-backup を、そのツール自身の回復手順を挟んでから測り直す。
# tracker の #179 / #1084 が示すとおり、中断されたバックアップは regress で戻す設計。
# 前回の checker は crash 直後にいきなり verify したので、回復契約を無視していた。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out4
WK=/work/wk4
mkdir -p "$OUT" "$WK" /work/rbr/src

cat > /work/rbr-setup.sh <<'EOS'
#!/bin/sh
mkdir -p /work/rbr/src
printf 'one\n' > /work/rbr/src/f1.txt
printf 'two\n' > /work/rbr/src/f2.txt
rdiff-backup backup /work/rbr/src /work/rbr/bk > /dev/null 2>&1
sleep 2
printf 'one changed\n' > /work/rbr/src/f1.txt
EOS

cat > /work/rbr-check.sh <<'EOC'
#!/bin/sh
# rdiff-backup 自身の回復手順を先に走らせてから検証する。
# regress は「前回が中断された」ときだけ意味を持つので、失敗しても止めない。
[ -d /work/rbr/bk ] || { echo "bk が無い"; exit 1; }
rdiff-backup regress /work/rbr/bk > /tmp/regress.txt 2>&1
rdiff-backup verify /work/rbr/bk > /tmp/verify.txt 2>&1 || {
  echo "regress を挟んでも verify が通らない: $(grep -v '^WARNING: Server' /tmp/verify.txt | tail -2 | tr '\n' ' ' | cut -c1-160)"
  exit 1
}
exit 0
EOC
chmod 755 /work/rbr-setup.sh /work/rbr-check.sh

echo "==================== rdiff-backup（回復手順つき）===================="
"$SE" explore --state /work/rbr/bk \
  --setup /work/rbr-setup.sh \
  --operation "/usr/bin/rdiff-backup backup /work/rbr/src /work/rbr/bk" \
  --check /work/rbr-check.sh \
  --shim "$SHIM" --oracle /usr/bin/strace \
  --work "$WK/rb" --json "$OUT/rdiff-backup-regress.json" > "$OUT/rdiff-backup-regress.txt" 2>&1
rc=$?
echo "raw rc=$rc   (0=PASS  1=FAIL  2=UNKNOWN  3=setup error)"
grep -vE "^WARNING: Server will be called" "$OUT/rdiff-backup-regress.txt" | head -18
