#!/bin/sh
# Every define through entry.sh, in one box, each under the environment run.sh will give its
# explore (/ap/env.sh, then the define's own env.sh). entry.sh itself is the 2026-10-02 copy and
# does not source either; z.lua, whose store is named by an environment variable, needs it
# (docs/scouting.md: "the operation child inherits the engine's environment").
#
#   docker run --rm --privileged --cgroupns=private --network none \
#       -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1007 sh /ap/gate-all.sh [name ...]
set -u
[ $# -gt 0 ] || set -- $(ls /ap/defines)
for t in "$@"; do
    ( . /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
      OUT=/out/entry sh /ap/entry.sh /ap/defines/$t; echo "EXIT $t $?" )
done
