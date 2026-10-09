#!/usr/bin/env python3
"""Each explored target's verdict as the engine's own JSON states it, for RESULTS.md and the ledger rows:
the mode that decided it, explored/violating worlds, crash points, the earliest exhibit's two operations,
and the replays. Reads transcripts/explore/<t>/{explore,syscalls,supervised}.json — the last one run is
the one that decided (run.sh follows a refusal's next step at most once).

    python3 apparatus/verdicts.py [target ...]
"""
import json, sys
from pathlib import Path

E = Path(__file__).resolve().parent.parent / "transcripts" / "explore"


def one(t):
    d = E / t
    chosen = None
    for label in ("explore", "syscalls", "supervised"):
        p = d / f"{label}.json"
        if p.exists():
            chosen = (label, json.loads(p.read_text()))
    if not chosen:
        return f"{t}\t-\tno explore"
    label, j = chosen
    v = j.get("verdict")
    ex = j.get("explored"); viol = j.get("violations"); cps = j.get("crash_points")
    nviol = len(viol) if isinstance(viol, list) else viol
    e = j.get("earliest") or {}
    where = ""
    if e:
        where = f"cp {e.get('crash_point')}/{cps}: after {e['after']['op']} {Path(e['after']['path']).name}, before {e['before']['op']} {Path(e['before']['path']).name}; {e.get('subject')}"
    rep = (d / f"{label}.replay.txt")
    reps = " ".join(l.split(":")[1].split()[0] for l in rep.read_text().splitlines() if l.startswith("replay")) if rep.exists() else ""
    reason = j.get("unknown_reason") or ""
    return f"{t}\t{label}\t{v} {nviol}/{ex} {reason}\t{where}\treplays: {reps}"


for t in sys.argv[1:] or sorted(p.name for p in E.iterdir() if p.is_dir()):
    print(one(t))
