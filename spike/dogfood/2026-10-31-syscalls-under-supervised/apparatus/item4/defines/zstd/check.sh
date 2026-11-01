#!/bin/sh
# spike/followup-item4/run.sh's check-zstd.sh, with its $SD spelled out.
SD=/s/zstd/state
if [ -f "$SD/a.bin" ]; then [ "$(wc -c < "$SD/a.bin")" = 300000 ] || { echo "a.bin truncated"; exit 1; }; exit 0; fi
[ -f "$SD/a.bin.zst" ] || { echo "neither a.bin nor a.bin.zst"; exit 1; }
zstd -t -q "$SD/a.bin.zst" || { echo "a.bin.zst does not decompress and a.bin is gone"; exit 1; }
exit 0
