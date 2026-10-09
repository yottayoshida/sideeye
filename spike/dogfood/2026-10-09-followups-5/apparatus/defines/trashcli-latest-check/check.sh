#!/bin/sh
# The invariant andreafrancia/trash-cli#414 was measured with: trash-list reads every trashinfo with no parse
# error, the three files trashed before are listed, and doomed.txt is in exactly one place — still live, or in
# the trash and listed.
cd "$SIDEEYE_STATE_DIR" || exit 1
export XDG_DATA_HOME="$SIDEEYE_STATE_DIR/data"
out=$(/opt/py/bin/trash-list 2>&1)
case "$out" in *"Parse Error"*|*"nable to parse"*) echo "trash-list: $(echo "$out" | grep -m1 -i -E 'error|parse' | cut -c1-120)"; exit 1;; esac
for k in kept1 kept2 kept3; do echo "$out" | grep -q "live/$k.txt" || { echo "$k.txt not listed"; exit 1; }; done
live=0; [ -f live/doomed.txt ] && live=1
tr=0; [ -f data/Trash/files/doomed.txt ] && echo "$out" | grep -q 'live/doomed.txt' && tr=1
[ $((live + tr)) -eq 1 ] && exit 0
echo "doomed.txt: live=$live, trashed and listed=$tr"; exit 1
