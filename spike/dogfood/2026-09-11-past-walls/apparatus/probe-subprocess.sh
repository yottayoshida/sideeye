#!/bin/sh
# #556: under --observe syscalls, a Python child whose exec fails along PATH dies of SIGSYS.
# Two probes, each run plain and under `sideeye preflight` in both modes:
#   sp3.py — subprocess.run on a missing program, four ways (absolute path / bare name,
#            with and without pipes). The first minimal attempt used only the absolute path
#            and did not reproduce it; the bare name is what does.
#   sp2.py — ocrmypdf's own get_version("jbig2"), from the main thread and a worker thread.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
cat > /tmp/sp3.py <<'PY'
import subprocess, sys
from subprocess import PIPE, STDOUT
cases = [
    ("abs path, no pipes ", ["/nonexistent-tool"], {}),
    ("abs path, pipes    ", ["/nonexistent-tool"], dict(stdout=PIPE, stderr=STDOUT)),
    ("PATH name, no pipes", ["nonexistent-tool"], {}),
    ("PATH name, pipes   ", ["nonexistent-tool"], dict(stdout=PIPE, stderr=STDOUT)),
]
for tag, args, kw in cases:
    try:
        p = subprocess.run(args, **kw)
        print(tag, "-> ran, returncode", p.returncode, file=sys.stderr)
    except FileNotFoundError:
        print(tag, "-> FileNotFoundError", file=sys.stderr)
open(sys.argv[1], "w").write("x\n")
PY
cat > /tmp/sp2.py <<'PY'
import sys, threading
sys.path.insert(0, "/usr/lib/python3/dist-packages")
from ocrmypdf.subprocess import get_version
def probe(tag):
    try:
        print(tag, "get_version(jbig2) ->", get_version("jbig2"), file=sys.stderr)
    except Exception as e:
        print(tag, "get_version(jbig2) raised", type(e).__name__, str(e)[:120], file=sys.stderr)
probe("main-thread:")
t = threading.Thread(target=probe, args=("worker-thread:",)); t.start(); t.join()
open(sys.argv[1], "w").write("x\n")
PY
echo "jbig2: $(command -v jbig2 || echo absent)   pngquant: $(command -v pngquant || echo absent)"
for p in sp3 sp2; do
  mkdir -p /s/$p/plain
  echo "==================== $p / plain ===================="
  python3 /tmp/$p.py /s/$p/plain/o.txt
  for m in wrappers syscalls; do
    mkdir -p /s/$p/$m /wk/$p/$m
    echo "==================== $p / preflight --observe $m ===================="
    "$SE" preflight --state /s/$p/$m --operation "python3 /tmp/$p.py /s/$p/$m/o.txt" \
      --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work /wk/$p/$m 2>&1 \
      | grep -E " -> |thread:|^(UNKNOWN|PREFLIGHT)"
  done
done
