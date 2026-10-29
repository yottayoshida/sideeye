#!/bin/sh
# One define, one build, one command: what the 2026-10-25 run's entry gate and explore asked, with the
# engine and shim mounted at /se (a `zig build -Dtarget=aarch64-linux-gnu` prefix) and that run's
# apparatus at /ap.
#
#   docker run --rm --privileged --cgroupns=private --network none \
#     -v <2026-10-25 apparatus>:/ap:ro -v <this apparatus>:/ap29:ro -v <zig-out>:/se:ro \
#     -v <out>:/out sideeye-r1029 sh /ap29/run.sh <define> <label> preflight|explore [extra flags...]
#
# preflight is the gate's own call (`--twice --oracle`); explore is the full run, whose report names the
# verdict. Each starts from the define's seed.sh, as the gate's did.
set -u
name=${1:?define}; label=${2:?label}; cmd=${3:?preflight|explore}; shift 3
def=/ap/defines/$name
out=/out/$name.$label.$cmd.txt
[ -f "$def/env.sh" ] && . "$def/env.sh"
sh "$def/seed.sh" > "/out/$name.$label.$cmd.seed.log" 2>&1 || { echo "seed.sh failed" > "$out"; exit 2; }
{ /se/bin/sideeye version; echo "command: $cmd $*"; echo; } > "$out"
case "$cmd" in
    preflight) /se/bin/sideeye preflight --config "$def/sideeye.toml" --twice --oracle /usr/bin/strace "$@" >> "$out" 2>&1 ;;
    explore) /se/bin/sideeye explore --config "$def/sideeye.toml" --oracle /usr/bin/strace --work /tmp/work "$@" >> "$out" 2>&1 ;;
esac
rc=$?
echo "rc=$rc" >> "$out"
echo "$name $label $cmd rc=$rc $(sed -n 's/^\(UNKNOWN\|PASS\|FAIL\|SETUP ERROR\)  */\1 /p' "$out" | head -1)"
