#!/bin/sh
# Assisted run (#118), buku P1 checker. Property (proposals.md P1): bookmarks
# you already had survive a crash during a new add, and the db stays a
# well-formed sqlite database.
#
# Leg order is deliberately query-FIRST here, unlike the blind campaigns:
# sqlite's documented contract is recovery-on-next-open (a hot journal is
# rolled back by the next opener). The bystander query below IS that
# documented next open, performed by buku itself; only after it does the
# file-level integrity check make a fair claim. A read-only integrity probe
# before recovery would fail worlds the contract explicitly permits.
set -u
export XDG_DATA_HOME=/tmp/assisted/buku/state
DB=$XDG_DATA_HOME/buku/bookmarks.db
TAB=$(printf '\t')

fail() { echo "checker(buku-add): $*"; exit 1; }

[ -f "$DB" ] || fail "db is missing (the store existed before the operation)"

out=$(timeout 10 /usr/bin/buku --nostdin --np -s GraceMark -f 4 < /dev/null 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "bystander query exited $rc: $out"
matches=$(printf '%s\n' "$out" | grep -Fxc "1${TAB}https://example.com/g${TAB}GraceMark${TAB}grace")
[ "$matches" -eq 1 ] || fail "expected exactly one anchored bystander line, got $matches: $out"

ic=$(python3 -c "import sqlite3; print(sqlite3.connect('$DB').execute('PRAGMA integrity_check').fetchone()[0])" 2>&1)
[ "$ic" = "ok" ] || fail "integrity_check after the documented recovery-open: $ic"

# DROPPED after two explorations (claim discipline): at the file level this
# checker cannot distinguish a hot journal (data at risk) from an
# invalid-header journal sqlite documents as cold and may leave behind — the
# journal legs were an undocumented hygiene claim, not the declared property.
# The declared property (P1 metadata) is conservation + a well-formed db,
# carried by the two legs above. Journal-file hygiene is recorded in RESULTS
# as an observation, not asserted.

exit 0
