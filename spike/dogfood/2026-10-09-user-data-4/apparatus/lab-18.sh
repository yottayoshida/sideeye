#!/bin/sh
# Lab 18: the eighth layer and CKAN (its Mono dependency added) by hand under strace.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-18.sh
set -u
. /ap/env.sh
O=/out/lab-18; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T,clone,clone3 -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines; $(grep -c -E 'clone3?\(' "$O/$n.strace") clone"
    grep -E 'O_TRUNC|O_CREAT|O_APPEND|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -${MAXL:-10}
    tail -2 "$O/$n.out" | cut -c1-200
}
mkdir -p /s/l18 && cd /s/l18
echo "## fly"
printf 'targets:\n  ci:\n    api: https://ci.example.org\n    team: main\n    token:\n      type: Bearer\n      value: not-a-real-token\n  prod:\n    api: https://prod.example.org\n    team: ops\n' > /s/aux/home/.flyrc
tr_ fly fly -t ci edit-target --team-name t2
cat /s/aux/home/.flyrc
echo "## kafkactl"
rm -rf /s/aux/home/.config/kafkactl; mkdir -p /s/aux/home/.config/kafkactl
printf 'contexts:\n  a:\n    brokers:\n      - localhost:9092\n  b:\n    brokers:\n      - localhost:9093\ncurrent-context: a\n' > /s/aux/home/.config/kafkactl/config.yml
tr_ kafkactl kafkactl config use-context b
find /s/aux/home/.config/kafkactl -type f -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \;
echo "## rpk"
rm -rf /s/aux/home/.config/rpk
rpk profile create a > "$O/rpk-seed.out" 2>&1; rpk profile create b >> "$O/rpk-seed.out" 2>&1; echo "seed: $(tail -1 "$O/rpk-seed.out")"
tr_ rpk rpk profile use a
find /s/aux/home/.config/rpk -type f | head; cat /s/aux/home/.config/rpk/rpk.yaml 2>/dev/null | head -12
echo "## atac"
rm -rf /s/atac && mkdir -p /s/atac
atac --help > "$O/atac-help.txt" 2>&1; head -20 "$O/atac-help.txt"
tr_ atac-new1 atac --directory /s/atac collection new demo
tr_ atac-new2 atac --directory /s/atac request new demo/ping -u http://localhost/
ls -la /s/atac; head -c 400 /s/atac/demo.json 2>/dev/null; echo
tr_ atac-new3 atac --directory /s/atac request new demo/pong -u http://localhost/2
echo "## ckan"
rm -rf /s/ksp /s/aux/home/.local/share/CKAN /s/aux/home/.config/CKAN && mkdir -p /s/ksp
ckan instance fake box /s/ksp/game 1.12.5 --set-default --headless > "$O/ckan-seed.out" 2>&1; echo "seed exit $?"; grep -v '^  at ' "$O/ckan-seed.out" | tail -3
find /s/ksp/game/CKAN -maxdepth 1 -type f 2>/dev/null | head
tr_ ckan ckan compat add 1.11 --headless
cat /s/ksp/game/CKAN/compatible_game_versions.json 2>/dev/null | head -12
