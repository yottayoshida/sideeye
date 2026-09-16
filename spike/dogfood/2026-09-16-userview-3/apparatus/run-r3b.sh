#!/bin/sh
# ラウンド3 再測定: bat は時刻を固定（metadata.yaml が run ごとに変わる）、
# tesseract は checker を強くする（「空でない」だけではゴミを受け入れてしまった）。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux/batsrc"

cat > "$AP/setup-bat.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/batsrc
batcat cache --build --source /localrun/aux/batsrc --target "$SD" >/dev/null 2>&1
EOS
cat > "$AP/check-bat.sh" <<'EOC'
#!/bin/sh
out=$(BAT_CACHE_PATH="$SD" batcat --list-themes 2>/tmp/e.txt) || {
  echo "batcat がテーマ一覧を出せない: $(head -1 /tmp/e.txt | tr -d '\033')"; exit 1; }
echo "$out" | grep -q . || { echo "テーマ一覧が空（cache が壊れた）"; exit 1; }
exit 0
EOC
cat > "$AP/bat.toml" <<'EOT'
[world]
state = "/localrun/st/bt2"
[define]
setup = "/localrun/ap/setup-bat.sh"
operation = ["batcat", "cache", "--build", "--source", "/localrun/aux/batsrc", "--target", "/localrun/st/bt2"]
check = "/localrun/ap/check-bat.sh"
apparatus = ["env:FAKETIME=@2024-01-01 00:00:00", "preload:libfaketime"]
EOT

mkpng='python3 -c "
from PIL import Image, ImageDraw
import sys
im = Image.new(\"RGB\", (160, 60), \"white\")
ImageDraw.Draw(im).text((6, 20), \"MARKER TEXT\", fill=\"black\")
im.save(sys.argv[1])
"'
cat > "$AP/setup-tesseract.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD"
$mkpng "\$SD/a.png"
printf 'MARKER previous result\n' > "\$SD/out.txt"
EOS
cat > "$AP/check-tesseract.sh" <<'EOC'
#!/bin/sh
# out.txt は「前の結果」か「新しい OCR 結果」のどちらかとして読める。
# どちらでもない中身（途中で切れた・ゴミ）は利用者が前の結果を失った状態。
f="$SD/out.txt"
[ -f "$f" ] || { echo "out.txt が無い（書き出し中に消えた）"; exit 1; }
[ -s "$f" ] || { echo "out.txt が空になった（前の結果も消えた）"; exit 1; }
if grep -q "MARKER previous result" "$f"; then exit 0; fi
if grep -qi "MARKER" "$f"; then exit 0; fi
echo "out.txt が前の結果でも OCR 結果でもない（$(wc -c < "$f") bytes: $(head -c 60 "$f" | tr '\n' ' ')）"
exit 1
EOC
chmod 755 "$AP"/*.sh

FT=$(find /usr/lib -name 'libfaketime.so*' 2>/dev/null | head -1); echo "$FT" > /etc/ld.so.preload
FAKETIME="@2024-01-01 00:00:00"; export FAKETIME
mkdir -p "$R/st/bt2" "$R/wk/ex-bat2"
SD=$R/st/bt2 "$SE" explore --config "$AP/bat.toml" --shim "$SHIM" --oracle /usr/bin/strace \
  --work "$R/wk/ex-bat2" --json "$OUTE/bat2.json" > "$OUTE/bat2.txt" 2>&1
echo "=== bat2 raw rc=$? ==="; head -13 "$OUTE/bat2.txt"; echo
: > /etc/ld.so.preload; unset FAKETIME

TS=$R/st/ts2; mkdir -p "$TS" "$R/wk/ex-tesseract2"
SD="$TS" "$SE" explore --state "$TS" --setup "$AP/setup-tesseract.sh" \
  --operation "tesseract $TS/a.png $TS/out" --check "$AP/check-tesseract.sh" \
  --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-tesseract2" --json "$OUTE/tesseract2.json" > "$OUTE/tesseract2.txt" 2>&1
echo "=== tesseract2 raw rc=$? ==="; head -14 "$OUTE/tesseract2.txt"
