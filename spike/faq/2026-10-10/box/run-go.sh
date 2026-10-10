#!/bin/sh
set -u
res() { echo "RESULT $1 rc=$2"; }
tag=$1
cp -r /box/go /tmp/go; cd /tmp/go; export GOFLAGS=-mod=mod GOTOOLCHAIN=local
go test -count=1 . > /out/go-$tag-clean.txt 2>&1; res go-$tag-clean $?
[ "$tag" = default ] && exit 0
printf 'package main\n\nconst buggy = true\n' > clean.go
go test -count=1 . > /out/go-$tag-bug.txt 2>&1; res go-$tag-bug $?
printf 'package main\n\nconst buggy = false\n' > clean.go
sed 's|"--observe", "supervised", "--oracle", "/usr/bin/strace",|"--observe", "supervised", "--allow-unverified",|' keytool_test.go > /tmp/k && cp /tmp/k keytool_test.go
go test -count=1 . > /out/go-$tag-nooracle.txt 2>&1; res go-$tag-nooracle $?
cp /box/go/keytool_test.go .
PATH=/usr/lib/go/bin:/usr/bin:/bin; rm -f /usr/local/bin/sideeye
go test -count=1 . > /out/go-$tag-nosideeye.txt 2>&1; res go-$tag-nosideeye $?
