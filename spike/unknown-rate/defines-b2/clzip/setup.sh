#!/bin/sh
set -eu
python3 -c 'import sys; open(sys.argv[1], "w").write("the quick brown fox jumps over the lazy dog\n" * 400)' "$TOY_STATE/a.txt"
