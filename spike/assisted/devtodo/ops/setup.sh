#!/bin/sh
# Assisted run (#118), devtodo P1 setup: two notes; AdaNote sorts to index 1
# (measured), GraceNote is the bystander. --database keeps everything inside
# the state root; no environment plumbing.
set -eu
export TERM=vt100
DB=/tmp/assisted/devtodo/state/.todo
mkdir -p /tmp/assisted/devtodo/state
devtodo --database "$DB" --add "GraceNote" --priority medium > /dev/null
devtodo --database "$DB" --add "AdaNote"   --priority medium > /dev/null

umask 077
chmod 600 "$DB"
