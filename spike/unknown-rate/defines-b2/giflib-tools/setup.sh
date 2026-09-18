#!/bin/sh
set -eu
python3 -c 'import base64, sys; open(sys.argv[1], "wb").write(base64.b64decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))' "$TOY_STATE/in.gif"
