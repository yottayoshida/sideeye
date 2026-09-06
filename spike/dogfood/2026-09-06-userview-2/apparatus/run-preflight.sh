#!/bin/sh
# 2026-09-06 dogfood run: 4 対象の preflight。
# rc はパイプに通す前に取る。setup は engine が exec するので 755 で置く。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out-pf
AP=/work/ap
mkdir -p "$OUT" "$AP"

########## setup スクリプト（engine が各 world で exec する）##########

cat > "$AP/setup-flac.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/fl
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do flac -s -f /tmp/src.wav -o "/work/st/fl/$n.flac"; done
EOS

cat > "$AP/setup-mp3.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/m3
python3 /work/mkwav.py /tmp/src.wav
for n in a b c; do lame --quiet /tmp/src.wav "/work/st/m3/$n.mp3"; done
EOS

cat > "$AP/setup-ttf.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/ff
cp /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /work/st/ff/f.ttf
EOS

cat > "$AP/setup-pdf.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st/mu
python3 /work/mkpdf.py /work/st/mu/a.pdf > /dev/null
EOS

cat > "$AP/op-ttf.sh" <<'EOS'
#!/bin/sh
exec fontforge -lang=ff -c 'Open("/work/st/ff/f.ttf"); Generate("/work/st/ff/f.ttf");'
EOS

chmod 755 "$AP"/*.sh

# state ディレクトリは preflight を呼ぶ前に存在していないと、engine が絶対パスへ
# 解決できず SETUP ERROR になる（中身は setup が作る）。
mkdir -p /work/st/fl /work/st/m3 /work/st/ff /work/st/mu

run() {  # run <名前> <preflight 引数...>
  name=$1; shift
  echo "==================== $name ===================="
  mkdir -p "/work/wk-pf/$name"
  "$SE" preflight "$@" --shim "$SHIM" --work "/work/wk-pf/$name" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc   (0=recording accepted, 2=refused)"
  tail -26 "$OUT/$name.txt"
  echo
}

########## 1. metaflac ##########
run metaflac \
  --state /work/st/fl \
  --setup "$AP/setup-flac.sh" \
  --operation "metaflac --set-tag=ARTIST=probe /work/st/fl/a.flac /work/st/fl/b.flac /work/st/fl/c.flac"

########## 2. mid3v2 ##########
run mid3v2 \
  --state /work/st/m3 \
  --setup "$AP/setup-mp3.sh" \
  --operation "mid3v2 -a probe /work/st/m3/a.mp3 /work/st/m3/b.mp3 /work/st/m3/c.mp3"

########## 3. fontforge ##########
run fontforge \
  --state /work/st/ff \
  --setup "$AP/setup-ttf.sh" \
  --operation 'fontforge -lang=ff -c Open("/work/st/ff/f.ttf");Generate("/work/st/ff/f.ttf"); ' 

########## 4. mutool ##########
run mutool \
  --state /work/st/mu \
  --setup "$AP/setup-pdf.sh" \
  --operation "mutool clean /work/st/mu/a.pdf /work/st/mu/a.pdf"
