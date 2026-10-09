#!/bin/sh
# Lab 2: scw again, with the config file seeded by hand (lab 1: `scw config set` refuses when
# ~/.config/scw/config.yaml does not exist; `scw init` is interactive and reaches the network).
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-2.sh
set -u
. /ap/env.sh
O=/out/lab-2; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,mkdir,mkdirat,write,pwrite64,close'
tr_() { n=$1; shift
    strace -f -qq -s 0 -e trace=$T -o "$O/$n.strace" "$@" > "$O/$n.out" 2>&1; rc=$?
    echo "== $n: exit $rc; $(grep -c . "$O/$n.strace") strace lines"
    grep -E 'O_TRUNC|O_CREAT|rename|unlink|link\(|truncate|fsync' "$O/$n.strace" | grep -v -E '/proc/|/sys/|/dev/|/etc/|/usr/|/opt/|/lib|\.so|locale' | head -20
}
echo "## scw"
rm -rf "$HOME/.config/scw"; mkdir -p "$HOME/.config/scw" /s/scw && cd /s/scw
printf 'default_region: nl-ams\ndefault_zone: nl-ams-1\nsend_telemetry: false\nprofiles:\n  prod:\n    default_region: fr-par\n' > "$HOME/.config/scw/config.yaml"
ls -l "$HOME/.config/scw/"
tr_ scw scw config set default_region=fr-par send_telemetry=false
cat "$HOME/.config/scw/config.yaml"; ls -la "$HOME/.config/scw/"
