set -eu
rm -rf /s/font /s/font-in && mkdir -p /s/font /s/font-in
/opt/py/bin/python -I - <<'PY'
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder([".notdef", "A"]); fb.setupCharacterMap({65: "A"})
p = TTGlyphPen(None); p.moveTo((100, 0)); p.lineTo((500, 700)); p.lineTo((900, 0)); p.closePath(); g = p.glyph()
fb.setupGlyf({".notdef": g, "A": g}); fb.setupHorizontalMetrics({".notdef": (1000, 100), "A": (1000, 100)})
fb.setupHorizontalHeader(ascent=800, descent=-200); fb.setupNameTable({"familyName": "T", "styleName": "Regular"})
fb.setupOS2(); fb.setupPost(); fb.save("/s/font/f.ttf")
PY
printf '%064d' 0 > /s/font-in/blob.bin
test -s /s/font/f.ttf
