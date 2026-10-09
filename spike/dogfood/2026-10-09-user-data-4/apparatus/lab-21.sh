#!/bin/sh
# Lab 21: the two report drafts' reproduce steps, run as written, with no Sideeye: strace's -P (only
# calls touching that path) and inject (deliver SIGKILL on entering the named call).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1009 sh /ap/lab-21.sh
set -u
. /ap/env.sh
echo "## seconv (report-seconv.md)"
. /ap/defines/seconv/env.sh
rm -rf /s/r1 && mkdir -p /s/r1 && cd /s/r1
printf '1\n00:00:05,000 --> 00:00:07,000\nHello\n\n' > subs.srt
ls -l subs.srt
strace -f -qq -P "$PWD/subs.srt" -e inject=pwrite64:signal=KILL \
  seconv subs.srt subrip --offset:-2000 --overwrite > /tmp/r1.out 2>&1
echo "exit $?"
ls -l subs.srt
echo "## mcaselector (report-mcaselector.md)"
rm -rf /s/r2 && mkdir -p /s/r2/world/region /s/r2/world/poi /s/r2/world/entities && cd /s/r2
python3 /ap/defines/mcaselector/make_region.py world/region 6
rm -f /tmp/r.0.0.mca*.tmp
ls -l world/region
strace -f -qq -P "$PWD/world/region/r.0.0.mca" -e inject=renameat:signal=KILL \
  /opt/mcaselector/bin/mcaselector --mode delete --world "$PWD/world" --query "InhabitedTime < 1000" > /tmp/r2.out 2>&1
echo "exit $?"
ls -l world/region
ls -l /tmp/r.0.0.mca*.tmp
