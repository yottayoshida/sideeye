#!/bin/sh
# ラウンド4: preflight → explore を 5 対象で。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTP=/out/preflight; OUTE=/out/explore
mkdir -p "$AP" "$OUTP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
"$SE" version
echo "--- meson が screen で失敗した理由 ---"
mkdir -p /localrun/aux/ms/src
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > /localrun/aux/ms/src/meson.build
printf 'int main(void){return 0;}\n' > /localrun/aux/ms/src/p.c
meson setup /localrun/aux/ms/b1 /localrun/aux/ms/src 2>&1 | tail -6

cat > "$AP/setup-ninja.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$SD/build.ninja"
printf 'MARKER first content\n' > "$SD/in.txt"
ninja -C "$SD" >/dev/null 2>&1
# 次のビルドに仕事がある状態にする
printf 'MARKER second content\n' > "$SD/in.txt"
EOS
cat > "$AP/check-ninja.sh" <<'EOC'
#!/bin/sh
# 途中で落ちても、ninja はその build ディレクトリでまた動ける。
[ -f "$SD/build.ninja" ] || { echo "build.ninja が無い"; exit 1; }
ninja -C "$SD" -n >/tmp/e.txt 2>&1 || {
  echo "ninja が build ディレクトリを読めない: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
[ -f "$SD/in.txt" ] || { echo "in.txt が消えた"; exit 1; }
grep -q MARKER "$SD/in.txt" || { echo "in.txt から MARKER が消えた"; exit 1; }
exit 0
EOC

cat > "$AP/setup-ccache.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/src
printf 'int main(void){return 0;}\n' > /localrun/aux/src/a.c
printf 'int f(void){return 1;}\n' > /localrun/aux/src/b.c
CCACHE_DIR="$SD" ccache gcc -c /localrun/aux/src/a.c -o /localrun/aux/src/a.o >/dev/null 2>&1
EOS
cat > "$AP/check-ccache.sh" <<'EOC'
#!/bin/sh
# 追加の途中で落ちても、ccache は自分の cache を読める。
out=$(CCACHE_DIR="$SD" ccache -s 2>/tmp/e.txt) || {
  echo "ccache -s が失敗した: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
echo "$out" | grep -qi "cache" || { echo "ccache -s の出力が読めない"; exit 1; }
CCACHE_DIR="$SD" ccache gcc -c /localrun/aux/src/a.c -o /localrun/aux/src/a2.o >/tmp/e2.txt 2>&1 || {
  echo "cache を使ったコンパイルが失敗した: $(head -2 /tmp/e2.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
exit 0
EOC

cat > "$AP/setup-pandoc.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux
printf '# MARKER title\n\nbody text\n' > /localrun/aux/in.md
printf '<html>MARKER old output</html>\n' > "$SD/out.html"
EOS
cat > "$AP/check-pandoc.sh" <<'EOC'
#!/bin/sh
# 上書きの途中で落ちても、out.html は前の出力か新しい出力のどちらかとして残る。
f="$SD/out.html"
[ -f "$f" ] || { echo "out.html が無い（上書き中に消えた）"; exit 1; }
[ -s "$f" ] || { echo "out.html が空になった（前の出力も消えた）"; exit 1; }
grep -q "MARKER old output" "$f" && exit 0
grep -q "MARKER title" "$f" && exit 0
echo "out.html が前の出力でも新しい出力でもない（$(wc -c < "$f") bytes: $(head -c 50 "$f" | tr '\n' ' ')）"
exit 1
EOC

cat > "$AP/setup-uucp.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'SOURCE MARKER content\n' > "$SD/src.txt"
printf 'DEST MARKER old content\n' > "$SD/dst.txt"
EOS
cat > "$AP/check-uucp.sh" <<'EOC'
#!/bin/sh
# 上書きコピーの途中で落ちても、宛先は元の中身か新しい中身のどちらかとして読める。
f="$SD/dst.txt"
[ -f "$f" ] || { echo "dst.txt が無い（コピー中に消えた）"; exit 1; }
[ -s "$f" ] || { echo "dst.txt が空になった（元の中身が消えた）"; exit 1; }
grep -q "DEST MARKER old content" "$f" && exit 0
grep -q "SOURCE MARKER content" "$f" && exit 0
echo "dst.txt が元の中身でも新しい中身でもない（$(wc -c < "$f") bytes: $(head -c 50 "$f" | tr '\n' ' ')）"
exit 1
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

NJ=$R/st/nj; CC=$R/st/cc; PD=$R/st/pd; UU=$R/st/uu
pf ninja "$NJ" "$AP/setup-ninja.sh" "ninja -C $NJ"
ex ninja "$NJ" "$AP/setup-ninja.sh" "ninja -C $NJ" "$AP/check-ninja.sh"
CCACHE_DIR=$CC; export CCACHE_DIR
pf ccache "$CC" "$AP/setup-ccache.sh" "ccache gcc -c /localrun/aux/src/b.c -o /localrun/aux/src/b.o"
ex ccache "$CC" "$AP/setup-ccache.sh" "ccache gcc -c /localrun/aux/src/b.c -o /localrun/aux/src/b.o" "$AP/check-ccache.sh"
unset CCACHE_DIR
pf pandoc "$PD" "$AP/setup-pandoc.sh" "pandoc /localrun/aux/in.md -o $PD/out.html"
ex pandoc "$PD" "$AP/setup-pandoc.sh" "pandoc /localrun/aux/in.md -o $PD/out.html" "$AP/check-pandoc.sh"
pf uucp "$UU" "$AP/setup-uucp.sh" "/usr/bin/coreutils cp $UU/src.txt $UU/dst.txt"
ex uucp "$UU" "$AP/setup-uucp.sh" "/usr/bin/coreutils cp $UU/src.txt $UU/dst.txt" "$AP/check-uucp.sh"
