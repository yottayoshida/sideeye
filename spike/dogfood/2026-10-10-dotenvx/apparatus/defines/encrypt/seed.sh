set -eu
rm -rf /s/dx && mkdir -p /s/dx && cd /s/dx
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
