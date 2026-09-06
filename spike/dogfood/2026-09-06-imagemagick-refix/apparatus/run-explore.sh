#!/bin/sh
# patch 前（Debian 7.1.1-43）と patch 後（main 3501ef34）を、2 つの checker で測る。
#   check-original-name  = #8939 で報告した不変条件（コマンドラインの名前にファイルがある）
#   check-recoverable    = 元の名前か ~ のどちらかに読める画像が残っている（回復可能性）
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
OUT=/lab/out
mkdir -p "$OUT" /work/wk

go() { # go <名前> <mogrify のパス> <checker>
  name=$1; mog=$2; chk=$3
  echo "==================== $name ===================="
  "$SE" explore --state /work/im --setup /lab/setup.sh \
    --operation "$mog -resize 50% /work/im/img1.png" \
    --check "$chk" --shim "$SHIM" --oracle /usr/bin/strace \
    --work "/work/wk/$name" --json "$OUT/$name.json" > "$OUT/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS  1=FAIL  2=UNKNOWN  3=setup error)"
  head -16 "$OUT/$name.txt"
  echo
}

go deb-original    /usr/bin/mogrify    /lab/check-original-name.sh
go deb-recoverable /usr/bin/mogrify    /lab/check-recoverable.sh
go main-original   /opt/im/bin/mogrify /lab/check-original-name.sh
go main-recoverable /opt/im/bin/mogrify /lab/check-recoverable.sh
