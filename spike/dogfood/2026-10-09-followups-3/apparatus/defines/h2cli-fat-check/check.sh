#!/bin/sh
# drumkit.xml is scratch (its attributes come out in a varying order, transcripts/twice-h2cli.txt); this
# judges it as Hydrogen's kit: it parses as XML, still names the kit, and lists its instruments.
python3 - "$SIDEEYE_STATE_DIR/drumkit.xml" <<'P'
import sys, xml.etree.ElementTree as ET
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as e:
    print("drumkit.xml does not parse: %s" % e); sys.exit(1)
text = ET.tostring(root, encoding="unicode")
if "Box Kit" not in text:
    print("drumkit.xml no longer names the kit"); sys.exit(1)
if "instrument" not in text:
    print("drumkit.xml lists no instrument"); sys.exit(1)
P
