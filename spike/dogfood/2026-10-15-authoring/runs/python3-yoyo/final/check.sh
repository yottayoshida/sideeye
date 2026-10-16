#!/bin/sh
# The checker for `yoyo apply` of 0002 and 0003 over app.db (INVARIANT.md has the contract).
# It runs recover.sh first (yoyo break-lock; SQLite rolls a hot journal back on that open),
# then judges four legs, all after the recovery:
#   a  record    yoyo's own `list` exits 0, names each of the three migrations once, and the
#                applied ones are 0001, 0001+0002 or all three
#   b  schema    the user tables are exactly {notes}, notes' columns and indexes are one of the
#                three shapes, and the one for the record when the record is one of the three
#   c  data      notes holds ids 1..100 with body 'note N'; where body_len exists, every row
#                has body_len = length(body)
#   d  next run  on a copy of the recovered state, the same `yoyo apply` exits 0 and yoyo's
#                `list` then shows all three applied
# A failed recovery is printed, not judged on its own: the legs read what it left.
set -u
S=${SIDEEYE_STATE_DIR:?}
D=$(cd "$(dirname "$0")" && pwd)
URL=sqlite:///app.db
export PYTHONDONTWRITEBYTECODE=1
cd "$S" || exit 1

echo "checker(yoyo) before recovery: $(ls -A "$S" | tr '\n' ' ')"
rout=$("$D/recover.sh" 2>&1); rrc=$?
[ "$rrc" = 0 ] || echo "checker(yoyo) recovery exited $rrc: $(printf '%s\n' "$rout" | tail -1 | head -c 200)"

# Leg a, through yoyo itself.
lout=$(timeout 60 python3 -m yoyo list --batch --database "$URL" migrations 2>&1); lrc=$?
rows=$(printf '%s\n' "$lout" | awk '$1=="A"||$1=="U"{print $1":"$2}' | sort -t: -k2 | tr '\n' ' ')
case "$lrc:$rows" in
    "0:A:0001-create-notes U:0002-add-body-len U:0003-index-body-len ") a=ok; rec=1 ;;
    "0:A:0001-create-notes A:0002-add-body-len U:0003-index-body-len ") a=ok; rec=2 ;;
    "0:A:0001-create-notes A:0002-add-body-len A:0003-index-body-len ") a=ok; rec=3 ;;
    *) a="FAIL(list exit $lrc: $rows$(printf '%s\n' "$lout" | tail -1 | head -c 120))"; rec=none ;;
esac

# Legs b and c, read straight from the database (yoyo has no reader for the user's tables).
bc=$(python3 -I - "$S/app.db" "$rec" <<'PY'
import sqlite3, sys
db, rec = sys.argv[1], sys.argv[2]
YOYO = {"yoyo_lock", "_yoyo_log", "_yoyo_version", "_yoyo_migration"}
COLS = [("id", "INTEGER", 0, 1), ("body", "TEXT", 1, 0)]
LEN = ("body_len", "INTEGER", 0, 0)
IDX = ("idx_notes_body_len", 0, ("body_len",))
SHAPES = {"1": (COLS, []), "2": (COLS + [LEN], []), "3": (COLS + [LEN], [IDX])}
try:
    c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
except Exception as e:
    print("a? b=FAIL(open %s) c=FAIL(open %s)" % (type(e).__name__, type(e).__name__)); sys.exit()
cols = None
try:
    tables = sorted(r[0] for r in c.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        if r[0] not in YOYO)
    cols = [(r[1], r[2].upper(), r[3], r[5]) for r in c.execute("PRAGMA table_info(notes)")]
    idx = []
    for r in c.execute("PRAGMA index_list(notes)"):
        on = tuple(x[2] for x in c.execute("PRAGMA index_info(%s)" % r[1]))
        idx.append((r[1], r[2], on))
    shape = (cols, sorted(idx))
    if tables != ["notes"]:
        b = "FAIL(tables %s)" % tables
    elif shape not in SHAPES.values():
        b = "FAIL(shape %s)" % (shape,)
    elif rec in SHAPES and shape != SHAPES[rec]:
        got = [k for k, v in SHAPES.items() if v == shape][0]
        b = "FAIL(schema of %s migrations, record of %s)" % (got, rec)
    else:
        b = "ok"
except Exception as e:
    b = "FAIL(%s: %s)" % (type(e).__name__, e)
try:
    got = c.execute("SELECT id, body FROM notes ORDER BY id").fetchall()
    if got != [(i, "note %d" % i) for i in range(1, 101)]:
        cc = "FAIL(%d rows, not ids 1..100 'note N')" % len(got)
    elif cols and any(x[0] == "body_len" for x in cols):
        bad = c.execute("SELECT count(*) FROM notes WHERE body_len IS NOT length(body)").fetchone()[0]
        cc = "ok" if bad == 0 else "FAIL(%d rows not backfilled)" % bad
    else:
        cc = "ok"
except Exception as e:
    cc = "FAIL(%s: %s)" % (type(e).__name__, e)
print("b=%s c=%s" % (b, cc))
PY
)

# Leg d, the next run, on a copy so legs a-c judge the state as the recovery left it.
T=$(mktemp -d /tmp/yoyo-check.XXXXXX)
cp -a "$S/." "$T/"
aout=$(cd "$T" && timeout 60 python3 -m yoyo apply --batch --database "$URL" migrations 2>&1); arc=$?
nout=$(cd "$T" && timeout 60 python3 -m yoyo list --batch --database "$URL" migrations 2>&1)
napplied=$(printf '%s\n' "$nout" | awk '$1=="A"{n++} END{print n+0}')
rm -rf "$T"
if [ "$arc" != 0 ]; then d="FAIL(next apply exit $arc: $(printf '%s\n' "$aout" | tail -1 | head -c 120))"
elif [ "$napplied" != 3 ]; then d="FAIL(next apply left $napplied of 3 applied)"
else d=ok; fi

after="a=$a $bc d=$d"
echo "checker(yoyo) after recovery: $after"
case "$after" in "a=ok b=ok c=ok d=ok") exit 0 ;; *) exit 1 ;; esac
