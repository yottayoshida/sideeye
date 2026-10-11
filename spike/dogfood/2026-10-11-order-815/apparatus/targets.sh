#!/bin/sh
# Usage: targets.sh <label> <engine dir> stylelint|doctl|virtualenv <runs> [extra explore flags]
set -u
L=$1; E=$2; T=$3; N=$4; shift 4
. /fu3/env.sh
case "$T" in
  stylelint) D=/fu3/defines/stylelint; export UV_THREADPOOL_SIZE=1 ;;
  doctl) D=/fu3/defines/doctl; export GOMAXPROCS=1 ;;
  virtualenv) D=/venv/defines/virtualenv ;;
esac
mkdir -p /out/$T
for i in $(seq 1 "$N"); do
  sh "$D/seed.sh" > /out/$T/seed-$L-$i.log 2>&1 || { echo "$L $T $i seed failed"; continue; }
  "$E/bin/sideeye" explore --config "$D/sideeye.toml" --oracle /usr/bin/strace --shim "$E/lib/libsideeye_shim.so" "$@" \
      --work /tmp/w-$T-$L-$i --json /out/$T/$L-$i.json > /out/$T/$L-$i.txt 2>&1
  rc=$?
  v=$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); e=r.get("earliest") or {}; print(r.get("verdict"), r.get("unknown_reason") or "", "explored", r.get("explored"), "earliest", e.get("crash_point"))' /out/$T/$L-$i.json 2>/dev/null)
  echo "$L $T run $i rc=$rc $v :: $(grep -o 'operation [0-9]* was [^,]*recording' /out/$T/$L-$i.txt | head -1)"
done
