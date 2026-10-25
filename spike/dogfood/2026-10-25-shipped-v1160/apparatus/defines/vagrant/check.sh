#!/bin/sh
# After a crash anywhere inside `global-status --prune`, Vagrant itself still reads its machine index:
# `vagrant global-status` exits 0 rather than stopping on a corrupt index, which would stop every
# Vagrant command that touches the index, in every project on the machine.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(vagrant): $*"; exit 1; }
[ -f "$d/data/machine-index/index" ] || fail "the machine index is missing"
out=$(VAGRANT_HOME="$d" ruby /opt/vagrant-gems/bin/vagrant global-status 2>&1) || fail "vagrant global-status exited $?: $(echo "$out" | tr '\n' ' ' | cut -c1-240)"
exit 0
