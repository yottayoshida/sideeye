#!/bin/sh
# The table and the history both as the seed left them: a gc changes neither.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"; cd "$t"
rows=$(dolt sql -r csv -q "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" 2>&1 | tail -1)
log=$(dolt log --oneline 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}' | tr '\n' ' ')
cd /; rm -rf "$t"
[ "$rows" = "1000,10,1.4985e+06" ] || { echo "checker(dolt): rows = $rows (want 1000,10,1.4985e+06)"; exit 1; }
[ "$log" = "ship seed Initialize " ] || { echo "checker(dolt): log = $log (want ship seed Initialize)"; exit 1; }
