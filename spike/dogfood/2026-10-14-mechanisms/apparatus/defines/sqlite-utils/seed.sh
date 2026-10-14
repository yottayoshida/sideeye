set -eu
S=/s/su
rm -rf $S /s/su-aux && mkdir -p $S /s/su-aux
python3 - <<'PY'
import sqlite3
c = sqlite3.connect("/s/su/data.db")
c.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, qty TEXT, junk TEXT)")
c.executemany("INSERT INTO items VALUES (?, ?, ?, ?)", [(i, "item %d" % i, str(i * 7), "x" * 40) for i in range(1, 201)])
c.commit()
PY
install -m 755 /ap/defines/sqlite-utils/check.sh /s/su-aux/check.sh
