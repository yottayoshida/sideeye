#!/bin/sh
# w (the wallet's cache, encrypted afresh in every run) is scratch; this judges the wallet through
# monero-wallet-cli itself: it opens with its password and holds the old description (none) or the new.
out=$(monero-wallet-cli --offline --wallet-file "$SIDEEYE_STATE_DIR/w" --password pw --log-file /tmp/chk.log get_description 2>&1)
case "$out" in *"description found: rent-and-savings"*|*"no description found"*) exit 0 ;; esac
echo "the wallet does not open with its description: $(echo "$out" | grep -m1 -i error | cut -c1-120)"; exit 1
