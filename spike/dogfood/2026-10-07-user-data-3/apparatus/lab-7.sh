#!/bin/sh
# Lab 7 (2026-10-07 user-data-3): the fourth screen's candidates, and three earlier ones given what they
# lacked (testdisk with fdisk and e2fsprogs, kitten themes with its archive cached, lasinfo on a file
# txt2las wrote). stdin at EOF.
#   docker run --rm --network none -v <apparatus>:/ap:ro sideeye-ud1007 sh /ap/lab-7.sh > transcripts/lab-7.txt 2>&1
set -u
. /ap/env.sh
show() { echo "\$ $*"; "$@" < /dev/null > /tmp/show.out 2>&1; rc=$?; head -10 /tmp/show.out | cut -c1-160; echo "  -> exit $rc"; }
digest() { (cd "$1" 2>/dev/null && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-12); }
kind() { f=$(command -v "$1" 2>/dev/null || echo "$1"); echo "  image: $f: $(file -L "$f" | sed 's/^[^:]*: //' | cut -c1-110)"; }

echo "=== pi install / remove a local extension"
( export PATH=/opt/node22/bin:$PATH; kind node
  mkdir -p /s/pi-in/ext1 /s/pi-in/ext2; printf '{"name":"ext1","version":"1.0.0","main":"index.js"}\n' > /s/pi-in/ext1/package.json; echo 'module.exports={}' > /s/pi-in/ext1/index.js
  printf '{"name":"ext2","version":"1.0.0","main":"index.js"}\n' > /s/pi-in/ext2/package.json; echo 'module.exports={}' > /s/pi-in/ext2/index.js
  show pi install /s/pi-in/ext1; find $HOME/.pi -type f 2>/dev/null | head -5
  b=$(digest $HOME/.pi); show pi install /s/pi-in/ext2; echo "  state: $b -> $(digest $HOME/.pi)"
  b=$(digest $HOME/.pi); show pi remove /s/pi-in/ext1; echo "  state: $b -> $(digest $HOME/.pi)"; cat $HOME/.pi/agent/settings.json 2>/dev/null | head -c 300; echo )

echo "=== cspell link add / remove"
( export PATH=/opt/node22/bin:$PATH
  mkdir -p /s/cspell-in; printf '{"version":"0.2","words":["sideeye"]}\n' > /s/cspell-in/a.json; printf '{"version":"0.2","words":["dogfood"]}\n' > /s/cspell-in/b.json
  show cspell link add /s/cspell-in/a.json; find $HOME/.config/cspell -type f 2>/dev/null
  b=$(digest $HOME/.config/cspell); show cspell link add /s/cspell-in/b.json; echo "  state: $b -> $(digest $HOME/.config/cspell)"
  b=$(digest $HOME/.config/cspell); show cspell link remove /s/cspell-in/a.json; echo "  state: $b -> $(digest $HOME/.config/cspell)" )

echo "=== ruler apply / revert"
kind node
d=/s/ruler; rm -rf $d; mkdir -p $d/.ruler; cd $d; git init -q .
printf '# My project rules\nAlways write tests.\n' > .ruler/instructions.md
printf '# hand-written CLAUDE.md\nkeep this\n' > CLAUDE.md
b=$(digest $d); show ruler apply --agents claude,codex; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2
b=$(digest $d); show ruler revert; echo "  state: $b -> $(digest $d)"; ls -la $d | tail -n +2

echo "=== doit forget / ignore with the json backend"
kind /opt/py/bin/python3
d=/s/doit; rm -rf $d; mkdir -p $d; cd $d
cat > dodo.py <<'PY'
def task_a():
    return {'actions': [lambda: True], 'file_dep': ['a.txt']}
def task_b():
    return {'actions': [lambda: True], 'file_dep': ['b.txt']}
PY
echo a > a.txt; echo b > b.txt
show doit run --backend json --db-file /s/doit/state/d.json 2>/dev/null; mkdir -p /s/doit/state; show doit run --backend json --db-file /s/doit/state/d.json
ls -la /s/doit/state | tail -n +2
b=$(digest /s/doit/state); show doit forget --backend json --db-file /s/doit/state/d.json a; echo "  state: $b -> $(digest /s/doit/state)"
b=$(digest /s/doit/state); show doit ignore --backend json --db-file /s/doit/state/d.json b; echo "  state: $b -> $(digest /s/doit/state)"

echo "=== thv config"
kind thv
show thv config usage-metrics disable; find $HOME/.config/toolhive -type f 2>/dev/null | head
b=$(digest $HOME/.config/toolhive); printf '{"servers":{}}\n' > /s/thv-reg.json; show thv config set-registry /s/thv-reg.json; echo "  state: $b -> $(digest $HOME/.config/toolhive)"

echo "=== kitten themes, offline on a cached archive"
kind kitten
mkdir -p $HOME/.config/kitty $XDG_CACHE_HOME/kitty; printf '# my kitty.conf\nfont_size 13.0\n' > $HOME/.config/kitty/kitty.conf
cp /opt/kitty-themes/kitty-themes.zip $XDG_CACHE_HOME/kitty/kitty-themes.zip
show kitten themes --help
b=$(digest $HOME/.config/kitty); show kitten themes --cache-age=-1 --reload-in=none Dracula; echo "  state: $b -> $(digest $HOME/.config/kitty)"; ls -la $HOME/.config/kitty | tail -n +2; tail -4 $HOME/.config/kitty/kitty.conf

echo "=== testdisk: find a lost partition and write it back"
d=/s/td; rm -rf $d /s/td-in; mkdir -p $d /s/td-in; cd /s/td-in
truncate -s 32M $d/disk.img; printf 'label: dos\nstart=2048, size=40960, type=83\n' | sfdisk -q $d/disk.img && echo "  partitioned"
dd if=/dev/zero of=/s/td-in/p.img bs=512 count=40960 2>/dev/null; mkfs.ext2 -q -F -L keepme /s/td-in/p.img && dd if=/s/td-in/p.img of=$d/disk.img bs=512 seek=2048 conv=notrunc 2>/dev/null && echo "  ext2 written"
sfdisk -d $d/disk.img | tail -1
dd if=/dev/zero of=$d/disk.img bs=1 seek=446 count=64 conv=notrunc 2>/dev/null && echo "  partition table zeroed"; sfdisk -d $d/disk.img 2>&1 | tail -1
b=$(sha256sum $d/disk.img | cut -c1-12); show testdisk /cmd /s/td/disk.img analyze,quicksearch,write; echo "  disk.img: $b -> $(sha256sum $d/disk.img | cut -c1-12)"; sfdisk -d $d/disk.img 2>&1 | tail -1; ls /s/td-in

echo "=== lasinfo on a file txt2las wrote"
d=/s/las; rm -rf $d /s/las-in; mkdir -p $d /s/las-in; cd /s/las-in
i=0; while [ $i -lt 20 ]; do echo "$((1000+i)).5 $((2000+i)).25 $((100+i)).75"; i=$((i+1)); done > pts.txt
show txt2las -i /s/las-in/pts.txt -o /s/las/a.las -parse xyz; ls -l $d | tail -n +2
b=$(digest $d); show lasinfo -i /s/las/a.las -set_file_source_ID 7; echo "  state: $b -> $(digest $d)"
b=$(digest $d); show lasinfo -i /s/las/a.las -set_system_identifier relabelled; echo "  state: $b -> $(digest $d)"; show lasinfo -i /s/las/a.las -nv -nmm
