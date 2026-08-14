#!/bin/sh
# End-to-end reproduction of the revert counterexample, default configuration
# (backups ON — the declared config file is NOT used for revert).
export HOME=/tmp/blind/home; mkdir -p "$HOME"
BIN=/usr/local/bin/topydo
S=/tmp/repro/revert
T=$S/todo.txt; D=$S/done.txt
rm -rf /tmp/repro; mkdir -p "$S"

echo "===== setup (plain topydo, default config, backups on) ====="
$BIN -t "$T" -d "$D" add water-plants
$BIN -t "$T" -d "$D" do 1
echo "--- todo.txt ---"; cat "$T"; echo "--- done.txt ---"; cat "$D"
echo "--- filenames ---"; ls -A "$S"

echo ""
echo "===== the crash: kill at point 3 (after open(done.txt), before write) ====="
SIDEEYE_STATE_DIR=$S \
SIDEEYE_TRACE_PATH=/tmp/repro/trace.bin \
LD_PRELOAD=/work/zig-out/lib/libsideeye_shim.so \
SIDEEYE_KILL_AT=3 \
$BIN -t "$T" -d "$D" revert
echo "operation rc=$? (137 = SIGKILL)"

echo ""
echo "===== state after the crash ====="
echo "--- todo.txt ---"; cat "$T" 2>&1; echo "[end]"
echo "--- done.txt ---"; cat "$D" 2>&1; echo "[end]"
echo "--- filenames ---"; ls -A "$S"
echo "--- byte sizes ---"; wc -c "$T" "$D" 2>&1

echo ""
echo "===== can the user get the task back? ====="
echo "\$ topydo ls -x"; $BIN -t "$T" -d "$D" ls -x; echo "rc=$?"
echo "\$ topydo revert ls"; $BIN -t "$T" -d "$D" revert ls; echo "rc=$?"
echo "\$ topydo revert   (the documented recovery)"; $BIN -t "$T" -d "$D" revert; echo "rc=$?"
echo "--- todo.txt after recovery attempt ---"; cat "$T" 2>&1; echo "[end]"
echo "--- done.txt after recovery attempt ---"; cat "$D" 2>&1; echo "[end]"
echo "\$ topydo ls -x"; $BIN -t "$T" -d "$D" ls -x; echo "rc=$?"
