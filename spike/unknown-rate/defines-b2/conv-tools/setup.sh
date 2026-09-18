#!/bin/sh
set -eu
python3 -c 'import os, sys; open(os.path.join(sys.argv[1].encode(), b"caf\xe9.txt"), "w").write("a file whose name is Latin-1\n")' "$TOY_STATE"
