#!/bin/sh
# One target, n recording runs under `explore --observe supervised`, no oracle (strace lines threads
# up: ADR 0138 decision 2, question 1). Run inside sideeye-gh1029 as root, --privileged.
#   measure.sh <probe|plain> <target> <n>
# probe: sideeye-testhandoffprobe, writing each hand-over and each crash point's thread-order
#        verdict to runNN.probe. plain: the shipped engine, for the observer effect.
# Both keep the recording's trace and print its records (trace-ops --records) for the same count.
set -u
arm=$1 t=$2 n=$3
case $arm in probe) se=/se/bin/sideeye-testhandoffprobe ;; plain) se=/se/bin/sideeye ;; *) echo "arm?" >&2; exit 2 ;; esac
o=/out/$arm/$t; mkdir -p "$o"
case $t in
  ctl-*) toml=$o/sideeye.toml; mkdir -p /s
         printf '[world]\nstate = "/s/ctl"\n\n[define]\noperation = "/opt/bin/%s /s/ctl"\ncwd = "/s"\n' "$t" > "$toml"
         seed() { rm -rf /s/ctl && mkdir -p /s/ctl; } ;;
  *)     d=/ap/defines/$t; toml=$d/sideeye.toml
         seed() { (. /ap/env.sh; [ -f "$d/env.sh" ] && . "$d/env.sh"; sh "$d/seed.sh") > "$o/seed.log" 2>&1; } ;;
esac
i=1
while [ "$i" -le "$n" ]; do
  f=$(printf '%s/run%02d' "$o" "$i")
  rm -rf "$f.work"
  seed || { echo "$arm $t run$i: seed failed" >&2; tail -3 "$o/seed.log" >&2; exit 1; }
  ( . /ap/env.sh 2>/dev/null; [ -n "${d:-}" ] && [ -f "$d/env.sh" ] && . "$d/env.sh"
    export GOMAXPROCS=1 SIDEEYE_HANDOFF_PROBE="$f.probe"
    "$se" explore --config "$toml" --observe supervised --no-oracle --allow-unverified \
      --work "$f.work" --json "$f.json" ) > "$f.out" 2>&1
  echo "$arm $t run$i: exit $? $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("verdict"), d.get("unknown_reason") or "-")' "$f.json" 2>/dev/null)" | tee -a "$o/exits.txt"
  /se/bin/trace-ops --records "$f.work/trace-record.bin" > "$f.records" 2>/dev/null
  i=$((i + 1))
done
