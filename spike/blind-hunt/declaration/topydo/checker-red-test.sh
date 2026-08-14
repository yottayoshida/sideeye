#!/bin/sh
# Seal B artifact (ADR 0012): red-side sanity of the declared checker, WITHOUT
# observing any topydo failure. Committed so the covenant-critical claim — that
# no non-normal target behavior was seen before the seal — can be checked
# against the actual fixtures and commands, not a summary.
#
# Every state below is hand-fabricated by THIS script (printf), not produced by
# topydo. Editing state files with other tools is itself a documented-normal
# scenario for this target (its docs discuss files "modified with other editors
# / applications"). The only topydo invocation the checker makes over these
# states is `ls` (and `revert ls` for the revert arm, unused here) — plain
# queries over user-authored text files, i.e. normal behavior. The checker's
# red side against real crash states belongs to sideeye's falsification gate,
# after Seal B.
#
# Usage (inside the pinned container, repo mounted at /work):
#   sh /work/spike/blind-hunt/declaration/topydo/checker-red-test.sh
set -u
export HOME=/tmp/blind/home
mkdir -p "$HOME"
here=/work/spike/blind-hunt/declaration/topydo/ops
S=/tmp/blind/hunt/do/state
fails=0

fixture() {
    echo "--- fixture: todo.txt ---"
    cat "$S/todo.txt" 2>/dev/null || echo "(absent)"
    echo "--- fixture: done.txt ---"
    cat "$S/done.txt" 2>/dev/null || echo "(absent)"
}
expect_red() {
    name=$1
    fixture
    echo "\$ (cd $here && sh ./check.sh do)"
    ( cd "$here" && sh ./check.sh do ) >/tmp/red.out 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "ok   $name: checker exited $rc — $(cat /tmp/red.out)"
    else
        echo "FAIL $name: checker exited 0 on a state it must reject"
        fails=$((fails+1))
    fi
    echo ""
}
mkdir -p "$S"

echo "===== 1. I-C loss: the declared task is in neither file ====="
printf '2026-08-13 unrelated-task\n' > "$S/todo.txt"
printf 'x 2026-08-13 2026-08-13 other-done\n' > "$S/done.txt"
expect_red "I-C loss"

echo "===== 2. I-C anchoring: the task text only inside a longer token ====="
printf '2026-08-13 rewater-plantsed\n' > "$S/todo.txt"
rm -f "$S/done.txt"
expect_red "I-C anchored"

echo "===== 3. I-D2 duplication: the task in both files ====="
printf '2026-08-13 water-plants\n' > "$S/todo.txt"
printf 'x 2026-08-13 2026-08-13 water-plants\n' > "$S/done.txt"
expect_red "I-D2 duplication"

echo "===== 4. I-F: a done.txt line with no completed-task mark ====="
printf '2026-08-13 water-plants\n' > "$S/todo.txt"
printf 'not-a-completed-task\n' > "$S/done.txt"
expect_red "I-F non-x line"

echo "===== 5. I-F: an x line missing the completion date ====="
printf '2026-08-13 water-plants\n' > "$S/todo.txt"
printf 'x other-task\n' > "$S/done.txt"
expect_red "I-F missing date"

echo "===== 6. Green control: task active, archive absent ====="
printf '2026-08-13 water-plants\n' > "$S/todo.txt"
rm -f "$S/done.txt"
fixture
( cd "$here" && sh ./check.sh do ) >/tmp/red.out 2>&1
rc=$?
if [ $rc -eq 0 ]; then echo "ok   green control: checker exits 0"; else
    echo "FAIL green control: rc=$rc — $(cat /tmp/red.out)"; fails=$((fails+1)); fi

echo ""
echo "red-run fails=$fails"
[ $fails -eq 0 ]
