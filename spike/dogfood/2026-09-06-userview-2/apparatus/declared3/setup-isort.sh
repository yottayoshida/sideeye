#!/bin/sh
mkdir -p /work/st3/is
cat > /work/st3/is/a.py <<'EOP'
import sys
import os
from collections import OrderedDict
import json

MARKER = "keep-me"
print(sys.argv, os.sep, OrderedDict(), json.dumps({}), MARKER)
EOP
cat > /work/st3/is/b.py <<'EOP'
import zlib
import base64
import abc

MARKER = "keep-me-too"
print(zlib.crc32(b""), base64.b64encode(b""), abc.ABC, MARKER)
EOP
