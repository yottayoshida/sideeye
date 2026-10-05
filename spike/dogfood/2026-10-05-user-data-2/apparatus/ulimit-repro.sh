#!/bin/sh
# Each FAIL put forward for a report, reproduced with no crash: the operation run plainly from its seed
# with `ulimit -f 0`, which makes its first write past offset 0 fail (EFBIG) the way a full disk would,
# then the state root listed. 2026-10-03's transcripts/ulimit-repro.txt is the shape. SIGXFSZ is ignored
# (`trap '' XFSZ`, inherited across exec) so the write returns EFBIG instead of killing the process: a C or
# C++ target dies on the signal by default, which is a kill, not a failed write (solvespace's first run
# here); Python ignores it already. The tool's output goes through a pipe: under `ulimit -f 0` a log
# FILE cannot be written either, and the first version of this script recorded every output as empty.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1005 sh /ap/ulimit-repro.sh <target> ...
set -u
. /ap/env.sh
for t in "$@"; do
  ( d=/ap/defines/$t; [ -f $d/env.sh ] && . $d/env.sh
    state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' $d/sideeye.toml); cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' $d/sideeye.toml)
    op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' $d/sideeye.toml)
    sh $d/seed.sh > /tmp/seed.log 2>&1
    echo "== $t"; echo "before:"; find "$state" -type f -exec ls -l {} \; | awk '{print "  " $5, $9}'
    cd "$cwd" && { ( ulimit -f 0; trap '' XFSZ; $op < /dev/null 2>&1; echo "EXIT $?" ) | cat > /tmp/op.log; }; echo "exit $(sed -n 's/^EXIT //p' /tmp/op.log)"; echo "output:"; grep -v -E 'Missing \(absent\) translation|^ *$' /tmp/op.log | tail -6 | sed 's/^/  | /' 
    echo "after:"; find "$state" -type f -exec ls -l {} \; | awk '{print "  " $5, $9}' )
done
