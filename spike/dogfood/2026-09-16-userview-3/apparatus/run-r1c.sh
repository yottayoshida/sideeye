#!/bin/sh
# zstd を syscalls 観測モードで測る（wrappers モードでは stdio の write を shim が記録できなかった）。
set -u
SE=/se/sideeye; SHIM=/se/libsideeye_shim.so; R=/localrun; AP=$R/ap; OUTE=/out/explore
mkdir -p "$AP" "$OUTE" "$R/wk" "$R/st" "$R/aux"
cp /hostap/*.toml "$AP"/ 2>/dev/null
cat > "$AP/setup-zstd.sh" <<'EOS'
#!/bin/sh
set -eu
mkdir -p "$SD"
rm -f "$SD/f.bin.zst"
python3 - "$SD/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(20000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp "$SD/f.bin" /localrun/aux/f.bin.orig
EOS
cat > "$AP/check-zstd.sh" <<'EOC'
#!/bin/sh
orig=/localrun/aux/f.bin.orig
if [ -f "$SD/f.bin" ]; then
  cmp -s "$SD/f.bin" "$orig" && exit 0
  echo "f.bin が残っているが中身が違う（$(wc -c < "$SD/f.bin") bytes / 元 $(wc -c < "$orig")）"; exit 1
fi
if [ -f "$SD/f.bin.zst" ]; then
  zstd -q -d -c "$SD/f.bin.zst" > /tmp/out.bin 2>/tmp/zerr.txt || {
    echo "原本が消え、f.bin.zst も展開できない（$(wc -c < "$SD/f.bin.zst") bytes）: $(head -1 /tmp/zerr.txt)"; exit 1; }
  cmp -s /tmp/out.bin "$orig" && exit 0
  echo "原本が消え、f.bin.zst の中身が元と違う"; exit 1
fi
echo "原本も .zst も無い（データが消えた）"; exit 1
EOC
chmod 755 "$AP"/*.sh
ZS=$R/st/zs; mkdir -p "$ZS" "$R/wk/ex-zstd-sys"
SD="$ZS" "$SE" explore --state "$ZS" --setup "$AP/setup-zstd.sh" \
  --operation "zstd -q --rm $ZS/f.bin" --check "$AP/check-zstd.sh" \
  --shim "$SHIM" --oracle /usr/bin/strace --observe syscalls \
  --work "$R/wk/ex-zstd-sys" --json "$OUTE/zstd-syscalls.json" > "$OUTE/zstd-syscalls.txt" 2>&1
echo "raw rc=$?"
head -16 "$OUTE/zstd-syscalls.txt"
