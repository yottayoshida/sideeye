#!/bin/sh
#   docker run --rm -v <apparatus>:/d sideeye-ud1007 (trixie; apt over the network) sh -c "sh /d/debian-packages.sh < /d/debian-names.txt"
# Which trixie package (if any) ships each tool: by package name, then by the file that provides its command.
set -u
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-file >/dev/null 2>&1 && apt-file update >/dev/null 2>&1
while read name cmd; do
  pkgs=""
  for p in $name python3-$name; do apt-cache show "$p" >/dev/null 2>&1 && pkgs="$pkgs $p"; done
  byfile=$(apt-file search -x "/usr/(s?bin|games)/$cmd\$" 2>/dev/null | cut -d: -f1 | sort -u | tr '\n' ' ')
  echo "$name | by-name:${pkgs:- none} | ships /usr/bin/$cmd: ${byfile:-none}"
done
