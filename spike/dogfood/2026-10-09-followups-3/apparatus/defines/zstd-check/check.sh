#!/bin/sh
# zstd --rm replaces f.bin with f.bin.zst, so no path exists before and after (nothing_could_fail without a
# checker, transcripts/explore/zstd-noasync). This judges the data: f.bin is the original, or f.bin.zst
# decompresses to it.
S="$SIDEEYE_STATE_DIR"; o=/s/zstd/f.orig
[ -f "$S/f.bin" ] && cmp -s "$S/f.bin" "$o" && exit 0
[ -f "$S/f.bin.zst" ] && zstd -q -dc "$S/f.bin.zst" 2>/dev/null | cmp -s - "$o" && exit 0
echo "neither f.bin nor f.bin.zst holds the data ($(ls "$S" | tr '\n' ' '))"; exit 1
