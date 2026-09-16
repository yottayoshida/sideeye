#!/bin/sh
# 2026-09-16 dogfood: cargo re-met with the released v1.4.0 in both observation modes (#538).
# Runs inside the image apparatus/Dockerfile builds, with the release tarball's directory at
# /se (read-only), this directory at /hostap (read-only) and the record's transcripts/ at /out:
#
#   docker run --rm --network none -v <untarred>:/se:ro -v <this dir>:/hostap:ro \
#       -v <record>/transcripts:/out sideeye-dogfood:2026-09-16-cargo sh /hostap/run.sh
#
# Two configurations always, two only when the first two leave something to compare
# (BUILDLOG 2026-09-16 (second) carries the predictions, committed before this ran):
#   A  plain cargo,  --observe wrappers   x3
#   B  plain cargo,  --observe syscalls   x3
#   C  RUSTC stand-in, wrappers  x3 — only if A's three unknown_reasons are not all oracle_missed_operation
#   D  RUSTC stand-in, syscalls  x3 — only if any of B's three runs is UNKNOWN
# Before A and B: `preflight --twice` in that mode. Its exit 1 is recorded and does not stop the run.
# State and work live on the container's own filesystem (#528). Every line printed is the
# report's own; nothing is re-counted.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
AP=/hostap
OUT=/out
R=/localrun
mkdir -p "$OUT" "$R"

{
  "$SE" version
  cargo --version; rustc --version; strace -V | head -1
  cat /etc/os-release | head -2; uname -m
  # v17 judges where the run was contained when the engine can make a cgroup; a default
  # container cannot, and the record must say which it was.
  if [ -w /sys/fs/cgroup ] && [ -f /sys/fs/cgroup/cgroup.controllers ]; then echo "cgroup: writable"; else echo "cgroup: not writable (default container)"; fi
} > "$OUT/environment.txt" 2>&1
cat "$OUT/environment.txt"

summ() {  # summ <json> <label>: the report's verdict and reason, from its own JSON
  python3 - "$1" "$2" <<'PY' 2>/dev/null || echo "$2: no report json"
import json, sys
d = json.load(open(sys.argv[1]))
print(sys.argv[2], d.get("verdict"), d.get("unknown_reason") or "", "explored=" + str(d.get("explored")), "crash_points=" + str(d.get("crash_points")))
PY
}

reason() {  # reason <json>: the unknown_reason field, or the verdict when there is none
  python3 - "$1" <<'PY' 2>/dev/null || echo "no-json"
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("unknown_reason") or d.get("verdict") or "no-verdict")
PY
}

run_one() {  # run_one <label> <mode> <setup> <standin:0|1> <n>
  label=$1; mode=$2; setup=$3; standin=$4; n=$5
  export CARGO_ROOT="$R/$label/$n"
  mkdir -p "$CARGO_ROOT/wk"
  if [ "$standin" = 1 ]; then export RUSTC="$CARGO_ROOT/rustc-standin"; else unset RUSTC; fi
  op="cargo add --offline --manifest-path $CARGO_ROOT/state/Cargo.toml --path $CARGO_ROOT/depcrate"
  echo "==================== $label run $n / $mode / standin=$standin ===================="
  echo "op: $op"
  "$SE" explore --state "$CARGO_ROOT/state" --setup "$AP/$setup" --operation "$op" \
      --check "$AP/check.sh" --shim "$SHIM" --oracle /usr/bin/strace \
      --observe "$mode" --work "$CARGO_ROOT/wk" \
      --json "$OUT/$label.$n.json" > "$OUT/$label.$n.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  grep -E "^(PASS|FAIL|UNKNOWN|SETUP ERROR)" "$OUT/$label.$n.txt" | head -2
  grep -E "^ *(explored|oracle|checker|processes|earliest|violation|crash point|reason)" "$OUT/$label.$n.txt" | head -8 | cut -c1-300
  summ "$OUT/$label.$n.json" "$label.$n"
  echo
}

twice() {  # twice <label> <mode>: preflight --twice on the plain define, recorded, never fatal
  label=$1; mode=$2
  export CARGO_ROOT="$R/twice-$label"
  mkdir -p "$CARGO_ROOT"
  unset RUSTC
  op="cargo add --offline --manifest-path $CARGO_ROOT/state/Cargo.toml --path $CARGO_ROOT/depcrate"
  echo "==================== preflight --twice / $mode ===================="
  "$SE" preflight --state "$CARGO_ROOT/state" --setup "$AP/setup.sh" --operation "$op" \
      --shim "$SHIM" --oracle /usr/bin/strace --observe "$mode" --twice \
      > "$OUT/preflight-twice.$mode.txt" 2>&1
  echo "raw rc=$?   (0=accepted 2=refused; an exit 1 is --twice's own answer and does not stop the run)"
  head -12 "$OUT/preflight-twice.$mode.txt" | cut -c1-300
  echo
}

twice A wrappers
for n in 1 2 3; do run_one A wrappers setup.sh 0 "$n"; done
twice B syscalls
for n in 1 2 3; do run_one B syscalls setup.sh 0 "$n"; done

# C: only if A did not land on r2's wall three times out of three.
runC=0
for n in 1 2 3; do
  r=$(reason "$OUT/A.$n.json")
  [ "$r" = "oracle_missed_operation" ] || runC=1
done
if [ "$runC" = 1 ]; then
  echo "A did not read oracle_missed_operation in all three runs: running C (stand-in, wrappers)"
  for n in 1 2 3; do run_one C wrappers setup-standin.sh 1 "$n"; done
else
  echo "C not run: A read oracle_missed_operation in all three runs, r2's wall, nothing to compare" | tee "$OUT/C.not-run.txt"
fi

# D: only if any of B's runs is UNKNOWN.
runD=0
for n in 1 2 3; do
  v=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verdict"))' "$OUT/B.$n.json" 2>/dev/null || echo "no-json")
  [ "$v" = "PASS" ] || [ "$v" = "FAIL" ] || runD=1
done
if [ "$runD" = 1 ]; then
  echo "B did not reach a verdict in all three runs: running D (stand-in, syscalls)"
  for n in 1 2 3; do run_one D syscalls setup-standin.sh 1 "$n"; done
else
  echo "D not run: B reached a verdict in all three runs, nothing to compare" | tee "$OUT/D.not-run.txt"
fi
echo "==================== done ===================="
