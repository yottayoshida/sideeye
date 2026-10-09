#!/bin/sh
# Lab 3: why ccache's operations differ between runs (kill_did_not_land, clock pinned or not).
# Two clean runs from the same seed under strace; the calls on the state directory compared, first
# as they are, then with hex runs and 6-character temporary suffixes replaced.
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-3.sh
set -u
. /ap/env.sh
. /ap/defines/ccache/env.sh
for i in 1 2; do
  sh /ap/defines/ccache/seed.sh > /dev/null 2>&1
  strace -f -qq -o /tmp/c$i.strace -e trace=openat,renameat,renameat2,unlinkat,mkdirat,linkat \
    ccache gcc -c /s/ccache/aux/src/b.c -o /s/ccache/aux/src/b.o
  grep '/s/ccache/state' /tmp/c$i.strace | sed -E 's/^[0-9]+ +//; s/= [0-9]+$/= N/' > /tmp/s$i.txt
  echo "run $i: $(wc -l < /tmp/s$i.txt) calls on the state directory"
done
echo "-- as they are: first difference"
diff /tmp/s1.txt /tmp/s2.txt | head -6 | cut -c1-200
norm() { sed -E 's/[0-9a-f]{8,}/H/g; s/\.[A-Za-z0-9]{6}"/.R"/g; s/tmp\.[A-Za-z0-9_.]+/tmp.R/g' "$1"; }
norm /tmp/s1.txt > /tmp/n1.txt; norm /tmp/s2.txt > /tmp/n2.txt
echo "-- names normalised: $(diff /tmp/n1.txt /tmp/n2.txt | grep -c '^[<>]') differing lines"
diff /tmp/n1.txt /tmp/n2.txt | head -8 | cut -c1-200
echo "-- the first run's calls naming a temporary"
grep -i -E 'tmp' /tmp/s1.txt | head -6 | cut -c1-200
