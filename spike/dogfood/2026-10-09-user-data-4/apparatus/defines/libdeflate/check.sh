#!/bin/sh
# gzip's promise: the text survives, either as notes.txt or inside notes.txt.gz. Exit 0 when
# notes.txt holds the original bytes, or when notes.txt.gz decompresses to them; exit 1 when
# neither does (the text is nowhere). The original's digest is written by the seed, outside --state.
set -u
d=${SIDEEYE_STATE_DIR:?}
want=$(cat /s/gz-expect.sha256)
if [ -f "$d/notes.txt" ] && [ "$(sha256sum < "$d/notes.txt" | cut -d' ' -f1)" = "$want" ]; then exit 0; fi
if [ -f "$d/notes.txt.gz" ] && [ "$(libdeflate-gzip -d -c "$d/notes.txt.gz" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$want" ]; then exit 0; fi
echo "checker(libdeflate): the text is in neither notes.txt nor notes.txt.gz"
exit 1
