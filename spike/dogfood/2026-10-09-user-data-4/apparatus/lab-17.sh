#!/bin/sh
# Lab 17: off the page's path. rootrm and iconvert both die of SIGABRT with the shim preloaded
# (entry-candidates-11.txt, lab-3.txt, lab-16.txt) and run to exit 0 by hand. --observe supervised
# counts from outside the process and inserts no library, so it is asked by hand, as 2026-10-07 asked
# it of roswell. Privileged box, its own cgroup namespace:
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-17.sh
set -u
O=/out/lab-17; mkdir -p "$O"
SE=$(cat /install.path)
for t in rootrm iconvert; do
    ( . /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
      sh /ap/defines/$t/seed.sh > "$O/$t-seed.log" 2>&1
      "$SE" preflight --config /ap/defines/$t/sideeye.toml --twice --oracle /usr/bin/strace --observe supervised > "$O/$t-preflight-supervised.txt" 2>&1
      echo "== $t preflight --observe supervised: exit $?"
      grep -E '^(UNKNOWN|SETUP|PREFLIGHT|next|processes)' "$O/$t-preflight-supervised.txt" | cut -c1-220 | head -4 )
done
