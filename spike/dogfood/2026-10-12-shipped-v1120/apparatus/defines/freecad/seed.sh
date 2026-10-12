set -eu
rm -rf /s/fc /s/fcaux && mkdir -p /s/fc/.tmp /s/fc/.home /s/fcaux
cat > /s/fcaux/mk.py <<'EOF'
import FreeCAD, Part
d = FreeCAD.newDocument("part")
b = d.addObject("Part::Box", "Box"); b.Length = 10; b.Width = 4; b.Height = 2
c = d.addObject("Part::Cylinder", "Bore"); c.Radius = 1; c.Height = 2
cut = d.addObject("Part::Cut", "Bracket"); cut.Base = b; cut.Tool = c
d.recompute(); d.saveAs("/s/fc/part.FCStd")
EOF
cat > /s/fcaux/edit.py <<'EOF'
import FreeCAD
d = FreeCAD.openDocument("/s/fc/part.FCStd")
d.getObject("Box").Length = 20
d.recompute(); d.save()
EOF
cat > /s/fcaux/check.py <<'EOF'
import os, FreeCAD
p = os.path.join(os.environ["SIDEEYE_STATE_DIR"], "part.FCStd")
try:
    d = FreeCAD.openDocument(p)
    n = d.getObject("Box").Length.Value
    ok = n in (10.0, 20.0) and d.getObject("Bracket") is not None
    print("checker(freecad): Box.Length=%s" % n)
except Exception as e:
    print("checker(freecad): the document does not open: %s" % e); ok = False
os._exit(0 if ok else 1)
EOF
/opt/freecad/usr/bin/freecadcmd /s/fcaux/mk.py < /dev/null > /s/fcaux/mk.log 2>&1
[ -s /s/fc/part.FCStd ]
install -m 755 /ap/defines/freecad/check.sh /s/fc-check.sh
