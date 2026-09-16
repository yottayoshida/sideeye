#!/bin/sh
# meson: image に入れた ccache が既定のコンパイラ指定に割り込んでいた。CC を明示して測る。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore; OUTP=/out/preflight
mkdir -p "$AP" "$OUTE" "$OUTP" "$R/wk" "$R/st" "$R/aux/ms/src"
CC=gcc; export CC
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > "$R/aux/ms/src/meson.build"
printf 'int main(void){return 0;}\n' > "$R/aux/ms/src/p.c"

cat > "$AP/setup-meson.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
python3 -c "
import shutil,sys,os,glob
for p in glob.glob(os.path.join(sys.argv[1],'*'))+glob.glob(os.path.join(sys.argv[1],'.*')):
    if os.path.basename(p) in ('.','..'): continue
    shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) and not os.path.islink(p) else os.unlink(p)
" "$SD"
CC=gcc meson setup "$SD" /localrun/aux/ms/src >/dev/null 2>&1
EOS
cat > "$AP/check-meson.sh" <<'EOC'
#!/bin/sh
# 再設定の途中で落ちても、meson はその build ディレクトリを読める。
out=$(meson introspect --projectinfo "$SD" 2>/tmp/e.txt) || {
  echo "meson が build ディレクトリを読めない: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
echo "$out" | grep -q "probe" || { echo "projectinfo に probe が無い: $(echo "$out" | cut -c1-80)"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh
MS=$R/st/ms; mkdir -p "$MS" "$R/wk/pf-meson" "$R/wk/ex-meson"
SD="$MS" "$SE" preflight --state "$MS" --setup "$AP/setup-meson.sh" \
  --operation "meson setup --reconfigure $MS /localrun/aux/ms/src" \
  --shim "$SHIM" --work "$R/wk/pf-meson" > "$OUTP/meson.txt" 2>&1
echo "=== meson preflight rc=$? ==="; grep -E "^PREFLIGHT|^UNKNOWN|state-changing|^SETUP" "$OUTP/meson.txt" | head -3
SD="$MS" "$SE" explore --state "$MS" --setup "$AP/setup-meson.sh" \
  --operation "meson setup --reconfigure $MS /localrun/aux/ms/src" --check "$AP/check-meson.sh" \
  --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/ex-meson" --json "$OUTE/meson.json" > "$OUTE/meson.txt" 2>&1
echo "=== meson explore rc=$? ==="; head -14 "$OUTE/meson.txt"
