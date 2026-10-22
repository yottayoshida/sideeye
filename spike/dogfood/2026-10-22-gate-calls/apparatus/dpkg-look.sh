#!/bin/sh
set -u
D=/ap/defines/dpkg-upgrade
. $D/env.sh
sh $D/seed.sh > /dev/null 2>&1
rm -rf /out/w; /t/branch-out/bin/sideeye preflight --config $D/sideeye.toml \
  --oracle /usr/bin/strace --shim /t/branch-out/lib/libsideeye_shim.so --work /out/w > /dev/null 2>&1
grep -nE '/s/dk/admin/(updates|triggers)' /out/w/oracle.txt | grep -vE 'stat|access|getdents|readlink|lseek|read\(' | head -14
