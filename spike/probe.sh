#!/bin/sh
# Spike probe: does the shim see the operations, and does the kill land where asked?
#
# This is the manual counterpart of the acceptance checks. It answers, by running
# things rather than by reasoning about them:
#   1. what the recording run observes, and whether two runs observe the same thing
#   2. whether SIDEEYE_KILL_AT=k dies immediately before the k-th operation, with the
#      state directory left in the shape that implies
#   3. whether each out-of-bounds target is visibly out of bounds
set -u

ROOT=${SIDEEYE_ROOT:-/work}
SHIM=$ROOT/zig-out/lib/libsideeye_shim.so
OUT=$ROOT/spike/out
W=/tmp/probe

hexdump_trace() {
    od -A n -t x1 -v "$1" 2>/dev/null | tr -d ' \n'
}

# 901 = kill_landed, little-endian
has_kill_landed() {
    hexdump_trace "$1" | grep -q '8503'
}

# 900 = shim_ready, little-endian, and a trace always starts with it when present
has_shim_ready() {
    hexdump_trace "$1" | grep -q '8403'
}

state_listing() {
    if [ -d "$W/state" ]; then
        ls "$W/state" | sort | tr '\n' ' '
    else
        echo -n '(no state dir)'
    fi
}

reset_world() {
    rm -rf "$W"
    mkdir -p "$W/state"
    TOY_STATE=$W/state
    export TOY_STATE
    SIDEEYE_STATE_DIR=$W/state
    export SIDEEYE_STATE_DIR
    SIDEEYE_TRACE_PATH=$W/trace.bin
    export SIDEEYE_TRACE_PATH
    "$1" init >/dev/null 2>&1
    rm -f "$W/trace.bin"
}

echo "=========== 1. recording run (no kill) ==========="
reset_world "$OUT/toy-bug"
LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate
echo "exit=$?  state: $(state_listing)"
echo "trace bytes: $(wc -c < "$W/trace.bin")"
cp "$W/trace.bin" /tmp/trace-a.bin

echo ""
echo "=========== 2. determinism: same run twice ==========="
reset_world "$OUT/toy-bug"
LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate
cp "$W/trace.bin" /tmp/trace-b.bin
if cmp -s /tmp/trace-a.bin /tmp/trace-b.bin; then
    echo "IDENTICAL: two recording runs produced byte-identical traces"
else
    echo "DIFFERENT: traces diverged"
    cmp /tmp/trace-a.bin /tmp/trace-b.bin
fi

echo ""
echo "=========== 3. kill at each k (toy-bug, N=5) ==========="
for k in 1 2 3 4 5 6; do
    reset_world "$OUT/toy-bug"
    SIDEEYE_KILL_AT=$k LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate >/dev/null 2>&1
    rc=$?
    landed=absent
    has_kill_landed "$W/trace.bin" && landed=PRESENT
    key=missing
    [ -f "$W/state/key.json" ] && key=present
    printf 'k=%s exit=%-4s kill_landed=%-8s key.json=%-8s state: %s\n' \
        "$k" "$rc" "$landed" "$key" "$(state_listing)"
done

echo ""
echo "=========== 4. kill reproducibility (k=5, ten times) ==========="
same=0
for i in $(seq 1 10); do
    reset_world "$OUT/toy-bug"
    SIDEEYE_KILL_AT=5 LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate >/dev/null 2>&1
    if [ ! -f "$W/state/key.json" ] && [ -f "$W/state/key.json.tmp" ]; then
        same=$((same + 1))
    fi
done
echo "$same/10 runs landed in the same state (no key.json, tmp present)"

echo ""
echo "=========== 5. the fixed toy, same treatment ==========="
reset_world "$OUT/toy-fixed"
LD_PRELOAD=$SHIM "$OUT/toy-fixed" rotate >/dev/null 2>&1
echo "recording run: $(wc -c < "$W/trace.bin") trace bytes, state: $(state_listing)"
for k in 1 2 3 4 5; do
    reset_world "$OUT/toy-fixed"
    SIDEEYE_KILL_AT=$k LD_PRELOAD=$SHIM "$OUT/toy-fixed" rotate >/dev/null 2>&1
    key=missing
    [ -f "$W/state/key.json" ] && key=present
    printf 'k=%s key.json=%-8s state: %s\n' "$k" "$key" "$(state_listing)"
done

echo ""
echo "=========== 6. out-of-bounds targets ==========="

reset_world "$OUT/toy-raw"
LD_PRELOAD=$SHIM "$OUT/toy-raw" rotate >/dev/null 2>&1
ready=no; has_shim_ready "$W/trace.bin" && ready=yes
echo "toy-raw    : shim_ready=$ready  trace bytes=$(wc -c < "$W/trace.bin" 2>/dev/null || echo 0)  state: $(state_listing)"
echo "             ^ the state changed but no operation was recorded"

reset_world "$OUT/toy-static"
LD_PRELOAD=$SHIM "$OUT/toy-static" rotate >/dev/null 2>&1
if [ -f "$W/trace.bin" ]; then
    ready=no; has_shim_ready "$W/trace.bin" && ready=yes
    echo "toy-static : trace exists, shim_ready=$ready  state: $(state_listing)"
else
    echo "toy-static : no trace file at all (the shim never loaded)  state: $(state_listing)"
fi

reset_world "$OUT/toy-bug"
TOY_FORK=1 LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate >/dev/null 2>&1
# 200 = fork
forked=no
hexdump_trace "$W/trace.bin" | grep -q 'c800' && forked=yes
echo "toy-bug+fork  : fork record present=$forked"

reset_world "$OUT/toy-bug"
TOY_THREAD=1 LD_PRELOAD=$SHIM "$OUT/toy-bug" rotate >/dev/null 2>&1
# 202 = thread
threaded=no
hexdump_trace "$W/trace.bin" | grep -q 'ca00' && threaded=yes
echo "toy-bug+thread: thread record present=$threaded"

echo ""
echo "=========== 7. the real-language stand-in ==========="
reset_world "$OUT/toy-rust"
LD_PRELOAD=$SHIM "$OUT/toy-rust" rotate >/dev/null 2>&1
echo "toy-rust: $(wc -c < "$W/trace.bin" 2>/dev/null || echo 0) trace bytes, state: $(state_listing)"
echo "--- what the shim saw (op classes, in order) ---"
od -A n -t u1 -v "$W/trace.bin" 2>/dev/null | head -40
