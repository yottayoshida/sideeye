#!/bin/sh
# Campaign-2 Seal B artifact (ADR 0012 via ADR 0015): the declared setup for each
# khard operation. Setup runs before the recording, so khard's random UIDs here
# are harmless — the baseline world replays the operation over the recorded
# pre-state, not over a fresh setup (the campaign-1 revert precedent: its
# second-precision backup bytes came from setup and never broke the baseline).
# Every invocation shape was observed working in a normal run:
# ../transcripts/normal-runs.txt.
#
# Grace is the conserved bystander in every operation (an empty addressbook
# makes `khard list` exit 1 — observed — so the checker keeps one contact that
# no operation touches). Ada is the operation's subject.
#
# Usage: setup.sh <op>
set -eu

op=${1:?usage: setup.sh <op>}
here=/work/spike/blind-hunt2/declaration/khard/ops
C=$here/khard-$op.conf
S=/tmp/blind2/hunt/$op/state
mkdir -p "$S/main" "$S/second"

k() { khard -c "$C" "$@" < /dev/null; }

case $op in
    new)
        k new -a main -i "$here/grace.yaml" ;;
    remove)
        k new -a main -i "$here/ada.yaml"
        k new -a main -i "$here/grace.yaml" ;;
    move)
        k new -a main -i "$here/ada.yaml"
        k new -a main -i "$here/grace.yaml" ;;
    copy)
        k new -a main -i "$here/ada.yaml"
        k new -a main -i "$here/grace.yaml" ;;
    *) echo "setup: unknown operation '$op'" >&2; exit 1 ;;
esac
