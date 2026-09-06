#!/bin/sh
f=/work/st3/pu/a.py
[ -f "$f" ] || { echo "a.py が無い"; exit 1; }
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || {
  echo "a.py をパースできない（$(wc -c < "$f") bytes）"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.py から元の中身 MARKER が消えた"; exit 1; }
exit 0
