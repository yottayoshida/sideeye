#!/bin/sh
# 3 度目の patch (960adadd, temp+rename) が、元ファイルの属性・出力形式・別名からの
# 見え方をどう変えるか。各項目を patch 前 (Debian 7.1.1-43) と後 (960adadd) で並べる。
set -u
OLD=/usr/bin/mogrify
NEW=/opt/im/bin/mogrify
each() { for pair in "patch前-7.1.1-43:$OLD" "patch後-960adadd:$NEW"; do n=${pair%%:*}; m=${pair#*:}; "$1" "$n" "$m"; done; }
hr() { echo; echo "======== $1 ========"; }

c_case() { n=$1; m=$2
  rm -rf /work/c; mkdir -p /work/c
  magick -size 64x64 xc:red /work/c/img1.png
  "$m" -resize 50% /work/c/img1.png > /work/c/err 2>&1; rc=$?
  fmt=$(identify -format '%m %wx%h' /work/c/img1.png 2>/dev/null) || fmt="READ-FAIL"
  echo "  $n  rc=$rc  identify=[$fmt]  file=[$(file -b /work/c/img1.png | cut -c1-38)]"
  [ -s /work/c/err ] && echo "      stderr: $(head -2 /work/c/err | tr '\n' ' ')"
  leftover=$(ls /work/c | grep '~' | tr '\n' ' ')
  [ -n "$leftover" ] && echo "      残骸: $leftover"
  return 0
}

d_case() { n=$1; m=$2
  rm -rf /work/d; mkdir -p /work/d
  magick -size 64x64 xc:red /work/d/img1.png
  chmod 600 /work/d/img1.png
  b=$(stat -c %a /work/d/img1.png); bi=$(stat -c %i /work/d/img1.png)
  "$m" -resize 50% /work/d/img1.png >/dev/null 2>&1; rc=$?
  echo "  $n  rc=$rc  mode $b -> $(stat -c %a /work/d/img1.png)   inode $([ "$bi" = "$(stat -c %i /work/d/img1.png)" ] && echo 同じ || echo 変わった)"
}

e_case() { n=$1; m=$2
  rm -rf /work/e; mkdir -p /work/e
  magick -size 64x64 xc:red /work/e/img1.png
  touch -d '2020-01-01 00:00:00' /work/e/img1.png
  b=$(stat -c %y /work/e/img1.png | cut -c1-19)
  "$m" -define preserve-timestamp=true -resize 50% /work/e/img1.png >/dev/null 2>&1; rc=$?
  echo "  $n  rc=$rc  mtime $b -> $(stat -c %y /work/e/img1.png | cut -c1-19)"
}

f_case() { n=$1; m=$2
  rm -rf /work/f; mkdir -p /work/f
  magick -size 64x64 xc:red xc:blue /work/f/multi.gif
  fb=$(identify /work/f/multi.gif 2>/dev/null | wc -l)
  "$m" +adjoin -resize 50% /work/f/multi.gif > /work/f/err 2>&1; rc=$?
  echo "  $n  rc=$rc  frames_before=$fb  出来たファイル: $(ls /work/f | grep -v '^err$' | tr '\n' ' ')"
  [ -s /work/f/err ] && echo "      stderr: $(head -2 /work/f/err | tr '\n' ' ')"
  return 0
}

j_case() { n=$1; m=$2
  rm -rf /work/j; mkdir -p /work/j
  magick -size 64x64 xc:red /work/j/img1.png
  ln /work/j/img1.png /work/j/alias.png
  "$m" -resize 50% /work/j/img1.png >/dev/null 2>&1; rc=$?
  s1=$(identify -format '%wx%h' /work/j/img1.png 2>/dev/null); s2=$(identify -format '%wx%h' /work/j/alias.png 2>/dev/null)
  echo "  $n  rc=$rc  img1.png=[$s1 links=$(stat -c %h /work/j/img1.png)]  alias.png=[$s2 links=$(stat -c %h /work/j/alias.png)]  別名にも反映: $([ "$s1" = "$s2" ] && echo yes || echo no)"
}

k_case() { n=$1; m=$2
  rm -rf /work/k; mkdir -p /work/k
  magick -size 64x64 xc:red /work/k/real.png
  ln -s real.png /work/k/link.png
  "$m" -resize 50% /work/k/link.png >/dev/null 2>&1; rc=$?
  echo "  $n  rc=$rc  link.png は $([ -L /work/k/link.png ] && echo 'symlink のまま' || echo '実体に置き換わった')  real.png=[$(identify -format '%wx%h' /work/k/real.png 2>/dev/null)]  link.png=[$(identify -format '%wx%h' /work/k/link.png 2>/dev/null)]"
}

echo "元画像はすべて 64x64、-resize 50% なので、成功なら 32x32 になる。"
hr "C: temp 名 (img1.png~xxxxxxxx) の拡張子で coder が決まるか"; each c_case
hr "D: mode が保存されるか（元を 0600 にしてから）"; each d_case
hr "E: preserve-timestamp が効くか（元の mtime を 2020-01-01 に）"; each e_case
hr "F: 2 フレームの GIF を +adjoin で in-place"; each f_case
hr "J: hard link した別名から見た内容"; each j_case
hr "K: symlink に対する in-place"; each k_case
