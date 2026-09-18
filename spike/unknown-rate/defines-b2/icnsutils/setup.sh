#!/bin/sh
set -eu
python3 - "$TOY_STATE/in32.png" <<'PY'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
w = h = 32
raw = b"".join(b"\x00" + bytes(v for x in range(w) for v in ((x * 8) % 256, (y * 8) % 256, 128, 255))
               for y in range(h))
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PY
