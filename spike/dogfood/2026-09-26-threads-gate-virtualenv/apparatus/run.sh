#!/bin/sh
# The 2026-09-26 threads-gate run: the 2026-09-22 entry gate, unchanged, over two contrasts
# and virtualenv.
#
#   docker build -t sideeye-tg <this directory>
#   docker run --rm --network none --cap-add SYS_PTRACE -v <this directory>:/ap:ro \
#       -v <out>:/out sideeye-tg sh /ap/run.sh
#
# The same flags as the 2026-09-22 run (no seccomp=unconfined, which the 2026-09-16 run had).
# Contrasts first: a gate that cannot answer green on js-beautify and red on joinedthreads in
# this box has not measured virtualenv either.
set -u
mkdir -p /out/entry
{ echo "image: sideeye-tg FROM sideeye-sv"; head -1 /versions.txt; grep -E 'digest' /install.log
  /usr/bin/virtualenv --version; dpkg-query -W python3-virtualenv; /usr/bin/python3 --version
  strace -V | head -1; uname -m; } > /out/environment.txt 2>&1
for t in legs/joinedthreads defines/js-beautify defines/virtualenv; do
    OUT=/out/entry sh /ap/entry.sh "/ap/$t"
    echo "exit $?"
done 2>&1 | tee /out/rows.txt
cp /tmp/gate-out/threads.txt /out/entry/virtualenv.strace.txt 2>/dev/null || true
