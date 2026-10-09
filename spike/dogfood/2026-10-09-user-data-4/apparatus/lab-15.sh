#!/bin/sh
# Lab 15: ifcpatch on a model written by defines/ifcpatch/make_model.py (lab 14's seed used an API
# 0.9 removed), with its recipe list, to find one whose output does not differ run to run.
#   docker run --rm --network none -v <apparatus>:/ap:ro -v <out>:/out sideeye-ud1009 sh /ap/lab-15.sh
set -u
. /ap/env.sh
O=/out/lab-15; mkdir -p "$O"
T='openat,creat,rename,renameat,renameat2,unlink,unlinkat,ftruncate,truncate,link,linkat,fsync,fdatasync,write,close'
ls /opt/py/lib/python3.13/site-packages/ifcpatch/recipes/ | sed 's/\.py$//' | tr '\n' ' '; echo
for r in Optimise RemoveDuplicateObjects ResetAbsoluteCoordinates; do
  for k in 1 2; do
    rm -rf /s/ifc && mkdir -p /s/ifc /s/ifc-in && cd /s/ifc-in
    /opt/py/bin/python3 /ap/defines/ifcpatch/make_model.py /s/ifc/model.ifc > "$O/seed.out" 2>&1 || { echo "seed failed"; tail -3 "$O/seed.out"; }
    strace -f -qq -s 0 -e trace=$T,clone,clone3 -o "$O/$r-$k.strace" /opt/py/bin/python3 -m ifcpatch -i /s/ifc/model.ifc -r $r > "$O/$r-$k.out" 2>&1; rc=$?
    echo "== $r run $k: exit $rc; $(sha256sum /s/ifc/model.ifc | cut -c1-12); $(wc -c < /s/ifc/model.ifc) bytes; $(grep -c -E 'clone3?\(' "$O/$r-$k.strace") clone; $(tail -1 "$O/$r-$k.out" | cut -c1-120)"
  done
  grep -E '/s/ifc/' "$O/$r-1.strace" | grep -E 'O_TRUNC|O_CREAT|rename|unlink|truncate|fsync' | head -6
done
ls -la /s/ifc /s/ifc-in
