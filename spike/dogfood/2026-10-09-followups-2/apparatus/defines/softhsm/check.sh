#!/bin/sh
# tokens/ is scratch; this judges the token through PKCS#11: it logs in with its PIN, key k1 is there,
# and k2 is there or not (before or after the import), and nothing else is.
export SOFTHSM2_CONF=/s/hsm/softhsm2.conf
out=$(pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label t --login --pin 1234 --list-objects --type privkey 2>&1) \
  || { echo "the token does not list its keys: $(echo "$out" | tail -1 | cut -c1-120)"; exit 1; }
labels=$(echo "$out" | awk -F: '/label:/{gsub(/ /,"",$2); print $2}' | sort | tr '\n' ' ')
case "$labels" in "k1 "|"k1 k2 ") exit 0 ;; esac
echo "the token's private keys are '$labels', neither k1 alone nor k1 and k2"; exit 1
