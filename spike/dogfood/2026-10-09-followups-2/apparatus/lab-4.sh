#!/bin/sh
# Lab 4: SoftHSM's token lost without Sideeye — a token with one key, a second key imported, and
# strace killing softhsm2-util at its first write to the token's token.object (after the truncation
# Sideeye found). Then what the token answers.
#   docker run --rm --network none --cap-add SYS_PTRACE -v <apparatus>:/ap:ro sideeye-fu2-1009 sh /ap/lab-4.sh
set -u
export SOFTHSM2_CONF=/t/softhsm2.conf
rm -rf /t && mkdir -p /t/tokens
printf 'directories.tokendir = /t/tokens\nobjectstore.backend = file\nlog.level = ERROR\n' > /t/softhsm2.conf
softhsm2-util --init-token --free --label t --pin 1234 --so-pin 5678 > /dev/null
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /t/k1.pem 2>/dev/null
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /t/k2.pem 2>/dev/null
softhsm2-util --import /t/k1.pem --token t --pin 1234 --label k1 --id 01 > /dev/null
tok=$(ls -d /t/tokens/*/ | head -1); echo "token directory: $tok"; ls -l "$tok"
echo "## before: the token's private keys"
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label t --login --pin 1234 --list-objects --type privkey 2>&1 | grep -E 'label|error'
strace -f -qq -o /tmp/imp.strace -P "${tok}token.object" -e trace=openat,ftruncate,truncate,write -e inject=write:signal=KILL \
  softhsm2-util --import /t/k2.pem --token t --pin 1234 --label k2 --id 02; echo "softhsm2-util exit $?"
grep -v ENOENT /tmp/imp.strace | tail -5 | cut -c1-160
ls -l "$tok"
echo "## after: the slots, and the token's private keys"
softhsm2-util --show-slots 2>&1 | grep -E 'Label|Slot [0-9]|Token' | head -6
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --token-label t --login --pin 1234 --list-objects --type privkey 2>&1 | head -3
