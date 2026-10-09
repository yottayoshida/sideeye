#!/bin/sh
# Lab 1: does UV_THREADPOOL_SIZE=1 take a Node target past the threads wall? libuv runs Node's
# asynchronous file calls on its thread pool (four threads by default); with one, they share one
# thread. For yarn and trash-cli (both refused multiple_threads_detected on 2026-10-09 in every mode):
# the threads that write the state directory, counted by strace, and the gate's answer, each with
# and without the variable.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro sideeye-fu3-1009 sh /ap/lab-1.sh
set -u
SE=$(cat /install.path)
. /ap/env.sh
for t in yarn trash; do
  d=/ap/defines/$t
  for pool in default 1; do
    (
      [ -f "$d/env.sh" ] && . "$d/env.sh"
      [ $pool = 1 ] && export UV_THREADPOOL_SIZE=1
      state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      op=$(sed -n 's/^operation *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      cwd=$(sed -n 's/^cwd *= *"\(.*\)"/\1/p' "$d/sideeye.toml")
      sh "$d/seed.sh" > /tmp/seed.log 2>&1
      (cd "$cwd" && strace -f -qq -o /tmp/$t.$pool.strace -e trace=openat,write,rename,renameat,renameat2,unlinkat,mkdirat $op > /dev/null 2>&1)
      n=$(grep "$state" /tmp/$t.$pool.strace | grep -v -E 'O_RDONLY|ENOENT' | awk '{print $1}' | sort -u | wc -l)
      sh "$d/seed.sh" > /tmp/seed.log 2>&1
      "$SE" preflight --config "$d/sideeye.toml" --work /tmp/w-$t-$pool > /tmp/pf.txt 2>&1
      echo "$t pool=$pool: $n thread(s) wrote $state; gate: $(grep -m1 -E '^(PREFLIGHT|UNKNOWN|SETUP)' /tmp/pf.txt | tr -s ' ' | cut -c1-90)"
      "$SE" preflight --config "$d/sideeye.toml" --observe supervised --work /tmp/w-$t-$pool-s > /tmp/pfs.txt 2>&1
      echo "$t pool=$pool supervised: $(grep -m1 -E '^(PREFLIGHT|UNKNOWN|SETUP)' /tmp/pfs.txt | tr -s ' ' | cut -c1-90)"
    )
  done
done
