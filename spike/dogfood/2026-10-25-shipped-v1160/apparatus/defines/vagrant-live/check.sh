#!/bin/sh
# After a crash anywhere inside `global-status --prune`, Vagrant still knows the machine that is alive:
# `vagrant global-status` exits 0 and lists the payments project's web machine. An empty index reads
# as "no machines" without an error, so the exit status alone cannot see the loss.
set -u
d=${SIDEEYE_STATE_DIR:?}
fail() { echo "checker(vagrant-live): $*"; exit 1; }
[ -f "$d/data/machine-index/index" ] || fail "the machine index is missing"
out=$(VAGRANT_HOME="$d" ruby /opt/vagrant-gems/bin/vagrant global-status 2>&1) || fail "vagrant global-status exited $?: $(echo "$out" | tr '\n' ' ' | cut -c1-240)"
printf '%s' "$out" | grep -q "/s/vagrantaux/payments" || fail "global-status no longer lists the live machine (payments/web): $(echo "$out" | tr '\n' ' ' | cut -c1-240)"
exit 0
