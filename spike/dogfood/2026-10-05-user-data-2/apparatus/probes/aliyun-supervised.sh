#!/bin/sh
# aliyun-cli explored with --observe supervised named, the mode the page's path never reaches for it
# (its default-mode refusal is oracle_missed_operation, whose next step names syscalls).
. /ap/env.sh
SE=$(cat /install.path)
sh /ap/defines/aliyun/seed.sh > /dev/null 2>&1
"$SE" explore --config /ap/defines/aliyun/sideeye.toml --oracle /usr/bin/strace --observe supervised --work /tmp/w --json /out/supervised.json 2>&1 | head -12
