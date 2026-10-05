#!/bin/sh
# Plain runs: the go command's `go env -w` onto a GOENV file of its own.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-10}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
G=/opt/go127/go/bin/go
export GOENV=/lab/goenv/env
mkdir -p /lab/goenv
x $G env -w GOPROXY=https://proxy.example.internal,direct GOPRIVATE=git.example.internal/* GONOSUMDB=git.example.internal/*
sum /lab/goenv; cat /lab/goenv/env
x $G env -w GOFLAGS=-mod=mod
sum /lab/goenv; cat /lab/goenv/env
x $G env -u GONOSUMDB
sum /lab/goenv; cat /lab/goenv/env
echo "--- what else the go command wrote under HOME"
find /s/aux/home -newer /lab/goenv -type f 2>/dev/null | head; find / -xdev -newer /etc/hostname -path '*telemetry*' 2>/dev/null | head -5
echo "--- strace: processes and writes"
strace -f -qq -e signal=none -e trace=execve,clone,clone3,openat,rename,renameat,renameat2,ftruncate -o /tmp/st $G env -w GOFLAGS=-mod=readonly </dev/null >/dev/null 2>&1
grep -c clone /tmp/st | sed 's/^/clone lines: /'; grep -E 'execve|/lab/goenv' /tmp/st | grep -v ENOENT | cut -c1-180
