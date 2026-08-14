#!/bin/sh
# Assisted run (#118), pass P1 setup. The gpg home lives OUTSIDE the state
# root (ambient, like khal's cache) — the operation (a plain rename dance)
# never touches gpg; only the checker decrypts. Fixed secrets go in through
# `insert -e` on a pipe; an expected/ reference copy of the whole store is
# part of the recorded pre-state so the checker can compare bytes without
# committed goldens (gpg ciphertext differs per keygen).
set -eu
export GNUPGHOME=/tmp/assisted/pass/gnupg
export PASSWORD_STORE_DIR=/tmp/assisted/pass/state/store
if [ ! -d "$GNUPGHOME" ]; then
    mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
    gpg --batch --quick-gen-key --passphrase "" "assisted@test" default default never >/dev/null 2>&1
fi
mkdir -p /tmp/assisted/pass/state
pass init assisted@test > /dev/null
echo "grace-secret-fixed" | pass insert -e grace > /dev/null
echo "ada-secret-fixed"   | pass insert -e ada   > /dev/null
cp -R "$PASSWORD_STORE_DIR" /tmp/assisted/pass/state/expected
