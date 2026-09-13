#!/bin/sh
# #556 re-measurement: the four-row table from spike/dogfood/2026-09-11-past-walls,
# against whichever engine+shim is mounted at /se. Prints the build it ran.
set -u
SE=/se/sideeye
SHIM=/se/libsideeye_shim.so
echo "engine: $("$SE" --version 2>&1 | head -1)"
echo "shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
echo "python: $(python3 --version 2>&1)  libc: $(ldd --version 2>&1 | head -1)"
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
mkdir -p /s/plain
echo "==================== plain ===================="
python3 /tmp/sp3.py /s/plain/o.txt
for m in wrappers syscalls; do
  mkdir -p /s/$m /wk/$m
  echo "==================== preflight --observe $m ===================="
  "$SE" preflight --state /s/$m --operation "python3 /tmp/sp3.py /s/$m/o.txt" \
    --shim "$SHIM" --oracle /usr/bin/strace --observe $m --work /wk/$m > /tmp/pf.$m.txt 2>&1
  echo "preflight rc=$?"
  grep -E " -> |^(UNKNOWN|PREFLIGHT)" /tmp/pf.$m.txt
done
