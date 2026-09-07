#!/bin/sh
# isort の crash point 数が記録（09-06, v1.2.0 系, 7/7）と今日（main, 9/9）で違う。
# モード差ではない（今日は両モード 9/9）。engine の世代差かを 4083db2 で測る。
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
R=/localrun
AP=$R/ap
mkdir -p "$AP" "$R/out" "$R/wk"

cat > "$AP/setup-isort.sh" <<'EOS'
#!/bin/sh
mkdir -p "$SD"
cat > "$SD/a.py" <<'EOP'
import sys
import os
from collections import OrderedDict
import json

MARKER = "keep-me"
print(sys.argv, os.sep, OrderedDict(), json.dumps({}), MARKER)
EOP
cat > "$SD/b.py" <<'EOP'
import zlib
import base64
import abc

MARKER = "keep-me-too"
print(zlib.crc32(b""), base64.b64encode(b""), abc.ABC, MARKER)
EOP
EOS

cat > "$AP/check-isort.sh" <<'EOC'
#!/bin/sh
for n in a b; do
  f="$SD/$n.py"
  [ -f "$f" ] || { echo "$n.py が無い"; exit 1; }
  python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" 2>/dev/null || { echo "$n.py をパースできない"; exit 1; }
  grep -q "MARKER" "$f" || { echo "$n.py から MARKER が消えた"; exit 1; }
done
exit 0
EOC
chmod 755 "$AP"/*.sh

{
  echo "# engine identity of the PRE-CHANGE build (4083db2), recorded inside the box"
  "$SE" --version 2>&1 | head -1
  sha256sum "$SE" "$SHIM" 2>/dev/null || shasum -a 256 "$SE" "$SHIM"
} > "$R/out/engine-identity-4083db2.txt"
cat "$R/out/engine-identity-4083db2.txt"

SD="$R/st/old/isort"; export SD
mkdir -p "$SD" "$R/wk/old-isort"
"$SE" explore --state "$SD" --setup "$AP/setup-isort.sh" \
  --operation "isort $SD/a.py $SD/b.py" --check "$AP/check-isort.sh" \
  --shim "$SHIM" --oracle /usr/bin/strace --work "$R/wk/old-isort" \
  > "$R/out/isort-old.txt" 2>&1
echo "old engine isort: raw rc=$?"
grep -m3 -nE "^(PASS|FAIL|UNKNOWN)|explored .* worlds|crash points" "$R/out/isort-old.txt"
echo "--- engine identity"
grep -m1 -i "sideeye [0-9]" "$R/out/isort-old.txt" || head -3 "$R/out/isort-old.txt"
mkdir -p /hostout; cp "$R/out/isort-old.txt" "$R/out/engine-identity-4083db2.txt" /hostout/ 2>/dev/null
