set -eu
rm -rf /s/zstd-userview3 && mkdir -p /s/zstd-userview3/state /s/zstd-userview3/aux
mkdir -p "/s/zstd-userview3/state"
rm -f "/s/zstd-userview3/state/f.bin.zst"
python3 - "/s/zstd-userview3/state/f.bin" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    for i in range(20000):
        f.write(b"MARKER-%06d-payload\n" % i)
PY
cp "/s/zstd-userview3/state/f.bin" /s/zstd-userview3/aux/f.bin.orig
