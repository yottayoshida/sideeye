set -eu
rm -rf /s/lg && mkdir -p /s/lg/src /s/lg/locales/en /s/lg/locales/ja && cd /s/lg && ln -s /opt/lingui-proj/node_modules node_modules
printf '{"name":"site","private":true,"type":"module"}\n' > package.json
printf 'import { defineConfig } from "@lingui/cli";\nexport default defineConfig({ sourceLocale: "en", locales: ["en", "ja"], catalogs: [{ path: "<rootDir>/locales/{locale}/messages", include: ["src"] }] });\n' > lingui.config.js
printf 'import { t } from "@lingui/core/macro";\nexport const a = t`Welcome home`;\nexport const b = t`Your basket`;\n' > src/app.js
node /opt/lingui-proj/node_modules/@lingui/cli/dist/lingui.js extract > /s/lg-seed.log 2>&1
sed -i 's/^msgstr ""$/msgstr "XX"/; 1,3s/^msgstr "XX"$/msgstr ""/' locales/ja/messages.po
sed -i 's/msgid "Welcome home"/&/' locales/ja/messages.po
printf 'export const c = t`Checkout now`;\n' >> src/app.js
