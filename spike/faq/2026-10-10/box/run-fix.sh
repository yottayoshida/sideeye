#!/bin/sh
set -u
res() { echo "RESULT $1 rc=$2"; }
cp -r /box/fsync /tmp/fsync; cd /tmp/fsync
sideeye explore --config unflushed.toml --oracle /usr/bin/strace --work /tmp/w6 --json /out/unflushed.json > /out/unflushed.txt 2>&1; res unflushed $?
cp -r /box/xdg /tmp/xdg; cd /tmp/xdg; mkdir -p /tmp/home2
HOME=/tmp/home2 XDG_CONFIG_HOME=/tmp/xdgtool-state/config \
  sideeye explore --config sideeye.toml --oracle /usr/bin/strace --work /tmp/w7 > /out/xdg-missing.txt 2>&1; res xdg-missing $?
{ echo "HOME after the run that forgot XDG_DATA_HOME:"; find /tmp/home2 -mindepth 1 | sort; } > /out/xdg-missing-home.txt; cat /out/xdg-missing-home.txt
cp -r /box/rs /tmp/rs; cd /tmp/rs
cargo test -q --offline > /out/rs-clean.txt 2>&1; res rs-clean $?
cargo test -q --offline --features buggy > /out/rs-bug.txt 2>&1; res rs-bug $?
sed 's|.args(\["--oracle", "/usr/bin/strace"\])|.args(["--allow-unverified"])|' tests/crash_consistency.rs > /tmp/c.rs && cp /tmp/c.rs tests/crash_consistency.rs
cargo test -q --offline > /out/rs-nooracle.txt 2>&1; res rs-nooracle $?
cp /box/rs/tests/crash_consistency.rs tests/
PATH=/usr/bin:/bin cargo test -q --offline > /out/rs-nosideeye.txt 2>&1; res rs-nosideeye $?
