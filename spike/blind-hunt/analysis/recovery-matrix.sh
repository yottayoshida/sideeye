#!/bin/sh
# Post-Seal-B analysis: at every crash point, under the DEFAULT configuration,
# what does the documented no-argument recovery do?
# Classification: REFUSED / UNDID-THE-CRASHED-COMMAND / UNDID-AN-OLDER-COMMAND.
export HOME=/tmp/blind/home; mkdir -p "$HOME"
BIN=/usr/local/bin/topydo

matrix() {
    op=$1; pts=$2
    echo "======== operation: $op (default config, backups on) ========"
    pt=1
    while [ "$pt" -le "$pts" ]; do
        S=/tmp/m/$op-$pt; rm -rf "$S"; mkdir -p "$S"
        T=$S/todo.txt; D=$S/done.txt
        $BIN -t "$T" -d "$D" add seed-task >/dev/null 2>&1
        case $op in
          add) OPARGS="add water-plants" ;;
          do)  $BIN -t "$T" -d "$D" add water-plants >/dev/null 2>&1; OPARGS="do 1" ;;
        esac
        SIDEEYE_STATE_DIR=$S SIDEEYE_TRACE_PATH=$S/trace.bin \
        LD_PRELOAD=/work/zig-out/lib/libsideeye_shim.so SIDEEYE_KILL_AT=$pt \
        $BIN -t "$T" -d "$D" $OPARGS >/dev/null 2>&1
        krc=$?
        seed_before_recovery=$($BIN -t "$T" -d "$D" ls -x 2>/dev/null | grep -c seed-task)
        msg=$($BIN -t "$T" -d "$D" revert 2>&1 | head -1)
        seed_after=$($BIN -t "$T" -d "$D" ls -x 2>/dev/null | grep -c seed-task)

        case "$msg" in
            "No backup"*)                verdict="REFUSED" ;;
            *"add water-plants"|*"do 1") verdict="undid-the-crashed-command" ;;
            *"add seed-task")            verdict="UNDID-AN-OLDER-COMMAND" ;;
            *)                           verdict="other" ;;
        esac
        lost=""
        [ "$seed_before_recovery" = 1 ] && [ "$seed_after" = 0 ] && lost="  <-- recovery DESTROYED an intact task"
        printf 'pt=%-2s kill_rc=%-3s seed_before_recovery=%s seed_after=%s  %-26s "%s"%s\n' \
            "$pt" "$krc" "$seed_before_recovery" "$seed_after" "$verdict" "$msg" "$lost"
        pt=$((pt + 1))
    done
    echo ""
}
matrix add 6
matrix do 8
