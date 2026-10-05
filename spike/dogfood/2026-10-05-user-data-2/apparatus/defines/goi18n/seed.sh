set -eu
rm -rf /s/gi && mkdir -p /s/gi && cd /s/gi
printf '[Greeting]\nother = "Hello"\n\n[Farewell]\nother = "Goodbye"\n\n[Cart]\nother = "Cart"\n' > active.en.toml
printf '[Greeting]\nhash = "sha1-f7ff9e8b7bb2e09b70935a5d785e0cc5d9d0abf0"\nother = "こんにちは"\n' > active.ja.toml
goi18n merge active.en.toml active.ja.toml
sed -i 's/other = "Goodbye"/other = "さようなら"/; s/other = "Cart"/other = "カート"/' translate.ja.toml
grep -q さようなら translate.ja.toml
