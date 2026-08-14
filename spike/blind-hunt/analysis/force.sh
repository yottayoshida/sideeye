#!/bin/sh
# Does the documented forced form recover what plain `revert` refuses?
# docs: "To force a `revert` action use it with a NUMBER."
export HOME=/tmp/blind/home; mkdir -p "$HOME"
BIN=/usr/local/bin/topydo

try() {
    pt=$1; arg=$2
    S=/tmp/f/$pt-$arg; rm -rf "$S"; mkdir -p "$S"
    T=$S/todo.txt; D=$S/done.txt
    $BIN -t "$T" -d "$D" add seed-task >/dev/null 2>&1
    SIDEEYE_STATE_DIR=$S SIDEEYE_TRACE_PATH=$S/trace.bin \
    LD_PRELOAD=/work/zig-out/lib/libsideeye_shim.so SIDEEYE_KILL_AT=$pt \
    $BIN -t "$T" -d "$D" add water-plants >/dev/null 2>&1
    echo "--- crash point $pt, then: topydo revert $arg ---"
    echo "state after crash: $(wc -c < "$T") bytes, seed visible: $($BIN -t "$T" -d "$D" ls -x 2>/dev/null | grep -c seed-task)"
    out=$($BIN -t "$T" -d "$D" revert $arg 2>&1); rc=$?
    echo "revert $arg -> rc=$rc :: $out"
    echo "todo.txt now: [$(cat "$T" | tr '\n' '/')] ; seed visible: $($BIN -t "$T" -d "$D" ls -x 2>/dev/null | grep -c seed-task)"
    echo ""
}
for a in 1 2; do try 5 $a; done
for a in 1 2; do try 4 $a; done
