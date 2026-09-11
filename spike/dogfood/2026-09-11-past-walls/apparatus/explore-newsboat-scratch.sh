#!/bin/sh
# newsboat judged by SQLite's own recovery rather than by the cache's bytes: the same
# define as explore.sh's `newsboat3`, with the database and its journal declared scratch
# (ADR 0043), so the built-in byte comparison leaves them alone and the checker —
# integrity_check, the earlier item still present, the next reload succeeding — decides.
# The first attempt passed absolute scratch paths and was refused SETUP ERROR ("a scratch
# path is relative to the state directory"); this is the second.
ONLY=" none " sh /hostap/explore.sh > /dev/null 2>&1
AP=/localrun/ap
for m in wrappers syscalls; do
  export SD=/localrun/st/scr-$m/newsboat3; mkdir -p $SD /localrun/wk/scr-$m
  echo "==================== newsboat3 + scratch cache.db / $m ===================="
  /se/sideeye explore --state $SD --setup $AP/setup-newsboat3.sh \
    --operation "newsboat -u $SD/urls -c $SD/cache.db -C $SD/config -x reload" \
    --check $AP/check-newsboat.sh --scratch cache.db --scratch cache.db-journal \
    --shim /se/libsideeye_shim.so --oracle /usr/bin/strace --observe $m --work /localrun/wk/scr-$m \
    --json /out/explore/newsboat3-scratch.$m.json > /out/explore/newsboat3-scratch.$m.txt 2>&1
  echo "raw rc=$?"
  grep -E "^(PASS|FAIL|UNKNOWN|SETUP ERROR)|^ *(explored|oracle|checker|scratch|earliest|observed|path|after|before)" /out/explore/newsboat3-scratch.$m.txt | head -10 | cut -c1-260
done
