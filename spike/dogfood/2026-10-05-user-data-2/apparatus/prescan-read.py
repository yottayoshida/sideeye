#!/usr/bin/env python3
"""A reading aid for rule 14, not a verdict: each pre-scan transcript's distinct issues, and among them
the titles that name a write shape (an interrupted, truncated, emptied or non-atomic write of a file).
The veto is still a reading of these titles against the operation's own write (SCOUT-BRIEF rule 14).

    python3 prescan-read.py <transcript> [...]
"""
import re, sys
SHAPE = re.compile(r'(?i)atomic|truncat|\bempty\b|emptied|zero[- ]byte|0[- ]byte|\blost\b|\bloss\b|corrupt|disk.?full|enospc|'
                   r'power|crash(?:es|ed)? (?:during|while)|partial|wipe|wiping|erase|erasing|blank|half|overwrit|clobber|'
                   r'interrupt|killed|sigkill|unclean|data.?loss|destroy|fsync|rename|temp(?:orary)? file')
for path in sys.argv[1:]:
    seen = {}
    controls = [l.strip() for l in open(path) if l.lstrip().startswith(('positive', 'negative'))]
    for line in open(path):
        m = re.match(r'\s+#(\d+) (\w+) (\S+) (.*)', line)
        if m: seen[m.group(1)] = (m.group(2), m.group(3), m.group(4).strip())
    hits = {k: v for k, v in seen.items() if SHAPE.search(v[2])}
    print(f"== {path.split('/')[-1]}: {len(seen)} distinct issues listed, {len(hits)} with a write-shape word; controls: {' | '.join(controls)}")
    for k, (st, d, t) in sorted(hits.items(), key=lambda x: -int(x[0])):
        print(f"   #{k} {st} {d} {t[:130]}")
