#!/bin/sh
# isort's setup, as the 2026-09-06 run's and spike/followup-527's setup-isort.sh.
mkdir -p "$SIDEEYE_STATE_DIR"
cat > "$SIDEEYE_STATE_DIR/a.py" <<'EOP'
import sys
import os
from collections import OrderedDict
import json

MARKER = "keep-me"
print(sys.argv, os.sep, OrderedDict(), json.dumps({}), MARKER)
EOP
cat > "$SIDEEYE_STATE_DIR/b.py" <<'EOP'
import zlib
import base64
import abc

MARKER = "keep-me-too"
print(zlib.crc32(b""), base64.b64encode(b""), abc.ABC, MARKER)
EOP
