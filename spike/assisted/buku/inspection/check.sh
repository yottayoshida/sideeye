#!/bin/sh
# Instrumented copy of spike/assisted/buku/ops/check.sh for the Correction
# section of ../RUNLOG.md. The verdict legs are the committed checker's, in
# the committed order (db-exists, bystander query, anchored line,
# integrity_check); the only additions are read-only: a dump of the visited
# world (file list, sizes, first 16 bytes, journal presence) and a log of the
# query's raw answer, both appended to /inv/worlds.log, which lives outside
# the judged state root. Investigation harness only — never a committed
# checker.
set -u
export XDG_DATA_HOME=/tmp/assisted/buku/state
DB=$XDG_DATA_HOME/buku/bookmarks.db
DIR=$XDG_DATA_HOME/buku
TAB=$(printf '\t')
LOG=/inv/worlds.log

n=$(cat /inv/n 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > /inv/n

{
  echo "===== visit $n ====="
  ls -la "$DIR" 2>&1
  for f in "$DB" "$DB-journal"; do
    if [ -f "$f" ]; then
      printf '%s size=%s head16=' "${f##*/}" "$(stat -c %s "$f")"
      head -c 16 "$f" | od -An -tx1 | tr -s ' ' | tr -d '\n'
      # db change counter lives at offset 24..27; journal magic at 0..7
      printf ' bytes24-27='
      dd if="$f" bs=1 skip=24 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n'
      echo
    else
      echo "${f##*/} MISSING"
    fi
  done
} >> "$LOG" 2>&1

fail() { echo "checker(buku-add): $*"; echo "VERDICT visit $n: FAIL $*" >> "$LOG"; exit 1; }

[ -f "$DB" ] || fail "db is missing (the store existed before the operation)"

out=$(timeout 10 /usr/bin/buku --nostdin --np -s GraceMark -f 4 < /dev/null 2>&1)
rc=$?
{
  echo "query rc=$rc"
  printf '%s\n' "$out" | grep -v -e DeprecationWarning -e 'import cgi' | head -4
  echo "after-query dir: $(ls "$DIR" 2>/dev/null | tr '\n' ' ')"
} >> "$LOG" 2>&1

[ "$rc" -eq 0 ] || fail "bystander query exited $rc: $out"
matches=$(printf '%s\n' "$out" | grep -Fxc "1${TAB}https://example.com/g${TAB}GraceMark${TAB}grace")
[ "$matches" -eq 1 ] || fail "expected exactly one anchored bystander line, got $matches: $out"

ic=$(python3 -c "import sqlite3; print(sqlite3.connect('$DB').execute('PRAGMA integrity_check').fetchone()[0])" 2>&1)
[ "$ic" = "ok" ] || fail "integrity_check after the documented recovery-open: $ic"

echo "VERDICT visit $n: PASS" >> "$LOG"
exit 0
