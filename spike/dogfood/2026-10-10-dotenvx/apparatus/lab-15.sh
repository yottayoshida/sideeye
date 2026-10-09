#!/bin/sh
# Where encrypt puts a new key when an OS secret store is there (the stand-in secret-tool): with and
# without -fk, and with --no-native / DOTENVX_NO_NATIVE. One after the other; no concurrency here.
export PATH=/ap/fake/native:/opt/dx-2.34.2/bin:/usr/local/bin:/usr/bin:/bin npm_config_update_notifier=false
for c in "encrypt -f apps/a/.env" "encrypt -fk .env.keys -f apps/a/.env" "encrypt --no-native -fk .env.keys -f apps/a/.env" "env DOTENVX_NO_NATIVE=true dotenvx encrypt -fk .env.keys -f apps/a/.env"; do
  d=/s/lab15/$(echo "$c" | tr -c 'a-z' _); mkdir -p $d/apps/a; cd $d; export HOME=$d/home FAKE_SECRET_STORE=$d/keyring.json DOTENVX_CONFIG=$d/config; mkdir -p $HOME
  printf 'A_SECRET=a\n' > apps/a/.env
  case "$c" in env*) $c > out.txt 2>&1;; *) dotenvx $c > out.txt 2>&1;; esac; rc=$?
  echo "## dotenvx $c: exit $rc; .env.keys: $(grep -c '^DOTENV_PRIVATE_KEY=.' .env.keys 2>/dev/null || echo none); keyring: $(grep -o 'public-key' keyring.json 2>/dev/null | wc -l) entr(ies); $(grep -v '^$' out.txt | head -2 | tr '\n' ' ' | cut -c1-120)"
done
