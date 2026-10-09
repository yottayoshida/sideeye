set -eu
rm -rf /s/zstd && mkdir -p /s/zstd/state /s/zstd/aux
python3 - /s/zstd/state/f.bin <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(50000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp /s/zstd/state/f.bin /s/zstd/aux/f.bin.orig
cp /s/zstd/state/f.bin /s/zstd/f.orig
