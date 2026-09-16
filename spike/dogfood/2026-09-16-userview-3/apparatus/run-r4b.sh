#!/bin/sh
# ninja: 既定のコンテナでは cgroup を作れず「群を出たプロセス」を止められない。
# 09-13 の ansible と同じく --privileged の root コンテナで測り直す。
# meson: screen で rc=1 だった理由を出してから define を書く。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so
R=/localrun; AP=$R/ap; OUTE=/out/explore; OUTP=/out/preflight
mkdir -p "$AP" "$OUTE" "$OUTP" "$R/wk" "$R/st" "$R/aux/src" "$R/aux/ms/src"

cat > "$AP/setup-ninja.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > "$SD/build.ninja"
printf 'MARKER first content\n' > "$SD/in.txt"
ninja -C "$SD" >/dev/null 2>&1
printf 'MARKER second content\n' > "$SD/in.txt"
EOS
cat > "$AP/check-ninja.sh" <<'EOC'
#!/bin/sh
[ -f "$SD/build.ninja" ] || { echo "build.ninja が無い"; exit 1; }
ninja -C "$SD" -n >/tmp/e.txt 2>&1 || {
  echo "ninja が build ディレクトリを読めない: $(head -2 /tmp/e.txt | tr '\n' ' ' | cut -c1-140)"; exit 1; }
[ -f "$SD/in.txt" ] || { echo "in.txt が消えた"; exit 1; }
grep -q MARKER "$SD/in.txt" || { echo "in.txt から MARKER が消えた"; exit 1; }
exit 0
EOC
chmod 755 "$AP"/*.sh

NJ=$R/st/nj2; mkdir -p "$NJ" "$R/wk/ex-ninja2"
SD="$NJ" "$SE" explore --state "$NJ" --setup "$AP/setup-ninja.sh" --operation "ninja -C $NJ" \
  --check "$AP/check-ninja.sh" --shim "$SHIM" --oracle /usr/bin/strace \
  --work "$R/wk/ex-ninja2" --json "$OUTE/ninja2.json" > "$OUTE/ninja2.txt" 2>&1
echo "=== ninja2（--privileged）raw rc=$? ==="; head -14 "$OUTE/ninja2.txt"; echo

echo "=== meson setup の失敗理由 ==="
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > "$R/aux/ms/src/meson.build"
printf 'int main(void){return 0;}\n' > "$R/aux/ms/src/p.c"
meson setup "$R/aux/ms/b1" "$R/aux/ms/src" 2>&1 | tail -8
