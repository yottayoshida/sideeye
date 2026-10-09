set -eu
rm -rf /s/lz4 && mkdir -p /s/lz4/state /s/lz4/aux
python3 - /s/lz4/state/f.bin <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(250000):
        f.write(b"MARKER-%07d-payload\n" % i)
PY
cp /s/lz4/state/f.bin /s/lz4/aux/lz4.orig
