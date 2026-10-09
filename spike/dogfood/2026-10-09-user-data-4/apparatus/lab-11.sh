#!/bin/sh
# Lab 11: stack with its global project seeded (lab 10: `config set` asks the network for
# snapshots.json when ~/.stack/global-project/stack.yaml does not exist), and chdman with a unit
# size the hunk size divides (lab 10: "Hunk size 512 bytes is not a whole multiple of 4096").
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-11.sh
set -u
. /ap/env.sh
O=/out/lab-11; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T,clone,clone3,execve -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c -E 'clone3?\(' "$O/$n.strace") clone"
    grep -E 'O_TRUNC|O_CREAT|O_APPEND|rename|unlink|link\(|truncate|fsync|pwrite64' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -${MAXL:-14}
    tail -3 "$O/$n.out" | cut -c1-200
}
echo "## stack"
rm -rf /s/aux/home/.stack /s/stk && mkdir -p /s/stk /s/aux/home/.stack/global-project && cd /s/stk
printf 'snapshot: lts-22.44\npackages: []\n' > /s/aux/home/.stack/global-project/stack.yaml
printf '# This file contains default non-project-specific settings for Stack.\ntemplates:\n  params: null\ninstall-ghc: true\n' > /s/aux/home/.stack/config.yaml
tr_ stack stack config set install-ghc false --global
find /s/aux/home/.stack -maxdepth 2 | head; cat /s/aux/home/.stack/config.yaml

echo "## chdman"
rm -rf /s/chd && mkdir -p /s/chd && cd /s/chd
head -c 1048576 /dev/zero | tr '\0' 'A' > raw.bin
chdman createraw -i raw.bin -o d.chd -hs 4096 -us 512 > "$O/chd-seed.out" 2>&1; echo "createraw exit $?"; tail -2 "$O/chd-seed.out"; ls -l
tr_ chdman-addmeta chdman addmeta -i d.chd -t NOTE -vt hello
ls -l; chdman info -i d.chd 2>&1 | grep -A3 -i metadata | head -8
tr_ chdman-delmeta chdman delmeta -i d.chd -t NOTE
ls -l
