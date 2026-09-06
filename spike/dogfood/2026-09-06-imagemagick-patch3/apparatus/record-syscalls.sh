#!/bin/sh
# patch 前と 3 度目の patch の書き込み経路を並べる。preserve-timestamp を付けて
# utimensat の位置も同じ列に出す。grep はファイル名と utimensat にかかるものだけ。
echo "== builds"
/usr/bin/mogrify --version | head -1
/opt/im/bin/mogrify --version | head -1
echo
for pair in "Debian-7.1.1-43:/usr/bin/mogrify" "main-960adadd:/opt/im/bin/mogrify"; do
  name=${pair%%:*}; mog=${pair#*:}
  echo "== $name"
  /lab/setup.sh
  touch -d '2020-01-01 00:00:00' /work/im/img1.png
  strace -f -e trace=rename,renameat,link,linkat,openat,unlink,unlinkat,utimensat \
    "$mog" -define preserve-timestamp=true -resize 50% /work/im/img1.png 2>&1 \
    | grep -E "img1|utimensat"
  echo "   -> mtime after: $(stat -c %y /work/im/img1.png | cut -c1-19)"
  echo
done
