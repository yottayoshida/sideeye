#!/bin/sh
# A copy of spike/dogfood/2026-10-14-mechanisms/apparatus/defines/alembic/check.sh (CANDIDATES.md 3.3),
# which also reports its legs. The recovery a user runs is `alembic upgrade head` again; its exit status is
# leg d. SQLite rolls back a hot journal on the first open, which that run makes.
set -u
S=${SIDEEYE_STATE_DIR:?}
export PYTHONDONTWRITEBYTECODE=1
legs() {
    python3 - "$S/app.db" <<'PY'
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1])
    vers = sorted(r[0] for r in c.execute("SELECT version_num FROM alembic_version"))
    a = "ok" if vers in (["r1"], ["r2"]) else "FAIL(alembic_version %s)" % vers
    cols = [(r[1], r[2].upper()) for r in c.execute("PRAGMA table_info(notes)")]
    shapes = {"r1": [("id", "INTEGER"), ("body", "TEXT")], "r2": [("id", "INTEGER"), ("text", "TEXT"), ("created", "INTEGER")]}
    b = "ok" if any(cols == shapes.get(v) for v in vers) else "FAIL(%s for %s)" % (cols, vers)
    label = "body" if ("body", "TEXT") in cols else "text"
    got = c.execute("SELECT id, %s FROM notes ORDER BY id" % label).fetchall()
    cc = "ok" if got == [(i, "note %d" % i) for i in range(1, 101)] else "FAIL(%d rows)" % len(got)
except Exception as e:
    a = b = cc = "FAIL(%s)" % type(e).__name__
print("a=%s b=%s c=%s" % (a, b, cc))
# The legs, for [controls]: from the values decided above, not read back off the printed line.
import os
if os.environ.get("SIDEEYE_LEGS"):
    with open(os.environ["SIDEEYE_LEGS"], "a") as f:
        for name, value in (("a", a), ("b", b), ("c", cc)):
            f.write("%s %s\n" % (name, "ok" if value == "ok" else "fail"))
PY
}
echo "checker(alembic) before recovery: $(ls -l "$S" | awk 'NR>1{printf "%s=%s ", $9, $5}')"
timeout 120 python3 -m alembic -c /s/al-aux/proj/alembic.ini upgrade head > /tmp/al-recovery.txt 2>&1
rc=$?
d=ok; [ "$rc" = 0 ] || d="FAIL(exit $rc: $(tail -1 /tmp/al-recovery.txt | head -c 120))"
after="$(legs) d=$d"; echo "checker(alembic) after recovery: $after"
if [ "$d" = ok ]; then echo "d ok"; else echo "d fail"; fi >> "${SIDEEYE_LEGS:-/dev/null}"
case "$after" in "a=ok b=ok c=ok d=ok") exit 0 ;; *) exit 1 ;; esac
