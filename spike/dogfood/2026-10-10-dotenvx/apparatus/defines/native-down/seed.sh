set -eu
rm -rf /s/kc && mkdir -p /s/kc/config && cd /s/kc
printf 'DB_PASSWORD=hunter2-not-a-real-secret\n' > .env
dotenvx encrypt -f .env > /s/seed-dotenvx.log 2>&1; test ! -e .env.keys; grep -q . keyring.json
