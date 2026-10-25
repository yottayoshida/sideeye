#!/bin/sh
# After a crash the database opens, passes SQLite's integrity check, and still holds the listener's
# account and every play count, rating and star the seed gave the six tracks of the first two
# albums; the library holds those six tracks, and the new album's three or none of them.
exec python3 - "$SIDEEYE_STATE_DIR/navidrome.db" <<'PY'
import sqlite3, sys
try:
    db = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    ic = db.execute("pragma integrity_check").fetchone()[0]
    users = [r[0] for r in db.execute("select user_name from user")]
    ann = db.execute("select count(*), sum(play_count), sum(rating), sum(starred) from annotation a join media_file m on m.id = a.item_id where m.album in ('Northern Lights', 'Harbour')").fetchone()
    tracks = db.execute("select count(*) from media_file where missing = 0").fetchone()[0]
except Exception as e:
    print(f"checker(navidrome): the database does not read: {e}"); sys.exit(1)
print(f"checker(navidrome): integrity {ic}; users {users}; annotations {ann}; tracks {tracks}")
ok = ic == "ok" and users == ["admin"] and tuple(ann) == (6, 72, 18, 6) and tracks in (6, 9)
sys.exit(0 if ok else 1)
PY
