#!/bin/sh
# plan のステップ 0 を承認前に測る: mutool の unresolvable_path は oracle なし・単一 run でも出るか。
# 出れば動機は装置に依存しない。出なければ前 plan と同じ死に方（装置が形を作っている）。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
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

echo "########## A: explore, oracle なし, --allow-unverified, 4 回 ##########"
i=1
while [ "$i" -le 4 ]; do
  SD="$R/s0/noor-$i/mutool"; export SD
  mkdir -p "$SD" "$R/wk/s0-noor-$i"
  "$SE" explore --state "$SD" --setup "$AP/setup-pdf.sh" \
    --operation "mutool clean $SD/a.pdf $SD/a.pdf" --check "$AP/check-pdf.sh" \
    --shim "$SHIM" --allow-unverified --work "$R/wk/s0-noor-$i" \
    > "$OUT/s0-noor-$i.txt" 2>&1
  rc=$?
  echo "run$i: rc=$rc  $(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/s0-noor-$i.txt" | tr -s ' ')"
  grep -m1 -oE "unlinked-fd [a-z]+ fd:[0-9]+" "$OUT/s0-noor-$i.txt" | sed 's/^/      kind: /'
  i=$((i + 1))
done

echo "########## B: preflight, oracle なし, 2 回（最も安い形）##########"
i=1
while [ "$i" -le 2 ]; do
  SD="$R/s0/pf-$i/mutool"; export SD
  mkdir -p "$SD" "$R/wk/s0-pf-$i"
  "$SE" preflight --state "$SD" --setup "$AP/setup-pdf.sh" \
    --operation "mutool clean $SD/a.pdf $SD/a.pdf" \
    --shim "$SHIM" --work "$R/wk/s0-pf-$i" > "$OUT/s0-pf-$i.txt" 2>&1
  echo "pf$i: rc=$?  $(grep -m1 -E '^(PREFLIGHT|UNKNOWN)' "$OUT/s0-pf-$i.txt" | tr -s ' ' | cut -c1-70)"
  grep -m1 -oE "unlinked-fd [a-z]+ fd:[0-9]+" "$OUT/s0-pf-$i.txt" | sed 's/^/      kind: /'
  i=$((i + 1))
done
mkdir -p /hostout; cp "$OUT"/s0-* /hostout/ 2>/dev/null
