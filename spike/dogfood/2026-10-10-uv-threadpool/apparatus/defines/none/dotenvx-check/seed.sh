set -eu
rm -rf /s/dotenvx && mkdir -p /s/dotenvx
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > /s/dotenvx/.env
