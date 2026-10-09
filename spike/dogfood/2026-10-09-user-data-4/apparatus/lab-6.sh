#!/bin/sh
# Lab 6: prefsCleaner off the page's path — the gate refused it child_process_detected ("an image
# replacement whose chain of observation broke": setpriv drops to uid 1000 and the shim's record
# of the exec is lost), and the next step (unwrap the script) does not apply: setpriv is what lets
# the script run at all. preflight --twice under --observe syscalls and under --observe supervised,
# named by hand, as 2026-10-05 probed aliyun-cli. Inside the box (privileged, own cgroup namespace):
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-6.sh
set -u
. /ap/env.sh
O=/out/lab-6; mkdir -p "$O"
SE=$(cat /install.path)
for m in syscalls supervised; do
    sh /ap/defines/prefscleaner/seed.sh
    "$SE" preflight --config /ap/defines/prefscleaner/sideeye.toml --twice --oracle /usr/bin/strace --observe $m > "$O/prefscleaner-preflight-$m.txt" 2>&1
    echo "== preflight --observe $m: exit $?"
    grep -E '^(UNKNOWN|SETUP|next|recording accepted|processes)' "$O/prefscleaner-preflight-$m.txt" | cut -c1-260 | head -5
done
