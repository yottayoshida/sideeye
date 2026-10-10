#!/bin/sh
set -u
res() { echo "RESULT $1 rc=$2"; }
cp -r /box/xdg /tmp/xdg; cp -r /box/fsync /tmp/fsync
mkdir -p /tmp/emptyhome
cd /tmp/xdg
# 1) 変数を state の下に向ける。HOME は空のディレクトリ
HOME=/tmp/emptyhome XDG_CONFIG_HOME=/tmp/xdgtool-state/config XDG_DATA_HOME=/tmp/xdgtool-state/data \
  sideeye explore --config sideeye.toml --oracle /usr/bin/strace --work /tmp/w1 --json /out/xdg-under.json > /out/xdg-under.txt 2>&1; res xdg-under $?
echo "HOME after: $(find /tmp/emptyhome -mindepth 1 | wc -l) entries" > /out/xdg-home.txt; cat /out/xdg-home.txt
# 2) 変数を 1 つ渡し忘れる → apparatus が止めるか
HOME=/tmp/emptyhome XDG_CONFIG_HOME=/tmp/xdgtool-state/config \
  sideeye explore --config sideeye.toml --oracle /usr/bin/strace --work /tmp/w2 > /out/xdg-missing.txt 2>&1; res xdg-missing $?
# 3) データ側だけ state の外へ（apparatus は外して、何が返るかを見る）
grep -v '^apparatus' sideeye.toml > outside.toml
mkdir -p /tmp/outside
HOME=/tmp/emptyhome XDG_CONFIG_HOME=/tmp/xdgtool-state/config XDG_DATA_HOME=/tmp/outside/data \
  sideeye explore --config outside.toml --oracle /usr/bin/strace --work /tmp/w3 --json /out/xdg-outside.json > /out/xdg-outside.txt 2>&1; res xdg-outside $?
# 4) fsync も flush も無い rename
cd /tmp/fsync
sideeye explore --config sideeye.toml --oracle /usr/bin/strace --work /tmp/w4 --json /out/nosync.json > /out/nosync.txt 2>&1; res nosync $?
