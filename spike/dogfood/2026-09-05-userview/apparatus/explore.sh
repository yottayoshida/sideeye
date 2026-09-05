#!/bin/sh
# 4本の explore。checker は必ずツール自身のコマンドで書く（rule 9 の厳しい読み）。
# checker は fail closed: 対象が無い・読めないは失敗。
# --work は state の外に置く（engine 自身の記録が対象の状態に混ざるため）。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out3
WK=/work/wk
mkdir -p "$OUT" "$WK"

go() {  # go <名前> <state> <setup> <operation> <check>
  name=$1; state=$2; setup=$3; op=$4; chk=$5
  echo "==================== $name ===================="
  "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "$WK/$name" --json "$OUT/$name.json" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc   (0=PASS  1=FAIL  2=UNKNOWN  3=setup error)"
  head -14 "$OUT/$name.txt"
  echo
}

########## 1. mogrify ##########
# 約束: 各画像を変換して書き戻す。crash 後も各ファイルは読める画像であってほしい。
mkdir -p /work/im
cat > /work/im-setup.sh <<'EOS'
#!/bin/sh
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=red:s=128x128 -frames:v 1 -y "/work/im/img$n.png"
done
EOS
cat > /work/im-check.sh <<'EOC'
#!/bin/sh
for n in 1 2 3; do
  f="/work/im/img$n.png"
  [ -f "$f" ] || { echo "img$n.png が無い"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "img$n.png を identify が読めない（$(wc -c < "$f") bytes）"; exit 1; }
done
exit 0
EOC
chmod 755 /work/im-setup.sh /work/im-check.sh
go mogrify /work/im /work/im-setup.sh \
  "/usr/bin/mogrify -resize 50% /work/im/img1.png /work/im/img2.png /work/im/img3.png" \
  /work/im-check.sh

########## 2. qpdf ##########
mkdir -p /work/pdf
cat > /work/pdf-setup.sh <<'EOS'
#!/bin/sh
ffmpeg -loglevel error -f lavfi -i color=c=blue:s=128x128 -frames:v 1 -y /tmp/x.png
convert /tmp/x.png /work/pdf/a.pdf 2>/dev/null || magick /tmp/x.png /work/pdf/a.pdf
EOS
cat > /work/pdf-check.sh <<'EOC'
#!/bin/sh
f=/work/pdf/a.pdf
[ -f "$f" ] || { echo "a.pdf が無い"; exit 1; }
qpdf --check "$f" > /dev/null 2>&1 || { echo "qpdf --check が通らない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC
chmod 755 /work/pdf-setup.sh /work/pdf-check.sh
go qpdf /work/pdf /work/pdf-setup.sh "/usr/bin/qpdf --replace-input /work/pdf/a.pdf" /work/pdf-check.sh

########## 3. exiv2 ##########
mkdir -p /work/ex
cat > /work/ex-setup.sh <<'EOS'
#!/bin/sh
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y "/work/ex/pic$n.jpg"
done
EOS
cat > /work/ex-check.sh <<'EOC'
#!/bin/sh
for n in 1 2 3; do
  f="/work/ex/pic$n.jpg"
  [ -f "$f" ] || { echo "pic$n.jpg が無い"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "pic$n.jpg を identify が読めない（$(wc -c < "$f") bytes）"; exit 1; }
done
exit 0
EOC
chmod 755 /work/ex-setup.sh /work/ex-check.sh
go exiv2 /work/ex /work/ex-setup.sh \
  "/usr/bin/exiv2 rm /work/ex/pic1.jpg /work/ex/pic2.jpg /work/ex/pic3.jpg" /work/ex-check.sh

########## 4. rdiff-backup ##########
# 約束: バックアップ先は rdiff-backup 自身が検証できる状態であること。
mkdir -p /work/rb/src
cat > /work/rb-setup.sh <<'EOS'
#!/bin/sh
mkdir -p /work/rb/src
printf 'one\n' > /work/rb/src/f1.txt
printf 'two\n' > /work/rb/src/f2.txt
rdiff-backup backup /work/rb/src /work/rb/bk > /dev/null 2>&1
sleep 2
printf 'one changed\n' > /work/rb/src/f1.txt
EOS
cat > /work/rb-check.sh <<'EOC'
#!/bin/sh
# rdiff-backup 自身に検証させる。壊れていれば非ゼロ。
[ -d /work/rb/bk ] || { echo "bk が無い"; exit 1; }
rdiff-backup verify /work/rb/bk > /tmp/v.txt 2>&1 || { echo "verify が通らない: $(tail -2 /tmp/v.txt|tr '\n' ' ')"; exit 1; }
exit 0
EOC
chmod 755 /work/rb-setup.sh /work/rb-check.sh
go rdiff-backup /work/rb/bk /work/rb-setup.sh \
  "/usr/bin/rdiff-backup backup /work/rb/src /work/rb/bk" /work/rb-check.sh
