#!/bin/sh
# Lab 9: libdeflate-gzip by hand under strace — it writes f.gz and removes f (programs/gzip.c),
# so the question is the order of the write, any fsync, and the unlink.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-9.sh
set -u
. /ap/env.sh
O=/out/lab-9; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close,utimensat,fchmod'
rm -rf /s/gz && mkdir -p /s/gz && cd /s/gz
head -c 300000 /dev/urandom | base64 > notes.txt; ls -l
strace -f -qq -s 0 -e trace=$T -o "$O/gzip.strace" libdeflate-gzip notes.txt > "$O/gzip.out" 2>&1; echo "exit $?"
grep -E 'O_TRUNC|O_CREAT|rename|unlink|truncate|fsync|write\(|close\(' "$O/gzip.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/lib|\.so|locale' | head -20
ls -l /s/gz
libdeflate-gzip -d notes.txt.gz; ls -l /s/gz; head -c 40 notes.txt; echo
