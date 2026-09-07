#!/bin/sh
# sweep で出た 2 つの食い違いを詰める。
#   1. mogrify: wrappers が baseline_violates_invariant、syscalls は FAIL 6/13。
#      モード差なのか、対象の出力がバイト単位で再現しないのかを preflight --twice で測る。
#   2. qpdf: 両モードで recording_run_failed（qpdf が warning で exit 3）。
#      最小 PDF が qpdf の厳しい読みに合わないので、09-05 と同じ magick 生成に替える。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
mkdir -p "$AP" "$OUT" "$R/wk"

cat > "$AP/setup-img.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y "$SD/img$n.png"
done
EOS

cat > "$AP/check-img.sh" <<'EOC'
#!/bin/sh
for n in 1 2 3; do
  f="$SD/img$n.png"
  [ -f "$f" ] || { echo "img$n.png が無い"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "img$n.png を identify が読めない（$(wc -c < "$f") bytes）"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-qpdf2.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
ffmpeg -loglevel error -f lavfi -i color=c=blue:s=128x128 -frames:v 1 -y /tmp/x.png
magick /tmp/x.png "$SD/a.pdf"
EOS

cat > "$AP/check-qpdf2.sh" <<'EOC'
#!/bin/sh
f="$SD/a.pdf"
[ -f "$f" ] || { echo "a.pdf が無い"; exit 1; }
qpdf --check "$f" > /dev/null 2>&1 || { echo "qpdf --check が通らない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

echo "########## 1. mogrify の出力はバイト単位で再現するか（preflight --twice）##########"
for mode in wrappers syscalls; do
  SD="$R/tw/$mode/mogrify"; export SD
  mkdir -p "$SD" "$R/wk/tw-$mode"
  echo "---- --twice / $mode ----"
  # --observe を渡す。初版はここだけ渡し忘れていて、両モードで測ったと3箇所に
  # 書きながら実際は既定モードを2回走らせていた（出力2本がバイト同一だったのが証拠。
  # 初見レビューが P0 として捕まえた）。やり直しは fix-p0.sh、成果は tw2-mogrify.*。
  "$SE" preflight --state "$SD" --setup "$AP/setup-img.sh" \
    --operation "/usr/bin/mogrify -resize 50% $SD/img1.png $SD/img2.png $SD/img3.png" \
    --shim "$SHIM" --observe "$mode" --work "$R/wk/tw-$mode" --twice \
    > "$OUT/tw-mogrify.$mode.txt" 2>&1
  echo "raw rc=$?"
  grep -nE "^PREFLIGHT|^UNKNOWN|differ|equal state|repeat" "$OUT/tw-mogrify.$mode.txt" | head -6
done

echo "########## 2. mogrify を wrappers で 3 回、syscalls で 2 回 ##########"
i=1
while [ "$i" -le 3 ]; do
  for mode in wrappers syscalls; do
    [ "$mode" = syscalls ] && [ "$i" -eq 3 ] && continue
    SD="$R/rep/$mode-$i/mogrify"; export SD
    mkdir -p "$SD" "$R/wk/rep-$mode-$i"
    "$SE" explore --state "$SD" --setup "$AP/setup-img.sh" \
      --operation "/usr/bin/mogrify -resize 50% $SD/img1.png $SD/img2.png $SD/img3.png" \
      --check "$AP/check-img.sh" --shim "$SHIM" --oracle /usr/bin/strace \
      --observe "$mode" --work "$R/wk/rep-$mode-$i" \
      > "$OUT/rep-mogrify.$mode-$i.txt" 2>&1
    echo "mogrify $mode run$i: raw rc=$?  $(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/rep-mogrify.$mode-$i.txt")"
  done
  i=$((i + 1))
done

echo "########## 3. qpdf を magick 生成の PDF で両モード ##########"
for mode in wrappers syscalls; do
  SD="$R/q2/$mode/qpdf"; export SD
  mkdir -p "$SD" "$R/wk/q2-$mode"
  "$SE" explore --state "$SD" --setup "$AP/setup-qpdf2.sh" \
    --operation "/usr/bin/qpdf --replace-input $SD/a.pdf" \
    --check "$AP/check-qpdf2.sh" --shim "$SHIM" --oracle /usr/bin/strace \
    --observe "$mode" --work "$R/wk/q2-$mode" > "$OUT/q2-qpdf.$mode.txt" 2>&1
  echo "qpdf2 $mode: raw rc=$?  $(grep -m1 -E '^(PASS|FAIL|UNKNOWN|SETUP ERROR)' "$OUT/q2-qpdf.$mode.txt")"
  grep -nE "crash point|earliest|oracle agree" "$OUT/q2-qpdf.$mode.txt" | head -3
done

mkdir -p /hostout
cp "$OUT"/tw-* "$OUT"/rep-* "$OUT"/q2-* /hostout/ 2>/dev/null
echo done
