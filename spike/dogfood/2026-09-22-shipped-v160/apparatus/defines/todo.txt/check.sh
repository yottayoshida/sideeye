#!/bin/sh
# The two tasks that were there before the operation must still be listed, by todo.sh itself.
out=$(bash /opt/todo/todo.sh -d /s/todo/todo.cfg -p ls 2>&1) || { echo "todo.sh ls failed: $out" >&2; exit 1; }
echo "$out" | grep -q "call mom" || { echo "the task 'call mom' is gone" >&2; exit 1; }
echo "$out" | grep -q "buy milk" || { echo "the task 'buy milk' is gone" >&2; exit 1; }
exit 0
