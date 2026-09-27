#!/bin/sh
# Copy the store run.sh made once (/tmp/gp-golden) into place: its configuration and age
# identity beside the judged root, and the store itself into the judged root the engine emptied.
set -eu
rm -rf /tmp/gp/.config /tmp/gp/.cache
mkdir -p /tmp/gp
cp -a /tmp/gp-golden/.config /tmp/gp/
cp -a /tmp/gp-golden/.local/share/gopass/stores/root/. /tmp/gp/.local/share/gopass/stores/root/
