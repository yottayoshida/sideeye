set -eu
rm -rf /s/eslint && mkdir -p /s/eslint/proj && cd /s/eslint/proj
printf "export default [{ rules: { \"no-var\": \"error\", \"prefer-const\": \"error\" } }];\n" > eslint.config.mjs
printf "var a = 1;\nvar b = 2;\nconsole.log(a + b);\n" > a.js
