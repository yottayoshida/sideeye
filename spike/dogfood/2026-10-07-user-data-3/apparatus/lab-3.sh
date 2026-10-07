#!/bin/sh
# Lab 3 (2026-10-07 user-data-3): the second screen's candidates by hand in the box, stdin at EOF.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-3.sh > transcripts/lab-3.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -12 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $f: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }

echo "=== tiddlywiki: save a single-file wiki over itself"
kind node
d=/s/tw; rm -rf $d; mkdir -p $d; cd $d
show tiddlywiki /s/tw/folder --init empty
show tiddlywiki /s/tw/folder --render '$:/core/save/all' wiki.html text/plain
ls -l /s/tw/folder/output 2>&1 | tail -n +2; cp /s/tw/folder/output/wiki.html /s/tw/wiki.html 2>/dev/null
mkdir -p /s/tw-out
b=$(digest $d); show tiddlywiki --load /s/tw/wiki.html --output /s/tw --render '$:/core/save/all' wiki.html text/plain; echo "  state: $b -> $(digest $d)"; ls -l $d | tail -n +2

echo "=== broot --install / --set-install-state"
kind broot
rm -rf $HOME/.config/broot $HOME/.local/share/broot; printf '# my bashrc\nalias ll=ls\n' > $HOME/.bashrc
b=$(digest $HOME); show broot --install; echo "  home: $b -> $(digest $HOME)"; tail -3 $HOME/.bashrc; ls -la $HOME/.config/broot 2>&1 | tail -n +2 | head; ls -la $HOME/.local/share/broot 2>&1 | tail -n +2 | head
b=$(digest $HOME); show broot --set-install-state refused; echo "  home: $b -> $(digest $HOME)"

echo "=== ziptool: edit an archive in place"
kind ziptool
d=/s/zip; rm -rf $d; mkdir -p $d/src; cd $d/src; for n in a b c; do head -c 4096 /dev/urandom > $n.bin; done; /opt/py/bin/python -I -c "import zipfile; z=zipfile.ZipFile('/s/zip/a.zip','w'); [z.write(n) for n in ('a.bin','b.bin','c.bin')]; z.close()"
cd $d; show ziptool a.zip delete 0; ls -l a.zip
b=$(digest $d); show ziptool a.zip rename 0 renamed.bin; echo "  state: $b -> $(digest $d)"
b=$(digest $d); show ziptool a.zip set_archive_comment hello; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== clipse -a"
kind clipse
rm -rf $HOME/.config/clipse
show clipse -a first-entry; ls -la $HOME/.config/clipse 2>&1 | tail -n +2
b=$(digest $HOME/.config/clipse); show clipse -a second-entry; echo "  state: $b -> $(digest $HOME/.config/clipse)"

echo "=== lnav: write a config value"
kind lnav
rm -rf $HOME/.config/lnav; show lnav -n -c ':config /ui/theme monocai' /dev/null; ls -la $HOME/.config/lnav 2>&1 | tail -n +2
b=$(digest $HOME/.config/lnav); show lnav -n -c ':config /ui/theme eldar' /dev/null; echo "  state: $b -> $(digest $HOME/.config/lnav)"; find $HOME/.config/lnav -name '*.json' | head -3

echo "=== prek install / uninstall"
kind prek
d=/s/prek; rm -rf $d; mkdir -p $d; cd $d; git init -q . ; printf 'repos: []\n' > .pre-commit-config.yaml
printf '#!/bin/sh\necho my own hook\n' > .git/hooks/pre-commit; chmod 755 .git/hooks/pre-commit
b=$(digest $d/.git/hooks); show prek install; echo "  hooks: $b -> $(digest $d/.git/hooks)"; ls -la .git/hooks | grep -v sample
b=$(digest $d/.git/hooks); show prek uninstall; echo "  hooks: $b -> $(digest $d/.git/hooks)"; ls -la .git/hooks | grep -v sample

echo "=== oh-my-fish: install offline, then switch theme"
kind fish
rm -rf $HOME/.local/share/omf $HOME/.config/omf $HOME/.config/fish
cd /opt/omf-src && show fish bin/install --offline --noninteractive --yes
ls -la $HOME/.config/omf 2>&1 | tail -n +2; cat $HOME/.config/omf/theme 2>/dev/null
b=$(digest $HOME/.config/omf); show fish -c 'omf theme default'; echo "  state: $b -> $(digest $HOME/.config/omf)"
show fish -c 'omf list'
