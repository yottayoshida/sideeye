#!/bin/sh
set -u
cat /tmp/apt-summary.txt
for b in ninja ccache pandoc meson coreutils uu-cp; do printf "%-12s %s\n" "$b" "$(command -v $b || echo -)"; done
ls /usr/lib/cargo/bin 2>/dev/null | head -5
mkdir -p /work/d/nj /work/d/cc /work/d/pd /work/d/ms/src /work/d/uu && cd /work/d
printf 'rule cp\n  command = cp $in $out\nbuild out.txt: cp in.txt\n' > /work/d/nj/build.ninja
printf 'hello MARKER\n' > /work/d/nj/in.txt
printf 'int main(void){return 0;}\n' > /work/d/a.c
printf 'int f(void){return 1;}\n' > /work/d/b.c
printf '# MARKER title\n\nbody text\n' > /work/d/in.md
printf '<html>old MARKER</html>\n' > /work/d/pd/out.html
printf "project('probe', 'c')\nexecutable('p', 'p.c')\n" > /work/d/ms/src/meson.build
printf 'int main(void){return 0;}\n' > /work/d/ms/src/p.c
printf 'SOURCE MARKER\n' > /work/d/uu/src.txt
printf 'DEST old content\n' > /work/d/uu/dst.txt
check() {
  name=$1; shift
  strace -f -e trace=clone,clone3 -o /tmp/tr-$name.txt "$@" > /tmp/op-$name.txt 2>&1
  rc=$?
  printf "%-12s thread=%-4s clone=%-4s rc=%-3s\n" "$name" "$(grep -c CLONE_THREAD /tmp/tr-$name.txt)" "$(grep -c clone /tmp/tr-$name.txt)" "$rc"
  [ "$rc" -ne 0 ] && echo "    失敗: $(head -3 /tmp/op-$name.txt | tr '\n' ' ' | cut -c1-170)"
  return 0
}
echo "=== 候補スクリーニング ==="
check ninja    ninja -C /work/d/nj
check ccache   env CCACHE_DIR=/work/d/cc ccache gcc -c /work/d/a.c -o /tmp/a.o
check pandoc   pandoc /work/d/in.md -o /work/d/pd/out.html
check meson    meson setup /work/d/ms/build /work/d/ms/src
UU=$(command -v coreutils || echo /usr/lib/cargo/bin/coreutils)
check uucp     "$UU" cp /work/d/uu/src.txt /work/d/uu/dst.txt
echo; echo "--- 書き込み後 ---"; ls -la /work/d/nj /work/d/pd /work/d/uu 2>/dev/null | head -20
file -L $(command -v ninja) $(command -v pandoc) "$UU" 2>/dev/null | cut -c1-90
