"""xref を正しく持つ最小 PDF を書く。

mutool は startxref の無い PDF を repair して読むので、repair 経路ではなく
通常の読み取り経路を測るために正しい xref を作る。
"""
import sys

path = sys.argv[1]

content = b"BT /F1 24 Tf 20 100 Td (probe page) Tj ET\n"

objs = [
    b"<</Type/Catalog/Pages 2 0 R>>",
    b"<</Type/Pages/Kids[3 0 R]/Count 1>>",
    b"<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]"
    b"/Resources<</Font<</F1 5 0 R>>>>/Contents 4 0 R>>",
    b"<</Length " + str(len(content)).encode() + b">>stream\n" + content + b"endstream",
    b"<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>",
]

out = bytearray(b"%PDF-1.4\n")
offsets = []
for i, body in enumerate(objs, start=1):
    offsets.append(len(out))
    out += str(i).encode() + b" 0 obj" + body + b"endobj\n"

xref_at = len(out)
out += b"xref\n0 " + str(len(objs) + 1).encode() + b"\n"
out += b"0000000000 65535 f \n"
for off in offsets:
    out += ("%010d 00000 n \n" % off).encode()
out += (b"trailer<</Size " + str(len(objs) + 1).encode() + b"/Root 1 0 R>>\n"
        b"startxref\n" + str(xref_at).encode() + b"\n%%EOF\n")

with open(path, "wb") as f:
    f.write(bytes(out))
print(f"{path}: {len(out)} bytes")
