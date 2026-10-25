#!/bin/sh
# After a crash the world reads every player back, from the backend world.mt names, with the
# position, health and inventory the seed gave them. Read with the world's own two formats:
# the player files by their key = value head, players.sqlite with sqlite3.
exec python3 - "$SIDEEYE_STATE_DIR" <<'PY'
import os, re, sqlite3, sys
w = sys.argv[1]
want = {p: (10 + i, i * 7) for i, p in enumerate(["alice", "bob", "carol", "dave", "eve"], 1)}
mt = dict(l.split(" = ", 1) for l in open(os.path.join(w, "world.mt")).read().splitlines() if " = " in l)
be = mt.get("player_backend")
got = {}
try:
    if be == "files":
        d = os.path.join(w, "players")
        for n in (os.listdir(d) if os.path.isdir(d) else []):
            t = open(os.path.join(d, n)).read()
            if "PlayerArgsEnd" not in t or "EndInventory" not in t: continue
            hp = int(re.search(r"^hp = (\d+)", t, re.M).group(1))
            dirt = int(re.search(r"^Item basenodes:dirt (\d+)", t, re.M).group(1))
            got[re.search(r"^name = (\S+)", t, re.M).group(1)] = (hp, dirt)
    elif be == "sqlite3":
        db = sqlite3.connect("file:" + os.path.join(w, "players.sqlite") + "?mode=ro", uri=True)
        for name, hp in db.execute("select name, hp from player"):
            row = db.execute("select item from player_inventory_items where player=? and inv_id=0 and slot_id=0", (name,)).fetchone()
            got[name] = (hp, int(row[0].split()[1]) if row else -1)
except Exception as e:
    print(f"checker(luanti): the {be} backend does not read: {e}"); sys.exit(1)
missing = sorted(set(want) - set(got)); wrong = sorted(p for p in got if p in want and got[p] != want[p])
print(f"checker(luanti): world.mt says {be}; {len(got)} players read; missing {missing}; wrong {wrong}")
sys.exit(1 if missing or wrong else 0)
PY
