#!/bin/sh
# fw.bin is scratch (a fresh ECDSA nonce in every signature); this judges it instead: the image is
# the original byte for byte, or the original followed by a signature espsecure itself verifies.
f="$SIDEEYE_STATE_DIR/fw.bin"; o=/s/esp-in/fw.orig
[ -f "$f" ] || { echo "fw.bin is missing"; exit 1; }
cmp -s "$f" "$o" && exit 0
head -c 65536 "$f" | cmp -s - "$o" || { echo "fw.bin's first 64 KiB are not the original ($(wc -c < "$f") bytes)"; exit 1; }
espsecure verify-signature --version 2 --keyfile "$SIDEEYE_STATE_DIR/k.pem" "$f" > /tmp/esp-verify.txt 2>&1 || { echo "the signature does not verify: $(tail -1 /tmp/esp-verify.txt | cut -c1-120)"; exit 1; }
exit 0
