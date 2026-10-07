#!/bin/sh
# Lab 8 (2026-10-07 user-data-3): kitten themes with its cached archive carrying the JSON comment kitten
# reads its cache age from (tools/themes/collection.go, fetch_cached), and testdisk with `noconfirm`.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-8.sh > transcripts/lab-8.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' /tmp/show.out | tr -cd '\11\12\40-\176' | head -10 | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" 2>/dev/null && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }

echo "=== kitten themes, offline on a cached archive with its comment"
mkdir -p $HOME/.config/kitty $XDG_CACHE_HOME/kitty; printf '# my kitty.conf\nfont_size 13.0\n' > $HOME/.config/kitty/kitty.conf
cp /opt/kitty-themes/kitty-themes.zip $XDG_CACHE_HOME/kitty/kitty-themes.zip
/opt/py/bin/python -I -c "import zipfile; z=zipfile.ZipFile('$XDG_CACHE_HOME/kitty/kitty-themes.zip','a'); z.comment=b'{\"etag\":\"lab\",\"timestamp\":\"2026-10-07T00:00:00.000000000+00:00\"}'; z.close()"
b=$(digest $HOME/.config/kitty); show kitten themes --cache-age=-1 --reload-in=none Dracula; echo "  state: $b -> $(digest $HOME/.config/kitty)"; ls -la $HOME/.config/kitty | tail -n +2; tail -4 $HOME/.config/kitty/kitty.conf

echo "=== testdisk with noconfirm"
d=/s/td; rm -rf $d /s/td-in; mkdir -p $d /s/td-in; cd /s/td-in
truncate -s 32M $d/disk.img; printf 'label: dos\nstart=2048, size=40960, type=83\n' | sfdisk -q $d/disk.img
dd if=/dev/zero of=/s/td-in/p.img bs=512 count=40960 2>/dev/null; mkfs.ext2 -q -F -L keepme /s/td-in/p.img && dd if=/s/td-in/p.img of=$d/disk.img bs=512 seek=2048 conv=notrunc 2>/dev/null
dd if=/dev/zero of=$d/disk.img bs=1 seek=446 count=64 conv=notrunc 2>/dev/null
for cmd in analyze,quicksearch,noconfirm,write analyze,quicksearch,write,noconfirm; do
  b=$(sha256sum $d/disk.img | cut -c1-12); show testdisk /cmd /s/td/disk.img $cmd; echo "  disk.img: $b -> $(sha256sum $d/disk.img | cut -c1-12)"; sfdisk -d $d/disk.img 2>&1 | tail -1
done
