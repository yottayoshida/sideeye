#!/bin/sh
# Assisted run (#118), buku P1 setup: one bystander bookmark, written by buku
# itself. XDG_DATA_HOME points the db inside the state root (measured: the
# pinned 4.7 honors XDG_DATA_HOME and ignores BUKU_DEFAULT_DBDIR).
set -eu
export XDG_DATA_HOME=/tmp/assisted/buku/state
mkdir -p "$XDG_DATA_HOME"
/usr/bin/buku --nostdin --np --tacit --add https://example.com/g grace --title GraceMark > /dev/null
