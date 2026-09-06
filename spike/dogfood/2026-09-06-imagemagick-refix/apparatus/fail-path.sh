#!/bin/sh
# 書き込みが ENOSPC で失敗したときの巻き戻しを見る。crash は使わない。
/usr/bin/magick -size 128x128 xc: +noise Random /src.png
ORIG=$(sha256sum /src.png | cut -c1-16)
echo "元画像: $(wc -c < /src.png) bytes  sha256=$ORIG"
echo
run() {
  echo "=== $1 ==="
  rm -f /tiny/img1.png /tiny/img1.png~
  cp /src.png /tiny/img1.png
  $2 -resize 1600% /tiny/img1.png > /dev/null 2>&1
  echo "  mogrify rc=$?"
  for f in /tiny/img1.png /tiny/img1.png~; do
    if [ -e "$f" ]; then
      h=$(sha256sum "$f" | cut -c1-16)
      if [ "$h" = "$ORIG" ]; then same="元画像と同一"; else same="元画像と別物"; fi
      if /usr/bin/magick "$f" /dev/null 2>/dev/null; then dec="完全にデコードできる"; else dec="デコードが途中で失敗"; fi
      echo "  $f  $(wc -c < "$f") bytes  links=$(stat -c %h "$f")  sha=$h  $same  $dec"
    else
      echo "  $f  存在しない"
    fi
  done
}
run "Debian 7.1.1-43 (patch 前)" /usr/bin/mogrify
run "main 3501ef34 (patch 後)" /opt/im/bin/mogrify
