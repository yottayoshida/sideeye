"""Write a small music library as FLAC files with Vorbis comments: STREAMINFO, the tags, and one
frame header's worth of nothing: TagLib reads the tags and the duration from the metadata blocks.
    python3 make_flac.py <music dir> <number of albums, 1-3>"""
import os, struct, sys
root = sys.argv[1]
def block(kind, data, last): return bytes([(0x80 if last else 0) | kind]) + len(data).to_bytes(3, "big") + data
def streaminfo(samples):
    # min/max block 4096, frame sizes unknown, 44100 Hz, 2 channels, 16 bits, total samples, no MD5
    v = (44100 << 44) | (1 << 41) | (15 << 36) | samples
    return struct.pack(">HH", 4096, 4096) + b"\0" * 6 + v.to_bytes(8, "big") + b"\0" * 16
def comments(tags):
    vendor = b"sideeye-dogfood"
    out = struct.pack("<I", len(vendor)) + vendor + struct.pack("<I", len(tags))
    for k, v in tags:
        e = f"{k}={v}".encode(); out += struct.pack("<I", len(e)) + e
    return out
albums = [("Northern Lights", "Ada Lake", 2019), ("Harbour", "The Pilots", 2022), ("Lowlands", "Ada Lake", 2024)]
for a, (album, artist, year) in enumerate(albums[: int(sys.argv[2])]):
    d = os.path.join(root, artist, album); os.makedirs(d, exist_ok=True)
    for t in range(1, 4):
        tags = [("TITLE", f"{album} {t}"), ("ARTIST", artist), ("ALBUM", album), ("TRACKNUMBER", str(t)), ("DATE", str(year)), ("GENRE", "Ambient")]
        body = b"fLaC" + block(0, streaminfo(44100 * (60 + t)), False) + block(4, comments(tags), True)
        open(os.path.join(d, f"{t:02} {album} {t}.flac"), "wb").write(body)
print("flac files written")
