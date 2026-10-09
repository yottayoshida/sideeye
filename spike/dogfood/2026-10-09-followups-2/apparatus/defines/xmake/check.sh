#!/bin/sh
# xmake.conf is scratch (its table's keys come out in a varying order); this judges it instead: a
# complete table that still holds the seeded network = "private", with the theme unset or the new one.
python3 - "$SIDEEYE_STATE_DIR/xmake.conf" <<'E'
import re, sys
try:
    s = open(sys.argv[1]).read()
except OSError as e:
    print("xmake.conf unreadable: %s" % e); sys.exit(1)
if not s.strip().endswith("}"):
    print("xmake.conf does not end its table (%d bytes)" % len(s)); sys.exit(1)
if not re.search(r'network\s*=\s*"private"', s):
    print("xmake.conf lost network = private (%d bytes)" % len(s)); sys.exit(1)
m = re.search(r'theme\s*=\s*"([^"]*)"', s)
if m and m.group(1) != "plain":
    print("theme is %r" % m.group(1)); sys.exit(1)
E
