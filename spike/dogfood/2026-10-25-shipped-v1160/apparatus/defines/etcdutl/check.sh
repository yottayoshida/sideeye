#!/bin/sh
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
out=$(etcdutl snapshot status "$t/db" -w json 2>&1); rc=$?
rm -rf "$t"
[ $rc -eq 0 ] || { echo "checker(etcdutl): snapshot status fails: $(echo "$out" | tail -1)"; exit 1; }
got=$(echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["hash"], d["revision"], d["totalKey"])' 2>&1)
want=$(cat /s/.etcd-expect)
[ "$got" = "$want" ] || { echo "checker(etcdutl): hash revision keys = $got, want $want"; exit 1; }
