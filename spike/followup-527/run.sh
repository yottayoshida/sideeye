#!/bin/sh
# 2026-09-07: 同じ対象を --observe wrappers と --observe syscalls の両方で測る。
#
# なぜ両方か: #527 は新しいモードが「届く」ことを 2 対象で測ったが、既定モードが
# すでに判定できていた対象で判定が変わらないことは toy でしか測っていない。
# 静かに verdict が変わる経路が実対象で残っている。
#
# state と work はコンテナローカルに置く（$R）。#528 の実測: macOS の bind mount
# 上では restore 後のファイルの /proc/self/fd/N が " (deleted)" に解決し、
# unresolvable_path の偽の拒否が出る。ホストから来るのは engine だけ。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
OUT=$R/out
mkdir -p "$AP" "$OUT" "$R/wk"
cp /hostap/mkwav.py /hostap/mkpdf.py "$AP/"

"$SE" --version

########## setup / checker ##########
# どれも $SD（そのモード・その対象の state 親）を読む。engine は環境変数を
# setup / operation / checker へ通すので、呼ぶ側が SD を export すれば足りる。

cat > "$AP/setup-flac.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
python3 /localrun/ap/mkwav.py /tmp/src.wav
for n in a b c; do
  flac -s -f /tmp/src.wav -o "$SD/$n.flac"
  metaflac --set-tag=ORIG=keep "$SD/$n.flac"
done
EOS

