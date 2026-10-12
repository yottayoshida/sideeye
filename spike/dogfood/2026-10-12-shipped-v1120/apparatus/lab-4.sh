#!/bin/sh
# Lab 4: two crashed states lab 3 could not show (a replay ends where the run completes), rebuilt by
# hand from the evidence tables; and KeePassXC with /dev/urandom pinned.
#   docker run --rm --privileged --cgroupns=private --network none -v <apparatus>:/ap:ro sideeye-sv1012 sh /ap/lab-4.sh
set -u
. /ap/env.sh
hr() { echo; echo "======== $*"; }
hr swiftlint: is the 703-byte crashed file the original with only opening_brace applied
sh /ap/defines/swiftlint/seed.sh; cd /s/sw
swiftlint --fix --no-cache --only-rule opening_brace Sources/Ledger.swift > /dev/null 2>&1; echo "only opening_brace: $(wc -c < Sources/Ledger.swift) bytes"
swiftlint --fix --no-cache Sources/Ledger.swift > /dev/null 2>&1; echo "then the rest: $(wc -c < Sources/Ledger.swift) bytes"
hr rclone: the crashed directory of crash point 6 rebuilt - rclone.conf moved aside, the new one not yet in
( . /ap/defines/rclone/env.sh; sh /ap/defines/rclone/seed.sh; cd /s/rclone
  mv rclone.conf rclone.conf.old2541991190; cp rclone.conf.old2541991190 rclone.conf780660081; ls
  echo "-- rclone listremotes:"; rclone listremotes 2>&1 | head -5; echo "exit $?"
  echo "-- rclone lsd backup: (a command a user would run next)"; rclone lsd backup: 2>&1 | head -3
  echo "-- rclone config update again (the documented way to set it):"; rclone config update s3prod region eu-west-1 --non-interactive > /dev/null 2>&1; echo "exit $?"; ls; head -3 rclone.conf )
hr keepassxc: two clean adds under the pins, compared
( . /ap/defines/keepassxc/env.sh
  for i in 1 2; do sh /ap/defines/keepassxc/seed.sh > /dev/null 2>&1; ( cd /s/kp && keepassxc-cli add -q --no-password -k /s/kpaux/key.keyx vault.kdbx github -u me < /dev/null ); cp /s/kp/vault.kdbx /s/kp-run$i.kdbx; done
  cmp /s/kp-run1.kdbx /s/kp-run2.kdbx && echo "the two runs wrote the same bytes" || echo "the two runs differ" )
rm -f /etc/ld.so.preload
