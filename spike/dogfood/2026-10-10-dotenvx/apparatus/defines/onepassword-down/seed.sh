set -eu
rm -rf /s/kc && mkdir -p /s/kc/config && cd /s/kc
printf 'DB_PASSWORD=hunter2-not-a-real-secret\n' > .env
dotenvx encrypt -f .env > /s/seed-dotenvx.log 2>&1; dotenvx 1password up -f .env >> /s/seed-dotenvx.log 2>&1; ! grep -q "^DOTENV_PRIVATE_KEY=." .env.keys 2>/dev/null; grep -q password op.json
