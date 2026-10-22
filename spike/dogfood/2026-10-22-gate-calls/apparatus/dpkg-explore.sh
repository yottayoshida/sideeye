#!/bin/sh
set -u
D=/ap/defines/dpkg-upgrade
. $D/env.sh
sh $D/seed.sh > /out/seed-explore.log 2>&1
rm -rf /out/w; /t/branch-out/bin/sideeye explore --config $D/sideeye.toml \
  --oracle /usr/bin/strace --observe supervised --shim /t/branch-out/lib/libsideeye_shim.so --work /out/w > /out/dpkg-explore-supervised.txt 2>&1
echo "== dpkg explore supervised: exit $?"; head -14 /out/dpkg-explore-supervised.txt
