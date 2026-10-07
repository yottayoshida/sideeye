set -eu
rm -rf /s/tw /s/tw-in && mkdir -p /s/tw /s/tw-in
tiddlywiki /s/tw-in/folder --init empty > /s/tw-in/seed.log 2>&1
mkdir -p /s/tw-in/folder/tiddlers
for n in Alpha Beta Gamma; do printf 'title: %s\n\nThe %s tiddler, written by hand.\n' $n $n > /s/tw-in/folder/tiddlers/$n.tid; done
tiddlywiki /s/tw-in/folder --output /s/tw --render '$:/core/save/all' wiki.html text/plain >> /s/tw-in/seed.log 2>&1
test "$(grep -c 'written by hand' /s/tw/wiki.html)" = 3
