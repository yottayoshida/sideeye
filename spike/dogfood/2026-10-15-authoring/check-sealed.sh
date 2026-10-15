#!/bin/sh
# check-sealed.sh: exits 0 when the sealed files hash to the manifest seal.json records.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
got=$(python3 -I "$here/tally.py" --manifest)
want=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifest"])' "$here/seal.json" 2> /dev/null) || {
    echo "check-sealed: no seal.json"; exit 1; }
[ "$got" = "$want" ] || { echo "check-sealed: the sealed files hash to $got, seal.json records $want"; exit 1; }
echo "ok   sealed files match $want"
