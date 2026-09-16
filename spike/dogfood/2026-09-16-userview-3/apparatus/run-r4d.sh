#!/bin/sh
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux/src" "$R/aux/ms/src"
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > "$R/aux/ms/src/meson.build"
printf 'int main(void){return 0;}\n' > "$R/aux/ms/src/p.c"
echo "=== meson setup を state ディレクトリに対して直に走らせる ==="
mkdir -p "$R/st/ms3"
CC=gcc meson setup "$R/st/ms3" "$R/aux/ms/src" 2>&1 | tail -6

echo
echo "=== ccache: cache から取り出せることを検査に入れる ==="
cat > "$AP/setup-ccache.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD" /localrun/aux/src
printf 'int main(void){return 0;}\n' > /localrun/aux/src/a.c
printf 'int f(void){return 1;}\n' > /localrun/aux/src/b.c
CCACHE_DIR="$SD" ccache gcc -c /localrun/aux/src/a.c -o /localrun/aux/src/a.o >/dev/null 2>&1
cp /localrun/aux/src/a.o /localrun/aux/src/a.o.golden
EOS
cat > "$AP/check-ccache.sh" <<'EOC'
#!/bin/sh
# 前に cache へ入れた a.c が、cache から取り出せる（当たる）こと。
# 「ccache -s が動く」だけでは、中身がゴミでも通ってしまった。
before=$(CCACHE_DIR="$SD" ccache --print-stats 2>/dev/null | awk '$1=="direct_cache_hit"{print $2}')
[ -n "$before" ] || { echo "ccache の統計が読めない"; exit 1; }
CCACHE_DIR="$SD" ccache gcc -c /localrun/aux/src/a.c -o /tmp/chk.o >/tmp/e.txt 2>&1 || {
  echo "cache を使ったコンパイルが失敗した: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-120)"; exit 1; }
after=$(CCACHE_DIR="$SD" ccache --print-stats 2>/dev/null | awk '$1=="direct_cache_hit"{print $2}')
[ "$after" -gt "$before" ] || {
  echo "前に入れた a.c が cache から取り出せない（direct_cache_hit $before -> $after）"; exit 1; }
cmp -s /tmp/chk.o /localrun/aux/src/a.o.golden || {
  echo "cache から出てきた .o が元と違う"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh
CC2=$R/st/cc2; mkdir -p "$CC2" "$R/wk/ex-ccache2"
CCACHE_DIR=$CC2; export CCACHE_DIR
SD="$CC2" "$SE" explore --state "$CC2" --setup "$AP/setup-ccache.sh" \
  --operation "ccache gcc -c /localrun/aux/src/b.c -o /localrun/aux/src/b.o" --check "$AP/check-ccache.sh" \
  --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-ccache2" --json "$OUTE/ccache2.json" > "$OUTE/ccache2.txt" 2>&1
echo "=== ccache2 rc=$? ==="; head -14 "$OUTE/ccache2.txt"
