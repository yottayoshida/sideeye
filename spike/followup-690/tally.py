#!/usr/bin/env python3
"""Count what spike/followup-690/run.sh measured, and name where runs part (#690).

usage: tally.py <results dir>               print the tally
       tally.py <results dir> --check <md>  exit 1 unless the block between
                                            `<!-- tally:begin -->` and `<!-- tally:end -->`
                                            in <md> is exactly what this prints

What the block holds is recomputed from the committed reports and decoded traces: each
run's verdict, refusal, crash points, how many worlds failed and the earliest failing crash
point with the operations around it; for the runs that part from the others, the first
record where they part. A hand-written count inside the block that the files do not support
is a red run. Sentences outside the block are checked by nothing here.

A decoded trace is `trace-ops --records` output: `<seq> <pid> <tid> <op> <path>` per line.
Process and thread ids differ from run to run, so before two traces are compared each id is
replaced by the order it first appeared in (p0, p1 / t0, t1). Records are named by their
`seq` — the trace's own number, the one crash points use; markers carry seq 0.
"""

import json
import os
import re
import sys
from collections import Counter

RUNS = {
    "tombi": [("explore", "ex", 20), ("replay", "rp", 40)],
    "mogrify": [("explore", "ex", 20), ("explore, date and time chunks left out", "nd", 10)],
    "isort": [("A", "A", 10), ("B", "B", 10)],
    "dotter": [("A", "A", 10), ("B", "B", 10)],
}

WRITES = {"open", "write", "truncate", "rename", "unlink", "mkdir", "rmdir", "link", "symlink", "fsync"}


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return None


def outcome(root, target, stem):
    """(verdict, reason, crash points, failed worlds, earliest failing crash point)."""
    d = None
    try:
        with open(os.path.join(root, target, stem + ".json")) as f:
            d = json.load(f)
    except (OSError, ValueError):
        pass
    txt = read(os.path.join(root, target, stem + ".txt")) or ""
    if d is None:
        return ("none", "-", "-", "-", "-")
    cp = re.search(r"crash points (\d+)", txt)
    worlds = re.search(r"^(?:FAIL|PASS)\s+(\d+ of \d+|\d+/\d+) explored worlds", txt, re.M)
    early = re.search(r"^earliest\s+crash point (\d+ of \d+)", txt, re.M)
    return (d.get("verdict") or "none", d.get("unknown_reason") or "-",
            cp.group(1) if cp else "-",
            worlds.group(1).replace(" of ", "/") if worlds else "-",
            early.group(1).replace(" of ", "/") if early else "-")


def around(root, target, stem):
    """The earliest failing world's `after` and `before` lines, file names only."""
    txt = read(os.path.join(root, target, stem + ".txt")) or ""
    a = re.search(r"^\s+after\s+(\w+)\(([^)]*)\)", txt, re.M)
    b = re.search(r"^\s+before\s+(\w+)\(([^)]*)\)", txt, re.M)
    f = lambda m: "%s(%s)" % (m.group(1), os.path.basename(m.group(2))) if m else "-"
    return "after %s before %s" % (f(a), f(b))


def records(path):
    """The decoded trace as (op, path, pid, tid, seq), ids normalised."""
    text = read(path)
    if text is None:
        return None
    pids, tids, out = {}, {}, []
    for ln in text.splitlines():
        parts = ln.split(" ", 4)
        if len(parts) < 4:
            continue
        seq, pid, tid, op = parts[:4]
        p = parts[4] if len(parts) > 4 else ""
        pids.setdefault(pid, "p%d" % len(pids))
        tids.setdefault(tid, "t%d" % len(tids))
        out.append((op, p, pids[pid], tids[tid], seq))
    return out


def first_divergence(a, b, key=lambda r: r[:4]):
    for i, (x, y) in enumerate(zip(a, b)):
        if key(x) != key(y):
            return i, x, y
    if len(a) != len(b):
        i = min(len(a), len(b))
        return i, (a[i] if i < len(a) else None), (b[i] if i < len(b) else None)
    return None


def fmt(rec):
    if rec is None:
        return "(end of trace)"
    op, p, pid, tid, seq = rec
    return "seq %s %s %s by %s/%s" % (seq, op, os.path.basename(p) or p, pid, tid)


def second_writer(recs):
    """The first write-class record by a thread other than the first one to write."""
    first = None
    for i, r in enumerate(recs):
        if r[0] not in WRITES:
            continue
        if first is None:
            first = r[3]
        elif r[3] != first:
            return i, r
    return None


def quoted_first_byte(q):
    """The first byte of a `quotedForReport` literal, given the text after its opening quote."""
    if q.startswith("\\x"):
        return int(q[2:4], 16)
    if q.startswith("\\\\") or q.startswith('\\"'):
        return ord(q[1])
    return q.encode()[0]


