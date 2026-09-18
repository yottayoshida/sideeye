#!/bin/sh
set -eu
python3 - "$TOY_STATE/in.pcap" <<'PY'
import struct, sys
pk = b"\x00" * 14 + b"\x45" * 20
with open(sys.argv[1], "wb") as f:
    f.write(struct.pack("<IHHiIII", 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1))
    for i in range(3):
        f.write(struct.pack("<IIII", 1700000000 + i, 0, len(pk), len(pk)) + pk)
PY
