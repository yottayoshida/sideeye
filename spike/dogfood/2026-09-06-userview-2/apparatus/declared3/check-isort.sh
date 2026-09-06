#!/bin/sh
for n in a b; do
  f="/work/st3/is/$n.py"
  [ -f "$f" ] || { echo "$n.py が無い"; exit 1; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || {
    echo "$n.py をパースできない（$(wc -c < "$f") bytes）"; exit 1; }
  grep -q "MARKER" "$f" || { echo "$n.py から元の中身 MARKER が消えた"; exit 1; }
done
# 元の import がすべて残っているか（並べ替えは中身を落とさない）
for m in sys os collections json; do
  grep -q "$m" /work/st3/is/a.py || { echo "a.py から import $m が消えた"; exit 1; }
done
exit 0
