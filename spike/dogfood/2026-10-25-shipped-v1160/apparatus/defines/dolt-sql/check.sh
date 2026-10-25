#!/bin/sh
# The history as the seed left it, and the working set either before the UPDATE or after all of it.
set -u
d=${SIDEEYE_STATE_DIR:?}
t=$(mktemp -d); cp -a "$d/." "$t/"; cd "$t"
rows=$(dolt sql -r csv -q "SELECT count(*), sum(status = 'shipped'), sum(cents) FROM orders" 2>&1 | tail -1)
log=$(dolt log --oneline 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}' | tr '\n' ' ')
cd /; rm -rf "$t"
case "$rows" in
  "1000,10,1.4985e+06"|"1000,510,1.4985e+06") ;;
  *) echo "checker(dolt-sql): rows = $rows (want 1000 rows, 10 or 510 shipped)"; exit 1 ;;
esac
[ "$log" = "ship seed Initialize " ] || { echo "checker(dolt-sql): log = $log (want ship seed Initialize)"; exit 1; }
