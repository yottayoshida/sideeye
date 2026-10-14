#!/bin/sh
# CANDIDATES.md 3.2. Opening the database is the recovery (a hot journal is rolled back).
set -u
S=${SIDEEYE_STATE_DIR:?}
echo "checker(sqlite-utils) before recovery: $(ls -l "$S" | awk 'NR>1{printf "%s=%s ", $9, $5}')"
timeout 60 sqlite3 "$S/data.db" "PRAGMA quick_check;" > /tmp/su-recovery.txt 2>&1 || echo "checker(sqlite-utils) recovery exited $?: $(tail -c 200 /tmp/su-recovery.txt)"
after=$(python3 - "$S/data.db" <<'PY'
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1])
    a = "ok" if c.execute("PRAGMA integrity_check").fetchone()[0] == "ok" else "FAIL"
    cols = [(r[1], r[2].upper()) for r in c.execute("PRAGMA table_info(items)")]
    old = [("id", "INTEGER"), ("name", "TEXT"), ("qty", "TEXT"), ("junk", "TEXT")]
    new = [("id", "INTEGER"), ("title", "TEXT"), ("qty", "INTEGER")]
    b = "ok" if cols in (old, new) else "FAIL(%s)" % cols
    label = "name" if ("name", "TEXT") in cols else "title"
    rows = c.execute("SELECT id, %s, qty FROM items ORDER BY id" % label).fetchall()
    want = [(i, "item %d" % i, i * 7) for i in range(1, 201)]
    got = [(r[0], r[1], int(r[2])) for r in rows]
    cc = "ok" if got == want else "FAIL(%d rows, %d differ)" % (len(got), sum(1 for x, y in zip(got, want) if x != y))
except Exception as e:
    a = b = cc = "FAIL(%s)" % type(e).__name__
print("a=%s b=%s c=%s" % (a, b, cc))
PY
)
echo "checker(sqlite-utils) after recovery: $after"
case "$after" in "a=ok b=ok c=ok") exit 0 ;; *) exit 1 ;; esac
