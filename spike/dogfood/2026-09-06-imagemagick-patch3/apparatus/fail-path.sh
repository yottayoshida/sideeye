#!/bin/sh
# 書き込みが ENOSPC で失敗したときの巻き戻しを見る。crash は使わない。
# 3 度目の patch は backup 名にランダム hex を付けるので、~ の後をワイルドカードで拾う。
/usr/bin/magick -size 128x128 xc: +noise Random /src.png
ORIG=$(sha256sum /src.png | cut -c1-16)
echo "元画像: $(wc -c < /src.png) bytes  sha256=$ORIG"
echo
run() {
  echo "=== $1 ==="
  rm -f /tiny/img1.png /tiny/img1.png~*
  cp /src.png /tiny/img1.png
  $2 -resize 1600% /tiny/img1.png > /tmp/e 2>&1
  echo "  mogrify rc=$?   stderr: $(head -1 /tmp/e | cut -c1-70)"
  found=0
  for f in /tiny/img1.png /tiny/img1.png~*; do
    [ -e "$f" ] || continue
    found=$((found+1))
    h=$(sha256sum "$f" | cut -c1-16)
    if [ "$h" = "$ORIG" ]; then same="元画像と同一"; else same="元画像と別物"; fi
    if /usr/bin/magick "$f" /dev/null 2>/dev/null; then dec="完全にデコードできる"; else dec="デコードが途中で失敗"; fi
    echo "  $f  $(wc -c < "$f") bytes  links=$(stat -c %h "$f")  sha=$h  $same  $dec"
  done
  echo "  ディレクトリに残ったファイル数: $found"
}
run "patch前 Debian 7.1.1-43" /usr/bin/mogrify
run "patch後 main 960adadd" /opt/im/bin/mogrify
