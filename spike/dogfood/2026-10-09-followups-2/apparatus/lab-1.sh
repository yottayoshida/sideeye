#!/bin/sh
# Lab 1: what monero-wallet-cli and plakar print, so their checkers read the tool's own answer.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-1.sh
set -u
. /ap/env.sh
echo "## monero"
( . /ap/defines/monero/env.sh; sh /ap/defines/monero/seed.sh > /dev/null 2>&1; ls -l /s/xmr
  monero-wallet-cli --offline --wallet-file /s/xmr/w --password pw --log-file /tmp/l get_description 2>&1 | tail -3
  monero-wallet-cli --offline --wallet-file /s/xmr/w --password pw --log-file /s/xmr-in/log set_description rent-and-savings > /dev/null 2>&1; echo "set exit $?"
  monero-wallet-cli --offline --wallet-file /s/xmr/w --password pw --log-file /tmp/l get_description 2>&1 | tail -3
  cp /s/xmr/w /tmp/w.good; head -c 100 /tmp/w.good > /s/xmr/w
  monero-wallet-cli --offline --wallet-file /s/xmr/w --password pw --log-file /tmp/l get_description 2>&1 | tail -2; echo "cut exit $?"
  rm -f /etc/ld.so.preload )
echo "## plakar"
( . /ap/defines/plakar/env.sh; sh /ap/defines/plakar/seed.sh > /dev/null 2>&1; ls /s/plakar/repo | head
  plakar at /s/plakar/repo ls 2>&1 | head -5
  plakar at /s/plakar/repo rm -apply -tag old > /dev/null 2>&1; echo "rm exit $?"
  plakar at /s/plakar/repo ls 2>&1 | head -5
  plakar at /s/plakar/repo check 2>&1 | tail -2; echo "check exit $?" )
