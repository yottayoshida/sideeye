#!/bin/sh
# After a crash the database still opens with its key and holds every entry it held before; the
# new entry may or may not be there.
set -u
d=${SIDEEYE_STATE_DIR:?}
l=$(keepassxc-cli ls -q --no-password -k /s/kpaux/key.keyx "$d/vault.kdbx" < /dev/null 2>&1) || { echo "checker(keepassxc): the database does not open: $(echo "$l" | head -2 | tr '\n' ' ')"; exit 1; }
for e in bank email nas; do echo "$l" | grep -qx "$e" || { echo "checker(keepassxc): entry $e is gone"; exit 1; }; done
exit 0
