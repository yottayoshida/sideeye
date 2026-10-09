"""Write a Minecraft Anvil region file (r.0.0.mca) holding a few chunks of the 1.18+ shape, enough
for MCA Selector's command-line mode to read them and delete the ones a query selects. Every byte
is written from the format's definitions (4 KiB sectors, an 8 KiB header of offsets and timestamps,
each chunk a big-endian length, a compression byte of 2 and zlib-compressed NBT). Nothing is
downloaded. The chunks differ in InhabitedTime so a query can pick some and leave others.

    python3 make_region.py <region dir> [chunks]
"""
import struct, sys, zlib
from pathlib import Path


def tag(t, name, payload):
    n = name.encode()
    return bytes([t]) + struct.pack(">H", len(n)) + n + payload


def t_int(name, v): return tag(3, name, struct.pack(">i", v))
def t_long(name, v): return tag(4, name, struct.pack(">q", v))
def t_byte(name, v): return tag(1, name, struct.pack(">b", v))
def t_string(name, s):
    b = s.encode(); return tag(8, name, struct.pack(">H", len(b)) + b)
def t_list(name, elem_type, payloads):
    return tag(9, name, bytes([elem_type]) + struct.pack(">i", len(payloads)) + b"".join(payloads))
def compound_payload(*children): return b"".join(children) + b"\x00"
def t_compound(name, *children): return tag(10, name, compound_payload(*children))


def chunk_nbt(x, z, inhabited):
    # A 1.18+ chunk: DataVersion 3465 (1.20.1), full status, no sections (an empty column), the
    # position fields MCA Selector reads, and the InhabitedTime the query filters on.
    return t_compound(
        "",
        t_int("DataVersion", 3465),
        t_int("xPos", x), t_int("zPos", z), t_int("yPos", -4),
        t_string("Status", "minecraft:full"),
        t_long("LastUpdate", 1000 + x * 7 + z),
        t_long("InhabitedTime", inhabited),
        t_byte("isLightOn", 1),
        t_list("sections", 10, []),
        t_list("block_entities", 10, []),
        t_list("PostProcessing", 9, []),
        t_compound("structures", t_compound("References"), t_compound("starts")),
        t_compound("Heightmaps"),
    )


def main():
    out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    header_loc = bytearray(4096); header_ts = bytearray(4096)
    body = bytearray()
    sector = 2  # the first two sectors are the header
    for i in range(n):
        x, z = i % 4, i // 4
        inhabited = 100 if i % 2 == 0 else 5000   # even chunks "barely visited", odd ones lived in
        data = zlib.compress(chunk_nbt(x, z, inhabited))
        payload = struct.pack(">I", len(data) + 1) + b"\x02" + data
        sectors = (len(payload) + 4095) // 4096
        payload += b"\x00" * (sectors * 4096 - len(payload))
        idx = (x + z * 32) * 4
        header_loc[idx:idx + 4] = struct.pack(">I", (sector << 8) | sectors)
        header_ts[idx:idx + 4] = struct.pack(">I", 1700000000 + i)
        body += payload
        sector += sectors
    (out / "r.0.0.mca").write_bytes(bytes(header_loc) + bytes(header_ts) + bytes(body))
    print(f"wrote {out / 'r.0.0.mca'}: {n} chunks, {sector} sectors")


main()
