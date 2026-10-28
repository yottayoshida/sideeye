#!/usr/bin/env python3
"""Rule 11 per repository from rule11.sh's transcript: how many of the listed bug reports had a
first project reply (OWNER/MEMBER/COLLABORATOR/CONTRIBUTOR, not the author) within seven days.
The bar is 2026-09-28's precedent, which 2026-10-03 moved to midway: at least 3 of the last 10.
A report whose seven days have not yet run out and that has no reply counts as unanswered —
the conservative direction.

    python3 score11.py <rule11 transcript>
"""
import re, sys
from datetime import date

def d(s): return date.fromisoformat(s)

repo = None; rows = {}
for line in open(sys.argv[1]):
    m = re.match(r'== (\S+) \(label (.*)\)', line)
    if m: repo = m.group(1); rows[repo] = {"label": m.group(2), "n": 0, "fast": 0}; continue
    m = re.match(r'#\d+ (\d{4}-\d\d-\d\d) comments=\d+ first_project_reply=(.*)', line)
    if m and repo:
        r = rows[repo]; r["n"] += 1
        reply = re.search(r'(\d{4}-\d\d-\d\d)', m.group(2))
        if reply and (d(reply.group(1)) - d(m.group(1))).days <= 7: r["fast"] += 1
    if line.startswith('no issues returned') and repo: rows[repo]["n"] = -1
for repo, r in rows.items():
    verdict = "pass" if r["fast"] >= 3 else "FAIL"
    if r["n"] <= 0: verdict = "UNMEASURED"
    print(f'{repo:42} {r["fast"]}/{r["n"]:<3} {verdict:10} label={r["label"]}')
