#!/bin/sh
# Lab 3: what the first explores' crashed states hold, read off a replay of each saved case, and
# two gate refusals asked of strace.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro \
#       -v <transcripts/explore>:/ex:ro sideeye-sv1012 sh /ap/lab-3.sh
set -u
. /ap/env.sh
SE=$(cat /install.path); W=/s/lab3; mkdir -p $W
hr() { echo; echo "======== $*"; }
replay() { # <target> <label> [flags]
  t=$1; l=$2; shift 2
  ( [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh; sh /ap/defines/$t/seed.sh > $W/$t.seed.log 2>&1 )
  c=$(ls /ex/$t/work-$l/cases/*.json | head -1)
  ( [ -f /ap/defines/$t/env.sh ] && . /ap/defines/$t/env.sh
    "$SE" replay "$c" --oracle /usr/bin/strace "$@" --work $W/$t-work > $W/$t.replay.txt 2>&1 )
  echo "replay $t: exit $? ($(head -1 $W/$t.replay.txt))"
}

hr swiftlint: the crashed Ledger.swift beside the original and the finished one
mkdir -p $W/sw-orig && sh /ap/defines/swiftlint/seed.sh && cp /s/sw/Sources/Ledger.swift $W/sw-orig/before.swift
( cd /s/sw && swiftlint --fix --no-cache Sources/Ledger.swift > /dev/null 2>&1 ); cp /s/sw/Sources/Ledger.swift $W/sw-orig/after.swift
replay swiftlint explore
wc -c $W/sw-orig/before.swift /s/sw/Sources/Ledger.swift $W/sw-orig/after.swift
echo "-- diff before -> crashed"; diff $W/sw-orig/before.swift /s/sw/Sources/Ledger.swift
echo "-- diff crashed -> after"; diff /s/sw/Sources/Ledger.swift $W/sw-orig/after.swift

hr ansible-vault: the crashed secrets.yml
replay ansible-vault explore
ls -la /s/av; od -A d -t x1 /s/av/secrets.yml 2>/dev/null | head -3
grep -c 'db_password' /s/av/secrets.yml 2>/dev/null; head -c 16 /s/av/secrets.yml 2>/dev/null | od -c | head -2

hr crystal: the crashed source
replay crystal supervised --observe supervised
ls -la /s/cr/src; wc -c /s/cr/src/inventory.cr

hr rclone: the crashed directory, and what rclone itself says next
replay rclone supervised --observe supervised
ls -la /s/rclone
( . /ap/defines/rclone/env.sh; rclone listremotes 2>&1 | head -5; echo "listremotes exit $?"; rclone config show s3prod 2>&1 | head -4 )

hr keepassxc: where its random bytes come from, with pin-random.so loaded
( . /ap/defines/keepassxc/env.sh; sh /ap/defines/keepassxc/seed.sh > /dev/null 2>&1
  cd /s/kp && strace -f -qq -e trace=getrandom,openat -o $W/kp.strace keepassxc-cli add --no-password -k /s/kpaux/key.keyx vault.kdbx github -u me < /dev/null > /dev/null 2>&1
  echo "getrandom syscalls: $(grep -c 'getrandom(' $W/kp.strace)"; grep -m3 'getrandom(' $W/kp.strace; grep -c 'urandom' $W/kp.strace )
rm -f /etc/ld.so.preload

hr duckdb: the unlinkat the gate refused
sh /ap/defines/duckdb/seed.sh > /dev/null 2>&1
( cd /s/duck && strace -f -qq -e trace=unlinkat,unlink,rename,renameat2,openat -o $W/dk.strace duckdb shop.duckdb -c "UPDATE orders SET status = 'shipped' WHERE id < 10" < /dev/null > /dev/null 2>&1 )
grep -E 'unlink' $W/dk.strace | head -5; grep -E 'openat\(.*/s/duck' $W/dk.strace | head -6
