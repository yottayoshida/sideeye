#!/usr/bin/env python3
"""Lab 11's inspector, run as sndfile's declared recovery on each crashed world (so Sideeye hands it the
state the crash left, and labels its lines `recovery world N:`). It changes nothing: it walks the WAV's
RIFF chunks, says whether the RIFF size and each chunk size agree with the file, and whether the sample
data still equals the 16000 frames sndfile's seed.sh wrote."""
import struct
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/s/snd/a.wav"
b = open(path, "rb").read()
expected = b"".join(struct.pack("<h", (i * 37) % 3000) for i in range(16000))
print(f"file {len(b)} bytes; head {b[:4]!r}")
if b[:4] != b"RIFF" or b[8:12] != b"WAVE":
    print("not a RIFF/WAVE header")
    sys.exit(0)
riff = struct.unpack("<I", b[4:8])[0]
print(f"RIFF size field {riff} -> file should be {riff + 8} bytes ({'agrees' if riff + 8 == len(b) else 'DISAGREES'})")
off = 12
while off + 8 <= len(b):
    cid = b[off:off + 4]
    size = struct.unpack("<I", b[off + 4:off + 8])[0]
    body = b[off + 8:off + 8 + size]
    note = ""
    if cid == b"data":
        note = "samples intact" if body == expected else f"samples DIFFER ({sum(1 for x, y in zip(body, expected) if x != y)} bytes differ, {len(body)} of {len(expected)} present)"
    elif cid in (b"LIST", b"bext"):
        note = repr(body[:40])
    print(f"chunk {cid!r} at {off}, size {size}{' (runs past the end)' if off + 8 + size > len(b) else ''}: {note}")
    off += 8 + size + (size & 1)
if off < len(b):
    print(f"{len(b) - off} trailing bytes no chunk accounts for: {b[off:off + 40]!r}")
