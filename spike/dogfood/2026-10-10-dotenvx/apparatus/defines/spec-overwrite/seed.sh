set -eu
rm -rf /s/proj && mkdir -p /s/proj && cd /s/proj
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env.example
dotenvx spec > /s/seed-dotenvx.log 2>&1
printf '# a rule of my own\n' >> Envfile
