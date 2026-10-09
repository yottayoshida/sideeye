set -eu
rm -rf /s/repo && git init -q /s/repo && cd /s/repo
printf 'DB_PASSWORD=hunter2-not-a-real-secret\nAPI_TOKEN_PLACEHOLDER=plaintext-value-one\n' > .env
printf '.env.keys\n' > .gitignore
