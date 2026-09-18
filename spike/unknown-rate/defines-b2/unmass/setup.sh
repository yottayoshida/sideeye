#!/bin/sh
set -eu
python3 - "$TOY_STATE/test.pak" <<'PY'
import struct, sys
files = [(b"hello.txt", b"hello world\n"), (b"data/second.dat", b"second file\n")]
data = b"".join(d for _, d in files)
dir_off = 12 + len(data)
out = b"PACK" + struct.pack("<ii", dir_off, 64 * len(files)) + data
off = 12
for name, d in files:
    out += name.ljust(56, b"\0") + struct.pack("<ii", off, len(d))
    off += len(d)
open(sys.argv[1], "wb").write(out)
PY
