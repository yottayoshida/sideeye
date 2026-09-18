#!/bin/sh
set -eu
python3 - "$TOY_STATE/a.png" <<'PY'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
w = h = 16
raw = b"".join(b"\x00" + bytes((x * 16) % 256 for x in range(w) for _ in range(3)) for y in range(h))
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 1)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PY
