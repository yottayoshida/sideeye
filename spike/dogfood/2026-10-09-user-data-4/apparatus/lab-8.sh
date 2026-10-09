#!/bin/sh
# Lab 8: the third layer's four tools by hand under strace — nmctl context set, yarn config set,
# trash (sindresorhus), softhsm2-util — to find each operation and read its write path.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-8.sh
set -u
. /ap/env.sh
O=/out/lab-8; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c clone "$O/$n.strace") clone"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale|node_modules' | head -${MAXL:-16}
}

echo "## nmctl"
rm -rf "$HOME/.netmaker" /s/nm && mkdir -p /s/nm && cd /s/nm
nmctl context set c0 --endpoint=https://api.example.org --master_key=k0 > "$O/nmctl-seed.out" 2>&1; echo "seed exit $?"; find "$HOME/.netmaker" -type f | head; cat "$HOME"/.netmaker/* 2>/dev/null | head -12
tr_ nmctl nmctl context set c1 --endpoint=https://api2.example.org --master_key=k1
find "$HOME/.netmaker" -type f -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; | head -20

echo "## yarn"
rm -rf /s/yarn "$HOME/.yarnrc.yml" && mkdir -p /s/yarn && cd /s/yarn
printf 'nodeLinker: node-modules\nenableTelemetry: false\n' > "$HOME/.yarnrc.yml"
yarn --version
tr_ yarn yarn config set -H npmAuthToken placeholder-npm-auth-token
cat "$HOME/.yarnrc.yml"

echo "## trash"
rm -rf /s/trash "$HOME/.local/share/Trash" && mkdir -p /s/trash && cd /s/trash
printf 'a report, 40 bytes of text that matter\n' > report.txt
tr_ trash trash report.txt
ls -la /s/trash; find "$HOME/.local/share/Trash" -type f | head; cat "$HOME"/.local/share/Trash/info/*.trashinfo 2>/dev/null

echo "## softhsm2"
rm -rf /s/hsm && mkdir -p /s/hsm/tokens && cd /s/hsm
printf 'directories.tokendir = /s/hsm/tokens\nobjectstore.backend = file\nlog.level = ERROR\n' > /s/hsm/softhsm2.conf
export SOFTHSM2_CONF=/s/hsm/softhsm2.conf
softhsm2-util --init-token --free --label t --pin 1234 --so-pin 5678 > "$O/hsm-seed.out" 2>&1; echo "init exit $?"; cat "$O/hsm-seed.out" | head -3
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /s/hsm/k.pem > /dev/null 2>&1; echo "key exit $?"
find /s/hsm/tokens -type f | head
tr_ softhsm-import softhsm2-util --import /s/hsm/k.pem --token t --pin 1234 --label k1 --id 01
find /s/hsm/tokens -type f | head
tr_ softhsm-delete softhsm2-util --delete-token --token t
find /s/hsm/tokens | head
