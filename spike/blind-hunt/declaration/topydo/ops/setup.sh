#!/bin/sh
# Seal B artifact (ADR 0012): the declared setup for each topydo operation.
# Builds the pre-operation state with topydo itself (setup runs before the
# recording; any tool is allowed there — ADR 0012 between-the-seals rules).
# Every invocation shape below was observed working in a normal (non-crash)
# run: transcripts/normal-runs.txt and transcripts/config-verification.txt.
#
# All operations except revert run with backups disabled by the declared
# config (nobackup.conf) so the un-killed baseline world is byte-reproducible
# — see declaration.md, "The backup decision". revert keeps backups: they are
# the operation's own input.
#
# Usage: setup.sh <op>
set -eu

op=${1:?usage: setup.sh <op>}
BIN=/usr/local/bin/topydo
CONF=/work/spike/blind-hunt/declaration/topydo/ops/nobackup.conf
S=/tmp/blind/hunt/$op/state
T=$S/todo.txt
D=$S/done.txt

t() { "$BIN" -c "$CONF" -t "$T" -d "$D" "$@"; }
tb() { "$BIN" -t "$T" -d "$D" "$@"; }   # backups on (revert only)

case $op in
    add)      t add seed-task ;;
    append)   t add water-plants ;;
    del)      t add water-plants
              t add keep-me ;;
    dep-add)  t add parent-task
              t add child-task ;;
    dep-rm)   t add parent-task
              t add child-task
              t dep add 1 to 2 ;;
    depri)    t add water-plants
              t pri 1 A ;;
    do)       t add water-plants ;;
    ls)       t add water-plants ;;
    postpone) t add water-plants
              t tag 1 due 2026-09-01 ;;
    pri)      t add water-plants ;;
    revert)   tb add water-plants
              tb do 1 ;;
    sort)     t add zebra-task
              t add alpha-task ;;
    tag)      t add water-plants ;;
    *) echo "setup: unknown operation '$op'" >&2; exit 1 ;;
esac
