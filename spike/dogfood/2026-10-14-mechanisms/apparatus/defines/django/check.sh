#!/bin/sh
# CANDIDATES.md 3.4. The recovery a user runs is `manage.py migrate` again; its exit status is leg d.
# SQLite rolls back a hot journal on the first open, which that run makes.
set -u
S=${SIDEEYE_STATE_DIR:?}
export PYTHONDONTWRITEBYTECODE=1
legs() {
    python3 - "$S/db.sqlite3" <<'PY'
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1])
    applied = sorted(r[0] for r in c.execute("SELECT name FROM django_migrations WHERE app = 'app'"))
    a = "ok" if applied in (["0001_initial"], ["0001_initial", "0002_change"]) else "FAIL(applied %s)" % applied
    cols = [(r[1], r[2].upper()) for r in c.execute("PRAGMA table_info(app_note)")]
    shapes = {1: [("id", "INTEGER"), ("body", "TEXT"), ("rank", "VARCHAR(10)")],
              2: [("id", "INTEGER"), ("text", "TEXT"), ("rank", "INTEGER")]}
    known = [n for n in applied if n in ("0001_initial", "0002_change")]
    b = "ok" if cols == shapes.get(len(known)) else "FAIL(%s for %s)" % (cols, known)
    label = "body" if ("body", "TEXT") in cols else "text"
    got = [(r[0], r[1], int(r[2])) for r in c.execute("SELECT id, %s, rank FROM app_note ORDER BY id" % label)]
    cc = "ok" if got == [(i, "note %d" % i, i) for i in range(1, 101)] else "FAIL(%d rows)" % len(got)
except Exception as e:
    a = b = cc = "FAIL(%s)" % type(e).__name__
print("a=%s b=%s c=%s" % (a, b, cc))
PY
}
echo "checker(django) before recovery: $(ls -l "$S" | awk 'NR>1{printf "%s=%s ", $9, $5}')"
timeout 120 python3 /s/dj-aux/proj/manage.py migrate app 0002 > /tmp/dj-recovery.txt 2>&1
rc=$?
d=ok; [ "$rc" = 0 ] || d="FAIL(exit $rc: $(tail -1 /tmp/dj-recovery.txt | head -c 120))"
after="$(legs) d=$d"; echo "checker(django) after recovery: $after"
case "$after" in "a=ok b=ok c=ok d=ok") exit 0 ;; *) exit 1 ;; esac
