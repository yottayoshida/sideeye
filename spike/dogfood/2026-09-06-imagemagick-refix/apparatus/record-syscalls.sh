#!/bin/sh
# patch 前後の書き込み経路を並べる。grep はファイル名にかかるものだけ。
echo "== builds"
/usr/bin/mogrify --version | head -1
/opt/im/bin/mogrify --version | head -1
echo
for pair in "Debian-7.1.1-43:/usr/bin/mogrify" "main-3501ef34:/opt/im/bin/mogrify"; do
  name=${pair%%:*}; mog=${pair#*:}
  echo "== $name"
  /lab/setup.sh
  strace -f -e trace=rename,renameat,link,linkat,openat,unlink,unlinkat \
    "$mog" -resize 50% /work/im/img1.png 2>&1 | grep img1
  echo
done
