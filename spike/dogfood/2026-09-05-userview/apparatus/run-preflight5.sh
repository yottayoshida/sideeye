#!/bin/sh
# 第5ラウンド: beets のスレッドの出所を最後まで絞る + joplin を測る
set -u
SE=/se/bin/sideeye
SHIM=/se/lib/libsideeye_shim.so
OUT=/work/out
mkdir -p "$OUT"

run() {
  name=$1; shift
  echo "==================== $name ===================="
  "$SE" preflight "$@" --shim "$SHIM" > "$OUT/$name.txt" 2>&1
  rc=$?
  echo "raw rc=$rc"
  head -4 "$OUT/$name.txt"
  echo
}

########## beets: 起動だけでスレッドが出るか ##########
mkdir -p /work/bt2/lib /work/py3/state
cat > /work/bt2/config.yaml <<'CFG'
directory: /work/bt2/lib
library: /work/bt2/lib/library.db
threaded: no
CFG
# --version は state を触らないので、書き込みだけ別に足して観測対象にする
cat > /work/bt2/version-op.sh <<'OP'
#!/bin/sh
/usr/local/bin/beet -c /work/bt2/config.yaml --version > /work/py3/state/version.txt 2>&1
OP
chmod 755 /work/bt2/version-op.sh
echo "--- beet --version（起動だけ）でスレッドが出るか ---"
run beets-version --state /work/py3/state --operation "/work/bt2/version-op.sh"

echo "--- beets の main() を Python から直接呼ぶ ---"
cat > /work/py3/callmain.py <<'PY'
import sys
sys.argv = ["beet", "-c", "/work/bt2/config.yaml", "--version"]
from beets.ui import main
try:
    main()
except SystemExit:
    pass
open("/work/py3/state2/out.txt", "w").write("done\n")
PY
mkdir -p /work/py3/state2
run beets-main-direct --state /work/py3/state2 --operation "/usr/bin/python3 /work/py3/callmain.py"

echo "--- スレッドを作った Python のコードを特定する ---"
cat > /work/py3/trace_thread.py <<'PY'
import threading, traceback, sys
orig = threading.Thread.start
def patched(self, *a, **k):
    sys.stderr.write("=== Thread.start ここから ===\n")
    traceback.print_stack(file=sys.stderr)
    return orig(self, *a, **k)
threading.Thread.start = patched
sys.argv = ["beet", "-c", "/work/bt2/config.yaml", "--version"]
from beets.ui import main
try:
    main()
except SystemExit:
    pass
PY
python3 /work/py3/trace_thread.py > "$OUT/beets-thread-origin.txt" 2>&1
echo "trace raw rc=$?"
grep -E "File \"" "$OUT/beets-thread-origin.txt" 2>/dev/null | tail -6
