#!/bin/sh
# Opened by Chroma on a copy: the SQLite file is whole, and the collection holds the same 100
# documents and embeddings the seed left (a vacuum changes neither).
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"
ic=$(sqlite3 "$t/chroma.sqlite3" "PRAGMA integrity_check" 2>&1)
got=$(/opt/chroma/bin/python -I /ap/defines/chroma/make.py read "$t" 2>&1 | tail -1)
rm -rf "$t"
[ "$ic" = ok ] || { echo "checker(chroma): integrity_check: $(echo "$ic" | head -2 | tr '\n' ' ')"; exit 1; }
[ "$got" = "$(cat /s/.chroma-expect)" ] || { echo "checker(chroma): collection = $got, want $(cat /s/.chroma-expect)"; exit 1; }
