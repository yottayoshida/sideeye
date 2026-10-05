#!/bin/sh
# Second pass on dokuwiki (the lab directory was never made), oh-my-posh (flag placement) and
# solvespace (the first test file linked another file that was not copied).
. /ap/env.sh
set -u
x() { echo "\$ $*"; timeout -k 2 90 "$@" </dev/null 2>&1 | tail -${TAILN:-8}; echo "rc=$?"; }
sum() { find "$1" -type f -exec sha256sum {} \; 2>/dev/null | cut -c1-12,65- | sort -k2; }
mkdir -p /lab
echo "##### dokuwiki"
cp -a /opt/dokuwiki /lab/dw
printf '====== Start ======\nOur household wiki.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php commit -m first /lab/page.txt wiki:start
printf '====== Start ======\nOur household wiki, edited.\n' > /lab/page.txt
x php /lab/dw/bin/dwpage.php commit -m second /lab/page.txt wiki:start
sum /lab/dw/data | grep -v -E '/cache/|/index/|_dummy|/media/|dont-panic|\.htaccess|/pages/wiki/'
echo "##### oh-my-posh"
mkdir -p /lab/omp
printf '%s\n' '{"$schema":"https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json","version":1,"blocks":[{"type":"prompt","alignment":"left","segments":[{"type":"path","style":"plain","foreground":"#ffffff","properties":{"prefix":"","style":"folder"}}]}]}' > /lab/omp/theme.omp.json
TAILN=14 x oh-my-posh config migrate --help
x oh-my-posh --config /lab/omp/theme.omp.json config migrate --write
sum /lab/omp; head -c 400 /lab/omp/theme.omp.json; echo
echo "##### solvespace"
mkdir -p /lab/ss
for f in $(find /tmp/src/solvespace/test -name '*.slvs' | head -40); do
  if ! grep -q 'Group.impFile' "$f"; then cp "$f" /lab/ss/part.slvs; echo "using $f"; break; fi
done
sum /lab/ss
x solvespace-cli regenerate /lab/ss/part.slvs
sum /lab/ss
