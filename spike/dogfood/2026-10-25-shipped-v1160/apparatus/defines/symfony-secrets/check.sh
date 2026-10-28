#!/bin/sh
# After a crash anywhere in the rotation, the application can still read every secret it was given:
# `secrets:list --reveal` (Symfony's own reader) decrypts all three to the values the seed set. A vault
# whose key and secrets are out of step reads them as null — the secrets are lost.
set -u
fail() { echo "checker(symfony-secrets): $*"; exit 1; }
cd /s/sf || fail "no project"
out=$(php bin/console secrets:list --reveal --env=prod 2>&1) || fail "secrets:list exited $?: $(printf '%s' "$out" | tail -c 300)"
for want in 'postgresql://app:Pg-2026-prod@db.internal:5432/app' 'example-stripe-live-secret-0001' 'smtp://mailer:Mx-2026@smtp.internal:587'; do
    printf '%s' "$out" | grep -q -F "\"$want\"" || fail "a secret no longer decrypts to its value ($want): $(printf '%s' "$out" | tr -s ' ' | tail -c 400)"
done
exit 0
