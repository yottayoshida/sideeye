#!/bin/sh
# The versions and digests the pages quote. Host half: the two downloaded artifacts against the
# digests their releases publish. Container half (run with --container, inside
# Dockerfile.screen3's image, the two builds mounted as for the screens): every tool's own
# version line and both Sideeye builds'.
set -u
if [ "${1:-}" = --container ]; then
  /se140/sideeye version; /semain/bin/sideeye version
  bun --version; node --version; markdownlint --version; prettier --version; svgo --version; npm --version
  java -version 2>&1 | head -1
  java -XX:-UsePerfData -jar /opt/gjf/gjf.jar --version 2>&1 | head -1
  xz --version | head -1; zstd --version; lz4 --version 2>&1 | head -1; ninja --version; git --version
  uname -srm
  exit 0
fi
dir=$1
echo "sideeye-v1.4.0-aarch64-linux.tar.gz"
echo "  published: $(gh release view v1.4.0 -R yottayoshida/sideeye --json assets --jq '.assets[] | select(.name=="sideeye-v1.4.0-aarch64-linux.tar.gz") | .digest')"
echo "  local:     sha256:$(shasum -a 256 "$dir/sideeye-v1.4.0-aarch64-linux.tar.gz" | cut -d' ' -f1)"
echo "google-java-format-1.36.1-all-deps.jar"
echo "  published: $(gh release view v1.36.1 -R google/google-java-format --json assets --jq '.assets[] | select(.name=="google-java-format-1.36.1-all-deps.jar") | .digest')"
echo "  local:     sha256:$(shasum -a 256 "$dir/ctx3/google-java-format-1.36.1-all-deps.jar" | cut -d' ' -f1)"
echo "bun-linux-aarch64.zip (bun-v1.4.2)"
echo "  published: $(grep ' bun-linux-aarch64.zip$' "$dir/ctx/SHASUMS256.txt")"
echo "  local:     $(shasum -a 256 "$dir/ctx/bun-linux-aarch64.zip" | cut -d' ' -f1)"
echo "main d5911cd build: $(git -C "$(dirname "$0")" rev-parse d5911cd)"
