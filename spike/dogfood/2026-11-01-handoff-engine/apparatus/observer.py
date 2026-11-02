#!/usr/bin/env python3
"""The observer effect, outside the criteria: thread id changes between successive crash points of one
process in each recording, under the probe engine and under the shipped one.

  observer.py <out dir holding probe/ and plain/>

Reads runNN.records (`trace-ops --records`: <seq> <pid> <tid> <op> <path>). A crash point is a record
with seq > 0. The count is the same quantity the probe's `handover` lines count, read from the trace
instead, so the shipped engine can be counted too.
"""
import json, os, re, sys


def changes(text):
    last = {}
    n = 0
    for line in text.splitlines():
        parts = line.split(" ", 4)
        if len(parts) < 4 or not parts[0].isdigit() or int(parts[0]) == 0:
            continue
        pid, tid = parts[1], parts[2]
        if pid in last and last[pid] != tid:
            n += 1
        last[pid] = tid
    return n


def main():
    root = sys.argv[1]
    rows = {}
    for arm in ("probe", "plain"):
        base = os.path.join(root, arm)
        if not os.path.isdir(base):
            continue
        for t in sorted(os.listdir(base)):
            d = os.path.join(base, t)
            counts = [changes(open(os.path.join(d, f)).read()) for f in sorted(os.listdir(d)) if re.match(r"run\d\d\.records$", f)]
            rows.setdefault(t, {})[arm] = counts
    for t, r in rows.items():
        print(json.dumps({"target": t, **r}))


if __name__ == "__main__":
    main()
