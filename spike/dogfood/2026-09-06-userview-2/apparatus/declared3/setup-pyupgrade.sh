#!/bin/sh
mkdir -p /work/st3/pu
cat > /work/st3/pu/a.py <<'EOP'
MARKER = "keep-me"
s = "%s-%s" % (1, 2)
d = dict()
print(s, d, MARKER)
EOP
