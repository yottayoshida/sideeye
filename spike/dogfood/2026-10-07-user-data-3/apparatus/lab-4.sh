#!/bin/sh
# Lab 4 (2026-10-07 user-data-3): TiddlyWiki with a real edit (lab 3 re-saved the same bytes) and
# lnav against an ordinary file (lab 3 gave it /dev/null, which it refuses).
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-4.sh > transcripts/lab-4.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -12 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }

echo "=== tiddlywiki: delete a tiddler from a single-file wiki and save it over itself"
d=/s/tw; rm -rf $d /s/tw-in; mkdir -p $d /s/tw-in; cd /s/tw-in
tiddlywiki /s/tw-in/folder --init empty > /dev/null 2>&1
mkdir -p /s/tw-in/folder/tiddlers; for n in Alpha Beta Gamma; do printf 'title: %s\n\nThe %s tiddler, written by hand.\n' $n $n > /s/tw-in/folder/tiddlers/$n.tid; done
tiddlywiki /s/tw-in/folder --output /s/tw --render '$:/core/save/all' wiki.html text/plain > /dev/null 2>&1; ls -l /s/tw
grep -c 'written by hand' /s/tw/wiki.html
b=$(digest $d); show tiddlywiki --load /s/tw/wiki.html --deletetiddlers '[[Beta]]' --output /s/tw --render '$:/core/save/all' wiki.html text/plain; echo "  state: $b -> $(digest $d)"; grep -c 'written by hand' /s/tw/wiki.html; ls -la /s/tw

echo "=== lnav: write a config value"
mkdir -p /s/lnav-in; printf '2026-10-07T00:00:00Z host app[1]: started\n' > /s/lnav-in/app.log
rm -rf $HOME/.config/lnav
show lnav -n -c ':config /ui/theme monocai' /s/lnav-in/app.log; find $HOME/.config/lnav -maxdepth 2 -type f | head -5
b=$(digest $HOME/.config/lnav); show lnav -n -c ':config /ui/theme eldar' /s/lnav-in/app.log; echo "  state: $b -> $(digest $HOME/.config/lnav)"
find $HOME/.config/lnav -maxdepth 1 -type f -name '*.json' -exec sh -c 'echo "== $1"; head -c 300 "$1"; echo' _ {} \;