def tally(root):
    out = []
    for target, groups in RUNS.items():
        out.append("## %s" % target)
        for label, prefix, n in groups:
            seen = Counter(outcome(root, target, "%s%d" % (prefix, i)) for i in range(1, n + 1))
            parts = ["%d x %s %s cp=%s worlds=%s earliest=%s" % ((c,) + k) for k, c in sorted(seen.items(), key=lambda kv: -kv[1])]
            out.append("%s (%d runs): %s" % (label, n, "; ".join(parts)))
        if target == "tombi":
            for label, prefix, n in groups:
                judged = [j for j in range(1, n + 1) if outcome(root, target, "%s%d" % (prefix, j))[0] in ("PASS", "FAIL")]
                for i in range(1, n + 1):
                    if outcome(root, target, "%s%d" % (prefix, i))[1] != "multiple_threads_detected":
                        continue
                    work = os.path.join(root, target, "%s%d" % (prefix, i))
                    traces = sorted(f for f in os.listdir(work) if f.endswith(".bin.txt")) if os.path.isdir(work) else []
                    hit = None
                    for t in traces:
                        recs = records(os.path.join(work, t)) or []
                        hit = second_writer(recs)
                        if hit:
                            break
                    if not hit:
                        out.append("  %s %d refused: no decoded trace holds a second writing thread" % (label, i))
                        continue
                    out.append("  %s %d refused: %s %s is the second writing thread's first record" % (label, i, t[:-4], fmt(hit[1])))
                    parted = Counter()
                    for j in judged:
                        ref = records(os.path.join(root, target, "%s%d" % (prefix, j), t))
                        if ref is None:
                            parted["no such trace kept"] += 1
                            continue
                        d = first_divergence(ref, recs)
                        parted["identical" if d is None else "part at seq %s: judged %s, refused %s" % (d[1][4] if d[1] else "-", fmt(d[1]), fmt(d[2]))] += 1
                    for k, c in parted.items():
                        out.append("    against %d of %d judged %ss, same trace: %s" % (c, len(judged), label, k))
        if target == "mogrify":
            for i in range(1, 21):
                o = outcome(root, target, "ex%d" % i)
                if o[0] == "UNKNOWN":
                    m = re.search(r"the two runs' bytes ([^;]+)", read(os.path.join(root, target, "ex%d.txt" % i)) or "")
                    out.append("  explore %d refused %s: %s" % (i, o[1], m.group(1) if m else "(no byte clause)"))
            kinds, gaps = Counter(), Counter()
            for i in range(1, 11):
                body = read(os.path.join(root, target, "tw%d.txt" % i))
                if body is None:
                    kinds["missing"] += 1
                    continue
                kinds["split" if "not accepted" in body else "accepted" if "recording accepted" in body else "other"] += 1
                m = re.search(r"difference   img1\.png \(content differs\)\n\s+bytes first differ at byte offset (\d+)[^:]*: first run \"(.*?)\"…?, second run \"(.*)", body)
                if m:
                    gaps["img1.png from offset %s, first byte %+d" % (m.group(1), quoted_first_byte(m.group(3)) - quoted_first_byte(m.group(2)))] += 1
            out.append("twice (10 runs): %s" % ", ".join("%d %s" % (c, k) for k, c in sorted(kinds.items())))
            for k, c in sorted(gaps.items()):
                out.append("  twice: %d x %s" % (c, k))
        if target == "isort":
            seqs = {}
            for which in ("A", "B"):
                for i in range(1, 11):
                    rs = records(os.path.join(root, target, "%s%d" % (which, i), "trace-record.bin.txt"))
                    seqs["%s%d" % (which, i)] = None if rs is None else tuple((r[0], os.path.basename(r[1]), r[3]) for r in rs if r[0] in WRITES)
            first = seqs.get("A1")
            same = sum(1 for v in seqs.values() if v is not None and v == first)
            out.append("  write-class records of the recording, by file name: %d of %d runs identical to A1's" % (same, len(seqs)))
            if first:
                out.append("  A1: %s" % ", ".join("%s %s" % (op, p) for op, p, _t in first))
        if target == "dotter":
            for i in range(1, 11):
                o = outcome(root, target, "A%d" % i)
                if o[1] != "kill_did_not_land":
                    continue
                work = os.path.join(root, target, "A%d" % i)
                rec = records(os.path.join(work, "trace-record.bin.txt")) or []
                worlds = sorted((f for f in os.listdir(work) if re.match(r"trace-\d+\.bin\.txt$", f)),
                                key=lambda f: int(re.search(r"\d+", f).group()))
                last = worlds[-1] if worlds else None
                w = records(os.path.join(work, last)) if last else None
                d = first_divergence(rec, w) if w is not None else None
                ops = lambda rs: len([r for r in rs if r[0] in WRITES])
                out.append("  A %d kill_did_not_land: %d write-class records recorded, %d in %s; %s" % (
                    i, ops(rec), ops(w or []), last[:-4] if last else "(no world trace)",
                    "identical" if d is None else "first part: recording %s, world %s" % (fmt(d[1]), fmt(d[2]))))
            arounds = Counter(around(root, target, "B%d" % i) for i in range(1, 11) if outcome(root, target, "B%d" % i)[0] == "FAIL")
            for k, c in arounds.items():
                out.append("  B earliest failing world, %d runs: %s" % (c, k))
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) not in (2, 4) or (len(argv) == 4 and argv[2] != "--check"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    got = tally(argv[1])
    if len(argv) == 2:
        sys.stdout.write(got)
        return 0
    with open(argv[3]) as f:
        md = f.read()
    m = re.search(r"<!-- tally:begin -->\n```\n(.*?)```\n<!-- tally:end -->", md, re.S)
    if not m:
        print("tally: no tally block in %s" % argv[3], file=sys.stderr)
        return 1
    if m.group(1) != got:
        print("tally: the block in %s is not what the results say:\n%s" % (argv[3], got), file=sys.stderr)
        return 1
    print("ok   tally: the tally block in %s recomputes from %s" % (argv[3], argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
