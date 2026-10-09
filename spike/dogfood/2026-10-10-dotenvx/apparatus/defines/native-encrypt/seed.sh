set -eu
rm -rf /s/kc && mkdir -p /s/kc/config && cd /s/kc
printf 'DB_PASSWORD=hunter2-not-a-real-secret\n' > .env

