#!/bin/sh
# What a FAIL's crash state is to the tool itself: replay the saved case (which leaves the crash
# state in --state), then run the tool's own reader on it. No checker: this is a reading, recorded.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro \
#       -v <transcripts/explore>:/out sideeye-ud1005 sh /ap/probes/after-crash.sh <target> <label> <reader...>
set -u
t=$1; label=$2; shift 2
. /ap/env.sh; [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
SE=$(cat /install.path)
sh /ap/defines/$t/seed.sh > /tmp/seed.log 2>&1
case $label in syscalls) obs="--observe syscalls" ;; supervised) obs="--observe supervised" ;; *) obs="" ;; esac
"$SE" replay /out/$t/work-$label/cases/000001.json --oracle /usr/bin/strace $obs --work /tmp/w --json /tmp/r.json > /tmp/replay.txt 2>&1
echo "replay exit $?: $(head -1 /tmp/replay.txt)"
state=$(sed -n 's/^state *= *"\(.*\)"/\1/p' /ap/defines/$t/sideeye.toml)
echo "state after the replay:"; find "$state" -type f -exec ls -l {} \; | awk '{print "  " $5, $9}'
echo "\$ $*"; "$@" 2>&1 | head -20; echo "reader exit $?"
