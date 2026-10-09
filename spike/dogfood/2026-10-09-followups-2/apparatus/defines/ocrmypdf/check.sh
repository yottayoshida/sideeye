#!/bin/sh
# The file ocrmypdf rewrites in place must still be a PDF in every world: the header, and
# a trailer in its last kilobyte. (2026-09-11-read-only-542/apparatus/ocrmypdf.sh, check.sh,
# with the path moved.)
python3 - /s/ocrmypdf/ocr/a.pdf <<'EOP'
import sys
try:
    b = open(sys.argv[1], "rb").read()
except OSError as e:
    print("a.pdf unreadable: %s" % e); sys.exit(1)
if not b.startswith(b"%PDF-"):
    print("a.pdf does not start with %%PDF- (%d bytes)" % len(b)); sys.exit(1)
if b"%%EOF" not in b[-1024:]:
    print("a.pdf has no %%%%EOF in its last KiB (%d bytes)" % len(b)); sys.exit(1)
EOP
