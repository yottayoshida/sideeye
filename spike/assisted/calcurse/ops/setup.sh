#!/bin/sh
# Assisted run (#118), calcurse P1 setup. The config dir lives OUTSIDE the
# state root (ambient; its write-back determinism is unmeasured and the
# declared property is about the data files). expected/ is a reference copy
# inside the recorded pre-state.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
D=/tmp/assisted/calcurse/state/d
mkdir -p "$D" /tmp/assisted/calcurse/conf
calcurse -D "$D" -C /tmp/assisted/calcurse/conf -q -i "$here/in.ics" > /dev/null
cp -R "$D" /tmp/assisted/calcurse/state/expected
