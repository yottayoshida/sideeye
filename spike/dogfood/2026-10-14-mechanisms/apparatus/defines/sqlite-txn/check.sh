#!/bin/sh
# CANDIDATES.md 2.1. Opening the database is the recovery (a hot journal is rolled back), so what is
# printed before it is the files on disk, and the legs are read after it.
set -u
S=${SIDEEYE_STATE_DIR:?}; DB=$S/ledger.db
echo "checker(sqlite-txn) before recovery: $(ls -l "$S" | awk 'NR>1{printf "%s=%s ", $9, $5}')"
timeout 60 sqlite3 "$DB" "PRAGMA quick_check;" > /tmp/sq-recovery.txt 2>&1 || echo "checker(sqlite-txn) recovery exited $?: $(tail -c 200 /tmp/sq-recovery.txt)"
q() { timeout 60 sqlite3 "$DB" "$1" 2>/dev/null; }
a=ok; b=ok; c=ok
[ "$(q 'PRAGMA integrity_check;')" = ok ] || a=FAIL
[ "$(q 'SELECT sum(bal) FROM accounts;')" = 150 ] || b="FAIL(sum $(q 'SELECT sum(bal) FROM accounts;'))"
st="$(q "SELECT bal FROM accounts WHERE id = 'A';")/$(q 'SELECT count(*) FROM journal;')"
case "$st" in 100/0|70/1) : ;; *) c="FAIL(A/journal $st)" ;; esac
after="a=$a b=$b c=$c"; echo "checker(sqlite-txn) after recovery: $after"
case "$after" in "a=ok b=ok c=ok") exit 0 ;; *) exit 1 ;; esac
