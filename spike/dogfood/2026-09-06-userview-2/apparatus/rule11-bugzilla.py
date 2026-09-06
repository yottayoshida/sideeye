"""rule 11 を Ghostscript Bugzilla で測る。

mupdf の tracker は GitHub ではない（repo は has_issues=false、README が
bugs.ghostscript.com を指す）。cohort4/novelty-prescan.sh も
rule11.py も GitHub API しか読まないので、この候補だけ別の装置が要る。
"""
import json
import subprocess
import datetime
import sys

BASE = "https://bugs.ghostscript.com/rest"


def get(path):
    r = subprocess.run(["curl", "-s", "--max-time", "60", BASE + path],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def parse(t):
    return datetime.datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ")


since = (datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=365)).strftime("%Y-%m-%d")
q = (f"/bug?product=MuPDF&f1=creation_time&o1=greaterthan&v1={since}"
     "&include_fields=id,summary,creation_time,status,creator&limit=40")
data = get(q)
if data is None:
    print("Bugzilla が読めない")
    sys.exit(1)

bugs = data.get("bugs", [])
bugs.sort(key=lambda b: b["creation_time"], reverse=True)
print(f"=== MuPDF: {since} 以降のバグ {len(bugs)} 件 ===")

shown = 0
for b in bugs:
    if shown >= 6:
        break
    cs = get(f"/bug/{b['id']}/comment")
    if cs is None:
        print(f"  {b['id']} コメントが読めない")
        shown += 1
        continue
    comments = cs["bugs"][str(b["id"])]["comments"]
    reporter = b.get("creator", "")
    others = [c for c in comments[1:] if c.get("creator") != reporter]
    if not others:
        print(f"  {b['id']} {b['creation_time'][:10]} [{b['status']}] "
              f"reply なし ({len(comments)} comments)  {b['summary'][:46]}")
    else:
        d = (parse(others[0]["creation_time"][:19] + "Z")
             - parse(b["creation_time"][:19] + "Z")).total_seconds() / 86400
        mark = "OK" if d <= 7 else "SLOW"
        print(f"  {b['id']} {b['creation_time'][:10]} [{b['status']}] "
              f"first reply after {d:.1f}d [{mark}]  {b['summary'][:46]}")
    shown += 1
