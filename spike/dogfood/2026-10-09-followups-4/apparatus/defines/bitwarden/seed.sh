set -eu
rm -rf /s/bitwarden && mkdir -p /s/bitwarden/state
BITWARDENCLI_APPDATA_DIR=/s/bitwarden/state bw config server https://first.example.invalid > /dev/null 2>&1
