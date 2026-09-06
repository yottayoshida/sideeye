#!/bin/sh
# 2026-09-06 dogfood run: preflight が受理した 3 対象を explore する。
# checker はツール自身のコマンドで書く（rule 9 の厳しい読み）。fail closed:
# 対象が無い・読めないは失敗。
#
# 「読める」と「元の中身が残っている」は別の検査。metaflac は padding block の
# 20 バイトだけを書き換えるので、crash 後もファイルは読めうる——読めるだけを見る
# checker は、そのとき何も検査していない。だから setup が先に ORIG タグを書き、
# checker はそれが残っていることまで見る。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out-ex
AP=/work/ap
mkdir -p "$OUT" "$AP" /work/wk-ex

########## setup（engine が各 world で exec する）##########

cat > "$AP/setup-flac2.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/fl
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do
  flac -s -f /tmp/src.wav -o "/work/st/fl/$n.flac"
  metaflac --set-tag=ORIG=keep "/work/st/fl/$n.flac"
done
EOS

cat > "$AP/setup-mp32.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/m3
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do
  lame --quiet /tmp/src.wav "/work/st/m3/$n.mp3"
  mid3v2 --TXXX "ORIG:keep" "/work/st/m3/$n.mp3"
done
EOS

cat > "$AP/setup-ttf2.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/ff
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /work/st/ff/f.ttf
EOS

########## checker ##########

cat > "$AP/check-flac.sh" <<'EOC'
#!/bin/sh
for n in a b c; do
  f="/work/st/fl/$n.flac"
  [ -f "$f" ] || { echo "$n.flac が無い"; exit 1; }
  metaflac --list "$f" > /dev/null 2>&1 || {
    echo "$n.flac を metaflac が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  metaflac --export-tags-to=- "$f" 2>/dev/null | grep -q '^ORIG=keep$' || {
    echo "$n.flac から元のタグ ORIG=keep が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/check-mp3.sh" <<'EOC'
#!/bin/sh
for n in a b c; do
  f="/work/st/m3/$n.mp3"
  [ -f "$f" ] || { echo "$n.mp3 が無い"; exit 1; }
  mid3v2 -l "$f" > /dev/null 2>&1 || {
    echo "$n.mp3 を mid3v2 が読めない（$(wc -c < "$f") bytes）"; exit 1; }
  mid3v2 -l "$f" 2>/dev/null | grep -q 'keep' || {
    echo "$n.mp3 から元のタグ ORIG:keep が消えた"; exit 1; }
done
exit 0
EOC

cat > "$AP/check-ttf.sh" <<'EOC'
#!/bin/sh
f=/work/st/ff/f.ttf
[ -f "$f" ] || { echo "f.ttf が無い"; exit 1; }
fontforge -lang=ff -c "Open(\"$f\");" > /dev/null 2>&1 || {
  echo "f.ttf を fontforge が開けない（$(wc -c < "$f") bytes）"; exit 1; }
exit 0
EOC

chmod 755 "$AP"/*.sh
mkdir -p /work/st/fl /work/st/m3 /work/st/ff

go() {  # go <名前> <state> <setup> <operation> <check>
  name=$1; state=$2; setup=$3; op=$4; chk=$5
  echo "==================== $name ===================="
  mkdir -p "/work/wk-ex/$name"
  "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "/work/wk-ex/$name" --json "$OUT/$name.json" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -18 "$OUT/$name.txt"
  echo
}

go metaflac /work/st/fl "$AP/setup-flac2.sh" \
  "metaflac --set-tag=ARTIST=probe /work/st/fl/a.flac /work/st/fl/b.flac /work/st/fl/c.flac" \
  "$AP/check-flac.sh"

go mid3v2 /work/st/m3 "$AP/setup-mp32.sh" \
  "mid3v2 -a probe /work/st/m3/a.mp3 /work/st/m3/b.mp3 /work/st/m3/c.mp3" \
  "$AP/check-mp3.sh"

go fontforge /work/st/ff "$AP/setup-ttf2.sh" \
  'fontforge -lang=ff -c Open("/work/st/ff/f.ttf");Generate("/work/st/ff/f.ttf"); ' \
  "$AP/check-ttf.sh"
