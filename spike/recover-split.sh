#!/bin/sh
# A recovery for TOY_SPLIT_REWRITE (#606): it repairs world 2's crash shape only — derived.txt
# truncated, primary.txt still old — by rolling derived.txt back. World 4's shape (derived.txt
# new, primary.txt truncated) and the completed state are left alone. The two saved exhibits of
# that define are those two worlds, so a correct run predicts earliest `pass` and claim exhibit
# `fail`; one snapshot handed to both legs, or no crash state rebuilt at all, reads the same
# twice, and swapped reads the other way round.
set -u
s=${SIDEEYE_STATE_DIR:?}
if [ ! -s "$s/derived.txt" ] && [ "$(cat "$s/primary.txt" 2>/dev/null)" = "primary-old" ]; then
    printf 'derived-old\n' > "$s/derived.txt"
fi
exit 0
