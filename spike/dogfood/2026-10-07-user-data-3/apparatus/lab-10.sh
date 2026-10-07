#!/bin/sh
# Lab 10 (2026-10-07 user-data-3): what each FAIL leaves a user with. Each define is seeded, its file is put
# in the state the explore's earliest exhibit found (a zero-length file, plus pi's leftover lock directory),
# and the tool's ordinary next command is run: does it fail loudly, or carry on with the data gone?
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-10.sh > transcripts/lab-10.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' /tmp/show.out | tr -cd '\11\12\40-\176' | head -8 | cut -c1-170; echo "  -> exit $rc"; }
seed() { ( [ -f /ap/defines/$1/env.sh ] && . /ap/defines/$1/env.sh; sh /ap/defines/$1/seed.sh > /tmp/seed-$1.log 2>&1 ) || echo "  seed $1 failed"; }

echo "=== lxc: config.yml at zero bytes"
seed lxc; : > $HOME/.config/lxc/config.yml
show lxc alias list; show lxc remote list; echo "  config.yml now $(wc -c < $HOME/.config/lxc/config.yml) bytes"

echo "=== duplicacy: preferences at zero bytes"
seed duplicacy; : > /s/dup/repo/.duplicacy/preferences; cd /s/dup/repo
show duplicacy list; show duplicacy backup

echo "=== ferium: config.json at zero bytes"
seed ferium; : > $HOME/.config/ferium/config.json
show ferium profiles; echo "  config.json now $(wc -c < $HOME/.config/ferium/config.json) bytes"; show ferium profile create --name p9 --game-version 1.20.1 --mod-loader fabric --output-dir /s/ferium-in/p9; echo "  config.json now $(wc -c < $HOME/.config/ferium/config.json) bytes"; cat $HOME/.config/ferium/config.json | head -c 300; echo

echo "=== TiddlyWiki: wiki.html at zero bytes"
seed tiddlywiki; : > /s/tw/wiki.html
show tiddlywiki --load /s/tw/wiki.html --output /s/tw-in/out --render '$:/core/save/all' check.html text/plain; ls -l /s/tw-in/out 2>/dev/null | tail -n +2

echo "=== mcpm: servers.json at zero bytes"
seed mcpm; : > $HOME/.config/mcpm/servers.json
show mcpm ls; show mcpm new third --type stdio --command true --force; echo "  servers.json now $(wc -c < $HOME/.config/mcpm/servers.json) bytes"

echo "=== pi: settings.json at zero bytes and its lock directory left behind"
( . /ap/defines/pi/env.sh; seed pi; : > $HOME/.pi/agent/settings.json; mkdir -p $HOME/.pi/agent/settings.json.lock
  ls -la $HOME/.pi/agent | tail -n +2
  show timeout 30 pi install /s/pi-in/ext2; ls -la $HOME/.pi/agent | tail -n +2; cat $HOME/.pi/agent/settings.json | head -c 200; echo
  show timeout 30 pi list )

echo "=== doit: d.json at zero bytes"
seed doit; : > /s/doit/state/d.json; cd /s/doit
show doit run --backend json --db-file /s/doit/state/d.json; show doit list --backend json --db-file /s/doit/state/d.json

echo "=== astro: settings.json at zero bytes"
( . /ap/defines/astro/env.sh; seed astro; : > $HOME/.config/astro/settings.json
  show astro preferences list --global; show astro preferences disable devToolbar --global; cat $HOME/.config/astro/settings.json; echo )
