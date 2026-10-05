#!/bin/sh
# Plain runs: dynaconf's `write`, lingui's `extract`.
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 120 "$@" </dev/null 2>&1 | tail -${TAILN:-12}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab/dyn
printf '[default]\nDB_HOST = "db.internal"\nDB_PASSWORD = "old-secret"\nAPI_TOKEN = "tok-aaaa"\n' > /lab/dyn/.secrets.toml
printf '[default]\nNAME = "household"\n' > /lab/dyn/settings.toml
TAILN=25 x dynaconf write --help
cd /lab/dyn && x dynaconf write toml -s DB_PASSWORD=new-secret -p /lab/dyn/
sum /lab/dyn; cat /lab/dyn/.secrets.toml; cat /lab/dyn/settings.toml; cd /
ls -la /opt/lingui-proj/node_modules/.bin/lingui; readlink -f /opt/lingui-proj/node_modules/.bin/lingui
mkdir -p /lab/lg/src /lab/lg/locales/en /lab/lg/locales/ja && cd /lab/lg && ln -s /opt/lingui-proj/node_modules node_modules
printf '{"name":"site","private":true,"type":"module"}\n' > package.json
printf 'import { defineConfig } from "@lingui/cli";\nexport default defineConfig({ sourceLocale: "en", locales: ["en", "ja"], catalogs: [{ path: "<rootDir>/locales/{locale}/messages", include: ["src"] }] });\n' > lingui.config.js
printf 'import { t } from "@lingui/core/macro";\nexport const a = t`Welcome home`;\nexport const b = t`Your basket`;\n' > src/app.js
x node /opt/lingui-proj/node_modules/@lingui/cli/dist/lingui.js extract
sum /lab/lg/locales; cat /lab/lg/locales/ja/messages.po
sed -i 's/^msgstr ""$/msgstr "XX"/' locales/ja/messages.po
printf 'export const c = t`Checkout now`;\n' >> src/app.js
x node /opt/lingui-proj/node_modules/@lingui/cli/dist/lingui.js extract
sum /lab/lg/locales; cat /lab/lg/locales/ja/messages.po
