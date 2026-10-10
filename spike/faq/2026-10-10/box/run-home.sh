#!/bin/sh
set -u
cp -r /box/xdg /tmp/xdg; cd /tmp/xdg
cat > home.toml <<'T'
[world]
state = "/tmp/xdgtool-state"

[define]
cwd       = "."
setup     = "python3 xdgtool.py init"
operation = "python3 xdgtool.py bump"
apparatus = ["env:HOME=/tmp/xdgtool-state/home"]
T
env -u XDG_CONFIG_HOME -u XDG_DATA_HOME HOME=/tmp/xdgtool-state/home \
  sideeye explore --config home.toml --oracle /usr/bin/strace --work /tmp/w5 > /out/home.txt 2>&1; echo "RESULT home rc=$?"