cat > "$AP/check-flac.sh" <<'EOC'
#!/bin/sh
for n in a b c; do
  f="$SD/$n.flac"
  [ -f "$f" ] || { echo "$n.flac が無い"; exit 1; }
  metaflac --list "$f" > /dev/null 2>&1 || { echo "$n.flac を metaflac が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  metaflac --export-tags-to=- "$f" 2>/dev/null | grep -q '^ORIG=keep$' || { echo "$n.flac から ORIG=keep が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-mp3.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
python3 /localrun/ap/mkwav.py /tmp/src.wav
for n in a b c; do
  lame --quiet /tmp/src.wav "$SD/$n.mp3"
  mid3v2 --TXXX "ORIG:keep" "$SD/$n.mp3"
done
EOS

cat > "$AP/check-mp3.sh" <<'EOC'
#!/bin/sh
for n in a b c; do
  f="$SD/$n.mp3"
  [ -f "$f" ] || { echo "$n.mp3 が無い"; exit 1; }
  mid3v2 -l "$f" > /dev/null 2>&1 || { echo "$n.mp3 を mid3v2 が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  mid3v2 -l "$f" 2>/dev/null | grep -q 'keep' || { echo "$n.mp3 から ORIG:keep が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-ttf.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf "$SD/f.ttf"
EOS

cat > "$AP/check-ttf-ff.sh" <<'EOC'
#!/bin/sh
f="$SD/f.ttf"
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fontforge -lang=ff -c "Open(\"$f\");" > /dev/null 2>&1 || { echo "f.ttf を fontforge が開けない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/check-ttf-fonttools.sh" <<'EOC'
#!/bin/sh
f="$SD/f.ttf"
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fonttools ttx -q -o /dev/null "$f" > /dev/null 2>&1 || { echo "f.ttf を fonttools が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

# item 1 の形: シェル wrapper が bare name を exec する（PATH 探索で ENOENT が並ぶ）。
cat > "$AP/op-ttf-wrapper.sh" <<'EOS'
#!/bin/sh
exec fontforge -lang=ff -c "Open(\"$SD/f.ttf\"); Generate(\"$SD/f.ttf\");"
EOS

cat > "$AP/setup-pdf.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
python3 /localrun/ap/mkpdf.py "$SD/a.pdf" > /dev/null
EOS

cat > "$AP/check-pdf-mutool.sh" <<'EOC'
#!/bin/sh
f="$SD/a.pdf"
[ -f "$f" ] || { echo "a.pdf が無い"; exit 1; }
mutool info "$f" > /dev/null 2>&1 || { echo "a.pdf を mutool が読めない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/check-pdf-qpdf.sh" <<'EOC'
#!/bin/sh
f="$SD/a.pdf"
[ -f "$f" ] || { echo "a.pdf が無い"; exit 1; }
qpdf --check "$f" > /dev/null 2>&1 || { echo "qpdf --check が通らない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

cat > "$AP/setup-tar.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD" /tmp/tsrc
printf 'one\n'   > /tmp/tsrc/f1.txt
printf 'two\n'   > /tmp/tsrc/f2.txt
printf 'three\n' > /tmp/tsrc/f3.txt
bsdtar -cf "$SD/a.tar" -C /tmp/tsrc f1.txt f2.txt
EOS

cat > "$AP/check-tar.sh" <<'EOC'
#!/bin/sh
a="$SD/a.tar"
[ -f "$a" ] || { echo "a.tar が無い"; exit 1; }
list=$(bsdtar -tf "$a" 2>/dev/null) || { echo "a.tar を bsdtar が読めない（$(wc -c < "$a") bytes）"; exit 1; }
for n in f1.txt f2.txt; do
  echo "$list" | grep -qx "$n" || { echo "a.tar から元の $n が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-bean.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
cat > "$SD/l.beancount" <<'EOB'
2026-01-01 open Assets:Cash
2026-01-01 open Expenses:Food
2026-01-02 * "lunch"
  Expenses:Food   10.00 JPY
  Assets:Cash
2026-01-03 * "coffee"
  Expenses:Food    3.50 JPY
  Assets:Cash
EOB
EOS

cat > "$AP/check-bean.sh" <<'EOC'
#!/bin/sh
f="$SD/l.beancount"
[ -f "$f" ] || { echo "l.beancount が無い"; exit 1; }
bean-check "$f" > /dev/null 2>&1 || { echo "bean-check が通らない（$(wc -c < "$f") bytes）"; exit 1; }
for t in lunch coffee; do
  grep -q "\"$t\"" "$f" || { echo "元の取引 $t が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-isort.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
cat > "$SD/a.py" <<'EOP'
import sys
import os
from collections import OrderedDict
import json

MARKER = "keep-me"
print(sys.argv, os.sep, OrderedDict(), json.dumps({}), MARKER)
EOP
cat > "$SD/b.py" <<'EOP'
import zlib
import base64
import abc

MARKER = "keep-me-too"
print(zlib.crc32(b""), base64.b64encode(b""), abc.ABC, MARKER)
EOP
EOS

cat > "$AP/check-isort.sh" <<'EOC'
#!/bin/sh
for n in a b; do
  f="$SD/$n.py"
  [ -f "$f" ] || { echo "$n.py が無い"; exit 1; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || { echo "$n.py をパースできない（$(wc -c < "$f") bytes）"; exit 1; }
  grep -q "MARKER" "$f" || { echo "$n.py から MARKER が消えた"; exit 1; }
done
for m in sys os collections json; do
  grep -q "$m" "$SD/a.py" || { echo "a.py から import $m が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-pyupgrade.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
cat > "$SD/a.py" <<'EOP'
MARKER = "keep-me"
s = "%s-%s" % (1, 2)
d = dict()
print(s, d, MARKER)
EOP
EOS

cat > "$AP/check-pyupgrade.sh" <<'EOC'
#!/bin/sh
f="$SD/a.py"
[ -f "$f" ] || { echo "a.py が無い"; exit 1; }
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || { echo "a.py をパースできない（$(wc -c < "$f") bytes）"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.py から MARKER が消えた"; exit 1; }
exit 0
EOC

cat > "$AP/setup-jpegtran.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
python3 - <<'PY'
import os
w = h = 32
with open('/tmp/src.ppm', 'wb') as f:
    f.write(b'P6\n%d %d\n255\n' % (w, h))
    f.write(bytes([(x * 7 + y * 3) % 256 for y in range(h) for x in range(w) for _ in range(3)]))
PY
cjpeg -quality 80 -outfile "$SD/a.jpg" /tmp/src.ppm
EOS

cat > "$AP/check-jpegtran.sh" <<'EOC'
#!/bin/sh
f="$SD/a.jpg"
[ -f "$f" ] || { echo "a.jpg が無い"; exit 1; }
out=$(djpeg -pnm "$f" 2>/dev/null | head -c 32) || { echo "a.jpg を djpeg が読めない（$(wc -c < "$f") bytes）"; exit 1; }
[ -n "$out" ] || { echo "a.jpg から画素が出てこない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

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

cat > "$AP/setup-exiv.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
for n in 1 2 3; do
  ffmpeg -loglevel error -f lavfi -i color=c=green:s=128x128 -frames:v 1 -y "$SD/pic$n.jpg"
done
EOS

cat > "$AP/check-exiv.sh" <<'EOC'
#!/bin/sh
for n in 1 2 3; do
  f="$SD/pic$n.jpg"
  [ -f "$f" ] || { echo "pic$n.jpg が無い"; exit 1; }
  identify "$f" > /dev/null 2>&1 || { echo "pic$n.jpg を identify が読めない（$(wc -c < "$f") bytes）"; exit 1; }
done
exit 0
EOC

cat > "$AP/setup-rb.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD/src"
printf 'one\n' > "$SD/src/f1.txt"
printf 'two\n' > "$SD/src/f2.txt"
rdiff-backup backup "$SD/src" "$SD/bk" > /dev/null 2>&1
sleep 2
printf 'one changed\n' > "$SD/src/f1.txt"
EOS

cat > "$AP/check-rb.sh" <<'EOC'
#!/bin/sh
[ -d "$SD/bk" ] || { echo "bk が無い"; exit 1; }
rdiff-backup verify "$SD/bk" > /tmp/v.txt 2>&1 || { echo "verify が通らない: $(tail -2 /tmp/v.txt | tr '\n' ' ')"; exit 1; }
exit 0
EOC

chmod 755 "$AP"/*.sh

########## driver ##########
# 1 対象 1 モードにつき 1 行だけ表に載せる値を出す: 生の rc と、report の
# 見出し行そのまま。#528 の教訓——数え直すスクリプトが列を膨らませたので、
# 集計はせず report の1行を逐語で写す。

go() {  # go <名前> <state 相対> <setup> <op テンプレート> <check> [追加引数...]
  name=$1; rel=$2; setup=$3; optmpl=$4; chk=$5; shift 5
  case "${ONLY:-}" in "") ;; *" $name "*) ;; *) return 0 ;; esac
  for mode in wrappers syscalls; do
    SD="$R/st/$mode/$name"
    export SD
    state="$SD$rel"
    mkdir -p "$SD" "$state" "$R/wk/$mode/$name"
    op=$(printf '%s' "$optmpl" | sed "s|@SD@|$SD|g")
    echo "==================== $name / $mode ===================="
    echo "op: $op"
    "$SE" explore --state "$state" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/$chk" --shim "$SHIM" --oracle /usr/bin/strace \
      --observe "$mode" --work "$R/wk/$mode/$name" \
      --json "$OUT/$name.$mode.json" "$@" > "$OUT/$name.$mode.txt" 2>&1
    rc=$?
    echo "raw rc=$rc   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
    grep -nE "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/$name.$mode.txt" | head -2
    grep -nE "crash point|oracle (agree|missed)|divergence at|violation" "$OUT/$name.$mode.txt" | head -4
    echo
  done
}

go metaflac  "" setup-flac.sh      'metaflac --set-tag=ARTIST=probe @SD@/a.flac @SD@/b.flac @SD@/c.flac' check-flac.sh
go mid3v2    "" setup-mp3.sh       'mid3v2 -a probe @SD@/a.mp3 @SD@/b.mp3 @SD@/c.mp3' check-mp3.sh
go fontforge "" setup-ttf.sh       'fontforge -lang=ff -c Open("@SD@/f.ttf");Generate("@SD@/f.ttf"); ' check-ttf-ff.sh
go ffwrapper "" setup-ttf.sh       '/localrun/ap/op-ttf-wrapper.sh' check-ttf-ff.sh
go mutool    "" setup-pdf.sh       'mutool clean @SD@/a.pdf @SD@/a.pdf' check-pdf-mutool.sh
go fonttools "" setup-ttf.sh       'fonttools subset @SD@/f.ttf --output-file=@SD@/f.ttf --unicodes=U+0041-005A' check-ttf-fonttools.sh
go bsdtar    "" setup-tar.sh       'bsdtar -uf @SD@/a.tar -C /tmp/tsrc f3.txt' check-tar.sh
go beanfmt   "" setup-bean.sh      'bean-format -o @SD@/l.beancount @SD@/l.beancount' check-bean.sh
go isort     "" setup-isort.sh     'isort @SD@/a.py @SD@/b.py' check-isort.sh
go pyupgrade "" setup-pyupgrade.sh 'pyupgrade --py311-plus @SD@/a.py' check-pyupgrade.sh --expect-status 1
go jpegtran  "" setup-jpegtran.sh  'jpegtran -copy all -optimize -outfile @SD@/a.jpg @SD@/a.jpg' check-jpegtran.sh
go mogrify   "" setup-img.sh       '/usr/bin/mogrify -resize 50% @SD@/img1.png @SD@/img2.png @SD@/img3.png' check-img.sh
go qpdf      "" setup-pdf.sh       '/usr/bin/qpdf --replace-input @SD@/a.pdf' check-pdf-qpdf.sh
go exiv2     "" setup-exiv.sh      '/usr/bin/exiv2 rm @SD@/pic1.jpg @SD@/pic2.jpg @SD@/pic3.jpg' check-exiv.sh
go rdiffbk   /bk setup-rb.sh       '/usr/bin/rdiff-backup backup @SD@/src @SD@/bk' check-rb.sh

echo "==== copying transcripts out ===="
mkdir -p /hostout
cp "$OUT"/* /hostout/ 2>/dev/null
echo done
