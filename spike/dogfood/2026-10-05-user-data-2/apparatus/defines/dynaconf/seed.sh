set -eu
rm -rf /s/dyn && mkdir -p /s/dyn
printf '[default]\nDB_HOST = "db.internal"\nDB_PASSWORD = "old-secret"\nAPI_TOKEN = "tok-aaaa"\n' > /s/dyn/.secrets.toml
printf '[default]\nNAME = "household"\n' > /s/dyn/settings.toml
