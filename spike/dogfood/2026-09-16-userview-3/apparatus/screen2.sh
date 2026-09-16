#!/bin/sh
# ラウンド2 スクリーニング: 動的リンクか / 実際の書き込み操作でスレッドを作るか。
set -u
cat /tmp/apt-summary.txt
mkdir -p /work/d && cd /work/d

# fish の履歴
mkdir -p /work/d/fhome
# pip: Debian が同梱する wheel をローカルから入れる（ネットを使わない）
ls /usr/share/python-wheels/ 2>/dev/null | head -5
# rrdtool: 既存の RRD
rrdtool create /work/d/t.rrd --start 1700000000 --step 60 DS:v:GAUGE:120:U:U RRA:AVERAGE:0.5:1:100 2>/dev/null && echo "rrd created"
# neomutt: mbox
printf 'From a@b Thu Jan  1 00:00:00 2026\nSubject: one\n\nbody one\n\nFrom a@b Thu Jan  1 00:01:00 2026\nSubject: two\n\nbody two\n' > /work/d/box
# composer: 最小の composer.json
mkdir -p /work/d/php/src
printf '{"name":"probe/probe","autoload":{"psr-4":{"Probe\\\\":"src/"}}}' > /work/d/php/composer.json
printf '<?php namespace Probe; class A {}\n' > /work/d/php/src/A.php
echo "--- 素材 ---"; ls -la /work/d

check() {
  name=$1; bin=$2; shift 2
  path=$(command -v "$bin" 2>/dev/null)
  if [ -z "$path" ]; then printf "%-12s 見つからない\n" "$name"; return 0; fi
  kind=$(file -L "$path" | cut -d: -f2- | cut -c1-46)
  if file -L "$path" | grep -q "statically linked"; then link=static
  elif file -L "$path" | grep -qi "ELF"; then link=dynamic
  else link=script; fi
  strace -f -e trace=clone,clone3 -o /tmp/tr-$name.txt "$@" > /tmp/op-$name.txt 2>&1
  rc=$?
  th=$(grep -c CLONE_THREAD /tmp/tr-$name.txt 2>/dev/null | head -1)
  ch=$(grep -c clone /tmp/tr-$name.txt 2>/dev/null | head -1)
  printf "%-12s %-8s thread=%-4s clone=%-4s rc=%-3s %s\n" "$name" "$link" "$th" "$ch" "$rc" "$kind"
  [ "$rc" -ne 0 ] && echo "    失敗: $(head -3 /tmp/op-$name.txt | tr '\n' ' ' | cut -c1-170)"
  return 0
}

echo
echo "=== 候補スクリーニング（実操作で測る）==="
check fish     fish     env HOME=/work/d/fhome fish -c 'echo hi'
check pip      pip3     pip3 install --no-index --no-deps --target /work/d/site /usr/share/python-wheels/wheel-*.whl
check rrdtool  rrdtool  rrdtool update /work/d/t.rrd 1700000060:42
check neomutt  neomutt  env HOME=/work/d/fhome neomutt -F /dev/null -f /work/d/box -e 'set quit=yes' -e 'push <delete-message><sync-mailbox><quit>'
check composer composer env HOME=/work/d/fhome COMPOSER_HOME=/work/d/fhome/.composer composer --working-dir=/work/d/php --no-interaction dump-autoload

echo
echo "--- 書き込み後 ---"; ls -la /work/d; ls -la /work/d/php 2>/dev/null | head -5
