#!/bin/sh
# slate 3: preflight → explore を 3 対象で。
# checker は「読める」で止めない（slate 1・2 が示した形）: パースできることと、
# 元からあった中身が残っていることは別の検査。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUTP=/work/out3-pf
OUTE=/work/out3-ex
AP=/work/ap3
mkdir -p "$OUTP" "$OUTE" "$AP" /work/wk3-pf /work/wk3-ex
mkdir -p /work/st3/is /work/st3/pu /work/st3/jt

########## setup ##########

cat > "$AP/setup-isort.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st3/is
cat > /work/st3/is/a.py <<'EOP'
import sys
import os
from collections import OrderedDict
import json

MARKER = "keep-me"
print(sys.argv, os.sep, OrderedDict(), json.dumps({}), MARKER)
EOP
cat > /work/st3/is/b.py <<'EOP'
import zlib
import base64
import abc

MARKER = "keep-me-too"
print(zlib.crc32(b""), base64.b64encode(b""), abc.ABC, MARKER)
EOP
EOS

cat > "$AP/setup-pyupgrade.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st3/pu
cat > /work/st3/pu/a.py <<'EOP'
MARKER = "keep-me"
s = "%s-%s" % (1, 2)
d = dict()
print(s, d, MARKER)
EOP
EOS

cat > "$AP/setup-jpegtran.sh" <<'EOS'
#!/bin/sh
mkdir -p /work/st3/jt
python3 - <<'PY'
w = h = 32
with open('/tmp/src.ppm', 'wb') as f:
    f.write(b'P6\n%d %d\n255\n' % (w, h))
    f.write(bytes([(x * 7 + y * 3) % 256 for y in range(h) for x in range(w) for _ in range(3)]))
PY
cjpeg -quality 80 -outfile /work/st3/jt/a.jpg /tmp/src.ppm
EOS

########## checker ##########

cat > "$AP/check-isort.sh" <<'EOC'
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
EOC

cat > "$AP/check-pyupgrade.sh" <<'EOC'
#!/bin/sh
f=/work/st3/pu/a.py
[ -f "$f" ] || { echo "a.py が無い"; exit 1; }
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || {
  echo "a.py をパースできない（$(wc -c < "$f") bytes）"; exit 1; }
grep -q "MARKER" "$f" || { echo "a.py から元の中身 MARKER が消えた"; exit 1; }
exit 0
EOC

cat > "$AP/check-jpegtran.sh" <<'EOC'
#!/bin/sh
f=/work/st3/jt/a.jpg
[ -f "$f" ] || { echo "a.jpg が無い"; exit 1; }
out=$(djpeg -pnm "$f" 2>/dev/null | head -c 32) || {
  echo "a.jpg を djpeg が読めない（$(wc -c < "$f") bytes）"; exit 1; }
[ -n "$out" ] || { echo "a.jpg から画素が出てこない（$(wc -c < "$f") bytes）"; exit 1; }
echo "$out" | head -1 | grep -q "P" || { echo "a.jpg の展開結果が PNM でない"; exit 1; }
exit 0
EOC

chmod 755 "$AP"/*.sh

pf() {
  name=$1; state=$2; setup=$3; op=$4; shift 4
  echo "-------- preflight: $name --------"
  mkdir -p "/work/wk3-pf/$name"
  "$SE" preflight --state "$state" --setup "$setup" --operation "$op" \
    --shim "$SHIM" --work "/work/wk3-pf/$name" "$@" > "$OUTP/$name.txt" 2>&1
  echo "raw rc=$?"
  grep -E "^PREFLIGHT|^UNKNOWN|state-changing" "$OUTP/$name.txt" | head -3
}

ex() {
  name=$1; state=$2; setup=$3; op=$4; chk=$5; shift 5
  echo "==================== explore: $name ===================="
  mkdir -p "/work/wk3-ex/$name"
  "$SE" explore --state "$state" --setup "$setup" --operation "$op" --check "$chk" \
    --shim "$SHIM" --oracle /usr/bin/strace \
    --work "/work/wk3-ex/$name" --json "$OUTE/$name.json" "$@" > "$OUTE/$name.txt" 2>&1
  echo "raw rc=$?   (0=PASS 1=FAIL 2=UNKNOWN 3=setup error)"
  head -16 "$OUTE/$name.txt"
  echo
}

IS_OP='isort /work/st3/is/a.py /work/st3/is/b.py'
PU_OP='pyupgrade --py311-plus /work/st3/pu/a.py'
JT_OP='jpegtran -copy all -optimize -outfile /work/st3/jt/a.jpg /work/st3/jt/a.jpg'

pf isort    /work/st3/is "$AP/setup-isort.sh"    "$IS_OP"
pf pyupgrade /work/st3/pu "$AP/setup-pyupgrade.sh" "$PU_OP" --expect-status 1
pf jpegtran /work/st3/jt "$AP/setup-jpegtran.sh" "$JT_OP"
echo

ex isort    /work/st3/is "$AP/setup-isort.sh"    "$IS_OP" "$AP/check-isort.sh"
ex pyupgrade /work/st3/pu "$AP/setup-pyupgrade.sh" "$PU_OP" "$AP/check-pyupgrade.sh" --expect-status 1
ex jpegtran /work/st3/jt "$AP/setup-jpegtran.sh" "$JT_OP" "$AP/check-jpegtran.sh"
