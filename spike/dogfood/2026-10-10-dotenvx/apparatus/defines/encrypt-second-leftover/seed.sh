set -eu
rm -rf /s/repo && git init -q /s/repo && cd /s/repo
git config user.email seed@example.invalid && git config user.name seed
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
printf 'PROD_DB_PASSWORD=prod-value-two-not-real\nPROD_FLAG=prod-value-three\n' > .env.production
printf '.env.keys\n.env.production\n' > .gitignore
dotenvx encrypt -f .env > /s/seed-dotenvx.log 2>&1
git add .env .gitignore && git commit -qm 'encrypted .env'
