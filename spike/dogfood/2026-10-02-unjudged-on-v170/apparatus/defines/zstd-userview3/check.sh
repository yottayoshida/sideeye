#!/bin/sh
orig=/s/zstd-userview3/aux/f.bin.orig
if [ -f "/s/zstd-userview3/state/f.bin" ]; then
  cmp -s "/s/zstd-userview3/state/f.bin" "$orig" && exit 0
  echo "f.bin が残っているが中身が違う（$(wc -c < "/s/zstd-userview3/state/f.bin") bytes / 元 $(wc -c < "$orig")）"; exit 1
fi
if [ -f "/s/zstd-userview3/state/f.bin.zst" ]; then
  zstd -q -d -c "/s/zstd-userview3/state/f.bin.zst" > /tmp/out.bin 2>/tmp/zerr.txt || {
    echo "原本が消え、f.bin.zst も展開できない（$(wc -c < "/s/zstd-userview3/state/f.bin.zst") bytes）: $(head -1 /tmp/zerr.txt)"; exit 1; }
  cmp -s /tmp/out.bin "$orig" && exit 0
  echo "原本が消え、f.bin.zst の中身が元と違う"; exit 1
fi
echo "原本も .zst も無い（データが消えた）"; exit 1
