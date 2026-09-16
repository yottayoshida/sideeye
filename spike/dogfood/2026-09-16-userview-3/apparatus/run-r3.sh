#!/bin/sh
# ラウンド3: preflight → explore を 5 対象で。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTP=/out/preflight; OUTE=/out/explore
mkdir -p "$AP" "$OUTP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
"$SE" version

mkpng='python3 -c "
from PIL import Image, ImageDraw
import sys
im = Image.new(\"RGB\", (160, 60), \"white\")
ImageDraw.Draw(im).text((6, 20), \"MARKER TEXT\", fill=\"black\")
im.save(sys.argv[1])
"'

cat > "$AP/setup-bat.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD" /localrun/aux/batsrc
batcat cache --build --source /localrun/aux/batsrc --target "\$SD" >/dev/null 2>&1
EOS
cat > "$AP/check-bat.sh" <<'EOC'
#!/bin/sh
out=$(BAT_CACHE_PATH="$SD" batcat --list-themes 2>/tmp/e.txt) || {
  echo "batcat がテーマ一覧を出せない: $(head -1 /tmp/e.txt)"; exit 1; }
echo "$out" | grep -q . || { echo "テーマ一覧が空（cache が壊れた）"; exit 1; }
BAT_CACHE_PATH="$SD" batcat --language sh --plain /etc/hostname >/dev/null 2>/tmp/e2.txt || {
  echo "cache を読んだ batcat が動かない: $(head -1 /tmp/e2.txt)"; exit 1; }
exit 0
EOC

cat > "$AP/setup-sphinx.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/docsrc
printf 'project = "probe"\nextensions = []\n' > /localrun/aux/docsrc/conf.py
printf 'Probe\n=====\n\nMARKER body text.\n' > /localrun/aux/docsrc/index.rst
sphinx-build -q -b html /localrun/aux/docsrc "$SD" >/dev/null 2>&1
EOS
cat > "$AP/check-sphinx.sh" <<'EOC'
#!/bin/sh
f="$SD/index.html"
[ -f "$f" ] || { echo "index.html が無い"; exit 1; }
[ -s "$f" ] || { echo "index.html が空になった"; exit 1; }
grep -q "MARKER body text" "$f" || { echo "index.html から本文が消えた（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/setup-virtualenv.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
python3 -c "
import shutil,sys,os,glob
for p in glob.glob(os.path.join(sys.argv[1],'*')):
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
" "$SD"
virtualenv -q --no-download "$SD/v1" >/dev/null 2>&1
EOS
cat > "$AP/check-virtualenv.sh" <<'EOC'
#!/bin/sh
# 2 つ目の venv を作っている途中で落ちても、前からある v1 は動く。
[ -x "$SD/v1/bin/python" ] || { echo "v1/bin/python が無いか実行できない"; exit 1; }
"$SD/v1/bin/python" -c "import sys; sys.exit(0)" 2>/tmp/e.txt || {
  echo "v1 の python が動かない: $(tail -1 /tmp/e.txt)"; exit 1; }
exit 0
EOC

cat > "$AP/setup-vips.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD"
$mkpng "\$SD/a.png"
$mkpng "\$SD/out.png"
EOS
cat > "$AP/check-vips.sh" <<'EOC'
#!/bin/sh
# 上書きの途中で落ちても、out.png は前の絵か新しい絵のどちらかとして開ける。
f="$SD/out.png"
[ -f "$f" ] || { echo "out.png が無い（上書き中に消えた）"; exit 1; }
[ -s "$f" ] || { echo "out.png が空になった"; exit 1; }
w=$(vipsheader -f width "$f" 2>/tmp/e.txt) || {
  echo "out.png が画像として開けない（$(wc -c < "$f") bytes）: $(head -1 /tmp/e.txt)"; exit 1; }
[ "$w" = "160" ] || { echo "out.png の幅が 160 でない: $w"; exit 1; }
exit 0
EOC

cat > "$AP/setup-tesseract.sh" <<EOS
#!/bin/sh
set -eu
mkdir -p "\$SD"
$mkpng "\$SD/a.png"
printf 'MARKER previous result\n' > "\$SD/out.txt"
EOS
cat > "$AP/check-tesseract.sh" <<'EOC'
#!/bin/sh
# 書き出しの途中で落ちても、out.txt は前の結果か新しい結果のどちらかとして残る。
f="$SD/out.txt"
[ -f "$f" ] || { echo "out.txt が無い（書き出し中に消えた）"; exit 1; }
[ -s "$f" ] || { echo "out.txt が空になった（前の結果も消えた）"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

pf() { name=$1; state=$2; setup=$3; op=$4; shift 4
  echo "-------- preflight: $name --------"; mkdir -p "$R/wk/pf-$name" "$state"
  SD="$state" "$SE" preflight --state "$state" --setup "$setup" --operation "$op" \
    --shim "$SHIM" --work "$R/wk/pf-$name" "$@" > "$OUTP/$name.txt" 2>&1
  echo "raw rc=$?"; grep -E "^PREFLIGHT|^UNKNOWN|state-changing|^SETUP" "$OUTP/$name.txt" | head -3; }
ex() { name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="; mkdir -p "$R/wk/ex-$name" "$state"
  SD="$state" "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?"; head -13 "$OUTE/$name.txt"; echo; }

BT=$R/st/bt; SP=$R/st/sp; VV=$R/st/vv; VP=$R/st/vp; TS=$R/st/ts
BAT_CACHE_PATH=$BT; export BAT_CACHE_PATH
pf bat "$BT" "$AP/setup-bat.sh" "batcat cache --build --source /localrun/aux/batsrc --target $BT"
ex bat "$BT" "$AP/setup-bat.sh" "batcat cache --build --source /localrun/aux/batsrc --target $BT" "$AP/check-bat.sh"
unset BAT_CACHE_PATH
pf sphinx "$SP" "$AP/setup-sphinx.sh" "sphinx-build -q -b html /localrun/aux/docsrc $SP"
ex sphinx "$SP" "$AP/setup-sphinx.sh" "sphinx-build -q -b html /localrun/aux/docsrc $SP" "$AP/check-sphinx.sh"
pf virtualenv "$VV" "$AP/setup-virtualenv.sh" "virtualenv -q --no-download $VV/v2"
ex virtualenv "$VV" "$AP/setup-virtualenv.sh" "virtualenv -q --no-download $VV/v2" "$AP/check-virtualenv.sh"
pf vips "$VP" "$AP/setup-vips.sh" "vips copy $VP/a.png $VP/out.png"
ex vips "$VP" "$AP/setup-vips.sh" "vips copy $VP/a.png $VP/out.png" "$AP/check-vips.sh"
pf tesseract "$TS" "$AP/setup-tesseract.sh" "tesseract $TS/a.png $TS/out"
ex tesseract "$TS" "$AP/setup-tesseract.sh" "tesseract $TS/a.png $TS/out" "$AP/check-tesseract.sh"
