#!/bin/sh
# Lab 7: MCA Selector's command-line delete over a region file this run writes itself
# (defines/mcaselector/make_region.py), under strace, to learn whether it reads the file and how
# it writes it back. Inside the box:
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-7.sh
set -u
. /ap/env.sh
O=/out/lab-7; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
rm -rf /s/mc && mkdir -p /s/mc/world/region && cd /s/mc
python3 /ap/defines/mcaselector/make_region.py /s/mc/world/region 6
ls -l /s/mc/world/region; sha256sum /s/mc/world/region/r.0.0.mca
# MCA Selector wants a world directory with region/ (and poi/, entities/ for newer worlds).
mkdir -p /s/mc/world/poi /s/mc/world/entities
strace -f -qq -s 0 -e trace=$T -o "$O/mca-select.strace" /opt/mcaselector/bin/mcaselector --mode select --world /s/mc/world --query "InhabitedTime < 1000" --output /s/mc/sel.csv > "$O/mca-select.out" 2>&1; echo "select exit $?"
grep -v -E 'log4j|^\s+at |UnknownHost|Caused by|more$' "$O/mca-select.out" | head -8; cat /s/mc/sel.csv 2>/dev/null | head
strace -f -qq -s 0 -e trace=$T -o "$O/mca-delete.strace" /opt/mcaselector/bin/mcaselector --mode delete --world /s/mc/world --query "InhabitedTime < 1000" > "$O/mca-delete.out" 2>&1; echo "delete exit $?"
grep -v -E 'log4j|^\s+at |UnknownHost|Caused by|more$' "$O/mca-delete.out" | head -8
grep -E 'O_TRUNC|O_CREAT|rename|unlink|truncate|fsync' "$O/mca-delete.strace" | grep -E '/s/mc' | head -20
ls -l /s/mc/world/region; sha256sum /s/mc/world/region/r.0.0.mca
grep -c 'clone' "$O/mca-delete.strace" || true
