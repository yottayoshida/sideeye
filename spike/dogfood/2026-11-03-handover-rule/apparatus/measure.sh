#!/bin/sh
# One subject, n explorations under --observe supervised with GOMAXPROCS=1, in one oracle mode.
# Run inside sideeye-gh1029 as root, --privileged.
#   measure.sh <no-oracle|oracle> <subject> <n>
# A subject is a control (ctl-*, built from controls/ into /c) or a 2026-10-25 define at /ap/defines.
set -u
mode=$1 t=$2 n=$3
case $mode in
  no-oracle) flags="--no-oracle --allow-unverified" ;;
  oracle)    flags="--oracle /usr/bin/strace" ;;
  *) echo "mode?" >&2; exit 2 ;;
esac
o=/out/$mode/$t; mkdir -p "$o"
case $t in
  ctl-*) toml=$o/sideeye.toml; mkdir -p /s
         printf '[world]\nstate = "/s/ctl"\n\n[define]\noperation = "/c/%s /s/ctl"\ncwd = "/s"\n' "$t" > "$toml"
         seed() { rm -rf /s/ctl && mkdir -p /s/ctl; } ;;
  *)     d=/ap/defines/$t; toml=$d/sideeye.toml
         seed() { (. /ap/env.sh; [ -f "$d/env.sh" ] && . "$d/env.sh"; sh "$d/seed.sh") > "$o/seed.log" 2>&1; } ;;
esac
i=1
while [ "$i" -le "$n" ]; do
  f=$(printf '%s/run%02d' "$o" "$i")
  rm -rf "$f.work"
  seed || { echo "$mode $t run$i: seed failed" >&2; tail -3 "$o/seed.log" >&2; exit 1; }
  ( . /ap/env.sh 2>/dev/null; [ -n "${d:-}" ] && [ -f "$d/env.sh" ] && . "$d/env.sh"
    export GOMAXPROCS=1
    /se/bin/sideeye explore --config "$toml" --observe supervised $flags --work "$f.work" --json "$f.json" ) > "$f.out" 2>&1
  echo "$mode $t run$i: exit $?" >> "$o/exits.txt"
  i=$((i + 1))
done
