#!/bin/sh
# preflight --twice of one define in a named observation mode, inside a set's box — to ask whether a
# mode moves a wall before an explore is spent on it.
#   sh /ap/pf-mode.sh <define> <mode>
set -u
t=$1; mode=$2; d=/ap/defines/$t
. /ap/env.sh; [ -f $d/env.sh ] && . $d/env.sh
sh $d/seed.sh > /tmp/seed.log 2>&1 || { echo "seed failed"; exit 2; }
set --
while IFS= read -r l; do set -- "$@" "$l"; done <<X
$(python3 /ap/toml2flags.py $d/sideeye.toml)
X
"$(cat /install.path)" preflight "$@" --twice --oracle /usr/bin/strace --observe "$mode" 2>&1 | grep -v '^20[0-9][0-9]/'
