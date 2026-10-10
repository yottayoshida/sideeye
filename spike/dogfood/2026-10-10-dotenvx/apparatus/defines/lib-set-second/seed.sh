set -eu
rm -rf /s/dx && mkdir -p /s/dx && cd /s/dx
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
printf 'PROD_FLAG=prod-value-three\n' > .env.production
dotenvx encrypt -f .env > /s/seed-dotenvx.log 2>&1
