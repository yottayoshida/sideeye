#!/bin/sh
# Both declarations must still be in a.js, rewritten or not, and ast-grep must still parse it:
# the rule it was rewritten by finds either zero matches (all rewritten) or both (none).
f=/s/sg/proj/a.js
grep -Eqx '(var|let) x = 1;?' "$f" || { echo "the declaration of x is gone from a.js" >&2; exit 1; }
grep -Eqx '(var|let) y = 2;?' "$f" || { echo "the declaration of y is gone from a.js" >&2; exit 1; }
n=$(cd /s/sg/proj && ast-grep scan --rule rule.yml --json=compact a.js 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))') || { echo "ast-grep could not scan a.js" >&2; exit 1; }
case "$n" in 0|2) exit 0 ;; *) echo "a.js is half rewritten: $n of 2 declarations still match the rule" >&2; exit 1 ;; esac
