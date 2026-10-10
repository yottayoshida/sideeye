#!/bin/sh
# jj 0.46.0's commit of a modified file (2026-09-27's define), under strace -f with thread exits kept:
# does the thread that writes the blob end before the first thread's next write in the repository?
#   docker run --rm -v <this dir and fu6's jj-046-plain define>:/t:ro -v <jj>:/j:ro -v <out>:/out ubuntu:24.04@<digest> sh /t/run.sh
# The trace and the operation's output are written inside the container and copied to /out at the end,
# so the record names no path of the machine it ran on.
mkdir -p /opt/jj-0.46.0 /rec && cp /j/jj /opt/jj-0.46.0/jj
. /t/env.sh
sh /t/seed.sh > /dev/null 2>&1 || { echo seed failed; exit 1; }
cd /s/jj-in
strace -f -tt -y -o /rec/join.strace -e trace=clone,clone3,openat,write,renameat,renameat2,exit,exit_group,futex jj -R /s/jj/repo commit -m probe > /rec/op.log 2>&1
echo "op exit $?" | tee -a /rec/op.log
cp /rec/join.strace /rec/op.log /out/
