#!/bin/sh
# A shada file of ordinary size — several kilobytes, more than one of the writer's 4 KiB buffers —
# with the rewrite's tail made to fail by `ulimit -f`. The source reads as: the buffer is flushed to
# the temporary file whenever it runs low, the temporary is renamed over main.shada, and the last
# flush happens in close_file after the rename. So a limit above what was flushed before the rename
# and below the whole file should leave main.shada cut at the limit. The next nvim is asked to read
# it. No Sideeye.
set -u
export HOME=/tmp/h XDG_STATE_HOME=/tmp/s; mkdir -p $HOME $XDG_STATE_HOME /tmp/base
{ i=1; while [ $i -le 400 ]; do printf 'call histadd("cmd", "echo history entry number %04d with some padding text")\n' $i; i=$((i+1)); done
  printf 'call setreg("a", "first register")\nwshada!\nqa!\n'; } > /tmp/setup.vim
printf 'call histadd("cmd", "echo second")\nwshada\nqa!\n' > /tmp/op.vim
printf 'call writefile([getreg("a"), string(len(filter(map(range(1, 450), "histget(\\"cmd\\", v:val)"), "v:val != \\"\\"")))], "/tmp/read.txt")\nset shada=\nqa!\n' > /tmp/read.vim
nvim --headless -n -u NONE -i /tmp/base/main.shada -S /tmp/setup.vim
full=$(wc -c < /tmp/base/main.shada)
echo "setup: main.shada $full bytes"
# The first version tried 4096..20480 bytes: every one of them stopped the rewrite before the rename
# (main.shada intact, main.shada.tmp.a left behind), so the tail written after the rename is under
# 4 KiB of a 25,715-byte file. These limits sit in that last stretch.
for blocks in 8 40 42 44 46 48 49 50; do
  d=/tmp/l$blocks; rm -rf $d; mkdir -p $d; cp /tmp/base/main.shada $d/
  ( ulimit -f $blocks; nvim --headless -n -u NONE -i $d/main.shada -S /tmp/op.vim ) > $d/op.out 2>&1; rc=$?
  size=$( [ -f $d/main.shada ] && wc -c < $d/main.shada || echo absent )
  : > /tmp/read.txt
  nvim --headless -n -u NONE -i $d/main.shada -S /tmp/read.vim > $d/read.out 2>&1
  printf 'limit %5d bytes: op rc=%s, main.shada %s bytes, files: %s\n' $((blocks*512)) "$rc" "$size" "$(ls $d | grep -v '\.out$' | tr '\n' ' ')"
  printf '    next nvim reads: register a "%s", %s history entries; says: %s\n' "$(sed -n 1p /tmp/read.txt)" "$(sed -n 2p /tmp/read.txt)" "$(grep -m1 -o 'E57[0-9][^"]*' $d/read.out | cut -c1-110)"
done
