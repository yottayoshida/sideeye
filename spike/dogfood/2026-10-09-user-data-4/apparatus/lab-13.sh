#!/bin/sh
# Lab 13: buildx run standalone with the remote driver (no Docker daemon in the box), and zvm's
# version-map setting. Inside the box:
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-13.sh
set -u
. /ap/env.sh
O=/out/lab-13; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T,clone,clone3,execve -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c -E 'clone3?\(' "$O/$n.strace") clone"
    grep -E 'O_TRUNC|O_CREAT|O_APPEND|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -${MAXL:-14}
    tail -3 "$O/$n.out" | cut -c1-200
}
echo "## buildx"
rm -rf /s/aux/home/.docker && mkdir -p /s/bx && cd /s/bx
tr_ buildx-create1 buildx create --name b1 --driver remote tcp://127.0.0.1:1234
tr_ buildx-create2 buildx create --name b2 --driver remote tcp://127.0.0.1:1235
find /s/aux/home/.docker -type f | head; for f in $(find /s/aux/home/.docker -type f); do echo "--- $f"; head -c 300 "$f"; echo; done
tr_ buildx-use buildx use b2 --default
tr_ buildx-rm buildx rm b1
find /s/aux/home/.docker -type f | head

echo "## zvm"
rm -rf /s/aux/home/.zvm && cd /s/bx
zvm --help > "$O/zvm-help.txt" 2>&1; head -30 "$O/zvm-help.txt"
tr_ zvm-vmu1 zvm vmu zig https://example.org/zig-index.json
find /s/aux/home/.zvm -type f | head; cat /s/aux/home/.zvm/settings.json 2>/dev/null
tr_ zvm-vmu2 zvm vmu zls https://example.org/zls-index.json
cat /s/aux/home/.zvm/settings.json 2>/dev/null
