#!/usr/bin/env python3
"""Every tombi 1.5.6 run of 2026-10-02 under --observe supervised, read back from the engine's
own output files: the verdict line and, for a FAIL, where. One line per run, then the totals.

    python3 tombi-tally.py <the host directory the runs wrote into>

It expects the layout the host commands left: out-entry/entry/ (entry.sh), out-tombi/ (the pass
of five), out-tombi20/ (the pass of twenty), out/tombi-r1/ (the first run through run.sh) and
out-tombi-run1..10/tombi-r1/ (the ten later ones). `transcripts/tombi-repeat/all-runs.txt` is
its output. The replay totals are counted from the replay JSON, not from the summary lines.
"""
import collections, json, os, re, sys

X = sys.argv[1]


def head(p):
    t = open(p, errors="replace").read()
    m = re.search(r"^(PREFLIGHT\s+.*|FAIL\s+.*|PASS\s+.*|UNKNOWN\s+.*)$", t, re.M)
    e = re.search(r"earliest\s+crash point (\d+ of \d+)\n\s+after\s+(\w+)\([^)]*\)\n\s+before\s+(\w+)\(", t)
    out = m.group(1).strip() if m else "NO VERDICT LINE"
    if e:
        out += " | earliest %s, after %s before %s" % e.groups()
    return out


print("# Every tombi 1.5.6 run of 2026-10-02 under --observe supervised, read back from the engine's")
print("# own output files (apparatus/tombi-tally.py). One line per run, then the totals.")
print("\n## the gate's preflight --twice")
pf = [("entry.sh", X + "/out-entry/entry/tombi-r1.preflight.txt")]
pf += [("five-%d" % i, X + "/out-tombi/preflight%d.txt" % i) for i in range(1, 6)]
pf += [("twenty-%d" % i, X + "/out-tombi20/preflight%d.txt" % i) for i in range(1, 21)]
c = collections.Counter()
for n, p in pf:
    h = head(p)
    print(n + ": " + h)
    c[h] += 1
print("preflight totals: %d runs" % len(pf))
for k, v in c.most_common():
    print("  %d x %s" % (v, k))

print("\n## explore")
ex = [("run.sh-first", X + "/out/tombi-r1/supervised.txt")]
ex += [("run.sh-%d" % i, X + "/out-tombi-run%d/tombi-r1/supervised.txt" % i) for i in range(1, 11)]
ex += [("five-%d" % i, X + "/out-tombi/explore%d.txt" % i) for i in range(1, 6)]
ex += [("twenty-%d" % i, X + "/out-tombi20/explore%d.txt" % i) for i in range(1, 21)]
c = collections.Counter()
for n, p in ex:
    h = head(p)
    print(n + ": " + h[:150])
    c[re.sub(r"\s+", " ", h)[:40] if h.startswith("UNKNOWN") else h] += 1
print("explore totals: %d runs" % len(ex))
for k, v in c.most_common():
    print("  %d x %s" % (v, k[:150]))

print("\n## replays of the ten FAILs found through run.sh (two each)")
c = collections.Counter()
for i in range(1, 11):
    d = X + "/out-tombi-run%d/tombi-r1/" % i
    parts = []
    for r in (1, 2):
        j = json.load(open(d + "supervised.replay%d.json" % r))
        v = "%s %s" % (j.get("verdict"), j.get("unknown_reason") or "-")
        parts.append("replay %d: %s" % (r, v))
        c[v] += 1
    print("run.sh-%d: %s" % (i, " | ".join(parts)))
print("replay totals: %d runs" % sum(c.values()))
for k, v in c.most_common():
    print("  %d x %s" % (v, k))
