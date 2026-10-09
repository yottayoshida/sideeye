#!/bin/sh
# cipher/gocryptfs.conf is scratch: the master key is wrapped afresh (a new scrypt salt) in every run.
# This judges it through gocryptfs-xray: the old or the new passphrase unwraps the same master key.
conf="$SIDEEYE_STATE_DIR/cipher/gocryptfs.conf"; want=$(cat /s/gocryptfs-in/masterkey)
for p in old new; do
  got=$(/opt/bin/gocryptfs-xray -dumpmasterkey "$conf" < /s/gocryptfs-in/$p 2>/dev/null | tail -1)
  [ "$got" = "$want" ] && exit 0
done
echo "neither passphrase unwraps the master key ($( [ -f "$conf" ] && wc -c < "$conf" || echo absent) bytes)"; exit 1
