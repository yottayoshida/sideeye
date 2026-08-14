#!/bin/sh
# Assisted run (#118), pass P1 checker. Property (proposals.md P1): an
# interrupted `pass mv` never loses the secret. File legs first, the target
# (decryption queries) last; queries must not modify the store.
set -u
export GNUPGHOME=/tmp/assisted/pass/gnupg
export PASSWORD_STORE_DIR=/tmp/assisted/pass/state/store
S=$PASSWORD_STORE_DIR
E=/tmp/assisted/pass/state/expected
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT

fail() { echo "checker(pass-mv): $*"; exit 1; }

[ -d "$S" ] || fail "store is missing"
[ -d "$E" ] || fail "expected reference copy is missing from the recorded state"

# ---- I-C: bystander and store id, byte-conserved (file legs) ----
cmp -s "$E/grace.gpg" "$S/grace.gpg" || fail "I-C: bystander grace.gpg differs from the recorded ciphertext (or is missing)"
cmp -s "$E/.gpg-id"   "$S/.gpg-id"   || fail "I-C: .gpg-id differs from the recorded copy (or is missing)"

# ---- the move window: ada's ciphertext at exactly one of the two paths,
# byte-equal to the recorded ciphertext (same-id move = bytes unchanged) ----
old=$S/ada.gpg
new=$S/moved/ada.gpg
if [ -f "$old" ] && [ -f "$new" ]; then fail "move window: ada exists at BOTH paths"; fi
if [ -f "$old" ]; then loc=$old; show=ada
elif [ -f "$new" ]; then loc=$new; show=moved/ada
else fail "move window: ada exists at NEITHER path — the secret is lost"; fi
cmp -s "$E/ada.gpg" "$loc" || fail "move window: ada's ciphertext at $loc differs from the recorded bytes"

# ---- query legs (the target runs LAST; snapshot for write-neutrality) ----
cp -R "$S" "$T/snap" || exit 2
gout=$(timeout 10 pass show grace < /dev/null 2>&1)
grc=$?
[ "$grc" -eq 0 ] || fail "I-Q: bystander decrypt exited $grc: $gout"
[ "$gout" = "grace-secret-fixed" ] || fail "I-Q: bystander decrypted to something else: $gout"
aout=$(timeout 10 pass show "$show" < /dev/null 2>&1)
arc=$?
[ "$arc" -eq 0 ] || fail "move window: surviving ada at '$show' does not decrypt (rc $arc): $aout"
[ "$aout" = "ada-secret-fixed" ] || fail "move window: ada decrypted to something else: $aout"
diff -r "$T/snap" "$S" > /dev/null 2>&1 || fail "I-W: a query changed the store's bytes"

exit 0
