#!/bin/sh
# Versions and digests the pages quote. Host half: the downloaded artifacts against their published
# digests (pyenv's source archive has none published; its sha256 and the tag's commit are recorded).
# Container half (--container, in Dockerfile's image with both builds mounted): each tool's version.
set -u
if [ "${1:-}" = --container ]; then
  /se140/sideeye version; /semain/bin/sideeye version
  aws --version; hatch --version; nvim --version | head -1; java -version 2>&1 | head -1
  java -jar /opt/jbang-0.141.0/bin/jbang.jar version 2>&1 | tail -1; node --version; bw --version 2>/dev/null | tail -1; pyenv --version
  uname -srm; exit 0
fi
dir=$1
echo "sideeye-v1.4.0-aarch64-linux.tar.gz"
echo "  published: $(gh release view v1.4.0 -R yottayoshida/sideeye --json assets --jq '.assets[] | select(.name=="sideeye-v1.4.0-aarch64-linux.tar.gz") | .digest')"
echo "  local:     sha256:$(shasum -a 256 "$dir/sideeye-v1.4.0-aarch64-linux.tar.gz" | cut -d' ' -f1)"
echo "jbang-0.141.0.zip"
echo "  published: $(gh release view v0.141.0 -R jbangdev/jbang --json assets --jq '.assets[] | select(.name=="jbang-0.141.0.zip") | .digest')"
echo "  local:     sha256:$(shasum -a 256 "$dir/ctx/jbang-0.141.0.zip" | cut -d' ' -f1)"
echo "pyenv-2.8.5.tar.gz (GitHub source archive, no published digest)"
echo "  local:     sha256:$(shasum -a 256 "$dir/ctx/pyenv-2.8.5.tar.gz" | cut -d' ' -f1); tag v2.8.5 -> $(gh api repos/pyenv/pyenv/git/ref/tags/v2.8.5 --jq .object.sha)"
echo "main build: 047592d, zig build -Doptimize=ReleaseSafe -Dtarget=aarch64-linux-gnu.2.28"
