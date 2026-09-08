#!/bin/sh
# 反証チェック 3 本目: mutool を N=16 で、修正前後の 2 アームで測る。
# 判定規則は測定の前に plan に登録済み: 前 0/16 到達（16/16 が unlinked-fd close で拒否）、
# 後 14 以上が到達。後アームの unlinked-fd 以外の UNKNOWN は 2 件まで許し、全件書く。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
ARM=${ARM:?ARM を before/after で渡す}
mkdir -p "$AP" "$OUT" "$R/wk"
cp /hostap/mkpdf.py "$AP/"

cat > "$AP/setup-pdf.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
python3 /localrun/ap/mkpdf.py "$SD/a.pdf" > /dev/null
EOS
cat > "$AP/check-pdf.sh" <<'EOC'
#!/bin/sh
f="$SD/a.pdf"
[ -f "$f" ] || { echo "a.pdf が無い"; exit 1; }
mutool info "$f" > /dev/null 2>&1 || { echo "a.pdf を mutool が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

echo "# arm=$ARM  engine: $("$SE" --version 2>&1 | head -1)"
i=1
while [ "$i" -le 16 ]; do
  SD="$R/m16/$ARM-$i/mutool"; export SD
  mkdir -p "$SD" "$R/wk/m16-$ARM-$i"
  "$SE" explore --state "$SD" --setup "$AP/setup-pdf.sh" \
    --operation "mutool clean $SD/a.pdf $SD/a.pdf" --check "$AP/check-pdf.sh" \
    --shim "$SHIM" --oracle /usr/bin/strace ${OBSERVE:+--observe "$OBSERVE"} --work "$R/wk/m16-$ARM-$i" \
    > "$OUT/m16-$ARM-$i.txt" 2>&1
  rc=$?
  head=$(grep -m1 -E "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/m16-$ARM-$i.txt" | tr -s ' ')
  kind=$(grep -m1 -oE "unlinked-fd [a-z]+ fd:[0-9]+|fd-without-path [a-z]+ fd:[0-9]+" "$OUT/m16-$ARM-$i.txt")
  worlds=$(grep -m1 -oE "explored [0-9]+ worlds \(crash points [0-9]+" "$OUT/m16-$ARM-$i.txt")
  printf 'run%-3s rc=%s  %-56s %s %s\n' "$i" "$rc" "$head" "$kind" "$worlds"
  i=$((i + 1))
done
mkdir -p /hostout; cp "$OUT"/m16-"$ARM"-*.txt /hostout/ 2>/dev/null
