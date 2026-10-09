#!/bin/sh
f="/s/vim/state/a.txt"
[ -f "$f" ] || { echo "a.txt が無い（保存中に落ちて消えた）"; exit 1; }
[ -s "$f" ] || { echo "a.txt が空になった"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.txt から MARKER が消えた（$(wc -c < "$f") bytes）"; exit 1; }
[ "$(wc -l < "$f")" -eq 3 ] || { echo "a.txt の行数が 3 でない: $(wc -l < "$f")"; exit 1; }
grep -q "line three stays" "$f" || { echo "最終行が消えた"; exit 1; }
exit 0
