#!/bin/sh
# isort's checker, as the 2026-09-06 run's and spike/followup-527's check-isort.sh: each file
# is there, parses, still holds MARKER, and a.py still imports everything it imported.
for n in a b; do
  f="$SIDEEYE_STATE_DIR/$n.py"
  [ -f "$f" ] || { echo "$n.py is missing"; exit 1; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || { echo "$n.py does not parse ($(wc -c < "$f") bytes)"; exit 1; }
  grep -q "MARKER" "$f" || { echo "$n.py lost MARKER"; exit 1; }
done
for m in sys os collections json; do
  grep -q "$m" "$SIDEEYE_STATE_DIR/a.py" || { echo "a.py lost import $m"; exit 1; }
done
exit 0
